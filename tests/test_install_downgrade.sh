#!/usr/bin/env bash
# test_install_downgrade.sh — install.sh 的 is_downgrade() 版本方向判斷真值表
#
# install.sh 升級路徑（curl|bash）若 clone 到的來源 .asp/VERSION 比已安裝舊，
# 不可無聲覆蓋成舊版。核心判斷是 is_downgrade <installed> <source>：僅當兩者皆
# 純 semver 且 source < installed 才回真。本測試抽出該函式（與 install.sh 同步），
# 直接驗證真值表 + 非 semver 邊界（不跑完整 install.sh — 那會動 ~/.claude，沿用
# test_install_precheck.sh 的隔離慣例）。
# Run: bash tests/test_install_downgrade.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$ASP_ROOT/.asp/scripts/install.sh"
mk_test_dir install-downgrade

# 從 install.sh 抽出 is_downgrade()（隨 install.sh 演進自動同步）
HELPERS="$TEST_DIR/helpers.sh"
awk '/^is_downgrade\(\)/,/^}/' "$INSTALL" > "$HELPERS"
grep -q 'is_downgrade' "$HELPERS" && pass "install.sh 有定義 is_downgrade()" || fail "install.sh 缺 is_downgrade()（測試其餘斷言將無意義）"

# 在乾淨子 shell 內判斷（installed, source）→ rc
assert_downgrade() {     # 期望「是降級」
  local desc="$1" inst="$2" src="$3"
  if ( . "$HELPERS"; is_downgrade "$inst" "$src" ); then pass "$desc"; else fail "$desc（應判降級卻否）"; fi
}
assert_not_downgrade() { # 期望「非降級」（升級 / 同版本 / 非 semver）
  local desc="$1" inst="$2" src="$3"
  if ( . "$HELPERS"; is_downgrade "$inst" "$src" ); then fail "$desc（誤判為降級）"; else pass "$desc"; fi
}

echo "── 降級（source < installed）──"
assert_downgrade "5.0.0 ← 來源 4.0.0"        "5.0.0" "4.0.0"
assert_downgrade "5.0.1 ← 來源 5.0.0"        "5.0.1" "5.0.0"
assert_downgrade "10.0.0 ← 來源 9.0.0（數值非字典序）" "10.0.0" "9.0.0"
assert_downgrade "5.1.0 ← 來源 5.0.9"        "5.1.0" "5.0.9"

echo "── 非降級（升級 / 同版本）──"
assert_not_downgrade "5.0.0 ← 來源 5.1.0（升級）"  "5.0.0" "5.1.0"
assert_not_downgrade "5.0.0 = 來源 5.0.0（同版本）" "5.0.0" "5.0.0"
assert_not_downgrade "9.0.0 ← 來源 10.0.0（升級）" "9.0.0" "10.0.0"

echo "── 非 semver 邊界（不可誤判）──"
assert_not_downgrade "installed=not installed" "not installed" "4.0.0"
assert_not_downgrade "source=unknown"          "5.0.0" "unknown"
assert_not_downgrade "installed 空字串"         ""      "4.0.0"
assert_not_downgrade "pre-release 含 - 視為非 semver" "5.0.0" "5.0.0-beta"
assert_not_downgrade "純點 source . （損毀 VERSION 不誤判降級）" "5.0.0" "."
assert_not_downgrade "純點 source .."          "5.0.0" ".."
assert_not_downgrade "純點 installed ."         "."     "4.0.0"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
