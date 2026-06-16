#!/usr/bin/env bash
# test_orch_round.sh — tests for .asp/scripts/orchestrator/post-audit-round.sh
# (v5 Phase 2: post-audit round cap state machine, .asp-orch-state.json).
# Run: bash tests/test_orch_round.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/orchestrator/post-audit-round.sh"
mk_test_dir

t() { OUT=$(bash "$SCRIPT" --project "$TEST_DIR" "$@" 2>/dev/null); RC=$?; }
jval() { echo "$OUT" | jq -r "$1"; }

echo ""
echo "T1: 初始 get → round=0"
t --get
[ "$RC" = "0" ] && [ "$(jval .round)" = "0" ] && pass "round=0" || fail "rc=$RC round=$(jval .round)"

echo ""
echo "T2: increment ×2 → 邊界"
t --increment
[ "$(jval .round)" = "1" ] && [ "$(jval .exceeded)" = "false" ] && pass "round=1 exceeded=false" || fail "round=$(jval .round) exceeded=$(jval .exceeded)"
t --increment
[ "$(jval .round)" = "2" ] && [ "$(jval .exceeded)" = "true" ] && pass "round=2 exceeded=true（達 cap）" || fail "round=$(jval .round) exceeded=$(jval .exceeded)"

echo ""
echo "T3: 第三次 increment → exit 4"
t --increment
[ "$RC" = "4" ] && pass "超限 increment exit 4" || fail "rc=$RC"

echo ""
echo "T4: reset → round=0"
t --reset
[ "$RC" = "0" ] && [ "$(jval .round)" = "0" ] && pass "reset 後 round=0" || fail "rc=$RC round=$(jval .round)"

echo ""
echo "T5: 狀態檔為合法 JSON"
jq -e . "$TEST_DIR/.asp-orch-state.json" >/dev/null && pass "state 檔合法 JSON" || fail "state file broken"

echo ""
echo "T6: 損毀 state → 視為 0 重建 + stderr WARNING"
echo 'garbage' > "$TEST_DIR/.asp-orch-state.json"
OUT=$(bash "$SCRIPT" --project "$TEST_DIR" --get 2>"$TEST_DIR/err"); RC=$?
[ "$RC" = "0" ] && [ "$(echo "$OUT" | jq -r .round)" = "0" ] && pass "損毀 → round=0" || fail "rc=$RC"
grep -qi 'warn' "$TEST_DIR/err" && pass "stderr 有 WARNING" || fail "no warning"

echo ""
echo "T7: 自訂 cap"
rm -f "$TEST_DIR/.asp-orch-state.json"
t --increment --cap 1
[ "$(jval .exceeded)" = "true" ] && pass "cap=1 時第一次即達上限" || fail "exceeded=$(jval .exceeded)"

echo ""
echo "T8: 參數錯誤 → exit 2"
t
[ "$RC" = "2" ] && pass "無動作參數 exit 2" || fail "rc=$RC"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
