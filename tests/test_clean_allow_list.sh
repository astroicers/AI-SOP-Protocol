#!/usr/bin/env bash
# test_clean_allow_list.sh — tests for the SessionStart permission hook
# (.asp/hooks/clean-allow-list.sh): injects the deny list, ensures Bash(*) in
# allow, and STRIPS dangerous rules a user may have added to allow (anti-bypass).
# Run: bash tests/test_clean_allow_list.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ASP_ROOT/.asp/hooks/clean-allow-list.sh"
mk_test_dir

S()  { echo "$TEST_DIR/.claude/settings.json"; }
SL() { echo "$TEST_DIR/.claude/settings.local.json"; }
reset() { rm -rf "${TEST_DIR:?}"; mkdir -p "$TEST_DIR/.claude"; }
run() { CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" >/dev/null 2>&1 || true; }
deny_has()  { jq --arg s "$1" '[.permissions.deny[]?  | select(. == $s)] | length' "$2" 2>/dev/null || echo 0; }
allow_has() { jq --arg s "$1" '[.permissions.allow[]? | select(. == $s)] | length' "$2" 2>/dev/null || echo 0; }

# ── T1: fallback deny injected + Bash(*) ensured in allow ──
echo ""
echo "T1: empty settings → dangerous deny injected, Bash(*) ensured"
reset
echo '{"permissions":{"allow":[],"deny":[]}}' > "$(S)"
run
[ "$(deny_has 'Bash(rm -rf *)' "$(S)")" = "1" ] && pass "dangerous deny injected (rm -rf)" || fail "deny not injected"
[ "$(allow_has 'Bash(*)' "$(S)")" = "1" ] && pass "Bash(*) ensured in allow" || fail "Bash(*) missing from allow"

# ── T2: user-added dangerous rule in ALLOW is stripped (anti-bypass) ──
echo ""
echo "T2: dangerous rule manually added to allow must be STRIPPED (deny-bypass guard)"
reset
echo '{"permissions":{"allow":["Bash(rm -rf /tmp/x)","Bash(ls)"],"deny":[]}}' > "$(S)"
run
[ "$(allow_has 'Bash(rm -rf /tmp/x)' "$(S)")" = "0" ] && pass "dangerous allow rule stripped" || fail "dangerous allow NOT stripped — deny bypass possible"
[ "$(allow_has 'Bash(ls)' "$(S)")" = "1" ] && pass "safe allow rule preserved" || fail "safe allow rule wrongly removed"

# ── T3: dynamic git-commit deny is cleaned (re-evaluated by session-audit) ──
echo ""
echo "T3: leftover dynamic git-commit deny is cleaned"
reset
echo '{"permissions":{"allow":[],"deny":["Bash(git commit *)","Bash(git commit)"]}}' > "$(S)"
run
[ "$(deny_has 'Bash(git commit *)' "$(S)")" = "0" ] && pass "dynamic git-commit deny cleaned" || fail "git-commit deny not cleaned"

# ── T4: both settings.json AND settings.local.json are processed ──
echo ""
echo "T4: settings.local.json is also processed"
reset
echo '{"permissions":{"allow":[],"deny":[]}}' > "$(S)"
echo '{"permissions":{"allow":[],"deny":[]}}' > "$(SL)"
run
[ "$(deny_has 'Bash(rm -rf *)' "$(SL)")" = "1" ] && pass "settings.local.json also gets the deny list" || fail "settings.local.json not processed"

# ── T5: an invalid-JSON settings file is skipped without breaking the valid one ──
echo ""
echo "T5: invalid-JSON settings.json is skipped gracefully; valid sibling still processed"
reset
printf 'not valid json {{{' > "$(S)"
echo '{"permissions":{"allow":[],"deny":[]}}' > "$(SL)"
run
[ "$(deny_has 'Bash(rm -rf *)' "$(SL)")" = "1" ] && pass "valid sibling processed despite invalid file" || fail "invalid file broke the run"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
