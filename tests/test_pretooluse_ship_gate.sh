#!/usr/bin/env bash
# test_pretooluse_ship_gate.sh — SPEC-013 / ADR-020 PreToolUse commit 閘
#
# hook 讀 stdin JSON（{tool_name, tool_input.command, cwd}），偵測指令位置的
# git commit；無測試痕跡（.asp-test-result.json passed 且 mtime ≥ .git/index）
# 則輸出 permissionDecision:deny（FC-002 方式 A）。escape hatch / fail-open 防死鎖。
# Run: bash tests/test_pretooluse_ship_gate.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ASP_ROOT/.asp/hooks/pretooluse-ship-gate.sh"
mk_test_dir
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 不存在"; exit 0; }

PROJ="$TEST_DIR/proj"; mkdir -p "$PROJ/.git"
METRICS="$TEST_DIR/rule-hits.jsonl"

run_hook(){ # $1=command ; env ASP_SHIP_OK optional
  printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":"%s"}' \
    "$(printf '%s' "$1" | jq -Rs .)" "$PROJ" \
    | CLAUDE_PROJECT_DIR="$PROJ" ASP_METRICS_FILE="$METRICS" ASP_SHIP_OK="${ASP_SHIP_OK:-}" bash "$HOOK"
}
denied(){ grep -q '"permissionDecision":[[:space:]]*"deny"' <<<"$1"; }
metric_has(){ grep -q "\"rule_id\":\"SHIP-GATE\".*\"action\":\"$1\"" "$METRICS" 2>/dev/null; }

fresh_ship(){ rm -f "$METRICS"; touch "$PROJ/.git/index"; sleep 1; echo '{"passed":true}' > "$PROJ/.asp-test-result.json"; }
stale_ship(){ rm -f "$METRICS"; echo '{"passed":true}' > "$PROJ/.asp-test-result.json"; sleep 1; touch "$PROJ/.git/index"; }
no_ship(){ rm -f "$METRICS" "$PROJ/.asp-test-result.json"; touch "$PROJ/.git/index"; }

echo ""; echo "P1: 非 commit（git status）→ 放行（無 deny）"
no_ship; OUT=$(run_hook "git status")
denied "$OUT" && fail "git status 被誤擋" || pass "非 commit 放行"

echo ""; echo "P2: git commit + 新鮮 ship → 放行 + metric pass"
fresh_ship; OUT=$(run_hook "git commit -m test")
denied "$OUT" && fail "新鮮 ship 被誤擋" || pass "新鮮 ship 放行"
metric_has pass && pass "metric SHIP-GATE pass 寫入" || fail "未寫 pass metric"

echo ""; echo "P3: escape hatch ASP_SHIP_OK=1 + 無痕跡 → 放行 + metric bypass"
no_ship; OUT=$(ASP_SHIP_OK=1 run_hook "git commit -m x")
denied "$OUT" && fail "escape hatch 仍被擋" || pass "escape hatch 放行"
metric_has bypass && pass "metric SHIP-GATE bypass 寫入" || fail "未寫 bypass metric"

echo ""; echo "N1: git commit + 無 ship 痕跡 → deny + metric block"
no_ship; OUT=$(run_hook "git commit -m forgot")
denied "$OUT" && pass "無痕跡 commit 被擋" || fail "無痕跡 commit 未擋"
metric_has block && pass "metric SHIP-GATE block 寫入" || fail "未寫 block metric"

echo ""; echo "N2: git commit + stale ship（index 比 test-result 新）→ deny"
stale_ship; OUT=$(run_hook "git commit -m stale")
denied "$OUT" && pass "stale ship 被擋" || fail "stale ship 未擋"

echo ""; echo "N3: 複合 command（git add && git commit）+ 無痕跡 → deny"
no_ship; OUT=$(run_hook "git add . && git commit -m combo")
denied "$OUT" && pass "複合 command 偵測到 commit 並擋" || fail "複合 command 漏擋"

echo ""; echo "F5: git log --grep=\"git commit\" → 放行（不誤判字串內 git commit）"
no_ship; OUT=$(run_hook 'git log --grep="git commit"')
denied "$OUT" && fail "誤判字串內 git commit" || pass "字串內 git commit 不誤判"

echo ""; echo "B2: 無 staged（.git/index 不存在）+ ship passed → 放行"
rm -f "$METRICS" "$PROJ/.git/index"; echo '{"passed":true}' > "$PROJ/.asp-test-result.json"
OUT=$(run_hook "git commit -m nostage")
denied "$OUT" && fail "無 staged + passed 被誤擋" || pass "無 staged + passed 放行"

echo ""; echo "B1: hook 對 amend 用 passed-only（amend index mtime 不可靠）→ 放行"
rm -f "$METRICS"; touch "$PROJ/.git/index"; sleep 1; echo '{"passed":true}' > "$PROJ/.asp-test-result.json"; sleep 1; touch "$PROJ/.git/index"
OUT=$(run_hook "git commit --amend --no-edit")
denied "$OUT" && fail "amend + passed 被誤擋" || pass "amend 退回 passed-only 放行"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
