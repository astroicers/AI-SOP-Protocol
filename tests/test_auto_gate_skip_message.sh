#!/usr/bin/env bash
# test_auto_gate_skip_message.sh — SPEC-006: glob 未命中時的決策痕跡句（必填）
# Run: bash tests/test_auto_gate_skip_message.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAN="$ASP_ROOT/.claude/skills/asp/asp-plan.md"

echo ""
grep -q "無 ADR/SPEC 變更，跳過 auto-gate" "$PLAN" \
    && pass "skip 決策痕跡句 verbatim 存在" || fail "缺「無 ADR/SPEC 變更，跳過 auto-gate」句"
grep -q "決策痕跡" "$PLAN" \
    && pass "明示其為必填決策痕跡" || fail "未說明 skip 句為必填決策痕跡"
grep -q "supersede 流程而非誤刪" "$PLAN" \
    && pass "E3 刪除提示句存在" || fail "缺 ADR 刪除 supersede 提示（E3）"

echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
