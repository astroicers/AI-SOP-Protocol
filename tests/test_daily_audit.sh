#!/usr/bin/env bash
# test_daily_audit.sh — Tests for daily-audit.sh
# Run: bash tests/test_daily_audit.sh
#
# T1: report file is created in PROJECT_DIR
# T2: report contains expected section headers
# T3: no ROADMAP → "無 ROADMAP.yaml" appears, script does not crash
# T4: ROADMAP with tasks → progress summary in report
# T5: inbox file present → inbox section shows status counts
# T6: no Makefile → adr-list/audit-health fallback silently, exit 0

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mk_test_dir



# ── Helpers ──

setup() {
    rm -rf "${TEST_DIR:?}"/*
    mkdir -p "$TEST_DIR/.asp/scripts"
    cp "$ASP_ROOT/.asp/scripts/daily-audit.sh" "$TEST_DIR/.asp/scripts/"
}

write_makefile() {
    cat > "$TEST_DIR/Makefile" <<'MAKE'
-include .asp/Makefile.inc
MAKE
    cp "$ASP_ROOT/.asp/Makefile.inc" "$TEST_DIR/.asp/" 2>/dev/null || true
}

write_roadmap() {
    cat > "$TEST_DIR/ROADMAP.yaml" <<'YAML'
version: "1.0"
project: test
milestones:
  - id: M001
    title: "MVP"
    status: pending
    tasks:
      - id: T001
        title: "Task A"
        type: NEW_FEATURE
        priority: 1
        status: completed
        description: "done"
      - id: T002
        title: "Task B"
        type: BUGFIX
        priority: 2
        status: pending
        description: "todo"
YAML
}

write_inbox() {
    cat > "$TEST_DIR/.asp-task-inbox.json" <<'JSON'
[
  {"id":"INBOX-001","title":"Fix bug","type":"BUGFIX","priority":"high","status":"pending"},
  {"id":"INBOX-002","title":"Old task","type":"GENERAL","priority":"low","status":"ingested"}
]
JSON
}

run_daily() {
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.asp/scripts/daily-audit.sh" 2>/dev/null
}

REPORT="$TEST_DIR/.asp-daily-report.md"

# ── T1: report file is created ──
echo ""
echo "T1: report file should be created in PROJECT_DIR"
setup
run_daily
if [ -f "$REPORT" ]; then
    pass "report file exists at $REPORT"
else
    fail "report file not found at $REPORT"
fi

# ── T2: report contains required section headers ──
echo ""
echo "T2: report should contain all required section headers"
setup
run_daily
for section in "ROADMAP 進度" "ADR 清單" "健康審計" "Task Inbox" "Git 活動" "今日待辦建議"; do
    if grep -q "$section" "$REPORT" 2>/dev/null; then
        pass "section '${section}' present"
    else
        fail "section '${section}' missing"
    fi
done

# ── T3: no ROADMAP → fallback message, exit 0 ──
echo ""
echo "T3: missing ROADMAP.yaml should show fallback, not crash"
setup
run_daily
exit_code=$?
if [ $exit_code -eq 0 ]; then
    pass "script exits 0 when no ROADMAP"
else
    fail "script exited $exit_code"
fi
if grep -q "無 ROADMAP.yaml" "$REPORT" 2>/dev/null; then
    pass "fallback message '無 ROADMAP.yaml' in report"
else
    fail "fallback message not found in report"
fi

# ── T4: ROADMAP with tasks → progress in report ──
echo ""
echo "T4: ROADMAP with tasks should show progress summary"
setup; write_roadmap
run_daily
if grep -q "completed=1" "$REPORT" 2>/dev/null; then
    pass "completed=1 found in ROADMAP summary"
else
    fail "completed=1 not found (got: $(grep -m1 'completed\|pending' "$REPORT" || echo 'nothing'))"
fi
# milestone itself is also status:pending, so pending count >= 1
if grep -qE "pending=[1-9]" "$REPORT" 2>/dev/null; then
    pass "pending>=1 found in ROADMAP summary"
else
    fail "pending count not found"
fi

# ── T5: inbox present → shows status counts ──
echo ""
echo "T5: inbox file should appear in report with status counts"
setup; write_inbox
run_daily
if grep -q "pending=1" "$REPORT" 2>/dev/null && grep -q "ingested=1" "$REPORT" 2>/dev/null; then
    pass "inbox counts (pending=1, ingested=1) in report"
else
    fail "inbox counts not found (got: $(grep -m3 'pending\|ingested' "$REPORT" || echo 'nothing'))"
fi

# ── T6: no Makefile → adr/audit sections degrade gracefully, exit 0 ──
echo ""
echo "T6: no Makefile → adr-list/audit-health fallback, exit 0"
setup
run_daily
exit_code=$?
if [ $exit_code -eq 0 ]; then
    pass "script exits 0 without Makefile"
else
    fail "script exited $exit_code without Makefile"
fi
# report must still exist and have headers
if [ -f "$REPORT" ]; then
    pass "report still created without Makefile"
else
    fail "report not created without Makefile"
fi

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
