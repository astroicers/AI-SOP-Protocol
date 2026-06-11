#!/usr/bin/env bash
# test_auto_gate_log_write.sh — SPEC-006: gate log 檔名 pattern + frontmatter schema
# 驗證 (1) .asp-gate-log/ 目錄初始化（A.5），(2) fixture 與所有真實 log 符合 schema。
# Run: bash tests/test_auto_gate_log_write.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$ASP_ROOT/.asp-gate-log"
FIXTURE="$ASP_ROOT/tests/fixtures/auto-gate/sample-gate-log.md"
PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

FNAME_RE='^[0-9]{8}T[0-9]{6}Z-G[1-6]-(ADR|SPEC)-[0-9]+.*\.md$'
REQUIRED_KEYS=(gate target_id target_path trigger_commit spawn_timestamp_utc subagent_type result findings_count)

check_log() {  # $1=path → asserts frontmatter keys + result 值域
    local f="$1" name; name=$(basename "$f")
    local fm; fm=$(sed -n '/^---$/,/^---$/p' "$f")
    local ok=1
    for k in "${REQUIRED_KEYS[@]}"; do
        echo "$fm" | grep -q "^${k}:" || { fail "$name 缺 frontmatter key: $k"; ok=0; }
    done
    [ "$ok" -eq 1 ] && pass "$name frontmatter keys 齊全"
    echo "$fm" | grep -E "^result: *(PASS|PASS_WITH_WARN|FAIL)" >/dev/null \
        && pass "$name result 值域正確" || fail "$name result 值域非法"
}

# ── A.5: 目錄初始化 ──
echo ""; echo "A5: .asp-gate-log/ initialized"
[ -d "$LOG_DIR" ] && pass ".asp-gate-log/ 存在" || fail ".asp-gate-log/ 不存在（A.5 未落地）"
[ -f "$LOG_DIR/.gitkeep" ] && pass ".gitkeep 存在" || fail ".gitkeep 缺"
[ -f "$LOG_DIR/.gitignore" ] && grep -q '\*.tmp' "$LOG_DIR/.gitignore" 2>/dev/null \
    && pass ".gitignore 排除暫存檔" || fail ".gitignore 缺或未排除 *.tmp"

# ── fixture schema ──
echo ""; echo "Fixture: sample-gate-log.md schema"
[ -f "$FIXTURE" ] && check_log "$FIXTURE" || fail "fixture 不存在"

# ── 真實 log（若有）：檔名 + schema 全驗 ──
echo ""; echo "Real logs in .asp-gate-log/ (if any)"
shopt -s nullglob
REAL=("$LOG_DIR"/*.md)
shopt -u nullglob
if [ "${#REAL[@]}" -eq 0 ]; then
    fail "尚無任何真實 gate log（SPEC-006 落地時應產生第一筆，例如本 SPEC 自己的 G2 報告）"
else
    for f in "${REAL[@]}"; do
        name=$(basename "$f")
        echo "$name" | grep -qE "$FNAME_RE" \
            && pass "$name 檔名符合 pattern" || fail "$name 檔名不符 {ts}-G{n}-{id}.md"
        check_log "$f"
    done
fi

echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
