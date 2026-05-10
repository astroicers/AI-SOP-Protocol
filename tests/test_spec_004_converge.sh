#!/usr/bin/env bash
# test_spec_004_converge.sh — SPEC-004 B3: converge.sh
#
# Covers:
#   P3: task 完成後 cleanup → worktree 移除、branch 保留
#   P4/S4: 三軌序列 converge 無衝突 → base 上 3 個 merge commit
#   N3/S8: task-vs-task merge 衝突 → exit 3 + escalation reason=task_merge_conflict
#          + 部分成功（TASK-001 已 merge，TASK-002 失敗）
#   B5/S14: base_branch 並行 commit + task branch 同檔案衝突 →
#           rebase 失敗 → exit 3 + escalation reason=base_branch_rebase_conflict
#   P5: telemetry — multi_agent.converge / multi_agent.fail 事件記錄
#
# Run: bash tests/test_spec_004_converge.sh

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-spec004-b3-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

DISPATCH="$ASP_ROOT/.asp/scripts/multi-agent/dispatch.sh"
CONVERGE="$ASP_ROOT/.asp/scripts/multi-agent/converge.sh"

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local actual="$2"; local expected="$3"
  if [ "$actual" = "$expected" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc"; echo "     expected: $expected"; echo "     actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

assert_contains() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local haystack="$2"; local needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc"; echo "     haystack: $haystack"; echo "     needle:   $needle"; FAIL=$((FAIL + 1)); fi
}

assert_file_exists() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ -f "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (missing: $path)"; FAIL=$((FAIL + 1)); fi
}

assert_dir_absent() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ ! -d "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (still exists: $path)"; FAIL=$((FAIL + 1)); fi
}

run_converge() {
  local stderr_file="$TEST_DIR/.stderr.$$"
  set +e
  bash "$CONVERGE" "$@" 2>"$stderr_file"
  local rc=$?
  set -e
  CONVERGE_RC=$rc
  CONVERGE_STDERR=$(cat "$stderr_file")
  rm -f "$stderr_file"
}

# Setup helpers ────────────────────────────────────────────────────────

# Initialize repo + dispatch a set of non-overlapping tasks. After this,
# worktrees exist with empty branches ready for Worker work.
setup_dispatched_repo() {
  rm -rf "$TEST_DIR"/*
  unset ASP_AUDIT_ROOT 2>/dev/null || true
  git init -q -b main "$TEST_DIR/main-repo"
  cd "$TEST_DIR/main-repo"
  git config user.email "test@test.local"
  git config user.name "test"
  mkdir -p src/store src/api src/auth src/shared
  echo "package store"  > src/store/file.go
  echo "package api"    > src/api/file.go
  echo "package auth"   > src/auth/file.go
  echo "shared line A"  > src/shared/util.go
  git add -A
  git commit -q -m "init"
  cd "$ASP_ROOT"
}

write_manifest() {
  local path="$1"; local task_id="$2"; local allow="$3"
  cat > "$path" <<EOF
task_id: $task_id
agent: worker-a
agent_role: impl
scope:
  allow: [$allow]
  forbid: []
worktree_branch: feat/spec-004-$(echo "$task_id" | tr '[:upper:]' '[:lower:]')
EOF
}

# Simulate Worker work: cd into worktree, modify a file, commit
worker_commit() {
  local worktree_dir="$1"; local file_path="$2"; local content="$3"; local msg="$4"
  cd "$worktree_dir"
  printf '%s\n' "$content" > "$file_path"
  git add "$file_path"
  git commit -q -m "$msg"
  cd "$ASP_ROOT"
}

# ── Test 1: converge.sh exists ──
echo "── Test 1: converge.sh exists ──"
assert_file_exists "converge.sh exists" "$CONVERGE"

# ── Test 2: P4/S4 — three sequential converges, no conflicts ──
echo "── Test 2: P4/S4 — three sequential converges, no conflicts ──"
setup_dispatched_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/"
write_manifest "$TEST_DIR/manifests/TASK-002.yaml" "TASK-002" "src/api/"
write_manifest "$TEST_DIR/manifests/TASK-003.yaml" "TASK-003" "src/auth/"

cd "$TEST_DIR/main-repo"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$DISPATCH" --manifests "$TEST_DIR/manifests" >/dev/null
cd "$ASP_ROOT"

# Each Worker makes a non-conflicting change in its own scope
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-001" "src/store/file.go" "package store // task1" "task1 change"
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-002" "src/api/file.go" "package api // task2" "task2 change"
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-003" "src/auth/file.go" "package auth // task3" "task3 change"

cd "$TEST_DIR/main-repo"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_converge --task TASK-001 --task TASK-002 --task TASK-003
cd "$ASP_ROOT"

assert_eq "exit 0 on 3-task converge" "$CONVERGE_RC" "0"

# Verify base has 3 merge commits
cd "$TEST_DIR/main-repo"
MERGE_COUNT=$(git log --merges --oneline main | wc -l | tr -d ' ')
cd "$ASP_ROOT"
assert_eq "main branch has 3 merge commits" "$MERGE_COUNT" "3"

# ── Test 3: P3 — cleanup after converge: worktrees removed, branches kept ──
echo "── Test 3: P3 — converge cleanup: worktrees gone, branches preserved ──"
# Continuing from Test 2 state
assert_dir_absent "task-001 worktree removed" "$TEST_DIR/main-repo/.asp-worktrees/task-001"
assert_dir_absent "task-002 worktree removed" "$TEST_DIR/main-repo/.asp-worktrees/task-002"
assert_dir_absent "task-003 worktree removed" "$TEST_DIR/main-repo/.asp-worktrees/task-003"

# Branches must still exist for PR review
cd "$TEST_DIR/main-repo"
BRANCHES=$(git branch --list 'feat/spec-004-*' | wc -l | tr -d ' ')
cd "$ASP_ROOT"
assert_eq "all 3 task branches preserved for PR review" "$BRANCHES" "3"

# ── Test 4: P5 — telemetry includes multi_agent.converge ──
echo "── Test 4: P5 — telemetry has multi_agent.converge events ──"
LOG="$TEST_DIR/main-repo/.asp-telemetry.ndjson"
TOTAL=$((TOTAL + 1))
CONVERGE_COUNT=$(grep -c '"event":"multi_agent.converge"' "$LOG" 2>/dev/null || echo 0)
if [ "$CONVERGE_COUNT" = "3" ]; then
  echo "  ✅ 3 converge events recorded"; PASS=$((PASS + 1))
else
  echo "  ❌ expected 3 converge events, got $CONVERGE_COUNT"; FAIL=$((FAIL + 1))
fi

# ── Test 5: N3/S8 — task-vs-task merge conflict (TASK-001 merges, TASK-002 fails) ──
echo "── Test 5: N3/S8 — task-vs-task merge conflict, partial success ──"
setup_dispatched_repo
mkdir -p "$TEST_DIR/manifests"
# Both tasks claim disjoint scope, but both happen to modify src/shared/util.go
# (a scope that wasn't designed-out). This simulates the SPEC's "scope 設計時未發現重疊"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/shared/"
write_manifest "$TEST_DIR/manifests/TASK-002.yaml" "TASK-002" "src/shared/"

# dispatch will reject this as overlap (N5). Bypass dispatch — manually create
# worktrees to simulate "design slipped through".
cd "$TEST_DIR/main-repo"
git worktree add -q -b feat/spec-004-task-001 ".asp-worktrees/task-001"
git worktree add -q -b feat/spec-004-task-002 ".asp-worktrees/task-002"
mkdir -p .asp-task-manifests
cp "$TEST_DIR/manifests/TASK-001.yaml" .asp-task-manifests/TASK-001.yaml
cp "$TEST_DIR/manifests/TASK-002.yaml" .asp-task-manifests/TASK-002.yaml
cd "$ASP_ROOT"

# Both modify the same line of src/shared/util.go differently
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-001" "src/shared/util.go" "shared line A from task1" "task1 conflict"
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-002" "src/shared/util.go" "shared line A from task2" "task2 conflict"

cd "$TEST_DIR/main-repo"
ASP_HITL_MODE=mock ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
  run_converge --task TASK-001 --task TASK-002
cd "$ASP_ROOT"

assert_eq "exit 3 on task-vs-task merge conflict" "$CONVERGE_RC" "3"
assert_contains "stderr lists conflict file" "$CONVERGE_STDERR" "src/shared/util.go"

# Partial success: TASK-001 should already be merged on main
cd "$TEST_DIR/main-repo"
TASK1_ON_MAIN=$(git log main --oneline | grep -c "task1 conflict" || true)
cd "$ASP_ROOT"
assert_eq "TASK-001 already merged (partial success)" "$TASK1_ON_MAIN" "1"

# Escalation log written
assert_file_exists "escalation log written" "$TEST_DIR/main-repo/.asp-escalation.ndjson"
ESC_LOG=$(cat "$TEST_DIR/main-repo/.asp-escalation.ndjson" 2>/dev/null)
assert_contains "escalation reason=task_merge_conflict" "$ESC_LOG" "task_merge_conflict"

# Telemetry should record the failure
LOG="$TEST_DIR/main-repo/.asp-telemetry.ndjson"
TOTAL=$((TOTAL + 1))
if grep -q '"event":"multi_agent.fail"' "$LOG" 2>/dev/null; then
  echo "  ✅ multi_agent.fail telemetry recorded"; PASS=$((PASS + 1))
else
  echo "  ❌ multi_agent.fail telemetry missing"; FAIL=$((FAIL + 1))
fi

# ── Test 6: B5/S14 — base_branch concurrent commit + task conflict (rebase fail) ──
echo "── Test 6: B5/S14 — base_branch rebase conflict ──"
setup_dispatched_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/api/"

cd "$TEST_DIR/main-repo"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$DISPATCH" --manifests "$TEST_DIR/manifests" >/dev/null
cd "$ASP_ROOT"

# Worker modifies src/api/file.go on its branch
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-001" "src/api/file.go" "api from worker" "worker change"

# Meanwhile, user commits a CONFLICTING change on main
cd "$TEST_DIR/main-repo"
echo "api from user-on-main" > src/api/file.go
git add src/api/file.go
git commit -q -m "user direct commit"
cd "$ASP_ROOT"

cd "$TEST_DIR/main-repo"
ASP_HITL_MODE=mock ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
  run_converge --task TASK-001
cd "$ASP_ROOT"

assert_eq "exit 3 on base_branch rebase conflict" "$CONVERGE_RC" "3"

ESC_LOG=$(cat "$TEST_DIR/main-repo/.asp-escalation.ndjson" 2>/dev/null || echo "")
assert_contains "escalation reason=base_branch_rebase_conflict" "$ESC_LOG" "base_branch_rebase_conflict"

# Verify rebase was aborted cleanly (no leftover REBASE_HEAD)
cd "$TEST_DIR/main-repo"
TOTAL=$((TOTAL + 1))
WORKTREE_DIR=".asp-worktrees/task-001"
if [ -d "$WORKTREE_DIR/.git" ] || [ -f "$WORKTREE_DIR/.git" ]; then
  # Use the worktree's git dir
  if [ ! -d ".git/worktrees/task-001/rebase-merge" ] && [ ! -d ".git/worktrees/task-001/rebase-apply" ]; then
    echo "  ✅ rebase state cleaned up after abort"; PASS=$((PASS + 1))
  else
    echo "  ❌ rebase state leaked"; FAIL=$((FAIL + 1))
  fi
else
  echo "  ⚠️  worktree gone — skipping rebase cleanup check"; PASS=$((PASS + 1))
fi
cd "$ASP_ROOT"

# ── Test 7: ASP_AUDIT_ROOT validation ──
echo "── Test 7: N7 — converge rejects unset ASP_AUDIT_ROOT ──"
unset ASP_AUDIT_ROOT
run_converge --task TASK-001
assert_eq "exit 7 on unset ASP_AUDIT_ROOT" "$CONVERGE_RC" "7"

# ── Test 8: missing --task argument ──
echo "── Test 8: missing --task argument ──"
setup_dispatched_repo
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_converge
assert_eq "exit non-zero when no --task given" \
  "$([ "$CONVERGE_RC" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# ── Test 9: nonexistent task ID ──
echo "── Test 9: nonexistent task → fail with clear error ──"
setup_dispatched_repo
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_converge --task TASK-999
assert_eq "exit non-zero on missing task" \
  "$([ "$CONVERGE_RC" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
assert_contains "stderr explains missing task" "$CONVERGE_STDERR" "TASK-999"

# ── Summary ──
echo ""
echo "═══════════════════════════════════════"
echo "  B3 Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ $FAIL -eq 0 ]
