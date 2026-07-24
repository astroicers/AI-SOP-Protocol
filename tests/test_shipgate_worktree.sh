#!/usr/bin/env bash
# test_shipgate_worktree.sh — #72：ship-gate 在 linked git worktree 正確解析 trace/index.
# Run: bash tests/test_shipgate_worktree.sh
#
# ship-gate（SPEC-013/ADR-020）commit 前檢查 .asp-test-result.json 是否新鮮
# （mtime ≥ git index）。linked worktree 的 .git 是「檔案」不是目錄，且 worktree
# session 下 CLAUDE_PROJECT_DIR 常指向主工作樹 → 兩個 bug：
#   (A) IDX="$PROJ/.git/index" 在 worktree 找不到 → 落 else fresh=1 → 恆放行（連 stale 也放；強制力破洞）。
#   (B) PROJ=CLAUDE_PROJECT_DIR(=主工作樹) → 檢查錯 repo 的 stale 痕跡 → 誤擋 worktree 的合法 commit（#60 實錄）。
# 修法：PROJ 用 commit 實際 cwd 的 git 頂層（git rev-parse --show-toplevel）、
#       IDX 用 git rev-parse --absolute-git-dir 解析真 index；非 git 退回舊行為。
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ASP_ROOT/.asp/hooks/pretooluse-ship-gate.sh"
command -v jq  >/dev/null 2>&1 || { echo "jq 缺，跳過";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "git 缺，跳過"; exit 0; }

mk_test_dir shipgate-wt
MAIN="$TEST_DIR/main"
mkdir -p "$MAIN"
git -C "$MAIN" init -q
git -C "$MAIN" config user.email t@t; git -C "$MAIN" config user.name t
echo a > "$MAIN/a"; git -C "$MAIN" add a
git -C "$MAIN" -c commit.gpgsign=false commit -qm init
WT="$TEST_DIR/wt"
git -C "$MAIN" worktree add -q "$WT" -b feat

# 餵 ship-gate：$1=cwd，$2=CLAUDE_PROJECT_DIR（空 = unset）。輸出含 "deny" = 擋。
run_gate() {
  local payload; payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$1")
  if [ -n "${2:-}" ]; then
    printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$2" bash "$GATE" 2>/dev/null
  else
    printf '%s' "$payload" | env -u CLAUDE_PROJECT_DIR bash "$GATE" 2>/dev/null
  fi
}

echo "── A：worktree + STALE 痕跡（index 新於 trace）→ 應擋（舊碼恆放行=破洞）──"
echo '{"passed":true}' > "$WT/.asp-test-result.json"
sleep 1
echo b > "$WT/b"; git -C "$WT" add b            # worktree 真 index 現新於 trace → stale
if run_gate "$WT" "" | grep -q '"deny"'; then
  pass "worktree + stale 痕跡 → 擋（真 index 解析生效）"
else
  fail "worktree + stale 痕跡未擋（#72-A 強制力破洞：IDX 找不到 → else fresh=1 恆放行）"
fi

echo "── B：worktree 有 FRESH 痕跡、但 CLAUDE_PROJECT_DIR=主工作樹(stale) → 應放行（舊碼誤擋 #60）──"
# 主工作樹：stale 痕跡（index 新於 trace）
echo '{"passed":true}' > "$MAIN/.asp-test-result.json"
sleep 1; echo z > "$MAIN/z"; git -C "$MAIN" add z
# worktree：fresh 痕跡（trace 新於 worktree index）
echo c > "$WT/c"; git -C "$WT" add c
sleep 1; echo '{"passed":true}' > "$WT/.asp-test-result.json"
if run_gate "$WT" "$MAIN" | grep -q '"deny"'; then
  fail "worktree 有 fresh 痕跡卻被擋（#72-B 誤擋：PROJ 取了 CLAUDE_PROJECT_DIR=主工作樹的 stale 痕跡）"
else
  pass "worktree fresh + CLAUDE_PROJECT_DIR=主工作樹 → 放行（PROJ 正確解析到 commit 所在 worktree）"
fi

echo "── C：worktree + FRESH 痕跡（無 CLAUDE_PROJECT_DIR）→ 放行（sanity，無誤擋）──"
# 承接 B 的 fresh 狀態（trace 仍新於 worktree index）
if run_gate "$WT" "" | grep -q '"deny"'; then
  fail "worktree + fresh 痕跡誤擋"
else
  pass "worktree + fresh 痕跡 → 放行"
fi

echo "── D：非 worktree 正常 repo（回歸）：stale→擋、fresh→放行，行為不變 ──"
echo '{"passed":true}' > "$MAIN/.asp-test-result.json"
sleep 1; echo q > "$MAIN/q"; git -C "$MAIN" add q   # main index 新於 main trace → stale
if run_gate "$MAIN" "$MAIN" | grep -q '"deny"'; then
  pass "正常 repo + stale → 擋（回歸不變）"
else
  fail "正常 repo + stale 應擋未擋（回歸破壞）"
fi
sleep 1; echo '{"passed":true}' > "$MAIN/.asp-test-result.json"  # trace 再度新於 index → fresh
if run_gate "$MAIN" "$MAIN" | grep -q '"deny"'; then
  fail "正常 repo + fresh 誤擋（回歸破壞）"
else
  pass "正常 repo + fresh → 放行（回歸不變）"
fi

echo "── E（安全審查 #1）：cwd 指向無關 repo（planted fresh 痕跡）、CLAUDE_PROJECT_DIR=主工作樹(stale) → 應擋（不信任無關 repo）──"
UNREL="$TEST_DIR/unrelated"
mkdir -p "$UNREL"; git -C "$UNREL" init -q
git -C "$UNREL" config user.email t@t; git -C "$UNREL" config user.name t
echo u > "$UNREL/u"; git -C "$UNREL" -c commit.gpgsign=false add u >/dev/null 2>&1 || git -C "$UNREL" add u
echo '{"passed":true}' > "$UNREL/.asp-test-result.json"     # planted 新鮮痕跡
echo '{"passed":true}' > "$MAIN/.asp-test-result.json"
sleep 1; echo s > "$MAIN/s"; git -C "$MAIN" add s           # 主工作樹 stale
if run_gate "$UNREL" "$MAIN" | grep -q '"deny"'; then
  pass "無關 repo 的 planted 痕跡不被信任 → 用 CLAUDE_PROJECT_DIR(stale) → 擋（繞過已堵）"
else
  fail "無關 repo planted 痕跡竟繞過 gate（#72 安全審查 #1：cwd 無條件覆蓋 CLAUDE_PROJECT_DIR）"
fi

echo "── F（安全審查 #2）：損壞/relocated worktree（.git 檔案無法解析）+ CLAUDE_PROJECT_DIR 未設 → 應擋（fail-closed）──"
MAIN2="$TEST_DIR/main2"
mkdir -p "$MAIN2"; git -C "$MAIN2" init -q
git -C "$MAIN2" config user.email t@t; git -C "$MAIN2" config user.name t
echo a > "$MAIN2/a"; git -C "$MAIN2" add a
git -C "$MAIN2" -c commit.gpgsign=false commit -qm init
git -C "$MAIN2" worktree add -q "$TEST_DIR/wt2" -b f2
mv "$MAIN2" "$TEST_DIR/main2moved"                          # 打斷 worktree → main gitdir 連結
echo '{"passed":true}' > "$TEST_DIR/wt2/.asp-test-result.json"
if run_gate "$TEST_DIR/wt2" "" | grep -q '"deny"'; then
  pass "損壞 worktree 無法解析 index → fail-closed 擋（強制力破洞已堵）"
else
  fail "損壞 worktree 恆放行（#72 安全審查 #2：else fresh=1 破洞復現）"
fi

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
