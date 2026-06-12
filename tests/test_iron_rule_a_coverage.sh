#!/usr/bin/env bash
# test_iron_rule_a_coverage.sh — Iron Rule A 必須涵蓋所有「看守者」腳本
#
# Iron Rule A 用 git-HEAD hash 比對偵測「git 外竄改關鍵腳本」。session-audit.sh
# 的 Iron Rule B chain 驗證委派給 bypass-hash.sh —— 若 bypass-hash.sh 不在 Iron
# Rule A 保護內，攻擊者改其 verify() 永遠回 exit 0 即繞過整個 hash chain，且不被
# 偵測（ADR-019 review HIGH finding：看守者的看守者缺口）。
# Run: bash tests/test_iron_rule_a_coverage.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ASP_ROOT/.asp/hooks/session-audit.sh"
PASS=0; FAIL=0; TOTAL=0
pass(){ echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# 擷取 CRITICAL_FILE 迴圈列出的受保護檔
CRIT=$(grep -oE 'for CRITICAL_FILE in [^;]+' "$HOOK" | head -1)

echo ""
echo "T1: Iron Rule A 涵蓋核心 hook 與 deny 清單"
echo "$CRIT" | grep -q 'session-audit.sh' && pass "session-audit.sh 受保護" || fail "session-audit.sh 未受保護"
echo "$CRIT" | grep -q 'denied-commands.json' && pass "denied-commands.json 受保護" || fail "denied-commands.json 未受保護"

echo ""
echo "T2: Iron Rule A 涵蓋 chain 驗證器 bypass-hash.sh（ADR-019 review HIGH）"
echo "$CRIT" | grep -q 'bypass-hash.sh' \
  && pass "bypass-hash.sh 受 Iron Rule A 保護" \
  || fail "bypass-hash.sh 不受保護 — 改 verify() 即可繞過 chain（看守者缺口）"
echo "$CRIT" | grep -q 'pretooluse-ship-gate.sh' \
  && pass "pretooluse-ship-gate.sh 受 Iron Rule A 保護（ADR-020 commit 閘）" \
  || fail "pretooluse-ship-gate.sh 不受保護 — 改 hook 即可繞過 commit 閘"

echo ""
echo "T3: 受保護腳本實際存在（git-tracked，否則 Iron Rule A 形同虛設）"
for f in .asp/hooks/session-audit.sh .asp/hooks/denied-commands.json .asp/scripts/bypass-hash.sh .asp/hooks/pretooluse-ship-gate.sh; do
  [ -f "$ASP_ROOT/$f" ] && pass "$f 存在" || fail "$f 不存在"
done

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
