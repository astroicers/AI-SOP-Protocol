#!/usr/bin/env bash
# POC spike for ADR-023: skill-level quality lint mechanizability + baseline.
#
# 屬 spike：放 docs/research/、不接 Makefile/CI/tests（與 poc1/poc2 同慣例）。
# 目的（de-risk ADR-023 的承重假設）：
#   (1) lint 能否用純 bash/grep 機械化（無重依賴）→ 本檔可跑即證實。
#   (2) 現有 15 個 asp skill 在「嚴格 schema」下的 baseline 合規率
#       → 印 PASS=N FAIL=M，供 ADR-010 摩擦評估與 advisory 分界對照。
#
# exit code 語意（仿 poc1）：
#   exit 0 = 探針成功執行並產出 baseline（不代表 15 skill 全合規）。
#   exit 1 = 探針本身無法機械化（缺必要工具 / 同義表覆蓋不了）。
#
# 檢查項（對應 ADR-023 決策表）：
#   R1  frontmatter name 存在 + kebab-case（asp 命名空間須 asp- 前綴）  [硬擋]
#   R2  description 存在 + 第三人稱 + 含 Triggers:/Use when            [硬擋]
#   R4  核心三段：適用場景 / Verification / 下一步（同義標題表）          [硬擋]
#   R4b 步驟段存在（Step/Phase/Mode/情境/G/面向…）                      [硬擋]
# SKILL.md（router, name: asp）豁免 R4/R4b（天生無內容 skill 段）。

set -uo pipefail

SKILL_DIR="${1:-.claude/skills/asp}"

if ! command -v grep >/dev/null 2>&1 || ! command -v awk >/dev/null 2>&1; then
  echo "exit1: 缺 grep/awk，無法純 shell 機械化" >&2
  exit 1
fi
if [ ! -d "$SKILL_DIR" ]; then
  echo "exit1: skill 目錄不存在：$SKILL_DIR" >&2
  exit 1
fi

# ── 同義標題對照表（ASCII alternation；A3 baseline 證實標題有變體）──
PURPOSE_RE='適用場景|使用情境|使用方式|When to Invoke|When to Use|核心概念|核心原則|設計原則|前置'
STEP_RE='## Step|### Step|## 步驟|### 步驟|## Phase|### Phase|## Mode|### Mode|情境|## 面向|核心流程|工作流|G1|G2-G|10 步驟|QA 驗證步驟|整合驗證步驟'
VERIFY_RE='Verification|驗證|判定|判斷標準|Go/No-Go|GATE_PASS|結論|風險評分|QA 判決|安全邊界|輸出摘要|輸出格式|calibration'
NEXT_RE='下一步|Next Steps|搭配|相關檔案|參考|After Merge|注意事項|協作|升級協議|快速修復|建議的下一步'

pass=0; fail=0
printf '%-26s | R1 R2 R4 R4b | 結果 | 缺漏\n' "skill"
printf -- '---------------------------+------------+------+-----------------------\n'

for f in "$SKILL_DIR"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"

  # frontmatter（首段 --- ... ---）
  fm="$(awk 'NR==1&&$0=="---"{infm=1;next} infm&&$0=="---"{exit} infm{print}' "$f")"
  body="$(awk 'BEGIN{n=0} $0=="---"{n++;next} n>=2{print}' "$f")"

  name_val="$(printf '%s\n' "$fm" | grep -m1 -E '^name:' | sed -E 's/^name:[[:space:]]*//')"
  is_router=0
  [ "$name_val" = "asp" ] && is_router=1

  miss=""

  # R1 name kebab-case（asp-* 前綴；router name=asp 允許）
  r1="✗"
  if printf '%s' "$name_val" | grep -qE '^[a-z0-9-]+$'; then
    if [ "$is_router" = 1 ] || printf '%s' "$name_val" | grep -qE '^asp-'; then
      r1="✓"
    fi
  fi
  [ "$r1" = "✗" ] && miss="${miss}R1(name) "

  # R2 description 存在 + 第三人稱 + Triggers/Use when
  r2="✗"
  if printf '%s\n' "$fm" | grep -qE '^description:'; then
    # 第三人稱啟發式：description 區塊不以「我」或「I 」起手
    if ! printf '%s\n' "$fm" | grep -qE '^[[:space:]]*(我|I )'; then
      if printf '%s\n' "$fm" | grep -qiE 'Triggers:|Use when'; then
        r2="✓"
      fi
    fi
  fi
  [ "$r2" = "✗" ] && miss="${miss}R2(desc) "

  # R4 核心三段（router 豁免）
  if [ "$is_router" = 1 ]; then
    r4="—"
  else
    has_p=0; has_v=0; has_n=0
    printf '%s\n' "$body" | grep -qE "^#+ .*($PURPOSE_RE)" && has_p=1
    printf '%s\n' "$body" | grep -qE "($VERIFY_RE)" && has_v=1
    printf '%s\n' "$body" | grep -qE "($NEXT_RE)" && has_n=1
    if [ $((has_p+has_v+has_n)) -eq 3 ]; then r4="✓"; else
      r4="✗"
      sub=""
      [ $has_p -eq 0 ] && sub="${sub}適用場景,"
      [ $has_v -eq 0 ] && sub="${sub}Verification,"
      [ $has_n -eq 0 ] && sub="${sub}下一步,"
      miss="${miss}R4(${sub%,}) "
    fi
  fi

  # R4b 步驟段（router 豁免）
  if [ "$is_router" = 1 ]; then
    r4b="—"
  else
    if printf '%s\n' "$body" | grep -qE "($STEP_RE)"; then r4b="✓"; else r4b="✗"; miss="${miss}R4b(步驟) "; fi
  fi

  # 嚴格判定：硬擋項全過才 PASS（router 只看 R1/R2）
  ok=1
  [ "$r1" = "✓" ] || ok=0
  [ "$r2" = "✓" ] || ok=0
  if [ "$is_router" != 1 ]; then
    [ "$r4" = "✓" ] || ok=0
    [ "$r4b" = "✓" ] || ok=0
  fi
  if [ "$ok" = 1 ]; then verdict="PASS"; pass=$((pass+1)); else verdict="FAIL"; fail=$((fail+1)); fi

  printf '%-26s |  %s  %s  %s  %s  | %s | %s\n' "$base" "$r1" "$r2" "$r4" "$r4b" "$verdict" "${miss:-—}"
done

echo
echo "PASS=$pass FAIL=$fail TOTAL=$((pass+fail))"
echo "（嚴格 schema baseline；router=SKILL.md 豁免 R4/R4b。FAIL 多 → 證實 advisory 分界落地必要，非過度設計。）"
exit 0
