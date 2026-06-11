#!/usr/bin/env bash
# test_autopilot_consolidation.sh — SPEC-010: autopilot profile→skill 整併（ADR-006 Item 7）
# S2: profile 已刪 + skill 為 canonical + ledger「遷入」節錨點存在
# S3: 活引用收斂（CLAUDE.md / validate-profile.sh / SKILL.md 無已刪 profile 活引用）
# S4: 歷史文件不被竄改（抽查）
# Run: bash tests/test_autopilot_consolidation.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ASP_ROOT/.claude/skills/asp/asp-autopilot.md"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# ── S2a: profile 已刪 ──
echo ""; echo "S2a: .asp/profiles/autopilot.md deleted"
[ ! -f "$ASP_ROOT/.asp/profiles/autopilot.md" ] \
    && pass "profile 已刪除" || fail "profile 仍存在"

# ── S2b: skill 含 canonical 標記 ──
echo ""; echo "S2b: skill carries canonical marker"
grep -q "唯一 canonical source" "$SKILL" && grep -q "ADR-006 Item 7" "$SKILL" \
    && pass "canonical 標記存在" || fail "缺 canonical 標記"

# ── S2c: ledger「遷入」節錨點存在於 skill ──
echo ""; echo "S2c: migrated section anchors present in skill"
for anchor in "前置文件動態探測" "CLAUDE.md 專案描述自動產生" "Profile 自動載入" "核心流程" "Session Bridge 狀態檔" "ROADMAP 更新規則" "安全邊界" "與其他 Profile 的關係"; do
    grep -q "$anchor" "$SKILL" \
        && pass "錨點「$anchor」存在" || fail "錨點「$anchor」遺失"
done

# ── S3: 活引用收斂 ──
echo ""; echo "S3: no live references to deleted profile"
for live in "CLAUDE.md" ".asp/scripts/validate-profile.sh" ".claude/skills/asp/SKILL.md" "README.md" "docs/where-to-start.md"; do
    f="$ASP_ROOT/$live"
    [ -f "$f" ] || continue
    if grep -qE '(\.asp/)?profiles/autopilot\.md' "$f"; then
        fail "$live 仍有活引用"
    else
        pass "$live 無活引用"
    fi
done

# ── S4: 歷史文件抽查（不可被本次改動）──
echo ""; echo "S4: historical references untouched (spot check)"
grep -q "asp/profiles/autopilot.md" "$ASP_ROOT/docs/adr/ADR-012-define-operator-autopilot-interaction-trust-model.md" 2>/dev/null \
    && pass "ADR-012 歷史路徑字樣保留" || fail "ADR-012 歷史字樣被改動（E2 違反）"
grep -rq "autopilot.md" "$ASP_ROOT/CHANGELOG.md" \
    && pass "CHANGELOG 歷史字樣保留" || fail "CHANGELOG 歷史字樣異常"

echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
