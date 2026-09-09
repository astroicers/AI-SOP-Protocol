#!/usr/bin/env bash
# test_metrics_isolation.sh — 測試不得寫進**真實的**治理遙測源
#
# 為何需要（2026-09-09，第三輪複審 F4）：`tests/test_shipgate_worktree.sh` 與
# `tests/test_worktree_resolve.sh` 呼叫 ship-gate hook 時設了 `CLAUDE_PROJECT_DIR`
# 卻漏了 `ASP_METRICS_FILE`，於是 hook 落回 `$HOME/.claude/asp/metrics/rule-hits.jsonl`。
# 複審實測一次 `make test` 就往真實檔追加了 **53 行** fixture 資料
# （`{"project":"wt","rule_id":"SHIP-GATE",…}`）。
#
# 這不只是髒：`make rule-stats` 讀的就是這個檔，而 **ADR-018 的「90 天零命中即待刪
# 候選」整個裁決依據就是這份資料**。fixture 混進去 = 用假資料做規則存留決策。
#
# 本測試採**靜態檢查**而非「跑完再比行數」：後者循環（測試套件驗自己）且慢。
# 判準：任何一支測試若會執行 hook，該次呼叫的同一行必須帶 `ASP_METRICS_FILE=`。
#
# Run: bash tests/test_metrics_isolation.sh
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ASP_ROOT" || exit 1

# hook 會寫遙測的進入點：ship-gate 與 git-guardrails。
# 抓「同一行裡執行了 hook」的呼叫；排除註解行。
# 偵測面要涵蓋**所有**執行 hook 的寫法，否則漏一種就等於沒驗（初版只抓
# `bash "$GATE"` / `bash "$HOOK"`，漏掉內嵌完整路徑與自訂變數名，實測仍漏 25 行）。
# 作法：先由每支測試自己的賦值行解析出「指向 .asp/hooks/ 的變數名」，
# 再連同內嵌路徑一起掃。
writes_metrics() {  # $1=hook 檔名 → 回 0 表示它會寫遙測
  local target="$ASP_ROOT/.asp/hooks/$1"
  [ -f "$target" ] || return 1
  grep -q 'rule-hits\|METRICS_FILE' "$target"
}

VIOLATIONS=""
CHECKED=0
SKIPPED=0
for t in tests/*.sh; do
  case "$t" in */test_metrics_isolation.sh) continue ;; esac
  # 此檔內指向 hooks 的變數名（HOOK / GATE / AUDIT_HOOK / …）
  vars=$(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*\.asp\/hooks\/[a-z0-9.-]*\.sh.*/\1/p' "$t" | sort -u)
  pat='bash "\$[A-Z_]*/*[^"]*\.asp/hooks/'      # 內嵌完整路徑
  for v in $vars; do pat="$pat\|bash \"\$$v\""; done
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    ln="${hit%%:*}"; line="${hit#*:}"
    case "$line" in \#*|*[[:space:]]\#*bash*) continue ;; esac
    # 這一行驅動的是哪支 hook？先看內嵌路徑，再看變數的賦值。
    h=$(printf '%s' "$line" | sed -n 's|.*\.asp/hooks/\([a-z0-9.-]*\.sh\).*|\1|p' | head -1)
    if [ -z "$h" ]; then
      for v in $vars; do
        case "$line" in *"\$$v\""*)
          h=$(sed -n "s|^$v=.*\.asp/hooks/\([a-z0-9.-]*\.sh\).*|\1|p" "$t" | head -1); break ;;
        esac
      done
    fi
    [ -n "$h" ] || continue
    if ! writes_metrics "$h"; then SKIPPED=$((SKIPPED + 1)); continue; fi
    CHECKED=$((CHECKED + 1))
    case "$line" in
      *ASP_METRICS_FILE=*) ;;
      *) VIOLATIONS="$VIOLATIONS
  $t:$ln  $(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-90)" ;;
    esac
  done < <(grep -n "$pat" "$t" 2>/dev/null || true)
done
[ "$SKIPPED" -gt 0 ] && echo "  ⏭  $SKIPPED 處的 hook 不寫遙測，不需隔離"

[ "$CHECKED" -gt 0 ] && pass "掃到 $CHECKED 處會執行 hook 的測試呼叫" \
                     || fail "零命中——本測試的偵測方式失效（hook 呼叫寫法變了？）"

if [ -z "$VIOLATIONS" ]; then
  pass "每一處都設了 ASP_METRICS_FILE（不會寫進真實 rule-hits.jsonl）"
else
  fail "下列呼叫未設 ASP_METRICS_FILE，會污染真實治理遙測：$VIOLATIONS"
fi

# 真實遙測檔本身不該被 repo 追蹤（它是使用者家目錄的產物）
if git ls-files --error-unmatch .asp/metrics/rule-hits.jsonl >/dev/null 2>&1; then
  fail "真實遙測檔被 repo 追蹤了——它屬家目錄產物，不該進版控"
else
  pass "真實遙測檔未被 repo 追蹤"
fi

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
