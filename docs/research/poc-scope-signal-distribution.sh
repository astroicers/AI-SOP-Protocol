#!/usr/bin/env bash
# POC spike for ADR-025 (item ④): scope-size 信號的閾值校準 + advisory 必要性。
#
# 屬 spike：放 docs/research/、不接 Makefile/CI/tests（同 poc1/poc2/poc-skill-lint/poc-megaskill）。
# 目的（de-risk ④）：用 ASP 自身 commit 的「每 commit 改檔數」分佈，
#   (1) 校準 scope 信號的 advisory 閾值；
#   (2) 證明 ASP 存在「合法的大 commit」（installer/v5 批次）→ scope 信號**必須 advisory 不能硬 gate**
#       （否則撞 ADR-020「偽硬 gate」與真實工作流）。
#
# exit 0 = 量測完成並印分佈 + 建議閾值；不對 ④ 是否採納做斷言（見 ADR-025）。

set -uo pipefail
N="${1:-40}"            # 取樣 commit 數
THRESH="${2:-8}"        # 候選 advisory 閾值（改檔數 > THRESH → 提示「可能多任務」）

echo "── ④ scope 信號閾值校準（ASP 自身近 $N 個 non-merge commit）──"
counts=$(git log --no-merges -"$N" --pretty="%h" | while read -r c; do
  git show --numstat --format="" "$c" 2>/dev/null | grep -c .
done)

echo "[分佈] 改檔數 → commit 數："
printf '%s\n' "$counts" | sort -n | uniq -c | awk '{printf "  %2s 檔: %s\n", $2, $1}'

total=$(printf '%s\n' "$counts" | grep -c .)
le=$(printf '%s\n' "$counts" | awk -v t="$THRESH" '$1<=t' | grep -c .)
gt=$(printf '%s\n' "$counts" | awk -v t="$THRESH" '$1>t'  | grep -c .)
max=$(printf '%s\n' "$counts" | sort -n | tail -1)

echo ""
echo "════════════════════════════════"
echo "SCOPE_DIST: total=$total  <=${THRESH}檔=$le  >${THRESH}檔=$gt  max=${max}檔"
echo "→ 建議 advisory 閾值 > ${THRESH} 檔（${le}/${total} 落在閾值內＝正常工作；${gt}/${total} 超過＝提示『可能多任務、建議拆』）"
echo "→ max=${max} 檔證實 ASP 有合法大 commit（installer/v5 批次）→ **必 advisory 不可硬 gate**（撞 ADR-020 偽硬 gate）"
echo "════════════════════════════════"
exit 0
