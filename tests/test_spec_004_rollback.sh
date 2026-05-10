#!/usr/bin/env bash
# test_spec_004_rollback.sh — SPEC-004 §🔄 Rollback Plan + Done When #9
#
# Verifies rollback.sh:
#   - removes all in-flight worktrees
#   - deletes feat/spec-004-* branches
#   - leaves base branch HEAD unchanged
#   - keeps task manifests as forensic record
#   - emits multi_agent.rollback telemetry

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-rollback-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

DISPATCH="$ASP_ROOT/.asp/scripts/multi-agent/dispatch.sh"
ROLLBACK="$ASP_ROOT/.asp/scripts/multi-agent/rollback.sh"

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local actual="$2"; local expected="$3"
  if [ "$actual" = "$expected" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc"; echo "     expected: $expected"; echo "     actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

assert_dir_absent() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ ! -d "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (still exists: $path)"; FAIL=$((FAIL + 1)); fi
}

assert_file_exists() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ -f "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (missing: $path)"; FAIL=$((FAIL + 1)); fi
}

setup_dispatched() {
  rm -rf "${TEST_DIR:?}"/*
  unset ASP_AUDIT_ROOT 2>/dev/null || true
  git init -q -b main "$TEST_DIR/main-repo"
  cd "$TEST_DIR/main-repo"
  git config user.email t@t && git config user.name t
  mkdir -p src/store src/api src/auth
  echo s > src/store/x && echo a > src/api/x && echo u > src/auth/x
  git add -A && git commit -q -m init
  cd "$ASP_ROOT"

  mkdir -p "$TEST_DIR/manifests"
  for tid in TASK-001 TASK-002 TASK-003; do
    case "$tid" in
      TASK-001) scope="src/store/" ;;
      TASK-002) scope="src/api/"   ;;
      TASK-003) scope="src/auth/"  ;;
    esac
    cat > "$TEST_DIR/manifests/$tid.yaml" <<EOF
task_id: $tid
agent: worker-a
agent_role: impl
scope:
  allow: [$scope]
  forbid: []
worktree_branch: feat/spec-004-$(echo "$tid" | tr '[:upper:]' '[:lower:]')
EOF
  done

  cd "$TEST_DIR/main-repo"
  ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$DISPATCH" --manifests "$TEST_DIR/manifests" >/dev/null
  cd "$ASP_ROOT"
}

# ── Test 1: rollback removes all worktrees + branches, base unchanged ──
echo "── Test 1: rollback after 3-task dispatch ──"
setup_dispatched

# Snapshot base HEAD
BASE_BEFORE=$(cd "$TEST_DIR/main-repo" && git rev-parse main)

# Workers commit something on their branches (gives rollback real work to do)
for i in 1 2 3; do
  cd "$TEST_DIR/main-repo/.asp-worktrees/task-00$i"
  case "$i" in
    1) f="src/store/x" ;;
    2) f="src/api/x"   ;;
    3) f="src/auth/x"  ;;
  esac
  echo "modified by worker $i" > "$f"
  git add -A && git commit -q -m "worker $i in-flight"
done
cd "$ASP_ROOT"

# Rollback
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$ROLLBACK" >/dev/null

# Worktrees gone
assert_dir_absent "task-001 worktree removed" "$TEST_DIR/main-repo/.asp-worktrees/task-001"
assert_dir_absent "task-002 worktree removed" "$TEST_DIR/main-repo/.asp-worktrees/task-002"
assert_dir_absent "task-003 worktree removed" "$TEST_DIR/main-repo/.asp-worktrees/task-003"

# Branches gone
cd "$TEST_DIR/main-repo"
LEFTOVER=$(git branch --list 'feat/spec-004-*' | wc -l | tr -d ' ')
cd "$ASP_ROOT"
assert_eq "no feat/spec-004-* branches remain" "$LEFTOVER" "0"

# Base unchanged
BASE_AFTER=$(cd "$TEST_DIR/main-repo" && git rev-parse main)
assert_eq "base branch HEAD unchanged" "$BASE_AFTER" "$BASE_BEFORE"

# Manifests preserved (forensic record)
assert_file_exists "TASK-001 manifest preserved" "$TEST_DIR/main-repo/.asp-task-manifests/TASK-001.yaml"
assert_file_exists "TASK-002 manifest preserved" "$TEST_DIR/main-repo/.asp-task-manifests/TASK-002.yaml"
assert_file_exists "TASK-003 manifest preserved" "$TEST_DIR/main-repo/.asp-task-manifests/TASK-003.yaml"

# Telemetry recorded
TOTAL=$((TOTAL + 1))
if grep -q '"event":"multi_agent.rollback"' "$TEST_DIR/main-repo/.asp-telemetry.ndjson" 2>/dev/null; then
  echo "  ✅ rollback telemetry recorded"; PASS=$((PASS + 1))
else
  echo "  ❌ rollback telemetry missing"; FAIL=$((FAIL + 1))
fi

# ── Test 2: rollback --dry-run does NOT modify state ──
echo "── Test 2: --dry-run leaves everything in place ──"
setup_dispatched
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$ROLLBACK" --dry-run >/dev/null

# Worktrees still there
TOTAL=$((TOTAL + 1))
if [ -d "$TEST_DIR/main-repo/.asp-worktrees/task-001" ]; then
  echo "  ✅ worktree preserved on dry-run"; PASS=$((PASS + 1))
else
  echo "  ❌ worktree removed despite dry-run"; FAIL=$((FAIL + 1))
fi

# Branches still there
cd "$TEST_DIR/main-repo"
B_COUNT=$(git branch --list 'feat/spec-004-*' | wc -l | tr -d ' ')
cd "$ASP_ROOT"
assert_eq "branches preserved on dry-run" "$B_COUNT" "3"

# ── Test 3: rollback on empty repo → exit 0, no error ──
echo "── Test 3: rollback when nothing to roll back ──"
rm -rf "${TEST_DIR:?}"/*
git init -q -b main "$TEST_DIR/main-repo"
cd "$TEST_DIR/main-repo" && git config user.email t@t && git config user.name t
echo init > x && git add x && git commit -q -m init && cd "$ASP_ROOT"

set +e
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$ROLLBACK" >/dev/null 2>&1
RC=$?
set -e
assert_eq "exit 0 when nothing to roll back" "$RC" "0"

# ── Test 4: ASP_AUDIT_ROOT validation ──
echo "── Test 4: rollback rejects unset ASP_AUDIT_ROOT ──"
unset ASP_AUDIT_ROOT
set +e
bash "$ROLLBACK" >/dev/null 2>&1
RC=$?
set -e
assert_eq "exit 7 on unset ASP_AUDIT_ROOT" "$RC" "7"

# ── Test 5: rollback after partial converge — base must NOT regress ──
echo "── Test 5: rollback after partial converge keeps merged tasks ──"
setup_dispatched

# Worker 1 commits and we converge it (so its merge is on base)
cd "$TEST_DIR/main-repo/.asp-worktrees/task-001"
echo "task1 work" > src/store/x
git add -A && git commit -q -m "task1 done"
cd "$ASP_ROOT"
cd "$TEST_DIR/main-repo"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$ASP_ROOT/.asp/scripts/multi-agent/converge.sh" --task TASK-001 >/dev/null
cd "$ASP_ROOT"

BASE_AFTER_CONVERGE=$(cd "$TEST_DIR/main-repo" && git rev-parse main)

# Now rollback the remaining (task-002 + task-003 still in flight)
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$ROLLBACK" >/dev/null

# Base HEAD must still be at "after converge of task-001" (NOT regressed
# to before-dispatch). Rollback only discards in-flight work.
BASE_AFTER_ROLLBACK=$(cd "$TEST_DIR/main-repo" && git rev-parse main)
assert_eq "base HEAD preserved at post-converge state" "$BASE_AFTER_ROLLBACK" "$BASE_AFTER_CONVERGE"

# task-001 branch was already deleted by converge; task-002/003 should be gone
cd "$TEST_DIR/main-repo"
LEFTOVER=$(git branch --list 'feat/spec-004-*' | wc -l | tr -d ' ')
cd "$ASP_ROOT"
assert_eq "in-flight branches cleared" "$LEFTOVER" "0"

# ── Summary ──
echo ""
echo "═══════════════════════════════════════"
echo "  rollback Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ $FAIL -eq 0 ]
