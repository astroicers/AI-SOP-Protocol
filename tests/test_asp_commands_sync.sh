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

# ── (4) 讓位給 asp-ng：帶 asp-ng-install: 標記的檔案不得被覆寫（2026-09-09）──
# 這個路徑有**兩個**安裝器在寫：本同步器與 asp-ng 的 `asp install`。原本兩側都
# 「先清空再覆蓋」，於是任一側跑一次就把另一側洗掉——實測家目錄 / 本 repo HEAD /
# asp-ng skills 三側 sha256 互不相同即為此。改為見標記即跳過。
#
# 為何不是「本側整個停掉」：那會讓只裝本 repo（未裝 asp-ng）的人回到 (2) 當初要修的
# 那個 bug——新電腦安裝後沒有 /asp:* 指令。(2) 與本案必須同時綠。
MARKED="$HOME_DIR/.claude/commands/asp/merge.md"
mkdir -p "$(dirname "$MARKED")"
printf '%s\n' '---' '# asp-ng-install: 由 `asp install` 產生——勿手改' 'ASPNG-SENTINEL' > "$MARKED"
UNMARKED="$HOME_DIR/.claude/commands/asp/approve-adr.md"
: > "$UNMARKED"                                   # 清空但無標記 → 應被同步回來

HOME="$HOME_DIR" ASP_REPO="$ASP_ROOT" bash "$SYNC" --yes >/dev/null 2>&1

if grep -q "ASPNG-SENTINEL" "$MARKED"; then
  pass "帶 asp-ng-install: 標記的 merge.md 未被覆寫（讓位成立）"
else
  fail "帶標記的檔案被覆寫——兩個安裝器仍會互相抹掉"
fi
if [ -s "$UNMARKED" ] && grep -q "argument-hint\|^---" "$UNMARKED"; then
  pass "無標記的 approve-adr.md 照常被同步（讓位不等於整個停掉）"
else
  fail "無標記的檔案未被同步——本側的安裝責任被誤停"
fi
if [ -f "$SIBLING" ] && grep -q "keep-me" "$SIBLING"; then
  pass "讓位邏輯下共用頂層 sibling 仍未被誤刪"
else
  fail "讓位邏輯破壞了共用頂層安全契約"
fi

# ── (5) 讓位判斷的兩個新分支（2026-09-09，第三輪複審：原本零覆蓋）──
# 兩者都是「不確定時保守讓位」：讀不到的檔可能是別人的，覆寫它就是資料遺失；
# 目錄無從帶標記，`cp -r <dir> <existing-dir>` 還會巢狀成 sub/sub。
UNREADABLE="$HOME_DIR/.claude/commands/asp/review-work.md"
printf '%s\n' 'UNREADABLE-SENTINEL' > "$UNREADABLE" && chmod 000 "$UNREADABLE"
SUBDIR="$HOME_DIR/.claude/commands/asp/approve-adr.md"
rm -f "$SUBDIR" && mkdir -p "$SUBDIR" && : > "$SUBDIR/inside.txt"

SYNC_OUT=$(HOME="$HOME_DIR" ASP_REPO="$ASP_ROOT" bash "$SYNC" --yes 2>&1)

chmod 644 "$UNREADABLE" 2>/dev/null
# ⚠️ 斷言不能只看「哨兵還在」——那是恆真的：`cp` 對 mode 000 的目標本來就會 EACCES 失敗，
# 保護它的是檔案權限而非本守衛（第三輪複審變異實測：拿掉守衛，哨兵照樣活著）。
# 也不能驗「印了 skip」：此時三個目標都被判為已讓位 → DIFF_CMDS 為空 → 走
# 「Already in sync」提前結束，複製迴圈根本不會跑。
# 真正有鑑別力的觀察是 **cp 有沒有炸出錯誤**：有守衛 → 一個字都不會冒；
# 沒守衛 → `cp: … Permission denied`（變異實測 =1）。那是個沒人收的錯誤輸出。
if grep -q "UNREADABLE-SENTINEL" "$UNREADABLE" 2>/dev/null \
   && ! grep -qi "Permission denied" <<<"$SYNC_OUT"; then
  pass "(5a) 不可讀的目標檔由守衛讓位（無 cp 錯誤外洩），內容未被動"
else
  fail "(5a) 不可讀目標的處置不符 — cp 錯誤=$(grep -ci 'Permission denied' <<<"$SYNC_OUT")；哨兵在=$(grep -c 'UNREADABLE-SENTINEL' "$UNREADABLE" 2>/dev/null || echo 0)"
fi
if [ -d "$SUBDIR" ] && [ ! -e "$SUBDIR/approve-adr.md" ]; then
  pass "(5b) 目標是目錄時跳過，未 cp -r 進去造成巢狀"
else
  fail "(5b) 目錄處置不符（巢狀或被取代）"
fi

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
