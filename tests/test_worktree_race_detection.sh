#!/usr/bin/env bash
# test_worktree_race_detection.sh — ADR-027 L2（#60）：A19.1 多 session worktree 競態 advisory.
# Run: bash tests/test_worktree_race_detection.sh
#
# session-audit 在「主工作樹（.git 為目錄）且存在其他 linked worktree」時印 A19.1 WARNING，
# 提醒多 session 並行同一 repo 有 HEAD/commit 落錯分支競態（#56 事故實錄）→ 建議每 session
# 專屬 worktree（ADR-027 L1）。純 advisory、不阻擋。已隔離的 linked worktree 不警告。
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ASP_ROOT/.asp/hooks/session-audit.sh"
command -v jq  >/dev/null 2>&1 || { echo "jq 缺，跳過";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "git 缺，跳過"; exit 0; }

mk_test_dir worktree-race
MAIN="$TEST_DIR/main"
mkdir -p "$MAIN"
git -C "$MAIN" init -q
git -C "$MAIN" config user.email t@t; git -C "$MAIN" config user.name t
echo x > "$MAIN/f"; git -C "$MAIN" add f
git -C "$MAIN" -c commit.gpgsign=false commit -qm init

run_audit() { CLAUDE_PROJECT_DIR="$1" bash "$AUDIT" 2>/dev/null </dev/null; }

# SPEC-017 harness 鐵則：worktree 案例必餵 stdin JSON .cwd + CLAUDE_PROJECT_DIR=主樹
# （真況＝anchor 恆主樹、worktree 訊號只在 stdin）；直接 CLAUDE_PROJECT_DIR=worktree 不模擬真 bug。
run_audit_wt() {
  printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1" \
    | CLAUDE_PROJECT_DIR="$2" bash "$AUDIT" 2>/dev/null
}

echo "── 單一 worktree（無並行）→ 不警告 ──"
run_audit "$MAIN" | grep -q "A19.1" && fail "單一 worktree 誤報 A19.1（false-positive）" || pass "單一 worktree 無 A19.1"

echo "── 加一個 linked worktree（模擬並行 session 用了 worktree）──"
git -C "$MAIN" worktree add -q "$TEST_DIR/wt" -b feat 2>/dev/null || git -C "$MAIN" worktree add -q "$TEST_DIR/wt" 2>/dev/null

echo "── 在主工作樹 + 其他 worktree 存在 → A19.1（共用風險）──"
run_audit "$MAIN" | grep -q "A19.1" && pass "主工作樹 + 其他 worktree → A19.1 警告" || fail "應報 A19.1（主工作樹共用風險）未報"

echo "── T5（SPEC-017）：真況 worktree session（stdin.cwd=worktree、CLAUDE_PROJECT_DIR=主樹）→ 不警告 ──"
run_audit_wt "$TEST_DIR/wt" "$MAIN" | grep -q "A19.1" \
  && fail "T5 worktree session 仍被 A19.1 cry-wolf（判別式讀 CLAUDE_PROJECT_DIR=主樹 .git 目錄）" \
  || pass "T5 worktree session 無 A19.1（cry-wolf 消除）"

echo "── T6（SPEC-017）：stdin.cwd=主樹、CLAUDE_PROJECT_DIR=主樹 + 其他活躍 worktree → 警告（意圖保留）──"
run_audit_wt "$MAIN" "$MAIN" | grep -q "A19.1" \
  && pass "T6 主樹 session + 其他 worktree → A19.1 警告保留" \
  || fail "T6 主樹 session 應報 A19.1 未報（修復把意圖修掉了）"

# F4 澄清：本案主體＝「anchor 本身即 worktree」（.git 為檔案 → 不警告）分支的回歸，
# 非模擬 worktree session（那類案例一律 stdin-piping，見 T5）；故保留舊 harness 合法。
echo "── 在 linked（專屬）worktree（舊 harness 回歸案，CLAUDE_PROJECT_DIR=worktree）→ 不警告（已隔離）──"
run_audit "$TEST_DIR/wt" | grep -q "A19.1" && fail "linked worktree 誤報 A19.1（已隔離不該警告）" || pass "linked（專屬）worktree 無 A19.1"

echo "── 刪掉 worktree 目錄（變 prunable 殭屍）→ 主工作樹不再警告（review 5b：cry-wolf 防治）──"
rm -rf "$TEST_DIR/wt"
run_audit "$MAIN" | grep -q "A19.1" && fail "prunable 殭屍 worktree 仍誤報 A19.1（cry-wolf）" || pass "prunable worktree 已濾除 → 主工作樹無 A19.1"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
