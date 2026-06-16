#!/usr/bin/env bash
# test_session_audit_compile.sh — session-audit.sh §1.5（A16 compiled profile）
# (v5 Phase 3, ADR-016)：hook 恆 exit 0、briefing 含 compiled_profile 欄位、
# 衝突 → A16.1 WARNING 不擋 session、無 compile 腳本 → 靜默跳過。
# Run: bash tests/test_session_audit_compile.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ASP_ROOT/.asp/hooks/session-audit.sh"
mk_test_dir

mkproj() { # $1=dir
  rm -rf "$1"; mkdir -p "$1/.asp/profiles" "$1/.asp/config" "$1/.asp/scripts" "$1/.claude" "$1/docs/adr"
  touch "$1/README.md" "$1/CHANGELOG.md" "$1/Makefile"
  cp "$ASP_ROOT/.asp/scripts/asp-compile.sh" "$ASP_ROOT/.asp/scripts/level-resolve.sh" \
     "$ASP_ROOT/.asp/scripts/validate-profile.sh" "$1/.asp/scripts/" 2>/dev/null || true
  printf '# GC\n<!-- requires: (none) -->\nbody\n' > "$1/.asp/profiles/global_core.md"
  printf '# AP\n<!-- requires: global_core -->\n<!-- conflicts: loosey -->\nbody\n' > "$1/.asp/profiles/autopiloty.md"
  printf '# LS\n<!-- requires: global_core -->\n<!-- conflicts: autopiloty -->\nbody\n' > "$1/.asp/profiles/loosey.md"
  cat > "$1/.asp/config/profile-map.yaml" <<'EOF'
version: 1
rules:
  - when: "type=system"
    load: "global_core"
  - when: "level=loose"
    load: "loosey"
  - when: "autopilot=enabled"
    load: "autopiloty"
level_aliases:
  - "0=loose"
EOF
}
run_hook() { CLAUDE_PROJECT_DIR="$1" bash "$HOOK" >/dev/null 2>&1; RC=$?; }

echo ""
echo "T1: 正常組態 → exit 0 + 產物生成 + briefing 欄位"
mkproj "$TEST_DIR/p1"
printf 'type: system\n' > "$TEST_DIR/p1/.ai_profile"
run_hook "$TEST_DIR/p1"
[ "$RC" = "0" ] && pass "hook exit 0" || fail "rc=$RC"
[ -f "$TEST_DIR/p1/.asp-compiled-profile.md" ] && pass "產物已生成" || fail "no artifact"
B="$TEST_DIR/p1/.asp-session-briefing.json"
[ "$(jq -r '.compiled_profile_ok' "$B" 2>/dev/null)" = "true" ] && pass "briefing compiled_profile_ok=true" || fail "briefing: $(jq -c '{compiled_profile_ok, compiled_profile_lines}' "$B" 2>/dev/null)"
[ "$(jq -r '.compiled_profile_lines' "$B")" -gt 0 ] && pass "compiled_profile_lines > 0" || fail "lines=0"

echo ""
echo "T2: 無 compile 腳本 → 仍 exit 0、無產物、無 BLOCKER"
mkproj "$TEST_DIR/p2"
rm -f "$TEST_DIR/p2/.asp/scripts/asp-compile.sh"
printf 'type: system\n' > "$TEST_DIR/p2/.ai_profile"
HOME="$TEST_DIR/fakehome" run_hook "$TEST_DIR/p2"
[ "$RC" = "0" ] && pass "hook exit 0" || fail "rc=$RC"
[ ! -f "$TEST_DIR/p2/.asp-compiled-profile.md" ] && pass "無產物（整段跳過）" || fail "unexpected artifact"
[ "$(jq -r '.blockers | length' "$TEST_DIR/p2/.asp-session-briefing.json")" = "0" ] && pass "無 BLOCKER" || fail "blockers added"

echo ""
echo "T3: 衝突組態 → exit 0 + A16.1 WARNING（不擋 session）"
mkproj "$TEST_DIR/p3"
printf 'type: system\nlevel: loose\nautopilot: enabled\n' > "$TEST_DIR/p3/.ai_profile"
run_hook "$TEST_DIR/p3"
[ "$RC" = "0" ] && pass "hook exit 0" || fail "rc=$RC"
jq -r '.warnings[]' "$TEST_DIR/p3/.asp-session-briefing.json" 2>/dev/null | grep -q 'A16.1' \
  && pass "A16.1 衝突 WARNING 在 briefing" || fail "no A16.1: $(jq -c .warnings "$TEST_DIR/p3/.asp-session-briefing.json")"
[ "$(jq -r '.compiled_profile_ok' "$TEST_DIR/p3/.asp-session-briefing.json")" = "false" ] \
  && pass "compiled_profile_ok=false" || fail "ok flag wrong"

echo ""
echo "T4: 壞 map → exit 0 + A16.2 INFO（靜默失敗回退散文）"
mkproj "$TEST_DIR/p4"
echo 'broken' > "$TEST_DIR/p4/.asp/config/profile-map.yaml"
printf 'type: system\n' > "$TEST_DIR/p4/.ai_profile"
run_hook "$TEST_DIR/p4"
[ "$RC" = "0" ] && pass "hook exit 0" || fail "rc=$RC"
jq -r '.infos[]' "$TEST_DIR/p4/.asp-session-briefing.json" 2>/dev/null | grep -q 'A16.2' \
  && pass "A16.2 INFO 在 briefing" || fail "no A16.2: $(jq -c .infos "$TEST_DIR/p4/.asp-session-briefing.json")"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
