#!/usr/bin/env bash
# inbox-triage.sh — 人類 triage held 外部任務（SPEC-009 / ADR-012 DP2/DP4）
#
# 使用：make inbox-triage                  互動逐件核准/駁回
#       bash .asp/scripts/inbox-triage.sh --approve <ID>   核准單筆
#       bash .asp/scripts/inbox-triage.sh --reject  <ID>   駁回單筆
#
# 設計（ADR-012 DP4）：
#   本工具只「寫入」，不 git commit——核准的授權記號是**人類自己的 commit**。
#   autopilot 閘會以 `git log -S` 驗證 ROADMAP entry 的引入 commit 作者非 bot。
#
# 行為：
#   approve → 任務寫入 ROADMAP（帶 triage_accepted_by/at + provenance 標記），
#             inbox 該筆 pending → triaged；提示人類 git commit。
#   reject  → inbox 該筆 pending → rejected；不碰 ROADMAP。
#   去重：ROADMAP 已含相同 source_ref → 拒絕重複寫入。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
INBOX_FILE="${PROJECT_DIR}/.asp-task-inbox.json"
ROADMAP_FILE="${PROJECT_DIR}/ROADMAP.yaml"
LOG_PREFIX="🧑‍⚖️ ASP Triage"

command -v jq &>/dev/null || { echo "${LOG_PREFIX}: 需要 jq" >&2; exit 1; }
command -v python3 &>/dev/null || { echo "${LOG_PREFIX}: 需要 python3" >&2; exit 1; }

[ -f "$INBOX_FILE" ] || { echo "${LOG_PREFIX}: 無 inbox（${INBOX_FILE}），無事可做" >&2; exit 0; }

PENDING_COUNT=$(jq '[.[] | select(.status == "pending")] | length' "$INBOX_FILE" 2>/dev/null || echo 0)
if [ "$PENDING_COUNT" -eq 0 ]; then
    echo "${LOG_PREFIX}: 無 held（pending）任務" >&2
    exit 0
fi

set_inbox_status() {  # $1=task_id $2=new_status
    local updated
    updated=$(jq --arg id "$1" --arg st "$2" '
        map(if .id == $id and .status == "pending"
            then .status = $st | .triaged_at = (now | todate)
            else . end)' "$INBOX_FILE") || return 1
    echo "$updated" > "$INBOX_FILE"
}

approve_task() {  # $1=task_id  → 0 ok / 1 error
    local task_id="$1" task_json
    task_json=$(jq -c --arg id "$task_id" '.[] | select(.id == $id and .status == "pending")' "$INBOX_FILE")
    if [ -z "$task_json" ]; then
        echo "${LOG_PREFIX}: ❌ 找不到 pending 任務 ${task_id}" >&2
        return 1
    fi
    if [ ! -f "$ROADMAP_FILE" ]; then
        echo "${LOG_PREFIX}: ❌ ROADMAP.yaml 不存在——先執行 make autopilot-init 再 triage" >&2
        return 1
    fi

    local title type sla source_type source_ref triggered_by description imported_at
    title=$(echo "$task_json" | jq -r '.title // "Untitled"')
    type=$(echo "$task_json" | jq -r '.type // "GENERAL"')
    sla=$(echo "$task_json" | jq -r '.sla_hours // 72')
    source_type=$(echo "$task_json" | jq -r '.source.type // "manual"')
    source_ref=$(echo "$task_json" | jq -r '.source.ref // ""')
    triggered_by=$(echo "$task_json" | jq -r '.triggered_by // "customer"')
    description=$(echo "$task_json" | jq -r '.description // ""')
    imported_at=$(echo "$task_json" | jq -r '.source.imported_at // ""')

    # 去重：相同 source_ref 已在 ROADMAP → 拒絕
    if [ -n "$source_ref" ] && grep -qF "$source_ref" "$ROADMAP_FILE"; then
        echo "${LOG_PREFIX}: ⏭️  ${task_id} 的 source_ref 已存在於 ROADMAP，拒絕重複核准" >&2
        return 1
    fi

    # sla_hours → priority（沿用原映射）
    local priority=3
    if [ "$sla" -eq 0 ] 2>/dev/null; then priority=0
    elif [ "$sla" -le 24 ] 2>/dev/null; then priority=1
    elif [ "$sla" -le 72 ] 2>/dev/null; then priority=2; fi

    local accepted_by accepted_at
    accepted_by=$(git config user.name 2>/dev/null || echo "unknown-human")
    accepted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local yaml_block
    yaml_block="      - id: ${task_id}
        title: \"${title}\"
        type: ${type}
        priority: ${priority}
        adr: null
        spec: null
        depends_on: []
        status: pending
        estimated_complexity: medium
        source_type: ${source_type}
        source_ref: \"${source_ref}\"
        triggered_by: ${triggered_by}
        sla_hours: ${sla}
        imported_at: \"${imported_at}\"
        triage_accepted_by: \"${accepted_by}\"
        triage_accepted_at: \"${accepted_at}\"
        description: |
          ${description}
          [人類 triage 核准 / ${source_type} / SPEC-009]"

    YAML_BLOCK="$yaml_block" ROADMAP_PATH="$ROADMAP_FILE" python3 - <<'PYEOF'
import os, re, sys

path = os.environ["ROADMAP_PATH"]
block = os.environ["YAML_BLOCK"]
with open(path, "r") as f:
    content = f.read()

new_content, count = re.subn(r"(    tasks:\n)", r"\1" + block + "\n", content, count=1)
if count == 0:
    sys.exit(1)
with open(path, "w") as f:
    f.write(new_content)
PYEOF
    if [ $? -ne 0 ]; then
        echo "${LOG_PREFIX}: ❌ ${task_id} 寫入失敗（ROADMAP tasks 區塊未找到）" >&2
        return 1
    fi

    set_inbox_status "$task_id" "triaged" || return 1
    echo "${LOG_PREFIX}: ✅ 已核准 ${task_id}「${title}」→ ROADMAP（triage_accepted_by: ${accepted_by}）" >&2
    echo "${LOG_PREFIX}: 👉 請以**你本人**身分 git commit 此變更——你的 commit 即授權記號（DP4），bot 引入會被 autopilot 閘拒絕" >&2
    return 0
}

reject_task() {  # $1=task_id
    local task_id="$1" exists
    exists=$(jq --arg id "$task_id" '[.[] | select(.id == $id and .status == "pending")] | length' "$INBOX_FILE")
    if [ "$exists" -eq 0 ]; then
        echo "${LOG_PREFIX}: ❌ 找不到 pending 任務 ${task_id}" >&2
        return 1
    fi
    set_inbox_status "$task_id" "rejected" || return 1
    echo "${LOG_PREFIX}: 🚫 已駁回 ${task_id}" >&2
    return 0
}

# ── CLI 旗標模式 ──
case "${1:-}" in
    --approve)
        [ -n "${2:-}" ] || { echo "${LOG_PREFIX}: 用法 --approve <ID>" >&2; exit 1; }
        approve_task "$2"; exit $? ;;
    --reject)
        [ -n "${2:-}" ] || { echo "${LOG_PREFIX}: 用法 --reject <ID>" >&2; exit 1; }
        reject_task "$2"; exit $? ;;
    "") ;;  # 互動模式
    *)
        echo "${LOG_PREFIX}: 未知參數 $1（支援 --approve <ID> / --reject <ID>）" >&2; exit 1 ;;
esac

# ── 互動模式：逐件 y/n/s ──
echo "${LOG_PREFIX}: ${PENDING_COUNT} 個 held 任務待 triage" >&2
RC=0
while IFS= read -r task_json; do
    tid=$(echo "$task_json" | jq -r '.id')
    ttitle=$(echo "$task_json" | jq -r '.title')
    tref=$(echo "$task_json" | jq -r '.source.ref // ""')
    echo "" >&2
    echo "── ${tid}「${ttitle}」(${tref})" >&2
    printf "${LOG_PREFIX}: 核准進 ROADMAP? [y=核准 / n=駁回 / s=略過] " >&2
    read -r answer < /dev/tty || answer="s"
    case "$answer" in
        y|Y) approve_task "$tid" || RC=1 ;;
        n|N) reject_task "$tid" || RC=1 ;;
        *)   echo "${LOG_PREFIX}: ⏭️  略過 ${tid}（維持 held）" >&2 ;;
    esac
done < <(jq -c '.[] | select(.status == "pending")' "$INBOX_FILE")

exit $RC
