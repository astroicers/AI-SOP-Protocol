#!/usr/bin/env bash
# test_adr_firm_state.sh — Tests for ADR FIRM middle-state behaviour
# Run: bash tests/test_adr_firm_state.sh
#
# Covers:
#   T1: FIRM ADR is NOT added to DRAFT_ADRS in session-audit.sh
#   T2: FIRM ADR appears in FIRM_ADRS and emits WARNING (not BLOCKER)
#   T3: audit-fallback.sh with FIRM ADR outputs YELLOW (not BLOCKER)
#   T4: Draft ADR is still detected as BLOCKER (regression guard)

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-firm-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# ── Setup: minimal ASP project skeleton ──
setup() {
  rm -rf "${TEST_DIR:?}"/*
  mkdir -p "$TEST_DIR/docs/adr" "$TEST_DIR/.claude"
  cp "$ASP_ROOT/.asp/hooks/session-audit.sh" "$TEST_DIR/session-audit.sh"
  cp "$ASP_ROOT/.asp/hooks/denied-commands.json" "$TEST_DIR/.asp-denied-commands.json" 2>/dev/null || echo '{}' > "$TEST_DIR/.asp-denied-commands.json"

  # Minimal settings.json
  echo '{"permissions":{"allow":[],"deny":[]}}' > "$TEST_DIR/.claude/settings.json"
}

# Helper: write an ADR with given status in canonical table format
write_adr_table() {
  local file="$1" status="$2"
  cat > "$file" <<ADR
# ADR-TEST: Test ADR

| 欄位 | 內容 |
|------|------|
| **狀態** | \`${status}\` |
| **日期** | 2026-05-27 |
| **決策者** | test |

## Context
Test context.

## Decision
Test decision.
ADR
}

# Helper: write FIRM ADR with Verification Evidence
write_firm_adr() {
  local file="$1"
  cat > "$file" <<ADR
# ADR-TEST: Test ADR

| 欄位 | 內容 |
|------|------|
| **狀態** | \`FIRM\` |
| **日期** | 2026-05-27 |
| **決策者** | test |

## Verification Evidence
- POC branch: poc/test-branch
- 驗證日期: 2026-05-27
- 驗證者: test-user

## Context
Test context.
ADR
}

# Run session-audit.sh in isolation and capture the briefing JSON
run_audit() {
  CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$ASP_ROOT/.asp/hooks/session-audit.sh" 2>/dev/null || true
}

# ── T1: FIRM ADR not added to DRAFT_ADRS ──
echo ""
echo "T1: FIRM ADR should NOT be in draft_adrs"
setup
write_firm_adr "$TEST_DIR/docs/adr/ADR-TEST-firm.md"
run_audit
if [ -f "$TEST_DIR/.asp-session-briefing.json" ]; then
  draft_count=$(jq '.draft_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo "err")
  if [ "$draft_count" = "0" ]; then
    pass "FIRM ADR not in draft_adrs (count=$draft_count)"
  else
    fail "FIRM ADR incorrectly added to draft_adrs (count=$draft_count)"
  fi
else
  fail "briefing JSON not generated"
fi

# ── T2: FIRM ADR appears in firm_adrs + emits WARNING not BLOCKER ──
echo ""
echo "T2: FIRM ADR should appear in firm_adrs with WARNING"
setup
write_firm_adr "$TEST_DIR/docs/adr/ADR-TEST-firm.md"
run_audit
if [ -f "$TEST_DIR/.asp-session-briefing.json" ]; then
  firm_count=$(jq '.firm_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo "err")
  blocker_count=$(jq '[.blockers[] | select(test("FIRM"))] | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo "err")
  warning_count=$(jq '[.warnings[] | select(test("FIRM"))] | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo "err")

  if [ "$firm_count" = "1" ]; then
    pass "FIRM ADR found in firm_adrs (count=$firm_count)"
  else
    fail "FIRM ADR not found in firm_adrs (count=$firm_count)"
  fi

  if [ "$blocker_count" = "0" ]; then
    pass "FIRM ADR does not produce a BLOCKER"
  else
    fail "FIRM ADR incorrectly produces a BLOCKER (count=$blocker_count)"
  fi

  if [ "$warning_count" = "1" ]; then
    pass "FIRM ADR produces a WARNING (count=$warning_count)"
  else
    fail "FIRM ADR did not produce a WARNING (count=$warning_count)"
  fi
else
  fail "briefing JSON not generated"
fi

# ── T3: audit-fallback.sh with FIRM ADR outputs YELLOW, not BLOCKER ──
echo ""
echo "T3: audit-fallback.sh FIRM ADR → YELLOW (not BLOCKER)"
if [ -f "$ASP_ROOT/.asp/scripts/audit-fallback.sh" ]; then
  setup
  write_firm_adr "$TEST_DIR/docs/adr/ADR-TEST-firm.md"
  output=$(CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$ASP_ROOT/.asp/scripts/audit-fallback.sh" 2>/dev/null || true)
  if echo "$output" | grep -q "YELLOW\|🟡\|FIRM"; then
    pass "audit-fallback.sh outputs YELLOW/FIRM signal for FIRM ADR"
  else
    fail "audit-fallback.sh missing YELLOW/FIRM signal for FIRM ADR"
  fi
  if echo "$output" | grep -qE "BLOCKER.*FIRM|FIRM.*BLOCKER"; then
    fail "audit-fallback.sh incorrectly marks FIRM ADR as BLOCKER"
  else
    pass "audit-fallback.sh does not mark FIRM ADR as BLOCKER"
  fi
else
  echo "  ⚠️  SKIP: audit-fallback.sh not found"
fi

# ── T4: Draft ADR is still detected as BLOCKER (regression guard) ──
echo ""
echo "T4: Draft ADR should still be a BLOCKER (regression guard)"
setup
write_adr_table "$TEST_DIR/docs/adr/ADR-TEST-draft.md" "Draft"
run_audit
if [ -f "$TEST_DIR/.asp-session-briefing.json" ]; then
  draft_count=$(jq '.draft_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo "err")
  blocker_count=$(jq '[.blockers[] | select(test("Draft|A3.1"))] | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo "err")

  if [ "$draft_count" = "1" ]; then
    pass "Draft ADR found in draft_adrs (count=$draft_count)"
  else
    fail "Draft ADR not found in draft_adrs (count=$draft_count)"
  fi

  if [ "$blocker_count" = "1" ]; then
    pass "Draft ADR produces a BLOCKER (count=$blocker_count)"
  else
    fail "Draft ADR did not produce a BLOCKER (count=$blocker_count)"
  fi
else
  fail "briefing JSON not generated"
fi

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
