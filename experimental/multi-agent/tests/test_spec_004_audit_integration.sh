#!/usr/bin/env bash
# test_spec_004_audit_integration.sh — SPEC-004 B5: Iron Rule A + audit/telemetry
#
# Covers:
#   P7/S16: worktree 中 session-audit.sh 仍可執行（smoke test）
#   S15: Worker cwd 在 worktree 時，audit-write.sh 寫到主 repo
#   S18: 並行壓測 — 5 worker × 200 entry = 1000 行 NDJSON 全綠
#   P5: telemetry schema 支援 multi_agent.dispatch / converge / fail 三種 event
#
# Run: bash tests/test_spec_004_audit_integration.sh

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-spec004-b5-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

DISPATCH="$ASP_ROOT/scripts/dispatch.sh"
WRAPPER="$ASP_ROOT/scripts/audit-write.sh"
SESSION_AUDIT="$ASP_ROOT/../../.asp/hooks/session-audit.sh"   # core hook（凍結測試引用主 repo）

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local actual="$2"; local expected="$3"
  if [ "$actual" = "$expected" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc"; echo "     expected: $expected"; echo "     actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

assert_file_exists() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ -f "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (missing: $path)"; FAIL=$((FAIL + 1)); fi
}

setup_repo_with_worktree() {
  rm -rf "${TEST_DIR:?}"/*
  unset ASP_AUDIT_ROOT 2>/dev/null || true
  git init -q -b main "$TEST_DIR/main-repo"
  cd "$TEST_DIR/main-repo"
  git config user.email "test@test.local"
  git config user.name "test"
  mkdir -p src/store src/api .claude
  echo "package store" > src/store/file.go
  echo "package api"   > src/api/file.go
  cat > .claude/settings.json <<'EOF'
{
  "hooks": {
    "SessionStart": []
  }
}
EOF
  git add -A
  git commit -q -m "init"
  cd "$ASP_ROOT"
}

# ── Test 1: P7/S16 — session-audit.sh runs inside worktree without crashing ──
echo "── Test 1: P7/S16 — session-audit.sh smoke test in worktree ──"
setup_repo_with_worktree

# Create a worktree manually (we're testing hooks, not dispatch here)
cd "$TEST_DIR/main-repo"
git worktree add -q -b feat/test ".asp-worktrees/task-001" 2>/dev/null
cd "$ASP_ROOT"

WORKTREE_DIR="$TEST_DIR/main-repo/.asp-worktrees/task-001"

# Run session-audit.sh with CLAUDE_PROJECT_DIR set to worktree path
set +e
CLAUDE_PROJECT_DIR="$WORKTREE_DIR" bash "$SESSION_AUDIT" >/dev/null 2>"$TEST_DIR/.audit-stderr"
AUDIT_RC=$?
set -e

assert_eq "session-audit.sh exits 0 in worktree" "$AUDIT_RC" "0"
assert_file_exists "session briefing created in worktree (not main repo)" \
  "$WORKTREE_DIR/.asp-session-briefing.json"

# Verify briefing is valid JSON (parse with jq if available, else basic check)
if command -v jq >/dev/null 2>&1; then
  TOTAL=$((TOTAL + 1))
  if jq -e '.' "$WORKTREE_DIR/.asp-session-briefing.json" >/dev/null 2>&1; then
    echo "  ✅ briefing is valid JSON"; PASS=$((PASS + 1))
  else
    echo "  ❌ briefing is not valid JSON"; FAIL=$((FAIL + 1))
  fi
fi

# ── Test 2: S15 — audit-write from worktree cwd lands in main repo ──
echo "── Test 2: S15 — audit-write from worktree cwd lands in main repo ──"
setup_repo_with_worktree

cd "$TEST_DIR/main-repo"
git worktree add -q -b feat/test2 ".asp-worktrees/task-002" 2>/dev/null
WORKTREE_DIR="$TEST_DIR/main-repo/.asp-worktrees/task-002"

cd "$WORKTREE_DIR"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
  bash "$WRAPPER" bypass '{"actor":"worker-from-worktree","scope":"src/store/"}'
WRAPPER_RC=$?
cd "$ASP_ROOT"

assert_eq "audit-write returns 0" "$WRAPPER_RC" "0"
assert_file_exists "main repo bypass log received entry" \
  "$TEST_DIR/main-repo/.asp-bypass-log.ndjson"
TOTAL=$((TOTAL + 1))
if [ ! -f "$WORKTREE_DIR/.asp-bypass-log.ndjson" ]; then
  echo "  ✅ worktree did NOT receive bypass log (path strategy works)"; PASS=$((PASS + 1))
else
  echo "  ❌ worktree got bypass log — Iron Rule B leak"; FAIL=$((FAIL + 1))
fi

# ── Test 3: S18 — concurrent stress test (5 × 200 = 1000 entries) ──
echo "── Test 3: S18 — concurrent append-only stress (5 workers × 200 entries) ──"
setup_repo_with_worktree

# Spawn 5 worker subshells, each appends 200 short JSON entries
NUM_WORKERS=5
ENTRIES_PER_WORKER=200
TOTAL_EXPECTED=$((NUM_WORKERS * ENTRIES_PER_WORKER))

PIDS=""
for w in $(seq 1 "$NUM_WORKERS"); do
  (
    for i in $(seq 1 "$ENTRIES_PER_WORKER"); do
      ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
        bash "$WRAPPER" bypass "{\"worker\":$w,\"i\":$i}" 2>/dev/null
    done
  ) &
  PIDS="$PIDS $!"
done

# Wait for all workers
for pid in $PIDS; do wait "$pid"; done

# Verify line count
LOG="$TEST_DIR/main-repo/.asp-bypass-log.ndjson"
LINE_COUNT=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ' || echo 0)
assert_eq "all $TOTAL_EXPECTED entries present (no truncation)" "$LINE_COUNT" "$TOTAL_EXPECTED"

# Verify every line is valid JSON (no interleaved/partial writes)
if command -v jq >/dev/null 2>&1; then
  TOTAL=$((TOTAL + 1))
  INVALID=$(jq -r -c . "$LOG" 2>&1 >/dev/null | wc -l | tr -d ' ' || echo 0)
  if [ "$INVALID" = "0" ]; then
    echo "  ✅ all $TOTAL_EXPECTED lines parseable by jq (no atomic-append violation)"; PASS=$((PASS + 1))
  else
    echo "  ❌ jq found $INVALID invalid lines"; FAIL=$((FAIL + 1))
  fi
fi

# ── Test 4: P5 — telemetry schema supports 3 event types ──
echo "── Test 4: P5 — telemetry supports multi_agent.{dispatch,converge,fail} ──"
setup_repo_with_worktree

# Write all three event types
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$WRAPPER" telemetry \
  '{"event":"multi_agent.dispatch","task_id":"TASK-001"}'
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$WRAPPER" telemetry \
  '{"event":"multi_agent.converge","task_id":"TASK-001","status":"success"}'
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$WRAPPER" telemetry \
  '{"event":"multi_agent.fail","task_id":"TASK-002","reason":"scope_violation"}'

LOG="$TEST_DIR/main-repo/.asp-telemetry.ndjson"
assert_file_exists "telemetry log exists" "$LOG"

# Verify each event type is present
for evt in dispatch converge fail; do
  TOTAL=$((TOTAL + 1))
  if grep -q "\"event\":\"multi_agent.$evt\"" "$LOG" 2>/dev/null; then
    echo "  ✅ multi_agent.$evt event recorded"; PASS=$((PASS + 1))
  else
    echo "  ❌ multi_agent.$evt event missing"; FAIL=$((FAIL + 1))
  fi
done

# ── Test 5: Integrated dispatch flow writes telemetry correctly ──
echo "── Test 5: P5 integrated — dispatch emits multi_agent.dispatch event ──"
setup_repo_with_worktree
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

LOG="$TEST_DIR/main-repo/.asp-telemetry.ndjson"
TOTAL=$((TOTAL + 1))
if grep -q '"event":"multi_agent.dispatch"' "$LOG" 2>/dev/null && \
   grep -q '"task_id":"TASK-001"' "$LOG" 2>/dev/null; then
  echo "  ✅ dispatch flow wrote multi_agent.dispatch with task_id"; PASS=$((PASS + 1))
else
  echo "  ❌ dispatch did not emit expected telemetry"
  echo "     telemetry log content:"
  cat "$LOG" 2>/dev/null | sed 's/^/       /'
  FAIL=$((FAIL + 1))
fi

# ── Summary ──
echo ""
echo "═══════════════════════════════════════"
echo "  B5 Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ $FAIL -eq 0 ]
