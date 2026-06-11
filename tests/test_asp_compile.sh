#!/usr/bin/env bash
# test_asp_compile.sh — tests for .asp/scripts/asp-compile.sh
# (v5 Phase 3, ADR-016: build-time profile dependency resolution →
# .asp-compiled-profile.md; two-stage conflict adjudication per ADR-014 D3/D8;
# contract-locked to asp-metrics via --list ↔ --simulate).
# Run: bash tests/test_asp_compile.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/asp-compile.sh"
METRICS="$ASP_ROOT/.asp/scripts/asp-metrics.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-compile-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

FIX="$TEST_DIR/proj"
build_fixture() {
  rm -rf "$FIX"; mkdir -p "$FIX/.asp/profiles" "$FIX/.asp/config" "$FIX/.asp/scripts"
  cp "$ASP_ROOT/.asp/scripts/level-resolve.sh" "$ASP_ROOT/.asp/scripts/validate-profile.sh" "$FIX/.asp/scripts/"
  # profiles：global_core(4) ← alpha(5,requires gc) ← beta(4,requires alpha)；
  # loosey 帶 conflicts: autopiloty；autopiloty 無依賴
  printf '# GC\n<!-- requires: (none — always loaded) -->\nbody gc\nend\n' > "$FIX/.asp/profiles/global_core.md"
  printf '# Alpha\n<!-- requires: global_core -->\nbody alpha\nmore\nend\n' > "$FIX/.asp/profiles/alpha.md"
  printf '# Beta\n<!-- requires: alpha -->\nbody beta\nend\n' > "$FIX/.asp/profiles/beta.md"
  printf '# Loosey\n<!-- requires: global_core -->\n<!-- conflicts: autopiloty -->\nbody loose\nend\n' > "$FIX/.asp/profiles/loosey.md"
  printf '# Autopiloty\n<!-- requires: global_core -->\nbody ap\nend\n' > "$FIX/.asp/profiles/autopiloty.md"
  cat > "$FIX/.asp/config/profile-map.yaml" <<'EOF'
version: 1
rules:
  - when: "type=system"
    load: "global_core beta"
  - when: "type=content"
    load: "global_core"
  - when: "workflow=vibe-coding"
    load: "loosey"
  - when: "level=loose"
    load: "loosey"
  - when: "autopilot=enabled"
    load: "autopiloty"
  - when: "rag=enabled"
    load: "ghost_profile"
level_aliases:
  - "0=loose"
  - "1=loose"
  - "2=standard"
  - "3=standard"
  - "4=autonomous"
  - "5=autonomous"
EOF
}
P() { printf '%s\n' "$@" > "$FIX/.ai_profile"; }
t() { OUT=$(cd "$FIX" && bash "$SCRIPT" "$@" 2>"$TEST_DIR/err"); RC=$?; ERR=$(cat "$TEST_DIR/err"); }
ART="$FIX/.asp-compiled-profile.md"

command -v jq >/dev/null || { echo "SKIP: jq not available"; exit 1; }

echo ""
echo "T1: type=system → 編譯成功 + 拓撲序（requires 在前）"
build_fixture; P "type: system" "level: standard"
t
[ "$RC" = "0" ] && pass "exit 0" || fail "rc=$RC err=$ERR"
[ -f "$ART" ] && pass "產物存在" || fail "no artifact"
grep -q 'profile: global_core' "$ART" && grep -q 'profile: beta' "$ART" && grep -q 'profile: alpha' "$ART" \
  && pass "含 global_core+alpha+beta（requires 展開）" || fail "sources wrong"
GC_LINE=$(grep -n 'profile: global_core' "$ART" | head -1 | cut -d: -f1)
A_LINE=$(grep -n 'profile: alpha' "$ART" | head -1 | cut -d: -f1)
B_LINE=$(grep -n 'profile: beta' "$ART" | head -1 | cut -d: -f1)
[ "$GC_LINE" -lt "$A_LINE" ] && [ "$A_LINE" -lt "$B_LINE" ] \
  && pass "拓撲序 global_core < alpha < beta" || fail "order: gc=$GC_LINE a=$A_LINE b=$B_LINE"
grep -q 'compiled_at:' "$ART" && grep -q 'total_lines:' "$ART" && pass "檔頭含 compiled_at/total_lines" || fail "header missing"

echo ""
echo "T2: type=content → 只含 global_core"
build_fixture; P "type: content"
t
[ "$RC" = "0" ] && pass "exit 0" || fail "rc=$RC"
grep -q 'profile: global_core' "$ART" && ! grep -q 'profile: beta' "$ART" \
  && pass "content 不含 beta" || fail "sources wrong"

echo ""
echo "T4: 顯式衝突（level=loose + autopilot）→ exit 1 指明衝突對"
build_fixture; P "type: system" "level: loose" "autopilot: enabled"
t
[ "$RC" = "1" ] && pass "exit 1" || fail "rc=$RC"
echo "$ERR" | grep -q 'loosey' && echo "$ERR" | grep -q 'autopiloty' \
  && pass "stderr 指明衝突對" || fail "err=$ERR"

echo ""
echo "T4b: 衍生衝突（workflow=vibe-coding + autopilot）→ 丟較鬆者 + WARNING"
build_fixture; P "type: system" "level: standard" "workflow: vibe-coding" "autopilot: enabled"
t
[ "$RC" = "0" ] && pass "exit 0（降級不報錯）" || fail "rc=$RC err=$ERR"
! grep -q 'profile: loosey' "$ART" && pass "loosey 不在產物（已丟棄）" || fail "loosey still compiled"
echo "$ERR" | grep -qi 'warn' && pass "stderr 有 WARNING" || fail "no warning"

echo ""
echo "T5: 幽靈引用容錯（rag=enabled → ghost_profile 無檔）"
build_fixture; P "type: content" "rag: enabled"
t
[ "$RC" = "0" ] && pass "exit 0" || fail "rc=$RC"
echo "$ERR" | grep -q 'ghost_profile' && pass "WARNING 提及 ghost_profile" || fail "no ghost warning"

echo ""
echo "T6: >2500 行 → WARNING"
build_fixture
{ printf '# Big\n<!-- requires: (none) -->\n'; for i in $(seq 1 2600); do echo "line $i"; done; } > "$FIX/.asp/profiles/big.md"
cat >> "$FIX/.asp/config/profile-map.yaml" <<'EOF'
EOF
awk '1; /load: "global_core"$/ && !d {print "  - when: \"type=content\""; print "    load: \"big\""; d=1}' \
  "$FIX/.asp/config/profile-map.yaml" > "$FIX/.asp/config/profile-map.yaml.t" && mv "$FIX/.asp/config/profile-map.yaml.t" "$FIX/.asp/config/profile-map.yaml"
P "type: content"
t
[ "$RC" = "0" ] && pass "exit 0" || fail "rc=$RC"
echo "$ERR" | grep -q '2,\?500\|2500' && pass "WARNING 提及 2500 門檻" || fail "no size warning: $ERR"

echo ""
echo "T7: --check 新鮮/重編"
build_fixture; P "type: content"
t
TS1=$(grep 'compiled_at:' "$ART")
sleep 1.1
t --check
echo "$ERR$OUT" | grep -qi 'fresh' && pass "--check 新鮮不重編" || fail "expected fresh"
TS2=$(grep 'compiled_at:' "$ART")
[ "$TS1" = "$TS2" ] && pass "compiled_at 未變" || fail "rewritten when fresh"
touch "$FIX/.ai_profile"; sleep 0.1
t --check
TS3=$(grep 'compiled_at:' "$ART")
[ "$TS1" != "$TS3" ] && pass "touch .ai_profile → 重編（compiled_at 變）" || fail "not recompiled"

echo ""
echo "T8: 缺 type → exit 2"
build_fixture; P "level: standard"
t
[ "$RC" = "2" ] && pass "exit 2" || fail "rc=$RC"

echo ""
echo "T9: 重複展開去重"
build_fixture; P "type: system" "level: standard" "workflow: vibe-coding"
t
[ "$(grep -c 'profile: global_core' "$ART")" = "1" ] && pass "global_core 只出現一次" || fail "duplicated"

echo ""
echo "T10: requires 循環 → exit 5"
build_fixture
printf '# C1\n<!-- requires: cyc2 -->\nx\n' > "$FIX/.asp/profiles/cyc1.md"
printf '# C2\n<!-- requires: cyc1 -->\nx\n' > "$FIX/.asp/profiles/cyc2.md"
awk '1; /load: "global_core"$/ && !d {print "  - when: \"type=content\""; print "    load: \"cyc1\""; d=1}' \
  "$FIX/.asp/config/profile-map.yaml" > "$FIX/.asp/config/profile-map.yaml.t" && mv "$FIX/.asp/config/profile-map.yaml.t" "$FIX/.asp/config/profile-map.yaml"
P "type: content"
t
[ "$RC" = "5" ] && pass "循環 exit 5" || fail "rc=$RC"

echo ""
echo "T3+T11: 真 repo 三組態編譯 + 與 asp-metrics 契約鎖定"
declare -a CFGS=(
  "type: content|level: 1|mode: auto|workflow: standard|hitl: standard"
  "type: system|level: 3|mode: auto|workflow: standard|hitl: standard|design: enabled|frontend_quality: enabled|guardrail: enabled|coding_style: enabled"
  "type: system|level: 5|mode: multi-agent|workflow: vibe-coding|hitl: minimal|autonomous: enabled|orchestrator: enabled|autopilot: enabled|rag: enabled|guardrail: enabled|coding_style: enabled"
)
declare -a SIMS=(
  "type=content,level=1,mode=auto,workflow=standard,hitl=standard"
  "type=system,level=3,mode=auto,workflow=standard,hitl=standard,design=enabled,frontend_quality=enabled,guardrail=enabled,coding_style=enabled"
  "type=system,level=5,mode=multi-agent,workflow=vibe-coding,hitl=minimal,autonomous=enabled,orchestrator=enabled,autopilot=enabled,rag=enabled,guardrail=enabled,coding_style=enabled"
)
for i in 0 1 2; do
  RP="$TEST_DIR/real$i"; mkdir -p "$RP"
  echo "${CFGS[$i]}" | tr '|' '\n' > "$RP/.ai_profile"
  OUT=$(cd "$RP" && bash "$SCRIPT" --asp-root "$ASP_ROOT/.asp" --list 2>"$TEST_DIR/err"); RC=$?
  [ "$RC" = "0" ] && pass "真組態 $i --list exit 0" || fail "cfg$i rc=$RC err=$(cat "$TEST_DIR/err")"
  COMPILE_SET=$(echo "$OUT" | sort | xargs)
  SIM_SET=$(bash "$METRICS" --repo-root "$ASP_ROOT" --simulate "${SIMS[$i]}" 2>/dev/null | jq -r '.profiles_loaded[]' | sort | xargs)
  [ "$COMPILE_SET" = "$SIM_SET" ] && pass "契約：compile --list == metrics --simulate（組態 $i）" \
    || fail "drift cfg$i: compile=[$COMPILE_SET] metrics=[$SIM_SET]"
done

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
