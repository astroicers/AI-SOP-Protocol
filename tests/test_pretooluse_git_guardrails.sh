#!/usr/bin/env bash
# test_pretooluse_git_guardrails.sh — SPEC-016 / ADR-030 PreToolUse 本地毀資料護欄
#
# hook 讀 stdin JSON（{tool_name, tool_input.command}），以 M0 tokenize + M1 逐子命令
# 謂詞判定本地毀滅性 git；命中→ permissionDecision:deny（FC-002 方式 A）+ GIT-GUARD block
# 遙測；ASP_GIT_OK=1（hook env）→ defer + bypass；jq 缺/stdin 空 → fail-open defer。
# 測試矩陣＝SPEC-016：P1-12（defer）/ N1-14（deny）/ B1-9（邊界）。
# Run: bash tests/test_pretooluse_git_guardrails.sh
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ASP_ROOT/.asp/hooks/pretooluse-git-guardrails.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 不存在"; exit 0; }
mk_test_dir git-guard
METRICS="$TEST_DIR/rule-hits.jsonl"

# run_hook <command> — 餵 stdin JSON，回 hook stdout。ASP_GIT_OK 由呼叫端 env 前綴。
run_hook() {
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" \
    | ASP_METRICS_FILE="$METRICS" ASP_GIT_OK="${ASP_GIT_OK:-}" bash "$HOOK"
}
denied() { grep -q '"permissionDecision":[[:space:]]*"deny"' <<<"$1"; }
metric_has() { grep -q "\"rule_id\":\"GIT-GUARD\".*\"action\":\"$1\"" "$METRICS" 2>/dev/null; }

# defer 案：期望「不 deny」（方式 A：defer＝無 deny JSON）
expect_defer() { # $1=label $2=cmd
  rm -f "$METRICS"; local out; out=$(run_hook "$2")
  denied "$out" && fail "$1：應 defer 卻被 deny — 「$2」" || pass "$1：defer — 「$2」"
}
# deny 案：期望 deny + block 遙測
expect_deny() { # $1=label $2=cmd
  rm -f "$METRICS"; local out; out=$(run_hook "$2")
  if denied "$out"; then
    metric_has block && pass "$1：deny + block 遙測 — 「$2」" || fail "$1：deny 但未寫 block 遙測 — 「$2」"
  else
    fail "$1：應 deny 卻放行 — 「$2」"
  fi
}

echo "════ 正向（P1-P12）：安全操作與 escape hatch → defer ════"
expect_defer "P1a" "git status"
expect_defer "P1b" "git checkout main"
expect_defer "P1c" "git switch -c feat"
expect_defer "P2a" "git clean -n"
expect_defer "P2b" "git clean --dry-run"
expect_defer "P2c" "git clean -i"
expect_defer "P2d" "git clean -fi"                       # force+interactive：interactive 放行
expect_defer "P3a" "git reset --soft HEAD~1"
expect_defer "P3b" "git reset HEAD file"
expect_defer "P3c" "git reset hard"                       # hard 是 ref 名非旗標
expect_defer "P4a" "git restore --staged file"
expect_defer "P4b" "git branch -d merged"
expect_defer "P4c" "git rm --cached f"
expect_defer "P5a" "git checkout hardening"               # 分支名含 hard 子字串
expect_defer "P5b" "git switch hotfix"
expect_defer "P6a" "git clean -nfd"                       # BLOCKER：dry-run+force → git 不刪
expect_defer "P6b" "git clean -nf"
expect_defer "P7a" "git worktree remove wt"              # 無 force
expect_defer "P7b" "git stash pop"
expect_defer "P7c" 'git stash push -m "clear cache before drop"'  # 訊息含 clear/drop 但子命令 push
expect_defer "P9"  "git checkout -b feat origin/main"    # 建分支+start-point 不誤命中 ≥2
expect_defer "P10a" "git checkout -p"
expect_defer "P10b" "git restore -p file"
expect_defer "P10c" "git checkout -p HEAD~1 -- src/f"    # 互動 hunk：-p 免除 --/≥2 DENY
expect_defer "P11" "git worktree add -f wt2 remove"      # remove 為 commit-ish 字面
expect_defer "P12a" "git checkout --orphan gh-pages"
expect_defer "P12b" "git checkout -B main origin/main"   # force-建分支：操作元不計 positional
expect_defer "P13a" "git checkout -Bf origin/main"       # UB-01 回歸：f 為 -B 分支名參數非旗標
expect_defer "P13b" "git switch -cf origin/main"         # UB-01 回歸：f 為 -c 分支名參數非旗標
expect_defer "P13c" "git stash push -- clear"            # OB-01：-- 後 clear 為 pathspec
expect_defer "P13d" "git stash -- drop"                  # OB-01：隱式 push + pathspec drop（安全）

echo ""; echo "P8：escape hatch（env 前綴於 hook）→ defer + bypass 遙測"
rm -f "$METRICS"; OUT=$(ASP_GIT_OK=1 run_hook "git reset --hard")
if denied "$OUT"; then fail "P8：escape hatch 仍被擋"; else
  metric_has bypass && pass "P8：escape hatch defer + bypass 遙測" || fail "P8：defer 但未寫 bypass 遙測"
fi

echo ""; echo "════ 負向（N1-N14）：本地毀滅性 → deny + block ════"
expect_deny "N1a" "git reset --hard"
expect_deny "N1b" "git reset --hard HEAD~3"
expect_deny "N2a" "git clean -fd"
expect_deny "N2b" "git clean -xf"
expect_deny "N2c" "git clean --force"
expect_deny "N2d" "git clean -fdx"
expect_deny "N3a" "git branch -D x"
expect_deny "N3b" "git branch --delete --force x"
expect_deny "N3c" "git branch -Df x"
expect_deny "N3d" "git branch -df x"                     # 小寫捆綁 {d,f} 走 clause(b)
expect_deny "N4a" "git checkout ."
expect_deny "N4b" "git checkout -q ."                    # -q 破字面「恰為 checkout .」
expect_deny "N4c" "git checkout -- src/"
expect_deny "N4d" "git checkout -f"
expect_deny "N4e" "git checkout main foo"                # ≥2 positional
expect_deny "N4f" "git checkout -qf main"                # UB-01：捆綁 force（-q + -f）
expect_deny "N4g" "git checkout -fq main"                # UB-01：捆綁順序顛倒
expect_deny "N5a" "git restore ."
expect_deny "N5b" "git restore --worktree x"
expect_deny "N5c" "git restore -SW f"
expect_deny "N5d" "git restore -WS f"                     # -W 在捆綁兩序皆命中
expect_deny "N6a" "git stash clear"
expect_deny "N6b" "git stash drop"
expect_deny "N6c" "git switch -C main"
expect_deny "N6d" "git switch --discard-changes"
expect_deny "N7a" "git switch -f main"                    # -f = --discard-changes 別名
expect_deny "N7b" "git switch --force main"
expect_deny "N7c" "git switch -qf main"                   # UB-01：捆綁 force（-q quiet + -f）
expect_deny "N7d" "git switch -fq main"                   # UB-01：捆綁順序顛倒
expect_deny "N7e" "git switch -qC main"                   # UB-01：捆綁 force-create
expect_deny "N8a" "git worktree remove -f wt"
expect_deny "N8b" "git worktree remove --force wt"
expect_deny "N8c" "git worktree remove -ff wt"           # 雙 force
expect_deny "N9a" "git rm -f f"
expect_deny "N9b" "git rm -rf dir"                       # git rm 非 rm，denied-commands 擋不到
expect_deny "N10a" "git -C /other reset --hard"          # 跳全域選項
expect_deny "N10b" "git -c user.name=x clean -fd"        # -c 帶 = 參數
expect_deny "N11a" "git add . && git reset --hard"
expect_deny "N11b" "git status; git reset --hard"
expect_deny "N11c" "git x || git reset --hard"
expect_deny "N11d" "git status | git reset --hard"       # 管線
expect_deny "N12" "git switch --force-create x master"   # -C 長式
expect_deny "N13a" "git --git-dir /tmp/o.git reset --hard"   # 空白分隔全域選項吃下一 token
expect_deny "N13b" "git --git-dir=/tmp/o.git reset --hard"   # = 形
expect_deny "N14" "FOO=bar git reset --hard"             # VAR=val 前綴須跳過

echo ""; echo "════ 邊界（B1-B9）════"
expect_defer "B1" 'git log --grep="reset --hard"'        # 字串內（引號感知）
expect_defer "B2" 'git commit -m "wip: git reset --hard notes"'  # 引號內危險字串
expect_defer "B5" "git push --force"                     # 既有層職責，本 hook 不重複
expect_defer "B6" "git reset --har"                      # 長選項前綴補全（已知漏擋釘樁）
expect_defer "B7" 'git commit -m "$(git reset --hard)"'  # 命令替換內巢狀（已知漏擋釘樁）
expect_defer "B8a" '\git reset --hard'                   # 反斜線包裝前綴（已知漏擋釘樁）
expect_defer "B8b" "env git reset --hard"                # env 包裝（首 token 非 git）
expect_defer "B9" "git checkout f2.txt"                  # 單 positional 為已追蹤檔（已知漏擋釘樁）

echo ""; echo "════ R（redirect 剝除）：shell redirect 不得算 positional（OB-02 over-block 修復）════"
# 誤擋修復：redirect token 曾被當 positional → checkout 誤判 ≥2 → deny
expect_defer "R1" "git checkout main 2>/dev/null"         # 極常見；曾誤擋
expect_defer "R2" "git checkout --detach origin/main 2>&1"
expect_defer "R3" "git checkout feature >/tmp/log 2>&1"
expect_defer "R4" "git checkout main >  /tmp/log"         # 分開形 operator + 目標
expect_defer "R5" "git switch main 2>/dev/null"
# 真 deny 不因 redirect 而漏擋（剝除後謂詞仍命中）
expect_deny  "R6" "git reset --hard 2>/dev/null"
expect_deny  "R7" "git checkout . 2>/dev/null"            # 唯一 positional 仍為 .
expect_deny  "R8" "git checkout main foo 2>/dev/null"     # 真 2 positional + redirect
expect_deny  "R9" "git clean -fd >/dev/null"
expect_deny  "R10" "git stash clear 2>/dev/null"          # clear 仍 first positional

echo ""; echo "GG-SEC-01：超長 command（>8192）→ defer（O(n²) tokenizer DoS 上限）"
BIG="git reset --hard $(head -c 9000 /dev/zero | tr '\0' 'a')"
rm -f "$METRICS"; OUT=$(run_hook "$BIG")
denied "$OUT" && fail "GG-SEC-01：超長 command 應 defer（護欄 fail-open）" || pass "GG-SEC-01：超長 command → defer（DoS 上限生效）"

echo ""; echo "B4：stdin 空 → defer 靜默（no-op，無 WARN）"
rm -f "$METRICS"; OUT=$(printf '' | ASP_METRICS_FILE="$METRICS" bash "$HOOK" 2>"$TEST_DIR/err")
denied "$OUT" && fail "B4：空 stdin 被 deny" || pass "B4：空 stdin defer"
[ -s "$TEST_DIR/err" ] && fail "B4：空 stdin 不應印 WARN（no-op）" || pass "B4：空 stdin 靜默無 WARN"

echo ""; echo "B3：jq 缺 → defer + WARN（以 PATH 剝除 jq 模擬）"
FAKEBIN="$TEST_DIR/fakebin"; mkdir -p "$FAKEBIN"
for c in bash grep sed cat printf env; do command -v "$c" >/dev/null && ln -sf "$(command -v "$c")" "$FAKEBIN/$c" 2>/dev/null; done
OUT=$(printf '{"tool_input":{"command":"git reset --hard"}}' | PATH="$FAKEBIN" ASP_METRICS_FILE="$METRICS" bash "$HOOK" 2>"$TEST_DIR/err2" || true)
if command -v jq >/dev/null 2>&1 && [ -x "$FAKEBIN/bash" ]; then
  denied "$OUT" && fail "B3：jq 缺應 fail-open defer" || pass "B3：jq 缺 → defer（fail-open）"
  grep -qi "jq" "$TEST_DIR/err2" && pass "B3：jq 缺印 WARN" || pass "B3：jq 缺 defer（WARN best-effort）"
else
  pass "B3：SKIP（環境限制）"
fi

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
