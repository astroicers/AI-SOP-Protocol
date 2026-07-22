#!/usr/bin/env bash
# test_plugin_env_harness.sh — SPEC-014 Done-When 2a（CI-gateable behavioral harness）.
# Run: bash tests/test_plugin_env_harness.sh
#
# 以 plugin 會設的 env（CLAUDE_PLUGIN_ROOT + CLAUDE_PROJECT_DIR）跑**真** .asp/hooks/session-audit.sh，
# 對一個**無 .asp/** 的 scratch 專案（純 plugin 使用者形狀）驗證 enforcement-first 核心：
#   P1/B1: Draft ADR → Bash(git commit *) 注入 <proj>/.claude/settings.local.json（零 .asp/ 依賴）
#   B2   : tracked settings.json sha256 不變（ADR-011 不變式）
#   S3   : Draft 解除 → deny 自清
# 對應 SPEC-014 §Test Matrix P1/B1/B2 + Gherkin S1/S3。真 /plugin install 端到端仍為 human-only（2b）。

set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ASP_ROOT/.asp/hooks/session-audit.sh"
command -v jq >/dev/null 2>&1 || { echo "jq 未安裝，跳過"; exit 0; }

mk_test_dir plugin-env-harness
PROJ="$TEST_DIR"
mkdir -p "$PROJ/docs/adr" "$PROJ/.claude"   # 注意：專案內**無** .asp/（純 plugin 形狀）
printf '{\n  "permissions": { "deny": ["Bash(rm -rf /)"] }\n}\n' > "$PROJ/.claude/settings.json"
BEFORE=$(sha256sum "$PROJ/.claude/settings.json" | awk '{print $1}')

run_audit()      { CLAUDE_PLUGIN_ROOT="$ASP_ROOT" CLAUDE_PROJECT_DIR="$PROJ" bash "$AUDIT" >/dev/null 2>&1; }
local_deny_has() { jq -e --arg d "$1" '.permissions.deny | index($d)' "$PROJ/.claude/settings.local.json" >/dev/null 2>&1; }

echo "── P1/B1: plugin-env + 專案無 .asp/ → Draft 擋 commit ──"
cat > "$PROJ/docs/adr/ADR-999-fixture.md" <<'EOF'
# [ADR-999]: fixture
| 欄位 | 內容 |
|------|------|
| **狀態** | Draft |
EOF
run_audit
local_deny_has "Bash(git commit *)" \
  && pass "P1/B1: plugin-env + 無 .asp/ → deny 注入 settings.local.json（核心零 .asp/ 依賴）" \
  || fail "P1/B1: deny 未注入"

echo "── B2: tracked settings.json 不變 ──"
AFTER=$(sha256sum "$PROJ/.claude/settings.json" | awk '{print $1}')
[ "$BEFORE" = "$AFTER" ] && pass "B2: tracked settings.json sha256 不變（ADR-011 不變式）" || fail "B2: settings.json 被改動"

echo "── S3: Draft 解除 → deny 自清 ──"
sed -i 's/\*\*狀態\*\* | Draft/**狀態** | Accepted/' "$PROJ/docs/adr/ADR-999-fixture.md"
run_audit
local_deny_has "Bash(git commit *)" && fail "S3: Draft 解除後 deny 未自清" || pass "S3: Draft 解除 → deny 自清為 []"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
