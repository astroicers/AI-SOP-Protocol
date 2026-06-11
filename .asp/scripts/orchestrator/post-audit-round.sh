#!/usr/bin/env bash
# post-audit-round.sh — 後置審計輪數狀態機（v5 Phase 2，ADR-015/SPEC-011）
#
# 自 task_orchestrator.md 統一入口 Step 3 下沉：後置審計最多 cap（預設 2）輪，
# 超限由呼叫端改記 tech-debt（make orch-debt-log）。
# 狀態檔：{project}/.asp-orch-state.json（gitignored）。
#
# 用法：post-audit-round.sh --get|--increment|--reset [--project DIR] [--cap N]
# 輸出：單行 JSON {round, cap, exceeded}
# 退出碼：0 正常 | 4 increment 時已達 cap（JSON 仍輸出） | 2 參數錯誤 | 3 缺 jq

set -euo pipefail

PROJECT="."
CAP=2
ACTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --get|--increment|--reset)
      [ -n "$ACTION" ] && { echo "ERROR: 只能指定一個動作" >&2; exit 2; }
      ACTION="${1#--}"; shift ;;
    --project) PROJECT="$2"; shift 2 ;;
    --cap) CAP="$2"; shift 2 ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$ACTION" ] || { echo "ERROR: 必須指定 --get | --increment | --reset" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 3; }

STATE="$PROJECT/.asp-orch-state.json"
ROUND=0
if [ -f "$STATE" ]; then
  if jq -e . "$STATE" >/dev/null 2>&1; then
    ROUND=$(jq -r '.audit_round // 0' "$STATE")
  else
    echo "WARNING: $STATE 損毀，視為 round=0 重建" >&2
    ROUND=0
  fi
fi

emit() { # $1=round
  local exceeded=false
  [ "$1" -ge "$CAP" ] && exceeded=true
  jq -cn --argjson r "$1" --argjson c "$CAP" --argjson e "$exceeded" \
    '{round: $r, cap: $c, exceeded: $e}'
}

write_state() { # $1=round
  jq -cn --argjson r "$1" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{audit_round: $r, updated: $ts}' > "$STATE"
}

case "$ACTION" in
  get)
    emit "$ROUND" ;;
  reset)
    write_state 0
    emit 0 ;;
  increment)
    if [ "$ROUND" -ge "$CAP" ]; then
      emit "$ROUND"
      echo "ERROR: 後置審計已達上限（cap=$CAP），剩餘 gap 請改記 tech-debt（make orch-debt-log）" >&2
      exit 4
    fi
    ROUND=$((ROUND + 1))
    write_state "$ROUND"
    emit "$ROUND" ;;
esac
