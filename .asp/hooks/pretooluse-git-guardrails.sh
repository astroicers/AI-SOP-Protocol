#!/usr/bin/env bash
# pretooluse-git-guardrails.sh — PreToolUse 本地毀資料護欄（SPEC-016 / ADR-030）
#
# 【薄包裝】檢查本體已遷至 asp-ng 單一事實源（asp-ng issue #32 G1 裁定；ADR-000 §7
# 「強制困在 hooks」為 v4 病灶）。判定邏輯＝ .asp/checks/git-guard.sh（M0 分段/tokenize
# 與 M1 九類謂詞逐行遷出）。本 hook 只留：攔截骨架（stdin/jq）、escape hatch、遙測、
# deny 輸出。擴充謂詞＝改 asp-ng 的檢查本體後同步至本 repo，不改本檔。
#
# 攔截點說明：本 hook 為 PreToolUse（逐指令），與 commit 時的 .asp/gate.sh 聚合物攔截點
# 不同，故直接呼叫檢查本體而非 gate.sh——避免 commit 專用檢查（test-fresh）被套用到每
# 一條 Bash 指令而全面誤擋。
#
# 檢查本體契約（asp-ng 定義）：exit 0＝無命中；exit 1＝命中（stdout 末段為命中謂詞）；
# exit 200＝自跳過（無指令／超長 GG-SEC-01）。stdout 一律由本 hook 吸收，不外洩至使用者。
#
# 於 Bash 執行前攔截「本地毀滅性 git 操作」（不可逆銷毀未提交/未合併/未追蹤本地成果）：
# reset --hard / clean(force,!dry-run,!interactive) / branch force-delete /
# checkout|restore|switch 丟工作區 / stash clear|drop / worktree remove --force / rm --force。
# 命中 → permissionDecision:deny（FC-002 方式 A）+ GIT-GUARD block 遙測；ASP_GIT_OK=1（hook
# env）→ defer + bypass 遙測；jq 缺 → defer+WARN；stdin 空/無 command → defer 靜默（no-op）。
# 把 CLAUDE-IR-1（破壞性操作前須人類確認）的本地 git 子集從散文升硬強制。
#
# 誠實能力邊界（前綴補全/命令替換/包裝前綴/checkout 檔路徑）見 SPEC-016 與 FC-013。
# 本腳本受 Iron Rule A 保護（改它即繞過 → session-audit 偵測）。
set -uo pipefail

# ── fail-open：jq 缺 → defer + WARN ──
command -v jq >/dev/null 2>&1 || { echo "[ASP] git-guardrails: jq 缺，fail-open defer" >&2; exit 0; }

INPUT=$(cat 2>/dev/null) || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0          # stdin 空/無 command → no-op 靜默 defer

# ── 檢查本體：單一事實源（asp-ng .asp/checks/git-guard.sh，逐行遷移）──
ASP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"   # repo 頂層（.asp/hooks/ 上兩層）
CHECK="$ASP_HOME/.asp/checks/git-guard.sh"
if [ ! -f "$CHECK" ]; then
  # 檢查本體缺（部分安裝/舊 checkout）→ fail-open，與 jq 缺同哲學：強制力讓位於可用性
  echo "[ASP] git-guardrails: 檢查本體缺（$CHECK），fail-open defer" >&2
  exit 0
fi

_OUT=$(bash "$CHECK" "$COMMAND" 2>/dev/null); _RC=$?
[ "$_RC" = 1 ] || exit 0             # 0＝無命中、200＝自跳過、其他＝異常 → 一律 defer

MATCHED="${_OUT##*操作: }"           # 契約：stdout 末段為命中謂詞
[ -n "$MATCHED" ] && [ "$MATCHED" != "$_OUT" ] || MATCHED="本地毀滅性 git 操作"

METRICS_FILE="${ASP_METRICS_FILE:-$HOME/.claude/asp/metrics/rule-hits.jsonl}"
write_metric() {                     # $1=action(block|bypass)
  local line
  line=$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg p "$(basename "${CLAUDE_PROJECT_DIR:-.}")" --arg a "$1" \
    '{ts:$ts,project:$p,rule_id:"GIT-GUARD",action:$a}' 2>/dev/null) || return 0
  { mkdir -p "${METRICS_FILE%/*}" && printf '%s\n' "$line" >>"$METRICS_FILE"; } 2>/dev/null || true
}

# escape hatch：命中但 ASP_GIT_OK=1（hook env）→ defer + 留痕
if [ "${ASP_GIT_OK:-}" = "1" ]; then
  write_metric bypass
  exit 0
fi

write_metric block
REASON="ASP git-guardrails：偵測到本地毀滅性操作（${MATCHED}），將不可逆銷毀本地成果（未提交變更/未合併分支/未追蹤檔）。破壞性操作前須人類確認（鐵則 CLAUDE-IR-1）。確認要執行 → 在 Claude Code 啟動環境設 ASP_GIT_OK=1 後重試（會留 GIT-GUARD 遙測）；否則請改用非破壞替代（git stash 代 reset --hard、git clean -n 先預覽、git branch -d 代 -D）。"
jq -cn --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
