#!/usr/bin/env bash
# test_orch_audit_check.sh — tests for .asp/scripts/orchestrator/audit-check.sh
# (v5 Phase 2: deterministic "should we audit?" pre-check; the audit body
# remains make audit-health).
# Run: bash tests/test_orch_audit_check.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/orchestrator/audit-check.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-oac-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

mkproj() { rm -rf "$TEST_DIR"; mkdir -p "$TEST_DIR"; touch "$TEST_DIR/README.md" "$TEST_DIR/CHANGELOG.md"; }
t() { OUT=$(bash "$SCRIPT" --project "$TEST_DIR" "$@" 2>/dev/null); RC=$?; }
jval() { echo "$OUT" | jq -r "$1"; }

echo ""
echo "T1: 無 baseline → audit_required=true, exit 2"
mkproj; t
[ "$RC" = "2" ] && pass "exit 2" || fail "rc=$RC"
[ "$(jval .baseline_exists)" = "false" ] && pass "baseline_exists=false" || fail "got $(jval .baseline_exists)"
[ "$(jval .audit_required)" = "true" ] && pass "audit_required=true" || fail "got $(jval .audit_required)"

echo ""
echo "T2: 新鮮 baseline → exit 0, stale=false"
mkproj
printf '{"last_audit": "%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TEST_DIR/.asp-audit-baseline.json"
t
[ "$RC" = "0" ] && pass "exit 0" || fail "rc=$RC"
[ "$(jval .stale)" = "false" ] && pass "stale=false" || fail "got $(jval .stale)"

echo ""
echo "T3: 8 天前 baseline → stale=true, exit 2"
mkproj
OLD=$(date -u -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-8d +%Y-%m-%dT%H:%M:%SZ)
printf '{"last_audit": "%s"}\n' "$OLD" > "$TEST_DIR/.asp-audit-baseline.json"
t
[ "$RC" = "2" ] && pass "exit 2" || fail "rc=$RC"
[ "$(jval .stale)" = "true" ] && pass "stale=true" || fail "got $(jval .stale)"
AGE=$(jval .age_days)
[ "$AGE" -ge 7 ] && pass "age_days=$AGE (≥7)" || fail "age_days=$AGE"

echo ""
echo "T3a: --max-age-days 30 放寬 → 同一 baseline 變新鮮"
t --max-age-days 30
[ "$RC" = "0" ] && [ "$(jval .stale)" = "false" ] && pass "30 天門檻下 exit 0" || fail "rc=$RC stale=$(jval .stale)"

echo ""
echo "T4: 壞 JSON baseline → 視同缺失 exit 2，不噴錯"
mkproj
echo 'not json{{{' > "$TEST_DIR/.asp-audit-baseline.json"
OUT=$(bash "$SCRIPT" --project "$TEST_DIR" 2>"$TEST_DIR/err"); RC=$?
[ "$RC" = "2" ] && pass "壞 JSON exit 2" || fail "rc=$RC"
echo "$OUT" | jq -e . >/dev/null && pass "仍輸出合法 JSON" || fail "broken JSON output"

echo ""
echo "T5: 缺 README/CHANGELOG 列入 missing_files"
mkproj; rm "$TEST_DIR/CHANGELOG.md"
printf '{"last_audit": "%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TEST_DIR/.asp-audit-baseline.json"
t
echo "$OUT" | jq -e '.missing_files | index("CHANGELOG.md")' >/dev/null \
  && pass "CHANGELOG.md 在 missing_files" || fail "missing_files=$(jval .missing_files)"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
