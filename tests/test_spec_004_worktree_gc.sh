#!/usr/bin/env bash
# test_spec_004_worktree_gc.sh — SPEC-004 B4: agent-worktree-list / agent-worktree-gc
#
# Covers:
#   S12/B3: stale worktree (idle > threshold) → GC removes it, marks manifest abandoned
#   S19/B6: Worker process killed → worktree保留 → GC 後續清理
#   list:   `make agent-worktree-list` shows worktree + age + task_id + status
#
# GC 策略（SPEC §⚠️ Case 4 + Done When #5/#6）:
#   - "stale" 預設 = HEAD commit time > IDLE_HOURS 小時前（預設 2）
#   - GC 移除 worktree dir + 標記 .asp-task-manifests/<TID>.yaml 加 abandoned: true
#   - branch 保留（與 converge cleanup 同策略）
#   - 環境變數 ASP_WORKTREE_IDLE_HOURS 可覆蓋 threshold（測試用）
#
# Run: bash tests/test_spec_004_worktree_gc.sh

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-spec004-b4-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

DISPATCH="$ASP_ROOT/.asp/scripts/multi-agent/dispatch.sh"
GC_SCRIPT="$ASP_ROOT/.asp/scripts/multi-agent/worktree-gc.sh"
LIST_SCRIPT="$ASP_ROOT/.asp/scripts/multi-agent/worktree-list.sh"

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

assert_dir_exists() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ -d "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (missing: $path)"; FAIL=$((FAIL + 1)); fi
}

assert_dir_absent() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ ! -d "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (still exists: $path)"; FAIL=$((FAIL + 1)); fi
}

setup_with_dispatched_task() {
  rm -rf "$TEST_DIR"/*
  unset ASP_AUDIT_ROOT 2>/dev/null || true
  git init -q -b main "$TEST_DIR/main-repo"
  cd "$TEST_DIR/main-repo"
  git config user.email "test@test.local"
  git config user.name "test"
  mkdir -p src/store src/api src/auth
  echo s > src/store/x.go && echo a > src/api/x.go && echo u > src/auth/x.go
  git add -A && git commit -q -m "init"
  cd "$ASP_ROOT"

  mkdir -p "$TEST_DIR/manifests"
  cat > "$TEST_DIR/manifests/TASK-001.yaml" <<EOF
task_id: TASK-001
agent: worker-a
agent_role: impl
scope:
  allow: [src/store/]
  forbid: []
worktree_branch: feat/spec-004-task-001
EOF

  cd "$TEST_DIR/main-repo"
  ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$DISPATCH" --manifests "$TEST_DIR/manifests" >/dev/null
  cd "$ASP_ROOT"
}

# Force a worktree to look "stale" by rewriting the branch's HEAD commit time
# to N hours in the past. Uses git's GIT_COMMITTER_DATE / amend.
make_worktree_stale() {
  local worktree="$1"
  local hours_ago="$2"
  local past_ts
  past_ts=$(( $(date +%s) - hours_ago * 3600 ))
  local past_iso
  past_iso=$(date -d "@$past_ts" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
             date -r "$past_ts" -u +"%Y-%m-%dT%H:%M:%SZ")
  cd "$worktree"
  GIT_COMMITTER_DATE="$past_iso" GIT_AUTHOR_DATE="$past_iso" \
    git commit -q --allow-empty -m "stale marker"
  cd "$ASP_ROOT"
}

# ── Test 1: scripts exist ──
echo "── Test 1: GC + list scripts exist ──"
assert_file_exists "worktree-gc.sh exists" "$GC_SCRIPT"
assert_file_exists "worktree-list.sh exists" "$LIST_SCRIPT"

# ── Test 2: list shows currently-dispatched worktree ──
echo "── Test 2: agent-worktree-list shows active worktrees ──"
setup_with_dispatched_task
LIST_OUT=$(ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$LIST_SCRIPT" 2>&1)
assert_contains "list shows TASK-001" "$LIST_OUT" "TASK-001"
assert_contains "list shows worktree path" "$LIST_OUT" "task-001"
assert_contains "list shows branch" "$LIST_OUT" "feat/spec-004-task-001"

# ── Test 3: list on empty repo → no error, prints empty/none ──
echo "── Test 3: list on repo with no worktrees ──"
rm -rf "$TEST_DIR"/*
git init -q -b main "$TEST_DIR/main-repo"
cd "$TEST_DIR/main-repo" && git config user.email t@t && git config user.name t
echo x > x && git add x && git commit -q -m init && cd "$ASP_ROOT"

set +e
LIST_OUT=$(ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$LIST_SCRIPT" 2>&1)
LIST_RC=$?
set -e
assert_eq "list exits 0 on empty repo" "$LIST_RC" "0"

# ── Test 4: GC dry-run does NOT remove anything ──
echo "── Test 4: agent-worktree-gc --dry-run leaves worktrees alone ──"
setup_with_dispatched_task
make_worktree_stale "$TEST_DIR/main-repo/.asp-worktrees/task-001" 5

GC_OUT=$(ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$GC_SCRIPT" --dry-run 2>&1)
assert_contains "dry-run mentions stale worktree" "$GC_OUT" "task-001"
assert_contains "dry-run mentions DRY-RUN" "$GC_OUT" "DRY"
assert_dir_exists "worktree NOT removed in dry-run" "$TEST_DIR/main-repo/.asp-worktrees/task-001"

# ── Test 5: S12 — GC removes stale worktree (idle > 2h) ──
echo "── Test 5: S12 — GC removes stale worktree, branch preserved, manifest abandoned ──"
setup_with_dispatched_task
make_worktree_stale "$TEST_DIR/main-repo/.asp-worktrees/task-001" 5

ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$GC_SCRIPT" >/dev/null 2>&1

assert_dir_absent "stale worktree removed" "$TEST_DIR/main-repo/.asp-worktrees/task-001"

# Branch must remain
cd "$TEST_DIR/main-repo"
BRANCH_LIST=$(git branch --list 'feat/spec-004-task-001')
cd "$ASP_ROOT"
assert_contains "feat branch preserved" "$BRANCH_LIST" "feat/spec-004-task-001"

# Manifest annotated as abandoned
MANIFEST="$TEST_DIR/main-repo/.asp-task-manifests/TASK-001.yaml"
assert_file_exists "manifest still exists" "$MANIFEST"
MANIFEST_CONTENT=$(cat "$MANIFEST")
assert_contains "manifest marked abandoned: true" "$MANIFEST_CONTENT" "abandoned: true"

# Telemetry recorded
LOG="$TEST_DIR/main-repo/.asp-telemetry.ndjson"
TOTAL=$((TOTAL + 1))
if grep -q '"event":"multi_agent.gc"' "$LOG" 2>/dev/null; then
  echo "  ✅ multi_agent.gc telemetry recorded"; PASS=$((PASS + 1))
else
  echo "  ❌ multi_agent.gc telemetry missing"; FAIL=$((FAIL + 1))
fi

# ── Test 6: GC with custom IDLE_HOURS via env ──
echo "── Test 6: ASP_WORKTREE_IDLE_HOURS overrides threshold ──"
setup_with_dispatched_task
# Make worktree only 1 hour old; default threshold 2h → not stale
make_worktree_stale "$TEST_DIR/main-repo/.asp-worktrees/task-001" 1

# Default threshold (2h): should NOT collect
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$GC_SCRIPT" >/dev/null 2>&1
assert_dir_exists "worktree kept under default 2h threshold" \
  "$TEST_DIR/main-repo/.asp-worktrees/task-001"

# Lower threshold to 0.5h (1800s) via env: should collect
ASP_WORKTREE_IDLE_HOURS=0.5 ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
  bash "$GC_SCRIPT" >/dev/null 2>&1
assert_dir_absent "worktree collected after lowering threshold" \
  "$TEST_DIR/main-repo/.asp-worktrees/task-001"

# ── Test 7: GC does NOT touch fresh worktrees ──
echo "── Test 7: fresh worktree (just dispatched) NOT collected ──"
setup_with_dispatched_task
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$GC_SCRIPT" >/dev/null 2>&1
assert_dir_exists "fresh worktree preserved" \
  "$TEST_DIR/main-repo/.asp-worktrees/task-001"

# ── Test 8: GC under empty .asp-worktrees/ → exits 0, no error ──
echo "── Test 8: GC on empty worktree dir → silent success ──"
rm -rf "$TEST_DIR"/*
git init -q -b main "$TEST_DIR/main-repo"
cd "$TEST_DIR/main-repo" && git config user.email t@t && git config user.name t
echo x > x && git add x && git commit -q -m init && cd "$ASP_ROOT"

set +e
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$GC_SCRIPT" >/dev/null 2>&1
GC_RC=$?
set -e
assert_eq "GC exits 0 when no worktrees" "$GC_RC" "0"

# ── Test 9: ASP_AUDIT_ROOT validation ──
echo "── Test 9: GC + list reject unset ASP_AUDIT_ROOT ──"
unset ASP_AUDIT_ROOT
set +e
bash "$GC_SCRIPT" >/dev/null 2>&1
GC_RC=$?
bash "$LIST_SCRIPT" >/dev/null 2>&1
LIST_RC=$?
set -e
assert_eq "GC exit 7 on unset ASP_AUDIT_ROOT" "$GC_RC" "7"
assert_eq "list exit 7 on unset ASP_AUDIT_ROOT" "$LIST_RC" "7"

# ── Test 10: S19 — Worker SIGKILL leaves worktree, GC handles next round ──
echo "── Test 10: S19 — SIGKILL'd worker → worktree保留 → next GC cleans (when stale) ──"
setup_with_dispatched_task
# Simulate worker that did some work but didn't get to commit-then-converge.
# We don't actually SIGKILL bash here; we just ensure the worktree is older
# than threshold and GC cleans it.
make_worktree_stale "$TEST_DIR/main-repo/.asp-worktrees/task-001" 4

# Verify GC catches abandoned worker work
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$GC_SCRIPT" >/dev/null 2>&1
assert_dir_absent "abandoned worker's worktree cleaned" \
  "$TEST_DIR/main-repo/.asp-worktrees/task-001"

# ── Summary ──
echo ""
echo "═══════════════════════════════════════"
echo "  B4 Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ $FAIL -eq 0 ]
