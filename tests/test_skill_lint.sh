#!/usr/bin/env bash
# test_skill_lint.sh — ASP skill 級品質 lint（ADR-023 ① 實作；Accepted 2026-06-24）
#
# 把 addyosmani CONTRIBUTING 四標準（Specific/Verifiable/Battle-tested/Minimal）的
# 可機械化部分翻成 exit-code 規則（報告 §3「誠實標註→機械判定」）：
#   R1  frontmatter name 存在 + kebab-case（asp 命名空間須 asp- 前綴）   [硬擋]
#   R2  description 存在 + 第三人稱 + 含 Triggers:/Use when             [硬擋]
#   R3  Triggers/description 含繁中（中英雙語）                          [advisory]
#   R4  核心三段「標題」齊：適用場景 / Verification / 下一步             [repo advisory]
#   R4b 步驟段「標題」存在（Step/Phase/Mode/工作流/維度/面向/G…）        [repo advisory]
#   R6  行數 ≤ 上限                                                     [advisory]
#   R7  Battle-tested → 無法靜態驗，誠實標人審（不在本 lint）
#   R5  discipline 型 skill 的 Red Flags 表 → 延後（語意判定難，見 ADR-023 後續追蹤）
# SKILL.md（name: asp，router）豁免 R4/R4b（天生無內容 skill 段）。
#
# ⚠️ 標題錨定（covering reality-checker Finding #1）：R4/R4b/STEP 全部要求標題行
#    `^#+ .*<同義詞>`，**不接受正文字詞命中**（否則「輸出」「參考」散落正文會假陽性）。
#    同義表依 .claude/skills/asp/ 既有 14 skill 的實際標題校準；新標題變體須補表。
#
# 兩部分：Part 1 自我測試（test integrity）；Part 2 repo 審計（R1/R2 硬擋、其餘 advisory）。
# 退出：R1/R2 任一硬擋 fail 或自我測試 fail → exit 1；advisory 不影響退出。
# 隨 `make test`（tests/*.sh runner）→ CI Job 1 自動執行。Run: bash tests/test_skill_lint.sh

source "$(dirname "$0")/lib/common.sh"
ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="${SKILL_DIR:-$ASP_ROOT/.claude/skills/asp}"
R6_MAX="${R6_MAX:-300}"   # 行數 advisory 上限（對齊 ADR-023 R6；mega-skill 拆小=ADR-024/②）

# ── 同義「標題」對照表（依 14 skill 實際標題校準；皆錨定 ^#+）──────────
PURPOSE_RE='適用場景|使用情境|使用方式|When to Invoke|When to Use|核心概念|核心原則|設計原則|前置'
STEP_RE='Step|步驟|Phase|Mode|工作流|核心流程|情境|維度|面向|Gate 定義|QA 驗證步驟|整合驗證步驟|G[0-9]'
VERIFY_RE='Verification|驗證|判定|判斷標準|Go/No-Go|GATE_PASS|結論|風險評分|QA 判決|安全邊界|輸出|Calibration|calibration'
NEXT_RE='下一步|Next Steps|搭配|相關|參考|After Merge|注意事項|協作|升級協議|快速修復|與其他'

# ── lint 核心 helper（自我測試與 repo 審計共用）──────────────────────
_fm()   { awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$1"; }
_body() { awk 'BEGIN{n=0} $0=="---"{n++;next} n>=2{print}' "$1"; }
_name() { _fm "$1" | grep -m1 -E '^name:' | sed -E 's/^name:[[:space:]]*//'; }
is_router() { [ "$(_name "$1")" = "asp" ]; }

r1_ok() {  # name 存在 + kebab-case + (router 或 asp- 前綴)
  local n; n="$(_name "$1")"
  printf '%s' "$n" | grep -qE '^[a-z0-9-]+$' || return 1
  is_router "$1" && return 0
  printf '%s' "$n" | grep -qE '^asp-'
}
r2_ok() {  # description 存在 + 第三人稱 + Triggers:/Use when
  local fm; fm="$(_fm "$1")"
  printf '%s\n' "$fm" | grep -qE '^description:' || return 1
  printf '%s\n' "$fm" | grep -qE '^[[:space:]]*(我|I )' && return 1
  printf '%s\n' "$fm" | grep -qiE 'Triggers:|Use when'
}
r3_ok() { printf '%s' "$(_fm "$1")" | LC_ALL=C grep -qE '[^[:space:][:print:]]'; }  # 雙語：含非 ASCII 位元組（CJK），locale-safe
r4_missing() {  # echo 缺的核心段（皆錨定標題）；空=齊全；router→空
  is_router "$1" && return 0
  local b m=""; b="$(_body "$1")"
  printf '%s\n' "$b" | grep -qE "^#+ .*($PURPOSE_RE)" || m="${m}適用場景 "
  printf '%s\n' "$b" | grep -qE "^#+ .*($VERIFY_RE)"  || m="${m}Verification "
  printf '%s\n' "$b" | grep -qE "^#+ .*($NEXT_RE)"    || m="${m}下一步 "
  printf '%s' "$m"
}
r4_ok()  { [ -z "$(r4_missing "$1")" ]; }
r4b_ok() { is_router "$1" && return 0; printf '%s\n' "$(_body "$1")" | grep -qE "^#+ .*($STEP_RE)"; }

echo "── Part 1: 自我測試（證明 lint 會抓違規、且標題錨定生效）──"
mk_test_dir skill-lint

cat > "$TEST_DIR/asp-good.md" <<'EOF'
---
name: asp-good
description: |
  Does a good thing in third person.
  Triggers: good, 做好事
---
## 適用場景
when good.
## 工作流
1. step one.
## Verification
- exit criteria binary.
## 下一步
- next.
EOF
r1_ok "$TEST_DIR/asp-good.md"  && pass "self R1: 合規 skill 通過" || fail "self R1: 合規 skill 應通過"
r2_ok "$TEST_DIR/asp-good.md"  && pass "self R2: 合規 skill 通過" || fail "self R2: 合規 skill 應通過"
r4_ok "$TEST_DIR/asp-good.md"  && pass "self R4: 合規 skill 三段齊" || fail "self R4: 合規 skill 應通過"
r4b_ok "$TEST_DIR/asp-good.md" && pass "self R4b: 合規 skill 有步驟" || fail "self R4b: 合規 skill 應通過"

# 標題錨定關鍵測試：核心段字詞只出現在「正文」（非標題）→ 必須判 fail
cat > "$TEST_DIR/asp-prose.md" <<'EOF'
---
name: asp-prose
description: |
  third person. Triggers: x, 中
---
## 適用場景
x
## 工作流
1. 這段正文提到 Verification 與 下一步 與 參考，但都不是標題。
EOF
[ "$(r4_missing "$TEST_DIR/asp-prose.md")" = "Verification 下一步 " ] \
  && pass "self R4 錨定: 正文字詞不算段落（正確抓 Verification+下一步 缺）" \
  || fail "self R4 錨定: 正文字詞被誤判為段落（Finding #1 未修）"

cat > "$TEST_DIR/noname.md" <<'EOF'
---
description: |
  no name. Triggers: x, 中
---
## 適用場景
x
EOF
r1_ok "$TEST_DIR/noname.md" && fail "self R1: 缺 name 應被抓" || pass "self R1: 缺 name 正確判 fail"

cat > "$TEST_DIR/badname.md" <<'EOF'
---
name: NotKebab_Case
description: |
  third person. Triggers: x, 中
---
EOF
r1_ok "$TEST_DIR/badname.md" && fail "self R1: 非 kebab/非 asp- 應被抓" || pass "self R1: 非 kebab 正確判 fail"

cat > "$TEST_DIR/firstperson.md" <<'EOF'
---
name: asp-fp
description: |
  我會做某事。Triggers: x, 中
---
EOF
r2_ok "$TEST_DIR/firstperson.md" && fail "self R2: 第一人稱應被抓" || pass "self R2: 第一人稱正確判 fail"

cat > "$TEST_DIR/notrigger.md" <<'EOF'
---
name: asp-nt
description: |
  Third person but no trigger marker.
---
EOF
r2_ok "$TEST_DIR/notrigger.md" && fail "self R2: 缺 Triggers/Use when 應被抓" || pass "self R2: 缺觸發詞正確判 fail"

cat > "$TEST_DIR/asp-en.md" <<'EOF'
---
name: asp-en
description: |
  English only. Use when x.
---
EOF
r3_ok "$TEST_DIR/asp-en.md" && fail "self R3: 純英文應被抓（advisory）" || pass "self R3: 缺繁中正確判 advisory"

cat > "$TEST_DIR/nosteps.md" <<'EOF'
---
name: asp-ns
description: |
  third person. Triggers: x, 中
---
## 適用場景
x
## Verification
y
## 下一步
z
EOF
r4b_ok "$TEST_DIR/nosteps.md" && fail "self R4b: 缺步驟段應被抓" || pass "self R4b: 缺步驟正確判 fail"

cat > "$TEST_DIR/SKILL.md" <<'EOF'
---
name: asp
description: |
  Router. Triggers: x, 中
---
路由表（無步驟/Verification 段）。
EOF
r1_ok "$TEST_DIR/SKILL.md"  && pass "self router: R1 通過" || fail "self router: R1 應通過"
r4_ok "$TEST_DIR/SKILL.md"  && pass "self router: R4 豁免" || fail "self router: R4 應豁免"
r4b_ok "$TEST_DIR/SKILL.md" && pass "self router: R4b 豁免" || fail "self router: R4b 應豁免"

echo ""
echo "── Part 2: repo 審計（R1/R2 硬擋；R3/R4/R4b/R6 advisory）──"
adv=0
for f in "$SKILL_DIR"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  if r1_ok "$f"; then pass "R1 $base"; else fail "R1 $base name 不合規（硬擋）"; fi
  if r2_ok "$f"; then pass "R2 $base"; else fail "R2 $base description 不合規（硬擋）"; fi
  r3_ok "$f" || { echo "  ⚠️  advisory R3  $base description 疑缺繁中（雙語）"; adv=$((adv+1)); }
  is_router "$f" && continue
  m="$(r4_missing "$f")";  [ -z "$m" ] || { echo "  ⚠️  advisory R4  $base 缺標題段：$m"; adv=$((adv+1)); }
  r4b_ok "$f" || { echo "  ⚠️  advisory R4b $base 缺步驟段標題"; adv=$((adv+1)); }
  lines=$(wc -l < "$f")
  [ "$lines" -le "$R6_MAX" ] || { echo "  ⚠️  advisory R6  $base ${lines} 行 > ${R6_MAX}（建議拆小，見 ②/ADR-024）"; adv=$((adv+1)); }
done

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed | advisory: ${adv}"
echo "（R1/R2 硬擋；R3/R4/R4b/R6 advisory 不阻擋 make test，對齊 ADR-023 漸進收斂分界）"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
