#!/usr/bin/env bash
# scope-guard.sh — SPEC-004 N2: Worker runtime scope violation interceptor
#
# Called as a PreToolUse hook (or directly by the worker) before any Write/Edit
# tool executes, to enforce scope.allow / scope.forbid from the TASK manifest.
#
# Usage:
#   scope-guard.sh <file_path>
#
# Environment:
#   ASP_AUDIT_ROOT     — absolute path to the main repo (Iron Rule B)
#   ASP_TASK_MANIFEST  — path to the current task's YAML manifest
#
# Exit codes:
#   0  allowed (path is within scope.allow and not in scope.forbid)
#   2  scope violation (path in forbid, or outside allow) — task must abort
#
# Behaviour when manifest missing / unreadable:
#   Fail-open (exit 0) — guard only enforces when manifest is present.
#   Non-multi-agent sessions have no manifest → no restriction.

set -eu

FILE_PATH="${1:-}"
MANIFEST="${ASP_TASK_MANIFEST:-}"
AUDIT_ROOT="${ASP_AUDIT_ROOT:-}"

BYPASS_LOG="${AUDIT_ROOT}/.asp-bypass-log.ndjson"

# ── Fail-open guard ──────────────────────────────────────────────────────────
# If no manifest is provided or it doesn't exist, this is not a multi-agent
# session — allow unconditionally.
if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  exit 0
fi

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# ── Parse manifest fields ────────────────────────────────────────────────────
# Extract task_id and agent (single-line fields)
TASK_ID=$(grep -E '^task_id:' "$MANIFEST" | head -1 | sed 's/^task_id:[[:space:]]*//' | tr -d '"')
AGENT=$(grep -E '^agent:' "$MANIFEST" | head -1 | sed 's/^agent:[[:space:]]*//' | tr -d '"')

# Extract scope.allow and scope.forbid (inline list format: [a, b, c])
ALLOW_LINE=$(grep -A5 '^scope:' "$MANIFEST" | grep 'allow:' | head -1 | sed 's/.*allow:[[:space:]]*//')
FORBID_LINE=$(grep -A5 '^scope:' "$MANIFEST" | grep 'forbid:' | head -1 | sed 's/.*forbid:[[:space:]]*//')

# Parse bracket list "[a, b, c]" → newline-separated items
parse_list() {
  echo "$1" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | grep -v '^$' || true
}

ALLOW_PATHS=$(parse_list "$ALLOW_LINE")
FORBID_PATHS=$(parse_list "$FORBID_LINE")

# Normalise file_path: strip leading ./
NORM_PATH=$(echo "$FILE_PATH" | sed 's|^\./||')

# ── Check forbid (highest priority) ─────────────────────────────────────────
while IFS= read -r fp; do
  [ -z "$fp" ] && continue
  norm_fp=$(echo "$fp" | sed 's|^\./||')
  if [[ "$NORM_PATH" == "$norm_fp"* ]]; then
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)
    ENTRY=$(printf '{"ts":"%s","event":"scope_violation","task_id":"%s","actor":"%s","file":"%s","matched_forbid":"%s","reason":"scope_violation"}' \
      "$TS" "$TASK_ID" "$AGENT" "$NORM_PATH" "$norm_fp")
    if [ -n "$AUDIT_ROOT" ]; then
      echo "$ENTRY" >> "$BYPASS_LOG"
    fi
    echo "scope_violation: $NORM_PATH matches forbid pattern $norm_fp (task=$TASK_ID)" >&2
    exit 2
  fi
done <<< "$FORBID_PATHS"

# ── Check allow ──────────────────────────────────────────────────────────────
# If allow list is empty, allow everything (no restriction defined).
if [ -z "$ALLOW_PATHS" ]; then
  exit 0
fi

while IFS= read -r ap; do
  [ -z "$ap" ] && continue
  norm_ap=$(echo "$ap" | sed 's|^\./||')
  if [[ "$NORM_PATH" == "$norm_ap"* ]]; then
    exit 0
  fi
done <<< "$ALLOW_PATHS"

# Path not in any allow entry → violation
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)
ENTRY=$(printf '{"ts":"%s","event":"scope_violation","task_id":"%s","actor":"%s","file":"%s","reason":"scope_violation","detail":"outside_allow"}' \
  "$TS" "$TASK_ID" "$AGENT" "$NORM_PATH")
if [ -n "$AUDIT_ROOT" ]; then
  echo "$ENTRY" >> "$BYPASS_LOG"
fi
echo "scope_violation: $NORM_PATH not in scope.allow (task=$TASK_ID)" >&2
exit 2
