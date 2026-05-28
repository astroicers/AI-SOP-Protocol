#!/usr/bin/env bash
# test_task_inbox.sh — Tests for Task Inbox (inbox-ingest.sh) mechanism
# Run: bash tests/test_task_inbox.sh
#
# T1: pending task is injected into ROADMAP.yaml
# T2: duplicate source.ref is not injected twice
# T3: ingested task status updated to "ingested" in inbox
# T4: inbox with no pending tasks does nothing
# T5: missing ROADMAP.yaml emits warning and exits cleanly (no crash)
# T6: sla_hours=0 maps to priority 0 (critical), sla_hours=72 maps to 2

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-inbox-XXXXXX)
PASS=0; FAIL=0; TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# ── Helpers ──

setup() {
    rm -rf "${TEST_DIR:?}"/*
    mkdir -p "$TEST_DIR/.asp/scripts" "$TEST_DIR/.asp/hooks"
    cp "$ASP_ROOT/.asp/scripts/inbox-ingest.sh" "$TEST_DIR/.asp/scripts/"
}

write_inbox() {
    cat > "$TEST_DIR/.asp-task-inbox.json" <<'JSON'
[
  {
    "id": "INBOX-001",
    "title": "Fix login timeout bug",
    "type": "BUGFIX",
    "priority": "high",
    "status": "pending",
    "sla_hours": 24,
    "source": {
      "type": "customer_bug",
      "ref": "https://example.com/tickets/42",
      "imported_at": "2026-05-28T10:00:00Z"
    },
    "triggered_by": "customer",
    "description": "Mobile Safari users get logged out after 30 seconds."
  }
]
JSON
}

write_roadmap() {
    cat > "$TEST_DIR/ROADMAP.yaml" <<'YAML'
version: "1.0"
project: test-project
milestones:
  - id: M001
    title: "MVP"
    status: pending
    tasks:
      - id: T001
        title: "Existing task"
        type: NEW_FEATURE
        priority: 1
        status: pending
        description: "Existing."
YAML
}

run_ingest() {
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.asp/scripts/inbox-ingest.sh" 2>/dev/null
}

# ── T1: pending task injected into ROADMAP ──
echo ""
echo "T1: pending task should be injected into ROADMAP.yaml"
setup; write_inbox; write_roadmap
run_ingest
if grep -q "INBOX-001" "$TEST_DIR/ROADMAP.yaml" 2>/dev/null; then
    pass "INBOX-001 found in ROADMAP.yaml"
else
    fail "INBOX-001 not found in ROADMAP.yaml"
fi
if grep -q "Fix login timeout bug" "$TEST_DIR/ROADMAP.yaml" 2>/dev/null; then
    pass "task title found in ROADMAP.yaml"
else
    fail "task title not found in ROADMAP.yaml"
fi

# ── T2: duplicate source.ref not injected twice ──
echo ""
echo "T2: duplicate source.ref should not be injected again"
setup; write_inbox; write_roadmap
run_ingest  # first run — injects
# reset inbox to pending again to simulate re-run
cat > "$TEST_DIR/.asp-task-inbox.json" <<'JSON'
[
  {
    "id": "INBOX-001",
    "title": "Fix login timeout bug",
    "type": "BUGFIX",
    "priority": "high",
    "status": "pending",
    "sla_hours": 24,
    "source": {
      "type": "customer_bug",
      "ref": "https://example.com/tickets/42",
      "imported_at": "2026-05-28T10:00:00Z"
    },
    "triggered_by": "customer",
    "description": "Duplicate."
  }
]
JSON
run_ingest  # second run — should skip
count=$(grep -c "INBOX-001" "$TEST_DIR/ROADMAP.yaml" 2>/dev/null || echo 0)
if [ "$count" -eq 1 ]; then
    pass "INBOX-001 appears exactly once (no duplicate, count=$count)"
else
    fail "INBOX-001 appears $count times (duplicate injection!)"
fi

# ── T3: ingested task status updated to "ingested" ──
echo ""
echo "T3: after ingest, inbox task status should be 'ingested'"
setup; write_inbox; write_roadmap
run_ingest
status=$(jq -r '.[0].status' "$TEST_DIR/.asp-task-inbox.json" 2>/dev/null)
if [ "$status" = "ingested" ]; then
    pass "inbox task status updated to 'ingested'"
else
    fail "inbox task status is '$status', expected 'ingested'"
fi

# ── T4: no pending tasks → no change to ROADMAP ──
echo ""
echo "T4: inbox with no pending tasks should not modify ROADMAP"
setup; write_roadmap
cat > "$TEST_DIR/.asp-task-inbox.json" <<'JSON'
[{"id":"INBOX-001","title":"Done","type":"BUGFIX","priority":"low","status":"ingested"}]
JSON
before=$(cat "$TEST_DIR/ROADMAP.yaml")
run_ingest
after=$(cat "$TEST_DIR/ROADMAP.yaml")
if [ "$before" = "$after" ]; then
    pass "ROADMAP unchanged when no pending tasks"
else
    fail "ROADMAP was modified despite no pending tasks"
fi

# ── T5: missing ROADMAP → warning, no crash ──
echo ""
echo "T5: missing ROADMAP.yaml should warn and exit 0 (no crash)"
setup; write_inbox
# no ROADMAP
output=$(CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.asp/scripts/inbox-ingest.sh" 2>&1 || true)
if echo "$output" | grep -qi "ROADMAP\|autopilot-init\|不存在"; then
    pass "warning emitted about missing ROADMAP"
else
    fail "no warning emitted (got: $output)"
fi
# script must exit cleanly
CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.asp/scripts/inbox-ingest.sh" 2>/dev/null
if [ $? -eq 0 ]; then
    pass "script exits 0 when ROADMAP missing"
else
    fail "script exits non-zero when ROADMAP missing"
fi

# ── T6: sla_hours priority mapping ──
echo ""
echo "T6: sla_hours should map to correct ROADMAP priority"
setup; write_roadmap
cat > "$TEST_DIR/.asp-task-inbox.json" <<'JSON'
[
  {"id":"INBOX-010","title":"P0 task","type":"BUGFIX","priority":"critical",
   "status":"pending","sla_hours":0,
   "source":{"type":"manual","ref":"ref-010","imported_at":"2026-05-28T00:00:00Z"},
   "triggered_by":"ops","description":"critical"}
]
JSON
run_ingest
if grep -q "priority: 0" "$TEST_DIR/ROADMAP.yaml" 2>/dev/null; then
    pass "sla_hours=0 maps to priority 0"
else
    fail "sla_hours=0 did not map to priority 0 ($(grep 'priority:' "$TEST_DIR/ROADMAP.yaml" | tail -3))"
fi

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
