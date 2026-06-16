#!/usr/bin/env bash
# test_ship_step96.sh — SPEC-006: asp-ship Step 9.6 gate-log 後驗
# 從 asp-ship.md Step 9.6 擷取 bash 區塊，在沙箱 repo 行為測試：
# 缺 log → WARN；log 齊 → 無 WARN；無 ADR/SPEC → 安靜跳過。
# Run: bash tests/test_ship_step96.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIP="$ASP_ROOT/.claude/skills/asp/asp-ship.md"
mk_test_dir

# ── 擷取 Step 9.6 的 bash 區塊（契約：文件內程式碼必須可執行且正確）──
SNIPPET=$(sed -n '/^### Step 9\.6/,/^### Step 10/p' "$SHIP" | sed -n '/^```bash$/,/^```$/p' | sed '1d;$d')
if [ -z "$SNIPPET" ]; then
    fail "asp-ship.md 無 Step 9.6 bash 區塊（SPEC-006 未落地）"
    echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"; exit 1
fi
pass "Step 9.6 bash 區塊存在"
echo "$SNIPPET" > "$TEST_DIR/step96.sh"

setup_repo() {
    rm -rf "${TEST_DIR:?}/repo"
    git init -q -b main "$TEST_DIR/repo"
    cd "$TEST_DIR/repo" || exit 1
    git config user.email "t@test"; git config user.name "t"
    mkdir -p docs/adr docs/specs
    echo seed > seed.txt; git add -A; git commit -q -m init
    cd "$ASP_ROOT" || exit 1
}

run96() { ( cd "$TEST_DIR/repo" && bash "$TEST_DIR/step96.sh" 2>&1 ); }

# ── T1: staged ADR、無 gate log → WARN ──
echo ""; echo "T1: staged ADR without gate log → WARN"
setup_repo
echo "# adr" > "$TEST_DIR/repo/docs/adr/ADR-099-test.md"
( cd "$TEST_DIR/repo" && git add docs/adr/ADR-099-test.md )
out=$(run96)
grep -q "Step 9.6 WARN" <<<"$out" && pass "WARN 輸出" || fail "無 WARN（got: $out）"
grep -q "ADR-099" <<<"$out" && pass "WARN 指名缺漏 ID" || fail "WARN 未指名 ID"

# ── T2: staged ADR + 對應 gate log → 無 WARN ──
echo ""; echo "T2: staged ADR with matching gate log → no WARN"
setup_repo
echo "# adr" > "$TEST_DIR/repo/docs/adr/ADR-099-test.md"
( cd "$TEST_DIR/repo" && git add docs/adr/ADR-099-test.md )
mkdir -p "$TEST_DIR/repo/.asp-gate-log"
touch "$TEST_DIR/repo/.asp-gate-log/20260611T000000Z-G1-ADR-099.md"
out=$(run96)
grep -q "Step 9.6 WARN" <<<"$out" && fail "不應有 WARN（got: $out）" || pass "無 WARN"

# ── T3: 無 ADR/SPEC staged → 安靜跳過（exit 0）──
echo ""; echo "T3: no ADR/SPEC staged → silent exit 0"
setup_repo
echo x > "$TEST_DIR/repo/other.txt"
( cd "$TEST_DIR/repo" && git add other.txt )
out=$(run96); rc=$?
[ "$rc" -eq 0 ] && pass "exit 0" || fail "exit $rc"
grep -q "WARN" <<<"$out" && fail "不應有 WARN" || pass "無輸出噪音"

# ── T4: SPEC staged 也納管 ──
echo ""; echo "T4: staged SPEC without log → WARN"
setup_repo
echo "# spec" > "$TEST_DIR/repo/docs/specs/SPEC-099-test.md"
( cd "$TEST_DIR/repo" && git add docs/specs/SPEC-099-test.md )
out=$(run96)
grep -q "Step 9.6 WARN" <<<"$out" && pass "SPEC 缺 log → WARN" || fail "SPEC 未被納管"

echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
