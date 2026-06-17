#!/usr/bin/env bash
# test_asp_sync_downgrade.sh — asp-sync 必須做版本方向防護（不可把降級當升級無聲執行）
#
# 缺陷背景：asp-sync 只用 diff -rq 比檔案差異，從不比 semver。當來源 repo 的
# .asp/VERSION 比已安裝舊（本地 repo 停在舊 commit / curl 抓到落後 origin），
# 會把「降級」當「同步/升級」執行並印 v{新} → v{舊}，毫無警告。本測試鎖定方向防護：
#   - 降級 + 非互動 → 預設中止（exit≠0），不覆蓋已安裝檔
#   - 降級 + ASP_ALLOW_DOWNGRADE=1 → 放行，文案「降級完成」
#   - 升級 → 正常放行，文案「升級」
#   - 同版本（內容有差）→ 照常同步，無「降級」字樣
#   - 非 semver（not installed/unknown）→ 不誤判降級
# Run: bash tests/test_asp_sync_downgrade.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$ASP_ROOT/.claude/scripts/asp-sync.sh"
mk_test_dir asp-sync-downgrade   # 單一 base dir（$TEST_DIR），各情境用子目錄當假 HOME

# 建一份最小合法 source repo 於 <home>/AI-SOP-Protocol，VERSION=<ver>
# 含一個 repo 獨有的 templates/MARKER：sync 真的執行才會出現在 user-level
# （新檔 rsync 必複製，不受 size+mtime 快速比對跳過 VERSION 的測試假象影響）
mk_repo() {
  local home="$1" ver="$2" profile="${3:-REPO}"
  local repo="$home/AI-SOP-Protocol"
  mkdir -p "$repo/.asp/profiles" "$repo/.asp/hooks" "$repo/.asp/config" "$repo/.asp/templates" "$repo/.claude/skills/asp"
  echo "$ver"        > "$repo/.asp/VERSION"
  echo "$profile"    > "$repo/.asp/profiles/global_core.md"
  echo "echo hi"     > "$repo/.asp/hooks/session-audit.sh"
  echo "v: 1"        > "$repo/.asp/config/profile-map.yaml"
  echo "synced-$ver" > "$repo/.asp/templates/MARKER"
  echo "# skill"     > "$repo/.claude/skills/asp/SKILL.md"
}
# sync 是否真的執行：repo 獨有 marker 已出現在 user-level
synced() { [ -f "$1/.claude/asp/templates/MARKER" ]; }

# 建一份已安裝 user-level 於 <home>/.claude/asp，VERSION=<ver>（傳 "" 代表不寫 VERSION 檔）
mk_installed() {
  local home="$1" ver="$2" profile="${3:-OLD}"
  mkdir -p "$home/.claude/asp/profiles" "$home/.claude/skills/asp"
  [ -n "$ver" ] && echo "$ver" > "$home/.claude/asp/VERSION"
  echo "$profile" > "$home/.claude/asp/profiles/global_core.md"
  echo "# skill old" > "$home/.claude/skills/asp/SKILL.md"
}

# scenario <name> <repo_ver> <installed_ver> [extra-env...] -- 建沙箱並跑 asp-sync --yes
scenario() {
  local home="$TEST_DIR/$1" repo_ver="$2" inst_ver="$3"; shift 3
  mkdir -p "$home"
  mk_repo "$home" "$repo_ver"
  mk_installed "$home" "$inst_ver"
  SCEN_HOME="$home"
  SCEN_OUT=$(cd "$home" && HOME="$home" "$@" bash "$SYNC" --yes 2>&1)
  SCEN_RC=$?
}

# ── T1: 降級 + 非互動 → 預設中止，sync 不執行 ──
echo "── T1: 降級非互動預設中止 ──"
scenario t1 "4.0.0" "5.0.0"
[ "$SCEN_RC" -ne 0 ] && pass "降級時 exit 非 0（$SCEN_RC）" || fail "降級竟以 exit 0 結束（無防護）"
grep -qF "降級" <<<"$SCEN_OUT" && pass "輸出含『降級』警告" || fail "輸出未警告降級"
synced "$SCEN_HOME" && fail "降級被中止卻仍同步了（marker 出現）" || pass "sync 未執行（marker 不存在）"

# ── T2: 降級 + ASP_ALLOW_DOWNGRADE=1 → 放行，文案『降級完成』 ──
echo "── T2: ASP_ALLOW_DOWNGRADE=1 放行 ──"
scenario t2 "4.0.0" "5.0.0" env ASP_ALLOW_DOWNGRADE=1
[ "$SCEN_RC" -eq 0 ] && pass "覆寫旗標下 exit 0" || fail "覆寫旗標仍中止（rc=$SCEN_RC）"
grep -qF "降級完成" <<<"$SCEN_OUT" && pass "文案為『降級完成』" || fail "文案非降級完成"
synced "$SCEN_HOME" && pass "sync 已執行（marker 出現）" || fail "覆寫旗標下未實際同步"

# ── T3: 升級 → 正常放行，文案含『升級』 ──
echo "── T3: 升級正常放行 ──"
scenario t3 "5.1.0" "5.0.0"
[ "$SCEN_RC" -eq 0 ] && pass "升級 exit 0" || fail "升級竟被擋（rc=$SCEN_RC）"
grep -qF "升級" <<<"$SCEN_OUT" && pass "文案含『升級』" || fail "升級文案缺失"
! grep -qF "降級" <<<"$SCEN_OUT" && pass "升級不應出現『降級』字樣" || fail "升級誤報降級"
synced "$SCEN_HOME" && pass "sync 已執行（marker 出現）" || fail "升級未實際同步"

# ── T4: 同版本（內容有差）→ 照常同步，無『降級』 ──
echo "── T4: 同版本內容更新 ──"
scenario t4 "5.0.0" "5.0.0"
[ "$SCEN_RC" -eq 0 ] && pass "同版本 exit 0" || fail "同版本被擋（rc=$SCEN_RC）"
! grep -qF "降級" <<<"$SCEN_OUT" && pass "同版本不出現『降級』" || fail "同版本誤報降級"

# ── T5: 非 semver（無已安裝 VERSION 檔）→ 不誤判降級 ──
echo "── T5: 非 semver 不誤判 ──"
scenario t5 "4.0.0" ""    # 無 VERSION → INSTALLED_VERSION = "not installed"
! grep -qF "降級" <<<"$SCEN_OUT" && pass "非 semver 不報降級" || fail "非 semver 誤報降級"
[ "$SCEN_RC" -eq 0 ] && pass "非 semver 正常完成" || fail "非 semver 被擋（rc=$SCEN_RC）"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
