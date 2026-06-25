#!/usr/bin/env bash
# POC spike for ADR-024 (item ②): mega-skill 拆分的「破壞半徑」量測。
#
# 屬 spike：放 docs/research/、不接 Makefile/CI/tests（同 poc1/poc2/poc-skill-lint 慣例）。
# 目的（de-risk ②）：量測「big-bang 拆 asp-autopilot/asp-gate/asp-ship」會牽動多少
#   硬編引用（hooks + 測試 + 其他 skill + router），作為 ADR-010 摩擦評估「overhead」
#   的證據——若 blast radius 大，則「全拆」是高破壞/高 churn，傾向「不全拆、漸進式」。
#
# exit code 語意：exit 0 = 量測完成並印 blast radius；不對決策本身做斷言（決策見 ADR-024）。

set -uo pipefail
ROOT="${1:-.}"
MEGA="asp-autopilot|asp-gate|asp-ship"

count() { grep -rlE "$MEGA" $1 2>/dev/null | grep -vE "asp-(autopilot|gate|ship)\.md$" | sort -u; }

echo "── ② mega-skill 拆分破壞半徑（hardcoded references）──"
echo ""
echo "[hooks] 硬編引用 mega-skill 名的 hook（拆名→hook 失效風險）："
H=$(count "$ROOT/.asp/hooks"); echo "${H:-  (none)}"; hn=$(printf '%s\n' "$H" | grep -c . )
echo ""
echo "[tests] 釘住 mega-skill 名/段落的測試（拆→測試紅）："
T=$(count "$ROOT/tests"); echo "$T"; tn=$(printf '%s\n' "$T" | grep -c . )
echo ""
echo "[skills] 其他 skill 互引 mega-skill（拆→路由/交叉引用漂移）："
S=$(count "$ROOT/.claude/skills/asp"); echo "$S"; sn=$(printf '%s\n' "$S" | grep -c . )
echo ""
rc=$(grep -cE "$MEGA" "$ROOT/.claude/skills/asp/SKILL.md" 2>/dev/null || echo 0)
echo "[router] SKILL.md 內 mega-skill 引用列數：$rc"
echo ""
echo "════════════════════════════════"
echo "BLAST_RADIUS: hooks=$hn tests=$tn skills=$sn router_lines=$rc"
echo "（數字大 → big-bang 全拆高破壞；傾向『分階索引(純加) + lint-gated 漸進拆』，見 ADR-024）"
echo "════════════════════════════════"
exit 0
