#!/usr/bin/env bash
# test_spec_004_audit_write.sh — SPEC-004 B1: ASP_AUDIT_ROOT fail-safe wrapper
#
# Covers SPEC-004 test matrix:
#   N7: ASP_AUDIT_ROOT 未設定 → reject (exit 7)
#   N8: ASP_AUDIT_ROOT 非絕對路徑 / 不存在 / 非 git repo → reject (exit 7)
#   S15: 正向 — Worker 在 worktree 中寫 audit log，落地到主 repo
#   S20: dispatch 階段 ASP_AUDIT_ROOT 未設定拒絕（含 stderr 訊息）
#   S21: dispatch 階段 ASP_AUDIT_ROOT 4 種無效值拒絕
#
# Run: bash tests/test_spec_004_audit_write.sh

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-spec004-b1-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

WRAPPER="$ASP_ROOT/.asp/scripts/multi-agent/audit-write.sh"
VALIDATOR="$ASP_ROOT/.asp/scripts/multi-agent/_validate_audit_root.sh"

# ── helpers ────────────────────────────────────────────────────────────

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local actual="$2"; local expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local haystack="$2"; local needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc"
    echo "     haystack: $haystack"
    echo "     needle:   $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ -f "$path" ]; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc (missing: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_absent() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ ! -e "$path" ]; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc (file exists: $path)"
    FAIL=$((FAIL + 1))
  fi
}

# Run wrapper, capture exit code + stderr
run_wrapper() {
  local stderr_file="$TEST_DIR/.stderr.$$"
  set +e
  bash "$WRAPPER" "$@" 2>"$stderr_file"
  local rc=$?
  set -e
  WRAPPER_RC=$rc
  WRAPPER_STDERR=$(cat "$stderr_file")
  rm -f "$stderr_file"
}

# Setup: a real git repo we can use as ASP_AUDIT_ROOT
setup_repo() {
  rm -rf "$TEST_DIR"/*
  unset ASP_AUDIT_ROOT 2>/dev/null || true
  git init -q "$TEST_DIR/main-repo"
  cd "$TEST_DIR/main-repo"
  git config user.email "test@test.local"
  git config user.name "test"
  echo "init" > README.md
  git add README.md
  git commit -q -m "init"
  cd "$ASP_ROOT"
}

# ── Tests ──────────────────────────────────────────────────────────────

# Test 1: wrapper exists and is executable
echo "── Test 1: wrapper file exists ──"
assert_file_exists "audit-write.sh exists" "$WRAPPER"
assert_file_exists "_validate_audit_root.sh exists" "$VALIDATOR"

# Test 2: N7 — ASP_AUDIT_ROOT 未設定
echo "── Test 2: N7 — ASP_AUDIT_ROOT unset rejected ──"
setup_repo
unset ASP_AUDIT_ROOT
run_wrapper bypass '{"actor":"test"}'
assert_eq "exit code 7 when unset" "$WRAPPER_RC" "7"
assert_contains "stderr mentions ASP_AUDIT_ROOT must be set" "$WRAPPER_STDERR" "ASP_AUDIT_ROOT must be set"

# Test 3: N8a — ASP_AUDIT_ROOT 為空字串
echo "── Test 3: N8a — empty string rejected ──"
setup_repo
ASP_AUDIT_ROOT="" run_wrapper bypass '{"actor":"test"}'
assert_eq "exit 7 on empty string" "$WRAPPER_RC" "7"
assert_contains "stderr mentions must be set" "$WRAPPER_STDERR" "ASP_AUDIT_ROOT must be set"

# Test 4: N8b — 相對路徑
echo "── Test 4: N8b — relative path rejected ──"
setup_repo
ASP_AUDIT_ROOT="." run_wrapper bypass '{"actor":"test"}'
assert_eq "exit 7 on '.'" "$WRAPPER_RC" "7"
assert_contains "stderr mentions absolute path" "$WRAPPER_STDERR" "absolute path"

ASP_AUDIT_ROOT="../some-rel" run_wrapper bypass '{"actor":"test"}'
assert_eq "exit 7 on '../some-rel'" "$WRAPPER_RC" "7"
assert_contains "stderr mentions absolute path again" "$WRAPPER_STDERR" "absolute path"

# Test 5: N8c — 路徑不存在
echo "── Test 5: N8c — non-existent path rejected ──"
setup_repo
ASP_AUDIT_ROOT="/tmp/spec-004-does-not-exist-$$" run_wrapper bypass '{"actor":"test"}'
assert_eq "exit 7 on missing path" "$WRAPPER_RC" "7"
assert_contains "stderr mentions path not found" "$WRAPPER_STDERR" "path not found"

# Test 6: N8d — 路徑存在但非 git repo
echo "── Test 6: N8d — non-git directory rejected ──"
setup_repo
mkdir -p "$TEST_DIR/not-a-repo"
ASP_AUDIT_ROOT="$TEST_DIR/not-a-repo" run_wrapper bypass '{"actor":"test"}'
assert_eq "exit 7 on non-git dir" "$WRAPPER_RC" "7"
assert_contains "stderr mentions not a git repo" "$WRAPPER_STDERR" "not a git repo"

# Test 7: S15 happy path — write bypass entry to main repo
echo "── Test 7: S15 — bypass log writes to main repo (not worktree) ──"
setup_repo
# Simulate Worker context: cwd is in worktree, ASP_AUDIT_ROOT points to main repo
mkdir -p "$TEST_DIR/main-repo/.asp-worktrees/task-001"
cd "$TEST_DIR/main-repo/.asp-worktrees/task-001"

ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_wrapper bypass '{"actor":"worker-a","reason":"scope_violation"}'
cd "$ASP_ROOT"

assert_eq "exit 0 on valid call" "$WRAPPER_RC" "0"
assert_file_exists "main repo bypass log created" "$TEST_DIR/main-repo/.asp-bypass-log.ndjson"
assert_file_absent "worktree bypass log NOT created" "$TEST_DIR/main-repo/.asp-worktrees/task-001/.asp-bypass-log.ndjson"

# Test 8: S15 — telemetry log also writes to main repo
echo "── Test 8: S15 — telemetry log writes to main repo ──"
setup_repo
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_wrapper telemetry '{"event":"multi_agent.dispatch","task_id":"TASK-001"}'
assert_eq "exit 0 on telemetry write" "$WRAPPER_RC" "0"
assert_file_exists "main repo telemetry log created" "$TEST_DIR/main-repo/.asp-telemetry.ndjson"

# Test 9: S15 — append-only (multiple writes accumulate)
echo "── Test 9: S15 — append-only behavior ──"
setup_repo
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_wrapper bypass '{"n":1}'
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_wrapper bypass '{"n":2}'
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_wrapper bypass '{"n":3}'
LINE_COUNT=$(wc -l < "$TEST_DIR/main-repo/.asp-bypass-log.ndjson" 2>/dev/null | tr -d ' ' || echo 0)
assert_eq "3 entries appended" "${LINE_COUNT:-0}" "3"

# Test 10: argument validation — unknown log type rejected
echo "── Test 10: unknown log type rejected ──"
setup_repo
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_wrapper unknown_type '{"x":1}'
assert_eq "exit non-zero on unknown log type" "$([ "$WRAPPER_RC" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# Test 11: argument validation — missing JSON payload
echo "── Test 11: missing payload rejected ──"
setup_repo
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_wrapper bypass
assert_eq "exit non-zero on missing payload" "$([ "$WRAPPER_RC" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# Test 12: validator script can be sourced (used by dispatch.sh too)
echo "── Test 12: validator can be sourced for reuse in dispatch.sh ──"
setup_repo
set +e
(
  ASP_AUDIT_ROOT="$TEST_DIR/main-repo"
  # shellcheck source=/dev/null
  . "$VALIDATOR"
  validate_audit_root  # should be defined as a function
)
SOURCE_RC=$?
set -e
assert_eq "validator function callable when sourced" "$SOURCE_RC" "0"

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  B1 Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ $FAIL -eq 0 ]
