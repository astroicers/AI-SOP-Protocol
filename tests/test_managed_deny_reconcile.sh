#!/usr/bin/env bash
# test_managed_deny_reconcile.sh — managed-deny reconciliation (TD-005 + ADR-011).
# Run: bash tests/test_managed_deny_reconcile.sh
#
# ADR-011: ASP writes its DYNAMIC deny to .claude/settings.local.json (gitignored,
# local), and NEVER touches the git-tracked .claude/settings.json (the user/team's
# deny). settings.local.json deny is merged by Claude Code with deny-first
# precedence (verified: .asp-fact-check.md FC-001), so enforcement is equivalent.
# This eliminates the tracked/gitignored desync, the cross-machine "stuck commit",
# and any ASP-induced diff on settings.json.
#
# Covers:
#   T1: user deny in settings.json, no Draft   → settings.json BYTE-identical
#   T2: Draft present                          → deny injected into settings.local.json; settings.json untouched
#   T3: Draft → resolved                        → settings.local.json self-clears; settings.json never touched
#   T4: settings.local.json created if absent  → created only when needed
#   T5: settings.local.json stays valid JSON
#   T6: a user's OWN deny in settings.local.json is preserved (sidecar ownership)

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ASP_ROOT/.asp/hooks/session-audit.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-deny-XXXXXX)
PASS=0; FAIL=0; TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

SETTINGS() { echo "$TEST_DIR/.claude/settings.json"; }
LOCAL()    { echo "$TEST_DIR/.claude/settings.local.json"; }

reset() { rm -rf "${TEST_DIR:?}"; mkdir -p "$TEST_DIR/.claude"; }

set_json_deny() {  # $1 = file, rest = deny strings (none → [])
  local file="$1"; shift
  local arr; if [ "$#" -eq 0 ]; then arr='[]'; else arr=$(printf '%s\n' "$@" | jq -R . | jq -s .); fi
  jq -n --argjson d "$arr" '{permissions:{allow:[],deny:$d}}' > "$file"
}

write_draft_adr() {
  mkdir -p "$TEST_DIR/docs/adr"
  printf '# ADR-001: x\n| 欄位 | 內容 |\n|------|------|\n| **狀態** | `Draft` |\n' \
    > "$TEST_DIR/docs/adr/ADR-001-x.md"
}

run_audit() { CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$AUDIT" >/dev/null 2>&1 || true; }

local_deny_has() {  # $1 = string → count in settings.local.json
  [ -f "$(LOCAL)" ] || { echo 0; return; }
  jq --arg s "$1" '[.permissions.deny[]? | select(. == $s)] | length' "$(LOCAL)" 2>/dev/null || echo 0
}

# ── T1: no Draft → settings.json must be byte-identical, no ASP deny ──
echo ""
echo "T1: user deny in settings.json, no Draft → settings.json untouched by ASP"
reset
set_json_deny "$(SETTINGS)" "Bash(git commit *)" "Bash(rm -rf /)"
before=$(sha256sum "$(SETTINGS)" | cut -d' ' -f1)
run_audit
after=$(sha256sum "$(SETTINGS)" | cut -d' ' -f1)
[ "$before" = "$after" ] && pass "settings.json byte-identical (ASP never wrote it)" \
  || fail "ASP modified the tracked settings.json"
[ "$(local_deny_has 'Bash(git commit *)')" = "0" ] && pass "no ASP deny injected without Draft" \
  || fail "ASP injected deny with no Draft"

# ── T2: Draft → inject to settings.local.json; settings.json untouched ──
echo ""
echo "T2: Draft present → git-commit deny in settings.local.json; settings.json untouched"
reset
set_json_deny "$(SETTINGS)" "Bash(rm -rf /)"
before=$(sha256sum "$(SETTINGS)" | cut -d' ' -f1)
write_draft_adr
run_audit
[ "$(local_deny_has 'Bash(git commit *)')" = "1" ] && pass "deny injected into settings.local.json" \
  || fail "deny not injected into settings.local.json"
after=$(sha256sum "$(SETTINGS)" | cut -d' ' -f1)
[ "$before" = "$after" ] && pass "settings.json still untouched under Draft" \
  || fail "ASP modified settings.json under Draft"

# ── T3: Draft → resolved → settings.local.json self-clears; settings.json never touched ──
echo ""
echo "T3: resolve Draft → settings.local.json self-clears; settings.json never touched"
reset
set_json_deny "$(SETTINGS)" "Bash(rm -rf /)"
sha_settings=$(sha256sum "$(SETTINGS)" | cut -d' ' -f1)
write_draft_adr; run_audit                 # inject
rm -rf "$TEST_DIR/docs/adr"; run_audit      # resolve
[ "$(local_deny_has 'Bash(git commit *)')" = "0" ] && pass "settings.local.json self-cleared" \
  || fail "settings.local.json deny not cleared after resolution"
[ "$(sha256sum "$(SETTINGS)" | cut -d' ' -f1)" = "$sha_settings" ] \
  && pass "settings.json never touched across the whole cycle" \
  || fail "settings.json changed during the cycle"

# ── T4: settings.local.json created only when needed ──
echo ""
echo "T4: clean project, no Draft → settings.local.json NOT created; Draft → created"
reset
set_json_deny "$(SETTINGS)"
run_audit
[ ! -f "$(LOCAL)" ] && pass "settings.local.json not created without need" \
  || fail "settings.local.json created spuriously"
write_draft_adr; run_audit
[ -f "$(LOCAL)" ] && pass "settings.local.json created when Draft present" \
  || fail "settings.local.json not created under Draft"

# ── T5: settings.local.json stays valid JSON ──
echo ""
echo "T5: settings.local.json valid JSON after inject"
reset
set_json_deny "$(SETTINGS)"; write_draft_adr; run_audit
jq -e . "$(LOCAL)" >/dev/null 2>&1 && pass "settings.local.json valid JSON" || fail "settings.local.json corrupted"

# ── T6: user's OWN deny in settings.local.json is preserved ──
echo ""
echo "T6: user's manual deny in settings.local.json survives a Draft→resolve cycle"
reset
set_json_deny "$(SETTINGS)"
set_json_deny "$(LOCAL)" "Bash(git commit *)"   # user put it in their local file for their own reason
write_draft_adr; run_audit                       # ASP also wants it (Draft) — already present, ASP must not claim it
rm -rf "$TEST_DIR/docs/adr"; run_audit            # resolve → ASP must NOT remove the user's pre-existing entry
[ "$(local_deny_has 'Bash(git commit *)')" = "1" ] && pass "user's settings.local.json deny preserved" \
  || fail "user's pre-existing settings.local.json deny was removed"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
