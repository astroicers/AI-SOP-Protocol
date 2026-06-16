#!/usr/bin/env bash
# test_l0_audit.sh — tests for .asp/scripts/l0-audit.sh (L0 Spike lifecycle
# audit; project graduation gating). Non-blocking diagnostic: must always exit 0.
# Run: bash tests/test_l0_audit.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/l0-audit.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-l0-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

mkproj() {
  rm -rf "${TEST_DIR:?}"; mkdir -p "$TEST_DIR"
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "t@test"; git -C "$TEST_DIR" config user.name "t"
}
OUT=""; RC=0
run() { OUT=$(bash "$SCRIPT" "$TEST_DIR" 2>&1); RC=$?; }

# ── T1: no .ai_profile → skip, exit 0 ──
echo ""
echo "T1: no .ai_profile → skip, exit 0"
mkproj; run
{ grep -q "not an ASP-governed" <<<"$OUT" && [ "$RC" = "0" ]; } \
  && pass "no profile → skip + exit 0" || fail "no-profile case wrong (rc=$RC)"

# ── T2: level != loose → not applicable, exit 0（v5：legacy 2 → standard）──
echo ""
echo "T2: non-loose project → not applicable, exit 0"
mkproj; printf 'type: system\nlevel: 2\n' > "$TEST_DIR/.ai_profile"; run
{ grep -q "not loose" <<<"$OUT" && [ "$RC" = "0" ]; } \
  && pass "non-loose → skip + exit 0" || fail "non-loose case wrong (rc=$RC)"
mkproj; printf 'type: system\nlevel: standard\n' > "$TEST_DIR/.ai_profile"; run
{ grep -q "not loose" <<<"$OUT" && [ "$RC" = "0" ]; } \
  && pass "named standard → skip + exit 0" || fail "named standard wrong (rc=$RC)"

# ── T2a: legacy level 0 與 named loose 均進入 audit ──
echo ""
echo "T2a: legacy 0 and named loose both enter audit"
mkproj; printf 'type: system\nlevel: loose\n' > "$TEST_DIR/.ai_profile"; run
grep -q "Level: loose" <<<"$OUT" && pass "level: loose enters audit" || fail "named loose not audited"

# ── T3: L0 + recent commit → Active ──
echo ""
echo "T3: L0 with a recent commit → diagnosed Active"
mkproj; printf 'type: system\nlevel: 0\n' > "$TEST_DIR/.ai_profile"
git -C "$TEST_DIR" add -A; git -C "$TEST_DIR" commit -q -m init
run
grep -q "Active" <<<"$OUT" && pass "L0 + recent commit → Active" || fail "Active not diagnosed"
[ "$RC" = "0" ] && pass "exit 0 (non-blocking)" || fail "non-zero exit (rc=$RC)"

# ── T4: L0 with no commits → zombie signal, still exit 0 ──
echo ""
echo "T4: L0 with no commit history → zombie signal, exit 0"
mkproj; printf 'type: system\nlevel: 0\n' > "$TEST_DIR/.ai_profile"
run
grep -qiE "zombie|0 commits" <<<"$OUT" && pass "L0 + no commits → zombie signal" || fail "zombie not flagged"
[ "$RC" = "0" ] && pass "still exit 0 with empty git history" || fail "non-zero exit on empty history (rc=$RC)"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
