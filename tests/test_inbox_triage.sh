#!/usr/bin/env bash
# test_inbox_triage.sh — SPEC-009: 人類 inbox-triage 授權通道（ADR-012 DP2/DP4）
# 涵蓋：triage 腳本行為（S1-S6）+ autopilot 閘 DP4 契約（S7）+ 訊息導向（S8）
# Run: bash tests/test_inbox_triage.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/inbox-triage.sh"
PROFILE="$ASP_ROOT/.claude/skills/asp/asp-autopilot.md"
INGEST="$ASP_ROOT/.asp/scripts/inbox-ingest.sh"
AUDIT_HOOK="$ASP_ROOT/.asp/hooks/session-audit.sh"
mk_test_dir

INBOX() { echo "$TEST_DIR/.asp-task-inbox.json"; }
ROADMAP() { echo "$TEST_DIR/ROADMAP.yaml"; }

make_inbox() {
    cat > "$(INBOX)" <<'JSON'
[
  {
    "id": "INBOX-77",
    "title": "External feature request",
    "type": "NEW_FEATURE",
    "priority": "P2",
    "status": "pending",
    "sla_hours": 72,
    "source": {"type": "github_issue", "ref": "https://github.com/x/y/issues/77", "imported_at": "2026-06-11T00:00:00Z"},
    "triggered_by": "customer",
    "description": "needs human triage before entering ROADMAP"
  }
]
JSON
}

make_roadmap() {
    cat > "$(ROADMAP)" <<'YAML'
version: "1.0"
project: test-project
milestones:
  - id: M1
    title: "Milestone 1"
    tasks:
      - id: H1
        title: "Human task"
        type: GENERAL
        priority: 1
        status: pending
YAML
}

run_triage() { (cd "$TEST_DIR" && CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$SCRIPT" "$@" 2>"$TEST_DIR/stderr.log"); }

reset() { rm -rf "${TEST_DIR:?}"; mkdir -p "$TEST_DIR"; (cd "$TEST_DIR" && git init -q && git config user.name "Test Human" && git config user.email "human@example.com"); }

# ── 前置：腳本存在 ──
echo ""
echo "S0: inbox-triage.sh exists and is invocable"
if [ -f "$SCRIPT" ]; then
    pass "script exists"
else
    fail "script missing: $SCRIPT"
fi

# ── S1: approve 寫入 ROADMAP（含 triage 記號 + provenance）並轉 triaged ──
echo ""
echo "S1: --approve writes task to ROADMAP with triage marker, inbox → triaged"
reset; make_inbox; make_roadmap
run_triage --approve INBOX-77; RC=$?
[ "$RC" -eq 0 ] && pass "approve exits 0" || fail "approve exit $RC"
grep -q "INBOX-77" "$(ROADMAP)" 2>/dev/null && pass "task in ROADMAP" || fail "task not in ROADMAP"
grep -q "triage_accepted_by" "$(ROADMAP)" 2>/dev/null && pass "triage_accepted_by present" || fail "triage_accepted_by missing"
grep -q "source_ref" "$(ROADMAP)" 2>/dev/null && pass "provenance markers kept" || fail "provenance markers lost"
status=$(jq -r '.[0].status' "$(INBOX)" 2>/dev/null)
[ "$status" = "triaged" ] && pass "inbox status → triaged" || fail "inbox status is '$status'"

# ── S2: reject 不碰 ROADMAP ──
echo ""
echo "S2: --reject marks rejected, ROADMAP untouched"
reset; make_inbox; make_roadmap
before=$(cat "$(ROADMAP)")
run_triage --reject INBOX-77; RC=$?
[ "$RC" -eq 0 ] && pass "reject exits 0" || fail "reject exit $RC"
[ "$before" = "$(cat "$(ROADMAP)")" ] && pass "ROADMAP unchanged" || fail "ROADMAP modified on reject"
status=$(jq -r '.[0].status' "$(INBOX)" 2>/dev/null)
[ "$status" = "rejected" ] && pass "inbox status → rejected" || fail "inbox status is '$status'"

# ── S3: 重複 approve 同 source_ref 去重 ──
echo ""
echo "S3: duplicate source_ref is not approved twice"
reset; make_inbox; make_roadmap
run_triage --approve INBOX-77
# 重置 inbox 為 pending 模擬重複投遞
make_inbox
run_triage --approve INBOX-77
count=$(grep -c "issues/77" "$(ROADMAP)" 2>/dev/null || true); count=${count:-0}
[ "$count" -eq 1 ] && pass "source_ref appears exactly once (count=$count)" || fail "source_ref count=$count (dup injection)"

# ── S4: ROADMAP 不存在 → exit 1 + 提示 ──
echo ""
echo "S4: missing ROADMAP fails with autopilot-init hint"
reset; make_inbox
run_triage --approve INBOX-77; RC=$?
[ "$RC" -ne 0 ] && pass "exit non-zero without ROADMAP" || fail "exit 0 without ROADMAP"
grep -q "autopilot-init" "$TEST_DIR/stderr.log" && pass "hints autopilot-init" || fail "no autopilot-init hint"

# ── S5: 不存在的 ID → exit 1 ──
echo ""
echo "S5: unknown task id fails"
reset; make_inbox; make_roadmap
run_triage --approve INBOX-NOPE; RC=$?
[ "$RC" -ne 0 ] && pass "unknown id exits non-zero" || fail "unknown id exited 0"

# ── S6: 無 held 任務 → exit 0 ──
echo ""
echo "S6: no pending tasks exits 0"
reset; make_roadmap
echo "[]" > "$(INBOX)"
run_triage; RC=$?
[ "$RC" -eq 0 ] && pass "empty inbox exits 0" || fail "empty inbox exit $RC"

# ── S7: autopilot 閘契約 — triage 分支 + DP4 bot 拒絕 ──
echo ""
echo "S7: autopilot gate has triage branch with DP4 bot-author rejection"
grep -q "triage_accepted_by" "$PROFILE" \
    && pass "gate has triage_accepted_by branch" || fail "gate lacks triage branch"
grep -qE "git log.*-S.*ROADMAP" "$PROFILE" \
    && pass "gate verifies introducing-commit author via git log" || fail "no git log author verification"
grep -qE '\\\[bot\\\]|\[bot\]' "$PROFILE" \
    && pass "gate rejects [bot] author pattern (DP4)" || fail "no bot-pattern rejection"

# ── S8: held 訊息導向 make inbox-triage ──
echo ""
echo "S8: held messages point to make inbox-triage"
grep -q "inbox-triage" "$INGEST" \
    && pass "inbox-ingest held message mentions inbox-triage" || fail "inbox-ingest not updated"
grep -q "inbox-triage" "$AUDIT_HOOK" \
    && pass "session-audit A15.1 mentions inbox-triage" || fail "session-audit not updated"

# ── Makefile target ──
echo ""
echo "S9: make inbox-triage target exists"
grep -qE "^inbox-triage:" "$ASP_ROOT/.asp/Makefile.inc" \
    && pass "Makefile target exists" || fail "Makefile target missing"

# ── 結果 ──
echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
