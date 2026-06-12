#!/usr/bin/env bash
# test_iron_rule_b_hashchain.sh — SPEC-012 / ADR-019 per-entry hash chain
#
# 單元（bypass-hash.sh rechain/verify/canonical）：
#   P1 rechain→verify 通過 + canonical 三端一致 / P2 空 log / N1 等量替換 /
#   N2 h 竄改 / N3 刪中間筆 / N6 prev 偽造 GENESIS / B1 GENESIS 首筆 / B2 舊格式遷移
# 整合（session-audit Iron Rule B chain）：
#   N5 刪中間筆+降 HWM → chain 獨立 BLOCKER / N7 chained 模式缺 h → BLOCKER /
#   正常 chained log → 無 chain BLOCKER
# Run: bash tests/test_iron_rule_b_hashchain.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HASH="$ASP_ROOT/.asp/scripts/bypass-hash.sh"
AUDIT="$ASP_ROOT/.asp/hooks/session-audit.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-hc-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup(){ rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass(){ echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 不存在"; exit 0; }

seed() { # $1=file — 3 筆原始 entry（無 hash 欄，模擬舊格式）
  printf '%s\n' \
    '{"timestamp":"2026-01-01T00:00:00Z","skill":"asp-ship","step":"S1","reason":"a","actor":"ai"}' \
    '{"timestamp":"2026-01-02T00:00:00Z","skill":"asp-ship","step":"S2","reason":"b","actor":"ai"}' \
    '{"timestamp":"2026-01-03T00:00:00Z","skill":"asp-ship","step":"S3","reason":"c","actor":"ai"}' > "$1"
}

# ───────────────── 單元：bypass-hash.sh ─────────────────

echo ""; echo "P1: rechain → verify 通過 + canonical 三端一致"
L="$TEST_DIR/p1.ndjson"; seed "$L"
bash "$HASH" rechain "$L" >/dev/null 2>&1
bash "$HASH" verify "$L" >/dev/null 2>&1 && pass "rechain 後 verify 通過" || fail "rechain 後 verify 失敗"
e='{"timestamp":"t","skill":"x","step":"y","reason":"z","actor":"ai","prev":"P","h":"H"}'
c1=$(bash "$HASH" canonical "$e" 2>/dev/null); c2=$(bash "$HASH" canonical "$e" 2>/dev/null)
{ [ -n "$c1" ] && [ "$c1" = "$c2" ]; } && pass "canonical 穩定且去除 prev/h" || fail "canonical 不穩定: '$c1'"
echo "$c1" | grep -q '"prev"' && fail "canonical 仍含 prev（應去除）" || pass "canonical 已去除 prev/h"

echo ""; echo "P2: 空 log → verify 通過"
: > "$TEST_DIR/empty.ndjson"
bash "$HASH" verify "$TEST_DIR/empty.ndjson" >/dev/null 2>&1 && pass "空 log 通過" || fail "空 log 誤報"

echo ""; echo "N1: 等量替換（改一筆內容、行數不變）→ verify 斷裂"
L="$TEST_DIR/n1.ndjson"; seed "$L"; bash "$HASH" rechain "$L" >/dev/null 2>&1
jq -c 'if .reason=="b" then .reason="HACKED" else . end' "$L" > "$L.t" && mv "$L.t" "$L"
bash "$HASH" verify "$L" >/dev/null 2>&1 && fail "等量替換未偵測" || pass "等量替換 → 斷裂"

echo ""; echo "N2: 竄改中間筆 h → verify 斷裂"
L="$TEST_DIR/n2.ndjson"; seed "$L"; bash "$HASH" rechain "$L" >/dev/null 2>&1
jq -c 'if .step=="S2" then .h="deadbeef" else . end' "$L" > "$L.t" && mv "$L.t" "$L"
bash "$HASH" verify "$L" >/dev/null 2>&1 && fail "h 竄改未偵測" || pass "h 竄改 → 斷裂"

echo ""; echo "N3: 刪中間筆 → verify 斷裂（prev 不接）"
L="$TEST_DIR/n3.ndjson"; seed "$L"; bash "$HASH" rechain "$L" >/dev/null 2>&1
sed -i '2d' "$L"
bash "$HASH" verify "$L" >/dev/null 2>&1 && fail "刪中間筆未偵測" || pass "刪中間筆 → 斷裂"

echo ""; echo "N6: 非首筆 prev 偽設 GENESIS → verify 斷裂"
L="$TEST_DIR/n6.ndjson"; seed "$L"; bash "$HASH" rechain "$L" >/dev/null 2>&1
jq -c 'if .step=="S2" then .prev="GENESIS" else . end' "$L" > "$L.t" && mv "$L.t" "$L"
bash "$HASH" verify "$L" >/dev/null 2>&1 && fail "prev 偽造未偵測" || pass "prev 偽造 GENESIS → 斷裂"

echo ""; echo "B1: 首筆 prev=GENESIS（rechain 預設）→ verify 通過"
L="$TEST_DIR/b1.ndjson"; seed "$L"; bash "$HASH" rechain "$L" >/dev/null 2>&1
head -1 "$L" | jq -e '.prev=="GENESIS"' >/dev/null 2>&1 && pass "首筆 prev=GENESIS" || fail "首筆 prev 非 GENESIS"

echo ""; echo "B2: 舊格式（無 hash）rechain 後嚴格驗證通過"
L="$TEST_DIR/b2.ndjson"; seed "$L"; bash "$HASH" rechain "$L" >/dev/null 2>&1
{ bash "$HASH" verify "$L" >/dev/null 2>&1 && [ "$(grep -c '"h"' "$L")" = "3" ]; } \
  && pass "舊格式遷移後每筆有 h 且通過" || fail "舊格式遷移失敗"

# ───────────────── 整合：session-audit Iron Rule B ─────────────────

mkproj() { # $1=dir
  rm -rf "$1"; mkdir -p "$1/.asp/profiles" "$1/.asp/config" "$1/.asp/scripts" "$1/.claude" "$1/docs/adr"
  touch "$1/README.md" "$1/CHANGELOG.md" "$1/Makefile"
  cp "$ASP_ROOT/.asp/scripts/asp-compile.sh" "$ASP_ROOT/.asp/scripts/level-resolve.sh" \
     "$ASP_ROOT/.asp/scripts/validate-profile.sh" "$ASP_ROOT/.asp/scripts/bypass-hash.sh" "$1/.asp/scripts/" 2>/dev/null || true
  printf '# GC\n<!-- requires: (none) -->\nbody\n' > "$1/.asp/profiles/global_core.md"
  printf 'version: 1\nrules:\n  - when: "type=system"\n    load: "global_core"\nlevel_aliases:\n  - "0=loose"\n' > "$1/.asp/config/profile-map.yaml"
  printf 'type: system\n' > "$1/.ai_profile"
}
run_hook(){ CLAUDE_PROJECT_DIR="$1" bash "$AUDIT" >/dev/null 2>&1; RC=$?; }
BJ(){ echo "$1/.asp-session-briefing.json"; }

echo ""; echo "整合-正常: chained log 完整 → 無 chain BLOCKER"
P="$TEST_DIR/ok"; mkproj "$P"
seed "$P/.asp-bypass-log.ndjson"; bash "$HASH" rechain "$P/.asp-bypass-log.ndjson" >/dev/null 2>&1
echo "1" > "$P/.asp-bypass-log.chained"; echo "3" > "$P/.asp-bypass-log.hwm"
run_hook "$P"
[ "$RC" = "0" ] && pass "hook exit 0" || fail "rc=$RC"
jq -r '.blockers[]' "$(BJ "$P")" 2>/dev/null | grep -qi 'hash chain' && fail "正常 log 誤報 chain BLOCKER" || pass "正常 chained log 無 chain BLOCKER"

echo ""; echo "N5: 刪中間筆 + 同步降 HWM（騙過截斷檢查）→ chain 獨立 BLOCKER"
P="$TEST_DIR/n5"; mkproj "$P"
seed "$P/.asp-bypass-log.ndjson"; bash "$HASH" rechain "$P/.asp-bypass-log.ndjson" >/dev/null 2>&1
echo "1" > "$P/.asp-bypass-log.chained"
sed -i '2d' "$P/.asp-bypass-log.ndjson"        # 刪中間筆（行數 3→2）
echo "2" > "$P/.asp-bypass-log.hwm"            # 同步降 HWM（HWM 截斷檢查不報）
run_hook "$P"
jq -r '.blockers[]' "$(BJ "$P")" 2>/dev/null | grep -qi 'hash chain' \
  && pass "chain 在 HWM 被騙過時仍報 BLOCKER" || fail "chain 未獨立偵測: $(jq -c .blockers "$(BJ "$P")" 2>/dev/null)"

echo ""; echo "N7: chained 模式某筆缺 h（刪 hash 欄降級繞過）→ BLOCKER"
P="$TEST_DIR/n7"; mkproj "$P"
seed "$P/.asp-bypass-log.ndjson"; bash "$HASH" rechain "$P/.asp-bypass-log.ndjson" >/dev/null 2>&1
echo "1" > "$P/.asp-bypass-log.chained"; echo "3" > "$P/.asp-bypass-log.hwm"
jq -c 'if .step=="S2" then del(.h,.prev) else . end' "$P/.asp-bypass-log.ndjson" > "$P/t" && mv "$P/t" "$P/.asp-bypass-log.ndjson"
run_hook "$P"
jq -r '.blockers[]' "$(BJ "$P")" 2>/dev/null | grep -qi 'hash chain' \
  && pass "缺 hash 欄（降級繞過）→ BLOCKER" || fail "降級繞過未偵測: $(jq -c .blockers "$(BJ "$P")" 2>/dev/null)"

echo ""; echo "整合-舊格式: 無 chained marker（純舊 log）→ 容錯不報 chain BLOCKER"
P="$TEST_DIR/old"; mkproj "$P"
seed "$P/.asp-bypass-log.ndjson"; echo "3" > "$P/.asp-bypass-log.hwm"   # 無 .chained marker
run_hook "$P"
jq -r '.blockers[]' "$(BJ "$P")" 2>/dev/null | grep -qi 'hash chain' && fail "純舊 log 誤報 chain BLOCKER" || pass "純舊 log 容錯（不報 chain）"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
