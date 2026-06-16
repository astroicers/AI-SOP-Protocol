#!/usr/bin/env bash
# test_validate_profile.sh — tests for .asp/scripts/validate-profile.sh
# (governance-critical: validates .ai_profile field constraints + dependency
# auto-fix). Also a regression for the TD/review fix replacing non-portable
# `sed -i` with portable awk for the frontend_quality auto-insert.
# Run: bash tests/test_validate_profile.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/validate-profile.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-vp-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

P() { echo "$TEST_DIR/.ai_profile"; }
OUT=""; RC=0
run() { OUT=$(bash "$SCRIPT" "$(P)" 2>&1); RC=$?; }

# ── T1: missing profile → exit 1 ──
echo ""
echo "T1: missing profile → exit 1"
OUT=$(bash "$SCRIPT" "$TEST_DIR/nope" 2>&1); RC=$?
[ "$RC" = "1" ] && pass "missing profile exits 1" || fail "missing profile rc=$RC (expected 1)"

# ── T2: missing required 'type' → ERROR + exit 1 ──
echo ""
echo "T2: missing 'type' → ERROR, exit 1"
printf 'level: 2\n' > "$(P)"; run
{ grep -q "缺少必填欄位 type" <<<"$OUT" && [ "$RC" = "1" ]; } \
  && pass "missing type produces ERROR + exit 1" || fail "missing type not caught (rc=$RC)"

# ── T3: invalid level → ERROR ──
echo ""
echo "T3: invalid level value → ERROR"
printf 'type: system\nlevel: 9\n' > "$(P)"; run
grep -q "level 值無效" <<<"$OUT" && pass "invalid level → ERROR" || fail "invalid level not caught"

# ── T3a: legacy numeric level → deprecation WARNING, not ERROR (v5 ADR-014) ──
echo ""
echo "T3a: legacy numeric level → WARNING + mapped, exit != 1"
printf 'type: system\nlevel: 3\n' > "$(P)"; run
grep -q "v4 數字等級" <<<"$OUT" && pass "deprecation warning shown" || fail "no deprecation warning"
grep -q "level: standard" <<<"$OUT" && pass "mapped to standard" || fail "not mapped to standard"
[ "$RC" != "1" ] && pass "numeric level does not exit 1" || fail "numeric level exits 1"

# ── T3b: named level passes cleanly ──
echo ""
echo "T3b: level: standard → ✅, no warning"
printf 'type: system\nlevel: standard\n' > "$(P)"; run
{ grep -q "✅ level: standard" <<<"$OUT" && [ "$RC" = "0" ]; } \
  && pass "named level ok, exit 0" || fail "named level rc=$RC"

# ── T3c: workflow vibe-coding loads loose_mode; with autonomous → conflict WARNING ──
echo ""
echo "T3c: vibe-coding → loose_mode; +autonomous → conflict warning"
printf 'type: system\nlevel: standard\nworkflow: vibe-coding\n' > "$(P)"; run
grep -q "loose_mode.md" <<<"$OUT" && pass "vibe-coding lists loose_mode.md" || fail "loose_mode.md not listed"
printf 'type: system\nworkflow: vibe-coding\nautonomous: enabled\n' > "$(P)"; run
grep -q "衝突" <<<"$OUT" && pass "vibe-coding+autonomous → conflict warning" || fail "no conflict warning"

# ── T3d: guardrail field deprecated → INFO ──
echo ""
echo "T3d: guardrail: enabled → deprecated INFO"
printf 'type: system\nlevel: standard\nguardrail: enabled\n' > "$(P)"; run
grep -q "guardrail 欄位已 deprecated" <<<"$OUT" && pass "guardrail INFO shown" || fail "no guardrail INFO"

# ── T4: invalid hitl → ERROR ──
echo ""
echo "T4: invalid hitl value → ERROR"
printf 'type: system\nhitl: bogus\n' > "$(P)"; run
grep -q "hitl 值無效" <<<"$OUT" && pass "invalid hitl → ERROR" || fail "invalid hitl not caught"

# ── T5: design:enabled w/o frontend_quality → WARNING + portable auto-fix ──
echo ""
echo "T5: design:enabled auto-adds frontend_quality right after design line (portable awk)"
printf 'type: system\ndesign: enabled\nlevel: 1\n' > "$(P)"; run
grep -q "^frontend_quality: enabled" "$(P)" && pass "auto-fix added frontend_quality" || fail "frontend_quality not auto-added"
awk '/^design:/{getline n; if (n=="frontend_quality: enabled") ok=1} END{exit !ok}' "$(P)" \
  && pass "frontend_quality inserted immediately after design (awk insert correct)" \
  || fail "frontend_quality not placed after design line"

# ── T6: idempotent — re-run does not duplicate frontend_quality ──
echo ""
echo "T6: re-run does not duplicate the auto-added field"
run
[ "$(grep -c '^frontend_quality: enabled' "$(P)")" = "1" ] && pass "no duplicate frontend_quality on re-run" || fail "frontend_quality duplicated"

# ── T7: fully valid profile → 驗證通過, exit 0 ──
echo ""
echo "T7: valid profile → pass, exit 0"
printf 'type: system\nlevel: standard\nhitl: standard\nmode: single\n' > "$(P)"; run
{ grep -q "驗證通過" <<<"$OUT" && [ "$RC" = "0" ]; } \
  && pass "valid profile passes with exit 0" || fail "valid profile not passing (rc=$RC)"

# ── T8: 手編 .ai_profile 比編譯產物新 → stale 提示（ADR-016 配套；純提示不改 rc） ──
echo ""
echo "T8: .ai_profile newer than compiled artifact → stale 提示"
printf 'type: system\nlevel: standard\n' > "$(P)"
ART="$TEST_DIR/.asp-compiled-profile.md"
: > "$ART"; touch -d '2020-01-01' "$ART"; touch "$(P)"   # artifact 舊、profile 新
run
{ grep -q "編譯產物可能 stale" <<<"$OUT" && [ "$RC" = "0" ]; } \
  && pass "stale 提示出現且不改 rc" || fail "stale 提示缺失或誤改 rc=$RC"
touch -d '2099-01-01' "$ART"; run                        # artifact 未來（fresh）→ 不提示
grep -q "編譯產物可能 stale" <<<"$OUT" && fail "fresh 時誤報 stale" || pass "fresh 時不提示"
rm -f "$ART"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
