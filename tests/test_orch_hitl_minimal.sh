#!/usr/bin/env bash
# test_orch_hitl_minimal.sh — v5 Phase 2 hitl:minimal 矛盾修正的雙重確認
# (ADR-015/SPEC-011)：(a) 腳本層 await_required 行為；(b) 文本層
# task_orchestrator.md 重寫驗收（無舊句、:571 原句保留、繞過表、行數、錨點）；
# (c) install.sh scripts 複製契約。
# Run: bash tests/test_orch_hitl_minimal.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/orchestrator/classify-task.sh"
TO="$ASP_ROOT/.asp/profiles/task_orchestrator.md"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

echo ""
echo "(a) 腳本層 — await_required 門檻行為"
OUT=$(bash "$SCRIPT" --hitl minimal "修復登入 bug crash" 2>/dev/null)
[ "$(echo "$OUT" | jq -r .await_required)" = "false" ] \
  && pass "minimal + 高信心 → await_required=false" || fail "got $(echo "$OUT" | jq -c .)"
OUT=$(bash "$SCRIPT" --hitl minimal "幫我處理一下那個東西" 2>/dev/null)
[ "$(echo "$OUT" | jq -r .await_required)" = "true" ] \
  && pass "minimal + 模糊（GENERAL 0.3） → await_required=true" || fail "got $(echo "$OUT" | jq -c .)"
OUT=$(bash "$SCRIPT" --hitl standard "修復登入 bug crash" 2>/dev/null)
[ "$(echo "$OUT" | jq -r .await_required)" = "true" ] \
  && pass "standard 永遠 await_required=true" || fail "got $(echo "$OUT" | jq -c .)"
OUT=$(bash "$SCRIPT" --hitl strict "修復登入 bug crash" 2>/dev/null)
[ "$(echo "$OUT" | jq -r .await_required)" = "true" ] \
  && pass "strict 永遠 await_required=true" || fail "got $(echo "$OUT" | jq -c .)"

echo ""
echo "(b) 文本層 — task_orchestrator.md 重寫驗收"
LINES=$(wc -l < "$TO")
[ "$LINES" -le 300 ] && pass "行數 ≤300（實際 $LINES）" || fail "行數 $LINES > 300"
grep -q '即使 hitl: minimal 也確認' "$TO" \
  && fail "舊句「即使 hitl: minimal 也確認」仍在" || pass "無條件 AWAIT 舊句已移除"
grep -q 'await_required' "$TO" && pass "入口含 await_required 條件式" || fail "await_required 條件式缺失"
grep -q '即使 hitl: minimal 也暫停' "$TO" \
  && pass ":571 L3 PAUSE 原句保留（紅線 2）" || fail "L3 PAUSE 原句遺失"
grep -q '繞過藉口與反駁' "$TO" && pass "繞過藉口表存在（紅線 4 pattern）" || fail "繞過表缺失"
for fn in execute_new_feature execute_bugfix execute_modification execute_removal execute_general; do
  grep -q "$fn" "$TO" && pass "錨點 $fn 保留" || fail "錨點 $fn 遺失"
done
for part in "Part A" "Part B" "Part C" "Part D" "Part E" "Part F" "Part G" "Part H" "Part J"; do
  grep -q "## $part" "$TO" && pass "「$part」標題保留" || fail "「$part」標題遺失"
done
grep -q 'orchestrator_multi_agent' "$TO" && pass "Part G stub 指向 orchestrator_multi_agent" || fail "stub 指向缺失"
grep -q 'make orch-classify' "$TO" && pass "分類下沉引用 make orch-classify" || fail "orch-classify 引用缺失"

echo ""
echo "(b2) Part G 逐字保真"
GMA="$ASP_ROOT/.asp/profiles/orchestrator_multi_agent.md"
ARCHIVE="$ASP_ROOT/docs/archive/profiles/task_orchestrator-v4.3-1587L.md"
[ -f "$GMA" ] && pass "orchestrator_multi_agent.md 存在" || fail "抽出檔缺失"
[ -f "$ARCHIVE" ] && [ "$(wc -l < "$ARCHIVE")" = "1587" ] \
  && pass "原文歸檔 1,587 行" || fail "歸檔缺失或行數錯"
if [ -f "$GMA" ] && [ -f "$ARCHIVE" ]; then
  # Part G 原文 = 歸檔 :891-1130（G1 review F-2 校正）；唯一已知差異 = 原 :1061
  # 的 ADR-014 D5 修正行——先對歸檔做該行正規化，之後 diff -u 必須為空（退出碼 0）
  sed -n '891,1130p' "$ARCHIVE" \
    | sed 's|IF escalation_loaded AND task.retry_count < MAX_RETRIES(2):|IF task.retry_count < MAX_RETRIES(2):  // 升級路徑隨 global_core 永遠載入（ADR-014 D5）|' \
    > /tmp/partg_orig.$$
  awk '/^## Part G: Multi-Agent 整合$/{f=1} f' "$GMA" > /tmp/partg_new.$$
  if diff -u /tmp/partg_orig.$$ /tmp/partg_new.$$ >/dev/null 2>&1; then
    pass "Part G 內文逐字一致（diff -u 退出碼 0，:891-1130 + D5 正規化）"
  else
    fail "Part G 內文與原文不一致：$(diff /tmp/partg_orig.$$ /tmp/partg_new.$$ | head -3)"
  fi
  rm -f /tmp/partg_orig.$$ /tmp/partg_new.$$
fi

echo ""
echo "(c) install.sh scripts 複製契約"
grep -qE 'for dir in .*scripts' "$ASP_ROOT/.asp/scripts/install.sh" \
  && pass "install.sh 複製清單含 scripts" || fail "install.sh 未複製 scripts"
grep -q '.asp-orch-state.json' "$ASP_ROOT/.gitignore" \
  && pass ".gitignore 含 .asp-orch-state.json" || fail ".gitignore 缺 .asp-orch-state.json"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
