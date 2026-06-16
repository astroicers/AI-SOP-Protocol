#!/usr/bin/env bash
# test_install_precheck.sh — SPEC-004 Done When #13: install.sh runtime precheck
#
# Tests precheck_runtime() in isolation by sourcing the helpers from install.sh
# and stubbing each binary via PATH manipulation. We don't run the full
# install.sh because that would touch ~/.claude/.

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-precheck-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

INSTALL="$ASP_ROOT/.asp/scripts/install.sh"

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local actual="$2"; local expected="$3"
  if [ "$actual" = "$expected" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc"; echo "     expected: $expected"; echo "     actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

assert_contains() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local haystack="$2"; local needle="$3"
  if grep -qF "$needle" <<<"$haystack"; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc"; echo "     haystack: $haystack"; echo "     needle:   $needle"; FAIL=$((FAIL + 1)); fi
}

# ── extract version_at_least + precheck_runtime into a sourceable file ──
# We grep the function definitions out of install.sh so the test stays in
# sync with whatever the script actually defines. If install.sh refactors,
# this still works.
HELPERS="$TEST_DIR/helpers.sh"
{
    echo 'set +e'
    echo 'GREEN=""; YELLOW=""; NC=""'  # silence color codes
    echo 'success() { echo "  [ok] $1"; }'
    echo 'warn()    { echo "  [warn] $1" >&2; }'
    awk '/^version_at_least\(\)/,/^}/' "$INSTALL"
    echo ""
    awk '/^precheck_runtime\(\)/,/^}/' "$INSTALL"
} > "$HELPERS"

run_precheck() {
    local stderr_file="$TEST_DIR/.stderr.$$"
    local stdout_file="$TEST_DIR/.stdout.$$"
    local custom_path="${1:-$PATH}"
    set +e
    # `env -i` strips the inherited environment so PATH in -c body really
    # is the only PATH precheck_runtime sees. We add HOME back because some
    # tools (python3) resolve user paths from it.
    env -i HOME="$HOME" PATH="$custom_path" \
        ASP_SKIP_PRECHECK="${ASP_SKIP_PRECHECK:-}" \
        bash -c ". '$HELPERS' && precheck_runtime" \
        >"$stdout_file" 2>"$stderr_file"
    local rc=$?
    set -e
    PRECHECK_RC=$rc
    PRECHECK_STDERR=$(cat "$stderr_file")
    PRECHECK_STDOUT=$(cat "$stdout_file")
    rm -f "$stderr_file" "$stdout_file"
}

# ── Test 1: version_at_least edge cases ──
echo "── Test 1: version_at_least correctness ──"
make_version_test() {
    local desc="$1"; local req="$2"; local actual="$3"; local expect_pass="$4"
    set +e
    bash -c ". '$HELPERS' && version_at_least '$req' '$actual'"
    local rc=$?
    set -e
    if [ "$expect_pass" = "yes" ]; then
        assert_eq "$desc" "$rc" "0"
    else
        TOTAL=$((TOTAL + 1))
        if [ "$rc" -ne 0 ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
        else echo "  ❌ $desc (expected non-zero, got $rc)"; FAIL=$((FAIL + 1)); fi
    fi
}
make_version_test "2.20 ≤ 2.34.1"     "2.20"  "2.34.1" yes
make_version_test "2.20 ≤ 2.20"       "2.20"  "2.20"   yes
make_version_test "2.20 ≤ 3.0"        "2.20"  "3.0"    yes
make_version_test "2.20 > 2.19"       "2.20"  "2.19"   no
make_version_test "2.20 > 2.10"       "2.20"  "2.10"   no
make_version_test "2.20 > 1.9"        "2.20"  "1.9"    no
make_version_test "1.6 ≤ 1.6"         "1.6"   "1.6"    yes
make_version_test "3.10 > 3.9"        "3.10"  "3.9"    no
make_version_test "3.10 ≤ 3.10"       "3.10"  "3.10"   yes

# Save real PATH for restoring binaries
REAL_PATH="$PATH"

# For Tests 2/3 we need a PATH that has bash itself (the test wrapper) but
# nothing else. Symlinking bash to a clean dir avoids the "git/jq/bash share
# /usr/bin" problem on most distros.
BASH_ONLY="$TEST_DIR/bash-only"
mkdir -p "$BASH_ONLY"
ln -sf "$(command -v bash)" "$BASH_ONLY/bash"
BASH_DIR="$BASH_ONLY"

# ── Test 2: ASP_SKIP_PRECHECK=1 bypasses everything ──
echo "── Test 2: ASP_SKIP_PRECHECK=1 bypass ──"
ASP_SKIP_PRECHECK=1 run_precheck "$BASH_DIR"
unset ASP_SKIP_PRECHECK
assert_eq "exit 0 with skip flag even when nothing installed" "$PRECHECK_RC" "0"
assert_contains "warning printed" "$PRECHECK_STDERR" "ASP_SKIP_PRECHECK=1"

# ── Test 3: missing binary → exit 13 ──
echo "── Test 3: missing tool → exit 13 ──"
run_precheck "$BASH_DIR"
assert_eq "exit 13 when no binaries" "$PRECHECK_RC" "13"
assert_contains "error mentions runtime requirement" "$PRECHECK_STDERR" "runtime requirement"

# ── Test 4: outdated git rejected via stub ──
echo "── Test 4: too-old git → exit 13 ──"
STUB_DIR="$TEST_DIR/stubs"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/git" <<'EOF'
#!/bin/sh
[ "$1" = "--version" ] && echo "git version 2.10.0"
EOF
chmod +x "$STUB_DIR/git"

# Stub PATH: stubs first, then real PATH so other binaries still work
run_precheck "$STUB_DIR:$REAL_PATH"
assert_eq "exit 13 when git too old" "$PRECHECK_RC" "13"
assert_contains "error names git version" "$PRECHECK_STDERR" "git 2.10"

# ── Test 5: outdated jq rejected via stub ──
echo "── Test 5: too-old jq → exit 13 ──"
cat > "$STUB_DIR/jq" <<'EOF'
#!/bin/sh
[ "$1" = "--version" ] && echo "jq-1.5"
EOF
chmod +x "$STUB_DIR/jq"
rm "$STUB_DIR/git"

run_precheck "$STUB_DIR:$REAL_PATH"
assert_eq "exit 13 when jq too old" "$PRECHECK_RC" "13"
assert_contains "error names jq version" "$PRECHECK_STDERR" "jq 1.5"

# ── Test 6: all real binaries on host → pass ──
echo "── Test 6: real environment passes ──"
rm -f "$STUB_DIR"/*
run_precheck "$REAL_PATH"
assert_eq "exit 0 on real environment" "$PRECHECK_RC" "0"
assert_contains "git ok line printed" "$PRECHECK_STDOUT" "git "
assert_contains "bash ok line printed" "$PRECHECK_STDOUT" "bash "
assert_contains "jq ok line printed" "$PRECHECK_STDOUT" "jq "
assert_contains "python3 ok line printed" "$PRECHECK_STDOUT" "python3 "

# ── Summary ──
echo ""
echo "═══════════════════════════════════════"
echo "  precheck Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ $FAIL -eq 0 ]
