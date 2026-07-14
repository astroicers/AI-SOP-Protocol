#!/usr/bin/env bash
# test_session_audit_compact.sh — SPEC-014 Feature B：Compact-aware 重注入
#
# session-audit.sh 解析 SessionStart hook stdin 的 source；source=compact 時額外
# 注入「Post-Compaction 存活包」。無 stdin 不得 hang、不誤觸。恆 exit 0。
# Run: bash tests/test_session_audit_compact.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT_HOOK="$ASP_ROOT/.asp/hooks/session-audit.sh"
mk_test_dir
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 不存在"; exit 0; }

PROJ="$TEST_DIR/proj"; mkdir -p "$PROJ"
command -v git >/dev/null 2>&1 && git -C "$PROJ" init -q
METRICS="$TEST_DIR/rule-hits.jsonl"
PACK='Post-Compaction 存活包'

run_audit(){ # $1 = source (empty → no stdin)
  local src="${1:-}"
  { [ -n "$src" ] && printf '{"source":"%s","hook_event_name":"SessionStart"}' "$src" || true; } \
    | CLAUDE_PROJECT_DIR="$PROJ" ASP_METRICS_FILE="$METRICS" bash "$AUDIT_HOOK" 2>/dev/null
}

echo ""; echo "B-P1: source=compact → 注入存活包"
OUT=$(run_audit compact)
echo "$OUT" | grep -q "$PACK" && pass "compact 注入存活包" || fail "compact 未注入存活包"

echo ""; echo "B-N1: source=startup → 不注入存活包"
OUT=$(run_audit startup)
echo "$OUT" | grep -q "$PACK" && fail "startup 誤觸存活包" || pass "startup 不注入存活包"

echo ""; echo "B-N2: 無 stdin → 不 hang、仍審計、不誤觸"
START=$(date +%s)
OUT=$(run_audit "")
END=$(date +%s)
echo "$OUT" | grep -q '## ASP Session Audit' && pass "無 stdin 仍輸出審計摘要" || fail "無 stdin 未輸出審計"
[ $((END - START)) -le 5 ] && pass "無 stdin 不 hang（<=5s）" || fail "無 stdin 疑似 hang（>5s）"
echo "$OUT" | grep -q "$PACK" && fail "無 stdin 誤觸存活包" || pass "無 stdin 不誤觸存活包"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
