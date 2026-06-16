#!/usr/bin/env bash
# test_rule_metrics.sh — session-audit asp_metric() 寫入端（v5 ADR-018 方案 A）。
# 斷言：Draft ADR fixture → rule-hits.jsonl 含 AUDIT-A3.1 與 DENY-DYNAMIC；
# 每行合法 JSON；唯讀目錄模擬 → hook 恆 exit 0 無噪音（遙測永不影響主流程）；
# 專案名含引號 → JSON 仍合法。
# Run: bash tests/test_rule_metrics.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ASP_ROOT/.asp/hooks/session-audit.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-rm-XXXXXX)
cleanup() { chmod -R u+w "$TEST_DIR" 2>/dev/null; rm -rf "$TEST_DIR"; }
trap cleanup EXIT

mkproj() { # $1=dir
  rm -rf "$1"; mkdir -p "$1/docs/adr" "$1/.claude"
  touch "$1/README.md" "$1/CHANGELOG.md" "$1/Makefile"
  printf 'type: system\n' > "$1/.ai_profile"
}

echo ""
echo "T1: Draft ADR fixture → AUDIT-A3.1 + DENY-DYNAMIC 記錄"
P="$TEST_DIR/p1"; mkproj "$P"
printf '# [ADR-001]: x\n\n| 欄位 | 內容 |\n|---|---|\n| **狀態** | `Draft` |\n' > "$P/docs/adr/ADR-001-x.md"
M="$TEST_DIR/m1.jsonl"
CLAUDE_PROJECT_DIR="$P" ASP_METRICS_FILE="$M" bash "$HOOK" >/dev/null 2>&1; RC=$?
[ "$RC" = "0" ] && pass "hook exit 0" || fail "rc=$RC"
[ -f "$M" ] && pass "rule-hits.jsonl 已產生" || fail "jsonl 缺失"
grep -q '"rule_id":"AUDIT-A3.1"' "$M" && pass "含 AUDIT-A3.1（Draft ADR 阻擋記錄）" || fail "缺 AUDIT-A3.1: $(cat "$M" 2>/dev/null | head -3)"
grep -q '"rule_id":"DENY-DYNAMIC"' "$M" && pass "含 DENY-DYNAMIC（動態 deny 注入）" || fail "缺 DENY-DYNAMIC"
BAD=0
while IFS= read -r line; do echo "$line" | jq -e . >/dev/null 2>&1 || BAD=$((BAD+1)); done < "$M"
[ "$BAD" = "0" ] && pass "每行皆合法 JSON" || fail "$BAD 行非法 JSON"
jq -e 'has("ts") and has("project") and has("rule_id") and has("action")' <(head -1 "$M") >/dev/null \
  && pass "欄位齊備 {ts, project, rule_id, action}" || fail "欄位缺失"

echo ""
echo "T2: 唯讀目錄模擬 → hook 恆 exit 0、briefing 仍生成、無 metrics 錯誤噪音"
P="$TEST_DIR/p2"; mkproj "$P"
mkdir -p "$TEST_DIR/ro"; chmod 555 "$TEST_DIR/ro"
OUT=$(CLAUDE_PROJECT_DIR="$P" ASP_METRICS_FILE="$TEST_DIR/ro/sub/m.jsonl" bash "$HOOK" 2>&1); RC=$?
[ "$RC" = "0" ] && pass "唯讀下 hook exit 0" || fail "rc=$RC"
[ -f "$P/.asp-session-briefing.json" ] && pass "briefing 仍生成" || fail "briefing 缺失"
grep -qi 'metrics.*error\|permission denied' <<<"$OUT" && fail "stderr 有 metrics 噪音" || pass "無 metrics 錯誤噪音"

echo ""
echo "T3: 專案名含引號 → JSON 仍合法"
P="$TEST_DIR/p3 \"quoted\""; mkproj "$P"
printf '# [ADR-001]: x\n\n| **狀態** | `Draft` |\n' > "$P/docs/adr/ADR-001-x.md"
M="$TEST_DIR/m3.jsonl"
CLAUDE_PROJECT_DIR="$P" ASP_METRICS_FILE="$M" bash "$HOOK" >/dev/null 2>&1
if [ -s "$M" ]; then
  jq -es . "$M" >/dev/null 2>&1 && pass "引號專案名 → 全部合法 JSON" || fail "JSON 損壞"
else
  fail "無記錄寫入"
fi

echo ""
echo "T4: 一般 session（無 Draft）也有評估記錄（A14 / A5 類）"
P="$TEST_DIR/p4"; mkproj "$P"; rm "$P/CHANGELOG.md"
M="$TEST_DIR/m4.jsonl"
CLAUDE_PROJECT_DIR="$P" ASP_METRICS_FILE="$M" bash "$HOOK" >/dev/null 2>&1
grep -q '"rule_id":"AUDIT-A14.1"' "$M" && pass "A14.1（無 baseline）有記錄" || fail "缺 A14.1"
grep -q '"rule_id":"AUDIT-A5.9"' "$M" && pass "A5.9（缺檔聚合）有記錄" || fail "缺 A5.9"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
