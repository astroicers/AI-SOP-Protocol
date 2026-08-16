#!/usr/bin/env bash
# test-fresh — commit 前測試痕跡新鮮度判定(P0-5 自 pretooluse-ship-gate.sh 抽出,邏輯逐行保留)
# 輸入(env):ASP_GATE_PROJ=受檢 repo 頂層(缺省=cwd 的 git toplevel)
#           ASP_GATE_COMMAND=攔截到的指令字串(--amend 判定用,缺省空)
# 結束碼:0=fresh(放行)、1=無/stale 痕跡(blocker)
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0   # fail-open,與 hook 既有行為一致

PROJ="${ASP_GATE_PROJ:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COMMAND="${ASP_GATE_COMMAND:-}"

TR="$PROJ/.asp-test-result.json"
# 解析真實 git index:linked worktree 的 .git 是檔案、index 在 .git/worktrees/<n>/index(#72)
_GITDIR="$(git -C "$PROJ" rev-parse --absolute-git-dir 2>/dev/null)"
IDX="${_GITDIR:-$PROJ/.git}/index"
fresh=0
if [ -f "$TR" ] && [ "$(jq -r '.passed // false' "$TR" 2>/dev/null)" = "true" ]; then
  if [ -f "$IDX" ]; then
    if grep -qE '\-\-amend' <<<"$COMMAND"; then
      fresh=1                       # amend:.git/index mtime 不可靠 → passed-only(保守放行)
    elif [ ! "$IDX" -nt "$TR" ]; then
      fresh=1                       # test-result 不舊於 index(= staging 後跑過測試)
    fi
  elif [ -n "$_GITDIR" ] || [ -d "$PROJ/.git" ]; then
    fresh=1                         # 確認是 repo 但無 index = 真無 staged → passed 放行
  fi                                # .git 為檔案卻無法解析 index → 保守擋(fail-closed,安全審查 #2)
fi
[ "$fresh" = 1 ]
