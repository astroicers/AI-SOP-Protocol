#!/usr/bin/env bash
# test_validate_profile.sh — tests for .asp/scripts/validate-profile.sh
# (governance-critical: validates .ai_profile field constraints + dependency
# auto-fix). Also a regression for the TD/review fix replacing non-portable
# `sed -i` with portable awk for the frontend_quality auto-insert.
# Run: bash tests/test_validate_profile.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/validate-profile.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-vp-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

P() { echo "$TEST_DIR/.ai_profile"; }
OUT=""; RC=0
run() { OUT=$(bash "$SCRIPT" "$(P)" 2>&1); RC=$?; }

# ── T1: missing profile → exit 1 ──
echo ""
echo "T1: missing profile → exit 1"
OUT=$(bash "$SCRIPT" "$TEST_DIR/nope" 2>&1); RC=$?
[ "$RC" = "1" ] && pass "missing profile exits 1" || fail "missing profile rc=$RC (expected 1)"

# ── T2: missing required 'type' → ERROR + exit 1 ──
echo ""
echo "T2: missing 'type' → ERROR, exit 1"
printf 'level: 2\n' > "$(P)"; run
{ echo "$OUT" | grep -q "缺少必填欄位 type" && [ "$RC" = "1" ]; } \
  && pass "missing type produces ERROR + exit 1" || fail "missing type not caught (rc=$RC)"

# ── T3: invalid level → ERROR ──
echo ""
echo "T3: invalid level value → ERROR"
printf 'type: system\nlevel: 9\n' > "$(P)"; run
echo "$OUT" | grep -q "level 值無效" && pass "invalid level → ERROR" || fail "invalid level not caught"

# ── T4: invalid hitl → ERROR ──
echo ""
echo "T4: invalid hitl value → ERROR"
printf 'type: system\nhitl: bogus\n' > "$(P)"; run
echo "$OUT" | grep -q "hitl 值無效" && pass "invalid hitl → ERROR" || fail "invalid hitl not caught"

# ── T5: design:enabled w/o frontend_quality → WARNING + portable auto-fix ──
echo ""
echo "T5: design:enabled auto-adds frontend_quality right after design line (portable awk)"
printf 'type: system\ndesign: enabled\nlevel: 1\n' > "$(P)"; run
grep -q "^frontend_quality: enabled" "$(P)" && pass "auto-fix added frontend_quality" || fail "frontend_quality not auto-added"
awk '/^design:/{getline n; if (n=="frontend_quality: enabled") ok=1} END{exit !ok}' "$(P)" \
  && pass "frontend_quality inserted immediately after design (awk insert correct)" \
  || fail "frontend_quality not placed after design line"

# ── T6: idempotent — re-run does not duplicate frontend_quality ──
echo ""
echo "T6: re-run does not duplicate the auto-added field"
run
[ "$(grep -c '^frontend_quality: enabled' "$(P)")" = "1" ] && pass "no duplicate frontend_quality on re-run" || fail "frontend_quality duplicated"

# ── T7: fully valid profile → 驗證通過, exit 0 ──
echo ""
echo "T7: valid profile → pass, exit 0"
printf 'type: system\nlevel: 2\nhitl: standard\nmode: single\n' > "$(P)"; run
{ echo "$OUT" | grep -q "驗證通過" && [ "$RC" = "0" ]; } \
  && pass "valid profile passes with exit 0" || fail "valid profile not passing (rc=$RC)"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
