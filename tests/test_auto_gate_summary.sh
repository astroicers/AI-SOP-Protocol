#!/usr/bin/env bash
# test_auto_gate_summary.sh — SPEC-006: 主對話摘要格式契約
# 驗證 (1) fixture 摘要含必要元素（canonical 格式防漂移），(2) asp-plan.md 指示 echo 該摘要。
# Run: bash tests/test_auto_gate_summary.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ASP_ROOT/tests/fixtures/auto-gate/sample-summary.md"
PLAN="$ASP_ROOT/.claude/skills/asp/asp-plan.md"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

echo ""; echo "Fixture: canonical summary format"
[ -f "$FIXTURE" ] || { fail "fixture 不存在"; echo "PASS: 0/1"; exit 1; }
grep -q "^## asp-gate auto-review 結果" "$FIXTURE" \
    && pass "標題行正確" || fail "缺標題「## asp-gate auto-review 結果」"
grep -q "| Gate | Status | WARN/BLOCKER |" "$FIXTURE" \
    && pass "表頭欄位正確" || fail "表頭欄位錯誤"
grep -qE "^完整報告：\.asp-gate-log/" "$FIXTURE" \
    && pass "含完整報告路徑行" || fail "缺「完整報告：.asp-gate-log/...」行"

echo ""; echo "Contract: asp-plan.md 指示 echo 摘要"
grep -q "asp-gate auto-review 結果" "$PLAN" \
    && pass "asp-plan.md 引用摘要區塊名" || fail "asp-plan.md 未指示 echo 摘要（SPEC-006 未落地）"

echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
