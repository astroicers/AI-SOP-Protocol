#!/usr/bin/env bash
# worktree-list.sh — SPEC-004 B4: list all SPEC-004 worktrees with metadata.
#
# Usage: worktree-list.sh
# Required env: ASP_AUDIT_ROOT
#
# Output format (one row per worktree):
#   TASK_ID  AGE  BRANCH  PATH  STATUS
# AGE is the time since the worktree's HEAD commit (h/m units, human-friendly).
# STATUS is "fresh" if AGE < threshold else "stale".
#
# Exit:
#   0  success (even if zero worktrees)
#   7  ASP_AUDIT_ROOT validation failed

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_validate_audit_root.sh"

validate_audit_root || exit $?

# Threshold — same source as worktree-gc.sh so the two stay consistent.
IDLE_HOURS="${ASP_WORKTREE_IDLE_HOURS:-2}"
# Convert to seconds via awk to handle fractional values like 0.5.
IDLE_SECONDS=$(awk -v h="$IDLE_HOURS" 'BEGIN { printf "%d", h * 3600 }')

WORKTREE_ROOT="$ASP_AUDIT_ROOT/.asp-worktrees"
NOW=$(date +%s)

# Empty / no dir → header + early return so users see the script ran.
if [ ! -d "$WORKTREE_ROOT" ]; then
    echo "no worktrees (no $WORKTREE_ROOT directory)"
    exit 0
fi

# git worktree list --porcelain emits 3-line records per worktree:
#   worktree <path>
#   HEAD <sha>
#   branch refs/heads/<name>
# We parse this rather than scanning the dir so detached/missing worktrees
# are reported correctly.

WORKTREES=$(git -C "$ASP_AUDIT_ROOT" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { p=$2 } /^branch refs\/heads\/(feat\/spec-004-)/ { sub("^branch refs/heads/", "", $0); print p "|" $0 }')

if [ -z "$WORKTREES" ]; then
    echo "no SPEC-004 worktrees active"
    exit 0
fi

# Header
printf '%-12s  %-10s  %-32s  %-40s  %s\n' "TASK_ID" "AGE" "BRANCH" "PATH" "STATUS"

while IFS='|' read -r path branch; do
    [ -z "$path" ] && continue

    # Derive task_id from path basename (lowercased dir → uppercase TASK ID)
    base=$(basename "$path")
    tid=$(printf '%s' "$base" | tr '[:lower:]' '[:upper:]')

    # Age = NOW - HEAD commit time (using git -C on the worktree)
    head_ts=$(git -C "$path" log -1 --format=%ct 2>/dev/null || echo "$NOW")
    age_sec=$((NOW - head_ts))
    if [ "$age_sec" -lt 60 ]; then
        age_str="${age_sec}s"
    elif [ "$age_sec" -lt 3600 ]; then
        age_str="$((age_sec / 60))m"
    else
        age_str="$((age_sec / 3600))h"
    fi

    if [ "$age_sec" -gt "$IDLE_SECONDS" ]; then
        status="stale"
    else
        status="fresh"
    fi

    printf '%-12s  %-10s  %-32s  %-40s  %s\n' "$tid" "$age_str" "$branch" "$path" "$status"
done <<EOF
$WORKTREES
EOF
