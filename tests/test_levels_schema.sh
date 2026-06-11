#!/usr/bin/env bash
# test_levels_schema.sh — v5 three-level taxonomy schema guard (ADR-014).
# Asserts: exactly 3 level yamls; required fields; every profile listed in a
# level yaml has a real file (ghost-reference regression guard); next_level
# chain loose→standard→autonomous→null; aliases cover 0-5 exactly once.
# Run: bash tests/test_levels_schema.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEVELS_DIR="$ASP_ROOT/.asp/levels"
PROFILES_DIR="$ASP_ROOT/.asp/profiles"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# ── T1: exactly 3 yamls, named loose/standard/autonomous ──
echo ""
echo "T1: exactly 3 level files"
COUNT=$(ls "$LEVELS_DIR"/*.yaml 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" = "3" ] && pass "3 yaml files" || fail "found $COUNT yaml files"
for n in loose standard autonomous; do
  [ -f "$LEVELS_DIR/$n.yaml" ] && pass "$n.yaml exists" || fail "$n.yaml missing"
done

# ── T2: required fields ──
echo ""
echo "T2: required fields per yaml"
for n in loose standard autonomous; do
  f="$LEVELS_DIR/$n.yaml"
  [ -f "$f" ] || { fail "$n.yaml missing (skip fields)"; continue; }
  for field in level name tagline profiles graduation_checklist next_level aliases; do
    grep -qE "^${field}:" "$f" && pass "$n.$field present" || fail "$n.$field MISSING"
  done
  grep -qE "^level: ${n}$" "$f" && pass "$n.level value matches filename" || fail "$n.level value mismatch"
done

# ── T3: ghost-reference guard — every listed profile has a real file ──
echo ""
echo "T3: profiles listed in level yamls all exist"
for n in loose standard autonomous; do
  f="$LEVELS_DIR/$n.yaml"
  [ -f "$f" ] || continue
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$PROFILES_DIR/$p.md" ] \
      && pass "$n: $p.md exists" || fail "$n: GHOST profile reference '$p'"
  done < <(awk '/^profiles:/{flag=1; next} /^[a-z_]/{flag=0} flag && /^  - /{sub(/^  - /,""); sub(/[ #].*$/,""); print}' "$f")
done

# ── T4: next_level chain ──
echo ""
echo "T4: next_level chain loose→standard→autonomous→null"
chain_ok=1
[ "$(grep -E '^next_level:' "$LEVELS_DIR/loose.yaml" 2>/dev/null | awk '{print $2}')" = "standard" ] || chain_ok=0
[ "$(grep -E '^next_level:' "$LEVELS_DIR/standard.yaml" 2>/dev/null | awk '{print $2}')" = "autonomous" ] || chain_ok=0
[ "$(grep -E '^next_level:' "$LEVELS_DIR/autonomous.yaml" 2>/dev/null | awk '{print $2}')" = "null" ] || chain_ok=0
[ "$chain_ok" = "1" ] && pass "chain correct" || fail "chain broken"

# ── T5: aliases cover 0-5 exactly once across the three files ──
echo ""
echo "T5: aliases cover digits 0-5 exactly once"
ALL=$(grep -hE '^aliases:' "$LEVELS_DIR"/*.yaml 2>/dev/null | sed 's/#.*//' | grep -oE '[0-9]' | sort)
[ "$(echo "$ALL" | tr '\n' ' ' | xargs)" = "0 1 2 3 4 5" ] \
  && pass "aliases = {0,1,2,3,4,5} with no dup/gap" || fail "aliases coverage wrong: $(echo "$ALL" | xargs)"

# ── T6: no legacy/archived profile names in profiles:/auto_load: blocks ──
echo ""
echo "T6: no ghost/archived profile names in level load lists"
HITS=""
for n in loose standard autonomous; do
  f="$LEVELS_DIR/$n.yaml"
  [ -f "$f" ] || continue
  H=$(awk '/^(profiles|auto_load):/{flag=1; next} /^[a-z_]/{flag=0} flag && /^  - /{sub(/^  - /,""); sub(/[ #].*$/,""); print FILENAME": "$0}' FILENAME="$n" "$f" \
    | grep -E ': (multi_agent|spike_mode|vibe_coding|escalation|guardrail)$' || true)
  [ -n "$H" ] && HITS="$HITS $H"
done
[ -z "$HITS" ] && pass "no archived names in load lists" || fail "ghost names found:$HITS"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
