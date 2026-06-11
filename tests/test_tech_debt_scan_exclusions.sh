#!/usr/bin/env bash
# test_tech_debt_scan_exclusions.sh — A8.3 tech-debt 掃描不得把框架文件的
# 「格式範例」標記當成真實逾期債務（2026-06-11 假陽性修復的回歸測試）。
# Run: bash tests/test_tech_debt_scan_exclusions.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ASP_ROOT/.asp/hooks/session-audit.sh"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# ── T1: 契約 — A8 掃描含框架文件路徑排除 ──
echo ""
echo "T1: A8 scan excludes framework-doc example paths"
A8_SECTION=$(sed -n '/Tech Debt 過期掃描/,/依賴健康檢查/p' "$HOOK")
echo "$A8_SECTION" | grep -q '\.asp/profiles/' \
    && pass "excludes .asp/profiles/ (format examples live here)" || fail ".asp/profiles/ not excluded"
echo "$A8_SECTION" | grep -q '\.asp/templates/' \
    && pass "excludes .asp/templates/" || fail ".asp/templates/ not excluded"
echo "$A8_SECTION" | grep -q '\.claude/skills/' \
    && pass "excludes .claude/skills/" || fail ".claude/skills/ not excluded"
echo "$A8_SECTION" | grep -q 'docs/runbooks/' \
    && pass "excludes docs/runbooks/ (templates)" || fail "docs/runbooks/ not excluded"

# ── T2: 行為 — 重演掃描管線：範例標記被排除、真實標記被計數 ──
echo ""
echo "T2: pipeline behavior — example markers excluded, real markers counted"
SANDBOX=$(mktemp -d /tmp/asp-test-a83-XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/.asp/profiles" "$SANDBOX/src"
# 註：以 printf 拼接組出標記，避免本測試檔自身被 A8.3 掃描命中（變成新的假陽性）
printf '範例：`tech-debt: HIGH security 範例項 (%s 2026-04-10)`\n' "DUE:" > "$SANDBOX/.asp/profiles/doc.md"
printf '# tech-debt: HIGH test-pending real overdue item (%s 2026-01-01)\n' "DUE:" > "$SANDBOX/src/real.sh"

# 以 hook 內相同的掃描管線（grep + 路徑排除）重演
HITS=$(grep -rn "tech-debt:.*HIGH.*DUE:" "$SANDBOX" --include="*.md" --include="*.sh" --exclude-dir=".git" 2>/dev/null \
    | grep -vE '(\.asp/profiles/|\.asp/templates/|\.claude/skills/|docs/runbooks/)' || true)
COUNT=$(echo "$HITS" | grep -c "DUE:" || true); COUNT=${COUNT:-0}
[ "$COUNT" -eq 1 ] && pass "exactly 1 hit (real marker only, example excluded)" \
    || fail "expected 1 hit, got $COUNT: $HITS"
echo "$HITS" | grep -q "real.sh" && pass "the surviving hit is the real marker" \
    || fail "real marker missing from results"

# ── T3: 本 repo 實際掃描 — 已知 global_core.md 範例不再命中 ──
echo ""
echo "T3: in-repo scan no longer hits global_core.md examples"
# 排除清單與 session-audit.sh A8.3 同步（v5 ADR-018 dogfood：+compiled artifact、
# archive、experimental/showcase——編譯產物複製框架範例曾復活假陽性）
REPO_HITS=$(grep -rn "tech-debt:.*HIGH.*DUE:" "$ASP_ROOT" --include="*.md" --include="*.sh" --exclude-dir=".git" 2>/dev/null \
    | grep -vE '(\.asp/profiles/|\.asp/templates/|\.claude/skills/|docs/runbooks/|\.asp-compiled-profile\.md|docs/archive/|experimental/|showcase/)' \
    | grep -v "tests/test_tech_debt_scan_exclusions.sh" \
    | grep -vE 'session-audit\.sh.*grep' || true)
if echo "$REPO_HITS" | grep -qE "global_core.md|asp-compiled-profile"; then
    fail "global_core.md/compiled artifact examples still scanned"
else
    pass "global_core.md examples excluded"
fi

# ── 結果 ──
echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
