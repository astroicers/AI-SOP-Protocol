#!/usr/bin/env bash
# inbox-ingest.sh — 將 .asp-task-inbox.json 的 pending 任務注入 ROADMAP.yaml
#
# 使用時機：session-audit.sh 在 SessionStart 時自動呼叫
# 手動執行：bash .asp/scripts/inbox-ingest.sh
#
# 規則：
#   1. 只處理 status: pending 的 inbox 任務
#   2. 相同 source.ref 的任務不重複注入（去重）
#   3. 注入後將 inbox 任務 status 改為 ingested
#   4. 無 ROADMAP.yaml 時輸出 WARNING 並跳過（不阻擋 session）
#   5. 依 sla_hours 排序：0 → critical，24 → high，72 → medium，其餘 → low

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
INBOX_FILE="${PROJECT_DIR}/.asp-task-inbox.json"
ROADMAP_FILE="${PROJECT_DIR}/ROADMAP.yaml"
LOG_PREFIX="📥 ASP Inbox"

command -v jq &>/dev/null || { echo "${LOG_PREFIX}: jq 未安裝，跳過 inbox 注入" >&2; exit 0; }
command -v python3 &>/dev/null || { echo "${LOG_PREFIX}: python3 未安裝，跳過 inbox 注入" >&2; exit 0; }

# inbox 不存在 → 靜默退出（正常情況）
[ -f "$INBOX_FILE" ] || exit 0

# inbox 空陣列 → 靜默退出
PENDING_COUNT=$(jq '[.[] | select(.status == "pending")] | length' "$INBOX_FILE" 2>/dev/null || echo 0)
[ "$PENDING_COUNT" -gt 0 ] || exit 0

# ROADMAP 不存在 → 警告但不阻擋
if [ ! -f "$ROADMAP_FILE" ]; then
    echo "${LOG_PREFIX}: ⚠️  發現 ${PENDING_COUNT} 個 inbox 任務，但 ROADMAP.yaml 不存在 → 執行 make autopilot-init 建立後重啟 session" >&2
    exit 0
fi

echo "${LOG_PREFIX}: 發現 ${PENDING_COUNT} 個待注入任務..." >&2

# ── 讀取 ROADMAP 中已有的 source.ref（去重用）──
EXISTING_REFS=$(python3 -c "
import sys, re

try:
    with open('${ROADMAP_FILE}', 'r') as f:
        content = f.read()
    refs = re.findall(r'source_ref:\s*[\"\'](.*?)[\"\']\s', content)
    print('\n'.join(refs))
except Exception:
    pass
" 2>/dev/null || true)

INJECTED=0
SKIPPED=0
ERRORS=0

# ── 逐一處理 pending 任務 ──
while IFS= read -r task_json; do
    TASK_ID=$(echo "$task_json" | jq -r '.id // "INBOX-?"')
    TITLE=$(echo "$task_json" | jq -r '.title // "Untitled"')
    TYPE=$(echo "$task_json" | jq -r '.type // "GENERAL"')
    SLA=$(echo "$task_json" | jq -r '.sla_hours // 72')
    SOURCE_TYPE=$(echo "$task_json" | jq -r '.source.type // "manual"')
    SOURCE_REF=$(echo "$task_json" | jq -r '.source.ref // ""')
    TRIGGERED_BY=$(echo "$task_json" | jq -r '.triggered_by // "manual"')
    DESCRIPTION=$(echo "$task_json" | jq -r '.description // ""')
    IMPORTED_AT=$(echo "$task_json" | jq -r '.source.imported_at // ""')

    # 去重：source.ref 已存在於 ROADMAP → 跳過
    if [ -n "$SOURCE_REF" ] && echo "$EXISTING_REFS" | grep -qF "$SOURCE_REF"; then
        echo "${LOG_PREFIX}: ⏭️  ${TASK_ID} 已存在（source.ref 重複），跳過" >&2
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # sla_hours → priority
    if [ "$SLA" -eq 0 ] 2>/dev/null; then
        PRIORITY=0
    elif [ "$SLA" -le 24 ] 2>/dev/null; then
        PRIORITY=1
    elif [ "$SLA" -le 72 ] 2>/dev/null; then
        PRIORITY=2
    else
        PRIORITY=3
    fi

    # 產生注入的 YAML 區塊
    YAML_BLOCK="      - id: ${TASK_ID}
        title: \"${TITLE}\"
        type: ${TYPE}
        priority: ${PRIORITY}
        adr: null
        spec: null
        depends_on: []
        status: pending
        estimated_complexity: medium
        source_type: ${SOURCE_TYPE}
        source_ref: \"${SOURCE_REF}\"
        triggered_by: ${TRIGGERED_BY}
        sla_hours: ${SLA}
        imported_at: \"${IMPORTED_AT}\"
        description: |
          ${DESCRIPTION}
          [自動注入自 inbox / ${SOURCE_TYPE} / ${TRIGGERED_BY}]"

    # 將 YAML 區塊追加到第一個 milestone 的 tasks: 區塊之後
    python3 - <<PYEOF
import sys, re

with open('${ROADMAP_FILE}', 'r') as f:
    content = f.read()

block = """${YAML_BLOCK}"""

# 找到第一個 tasks: 後的位置插入
pattern = r'(    tasks:\n)'
replacement = r'\1' + block + '\n'
new_content, count = re.subn(pattern, replacement, content, count=1)

if count == 0:
    sys.exit(1)

with open('${ROADMAP_FILE}', 'w') as f:
    f.write(new_content)

sys.exit(0)
PYEOF

    if [ $? -eq 0 ]; then
        echo "${LOG_PREFIX}: ✅ 注入 ${TASK_ID}「${TITLE}」(${TYPE}, sla=${SLA}h, from=${SOURCE_TYPE})" >&2
        INJECTED=$((INJECTED + 1))
        # 追蹤已注入的 ref
        EXISTING_REFS="${EXISTING_REFS}
${SOURCE_REF}"
    else
        echo "${LOG_PREFIX}: ❌ ${TASK_ID} 注入失敗（ROADMAP tasks 區塊未找到）" >&2
        ERRORS=$((ERRORS + 1))
    fi

done < <(jq -c '.[] | select(.status == "pending")' "$INBOX_FILE" 2>/dev/null)

# ── 將已注入的任務標為 ingested ──
if [ "$INJECTED" -gt 0 ]; then
    UPDATED=$(jq '
        map(
            if .status == "pending" then .status = "ingested" | .ingested_at = (now | todate)
            else . end
        )
    ' "$INBOX_FILE" 2>/dev/null)

    if [ -n "$UPDATED" ]; then
        echo "$UPDATED" > "$INBOX_FILE"
    fi
fi

# ── 摘要輸出 ──
echo "${LOG_PREFIX}: 完成 — 注入 ${INJECTED}，略過 ${SKIPPED}，失敗 ${ERRORS}" >&2

[ "$ERRORS" -eq 0 ] && exit 0 || exit 1
