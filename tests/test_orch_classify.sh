#!/usr/bin/env bash
# test_orch_classify.sh — tests for .asp/scripts/orchestrator/classify-task.sh
# (v5 Phase 2, ADR-015/SPEC-011: deterministic task classification with
# confidence + bug-domain detection, sunk from task_orchestrator.md pseudocode).
# Run: bash tests/test_orch_classify.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/orchestrator/classify-task.sh"

t() { OUT=$(bash "$SCRIPT" "$@" 2>/dev/null); RC=$?; }
jval() { echo "$OUT" | jq -r "$1"; }

echo ""
echo "T1-T4: 四類關鍵字分類"
t "移除舊的快取模組"
[ "$(jval .type)" = "REMOVAL" ] && pass "移除 → REMOVAL" || fail "got $(jval .type)"
t "fix the login crash"
[ "$(jval .type)" = "BUGFIX" ] && pass "fix → BUGFIX" || fail "got $(jval .type)"
t "重構 user service 的命名"
[ "$(jval .type)" = "MODIFICATION" ] && pass "重構 → MODIFICATION" || fail "got $(jval .type)"
echo "$OUT" | jq -e '.post_checks | index("target_exists_in_codebase")' >/dev/null \
  && pass "MODIFICATION 帶 target_exists post_check" || fail "post_checks missing"
t "新增 CSV 匯出功能"
[ "$(jval .type)" = "NEW_FEATURE" ] && pass "新增 → NEW_FEATURE" || fail "got $(jval .type)"

echo ""
echo "T5: priority 序（REMOVAL > BUGFIX > MODIFICATION > NEW_FEATURE）"
t "移除舊功能再新增新版"
[ "$(jval .type)" = "REMOVAL" ] && pass "多重命中 → REMOVAL（priority 1）" || fail "got $(jval .type)"

echo ""
echo "T6: 英文關鍵字"
t "delete the legacy endpoint"
[ "$(jval .type)" = "REMOVAL" ] && pass "delete → REMOVAL" || fail "got $(jval .type)"

echo ""
echo "T7: 無命中 → GENERAL fallback"
t "幫我看看這個專案"
[ "$(jval .type)" = "GENERAL" ] && pass "fallback → GENERAL" || fail "got $(jval .type)"
[ "$(jval .confidence)" = "0.3" ] && pass "GENERAL confidence=0.3" || fail "confidence=$(jval .confidence)"

echo ""
echo "T8: 輸出為合法 JSON 且欄位齊備"
t "修復 bug"
echo "$OUT" | jq -e 'has("type") and has("confidence") and has("matched") and has("reason") and has("await_required") and has("threshold") and has("hitl")' >/dev/null \
  && pass "全欄位齊備" || fail "fields missing: $OUT"
C=$(jval .confidence)
awk -v c="$C" 'BEGIN{exit !(c>0 && c<=1)}' && pass "confidence ∈ (0,1]" || fail "confidence=$C"

echo ""
echo "T9: 空輸入 → exit 2"
t ""
[ "$RC" = "2" ] && pass "空輸入 exit 2" || fail "rc=$RC"
t "   "
[ "$RC" = "2" ] && pass "全空白 exit 2" || fail "rc=$RC"

echo ""
echo "T10: rules 檔缺失 → exit 3"
OUT=$(bash "$SCRIPT" --rules /nonexistent/rules.json "修 bug" 2>/dev/null); RC=$?
[ "$RC" = "3" ] && pass "rules 缺失 exit 3" || fail "rc=$RC"

echo ""
echo "T11: --domain auth 偵測"
t --domain "JWT token 過期沒有擋住未授權請求"
[ "$(jval .domain)" = "auth" ] && pass "domain=auth" || fail "domain=$(jval .domain)"
echo "$OUT" | jq -e '.add_agents | index("sec")' >/dev/null && pass "add_agents 含 sec" || fail "add_agents=$(jval .add_agents)"

echo ""
echo "T12: --domain data_integrity → force_full_test"
t --domain "migration 之後出現 duplicate 資料"
[ "$(jval .domain)" = "data_integrity" ] && pass "domain=data_integrity" || fail "domain=$(jval .domain)"
[ "$(jval .force_full_test)" = "true" ] && pass "force_full_test=true" || fail "force_full_test=$(jval .force_full_test)"
t --domain "完全無關的描述文字"
[ "$(jval .domain)" = "general" ] && pass "無命中 → domain=general" || fail "domain=$(jval .domain)"

echo ""
echo "T13: 引號注入安全"
t '修復 "quoted" bug 與 \ 反斜線'
echo "$OUT" | jq -e . >/dev/null && pass "含引號輸入仍輸出合法 JSON" || fail "broken JSON"

echo ""
echo "T14: 確定性（同輸入同輸出）"
A=$(bash "$SCRIPT" "修復登入 bug" 2>/dev/null)
B=$(bash "$SCRIPT" "修復登入 bug" 2>/dev/null)
[ "$A" = "$B" ] && pass "兩次輸出一致" || fail "outputs differ"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
