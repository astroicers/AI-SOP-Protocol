#!/usr/bin/env bash
# test_auto_gate_glob_matcher.sh — SPEC-006: Step 5.5 機械觸發判斷
# 從 asp-plan.md Step 5.5.1 擷取 bash 區塊，在沙箱 git repo 對 staged 變更執行，
# 驗證 P1/P2/P3/N1/B1/B2/B3（含 E3 刪除不觸發 + supersede 提示）。
# Run: bash tests/test_auto_gate_glob_matcher.sh

set -uo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAN="$ASP_ROOT/.claude/skills/asp/asp-plan.md"
TEST_DIR=$(mktemp -d /tmp/asp-test-glob-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

# ── 擷取 asp-plan.md Step 5.5.1 的觸發 bash 區塊（契約：文件內的程式碼必須可執行且正確）──
SNIPPET=$(sed -n '/^### 5\.5\.1/,/^### 5\.5\.2/p' "$PLAN" | sed -n '/^```bash$/,/^```$/p' | sed '1d;$d')
if [ -z "$SNIPPET" ]; then
    fail "asp-plan.md Step 5.5.1 無 bash 觸發區塊（SPEC-006 未落地）"
    echo "PASS: $PASS / $((TOTAL))  (FAIL: $FAIL)"; exit 1
fi
pass "Step 5.5.1 bash 觸發區塊存在"

setup_repo() {
    rm -rf "${TEST_DIR:?}"/*
    git init -q -b main "$TEST_DIR/repo"
    cd "$TEST_DIR/repo" || exit 1
    git config user.email "t@test"; git config user.name "t"
    mkdir -p docs/adr docs/specs .claude/skills/asp
    echo "# seed" > docs/adr/ADR-001-seed.md
    echo "# readme" > docs/adr/README.md
    git add -A; git commit -q -m init
}

# 在 repo 內執行擷取的 snippet，輸出三個計數
run_trigger() {
    cd "$TEST_DIR/repo" || exit 1
    eval "$SNIPPET" 2>/dev/null || true
    echo "${hits_adr:-?}|${hits_spec:-?}|${deleted_gov:-?}"
    cd "$ASP_ROOT" || exit 1
}

# ── P1: 新增 ADR → hits_adr=1 ──
echo ""; echo "P1: staged new ADR triggers G1"
setup_repo
echo "# new" > "$TEST_DIR/repo/docs/adr/ADR-010-foo.md"
( cd "$TEST_DIR/repo" && git add docs/adr/ADR-010-foo.md )
r=$(run_trigger)
[ "$r" = "1|0|0" ] && pass "ADR-010 → hits 1|0|0" || fail "got $r (want 1|0|0)"

# ── P2: ADR + SPEC 同 plan → 兩者皆觸發 ──
echo ""; echo "P2: ADR + SPEC staged together"
setup_repo
echo "# a" > "$TEST_DIR/repo/docs/adr/ADR-010-foo.md"
echo "# s" > "$TEST_DIR/repo/docs/specs/SPEC-007-bar.md"
( cd "$TEST_DIR/repo" && git add -A )
r=$(run_trigger)
[ "$r" = "1|1|0" ] && pass "→ 1|1|0" || fail "got $r (want 1|1|0)"

# ── P3: 只動 skill → 全 0（skip 路徑）──
echo ""; echo "P3: skill-only change does not trigger"
setup_repo
echo "# sk" > "$TEST_DIR/repo/.claude/skills/asp/asp-plan.md"
( cd "$TEST_DIR/repo" && git add -A )
r=$(run_trigger)
[ "$r" = "0|0|0" ] && pass "→ 0|0|0" || fail "got $r (want 0|0|0)"

# ── N1: docs/adr/README.md 不命中 ──
echo ""; echo "N1: docs/adr/README.md does not match"
setup_repo
echo "更新" >> "$TEST_DIR/repo/docs/adr/README.md"
( cd "$TEST_DIR/repo" && git add docs/adr/README.md )
r=$(run_trigger)
[ "$r" = "0|0|0" ] && pass "README → 0|0|0" || fail "got $r (want 0|0|0)"

# ── B1: rename（git mv）→ 視同新增，觸發 ──
echo ""; echo "B1: git mv rename still triggers (treated as new)"
setup_repo
( cd "$TEST_DIR/repo" && git mv docs/adr/ADR-001-seed.md docs/adr/ADR-011-renamed.md )
r=$(run_trigger)
[ "$r" = "1|0|0" ] && pass "rename → 1|0|0" || fail "got $r (want 1|0|0)"

# ── B2: 既有 ADR 內容修改（status-only 等價）→ 仍觸發 ──
echo ""; echo "B2: modify existing ADR (status-only) still triggers"
setup_repo
echo "Status: Accepted" >> "$TEST_DIR/repo/docs/adr/ADR-001-seed.md"
( cd "$TEST_DIR/repo" && git add docs/adr/ADR-001-seed.md )
r=$(run_trigger)
[ "$r" = "1|0|0" ] && pass "modify → 1|0|0" || fail "got $r (want 1|0|0)"

# ── B3/E3: 刪除 ADR → 不觸發 G1，deleted_gov=1（supersede 提示）──
echo ""; echo "B3: git rm ADR does NOT trigger; counts as deletion"
setup_repo
( cd "$TEST_DIR/repo" && git rm -q docs/adr/ADR-001-seed.md )
r=$(run_trigger)
[ "$r" = "0|0|1" ] && pass "delete → 0|0|1（不觸發 + supersede 提示計數）" || fail "got $r (want 0|0|1)"

echo ""
echo "================================"
echo "PASS: $PASS / $TOTAL  (FAIL: $FAIL)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
