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

# ── 解析 commit 實際所在的 git worktree 頂層（#72）──
# worktree session 下 CLAUDE_PROJECT_DIR 常指向主工作樹 → 檢查錯 repo 的 trace/index
# （誤擋或恆放行）。修法：CLAUDE_PROJECT_DIR 仍是強信任錨；**僅當** cwd 是「與其同一
# superproject」的 worktree（絕對 git-common-dir 相等）才改用 cwd 的 worktree 頂層——
# 這杜絕 cd 進無關 repo 放 planted-trace 的無聲繞過（安全審查 #1）。未設 CLAUDE_PROJECT_DIR
# （非標準環境）才退回 cwd 的 git 頂層再退回 cwd。
# 信任假設：本 hook 進程的環境未被 ambient 設 GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE——
# 若被設，rev-parse 解析會被導向，可繞過 superproject 血緣比對。Claude Code 的 Bash 工具
# 每次呼叫的 env 不跨呼叫留存（指令字串只被本 hook 當字串讀、不執行）→ 單次 commit 無法注入；
# 屬既有威脅類別（等同能改 hook 本身，已由 Iron Rule A 另行涵蓋）。
# ── worktree 解析共用 lib（SPEC-017 DP1=b：_abs_common_dir 單一真相在 lib，與 session-audit 共用）──
# lib 缺（舊 checkout / 部分安裝）→ stub 印空 → 下方血緣比對不成立 → PROJ 守 CLAUDE_PROJECT_DIR
# （graceful degrade 回 pre-#72 行為：不 crash、不信 planted）。lib 受 Iron Rule A hash 保護。
# lib 與本 hook 同 repo ship → 先以 hook 自身位置解析，再退 CLAUDE_PROJECT_DIR / HOME 安裝點。
for _WT_LIB in "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/../scripts/lib/worktree.sh" \
               "${CLAUDE_PROJECT_DIR:-.}/.asp/scripts/lib/worktree.sh" \
               "${HOME}/.claude/asp/scripts/lib/worktree.sh"; do
    # shellcheck source=/dev/null
    [ -f "$_WT_LIB" ] && . "$_WT_LIB" && break
done
command -v _abs_common_dir >/dev/null 2>&1 || _abs_common_dir(){ :; }
_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // "."' 2>/dev/null)"
_CPD="${CLAUDE_PROJECT_DIR:-}"
if [ -n "$_CPD" ]; then
  PROJ="$_CPD"
  _CWD_TOP="$(git -C "$_CWD" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$_CWD_TOP" ] && [ "$_CWD_TOP" != "$_CPD" ]; then
    _cwd_common="$(_abs_common_dir "$_CWD")"
    if [ -n "$_cwd_common" ] && [ "$_cwd_common" = "$(_abs_common_dir "$_CPD")" ]; then
      PROJ="$_CWD_TOP"              # cwd 確為同 superproject 的 worktree → 用它
    fi
  fi
else
  PROJ="$(git -C "$_CWD" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$PROJ" ] || PROJ="$_CWD"
fi
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

# ── 檢查本體：單一事實源（P0-5 薄包裝；asp-ng ADR-000 §7）──
# 新鮮度邏輯已抽至 asp-gate.yaml → 渲染物 .asp/gate.sh（.asp/checks/test-fresh.sh，逐行保留）。
# 本 hook 只留攔截/worktree 解析/escape hatch/metrics 骨架；擴充檢查＝改 asp-gate.yaml
# 後以 asp-ng 的 `asp render gate` 重渲染，不改本檔。
ASP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"   # repo 頂層（.asp/hooks/ 上兩層）
GATE="$ASP_HOME/.asp/gate.sh"
if [ ! -f "$GATE" ]; then
  # 渲染物缺（部分安裝/舊 checkout）→ fail-open，與 jq 缺同哲學：強制力讓位於可用性
  echo "[ASP] pretooluse-ship-gate: gate 渲染物缺（$GATE），fail-open 放行" >&2
  exit 0
fi
if ASP_GATE_HOME="$ASP_HOME" ASP_GATE_PROJ="$PROJ" ASP_GATE_COMMAND="$COMMAND" bash "$GATE" >/dev/null 2>&1; then
  write_metric pass
  exit 0
fi

# ── 無/stale 測試痕跡 → deny ──
write_metric block
jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"ASP commit 閘：commit 前未見新鮮測試痕跡（.asp-test-result.json）。請先跑 /asp-ship 或 make test 再 commit；若確認要跳過，用 ASP_SHIP_OK=1 git commit ...（會留 bypass 遙測）。"}}'
exit 0
