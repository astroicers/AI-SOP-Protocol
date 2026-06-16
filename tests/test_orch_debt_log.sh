#!/usr/bin/env bash
# test_orch_debt_log.sh — tests for .asp/scripts/orchestrator/tech-debt-log.sh
# (v5 Phase 2: tech-debt marker append, format-compatible with A8.3 scan and
# make tech-debt-list).
# Run: bash tests/test_orch_debt_log.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/orchestrator/tech-debt-log.sh"
mk_test_dir

t() { OUT=$(cd "$TEST_DIR" && bash "$SCRIPT" "$@" 2>/dev/null); RC=$?; }
DEBT="$TEST_DIR/docs/TECH_DEBT.md"

echo ""
echo "T1: 建檔 + 追加 marker 行（A8.3 可掃描格式）"
t --category post-audit-overflow --desc "audit gap X" --severity MED --due 2026-12-31
[ "$RC" = "0" ] && pass "exit 0" || fail "rc=$RC"
[ -f "$DEBT" ] && pass "docs/TECH_DEBT.md 已建檔" || fail "file missing"
grep -qE 'tech-debt: MED post-audit-overflow .*\(DUE: 2026-12-31' "$DEBT" \
  && pass "marker 格式正確（tech-debt: SEV CAT desc (DUE: date)）" || fail "format wrong: $(cat "$DEBT" 2>/dev/null | tail -1)"
echo "$OUT" | jq -e '.recorded == true' >/dev/null && pass "JSON recorded=true" || fail "JSON wrong"

echo ""
echo "T2: append-only（兩次呼叫兩行）"
t --category misc --desc "second item" --severity LOW
[ "$(grep -c 'tech-debt:' "$DEBT")" = "2" ] && pass "兩行 marker" || fail "count=$(grep -c 'tech-debt:' "$DEBT")"

echo ""
echo "T3: HIGH 無 --due → exit 2"
t --category security --desc "no due" --severity HIGH
[ "$RC" = "2" ] && pass "HIGH 無 due exit 2" || fail "rc=$RC"

echo ""
echo "T4: 預設 severity = MED；輸出 JSON 合法"
t --category refactor --desc "default sev"
echo "$OUT" | jq -e . >/dev/null && pass "JSON 合法" || fail "broken JSON"
grep -q 'tech-debt: MED refactor' "$DEBT" && pass "預設 MED" || fail "default sev wrong"

echo ""
echo "T5: 參數缺失 → exit 2"
t --severity LOW
[ "$RC" = "2" ] && pass "缺 category/desc exit 2" || fail "rc=$RC"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
