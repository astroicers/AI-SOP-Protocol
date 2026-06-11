#!/usr/bin/env bash
# test_autopilot_provenance_gate.sh — SPEC-008: autopilot 外部來源 provenance 閘
# (ADR-012 INV-2/DP2/DP8)。文字契約測試：autopilot.md 是 AI 解讀的 profile，
# 本測試斷言 profile 含正確閘邏輯、且既有內部閘（DP3）未被破壞。
# Run: bash tests/test_autopilot_provenance_gate.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="$ASP_ROOT/.claude/skills/asp/asp-autopilot.md"
SKILL="$ASP_ROOT/.claude/skills/asp/asp-autopilot.md"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

[ -f "$PROFILE" ] || { echo "FATAL: $PROFILE not found"; exit 1; }

# 擷取 provenance 閘段落（標記行至既有 ADR 閘標記行之間）供區段內斷言
GATE_SECTION=$(sed -n '/SPEC-008.*provenance 閘/,/驗證 ADR 狀態 + 智能評估架構影響/p' "$PROFILE")

# ── S1/P1: provenance 判別函式存在且涵蓋兩欄位 ──
echo ""
echo "S1: is_external_provenance defined with source_type + triggered_by rules"
grep -q "is_external_provenance" "$PROFILE" \
    && pass "is_external_provenance defined" || fail "is_external_provenance missing"
echo "$GATE_SECTION" | grep -q "source_type" \
    && pass "rule covers source_type" || fail "source_type not in gate section"
echo "$GATE_SECTION" | grep -q "triggered_by" \
    && pass "rule covers triggered_by" || fail "triggered_by not in gate section"

# ── S2/P2: 外部 + 無 ADR → blocked，含 INV-2 與 SPEC-009 過渡語意 ──
echo ""
echo "S2: external task without ADR is blocked (INV-2, SPEC-009 transition)"
echo "$GATE_SECTION" | grep -q "INV-2" \
    && pass "gate cites INV-2" || fail "no INV-2 reference in gate"
echo "$GATE_SECTION" | grep -q "SPEC-009" \
    && pass "gate cites SPEC-009 transition" || fail "no SPEC-009 transition reference"
echo "$GATE_SECTION" | grep -q "blocked_by_provenance" \
    && pass "blocked_by_provenance list exists" || fail "blocked_by_provenance missing"

# ── S3/P3: 外部任務不適用 FIRM 🟡 豁免 ──
echo ""
echo "S3: external tasks get NO FIRM yellow-flag exemption"
echo "$GATE_SECTION" | grep -q "FIRM" \
    && pass "gate addresses FIRM explicitly" || fail "gate silent on FIRM (exemption ambiguity)"
echo "$GATE_SECTION" | grep -qE 'Accepted' \
    && pass "gate requires Accepted" || fail "gate does not require Accepted"

# ── S4/N1: provenance 閘段內不自動建 Draft ADR ──
echo ""
echo "S4: provenance gate never auto-creates Draft ADRs for external tasks"
if echo "$GATE_SECTION" | grep -q "make adr-new"; then
    fail "provenance gate auto-creates ADRs (C1 noise; belongs to asp-op pivot)"
else
    pass "no make adr-new inside provenance gate"
fi

# ── S5/B1: 既有內部閘逐字保留（DP3 向後相容） ──
echo ""
echo "S5: existing internal ADR gate intact (DP3 backward compatibility)"
grep -q "blocked_by_adr = \[\]" "$PROFILE" \
    && pass "blocked_by_adr list intact" || fail "blocked_by_adr removed/renamed"
grep -q "adr = FIND_ADR(task.adr)" "$PROFILE" \
    && pass "FIND_ADR validation intact" || fail "FIND_ADR validation altered"
grep -q 'adr.status == "FIRM"' "$PROFILE" \
    && pass "internal FIRM yellow-flag path intact" || fail "internal FIRM path altered"
grep -q "assess_architecture_impact(task)" "$PROFILE" \
    && pass "adr:null impact assessment intact" || fail "impact assessment altered"
grep -q "blocked_tasks = blocked_by_provenance + blocked_by_adr + cycle_tasks" "$PROFILE" \
    && pass "blocked merge includes provenance list" || fail "provenance list not merged into blocked_tasks"

# ── S6/B2: asp-autopilot skill 摘要同步 ──
echo ""
echo "S6: asp-autopilot skill summary mentions provenance gate"
if [ -f "$SKILL" ]; then
    grep -qE "provenance|外部來源" "$SKILL" \
        && pass "skill summary mentions provenance gate" || fail "skill summary not synced"
else
    fail "skill file not found: $SKILL"
fi

# ── 結果 ──
echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
