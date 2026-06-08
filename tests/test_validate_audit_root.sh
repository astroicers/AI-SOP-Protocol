#!/usr/bin/env bash
# test_validate_audit_root.sh — tests for _validate_audit_root.sh (SPEC-004
# ASP_AUDIT_ROOT validation; Iron Rule B audit-trail integrity).
#
# ADR-010 Pattern B (human-approved 2026-06-08): a git WORKTREE must be REJECTED
# as ASP_AUDIT_ROOT. A worktree's .git is a FILE and its --git-dir differs from
# --git-common-dir; audit NDJSON written there is silently destroyed by
# `git worktree remove --force`, breaking Iron Rule B. The old Stage D shortcut
# (`[ ! -e .git ]`) wrongly passed worktrees.
# Run: bash tests/test_validate_audit_root.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ASP_ROOT/.asp/scripts/multi-agent/_validate_audit_root.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-var-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# shellcheck source=/dev/null
source "$SRC"

# run validate_audit_root in a subshell with controlled env; echo its rc
check() {  # $1=ASP_AUDIT_ROOT (empty string → unset)  $2=override(optional)
  (
    if [ -n "$1" ]; then export ASP_AUDIT_ROOT="$1"; else unset ASP_AUDIT_ROOT; fi
    if [ -n "${2:-}" ]; then export ASP_ALLOW_WORKTREE_AUDIT_ROOT="$2"; else unset ASP_ALLOW_WORKTREE_AUDIT_ROOT 2>/dev/null || true; fi
    validate_audit_root >/dev/null 2>&1; echo $?
  )
}

# ── build a main repo + a linked worktree ──
MAIN="$TEST_DIR/main"
WT="$TEST_DIR/wt"
mkdir -p "$MAIN"
git -C "$MAIN" init -q
git -C "$MAIN" config user.email "t@test"; git -C "$MAIN" config user.name "t"
echo x > "$MAIN/f"; git -C "$MAIN" add -A; git -C "$MAIN" commit -q -m init
git -C "$MAIN" worktree add -q "$WT" -b wtbranch 2>/dev/null

echo ""
echo "main .git is a $( [ -d "$MAIN/.git" ] && echo directory || echo other ); worktree .git is a $( [ -f "$WT/.git" ] && echo file || echo other )"

# ── T1: main repo → pass (0) ──
echo ""
echo "T1: main repo as ASP_AUDIT_ROOT → pass"
[ "$(check "$MAIN")" = "0" ] && pass "main repo accepted" || fail "main repo wrongly rejected"

# ── T2: worktree → reject (7)  [the bug] ──
echo ""
echo "T2: git WORKTREE as ASP_AUDIT_ROOT → MUST reject (exit 7)"
[ "$(check "$WT")" = "7" ] && pass "worktree rejected (Iron Rule B protected)" || fail "worktree WRONGLY accepted — audit trail can be silently destroyed"

# ── T3: worktree + override → pass (0) ──
echo ""
echo "T3: worktree + ASP_ALLOW_WORKTREE_AUDIT_ROOT=1 → pass (explicit override)"
[ "$(check "$WT" "1")" = "0" ] && pass "override allows worktree" || fail "override did not work"

# ── T4: non-git directory → reject ──
echo ""
echo "T4: non-git directory → reject (7)"
mkdir -p "$TEST_DIR/plain"
[ "$(check "$TEST_DIR/plain")" = "7" ] && pass "non-git dir rejected" || fail "non-git dir accepted"

# ── T5: unset → reject ──
echo ""
echo "T5: unset ASP_AUDIT_ROOT → reject (7)"
[ "$(check "")" = "7" ] && pass "unset rejected" || fail "unset accepted"

# ── T6: relative path → reject ──
echo ""
echo "T6: relative path → reject (7)"
[ "$(check "relative/path")" = "7" ] && pass "relative path rejected" || fail "relative path accepted"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
