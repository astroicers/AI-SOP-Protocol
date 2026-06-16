#!/usr/bin/env bash
# tests/lib/common.sh — shared test helpers (DRY for tests/test_*.sh).
#
# Sourced near the top of each test:
#     source "$(dirname "$0")/lib/common.sh"
#
# Provides the boilerplate that was previously copy-pasted into every test:
#   - PASS / FAIL / TOTAL counters (read them directly for custom summaries)
#   - pass() / fail()  — tally + print a ✅/❌ line
#   - mk_test_dir()    — mktemp -d + auto-cleanup trap, sets $TEST_DIR
#
# Lives under tests/lib/ (NOT tests/) on purpose: the `make test` runner and
# the shellcheck lint both glob `tests/*.sh`, which does not recurse, so this
# helper is never executed as a standalone test nor double-counted.

# Counters. Callers may print their own summary using these.
PASS=0; FAIL=0; TOTAL=0

pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# mk_test_dir [name] — create a temp dir and remove it on EXIT.
# Sets $TEST_DIR. Default name fragment is the test file's basename.
mk_test_dir() {
  local name="${1:-$(basename "${0:-asp-test}" .sh)}"
  TEST_DIR=$(mktemp -d "/tmp/${name}-XXXXXX")
  trap 'rm -rf "$TEST_DIR"' EXIT
}
