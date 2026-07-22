#!/usr/bin/env bash
# ADR-021 POC-1 — local simulation (no /plugin install needed).
# Runs the BUNDLED session-audit.sh with the env a Claude Code plugin hook receives
# (${CLAUDE_PLUGIN_ROOT} + ${CLAUDE_PROJECT_DIR}, both guaranteed per FC-006) against a
# throwaway project containing a Draft ADR, and asserts:
#   (1) the plugin-bundled hook writes the git-commit deny into <project>/.claude/settings.local.json
#   (2) tracked <project>/.claude/settings.json is never touched
# This proves the script behaves identically whether wired via .claude/settings.json or a plugin.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$HERE/asp-hook-poc"            # value ${CLAUDE_PLUGIN_ROOT} resolves to at runtime
AUDIT="$PLUGIN_ROOT/hooks/session-audit.sh" # the BUNDLED copy inside the plugin

PROJ="$(mktemp -d /tmp/adr021-poc1.XXXXXX)"
mkdir -p "$PROJ/docs/adr" "$PROJ/.claude"
printf '{\n  "permissions": { "deny": ["Bash(rm -rf /)"] }\n}\n' > "$PROJ/.claude/settings.json"
BEFORE="$(sha256sum "$PROJ/.claude/settings.json" | awk '{print $1}')"
cat > "$PROJ/docs/adr/ADR-999-poc-fixture.md" <<'EOF'
# [ADR-999]: POC fixture
| 欄位 | 內容 |
|------|------|
| **狀態** | Draft |
EOF

echo "### plugin-invoked SessionStart simulation ###"
echo "CLAUDE_PLUGIN_ROOT = $PLUGIN_ROOT"
echo "CLAUDE_PROJECT_DIR = $PROJ   (guaranteed for plugin hooks — FC-006 #1)"
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$PROJ" bash "$AUDIT" >/dev/null 2>&1

echo
echo "[settings.local.json written by the BUNDLED hook]"
cat "$PROJ/.claude/settings.local.json" 2>/dev/null
echo "[deny contains the commit pattern?]"
if jq -e '.permissions.deny | index("Bash(git commit *)")' "$PROJ/.claude/settings.local.json" >/dev/null 2>&1; then
  echo "  PASS — plugin-bundled hook wrote the ASP L2 deny into <project>/.claude/settings.local.json"
else
  echo "  FAIL — deny not written"
fi
AFTER="$(sha256sum "$PROJ/.claude/settings.json" | awk '{print $1}')"
[ "$BEFORE" = "$AFTER" ] && echo "[tracked settings.json] PASS — UNCHANGED" || echo "[tracked settings.json] FAIL — CHANGED"

rm -rf "$PROJ"
echo "(scratch removed)"
