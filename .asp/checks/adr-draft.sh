#!/usr/bin/env bash
# .asp/checks/adr-draft.sh — ADR Draft 禁 commit(asp-gate.yaml id: adr-draft)
#
# 血緣:v4 session-audit.sh A3(TD-004 戰場驗證 regex)遷出(asp-ng issue #32 S8a);
# 鐵則「ADR 未定案禁止實作」自 SessionStart 動態 deny 升為 commit 閘硬強制。
# L0 ruleset 就位後移除(asp-gate-schema.md 落地裁定 6 的 v0.2 過渡承接)。
#
# 用法:adr-draft.sh [專案根目錄]
#   缺參數取 ${ASP_GATE_PROJ:-.};無 ADR 目錄(docs/adr、docs/ADR、adr 擇先)
#   → exit 200(skip 契約)**除非** repo 宣告 asp_level ≥ D(asp-gate.yaml 的
#   level_gate: D;#360)——宣告 D 級即取消缺件豁免,無 ADR 目錄轉紅。
#
# 狀態判定錨定「狀態/Status label」,支援兩種格式,正文 legend 不誤判(TD-004):
#   表格 cell:`| **狀態** | `Draft` |`、`| 狀態 | Draft(待確認) |`
#   blockquote:`> 狀態:Draft v0.8|日期:...`(值段至首個 | 為界)
#
# 輸出(薄 hook/session-audit 以前綴解析):
#   ❌ Draft ADR:<basename> …  → exit 1(blocker)
#   ⚠️  FIRM ADR:<basename> …  → exit 0(advisory:允許 commit,需 Verification Evidence)
#   ⚠️  Retrospective ADR:<basename> … → exit 0(advisory:證據鏈歸 retrospective-evidence)
#   ⏸  Parked ADR:<basename> … → exit 0(advisory:擱置中,非在途)
#
# 第三個狀態值 `Retrospective`(issue #361;設計源 docs/d-level-onboarding.md §3.2):
# 考古 epic 的回溯 ADR 必須標 `Retrospective` 而**不得標 `Accepted`**——它記的是
# 重建的歷史,不是當下的裁定。此處只認得這個值並把讀者指向證據鏈檢查;既有兩值
# (`Draft` 紅、`FIRM` ⚠️)的語意一字不動。
#
# 第四個狀態值 `Parked`(eks-infra#610 裁定,2026-09-03):刻意擱置、未簽、不刪、
# 不在途的 ADR。與 Draft 的差別是**沒有人正在實作它**——Draft 紅是因為「定案前
# 不得寫生產代碼」,Parked 的前提是「根本不會有人寫」,故 advisory 不擋 commit。
# 復活時把狀態改回 Draft,本檢查即恢復硬擋。
#
# 為什麼要「認得」而不是讓它落進 else:落進 else 就與 `Accepted` 同待遇,而這兩者
# 恰恰是設計要分開的一組。狀態值一旦有第三種語意,沉默的相等就是漂移的起點。
#
# 檔名 glob(eks-infra#610,2026-09-03 放寬):除 `ADR-*.md`/`adr-*.md` 外,同時
# 吃 `NNN-標題.md`(eks-infra 慣例,83 份;放寬前對該 repo 命中 0——「Draft 禁
# 實作」鐵則在那裡從未有過機械支撐)。同時排除 `000-template.md`(範本,狀態
# 設計上就是 Draft;用精確檔名而非 `*template*` 寬匹配,避免誤豁免真 ADR)。
set -u

# 等級感知(#360):缺件豁免是否仍成立由 .asp/lib/level-gate.sh 判定;缺該檔
# (vendoring 不完整)時退回現行豁免——理由與那一行 ⚠️ 見該檔抬頭「缺檔處置」。
_LG="$(dirname "${BASH_SOURCE[0]}")/../lib/level-gate.sh"
if [ -f "$_LG" ]; then
  # shellcheck source=../lib/level-gate.sh
  . "$_LG"
else
  asp_level_gate() { [ -f "$3/.ai_profile" ] && printf '⚠️  %s: 等級感知停用——缺 .asp/lib/level-gate.sh(vendoring 不完整),維持缺件豁免\n' "$1" >&2; return 1; }
fi

BASE="${1:-${ASP_GATE_PROJ:-.}}"
ADR_DIR=""
for d in "$BASE/docs/adr" "$BASE/docs/ADR" "$BASE/adr"; do
  [ -d "$d" ] && ADR_DIR="$d" && break
done
if [ -z "$ADR_DIR" ]; then
  if asp_level_gate adr-draft D "$BASE" "無 ADR 目錄($BASE/docs/adr)" "ADR/RFC 鏈" "補上 docs/adr/"; then
    exit 1
  fi
  echo "⏭  adr-draft: 無 ADR 目錄($BASE/docs/adr),略過"
  exit 200
fi

# TD-004:錨定 label cell,值段任意包裝(反引號/粗體/註記)皆命中;正文散提不匹配。
TABLE_RE='\|[[:space:]]*\*{0,2}(狀態|Status)\*{0,2}[[:space:]]*\|[^|]*'
QUOTE_RE='^>[[:space:]]*\*{0,2}(狀態|Status)\*{0,2}[[:space:]]*[::][^|]*'

DRAFT_ADRS=()
FIRM_ADRS=()
RETRO_ADRS=()
PARKED_ADRS=()
while IFS= read -r adr_file; do
  [ -f "$adr_file" ] || continue
  if grep -qiE "${TABLE_RE}\bDraft\b" "$adr_file" 2>/dev/null \
     || grep -qiE "${QUOTE_RE}\bDraft\b" "$adr_file" 2>/dev/null; then
    DRAFT_ADRS+=("$(basename "$adr_file")")
  elif grep -qiE "${TABLE_RE}\bFIRM\b" "$adr_file" 2>/dev/null \
       || grep -qiE "${QUOTE_RE}\bFIRM\b" "$adr_file" 2>/dev/null; then
    FIRM_ADRS+=("$(basename "$adr_file")")
  elif grep -qiE "${TABLE_RE}\bRetrospective\b" "$adr_file" 2>/dev/null \
       || grep -qiE "${QUOTE_RE}\bRetrospective\b" "$adr_file" 2>/dev/null; then
    RETRO_ADRS+=("$(basename "$adr_file")")
  elif grep -qiE "${TABLE_RE}\bParked\b" "$adr_file" 2>/dev/null \
       || grep -qiE "${QUOTE_RE}\bParked\b" "$adr_file" 2>/dev/null; then
    PARKED_ADRS+=("$(basename "$adr_file")")
  fi
done < <(find "$ADR_DIR" \( -name "ADR-*.md" -o -name "adr-*.md" -o -name "[0-9][0-9][0-9]-*.md" \) ! -name "000-template.md" 2>/dev/null | sort)

for f in ${FIRM_ADRS[@]+"${FIRM_ADRS[@]}"}; do
  echo "⚠️  FIRM ADR:$f — 允許 commit,需附 Verification Evidence(A3.2)"
done

for f in ${RETRO_ADRS[@]+"${RETRO_ADRS[@]}"}; do
  echo "⚠️  Retrospective ADR:$f — 允許 commit;決策列的證據鏈由 retrospective-evidence 檢查"
done

for f in ${PARKED_ADRS[@]+"${PARKED_ADRS[@]}"}; do
  echo "⏸  Parked ADR:$f — 允許 commit;擱置中非在途,復活時改回 Draft 即恢復硬擋"
done

if [ "${#DRAFT_ADRS[@]}" -gt 0 ]; then
  for f in "${DRAFT_ADRS[@]}"; do
    echo "❌ Draft ADR:$f — ADR 未定案禁止實作(鐵則 A3.1),定案或改 status 後再 commit"
  done
  exit 1
fi
exit 0
