#!/usr/bin/env bash
# daily-audit.sh — 每日健康審計 + 結構化日報草稿
#
# 使用時機：cron 或 GitHub Actions schedule（見 .asp/templates/cron-setup.md）
# 手動執行：bash .asp/scripts/daily-audit.sh
#
# 輸出：.asp-daily-report.md（結構化 Markdown，供 ASP-Operator 未來讀取發送）

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
REPORT_FILE="${PROJECT_DIR}/.asp-daily-report.md"
DATE=$(date +%Y-%m-%d)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── 收集 ROADMAP 狀態 ──
roadmap_summary() {
    local roadmap="${PROJECT_DIR}/ROADMAP.yaml"
    if [ ! -f "$roadmap" ]; then
        echo "無 ROADMAP.yaml"
        return
    fi
    python3 -c "
import sys
try:
    content = open('${roadmap}').read()
    import re
    statuses = re.findall(r'status:\s*(pending|in_progress|completed|blocked|failed|skipped)', content)
    from collections import Counter
    c = Counter(statuses)
    parts = []
    for k in ['completed','in_progress','pending','blocked','failed','skipped']:
        if k in c:
            parts.append(f'{k}={c[k]}')
    print('  '.join(parts) if parts else '無任務')
except Exception as e:
    print(f'(讀取失敗: {e})')
" 2>/dev/null || echo "(python3 不可用)"
}

# ── 收集 ADR 狀態 ──
adr_summary() {
    local adr_dir="${PROJECT_DIR}/docs/adr"
    if [ ! -d "$adr_dir" ]; then echo "無 ADR"; return; fi
    local draft=0 firm=0 accepted=0 total=0
    for f in "$adr_dir"/ADR-*.md; do
        [ -f "$f" ] || continue
        total=$((total+1))
        STATUS=$(grep -m1 "狀態" "$f" 2>/dev/null | grep -o '`[^`]*`' | tr -d '`' || true)
        case "$STATUS" in
            Draft)    draft=$((draft+1)) ;;
            FIRM)     firm=$((firm+1)) ;;
            Accepted) accepted=$((accepted+1)) ;;
        esac
    done
    echo "total=${total}  accepted=${accepted}  firm=${firm}  draft=${draft}"
}

# ── 收集 audit-quick 結果 ──
audit_result() {
    local out
    out=$(CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "${PROJECT_DIR}/.asp/hooks/session-audit.sh" 2>/dev/null | head -5 || true)
    if [ -f "${PROJECT_DIR}/.asp-session-briefing.json" ]; then
        python3 -c "
import json
d = json.load(open('${PROJECT_DIR}/.asp-session-briefing.json'))
b = len(d.get('blockers',[]))
w = len(d.get('warnings',[]))
i = len(d.get('infos',[]))
print(f'blockers={b}  warnings={w}  infos={i}')
" 2>/dev/null || echo "(briefing 讀取失敗)"
    else
        echo "(未執行審計)"
    fi
}

# ── 收集 inbox 狀態 ──
inbox_summary() {
    local inbox="${PROJECT_DIR}/.asp-task-inbox.json"
    if [ ! -f "$inbox" ]; then echo "無 inbox"; return; fi
    python3 -c "
import json
d = json.load(open('${inbox}'))
from collections import Counter
c = Counter(t.get('status','?') for t in d)
print('  '.join(f'{k}={v}' for k,v in c.items()) or '空')
" 2>/dev/null || echo "(jq 讀取失敗)"
}

# ── 收集 git 活動 ──
git_summary() {
    cd "$PROJECT_DIR" 2>/dev/null || return
    local since
    since=$(date -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
         || date -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
         || echo "1970-01-01")
    local count
    count=$(git log --oneline --after="$since" 2>/dev/null | wc -l | tr -d ' ')
    local authors
    authors=$(git log --format="%an" --after="$since" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || echo "unknown")
    echo "commits_24h=${count}  authors=${authors:-none}"
}

# ── 產生日報 ──
cat > "$REPORT_FILE" <<REPORT
# ASP 每日日報 — ${DATE}

> 自動產生時間：${TS}
> 來源：daily-audit.sh

---

## 專案狀態摘要

### ROADMAP 進度
$(roadmap_summary)

### ADR 狀態
$(adr_summary)

### 健康審計（session-audit）
$(audit_result)

### Task Inbox
$(inbox_summary)

### Git 活動（過去 24 小時）
$(git_summary)

---

## 今日待辦建議

> *以下為自動推斷，請人工確認後再行動*

$(if [ -f "${PROJECT_DIR}/.asp-session-briefing.json" ]; then
python3 -c "
import json
d = json.load(open('${PROJECT_DIR}/.asp-session-briefing.json'))
blockers = d.get('blockers', [])
if blockers:
    print('**Blockers（需立即處理）：**')
    for b in blockers:
        print(f'- {b}')
else:
    print('無 blocker，可繼續正常開發。')
" 2>/dev/null || echo "無法讀取 briefing"
else
    echo "尚未執行審計。"
fi)

---

*此報告由 ASP daily-audit.sh 自動生成，僅供參考。*
*如需發送通知，請接入 ASP-Operator（n8n / Slack webhook）。*
REPORT

echo "📊 ASP 每日日報已產生：${REPORT_FILE}" >&2
cat "$REPORT_FILE"
