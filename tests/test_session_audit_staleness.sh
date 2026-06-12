#!/usr/bin/env bash
# test_session_audit_staleness.sh — session-audit §8.5/8.6
#   A17 外部事實查證時效（fact-check 超過 TTL → INFO + briefing stale_fact_count）
#   A18 autopilot 未完成狀態（.asp-autopilot-state.json 存在 → INFO + autopilot_state_exists）
# 二者皆純 INFO、hook 恆 exit 0、不擋 session。
# Run: bash tests/test_session_audit_staleness.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ASP_ROOT/.asp/hooks/session-audit.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-sas-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 不存在"; exit 0; }

mkproj() { # $1=dir — 最小可跑專案（仿 test_session_audit_compile.sh）
  rm -rf "$1"; mkdir -p "$1/.asp/profiles" "$1/.asp/config" "$1/.asp/scripts" "$1/.claude" "$1/docs/adr"
  touch "$1/README.md" "$1/CHANGELOG.md" "$1/Makefile"
  cp "$ASP_ROOT/.asp/scripts/asp-compile.sh" "$ASP_ROOT/.asp/scripts/level-resolve.sh" \
     "$ASP_ROOT/.asp/scripts/validate-profile.sh" "$1/.asp/scripts/" 2>/dev/null || true
  printf '# GC\n<!-- requires: (none) -->\nbody\n' > "$1/.asp/profiles/global_core.md"
  cat > "$1/.asp/config/profile-map.yaml" <<'EOF'
version: 1
rules:
  - when: "type=system"
    load: "global_core"
level_aliases:
  - "0=loose"
EOF
  printf 'type: system\n' > "$1/.ai_profile"
}
run_hook() { CLAUDE_PROJECT_DIR="$1" bash "$HOOK" >/dev/null 2>&1; RC=$?; }
B() { echo "$1/.asp-session-briefing.json"; }

# ── T1: 過期 fact-check（超過 180 天）→ A17.1 INFO + stale_fact_count ≥ 1 ──
echo ""
echo "T1: 過期 fact-check → A17.1 INFO"
mkproj "$TEST_DIR/p1"
OLD=$(date -d '200 days ago' +%Y-%m-%d 2>/dev/null || echo '2020-01-01')
printf '# fc\n\n## FC-001 — x\n- **日期**：%s\n- **再驗證條件**：...\n' "$OLD" > "$TEST_DIR/p1/.asp-fact-check.md"
run_hook "$TEST_DIR/p1"
[ "$RC" = "0" ] && pass "hook exit 0" || fail "rc=$RC"
jq -r '.infos[]' "$(B "$TEST_DIR/p1")" 2>/dev/null | grep -q 'A17.1' \
  && pass "A17.1 INFO 在 briefing" || fail "no A17.1: $(jq -c .infos "$(B "$TEST_DIR/p1")" 2>/dev/null)"
[ "$(jq -r '.stale_fact_count' "$(B "$TEST_DIR/p1")" 2>/dev/null)" -ge 1 ] 2>/dev/null \
  && pass "stale_fact_count ≥ 1" || fail "stale_fact_count=$(jq -r '.stale_fact_count' "$(B "$TEST_DIR/p1")" 2>/dev/null)"

# ── T2: 近期 fact-check（今天）→ 無 A17.1、stale_fact_count=0 ──
echo ""
echo "T2: 近期 fact-check → 不提示"
mkproj "$TEST_DIR/p2"
printf '# fc\n\n## FC-001 — x\n- **日期**：%s\n' "$(date +%Y-%m-%d)" > "$TEST_DIR/p2/.asp-fact-check.md"
run_hook "$TEST_DIR/p2"
[ "$(jq -r '.stale_fact_count' "$(B "$TEST_DIR/p2")" 2>/dev/null)" = "0" ] \
  && pass "stale_fact_count=0" || fail "false positive"
jq -r '.infos[]' "$(B "$TEST_DIR/p2")" 2>/dev/null | grep -q 'A17.1' && fail "近期誤報 A17.1" || pass "近期不報 A17.1"

# ── T3: autopilot-state 存在 → A18.1 INFO + autopilot_state_exists=true ──
echo ""
echo "T3: autopilot-state 存在 → A18.1 INFO"
mkproj "$TEST_DIR/p3"
echo '{"task":"x"}' > "$TEST_DIR/p3/.asp-autopilot-state.json"
run_hook "$TEST_DIR/p3"
[ "$RC" = "0" ] && pass "hook exit 0" || fail "rc=$RC"
jq -r '.infos[]' "$(B "$TEST_DIR/p3")" 2>/dev/null | grep -q 'A18.1' \
  && pass "A18.1 INFO 在 briefing" || fail "no A18.1: $(jq -c .infos "$(B "$TEST_DIR/p3")" 2>/dev/null)"
[ "$(jq -r '.autopilot_state_exists' "$(B "$TEST_DIR/p3")" 2>/dev/null)" = "true" ] \
  && pass "autopilot_state_exists=true" || fail "flag wrong"

# ── T4: 無 autopilot-state → autopilot_state_exists=false ──
echo ""
echo "T4: 無 autopilot-state → false"
mkproj "$TEST_DIR/p4"
run_hook "$TEST_DIR/p4"
[ "$(jq -r '.autopilot_state_exists' "$(B "$TEST_DIR/p4")" 2>/dev/null)" = "false" ] \
  && pass "autopilot_state_exists=false" || fail "flag wrong"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
