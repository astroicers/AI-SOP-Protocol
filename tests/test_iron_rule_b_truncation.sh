#!/usr/bin/env bash
# test_iron_rule_b_truncation.sh — Tests for Iron Rule B append-only truncation
# detection in session-audit.sh (TD-002).
# Run: bash tests/test_iron_rule_b_truncation.sh
#
# Iron Rule B invariant: .asp-bypass-log.ndjson is APPEND-ONLY. Its line count
# must be monotonically non-decreasing; any drop ⇒ audit entries were removed.
#
# The bypass log is GITIGNORED (local-only), so a git/HEAD baseline is always
# empty and can never see a truncation (the original TD-002 framing assumed the
# log was tracked — it is not). Detection therefore uses a high-water-mark
# sidecar (.asp-bypass-log.hwm) ratcheted up each SessionStart. These tests use
# NO git — matching the production reality of a gitignored log.
#
# Covers:
#   T1: count unchanged                              → no BLOCKER
#   T2: append (grows)                               → no BLOCKER, HWM ratchets up
#   T3: truncate below HWM                           → BLOCKER (the attack)
#   T4: append-then-erase within/after a session    → BLOCKER (HWM remembers peak)
#   T5: brand-new log, no prior HWM                  → no BLOCKER, seeds HWM
#   T6: trailing-newline toggle cannot hide a delete → BLOCKER (awk NR robustness)
#   T7: truncation BLOCKER persists until restored   → still BLOCKER next session

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ASP_ROOT/.asp/hooks/session-audit.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-ironb-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

LOG=".asp-bypass-log.ndjson"

reset() {  # fresh project, NO git (log is gitignored in prod → git is irrelevant)
  rm -rf "${TEST_DIR:?}"; mkdir -p "$TEST_DIR/.claude"
  echo '{"permissions":{"allow":[],"deny":[]}}' > "$TEST_DIR/.claude/settings.json"
}

write_log() {  # $1 = number of lines (each a distinct ndjson record, newline-terminated)
  local n="$1" i
  : > "$TEST_DIR/$LOG"
  for i in $(seq 1 "$n"); do echo "{\"event\":$i}" >> "$TEST_DIR/$LOG"; done
}

# Run audit; echo 1 if an Iron Rule B BLOCKER was emitted, else 0.
ironb_blocker() {
  CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$AUDIT" >/dev/null 2>&1 || true
  if [ -f "$TEST_DIR/.asp-session-briefing.json" ]; then
    jq '[.blockers[] | select(test("Iron Rule B"))] | length' \
      "$TEST_DIR/.asp-session-briefing.json" 2>/dev/null || echo 0
  else
    echo "ERR"
  fi
}

# ── T1: count unchanged → no BLOCKER ──
echo ""
echo "T1: 5 lines, run twice unchanged → no truncation"
reset; write_log 5
ironb_blocker >/dev/null            # seeds HWM=5
[ "$(ironb_blocker)" = "0" ] && pass "no BLOCKER when unchanged" || fail "false BLOCKER on unchanged log"

# ── T2: append (grows) → no BLOCKER ──
echo ""
echo "T2: 5 → append to 8 → no truncation, HWM ratchets up"
reset; write_log 5; ironb_blocker >/dev/null
write_log 8
[ "$(ironb_blocker)" = "0" ] && pass "no BLOCKER on append-only growth" || fail "false BLOCKER on appended log"

# ── T3: truncate below HWM → BLOCKER ──
echo ""
echo "T3: HWM=5, truncate to 2 → MUST BLOCKER"
reset; write_log 5; ironb_blocker >/dev/null
write_log 2
[ "$(ironb_blocker)" = "1" ] && pass "BLOCKER raised on truncation" || fail "truncation NOT detected (Iron Rule B miss)"

# ── T4: append-then-erase back to baseline → BLOCKER (HWM remembers the peak) ──
echo ""
echo "T4: 2 → grow to 10 → erased back to 2 → MUST BLOCKER (HEAD-based check missed this)"
reset; write_log 2; ironb_blocker >/dev/null   # HWM=2
write_log 10; ironb_blocker >/dev/null          # HWM=10
write_log 2                                      # cover-up: back to the original 2
[ "$(ironb_blocker)" = "1" ] && pass "BLOCKER on append-then-erase (peak remembered)" || fail "append-then-erase NOT detected"

# ── T5: brand-new log, no prior HWM → no BLOCKER ──
echo ""
echo "T5: new log, no prior high-water-mark → no truncation, seeds HWM"
reset; write_log 3
[ "$(ironb_blocker)" = "0" ] && pass "no BLOCKER for fresh log" || fail "false BLOCKER for fresh log"

# ── T6: trailing-newline toggle cannot mask a deletion ──
echo ""
echo "T6: HWM=5 (no final newline), delete 1 entry + add final newline → MUST BLOCKER"
reset
printf '{"e":1}\n{"e":2}\n{"e":3}\n{"e":4}\n{"e":5}' > "$TEST_DIR/$LOG"   # 5 records, no trailing \n
ironb_blocker >/dev/null                                                   # HWM=5 (awk NR counts the 5th)
printf '{"e":1}\n{"e":2}\n{"e":3}\n{"e":4}\n' > "$TEST_DIR/$LOG"           # 4 records WITH trailing \n
[ "$(ironb_blocker)" = "1" ] && pass "newline toggle cannot hide a delete (awk NR)" || fail "off-by-one newline skew let a delete slip"

# ── T7: BLOCKER persists across sessions until the log is restored ──
echo ""
echo "T7: after truncation, BLOCKER persists next session (HWM not lowered)"
reset; write_log 6; ironb_blocker >/dev/null   # HWM=6
write_log 1; ironb_blocker >/dev/null           # BLOCKER, HWM stays 6
[ "$(ironb_blocker)" = "1" ] && pass "BLOCKER persists until restored" || fail "BLOCKER cleared itself (HWM was lowered)"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
