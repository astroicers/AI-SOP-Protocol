#!/usr/bin/env bash
# test_rule_stats.sh — rule-stats.sh 統計端（v5 ADR-018）。
# 斷言：registry 全 id 枚舉（零命中必列）、90 天窗、gate-log 機械統計、
# disposition 四分類、退出碼。
# Run: bash tests/test_rule_stats.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ASP_ROOT/.asp/scripts/rule-stats.sh"
TEST_DIR=$(mktemp -d /tmp/asp-test-rs-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# fixture registry（4 條涵蓋四種 disposition）+ jsonl + gate-log
REG="$TEST_DIR/registry.yaml"
cat > "$REG" <<'EOF'
version: 1
rules:
  - id: IRON-X
    desc: "iron"
    source: "t"
    observed_by: session-audit
    exempt: true
  - id: AUDIT-HIT
    desc: "hit me"
    source: "t"
    observed_by: session-audit
  - id: AUDIT-COLD
    desc: "never fires"
    source: "t"
    observed_by: session-audit
  - id: DENY-X
    desc: "unobservable"
    source: "t"
    observed_by: none
  - id: GATE-G1
    desc: "gate"
    source: "t"
    observed_by: gate-log
EOF
M="$TEST_DIR/hits.jsonl"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OLD=$(date -u -d '120 days ago' +%Y-%m-%dT%H:%M:%SZ)
printf '{"ts":"%s","project":"p","rule_id":"AUDIT-HIT","action":"warn"}\n' "$NOW" >> "$M"
printf '{"ts":"%s","project":"p","rule_id":"AUDIT-HIT","action":"warn"}\n' "$NOW" >> "$M"
printf '{"ts":"%s","project":"p","rule_id":"AUDIT-COLD","action":"warn"}\n' "$OLD" >> "$M"   # 窗外
GL="$TEST_DIR/gate-log"; mkdir -p "$GL"
printf -- '---\ngate: G1\nresult: PASS\n---\nbody\n' > "$GL/20990101T000000Z-G1-ADR-001.md"

run() { OUT=$(ASP_RULE_REGISTRY="$REG" ASP_METRICS_FILE="$M" ASP_GATE_LOG_DIR="$GL" bash "$SCRIPT" "$@" 2>"$TEST_DIR/err"); RC=$?; }

echo ""
echo "T1: 全 id 枚舉 + 命中計數"
run
[ "$RC" = "0" ] && pass "exit 0" || fail "rc=$RC err=$(cat "$TEST_DIR/err")"
for id in IRON-X AUDIT-HIT AUDIT-COLD DENY-X GATE-G1; do
  echo "$OUT" | grep -q "$id" && pass "$id 在輸出中" || fail "$id 缺席"
done
echo "$OUT" | grep 'AUDIT-HIT' | grep -q ' 2 ' && pass "AUDIT-HIT hits=2" || fail "AUDIT-HIT 計數錯: $(echo "$OUT" | grep AUDIT-HIT)"

echo ""
echo "T2: 90 天窗（窗外事件不計）+ disposition 四分類"
echo "$OUT" | grep 'AUDIT-COLD' | grep -q '待刪候選' && pass "AUDIT-COLD（窗外）→ 待刪候選" || fail "AUDIT-COLD 分類錯"
echo "$OUT" | grep 'IRON-X' | grep -q '鐵則豁免' && pass "exempt → 鐵則豁免" || fail "IRON-X 分類錯"
echo "$OUT" | grep 'DENY-X' | grep -q '不可觀測' && pass "observed_by none → 不可觀測" || fail "DENY-X 分類錯"
echo "$OUT" | grep 'AUDIT-HIT' | grep -q 'active' && pass "有命中 → active" || fail "AUDIT-HIT 分類錯"
echo "$OUT" | grep 'GATE-G1' | grep -q ' 1 ' && pass "GATE-G1 gate-log 機械計數=1" || fail "GATE-G1 計數錯"

echo ""
echo "T3: --days 365 → 窗外事件納入"
run --days 365
echo "$OUT" | grep 'AUDIT-COLD' | grep -q ' 1 ' && pass "--days 365 納入舊事件" || fail "窗口參數無效"

echo ""
echo "T4: 待刪候選彙總段存在"
run
echo "$OUT" | grep -q '待刪候選' && pass "輸出含待刪候選段" || fail "缺彙總段"

echo ""
echo "T5: 退出碼"
ASP_RULE_REGISTRY="$TEST_DIR/nonexistent.yaml" bash "$SCRIPT" >/dev/null 2>&1; RC=$?
[ "$RC" = "2" ] && pass "registry 缺失 exit 2" || fail "rc=$RC"
ASP_RULE_REGISTRY="$REG" ASP_METRICS_FILE="$TEST_DIR/no-such.jsonl" ASP_GATE_LOG_DIR="$GL" bash "$SCRIPT" >/dev/null 2>&1; RC=$?
[ "$RC" = "0" ] && pass "遙測檔缺失視為全零、exit 0" || fail "rc=$RC"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
