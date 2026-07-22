#!/usr/bin/env bash
# test_plugin_manifest.sh — SPEC-014 (enforcement-first) marketplace plugin 封裝驗證.
# Run: bash tests/test_plugin_manifest.sh
#
# 驗證 repo-root 的 .claude-plugin/marketplace.json + hooks/hooks.json 讓 ASP 可經
# /plugin marketplace add 安裝、且承載現行三 hook（session-audit / ship-gate /
# clean-allow-list）。核心強制力 POC-1 已證零 .asp/ 依賴；本測試只驗封裝正確性
# （well-formed + schema + 引用腳本存在 + experimental/showcase 不入包）。
#
# 對應 SPEC-014 Done-When #1 與 CI-gateable 部分；真 /plugin install 端到端為 human-only（2b）。

set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MKT="$ASP_ROOT/.claude-plugin/marketplace.json"
HOOKS="$ASP_ROOT/hooks/hooks.json"

command -v jq >/dev/null 2>&1 || { echo "jq 未安裝，跳過"; exit 0; }

echo "── marketplace.json ──"
if [ -f "$MKT" ] && jq -e . "$MKT" >/dev/null 2>&1; then
  pass "marketplace.json 存在且為合法 JSON"
else
  fail "marketplace.json 缺失或非合法 JSON"; echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"; exit 1
fi

[ "$(jq -r '.name // empty' "$MKT")" != "" ] && pass "marketplace.name 存在" || fail "marketplace.name 缺"
[ "$(jq -r '.owner.name // empty' "$MKT")" != "" ] && pass "marketplace.owner.name 存在" || fail "marketplace.owner.name 缺"

# 取 asp plugin entry
ENTRY=$(jq -c '.plugins[] | select(.name=="asp")' "$MKT" 2>/dev/null)
[ -n "$ENTRY" ] && pass "plugins[] 含 name=asp 的 entry" || fail "找不到 name=asp 的 plugin entry"

[ "$(jq -r '.source // empty' <<<"$ENTRY")" = "./" ] && pass "asp.source = ./（repo 即 plugin）" || fail "asp.source 非 ./"
[ "$(jq -r '.strict' <<<"$ENTRY")" = "false" ] && pass "asp.strict = false（免 plugin.json）" || fail "asp.strict 非 false"
[ "$(jq -r '.hooks // empty' <<<"$ENTRY")" = "./hooks/hooks.json" ] && pass "asp.hooks 映射 ./hooks/hooks.json" || fail "asp.hooks 未映射 ./hooks/hooks.json"
# skills/commands 映射既有非標準路徑
jq -e '.skills | index("./.claude/skills/asp")' <<<"$ENTRY" >/dev/null 2>&1 && pass "asp.skills 映射 ./.claude/skills/asp" || fail "asp.skills 未映射 ./.claude/skills/asp"
jq -e '.commands | index("./.claude/commands/asp")' <<<"$ENTRY" >/dev/null 2>&1 && pass "asp.commands 映射 ./.claude/commands/asp" || fail "asp.commands 未映射 ./.claude/commands/asp"

# ADR-017：experimental / showcase 不入包
PATHS=$(jq -r '.plugins[] | (.skills // [], .commands // [], .agents // [], .hooks // "") | tostring' "$MKT" 2>/dev/null)
if grep -qE 'experimental|showcase' <<<"$PATHS"; then fail "marketplace 映射了 experimental/showcase（違反 ADR-017）"; else pass "experimental/showcase 不在 plugin 封裝（ADR-017）"; fi

echo "── hooks/hooks.json ──"
if [ -f "$HOOKS" ] && jq -e . "$HOOKS" >/dev/null 2>&1; then
  pass "hooks.json 存在且為合法 JSON"
else
  fail "hooks.json 缺失或非合法 JSON"; echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"; exit 1
fi

jq -e '.hooks.SessionStart' "$HOOKS" >/dev/null 2>&1 && pass "hooks.json 有 SessionStart" || fail "hooks.json 缺 SessionStart"
[ "$(jq -r '.hooks.PreToolUse[0].matcher // empty' "$HOOKS")" = "Bash" ] && pass "PreToolUse matcher = Bash" || fail "PreToolUse matcher 非 Bash"

# 每個 command 用 ${CLAUDE_PLUGIN_ROOT} 且引用的腳本存在於 .asp/hooks/
CMDS=$(jq -r '[.hooks[][].hooks[].command] | .[]' "$HOOKS" 2>/dev/null)
all_ok=1; refs=0
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  refs=$((refs+1))
  grep -q 'CLAUDE_PLUGIN_ROOT' <<<"$cmd" || { fail "command 未用 \${CLAUDE_PLUGIN_ROOT}: $cmd"; all_ok=0; }
  script=$(sed -E 's#.*/([a-zA-Z0-9_-]+\.sh).*#\1#' <<<"$cmd")
  [ -f "$ASP_ROOT/.asp/hooks/$script" ] || { fail "引用的腳本不存在: .asp/hooks/$script"; all_ok=0; }
done <<< "$CMDS"
[ "$refs" -ge 3 ] && pass "hooks.json 引用 ≥3 個 hook 命令（session-audit/ship-gate/clean-allow-list）" || fail "hooks.json 引用命令數 <3（$refs）"
[ "$all_ok" -eq 1 ] && pass "所有 hook command 用 \${CLAUDE_PLUGIN_ROOT} 且引用腳本皆存在" || true

# 綁定 script → event by name（防止未來把錯的腳本接到錯的事件仍通過）
SS_SCRIPTS=$(jq -r '[.hooks.SessionStart[].hooks[].command] | .[]' "$HOOKS" 2>/dev/null | sed -E 's#.*/([a-zA-Z0-9_-]+\.sh).*#\1#' | sort | tr '\n' ',')
PT_SCRIPT=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$HOOKS" 2>/dev/null | sed -E 's#.*/([a-zA-Z0-9_-]+\.sh).*#\1#')
[ "$SS_SCRIPTS" = "clean-allow-list.sh,session-audit.sh," ] && pass "SessionStart 綁定 = {clean-allow-list, session-audit}" || fail "SessionStart 腳本綁定不符：$SS_SCRIPTS"
[ "$PT_SCRIPT" = "pretooluse-ship-gate.sh" ] && pass "PreToolUse 綁定 = ship-gate" || fail "PreToolUse 腳本綁定不符：$PT_SCRIPT"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
