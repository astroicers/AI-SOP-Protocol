#!/usr/bin/env bash
# .asp/checks/adr-draft.sh — ADR Draft 禁 commit(asp-gate.yaml id: adr-draft)
#
# 血緣:v4 session-audit.sh A3(TD-004 戰場驗證 regex)遷出(asp-ng issue #32 S8a);
# 鐵則「ADR 未定案禁止實作」自 SessionStart 動態 deny 升為 commit 閘硬強制。
# L0 ruleset 就位後移除(asp-gate-schema.md 落地裁定 6 的 v0.2 過渡承接)。
#
# 用法:adr-draft.sh [專案根目錄]
#   缺參數取 ${ASP_GATE_PROJ:-.};無 ADR 目錄(docs/adr、docs/ADR、adr 擇先)
#   → exit 200(skip 契約)。
#
# 狀態判定錨定「狀態/Status label」,支援兩種格式,正文 legend 不誤判(TD-004):
#   表格 cell:`| **狀態** | `Draft` |`、`| 狀態 | Draft(待確認) |`
#   blockquote:`> 狀態:Draft v0.8|日期:...`(值段至首個 | 為界)
#
# 輸出(薄 hook/session-audit 以前綴解析):
#   ❌ Draft ADR:<basename> …  → exit 1(blocker)
#   ⚠️  FIRM ADR:<basename> …  → exit 0(advisory:允許 commit,需 Verification Evidence)
set -u

BASE="${1:-${ASP_GATE_PROJ:-.}}"
ADR_DIR=""
for d in "$BASE/docs/adr" "$BASE/docs/ADR" "$BASE/adr"; do
  [ -d "$d" ] && ADR_DIR="$d" && break
done
if [ -z "$ADR_DIR" ]; then
  echo "⏭  adr-draft: 無 ADR 目錄($BASE/docs/adr),略過"
  exit 200
fi

# TD-004:錨定 label cell,值段任意包裝(反引號/粗體/註記)皆命中;正文散提不匹配。
TABLE_RE='\|[[:space:]]*\*{0,2}(狀態|Status)\*{0,2}[[:space:]]*\|[^|]*'
QUOTE_RE='^>[[:space:]]*\*{0,2}(狀態|Status)\*{0,2}[[:space:]]*[::][^|]*'

DRAFT_ADRS=()
FIRM_ADRS=()
while IFS= read -r adr_file; do
  [ -f "$adr_file" ] || continue
  if grep -qiE "${TABLE_RE}\bDraft\b" "$adr_file" 2>/dev/null \
     || grep -qiE "${QUOTE_RE}\bDraft\b" "$adr_file" 2>/dev/null; then
    DRAFT_ADRS+=("$(basename "$adr_file")")
  elif grep -qiE "${TABLE_RE}\bFIRM\b" "$adr_file" 2>/dev/null \
       || grep -qiE "${QUOTE_RE}\bFIRM\b" "$adr_file" 2>/dev/null; then
    FIRM_ADRS+=("$(basename "$adr_file")")
  fi
done < <(find "$ADR_DIR" -name "ADR-*.md" -o -name "adr-*.md" 2>/dev/null | sort)

for f in ${FIRM_ADRS[@]+"${FIRM_ADRS[@]}"}; do
  echo "⚠️  FIRM ADR:$f — 允許 commit,需附 Verification Evidence(A3.2)"
done

if [ "${#DRAFT_ADRS[@]}" -gt 0 ]; then
  for f in "${DRAFT_ADRS[@]}"; do
    echo "❌ Draft ADR:$f — ADR 未定案禁止實作(鐵則 A3.1),定案或改 status 後再 commit"
  done
  exit 1
fi
exit 0
