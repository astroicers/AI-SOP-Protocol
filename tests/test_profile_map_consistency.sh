#!/usr/bin/env bash
# test_profile_map_consistency.sh — profile 載入清單多來源一致性（ADR-013 Phase 3 收尾）
#
# profile-map.yaml 是 .ai_profile → profile 載入的 single source of truth（ADR-013）。
# 本測試把三份「載入清單」釘在同一真相上，防止 drift 復活：
#   - validate-profile.sh 載入清單  ≡  asp-compile --list（map 權威解析）
#   - CLAUDE.md「Profile 核心映射」段提到的 profile  ⊆  map 的 load 集合
# 回歸目標：level-based 載入（ADR-014）曾只進 map，未進 validate 硬編碼清單，
#   導致 type=system/level=standard 漏列 pipeline（本測試的 T1）。
# Run: bash tests/test_profile_map_consistency.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATE="$ASP_ROOT/.asp/scripts/validate-profile.sh"
COMPILE="$ASP_ROOT/.asp/scripts/asp-compile.sh"
MAP="$ASP_ROOT/.asp/config/profile-map.yaml"
CLAUDEMD="$ASP_ROOT/CLAUDE.md"
PROFILES_DIR="$ASP_ROOT/.asp/profiles"
mk_test_dir

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 不存在（asp-compile 依賴），跳過一致性測試"; exit 0; }

# 從 validate-profile.sh 輸出抽出載入清單的 profile 集合（「• xxx.md」→ xxx）
validate_profiles() {
  bash "$VALIDATE" "$1" 2>/dev/null \
    | grep -oE '•[[:space:]]+[a-z_]+\.md' | grep -oE '[a-z_]+\.md' | sed 's/\.md$//' | sort -u
}
# asp-compile --list 的權威集合（跳過二次欄位驗證，避免與 validate 互呼遞迴）
compile_profiles() {
  ASP_COMPILE_SKIP_VALIDATE=1 bash "$COMPILE" --asp-root "$ASP_ROOT/.asp" --profile "$1" --list 2>/dev/null | sort -u
}

# ── T1: 回歸 — level=standard 必載 pipeline + coding_style（drift 核心 bug） ──
echo ""
echo "T1: type=system, level=standard → validate 載入清單含 pipeline + coding_style"
P1="$TEST_DIR/p1"
printf 'type: system\nlevel: standard\ncoding_style: enabled\n' > "$P1"
VP=$(validate_profiles "$P1")
grep -qx "pipeline" <<<"$VP"     && pass "validate 載入清單含 pipeline" \
  || fail "validate 載入清單缺 pipeline（level=standard drift — map 有但 validate 硬編碼漏列）"
grep -qx "coding_style" <<<"$VP" && pass "validate 載入清單含 coding_style" \
  || fail "validate 載入清單缺 coding_style"

# ── T2: 契約鎖定 — validate 載入清單 ≡ asp-compile --list（多組態，皆不觸發 auto-fix） ──
echo ""
echo "T2: validate 載入清單 ≡ asp-compile --list"
i=0
for combo in \
  'type: system\nlevel: standard\ncoding_style: enabled\n' \
  'type: content\nlevel: loose\n' \
  'type: system\nlevel: standard\nopenapi: enabled\n' ; do
  i=$((i+1)); P="$TEST_DIR/combo$i"; printf '%b' "$combo" > "$P"
  V=$(validate_profiles "$P"); C=$(compile_profiles "$P")
  label=$(printf '%b' "$combo" | tr '\n' ' ')
  if [ -n "$C" ] && [ "$V" = "$C" ]; then
    pass "一致：$label"
  else
    fail "drift：[$label] validate={$(echo $V|tr '\n' ',')} vs compile={$(echo $C|tr '\n' ',')}"
  fi
done

# ── T3: CLAUDE.md「Profile 核心映射」提到的 profile 均在 map 的 load 集合 ──
echo ""
echo "T3: CLAUDE.md 映射段提到的 profile ⊆ profile-map.yaml load 集合"
MAP_PROFILES=$(awk '/load:/{sub(/.*load:[[:space:]]*"/,"");sub(/".*/,"");print}' "$MAP" | tr ' ' '\n' | sort -u)
# 抽映射段所有 backtick 區塊，內部依 + / 空白拆 token（複合如 `global_core+system_dev`），
# 留純 snake_case，下方再以「.asp/profiles/X.md 存在」過濾出真 profile（排除路徑/skill token）
CANDIDATES=$(grep -i 'Profile 核心映射' "$CLAUDEMD" \
  | grep -oE '`[^`]+`' | tr -d '`' | tr '+/ ' '\n' | grep -oxE '[a-z_]+' | sort -u)
T3FAIL=0; T3CHECKED=0
for tok in $CANDIDATES; do
  [ -f "$PROFILES_DIR/$tok.md" ] || continue   # 只檢真 profile 檔（排除 asp-autopilot skill 等非 profile token）
  T3CHECKED=$((T3CHECKED+1))
  grep -qx "$tok" <<<"$MAP_PROFILES" || { fail "CLAUDE.md 提到 $tok 但 map 無對應 load（drift）"; T3FAIL=1; }
done
if [ "$T3CHECKED" = 0 ]; then
  fail "CLAUDE.md 映射段未抽到任何 profile token（解析失效，需檢查段落格式）"
elif [ "$T3FAIL" = 0 ]; then
  pass "CLAUDE.md 映射段 $T3CHECKED 個 profile 均在 map"
fi

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
