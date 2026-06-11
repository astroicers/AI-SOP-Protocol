#!/usr/bin/env bash
# test_task_inbox.sh — Tests for Task Inbox (inbox-ingest.sh) mechanism
# Run: bash tests/test_task_inbox.sh
#
# ⚠️ 契約變更（SPEC-007 / ADR-012 INV-2）：inbox-ingest 自 SPEC-007 起為 held-mode
#   （只回報、不注入 ROADMAP、不標 ingested）。本檔由舊「注入契約」測試
#   改寫為「held 契約」測試（2026-06-11，對應 Accepted ADR-012）。
#   深度旁路測試見 tests/test_inbox_ingest_no_bypass.sh。
#
# T1: pending task is HELD — not injected into ROADMAP.yaml
# T2: re-run is idempotent (still held, still no injection)
# T3: inbox task status stays "pending" (never auto-ingested)
# T4: inbox with no pending tasks does nothing (silent)
# T5: missing ROADMAP.yaml still exits 0 and reports held (no crash)
# T6: held report lists the task id

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
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.asp/scripts/inbox-ingest.sh" 2>"$TEST_DIR/stderr.log"
}

# ── T1: pending task is HELD — not injected into ROADMAP ──
echo ""
echo "T1: pending task should be HELD (not injected into ROADMAP.yaml)"
setup; write_inbox; write_roadmap
run_ingest
if grep -q "INBOX-001" "$TEST_DIR/ROADMAP.yaml" 2>/dev/null; then
    fail "INBOX-001 was injected into ROADMAP.yaml (SPEC-007 violated)"
else
    pass "INBOX-001 not in ROADMAP.yaml (held)"
fi
if grep -qi "held" "$TEST_DIR/stderr.log"; then
    pass "held reported on stderr"
else
    fail "no held report on stderr"
fi

# ── T2: re-run is idempotent — still held, still no injection ──
echo ""
echo "T2: re-run should remain held (idempotent, no injection on any run)"
setup; write_inbox; write_roadmap
run_ingest  # first run — held
run_ingest  # second run — still held
count=$(grep -c "INBOX-001" "$TEST_DIR/ROADMAP.yaml" 2>/dev/null || true)
count=${count:-0}
if [ "$count" -eq 0 ]; then
    pass "INBOX-001 never enters ROADMAP across re-runs (count=$count)"
else
    fail "INBOX-001 appears $count times in ROADMAP (injection occurred!)"
fi

# ── T3: inbox task status stays "pending" (never auto-ingested) ──
echo ""
echo "T3: inbox task status must stay 'pending' (no auto-ingested marking)"
setup; write_inbox; write_roadmap
run_ingest
status=$(jq -r '.[0].status' "$TEST_DIR/.asp-task-inbox.json" 2>/dev/null)
if [ "$status" = "pending" ]; then
    pass "inbox task status stays 'pending' (awaits human authorization)"
else
    fail "inbox task status is '$status', expected 'pending'"
fi

# ── T4: no pending tasks → silent, no change to ROADMAP ──
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

# ── T5: missing ROADMAP → still exit 0 + held report (no crash) ──
echo ""
echo "T5: missing ROADMAP.yaml should exit 0 and still report held"
setup; write_inbox
# no ROADMAP — held is independent of ROADMAP existence
run_ingest
if [ $? -eq 0 ]; then
    pass "script exits 0 when ROADMAP missing"
else
    fail "script exits non-zero when ROADMAP missing"
fi
if grep -qi "held" "$TEST_DIR/stderr.log"; then
    pass "held still reported without ROADMAP"
else
    fail "no held report when ROADMAP missing (got: $(cat "$TEST_DIR/stderr.log"))"
fi

# ── T6: held report lists the task id ──
echo ""
echo "T6: held report should list the held task id"
setup; write_inbox; write_roadmap
run_ingest
if grep -q "INBOX-001" "$TEST_DIR/stderr.log"; then
    pass "held report lists INBOX-001"
else
    fail "held report does not list INBOX-001"
fi

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
