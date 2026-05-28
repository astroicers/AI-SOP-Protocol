#!/usr/bin/env bash
# test_spec_004_scope_guard.sh — SPEC-004 N2: scope-guard PreToolUse hook
#
# Covers:
#   S7: Worker 嘗試修改 scope.forbid 路徑 → 中止、exit 2、bypass log 寫入
#   S7b: Worker 嘗試修改 scope.allow 外的路徑 → 同樣被攔截
#   S7c: Worker 修改 scope.allow 內的路徑 → 正常允許
#   S7d: 無 manifest 時 guard 直接放行（fail-open for non-multi-agent sessions）
#
# Run: bash tests/test_spec_004_scope_guard.sh

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-spec004-scope-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

GUARD="$ASP_ROOT/.asp/scripts/multi-agent/scope-guard.sh"
BYPASS_LOG="$TEST_DIR/main-repo/.asp-bypass-log.ndjson"

# ── helpers ──

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local actual="$2"; local expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✅ $desc"; PASS=$((PASS + 1))
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
    echo "  ✅ $desc"; PASS=$((PASS + 1))
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
  if [ -f "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (missing: $path)"; FAIL=$((FAIL + 1)); fi
}

# Run scope-guard with a simulated tool_input (file path)
# Usage: run_guard <manifest_path> <file_path_being_written>
run_guard() {
  local manifest="$1"
  local file_path="$2"
  local stderr_file="$TEST_DIR/.stderr.$$"
  local stdout_file="$TEST_DIR/.stdout.$$"
  set +e
  ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
    ASP_TASK_MANIFEST="$manifest" \
    bash "$GUARD" "$file_path" \
      >"$stdout_file" 2>"$stderr_file"
  GUARD_RC=$?
  set -e
  GUARD_STDERR=$(cat "$stderr_file")
  GUARD_STDOUT=$(cat "$stdout_file")
  rm -f "$stderr_file" "$stdout_file"
}

# Setup minimal repo + manifest
setup_repo() {
  rm -rf "${TEST_DIR:?}"/*
  git init -q -b main "$TEST_DIR/main-repo"
  cd "$TEST_DIR/main-repo"
  git config user.email "test@test.local"
  git config user.name "test"
  mkdir -p src/store src/auth src/config
  echo "// store" > src/store/file.go
  echo "// auth"  > src/auth/login.go
  echo "// cfg"   > src/config/env.go
  git add -A && git commit -q -m "init"
  cd "$ASP_ROOT"
}

write_manifest() {
  local path="$1"; local task_id="$2"; local allow="$3"; local forbid="$4"
  cat > "$path" <<EOF
task_id: $task_id
agent: worker-a
agent_role: impl
scope:
  allow: [$allow]
  forbid: [$forbid]
worktree_branch: feat/spec-004-$(echo "$task_id" | tr '[:upper:]' '[:lower:]')
EOF
}

# ── Test 1: scope-guard.sh exists and is executable ──
echo "── Test 1: scope-guard.sh exists ──"
assert_file_exists "scope-guard.sh exists" "$GUARD"

# ── Test 2: S7 — forbid path blocked (exit 2, bypass log written) ──
echo "── Test 2: S7 — forbid path triggers exit 2 + bypass log ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/" "src/auth/"

run_guard "$TEST_DIR/manifests/TASK-001.yaml" "src/auth/login.go"

assert_eq "exit 2 on forbid violation" "$GUARD_RC" "2"
assert_contains "stderr mentions scope_violation" "$GUARD_STDERR" "scope_violation"
assert_file_exists "bypass log created" "$BYPASS_LOG"

BYPASS_ENTRY=$(tail -1 "$BYPASS_LOG" 2>/dev/null || echo "")
assert_contains "bypass log has reason=scope_violation" \
  "$BYPASS_ENTRY" '"reason":"scope_violation"'
assert_contains "bypass log has actor=worker-a" \
  "$BYPASS_ENTRY" '"actor":"worker-a"'
assert_contains "bypass log has task_id" \
  "$BYPASS_ENTRY" '"task_id":"TASK-001"'

# ── Test 3: S7b — path outside scope.allow (not in forbid) also blocked ──
echo "── Test 3: S7b — path outside allow blocked even if not in forbid ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/" ""

# src/config/ is neither in allow nor forbid → should be blocked
run_guard "$TEST_DIR/manifests/TASK-001.yaml" "src/config/env.go"

assert_eq "exit 2 on out-of-allow path" "$GUARD_RC" "2"
assert_contains "stderr mentions scope_violation" "$GUARD_STDERR" "scope_violation"

# ── Test 4: S7c — path inside scope.allow is permitted ──
echo "── Test 4: S7c — allowed path exits 0 ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/" "src/auth/"

run_guard "$TEST_DIR/manifests/TASK-001.yaml" "src/store/file.go"

assert_eq "exit 0 on allowed path" "$GUARD_RC" "0"

# ── Test 5: S7d — no manifest → fail-open (exit 0) ──
echo "── Test 5: S7d — no manifest → fail-open ──"
setup_repo

run_guard "/nonexistent/manifest.yaml" "src/auth/login.go"

assert_eq "exit 0 when no manifest (fail-open)" "$GUARD_RC" "0"

# ── Test 6: forbid takes precedence over allow ──
echo "── Test 6: forbid beats allow when both match ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
# Overlap: both allow and forbid include src/ (forbid should win)
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/" "src/auth/"

run_guard "$TEST_DIR/manifests/TASK-001.yaml" "src/auth/login.go"

assert_eq "exit 2: forbid takes precedence over allow" "$GUARD_RC" "2"

# ── Summary ──
echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ $FAIL -eq 0 ]
