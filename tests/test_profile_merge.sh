#!/usr/bin/env bash
# test_profile_merge.sh — v5 Phase 1 profile merge acceptance (ADR-014).
# Asserts: 13 profiles; loose_mode carries the [spike] exemption + role table
# (red-line content from vibe_coding/spike_mode); global_core absorbed
# escalation (P0-P3) + guardrail (three-layer response) + HITL levels and kept
# all three 繞過藉口 tables; archives exist; no live /asp-escalate references.
# Run: bash tests/test_profile_merge.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P="$ASP_ROOT/.asp/profiles"
GC="$P/global_core.md"
LM="$P/loose_mode.md"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# ── T1: profile count = 13 (Phase 1 target; Phase 2 adds orchestrator_multi_agent → 14; Phase 4 → 12) ──
echo ""
echo "T1: profiles count"
COUNT=$(ls "$P"/*.md | wc -l | tr -d ' ')
case "$COUNT" in
  13|14|12) pass "profiles = $COUNT (valid for current phase)" ;;
  *) fail "profiles = $COUNT (expected 13/14/12 depending on phase)" ;;
esac
for gone in vibe_coding spike_mode escalation guardrail; do
  [ ! -f "$P/$gone.md" ] && pass "$gone.md removed from live profiles" || fail "$gone.md still in .asp/profiles/"
done

# ── T2: loose_mode.md content (red-line carriers) ──
echo ""
echo "T2: loose_mode carries spike exemption + vibe role table"
[ -f "$LM" ] || { fail "loose_mode.md missing"; echo "Results: ${PASS}/${TOTAL}, ${FAIL} failed"; exit 1; }
grep -q '\[spike\]' "$LM" && pass "[spike] explicit exemption marker present" || fail "[spike] marker missing"
grep -q '角色分工' "$LM" && pass "role-division table present" || fail "role table missing"
grep -q 'conflicts: autonomous_dev, autopilot, pipeline, multi_agent' "$LM" \
  && pass "conflicts header inherited from spike" || fail "conflicts header wrong"
grep -q 'spike-conclusion' "$LM" && pass "spike conclusion checklist kept" || fail "spike conclusion missing"
grep -q '絕不可跳過' "$LM" && pass "never-skip table kept" || fail "never-skip table missing"
grep -qE 'Step 9|憑證掃描' "$LM" && pass "credential-scan red line referenced" || fail "Step 9 reference missing"

# ── T3: global_core absorbed sections ──
echo ""
echo "T3: global_core absorbed escalation/guardrail/HITL"
grep -q '升級路徑' "$GC" && pass "escalation section present" || fail "升級路徑 missing"
grep -qE 'P0.*緊急|P0.*P1.*P2.*P3' "$GC" && pass "P0-P3 severity table present" || fail "P0-P3 table missing"
grep -q '三層回應' "$GC" && pass "guardrail three-layer section present" || fail "三層回應 missing"
grep -q 'should_pause' "$GC" && pass "HITL should_pause moved in" || fail "should_pause missing"
grep -q 'minimal 模式行為規範' "$GC" && pass "minimal behaviour table moved in" || fail "minimal table missing"
N=$(grep -c '繞過藉口' "$GC")
[ "$N" -ge 3 ] && pass "繞過藉口 tables ≥3 (red line 4: $N)" || fail "繞過藉口 tables = $N (<3)"
grep -q 'asp-escalate' "$GC" && fail "global_core still references ghost /asp-escalate" || pass "no ghost /asp-escalate"
grep -q 'asp-handoff' "$GC" && pass "escalation routes to /asp-handoff" || fail "no /asp-handoff routing"

# ── T4: archives exist ──
echo ""
echo "T4: merged sources archived"
for a in vibe_coding spike_mode escalation guardrail; do
  [ -f "$ASP_ROOT/docs/archive/profiles/$a.md" ] && pass "archive/$a.md exists" || fail "archive/$a.md missing"
done

# ── T5: no live references to merged profile files (excluding archives & ADR/SPEC/CHANGELOG history) ──
echo ""
echo "T5: zero live references"
HITS=$(grep -rn 'vibe_coding\|spike_mode\|escalation\.md\|guardrail\.md' \
  "$ASP_ROOT/.asp" "$ASP_ROOT/.claude" "$ASP_ROOT/CLAUDE.md" "$ASP_ROOT/CONTEXT.md" 2>/dev/null \
  | grep -v 'docs/archive' || true)
[ -z "$HITS" ] && pass "no live refs in .asp/.claude/CLAUDE.md/CONTEXT.md" \
  || fail "live refs remain: $(echo "$HITS" | head -3)"
HITS2=$(grep -rln 'asp-escalate' "$ASP_ROOT/.asp" "$ASP_ROOT/.claude" "$ASP_ROOT/CLAUDE.md" "$ASP_ROOT/CONTEXT.md" 2>/dev/null | grep -v docs/archive || true)
[ -z "$HITS2" ] && pass "no live /asp-escalate refs" || fail "asp-escalate refs remain: $HITS2"

# ── T6: autonomous_dev requires fixed (D2) ──
echo ""
echo "T6: autonomous_dev dependency adjudication"
grep -q '<!-- requires: global_core, system_dev -->' "$P/autonomous_dev.md" \
  && pass "autonomous_dev requires = global_core, system_dev" || fail "autonomous_dev requires not updated"

# ── T7: install.sh / install.ps1 三級制契約（ps1 無法本機執行 → grep 契約；
#        tech-debt: MED test-pending install.ps1 Windows 實測 (DUE: 2026-09-30) ──
echo ""
echo "T7: installer three-level contract"
INS="$ASP_ROOT/.asp/scripts/install.sh"
PS1="$ASP_ROOT/.asp/scripts/install.ps1"
grep -q 'apply_preset loose' "$INS" && pass "install.sh has loose preset" || fail "install.sh loose preset missing"
grep -q 'ENABLE_GUARDRAIL' "$INS" && fail "install.sh still sets ENABLE_GUARDRAIL" || pass "install.sh guardrail field dropped"
grep -q "ASP_LEVEL:-loose" "$INS" && pass "install.sh non-interactive default = loose" || fail "non-interactive default wrong"
for n in loose standard autonomous; do
  grep -q "'$n'" "$PS1" && pass "install.ps1 knows '$n'" || fail "install.ps1 missing '$n'"
done
grep -q 'L1 Starter' "$PS1" && fail "install.ps1 still shows v4 level menu" || pass "install.ps1 v4 menu removed"
bash -n "$INS" && pass "install.sh syntax ok" || fail "install.sh syntax error"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
