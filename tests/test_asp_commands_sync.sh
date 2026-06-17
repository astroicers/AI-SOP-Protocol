#!/usr/bin/env bash
# test_asp_commands_sync.sh — 安裝器/同步器必須把 repo 的 .claude/commands/asp/
# 同步到 ~/.claude/commands/asp/，且**絕不**刪除共用頂層 ~/.claude/commands/ 的非-asp 檔。
#
# 對應 bugfix：自訂 slash 指令（/asp:approve-adr、/asp:review-work）過去只在原作者本機，
# 從未進 repo，故新電腦安裝後缺指令。本測試釘住三個核心契約：
#   (1) commands/asp 來源存在於 repo
#   (2) 升級情境（已裝 asp/skills、缺 commands/asp）跑 asp-sync 後 commands/asp 會落地
#   (3) 共用頂層 ~/.claude/commands/ 的 sibling 檔不被誤刪（rm/--delete 限 asp 子目錄）
# 並以 grep 守護三腳本（install.sh / install.ps1 / asp-sync.sh）的 commands 邏輯不被回退。
#
# Run: bash tests/test_asp_commands_sync.sh
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$ASP_ROOT/.claude/scripts/asp-sync.sh"
mk_test_dir asp-commands-sync

# ── (1) repo 來源存在 ──────────────────────────────────────────────
if [ -f "$ASP_ROOT/.claude/commands/asp/approve-adr.md" ] && \
   [ -f "$ASP_ROOT/.claude/commands/asp/review-work.md" ]; then
  pass "repo 有 .claude/commands/asp/ 權威來源（approve-adr + review-work）"
else
  fail "repo 缺 .claude/commands/asp/ 來源（bugfix 未落地）"
fi

# ── 模擬「已裝舊版 ASP（asp+skills 在）但無 commands/asp」的升級情境 ──
HOME_DIR="$TEST_DIR/home"
mkdir -p "$HOME_DIR/.claude/skills" "$HOME_DIR/.claude/commands"
cp -r "$ASP_ROOT/.asp" "$HOME_DIR/.claude/asp"
cp -r "$ASP_ROOT/.claude/skills/asp" "$HOME_DIR/.claude/skills/asp"
SIBLING="$HOME_DIR/.claude/commands/other-tool.md"     # 別的工具的指令，應被保留
echo "keep-me" > "$SIBLING"

# ── (2) 跑同步 ─────────────────────────────────────────────────────
HOME="$HOME_DIR" ASP_REPO="$ASP_ROOT" bash "$SYNC" --yes >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && pass "asp-sync --yes 正常結束 (rc=0)" || fail "asp-sync 非零退出 (rc=$rc)"

[ -f "$HOME_DIR/.claude/commands/asp/approve-adr.md" ] && pass "approve-adr.md 已同步落地" || fail "approve-adr.md 未同步"
[ -f "$HOME_DIR/.claude/commands/asp/review-work.md" ] && pass "review-work.md 已同步落地" || fail "review-work.md 未同步"

# ── (3) 共用頂層 sibling 未被刪（核心安全契約）─────────────────────
if [ -f "$SIBLING" ] && grep -q "keep-me" "$SIBLING"; then
  pass "共用頂層 other-tool.md 未被誤刪（rm/rsync --delete 限 asp 子目錄）"
else
  fail "共用頂層 other-tool.md 被刪/竄改（安全契約破壞！）"
fi

# ── 冪等：第二次應 Already in sync ─────────────────────────────────
out=$(HOME="$HOME_DIR" ASP_REPO="$ASP_ROOT" bash "$SYNC" --yes 2>&1)
echo "$out" | grep -q "Already in sync" && pass "第二次同步冪等 (Already in sync)" || fail "第二次同步非冪等"

# ── 三腳本 parity 守護（防未來回退）──────────────────────────────
grep -q "commands/asp" "$ASP_ROOT/.asp/scripts/install.sh"      && pass "install.sh 含 commands/asp 複製邏輯"      || fail "install.sh 缺 commands/asp 邏輯"
grep -q "commands.asp" "$ASP_ROOT/.asp/scripts/install.ps1"     && pass "install.ps1 含 commands\\asp 複製邏輯"    || fail "install.ps1 缺 commands\\asp 邏輯"
grep -q "commands/asp" "$ASP_ROOT/.claude/scripts/asp-sync.sh"  && pass "asp-sync.sh 含 commands/asp 同步邏輯"     || fail "asp-sync.sh 缺 commands/asp 邏輯"

# ── review-work.md 內容護欄（防範圍自動判斷邏輯被未來編輯靜默移除）──
RW="$ASP_ROOT/.claude/commands/asp/review-work.md"
grep -q "argument-hint" "$RW" && pass "review-work.md 保留 argument-hint frontmatter"          || fail "review-work.md 缺 argument-hint"
grep -q "推斷規則"      "$RW" && pass "review-work.md 含未指定參數時的自動範圍推斷規則段落"   || fail "review-work.md 缺自動推斷規則（auto-judgment 邏輯遺失）"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
