#!/usr/bin/env bash
# test_autopilot_targets.sh — TDD tests for autopilot Makefile targets
# Run: bash tests/test_autopilot_targets.sh
# All tests run in an isolated /tmp directory to avoid polluting the project.

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-autopilot-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# ── Helper: set up a minimal project with ASP ──
setup_project() {
  rm -rf "$TEST_DIR"/*
  mkdir -p "$TEST_DIR/.asp/templates" "$TEST_DIR/.asp/profiles" "$TEST_DIR/docs/adr"

  # Copy templates (they don't exist yet in TDD — create stubs)
  # The real templates will be created in Step 3. For now, create minimal stubs.
  if [ -f "$ASP_ROOT/.asp/templates/ROADMAP_Template.yaml" ]; then
    cp "$ASP_ROOT/.asp/templates/ROADMAP_Template.yaml" "$TEST_DIR/.asp/templates/"
  else
    cat > "$TEST_DIR/.asp/templates/ROADMAP_Template.yaml" <<'STUB'
version: "1.0"
project: PROJECT_NAME
milestones: []
STUB
  fi

  for tmpl in SRS_Template.md SDS_Template.md UIUX_SPEC_Template.md DEPLOY_SPEC_Template.md; do
    if [ -f "$ASP_ROOT/.asp/templates/$tmpl" ]; then
      cp "$ASP_ROOT/.asp/templates/$tmpl" "$TEST_DIR/.asp/templates/"
    else
      echo "# ${tmpl%.md} Template Stub" > "$TEST_DIR/.asp/templates/$tmpl"
    fi
  done

  # Copy Makefile.inc
  cp "$ASP_ROOT/.asp/Makefile.inc" "$TEST_DIR/.asp/Makefile.inc"

  # Create project Makefile
  cat > "$TEST_DIR/Makefile" <<'MK'
include .asp/Makefile.inc
MK
}

# ── Test runner ──
assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo "  ✅ $test_name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $test_name"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local test_name="$1" filepath="$2"
  TOTAL=$((TOTAL + 1))
  if [ -f "$filepath" ]; then
    echo "  ✅ $test_name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $test_name — file not found: $filepath"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local test_name="$1" filepath="$2"
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$filepath" ]; then
    echo "  ✅ $test_name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $test_name — file should not exist: $filepath"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -q "$needle"; then
    echo "  ✅ $test_name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $test_name — output does not contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo "  ✅ $test_name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $test_name — expected exit $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_nonzero() {
  local test_name="$1" actual="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$actual" -ne 0 ]; then
    echo "  ✅ $test_name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $test_name — expected non-zero exit, got 0"
    FAIL=$((FAIL + 1))
  fi
}

# ═══════════════════════════════════════
echo "🧪 Autopilot Makefile Targets Tests"
echo "═══════════════════════════════════════"
echo "  ASP_ROOT: $ASP_ROOT"
echo "  TEST_DIR: $TEST_DIR"
echo ""

# ── Test 1: make autopilot-init creates ROADMAP.yaml ──
echo "── Test 1: autopilot-init creates ROADMAP.yaml ──"
setup_project
output=$(cd "$TEST_DIR" && make autopilot-init 2>&1)
assert_file_exists "ROADMAP.yaml created" "$TEST_DIR/ROADMAP.yaml"
assert_output_contains "shows success message" "Created ROADMAP.yaml" "$output"

# ── Test 2: make autopilot-init (repeat) does not overwrite ──
echo "── Test 2: autopilot-init (repeat) warns ──"
echo "# user content" >> "$TEST_DIR/ROADMAP.yaml"
output=$(cd "$TEST_DIR" && make autopilot-init 2>&1)
assert_output_contains "shows warning" "already exists" "$output"
# Verify user content preserved
content=$(cat "$TEST_DIR/ROADMAP.yaml")
assert_output_contains "content preserved" "user content" "$content"

# ── Test 3: make autopilot-validate (valid ROADMAP) ──
echo "── Test 3: autopilot-validate (valid) ──"
setup_project
cat > "$TEST_DIR/ROADMAP.yaml" <<'YAML'
version: "1.0"
project: test-project
milestones:
  - id: M1
    title: "Test Milestone"
    tasks:
      - id: T001
        title: "Test task"
        type: NEW_FEATURE
        priority: 1
        depends_on: []
        status: pending
YAML
output=$(cd "$TEST_DIR" && make autopilot-validate 2>&1) && exit_code=0 || exit_code=$?
assert_exit_code "valid ROADMAP exits 0" "0" "$exit_code"
assert_output_contains "shows task count" "Tasks:" "$output"

# ── Test 4: make autopilot-validate (invalid dependency) ──
echo "── Test 4: autopilot-validate (invalid dependency) ──"
cat > "$TEST_DIR/ROADMAP.yaml" <<'YAML'
version: "1.0"
project: test-project
milestones:
  - id: M1
    title: "Test"
    tasks:
      - id: T001
        title: "Task 1"
        type: NEW_FEATURE
        priority: 1
        depends_on: [T999]
        status: pending
YAML
output=$(cd "$TEST_DIR" && make autopilot-validate 2>&1) && exit_code=0 || exit_code=$?
assert_exit_nonzero "invalid dep exits non-zero" "$exit_code"
assert_output_contains "shows error" "unknown" "$output"

# ── Test 5: make autopilot-validate (missing ADR reference) ──
echo "── Test 5: autopilot-validate (missing ADR) ──"
cat > "$TEST_DIR/ROADMAP.yaml" <<'YAML'
version: "1.0"
project: test-project
milestones:
  - id: M1
    title: "Test"
    tasks:
      - id: T001
        title: "Task 1"
        type: NEW_FEATURE
        priority: 1
        adr: ADR-999
        depends_on: []
        status: pending
YAML
output=$(cd "$TEST_DIR" && make autopilot-validate 2>&1) && exit_code=0 || exit_code=$?
assert_exit_nonzero "missing ADR exits non-zero" "$exit_code"
assert_output_contains "shows missing ADR" "missing" "$output"

# ── Test 6: make autopilot-validate (missing prerequisite doc) ──
echo "── Test 6: autopilot-validate (missing prerequisite doc) ──"
cat > "$TEST_DIR/ROADMAP.yaml" <<'YAML'
version: "1.0"
project: test-project
documents:
  srs: docs/SRS.md
milestones: []
YAML
output=$(cd "$TEST_DIR" && make autopilot-validate 2>&1) && exit_code=0 || exit_code=$?
# Missing doc should warn but may not fail (depends on implementation)
assert_output_contains "shows missing doc" "not found" "$output"

# ── Test 7: make autopilot-status (no state) ──
echo "── Test 7: autopilot-status (no state) ──"
setup_project
output=$(cd "$TEST_DIR" && make autopilot-status 2>&1)
assert_output_contains "shows not started" "not started" "$output"

# ── Test 8: make autopilot-status (with state) ──
echo "── Test 8: autopilot-status (with state) ──"
cat > "$TEST_DIR/.asp-autopilot-state.json" <<'JSON'
{
  "version": 1,
  "status": "in_progress",
  "session_count": 2,
  "total_tasks": 5,
  "current_task": "T003",
  "completed": ["T001", "T002"],
  "failed": [],
  "blocked": [],
  "exit_reason": "context_budget"
}
JSON
cat > "$TEST_DIR/ROADMAP.yaml" <<'YAML'
version: "1.0"
project: test-project
milestones:
  - id: M1
    title: "Test"
    tasks:
      - { id: T001, status: completed }
      - { id: T002, status: completed }
      - { id: T003, status: in_progress }
      - { id: T004, status: pending }
      - { id: T005, status: pending }
YAML
output=$(cd "$TEST_DIR" && make autopilot-status 2>&1)
assert_output_contains "shows status" "in_progress" "$output"
assert_output_contains "shows completed count" "2" "$output"

# ── Test 9: make autopilot-reset ──
echo "── Test 9: autopilot-reset ──"
output=$(cd "$TEST_DIR" && make autopilot-reset 2>&1)
assert_file_not_exists "state file deleted" "$TEST_DIR/.asp-autopilot-state.json"
assert_file_exists "ROADMAP preserved" "$TEST_DIR/ROADMAP.yaml"
assert_output_contains "shows cleared" "cleared" "$output"

# ── Test 10: make srs-new / sds-new / uiux-spec-new / deploy-spec-new ──
echo "── Test 10: document template targets ──"
setup_project

output=$(cd "$TEST_DIR" && make srs-new 2>&1)
assert_file_exists "SRS created" "$TEST_DIR/docs/SRS.md"
assert_output_contains "SRS success" "Created" "$output"

output=$(cd "$TEST_DIR" && make sds-new 2>&1)
assert_file_exists "SDS created" "$TEST_DIR/docs/SDS.md"

output=$(cd "$TEST_DIR" && make uiux-spec-new 2>&1)
assert_file_exists "UIUX_SPEC created" "$TEST_DIR/docs/UIUX_SPEC.md"

output=$(cd "$TEST_DIR" && make deploy-spec-new 2>&1)
assert_file_exists "DEPLOY_SPEC created" "$TEST_DIR/docs/DEPLOY_SPEC.md"

# ── Test 11: repeat doc targets don't overwrite ──
echo "── Test 11: repeat doc targets don't overwrite ──"
echo "# user SRS content" >> "$TEST_DIR/docs/SRS.md"
output=$(cd "$TEST_DIR" && make srs-new 2>&1)
assert_output_contains "SRS warns already exists" "already exists" "$output"
content=$(cat "$TEST_DIR/docs/SRS.md")
assert_output_contains "SRS content preserved" "user SRS content" "$content"

output=$(cd "$TEST_DIR" && make sds-new 2>&1)
assert_output_contains "SDS warns already exists" "already exists" "$output"

output=$(cd "$TEST_DIR" && make uiux-spec-new 2>&1)
assert_output_contains "UIUX warns already exists" "already exists" "$output"

output=$(cd "$TEST_DIR" && make deploy-spec-new 2>&1)
assert_output_contains "DEPLOY warns already exists" "already exists" "$output"

# ═══════════════════════════════════════
echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
