#!/usr/bin/env bash
# test_managed_deny_reconcile.sh — Tests for managed-deny reconciliation in
# session-audit.sh Section 10 (TD-005).
# Run: bash tests/test_managed_deny_reconcile.sh
#
# Bug (TD-005): the old reconcile removed a HARDCODED MANAGED_DENY list
# (`Bash(git commit *)`, `Bash(git commit)`) unconditionally. If a user had
# manually added an identical deny for their OWN reasons, ASP silently deleted
# it on the next no-Draft session.
#
# Fix: track entries ASP ACTUALLY injected (absent before injection) in a sidecar
# `.asp-managed-deny.json`; reconcile removes only ASP-owned entries. A user's
# pre-existing manual deny is never recorded as ASP-owned, so it survives.
#
# Covers:
#   T1: user's manual `Bash(git commit *)`, no Draft ADR → survives (the bug)
#   T2: Draft present → ASP injects; Draft resolved → ASP entry self-clears,
#       user's unrelated deny preserved
#   T3: pure self-clear cycle still works (empty → inject → clear)

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ASP_ROOT/.asp/hooks/session-audit.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-deny-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

SETTINGS() { echo "$TEST_DIR/.claude/settings.json"; }

reset() {
  rm -rf "${TEST_DIR:?}"; mkdir -p "$TEST_DIR/.claude"
}

set_deny() {  # $@ = deny strings (none → empty array)
  local arr
  if [ "$#" -eq 0 ]; then arr='[]'; else arr=$(printf '%s\n' "$@" | jq -R . | jq -s .); fi
  jq -n --argjson d "$arr" '{permissions:{allow:[],deny:$d}}' > "$(SETTINGS)"
}

write_draft_adr() {
  mkdir -p "$TEST_DIR/docs/adr"
  cat > "$TEST_DIR/docs/adr/ADR-001-x.md" <<'ADR'
# ADR-001: x
| 欄位 | 內容 |
|------|------|
| **狀態** | `Draft` |
ADR
}

run_audit() { CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$AUDIT" >/dev/null 2>&1 || true; }

deny_has() {  # $1 = string → 0/1
  jq --arg s "$1" '[.permissions.deny[] | select(. == $s)] | length' "$(SETTINGS)" 2>/dev/null
}

# ── T1: user's manual git-commit deny must survive a no-Draft session ──
echo ""
echo "T1: user-owned \`Bash(git commit *)\` deny + no Draft ADR → must NOT be removed"
reset
set_deny "Bash(git commit *)" "Bash(rm -rf /)"
run_audit                       # no ADR dir → no Draft → ADD_DENY empty
[ "$(deny_has 'Bash(git commit *)')" = "1" ] && pass "user's git-commit deny preserved" \
  || fail "user's git-commit deny SILENTLY REMOVED (TD-005 bug)"
[ "$(deny_has 'Bash(rm -rf /)')" = "1" ] && pass "user's unrelated deny preserved" \
  || fail "user's unrelated deny removed"

# ── T2: Draft injects, resolution self-clears ASP entry but keeps user's ──
echo ""
echo "T2: Draft → ASP injects; Draft resolved → ASP entry clears, user deny kept"
reset
set_deny "Bash(rm -rf /)"
write_draft_adr
run_audit
inj_ok=$([ "$(deny_has 'Bash(git commit *)')" = "1" ] && echo 1 || echo 0)
[ "$inj_ok" = "1" ] && pass "ASP injected git-commit deny under Draft" \
  || fail "ASP did not inject deny under Draft"
# resolve the Draft (remove ADR) and re-run
rm -rf "$TEST_DIR/docs/adr"
run_audit
[ "$(deny_has 'Bash(git commit *)')" = "0" ] && pass "ASP self-cleared its injected deny" \
  || fail "ASP injected deny not self-cleared"
[ "$(deny_has 'Bash(rm -rf /)')" = "1" ] && pass "user's unrelated deny survived the cycle" \
  || fail "user's unrelated deny lost during reconcile"

# ── T3: pure self-clear cycle (empty → inject → clear) ──
echo ""
echo "T3: empty deny → Draft inject → resolve clears back to empty"
reset
set_deny    # empty deny
write_draft_adr
run_audit
[ "$(deny_has 'Bash(git commit *)')" = "1" ] && pass "injected under Draft" || fail "not injected"
rm -rf "$TEST_DIR/docs/adr"
run_audit
remaining=$(jq '.permissions.deny | length' "$(SETTINGS)" 2>/dev/null)
[ "$remaining" = "0" ] && pass "deny back to empty after resolution" \
  || fail "deny not cleared (remaining=$remaining)"

# ── T4: lost sidecar + ASP-namespace deny + no Draft → WARNING (surfaced) ──
echo ""
echo "T4: orphaned ASP-namespace deny without a sidecar → WARNING, not silent keep/remove"
reset
set_deny "Bash(git commit *)"     # looks like an ASP injection, but no sidecar + no Draft
run_audit
brief="$TEST_DIR/.asp-session-briefing.json"
warn=$(jq '[.warnings[] | select(test("git-commit deny"))] | length' "$brief" 2>/dev/null || echo 0)
[ "${warn:-0}" -ge 1 ] && pass "orphan deny surfaced as WARNING" || fail "orphan deny not surfaced (warn=$warn)"
[ "$(deny_has 'Bash(git commit *)')" = "1" ] && pass "orphan deny NOT silently removed" || fail "orphan deny silently removed"

# ── T5: settings.json stays valid JSON through a reconcile (corruption guard) ──
echo ""
echo "T5: settings.json remains valid JSON after an injecting reconcile"
reset
set_deny "Bash(rm -rf /)"
write_draft_adr
run_audit
jq -e . "$(SETTINGS)" >/dev/null 2>&1 && pass "settings.json valid JSON after inject" || fail "settings.json corrupted"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
