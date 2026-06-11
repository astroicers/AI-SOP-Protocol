#!/usr/bin/env bash
# tech-debt-log.sh — tech-debt 記錄落檔（v5 Phase 2，ADR-015/SPEC-011）
#
# 自 task_orchestrator.md 的 LOG_TECH_DEBT() 散落呼叫下沉。追加一行標準
# marker 至 docs/TECH_DEBT.md，格式與 global_core「Tech Debt 彙總」/
# session-audit A8.3 掃描 / make tech-debt-list 相容：
#   tech-debt: [HIGH|MED|LOW] [CATEGORY] description (DUE: YYYY-MM-DD, logged: YYYY-MM-DD)
#
# 用法：tech-debt-log.sh --category C --desc D [--severity HIGH|MED|LOW] [--due YYYY-MM-DD]
# 輸出：單行 JSON {recorded, file}
# 退出碼：0 成功 | 2 參數錯誤（含 HIGH 無 --due） | 3 缺 jq

set -euo pipefail

CATEGORY=""
DESC=""
SEVERITY="MED"
DUE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --category) CATEGORY="$2"; shift 2 ;;
    --desc) DESC="$2"; shift 2 ;;
    --severity) SEVERITY="$2"; shift 2 ;;
    --due) DUE="$2"; shift 2 ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 3; }
[ -n "$CATEGORY" ] && [ -n "$DESC" ] || { echo "ERROR: --category 與 --desc 必填" >&2; exit 2; }
case "$SEVERITY" in HIGH|MED|LOW) ;; *) echo "ERROR: severity 值無效：$SEVERITY" >&2; exit 2 ;; esac
if [ "$SEVERITY" = "HIGH" ] && [ -z "$DUE" ]; then
  echo "ERROR: HIGH 必須附 --due 日期（global_core Tech Debt 規則：超期自動升 blocker）" >&2
  exit 2
fi

FILE="docs/TECH_DEBT.md"
TODAY=$(date -u +%Y-%m-%d)
mkdir -p "$(dirname "$FILE")"
if [ ! -f "$FILE" ]; then
  printf '# Tech Debt Ledger\n\n> 由 make orch-debt-log 追加；格式見 global_core「Tech Debt 彙總」。\n\n' > "$FILE"
fi

if [ -n "$DUE" ]; then
  printf -- '- tech-debt: %s %s %s (DUE: %s, logged: %s)\n' "$SEVERITY" "$CATEGORY" "$DESC" "$DUE" "$TODAY" >> "$FILE"
else
  printf -- '- tech-debt: %s %s %s (logged: %s)\n' "$SEVERITY" "$CATEGORY" "$DESC" "$TODAY" >> "$FILE"
fi

jq -cn --arg f "$FILE" '{recorded: true, file: $f}'
