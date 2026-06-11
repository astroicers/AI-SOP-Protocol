#!/usr/bin/env bash
# test_asp_metrics.sh — tests for .asp/scripts/asp-metrics.sh
# (v5 Phase 0, ADR-013: baseline metrics + machine-readable profile map).
# Covers: line counting, rule counting, profile-map driven config simulation
# (context tax), determinism, --compare, exit codes, ghost-reference tolerance,
# and a real-repo smoke test that auto-adapts to later phases.
# Run: bash tests/test_asp_metrics.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/asp-metrics.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-metrics-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# ── fixture repo builder ──
FIX="$TEST_DIR/repo"
build_fixture() {
  rm -rf "$FIX"
  mkdir -p "$FIX/.asp/profiles" "$FIX/.asp/levels" "$FIX/.asp/config" "$FIX/.claude/skills/asp"
  # global_core: 10 lines, contains 2x MUST + 1x 禁止
  {
    echo '# Global Core'
    echo '<!-- requires: (none — always loaded) -->'
    echo 'rule: you MUST do X'
    echo 'rule: you MUST do Y'
    echo '禁止輸出憑證'
    printf 'filler\n%.0s' 1 2 3 4 5
  } > "$FIX/.asp/profiles/global_core.md"          # 10 lines
  # alpha: 6 lines, requires global_core, contains 1x 🔴
  {
    echo '# Alpha'
    echo '<!-- requires: global_core -->'
    echo '🔴 hard rule'
    printf 'filler\n%.0s' 1 2 3
  } > "$FIX/.asp/profiles/alpha.md"                # 6 lines
  # beta: 4 lines, requires alpha (transitive expansion test)
  {
    echo '# Beta'
    echo '<!-- requires: alpha -->'
    printf 'filler\n%.0s' 1 2
  } > "$FIX/.asp/profiles/beta.md"                 # 4 lines
  # one skill file: 5 lines with 1x MUST
  {
    echo '# skill'
    echo 'you MUST invoke'
    printf 'filler\n%.0s' 1 2 3
  } > "$FIX/.claude/skills/asp/asp-x.md"           # 5 lines
  # one level yaml: 3 lines
  printf 'level: 1\nname: T\nprofiles: []\n' > "$FIX/.asp/levels/level-1.yaml"
  # CLAUDE.md: 2 lines
  printf '# C\nx\n' > "$FIX/CLAUDE.md"
  # profile map
  cat > "$FIX/.asp/config/profile-map.yaml" <<'EOF'
version: 1
rules:
  - when: "type=content"
    load: "global_core"
  - when: "type=system"
    load: "global_core beta"
  - when: "design=enabled&coding_style=enabled"
    load: "alpha"
level_aliases:
  - "0=loose"
EOF
}

run_json() { OUT=$(bash "$SCRIPT" --repo-root "$FIX" 2>"$TEST_DIR/stderr"); RC=$?; }

command -v jq >/dev/null || { echo "SKIP: jq not available"; exit 1; }

# ── T1: fixture line counts exact ──
echo ""
echo "T1: fixture line counts"
build_fixture; run_json
[ "$RC" = "0" ] || fail "metrics rc=$RC (expected 0); stderr: $(head -3 "$TEST_DIR/stderr")"
[ "$(echo "$OUT" | jq -r '.profiles.count')" = "3" ] && pass "profiles.count=3" || fail "profiles.count=$(echo "$OUT" | jq -r '.profiles.count')"
[ "$(echo "$OUT" | jq -r '.profiles.total_lines')" = "20" ] && pass "profiles.total_lines=20" || fail "profiles.total_lines=$(echo "$OUT" | jq -r '.profiles.total_lines')"
[ "$(echo "$OUT" | jq -r '.profiles.files["global_core.md"]')" = "10" ] && pass "per-file lines exact" || fail "global_core.md lines=$(echo "$OUT" | jq -r '.profiles.files["global_core.md"]')"
[ "$(echo "$OUT" | jq -r '.skills.count')" = "1" ] && pass "skills.count=1" || fail "skills.count wrong"
[ "$(echo "$OUT" | jq -r '.levels.count')" = "1" ] && pass "levels.count=1" || fail "levels.count wrong"

# ── T2: rule counting (MUST|禁止|🔴) ──
echo ""
echo "T2: rule counting"
[ "$(echo "$OUT" | jq -r '.rules.per_profile["global_core.md"]')" = "3" ] && pass "global_core rules=3 (2 MUST + 1 禁止)" || fail "global_core rules=$(echo "$OUT" | jq -r '.rules.per_profile["global_core.md"]')"
[ "$(echo "$OUT" | jq -r '.rules.per_profile["alpha.md"]')" = "1" ] && pass "alpha rules=1 (🔴)" || fail "alpha rules wrong"
[ "$(echo "$OUT" | jq -r '.rules.total')" = "5" ] && pass "rules.total=5 (4 profile + 1 skill)" || fail "rules.total=$(echo "$OUT" | jq -r '.rules.total')"
[ "$(echo "$OUT" | jq -r '.rules.pattern')" = "MUST|禁止|🔴" ] && pass "pattern recorded in JSON" || fail "pattern missing"

# ── T3: config simulation from map (incl. AND + requires expansion) ──
echo ""
echo "T3: map-driven config simulation"
SIM=$(bash "$SCRIPT" --repo-root "$FIX" --simulate "type=content" 2>/dev/null)
[ "$(echo "$SIM" | jq -c '.profiles_loaded')" = '["global_core"]' ] && pass "type=content loads exactly [global_core]" || fail "got $(echo "$SIM" | jq -c '.profiles_loaded')"
SIM=$(bash "$SCRIPT" --repo-root "$FIX" --simulate "type=system" 2>/dev/null)
echo "$SIM" | jq -e '.profiles_loaded | index("alpha")' >/dev/null \
  && pass "requires expansion pulls alpha via beta" || fail "transitive requires not expanded: $(echo "$SIM" | jq -c '.profiles_loaded')"
[ "$(echo "$SIM" | jq -r '.profile_lines')" = "20" ] && pass "type=system lines=20 (10+6+4)" || fail "lines=$(echo "$SIM" | jq -r '.profile_lines')"
SIM=$(bash "$SCRIPT" --repo-root "$FIX" --simulate "type=content,design=enabled" 2>/dev/null)
echo "$SIM" | jq -e '.profiles_loaded | index("alpha")' >/dev/null \
  && fail "AND condition fired with only one field set" || pass "AND condition requires both fields"
SIM=$(bash "$SCRIPT" --repo-root "$FIX" --simulate "type=content,design=enabled,coding_style=enabled" 2>/dev/null)
echo "$SIM" | jq -e '.profiles_loaded | index("alpha")' >/dev/null \
  && pass "AND condition fires when both fields match" || fail "AND condition did not fire"

# ── T4: determinism (two runs identical modulo timestamps) ──
echo ""
echo "T4: determinism"
A=$(bash "$SCRIPT" --repo-root "$FIX" 2>/dev/null | jq -S 'del(.generated_at,.git_commit)')
B=$(bash "$SCRIPT" --repo-root "$FIX" 2>/dev/null | jq -S 'del(.generated_at,.git_commit)')
[ "$A" = "$B" ] && pass "two runs identical (excl. generated_at/git_commit)" || fail "outputs differ between runs"

# ── T5: --compare with self → zero deltas, exit 0 ──
echo ""
echo "T5: --compare with self"
bash "$SCRIPT" --repo-root "$FIX" --output "$TEST_DIR/base.json" >/dev/null 2>&1
CMP=$(bash "$SCRIPT" --repo-root "$FIX" --compare "$TEST_DIR/base.json" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && pass "--compare exit 0" || fail "--compare rc=$RC"
echo "$CMP" | grep -q 'Δ' && pass "compare table contains Δ column" || fail "no Δ in compare output"
echo "$CMP" | grep -qE '\+0|-0| 0 ' && pass "self-compare shows zero delta" || fail "no zero delta found"

# ── T6: exit codes ──
echo ""
echo "T6: exit codes"
rm "$FIX/.asp/config/profile-map.yaml"
bash "$SCRIPT" --repo-root "$FIX" >/dev/null 2>&1; RC=$?
[ "$RC" = "4" ] && pass "missing map → exit 4" || fail "missing map rc=$RC (expected 4)"
build_fixture
bash "$SCRIPT" --repo-root "$TEST_DIR/nonexistent" >/dev/null 2>&1; RC=$?
[ "$RC" = "3" ] && pass "missing profiles dir → exit 3" || fail "missing profiles rc=$RC (expected 3)"
bash "$SCRIPT" --repo-root "$FIX" --bogus-flag >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && pass "unknown arg → exit 1" || fail "unknown arg rc=$RC (expected 1)"

# ── T7: real repo smoke test (auto-adapts to later phases) ──
echo ""
echo "T7: real repo smoke"
REAL=$(bash "$SCRIPT" --repo-root "$ASP_ROOT" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && pass "real repo exit 0" || fail "real repo rc=$RC"
WANT=$(ls "$ASP_ROOT/.asp/profiles/"*.md | wc -l | tr -d ' ')
GOT=$(echo "$REAL" | jq -r '.profiles.count')
[ "$GOT" = "$WANT" ] && pass "profiles.count matches ls ($WANT)" || fail "profiles.count=$GOT want=$WANT"
for cfg in L1_content L3_system_design L5_autonomous; do
  M=$(echo "$REAL" | jq -c ".context_tax.${cfg}.missing_profiles")
  [ "$M" = "[]" ] && pass "$cfg missing_profiles empty" || fail "$cfg missing_profiles=$M (map/實檔脫鉤)"
done
echo "$REAL" | jq -e '.context_tax.L5_autonomous.profiles_loaded | index("global_core")' >/dev/null \
  && pass "L5 loads global_core" || fail "L5 missing global_core"
T1=$(echo "$REAL" | jq -r '.context_tax.L1_content.total')
T5=$(echo "$REAL" | jq -r '.context_tax.L5_autonomous.total')
[ "$T1" -lt "$T5" ] && pass "context tax L1($T1) < L5($T5)" || fail "tax ordering wrong: L1=$T1 L5=$T5"

# ── T8: ghost reference tolerance ──
echo ""
echo "T8: ghost reference tolerance"
build_fixture
cat >> "$FIX/.asp/config/profile-map.yaml" <<'EOF'
EOF
# inject a rule loading a nonexistent profile
awk '1; /load: "global_core"$/ && !done { print "  - when: \"type=content\""; print "    load: \"ghost_profile\""; done=1 }' \
  "$FIX/.asp/config/profile-map.yaml" > "$FIX/.asp/config/profile-map.yaml.tmp" \
  && mv "$FIX/.asp/config/profile-map.yaml.tmp" "$FIX/.asp/config/profile-map.yaml"
SIM=$(bash "$SCRIPT" --repo-root "$FIX" --simulate "type=content" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && pass "ghost reference → exit 0" || fail "ghost rc=$RC"
echo "$SIM" | jq -e '.missing_profiles | index("ghost_profile")' >/dev/null \
  && pass "ghost recorded in missing_profiles" || fail "ghost not recorded: $(echo "$SIM" | jq -c '.missing_profiles')"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
