#!/usr/bin/env bash
# worktree-gc.sh — SPEC-004 B4: garbage-collect stale SPEC-004 worktrees.
#
# A worktree is "stale" when its HEAD commit time is older than
# ASP_WORKTREE_IDLE_HOURS (default 2). For each stale worktree:
#   1. git worktree remove --force (deletes worktree dir but keeps branch)
#   2. annotate .asp-task-manifests/<TID>.yaml with `abandoned: true`
#   3. emit multi_agent.gc telemetry
#
# Branches are preserved so a human can still `git log <branch>` to see
# what the abandoned worker did, or merge it manually if the work is
# salvageable. Same policy as converge.sh's post-merge cleanup (P3).
#
# Usage:
#   worktree-gc.sh [--dry-run]
#
# Required env: ASP_AUDIT_ROOT
# Optional env: ASP_WORKTREE_IDLE_HOURS (default 2; accepts fractions like 0.5)
#
# Exit:
#   0  success (zero or more worktrees collected)
#   7  ASP_AUDIT_ROOT validation failed

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_validate_audit_root.sh"

WRAPPER="$SCRIPT_DIR/audit-write.sh"

DRY_RUN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1; shift ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--dry-run]
Required env: ASP_AUDIT_ROOT
Optional env: ASP_WORKTREE_IDLE_HOURS (default 2)
EOF
            exit 0
            ;;
        *) echo "worktree-gc: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

validate_audit_root || exit $?

IDLE_HOURS="${ASP_WORKTREE_IDLE_HOURS:-2}"
IDLE_SECONDS=$(awk -v h="$IDLE_HOURS" 'BEGIN { printf "%d", h * 3600 }')

WORKTREE_ROOT="$ASP_AUDIT_ROOT/.asp-worktrees"
MANIFESTS_DIR="$ASP_AUDIT_ROOT/.asp-task-manifests"
NOW=$(date +%s)

# Nothing to do if dir absent.
if [ ! -d "$WORKTREE_ROOT" ]; then
    exit 0
fi

# Collect candidate worktrees from git's source of truth (handles detached
# / pruned cases git already knows about, but we'll filter to SPEC-004 ones).
CANDIDATES=$(git -C "$ASP_AUDIT_ROOT" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { p=$2 } /^branch refs\/heads\/feat\/spec-004-/ { print p }')

if [ -z "$CANDIDATES" ]; then
    exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
    echo "── DRY-RUN: would collect the following ──"
fi

COLLECTED=0
while IFS= read -r path; do
    [ -z "$path" ] && continue

    # If the dir vanished from disk but git still knows about it, treat as
    # already-abandoned and prune.
    if [ ! -d "$path" ]; then
        if [ "$DRY_RUN" = "1" ]; then
            echo "  [missing] $path (would prune git's record)"
        else
            git -C "$ASP_AUDIT_ROOT" worktree prune >/dev/null 2>&1 || true
        fi
        continue
    fi

    head_ts=$(git -C "$path" log -1 --format=%ct 2>/dev/null || echo "$NOW")
    age_sec=$((NOW - head_ts))

    if [ "$age_sec" -le "$IDLE_SECONDS" ]; then
        continue  # fresh — leave alone
    fi

    base=$(basename "$path")
    tid=$(printf '%s' "$base" | tr '[:lower:]' '[:upper:]')

    if [ "$DRY_RUN" = "1" ]; then
        echo "  [stale, ${age_sec}s] $tid — $path"
        continue
    fi

    # Real collection: remove worktree, annotate manifest, emit telemetry
    git -C "$ASP_AUDIT_ROOT" worktree remove --force "$path" >/dev/null 2>&1 || true

    # Annotate manifest. Idempotent: if abandoned: true already present, skip.
    manifest="$MANIFESTS_DIR/$tid.yaml"
    if [ -f "$manifest" ] && ! grep -q '^abandoned:' "$manifest"; then
        printf 'abandoned: true\nabandoned_at: %s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$manifest"
    fi

    bash "$WRAPPER" telemetry \
        "{\"event\":\"multi_agent.gc\",\"task_id\":\"$tid\",\"age_seconds\":$age_sec}" \
        >/dev/null 2>&1 || true

    COLLECTED=$((COLLECTED + 1))
done <<EOF
$CANDIDATES
EOF

if [ "$DRY_RUN" = "0" ] && [ "$COLLECTED" -gt 0 ]; then
    echo "worktree-gc: collected $COLLECTED stale worktree(s)"
fi
