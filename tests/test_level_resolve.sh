#!/usr/bin/env bash
# test_level_resolve.sh — tests for .asp/scripts/level-resolve.sh
# (v5 Phase 1, ADR-014: numeric level → named level central mapping with
# deprecation notice; data source = profile-map.yaml level_aliases).
# Run: bash tests/test_level_resolve.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/level-resolve.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-lr-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# ── T1: 6 numeric mappings ──
echo ""
echo "T1: numeric → name mappings (0,1→loose / 2,3→standard / 4,5→autonomous)"
declare -A EXPECT=( [0]=loose [1]=loose [2]=standard [3]=standard [4]=autonomous [5]=autonomous )
for n in 0 1 2 3 4 5; do
  OUT=$(bash "$SCRIPT" "$n" 2>/dev/null); RC=$?
  [ "$RC" = "0" ] && [ "$OUT" = "${EXPECT[$n]}" ] \
    && pass "level $n → ${EXPECT[$n]}" || fail "level $n → '$OUT' (rc=$RC, want ${EXPECT[$n]})"
done

# ── T2: numeric input prints deprecation to stderr, name only on stdout ──
echo ""
echo "T2: deprecation notice on stderr for numeric input"
ERR=$(bash "$SCRIPT" 3 2>&1 >/dev/null)
echo "$ERR" | grep -q "DEPRECATED" && pass "stderr contains DEPRECATED" || fail "no DEPRECATED in stderr: $ERR"
echo "$ERR" | grep -q "v6" && pass "stderr mentions v6 removal" || fail "no v6 mention"
OUT=$(bash "$SCRIPT" 3 2>/dev/null)
[ "$OUT" = "standard" ] && pass "stdout is clean name only" || fail "stdout polluted: '$OUT'"

# ── T3: name passthrough, no notice ──
echo ""
echo "T3: named values pass through silently"
for name in loose standard autonomous; do
  OUT=$(bash "$SCRIPT" "$name" 2>"$TEST_DIR/err"); RC=$?
  [ "$RC" = "0" ] && [ "$OUT" = "$name" ] && [ ! -s "$TEST_DIR/err" ] \
    && pass "$name → $name (silent)" || fail "$name → '$OUT' rc=$RC stderr=$(cat "$TEST_DIR/err")"
done

# ── T4: invalid value → exit 1 ──
echo ""
echo "T4: invalid value → exit 1"
bash "$SCRIPT" "9" >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && pass "level 9 → exit 1" || fail "level 9 rc=$RC"
bash "$SCRIPT" "bogus" >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && pass "bogus → exit 1" || fail "bogus rc=$RC"

# ── T5: no arg → read ./.ai_profile; missing level → exit 2 ──
echo ""
echo "T5: argless mode reads .ai_profile"
cd "$TEST_DIR" || exit 1
printf 'type: system\nlevel: 4\n' > .ai_profile
OUT=$(bash "$SCRIPT" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && [ "$OUT" = "autonomous" ] && pass ".ai_profile level: 4 → autonomous" || fail "got '$OUT' rc=$RC"
printf 'type: system\n' > .ai_profile
OUT=$(bash "$SCRIPT" 2>/dev/null); RC=$?
[ "$RC" = "2" ] && [ -z "$OUT" ] && pass "missing level field → exit 2, empty stdout" || fail "rc=$RC out='$OUT'"
cd "$ASP_ROOT" || exit 1

# ── T6: map missing → builtin fallback still correct ──
echo ""
echo "T6: profile-map missing → builtin fallback"
OUT=$(ASP_PROFILE_MAP="$TEST_DIR/nonexistent.yaml" bash "$SCRIPT" 5 2>"$TEST_DIR/err"); RC=$?
[ "$RC" = "0" ] && [ "$OUT" = "autonomous" ] && pass "fallback maps 5 → autonomous" || fail "fallback got '$OUT' rc=$RC"
grep -q "fallback" "$TEST_DIR/err" && pass "fallback warning on stderr" || fail "no fallback warning"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
