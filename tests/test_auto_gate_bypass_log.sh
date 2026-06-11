#!/usr/bin/env bash
# test_auto_gate_bypass_log.sh — SPEC-006: bypass 整合
# 驗證 (1) asp-plan.md 5.5.4 / asp-ship.md 9.6 含正確的 bypass 指令（STEP 對應），
# (2) bypass entry 的 ndjson schema（與 Makefile asp-bypass-record 同構）。
# Run: bash tests/test_auto_gate_bypass_log.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAN="$ASP_ROOT/.claude/skills/asp/asp-plan.md"
SHIP="$ASP_ROOT/.claude/skills/asp/asp-ship.md"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

echo ""; echo "Contract: bypass 指令存在且 STEP 正確"
grep -q "asp-bypass-record SKILL=asp-plan STEP=Step5.5" "$PLAN" \
    && pass "asp-plan.md 5.5.4 含 STEP=Step5.5 bypass 指令" || fail "asp-plan.md 缺 Step5.5 bypass 指令"
grep -q "STEP=Step9.6" "$SHIP" \
    && pass "asp-ship.md 9.6 含 STEP=Step9.6 bypass 指令" || fail "asp-ship.md 缺 Step9.6 bypass 指令"
grep -q "spawn-failure\|spawn 失敗" "$PLAN" \
    && pass "asp-plan.md 含 spawn 失敗 → bypass 規則（E9）" || fail "缺 E9 spawn-failure bypass 規則"

echo ""; echo "Schema: bypass entry ndjson（與 make asp-bypass-record 同構）"
ENTRY=$(jq -n --arg t "2026-06-11T00:00:00Z" --arg s "asp-plan" --arg st "Step5.5" --arg r "spawn-failure: timeout" --arg a "ai" \
    '{timestamp:$t, skill:$s, step:$st, reason:$r, actor:$a}')
echo "$ENTRY" | jq -e '.timestamp and .skill and .step and .reason and .actor' >/dev/null \
    && pass "schema keys: timestamp/skill/step/reason/actor" || fail "schema 組裝失敗"
echo "$ENTRY" | jq -e '.step == "Step5.5"' >/dev/null \
    && pass "step 值正確" || fail "step 值錯誤"

echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
