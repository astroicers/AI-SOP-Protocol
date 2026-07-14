#!/usr/bin/env bash
# test_session_journal.sh — SPEC-014 Feature A：Session 敘事日誌讀回閉環
#
# SessionEnd hook（session-end-journal.sh）把本 session 的機械事實 + 人工 note
# append 到 .asp-session-journal.jsonl；session-audit.sh 於 SessionStart 讀 tail-N
# 注入 stdout。純副作用、恆 exit 0。
# Run: bash tests/test_session_journal.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
END_HOOK="$ASP_ROOT/.asp/hooks/session-end-journal.sh"
AUDIT_HOOK="$ASP_ROOT/.asp/hooks/session-audit.sh"
mk_test_dir
command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq 不存在";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git 不存在"; exit 0; }

PROJ="$TEST_DIR/proj"; mkdir -p "$PROJ"
git -C "$PROJ" init -q
git -C "$PROJ" config user.email t@t.local
git -C "$PROJ" config user.name  tester
echo a > "$PROJ/a.txt"; git -C "$PROJ" add .; git -C "$PROJ" commit -qm init
BASE=$(git -C "$PROJ" rev-parse HEAD)

JOURNAL="$PROJ/.asp-session-journal.jsonl"
MARKER="$PROJ/.asp-session-marker.json"
NOTES="$PROJ/.asp-session-notes.tmp"
METRICS="$TEST_DIR/rule-hits.jsonl"

write_marker(){ printf '{"head":"%s","ts":"2020-01-01T00:00:00Z","branch":"main"}' "$1" > "$MARKER"; }
run_end(){ CLAUDE_PROJECT_DIR="$PROJ" ASP_METRICS_FILE="$METRICS" bash "$END_HOOK"; }
run_audit(){ # $1 = source (empty → no stdin)
  local src="${1:-}"
  { [ -n "$src" ] && printf '{"source":"%s","hook_event_name":"SessionStart"}' "$src" || true; } \
    | CLAUDE_PROJECT_DIR="$PROJ" ASP_METRICS_FILE="$METRICS" bash "$AUDIT_HOOK" 2>/dev/null
}

echo ""; echo "A-P1: marker + 期間 commit → journal append 該 commit"
rm -f "$JOURNAL"; write_marker "$BASE"
echo b > "$PROJ/b.txt"; git -C "$PROJ" add .; git -C "$PROJ" commit -qm "feat: add b"
run_end
{ [ -f "$JOURNAL" ] && grep -q 'feat: add b' "$JOURNAL"; } && pass "commit 寫入 journal" || fail "commit 未寫入 journal"
[ ! -f "$MARKER" ] && pass "marker 已被消費清除" || fail "marker 未清除"

echo ""; echo "A-P2: journal-note 暫存 → notes[] 收斂 + notes.tmp 清除"
write_marker "$(git -C "$PROJ" rev-parse HEAD)"
printf '踩到 X 陷阱\n' > "$NOTES"
echo c > "$PROJ/c.txt"; git -C "$PROJ" add .; git -C "$PROJ" commit -qm "feat: c"
run_end
grep -q '踩到 X 陷阱' "$JOURNAL" && pass "note 收斂進 notes[]" || fail "note 未寫入"
[ ! -f "$NOTES" ] && pass "notes.tmp 已清除" || fail "notes.tmp 未清除"

echo ""; echo "A-N1: 無 commit / note / test → 不寫空條目"
BEFORE=$(wc -l < "$JOURNAL")
write_marker "$(git -C "$PROJ" rev-parse HEAD)"
run_end
AFTER=$(wc -l < "$JOURNAL")
[ "$BEFORE" = "$AFTER" ] && pass "空 session 不 append" || fail "寫了空條目噪音"

echo ""; echo "A-N2: 無 marker → 不報錯（exit 0），有 note 仍記錄"
rm -f "$MARKER"
printf '無 marker 也要記\n' > "$NOTES"
run_end && pass "無 marker 恆 exit 0" || fail "無 marker 報錯"
grep -q '無 marker 也要記' "$JOURNAL" && pass "無 marker 時 note 仍寫入" || fail "note 未寫入"

echo ""; echo "A-P3: SessionStart 讀 tail-N 注入 '📓 最近 Session 經驗'"
OUT=$(run_audit startup)
echo "$OUT" | grep -q '📓 最近 Session 經驗' && pass "SessionStart 注入 journal 區塊" || fail "未注入 journal 區塊"

echo ""; echo "A-marker: SessionStart（startup）寫 .asp-session-marker.json"
rm -f "$MARKER"; run_audit startup >/dev/null
[ -f "$MARKER" ] && pass "startup 寫 marker" || fail "startup 未寫 marker"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
