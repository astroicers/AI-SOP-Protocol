#!/usr/bin/env bash
# test_asp_plan_step5_rationalization.sh — SPEC-006: R1-R7 反藉口初始集
# asp-plan.md Step 5.5.4 必須含 R1-R7 七條（各 grep 對應反駁關鍵字）。
# Run: bash tests/test_asp_plan_step5_rationalization.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAN="$ASP_ROOT/.claude/skills/asp/asp-plan.md"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

echo ""
grep -q '^## Step 5\.[0-9]\+ — auto-gate' "$PLAN" \
    && pass "Step 5.X auto-gate 標題（markdown header）存在" || fail "缺 Step 5.X auto-gate header"

# R1-R7：藉口關鍵字 + 反駁關鍵字成對檢查
declare -A EXCUSE REBUT
EXCUSE[R1]="太小，不值得";        REBUT[R1]="主觀判斷"
EXCUSE[R2]="腦中已驗證";          REBUT[R2]="獨立 context"
EXCUSE[R3]="趕時間";              REBUT[R3]="便宜 10x"
EXCUSE[R4]="只是 Draft";          REBUT[R4]="review 的對象"
EXCUSE[R5]="Context budget";      REBUT[R5]="獨立 context，不佔主對話"
EXCUSE[R6]="只是修錯字";          REBUT[R6]="仍命中 glob"
EXCUSE[R7]="八成也是";            REBUT[R7]="機械統計"

for r in R1 R2 R3 R4 R5 R6 R7; do
    if grep -q "${EXCUSE[$r]}" "$PLAN" && grep -q "${REBUT[$r]}" "$PLAN"; then
        pass "$r 藉口+反駁成對存在"
    else
        fail "$r 缺藉口或反駁（藉口:「${EXCUSE[$r]}」反駁:「${REBUT[$r]}」）"
    fi
done

grep -q "機械 glob\|禁止以 AI 啟發式判斷" "$PLAN" \
    && pass "明示機械觸發、禁止啟發式" || fail "未明示禁止 AI 啟發式判斷"

echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
