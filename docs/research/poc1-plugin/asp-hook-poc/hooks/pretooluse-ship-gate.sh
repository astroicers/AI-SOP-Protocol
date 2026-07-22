#!/usr/bin/env bash
# pretooluse-ship-gate.sh — PreToolUse commit 閘（SPEC-013 / ADR-020）
#
# 攔截「指令位置的 git commit」；若無新鮮測試痕跡（.asp-test-result.json passed
# 且 mtime ≥ .git/index）且未走 escape hatch → 輸出 permissionDecision:deny（FC-002
# 方式 A）擋下 commit，提示先跑 /asp-ship。把「commit 前跑測試」（asp-ship Step 1，
# 最高後果步驟）從散文升硬強制（ADR-020 遺忘威脅）。
#
# 誠實邊界：擋的是「連 make test 都沒跑」，非完整 10 步 ship（Steps 2-9 仍自律）。
# 死鎖防護：escape hatch（ASP_SHIP_OK=1）+ fail-open（jq 缺/異常 → 放行）。
# 本腳本受 Iron Rule A 保護（改它即繞過 → session-audit 偵測）。

set -uo pipefail

# ── fail-open：jq 缺 → 放行（defer），強制力讓位於可用性 ──
command -v jq >/dev/null 2>&1 || { echo "[ASP] pretooluse-ship-gate: jq 缺，fail-open 放行" >&2; exit 0; }

INPUT=$(cat 2>/dev/null) || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0

# ── 只攔「指令位置」的 git commit（行首或 ;/&&/| 之後），避免字串內誤判 ──
grep -qE '(^|[;&|]+[[:space:]]*)git[[:space:]]+commit' <<<"$COMMAND" || exit 0

PROJ="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // "."' 2>/dev/null)}"
METRICS_FILE="${ASP_METRICS_FILE:-$HOME/.claude/asp/metrics/rule-hits.jsonl}"

write_metric(){ # $1=action(pass|block|bypass)
  local line
  line=$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg p "$(basename "$PROJ")" \
    --arg r "SHIP-GATE" --arg a "$1" '{ts:$ts,project:$p,rule_id:$r,action:$a}' 2>/dev/null) || return 0
  { mkdir -p "${METRICS_FILE%/*}" && printf '%s\n' "$line" >>"$METRICS_FILE"; } 2>/dev/null || true
}

# ── escape hatch：誠實留痕（非無聲跳過） ──
if [ "${ASP_SHIP_OK:-}" = "1" ]; then
  write_metric bypass
  exit 0
fi

# ── 測試痕跡新鮮度判定 ──
TR="$PROJ/.asp-test-result.json"
IDX="$PROJ/.git/index"
fresh=0
if [ -f "$TR" ] && [ "$(jq -r '.passed // false' "$TR" 2>/dev/null)" = "true" ]; then
  if [ -f "$IDX" ]; then
    if grep -qE '\-\-amend' <<<"$COMMAND"; then
      fresh=1                       # amend：.git/index mtime 不可靠 → passed-only（保守放行）
    elif [ ! "$IDX" -nt "$TR" ]; then
      fresh=1                       # test-result 不舊於 index（= staging 後跑過測試）
    fi
  else
    fresh=1                         # 無 staged → passed 即放行
  fi
fi

if [ "$fresh" = 1 ]; then
  write_metric pass
  exit 0
fi

# ── 無/stale 測試痕跡 → deny ──
write_metric block
jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"ASP commit 閘：commit 前未見新鮮測試痕跡（.asp-test-result.json）。請先跑 /asp-ship 或 make test 再 commit；若確認要跳過，用 ASP_SHIP_OK=1 git commit ...（會留 bypass 遙測）。"}}'
exit 0
