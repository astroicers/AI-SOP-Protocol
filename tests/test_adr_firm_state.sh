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

# Helper: Accepted ADR that RETAINS the template 狀態說明 legend line.
# This legend (from ADR_Template.md) contains backtick `Draft` and `FIRM` in
# body prose — the false-positive vector for TD-004. Canonical status is the
# table cell `| **狀態** | `Accepted` |`, so this ADR must NOT be flagged.
write_accepted_with_status_legend() {
  local file="$1"
  cat > "$file" <<ADR
# ADR-TEST: Accepted ADR retaining the template status legend

| 欄位 | 內容 |
|------|------|
| **狀態** | \`Accepted\` |
| **日期** | 2026-06-08 |

> **狀態說明：** \`Draft\`（初稿，禁止實作）→ \`FIRM\`（POC 驗證，允許 commit）→ \`Accepted\`（人類審核通過）

## Context
This ADR is Accepted; its body legend mentions \`Draft\`/\`FIRM\` but the
canonical status table cell says Accepted.
ADR
}

# Helper: write an ADR with an ARBITRARY status value cell, to exercise the
# non-backtick and annotated formats that are actually used in this repo's
# SPEC files (e.g. `| **狀態** | Accepted |`). The status legend body line is
# kept on purpose so each test also guards against the TD-004 false positive.
write_adr_status_cell() {
  local file="$1" valuecell="$2"
  cat > "$file" <<ADR
# ADR-TEST: raw status cell

| 欄位 | 內容 |
|------|------|
| **狀態** | ${valuecell} |
| **日期** | 2026-06-08 |
| **決策者** | astroicers（待確認） |

> **狀態說明：** \`Draft\`（初稿，禁止實作）→ \`FIRM\`（POC 驗證）→ \`Accepted\`（人類審核通過）

## Context
test
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
  if grep -q "YELLOW\|🟡\|FIRM" <<<"$output"; then
    pass "audit-fallback.sh outputs YELLOW/FIRM signal for FIRM ADR"
  else
    fail "audit-fallback.sh missing YELLOW/FIRM signal for FIRM ADR"
  fi
  if grep -qE "BLOCKER.*FIRM|FIRM.*BLOCKER" <<<"$output"; then
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

# ── T5: Accepted ADR with status-legend body text → NOT Draft/FIRM (TD-004) ──
echo ""
echo "T5: Accepted ADR whose body mentions \`Draft\`/\`FIRM\` must NOT be flagged (TD-004 false-positive regression)"
setup
write_accepted_with_status_legend "$TEST_DIR/docs/adr/ADR-TEST-accepted-legend.md"
run_audit
if [ -f "$TEST_DIR/.asp-session-briefing.json" ]; then
  draft_count=$(jq '.draft_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo "err")
  firm_count=$(jq '.firm_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo "err")
  blocker_count=$(jq '[.blockers[] | select(test("Draft|A3.1"))] | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo "err")

  if [ "$draft_count" = "0" ]; then
    pass "Accepted ADR with body \`Draft\` not flagged as Draft (count=$draft_count)"
  else
    fail "Accepted ADR falsely flagged as Draft from body text (count=$draft_count)"
  fi

  if [ "$blocker_count" = "0" ]; then
    pass "Accepted ADR with body \`Draft\` does not produce a BLOCKER"
  else
    fail "Accepted ADR falsely produces a Draft BLOCKER (count=$blocker_count)"
  fi

  if [ "$firm_count" = "0" ]; then
    pass "Accepted ADR with body \`FIRM\` not flagged as FIRM (count=$firm_count)"
  else
    fail "Accepted ADR falsely flagged as FIRM from body text (count=$firm_count)"
  fi
else
  fail "briefing JSON not generated"
fi

# ── T6: no-backtick Draft status cell → BLOCKER (TD-004 round 2 false-negative) ──
echo ""
echo "T6: plain-text \`| **狀態** | Draft |\` (no backticks) MUST be a BLOCKER (governance bypass guard)"
setup
write_adr_status_cell "$TEST_DIR/docs/adr/ADR-TEST-plain-draft.md" "Draft"
run_audit
draft_count=$(jq '.draft_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo err)
blocker_count=$(jq '[.blockers[] | select(test("Draft|A3.1"))] | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo err)
{ [ "$draft_count" = "1" ] && [ "$blocker_count" = "1" ]; } \
  && pass "no-backtick Draft flagged + BLOCKER (count=$draft_count)" \
  || fail "no-backtick Draft NOT flagged (draft=$draft_count blocker=$blocker_count) — Draft ADR would bypass commit deny"

# ── T7: annotated Draft status cell → BLOCKER ──
echo ""
echo "T7: annotated \`| **狀態** | \\\`Draft\\\`（待人類審核） |\` MUST be a BLOCKER"
setup
write_adr_status_cell "$TEST_DIR/docs/adr/ADR-TEST-annot-draft.md" '`Draft`（待人類審核）'
run_audit
draft_count=$(jq '.draft_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo err)
[ "$draft_count" = "1" ] && pass "annotated Draft cell flagged (count=$draft_count)" \
  || fail "annotated Draft cell NOT flagged (count=$draft_count)"

# ── T8: no-backtick FIRM status cell → WARNING (firm), not Draft ──
echo ""
echo "T8: plain-text \`| **狀態** | FIRM |\` → firm_adrs (WARNING), not Draft"
setup
write_adr_status_cell "$TEST_DIR/docs/adr/ADR-TEST-plain-firm.md" "FIRM"
run_audit
firm_count=$(jq '.firm_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo err)
draft_count=$(jq '.draft_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo err)
{ [ "$firm_count" = "1" ] && [ "$draft_count" = "0" ]; } \
  && pass "no-backtick FIRM in firm_adrs, not Draft (firm=$firm_count draft=$draft_count)" \
  || fail "no-backtick FIRM mis-detected (firm=$firm_count draft=$draft_count)"

# ── T9: no-backtick Accepted (control) → neither Draft nor FIRM ──
echo ""
echo "T9: plain-text \`| **狀態** | Accepted |\` → neither Draft nor FIRM"
setup
write_adr_status_cell "$TEST_DIR/docs/adr/ADR-TEST-plain-accepted.md" "Accepted"
run_audit
draft_count=$(jq '.draft_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo err)
firm_count=$(jq '.firm_adrs | length' "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo err)
{ [ "$draft_count" = "0" ] && [ "$firm_count" = "0" ]; } \
  && pass "Accepted not mis-flagged (draft=$draft_count firm=$firm_count)" \
  || fail "Accepted mis-flagged (draft=$draft_count firm=$firm_count)"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
