#!/usr/bin/env bash
# tests/test_worktree_resolve.sh — SPEC-017：worktree 解析 lib + session-audit worktree 感知 advisory.
# Run: bash tests/test_worktree_resolve.sh
#
# 覆蓋 SPEC-017 測試矩陣：
#   T1-T4   asp_resolve_worktree 單元（.asp/scripts/lib/worktree.sh，DP1=b）
#   T7/T7b  A18 autopilot-state worktree 感知 + fail-open SUPPRESS（含 Observability INFO 行）
#   T5b     A5 required-files 讀 worktree
#   T8b     A8 tech-debt 讀 worktree
#   T9b     A1/.ai_profile 讀 worktree
#   T-INV2  與 ship-gate 解析 parity（INV-2：靜態單一真相 + 行為 black-box）
#   T9/T10/T11 靜態不變式（PROJECT_DIR 單一定義 / lib 入 Iron Rule A 清單 / dead SETTINGS_FILE 已除）
#
# Harness 鐵則（SPEC-017 review #1）：模擬 worktree session 一律餵 stdin JSON
# {"cwd":"<worktree>"} 且 CLAUDE_PROJECT_DIR=<主樹>（鏡像 test_shipgate_worktree.sh run_gate）。
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ASP_ROOT/.asp/hooks/session-audit.sh"
GATE="$ASP_ROOT/.asp/hooks/pretooluse-ship-gate.sh"
LIB="$ASP_ROOT/.asp/scripts/lib/worktree.sh"
command -v jq  >/dev/null 2>&1 || { echo "jq 缺，跳過";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "git 缺，跳過"; exit 0; }

mk_test_dir worktree-resolve
MAIN="$TEST_DIR/main"; WT="$TEST_DIR/wt"; UNREL="$TEST_DIR/unrelated"; PLAIN="$TEST_DIR/plain"
mkdir -p "$MAIN" "$PLAIN"
git -C "$MAIN" init -q
git -C "$MAIN" config user.email t@t; git -C "$MAIN" config user.name t
echo r > "$MAIN/README.md"; echo c > "$MAIN/CHANGELOG.md"; printf 'test:\n\ttrue\n' > "$MAIN/Makefile"
git -C "$MAIN" add -A
git -C "$MAIN" -c commit.gpgsign=false commit -qm init
git -C "$MAIN" worktree add -q "$WT" -b feat
mkdir -p "$UNREL"; git -C "$UNREL" init -q
git -C "$UNREL" config user.email t@t; git -C "$UNREL" config user.name t
echo u > "$UNREL/u"; git -C "$UNREL" add u
git -C "$UNREL" -c commit.gpgsign=false commit -qm init

# helper 呼叫：$1=anchor（CLAUDE_PROJECT_DIR）、$2=cwd 訊號
resolve() { ( export CLAUDE_PROJECT_DIR="$1"; . "$LIB" 2>/dev/null || exit 9; asp_resolve_worktree "$2" ); }

# audit 呼叫（stdin-piping harness）：$1=stdin.cwd、$2=CLAUDE_PROJECT_DIR
run_audit_wt() {
  printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1" \
    | CLAUDE_PROJECT_DIR="$2" bash "$AUDIT" 2>/dev/null
}

# ship-gate 呼叫（black-box）：$1=cwd、$2=CLAUDE_PROJECT_DIR
run_gate() {
  local payload; payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$1")
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$2" bash "$GATE" 2>/dev/null
}

echo "── T1-T4：asp_resolve_worktree 單元 ──"
if [ ! -f "$LIB" ]; then
  fail "lib 不存在：$LIB（DP1=b 交付物）"
else
  pass "lib 存在"
fi
R=$(resolve "$MAIN" "$WT" || true)
[ "$R" = "$WT" ] && pass "T1 同 superproject worktree → worktree top" || fail "T1 期望 $WT 得 '$R'"
R=$(resolve "$MAIN" "$UNREL" || true)
[ "$R" = "$MAIN" ] && pass "T2 無關 repo → anchor（血緣守衛擋 planted）" || fail "T2 期望 $MAIN 得 '$R'"
mkdir -p "$MAIN/sub"
R=$(resolve "$MAIN" "$MAIN/sub" || true)
[ "$R" = "$MAIN" ] && pass "T3 主樹子目錄 → anchor（top==anchor 短路）" || fail "T3 期望 $MAIN 得 '$R'"
R=$(resolve "$MAIN" "$PLAIN" || true)
[ "$R" = "$MAIN" ] && pass "T4a 非 git cwd → anchor" || fail "T4a 期望 $MAIN 得 '$R'"
R=$(resolve "$MAIN/" "$MAIN" || true)   # SH-01：anchor 帶尾斜線不得誤判 worktree
[ "$R" = "$MAIN" ] && pass "T3b 尾斜線 anchor + cwd=主樹 → anchor（正規化，SH-01）" || fail "T3b 期望 $MAIN 得 '$R'"
run_audit_wt "$MAIN" "$MAIN/" | grep -q "A19.1" \
  && pass "T3c 尾斜線 anchor 主樹 session → A19.1 警告不被誤抑制（SH-01）" \
  || fail "T3c 尾斜線 anchor 被誤判 worktree → A19.1 被抑制"
BM="$TEST_DIR/bm"; mkdir -p "$BM"; git -C "$BM" init -q
git -C "$BM" config user.email t@t; git -C "$BM" config user.name t
echo x > "$BM/x"; git -C "$BM" add x; git -C "$BM" -c commit.gpgsign=false commit -qm i
git -C "$BM" worktree add -q "$TEST_DIR/bw" -b bx
mv "$BM" "$TEST_DIR/bm-moved"   # 打斷 gitdir 連結 → 損壞 worktree
R=$(resolve "$MAIN" "$TEST_DIR/bw" || true)
[ "$R" = "$MAIN" ] && pass "T4b 損壞 worktree → anchor，不 crash" || fail "T4b 期望 $MAIN 得 '$R'"

echo "── T7/T7b：A18 worktree 感知 + fail-open SUPPRESS ──"
echo '{}' > "$WT/.asp-autopilot-state.json"
OUT=$(run_audit_wt "$WT" "$MAIN")
grep -q "A18.1" <<<"$OUT" && pass "T7 stdin.cwd=worktree（有 state）→ 報 resume（讀對 worktree）" || fail "T7 未報 A18.1（讀了主樹＝讀錯目錄）"
rm -f "$WT/.asp-autopilot-state.json"
echo '{}' > "$MAIN/.asp-autopilot-state.json"       # 主樹殘留他 session 的 state
OUT=$(run_audit_wt "$UNREL" "$MAIN")                # cwd=無關 repo → 解析歧義/退錨
grep -q "A18.1" <<<"$OUT" && fail "T7b 歧義退錨竟讀主樹殘留 state（誤報 resume）" || pass "T7b 歧義/退錨 + 主樹殘留 state → 不報 resume（SUPPRESS）"
grep -q "A18 suppressed" <<<"$OUT" && pass "T7b-obs suppress INFO 行存在（Observability D4-1）" || fail "T7b-obs 缺 suppress INFO 行（無法區分 suppress vs 沒 state）"
rm -f "$MAIN/.asp-autopilot-state.json"

echo "── T5b：A5 required-files 讀 worktree ──"
rm -f "$WT/README.md"
OUT=$(run_audit_wt "$WT" "$MAIN")
grep -q "A5:.*README.md" <<<"$OUT" && pass "T5b worktree 缺 README → 依 worktree 判 MISSING" || fail "T5b 未依 worktree 判（讀了主樹的 README）"
git -C "$WT" checkout -q -- README.md 2>/dev/null || echo r > "$WT/README.md"

echo "── T8b：A8 tech-debt 讀 worktree ──"
# 拆開 "DUE:" 避免本測試檔自身被 A8 掃描誤判為真債（比照 test_tech_debt_scan_exclusions.sh:34）
printf 'tech-debt: demo HIGH %s 2020-01-01\n' "DUE:" > "$WT/debt-note.md"
OUT=$(run_audit_wt "$WT" "$MAIN")
grep -q "A8.3" <<<"$OUT" && pass "T8b worktree overdue debt → A8.3（讀對 worktree）" || fail "T8b 未報 A8.3（讀了主樹）"
rm -f "$WT/debt-note.md"

echo "── T9b：A1/.ai_profile 讀 worktree ──"
printf 'type: system\n' > "$WT/.ai_profile"
OUT=$(run_audit_wt "$WT" "$MAIN")
grep -q "A1: .ai_profile 不存在" <<<"$OUT" && fail "T9b worktree 有 .ai_profile 仍誤報不存在（讀了主樹）" || pass "T9b 依 worktree 判 profile 存在"
rm -f "$WT/.ai_profile"

echo "── T-INV2：與 ship-gate 解析 parity（INV-2）──"
grep -q 'scripts/lib/worktree.sh' "$GATE" \
  && pass "T-INV2s ship-gate source 共用 lib（DP1=b 單一真相）" \
  || fail "T-INV2s ship-gate 未 source 共用 lib"
n=$(grep -c 'rev-parse --git-common-dir' "$GATE" || true)
[ "$n" = "0" ] \
  && pass "T-INV2s2 ship-gate 無第二份 _abs_common_dir 真實作（防漂移）" \
  || fail "T-INV2s2 ship-gate 仍有 $n 處自帶 git-common-dir 實作（雙真相漂移風險）"
# 行為 parity：helper 解析 vs ship-gate 實際採用的 PROJ（black-box：fresh/stale 痕跡觀測）
echo '{"passed":true}' > "$MAIN/.asp-test-result.json"; sleep 1; echo z1 > "$MAIN/z1"; git -C "$MAIN" add z1   # 主樹 stale
echo p1 > "$WT/p1"; git -C "$WT" add p1; sleep 1; echo '{"passed":true}' > "$WT/.asp-test-result.json"        # worktree fresh
R=$(resolve "$MAIN" "$WT" || true)
if [ "$R" = "$WT" ] && ! run_gate "$WT" "$MAIN" | grep -q '"deny"'; then
  pass "T-INV2a cwd=worktree：helper=WT 且 ship-gate 讀 WT（fresh 放行）→ 一致"
else
  fail "T-INV2a 分歧：helper='$R'（期望 $WT）或 ship-gate 誤用主樹 stale 而擋"
fi
echo '{"passed":true}' > "$UNREL/.asp-test-result.json"   # planted fresh 痕跡
R=$(resolve "$MAIN" "$UNREL" || true)
if [ "$R" = "$MAIN" ] && run_gate "$UNREL" "$MAIN" | grep -q '"deny"'; then
  pass "T-INV2b cwd=無關 repo：helper=anchor 且 ship-gate 守 anchor（擋 planted）→ 一致"
else
  fail "T-INV2b 分歧：helper='$R'（期望 $MAIN）或 ship-gate 信了 planted 痕跡"
fi
R=$(resolve "$MAIN" "$MAIN/sub" || true)
if [ "$R" = "$MAIN" ] && run_gate "$MAIN/sub" "$MAIN" | grep -q '"deny"'; then
  pass "T-INV2c cwd=主樹子目錄：兩者皆 anchor（主樹 stale 擋）→ 一致"
else
  fail "T-INV2c 分歧：helper='$R'（期望 $MAIN）或 ship-gate 未守 anchor"
fi

echo "── T9/T10/T11：靜態不變式 ──"
n=$(grep -c 'PROJECT_DIR=' "$AUDIT" || true)
[ "$n" = "1" ] && pass "T9 PROJECT_DIR= 僅一處（檔首定義區，未全域改寫）" || fail "T9 PROJECT_DIR= 出現 $n 處（期望 1）"
grep -E 'for CRITICAL_FILE in' "$AUDIT" | grep -q 'scripts/lib/worktree.sh' \
  && pass "T10 lib 已納 CRITICAL_FILE 清單（Iron Rule A hash 保護）" \
  || fail "T10 lib 未納 Iron Rule A CRITICAL_FILE 清單"
n=$(grep -cE '(^|[^A-Z_])SETTINGS_FILE' "$AUDIT" || true)
[ "$n" = "0" ] && pass "T11 dead SETTINGS_FILE 已移除（LOCAL_SETTINGS_FILE 不受影響）" || fail "T11 SETTINGS_FILE 仍有 $n 處（期望 0）"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
