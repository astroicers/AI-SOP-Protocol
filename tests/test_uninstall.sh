#!/usr/bin/env bash
# test_uninstall.sh — safety tests for .asp/scripts/uninstall.sh (destructive).
# Uses ONLY --dry-run (which must delete nothing) so the test itself is safe.
# Verifies: (1) dry-run removes nothing, (2) user content (.ai_profile, docs/)
# is NOT in the removal set (preserved).
# Run: bash tests/test_uninstall.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/uninstall.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-uninst-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

setup() {
  rm -rf "${TEST_DIR:?}"; mkdir -p "$TEST_DIR/.asp/hooks" "$TEST_DIR/.claude" "$TEST_DIR/docs/adr"
  git -C "$TEST_DIR" init -q   # uninstall.sh requires a git repo (safety guard)
  echo '{"hooks":{}}' > "$TEST_DIR/.claude/settings.json"
  echo 'include .asp/Makefile.inc' > "$TEST_DIR/Makefile"
  echo 'type: system' > "$TEST_DIR/.ai_profile"
  echo '# ADR-001 user content (must be preserved)' > "$TEST_DIR/docs/adr/ADR-001-x.md"
}

# ── T1: --dry-run --yes deletes nothing, exits 0, runs in dry mode ──
echo ""
echo "T1: dry-run is non-destructive (deletes nothing) and exits 0"
setup
OUT=$(cd "$TEST_DIR" && bash "$SCRIPT" --dry-run --yes 2>&1); RC=$?
[ "$RC" = "0" ] && pass "dry-run exits 0" || fail "dry-run exit code $RC"
grep -q "\[DRY\]" <<<"$OUT" && pass "ran in dry mode ([DRY] markers present)" || fail "no [DRY] markers — dry mode not active"
intact=1
for f in .asp .asp/hooks .claude/settings.json Makefile .ai_profile docs/adr/ADR-001-x.md; do
  [ -e "$TEST_DIR/$f" ] || { intact=0; echo "    deleted: $f"; }
done
[ "$intact" = "1" ] && pass "dry-run deleted NOTHING (all files intact)" || fail "dry-run DELETED files — non-destructive contract broken"

# ── T2: user content is NOT in the removal set (preserve guarantee) ──
echo ""
echo "T2: .ai_profile and docs/ are preserved (never marked for removal)"
if grep -qE "\[DRY\].*(\.ai_profile|docs/adr)" <<<"$OUT"; then
  fail "uninstall would remove user content (.ai_profile / docs/adr)"
else
  pass "user content (.ai_profile, docs/adr) not in removal set"
fi

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
