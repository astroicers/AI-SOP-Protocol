#!/usr/bin/env bash
# test_asp_sync_metrics.sh — asp-sync 必須保護 user-level runtime 遙測 metrics/
#
# metrics/rule-hits.jsonl 由 session-audit 每次規則 fire 追加（ADR-018 規則留存證據源），
# 是 user-level 生成的本地資料，repo source 沒有它。asp-sync 的 rsync --delete /
# fallback rm -rf 若不排除 metrics，會無聲刪光遙測（同 .showcase-installed 的保護理由）。
# Run: bash tests/test_asp_sync_metrics.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$ASP_ROOT/.claude/scripts/asp-sync.sh"
FAKE=$(mktemp -d /tmp/asp-sync-test-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup(){ rm -rf "$FAKE"; }
trap cleanup EXIT
pass(){ echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# 假 repo（$HOME/AI-SOP-Protocol）— asp-sync 以 $HOME 推導路徑
REPO="$FAKE/AI-SOP-Protocol"
mkdir -p "$REPO/.asp/profiles" "$REPO/.asp/hooks" "$REPO/.asp/config" "$REPO/.claude/skills/asp"
echo "9.9.9" > "$REPO/.asp/VERSION"
echo "# gc"   > "$REPO/.asp/profiles/global_core.md"
echo "echo hi" > "$REPO/.asp/hooks/session-audit.sh"
echo "v: 1"   > "$REPO/.asp/config/profile-map.yaml"
echo "# skill" > "$REPO/.claude/skills/asp/SKILL.md"

# 假 user-level（$HOME/.claude/asp 含 metrics 遙測 + skills）
mkdir -p "$FAKE/.claude/asp/metrics" "$FAKE/.claude/skills/asp"
echo "8.8.8" > "$FAKE/.claude/asp/VERSION"
printf '%s\n' '{"id":"AUDIT-A1","ts":"t1"}' '{"id":"IRON-B","ts":"t2"}' '{"id":"GATE-G2","ts":"t3"}' \
  > "$FAKE/.claude/asp/metrics/rule-hits.jsonl"
BEFORE=$(wc -l < "$FAKE/.claude/asp/metrics/rule-hits.jsonl")

# 執行 asp-sync（假 HOME → 假 repo + 假 user-level）
HOME="$FAKE" bash "$SYNC" --yes >/dev/null 2>&1 || true

echo ""
echo "T1: metrics/rule-hits.jsonl sync 後仍存在（不被 --delete 刪）"
[ -f "$FAKE/.claude/asp/metrics/rule-hits.jsonl" ] && pass "metrics 檔保留" || fail "metrics 被刪（遙測資料遺失）"

echo ""
echo "T2: metrics 內容未被截斷（行數不變）"
if [ -f "$FAKE/.claude/asp/metrics/rule-hits.jsonl" ]; then
  AFTER=$(wc -l < "$FAKE/.claude/asp/metrics/rule-hits.jsonl")
  [ "$AFTER" = "$BEFORE" ] && pass "行數保留（$AFTER 行）" || fail "行數變動 $BEFORE→$AFTER"
else
  fail "metrics 不存在，無法驗行數"
fi

echo ""
echo "T3: 同步仍正常完成（repo profile 已寫入 user-level）"
[ -f "$FAKE/.claude/asp/profiles/global_core.md" ] && pass "profile 已同步" || fail "同步未完成"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
