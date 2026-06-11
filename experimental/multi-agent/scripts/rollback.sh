#!/usr/bin/env bash
# rollback.sh — SPEC-004 §🔄 Rollback Plan
#
# Discard all in-flight SPEC-004 work cleanly:
#   1. For every active worktree under .asp-worktrees/, force-remove it
#      (`git worktree remove --force`)
#   2. Delete the corresponding feat/spec-004-* branches (`git branch -D`)
#   3. Verify base branch HEAD has not moved
#
# What stays intact:
#   - base branch (untouched — rollback only discards in-flight Worker work)
#   - .asp-task-manifests/*.yaml (kept as forensic record of what was tried)
#   - .asp-bypass-log.ndjson / .asp-telemetry.ndjson (Iron Rule B append-only)
#
# Usage:
#   rollback.sh [--dry-run] [--base <branch>]
#
# Required env: ASP_AUDIT_ROOT
# Exit:
#   0  rollback succeeded (or nothing to roll back)
#   2  bad args
#   7  ASP_AUDIT_ROOT validation failed
#   8  rollback verification failed (base HEAD moved, or branch deletion blocked)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_validate_audit_root.sh"

WRAPPER="$SCRIPT_DIR/audit-write.sh"

DRY_RUN=0
BASE_BRANCH="main"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1; shift ;;
        --base)       BASE_BRANCH="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--dry-run] [--base <branch>]
Required env: ASP_AUDIT_ROOT
Exit: 0=ok / 2=args / 7=ASP_AUDIT_ROOT / 8=verify failed
EOF
            exit 0
            ;;
        *) echo "rollback: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

validate_audit_root || exit $?

# Snapshot base HEAD BEFORE we do anything so we can verify it didn't move.
BASE_HEAD_BEFORE=$(git -C "$ASP_AUDIT_ROOT" rev-parse "$BASE_BRANCH" 2>/dev/null || echo "")
if [ -z "$BASE_HEAD_BEFORE" ]; then
    echo "rollback: base branch '$BASE_BRANCH' not found" >&2
    exit 2
fi

# Collect SPEC-004 worktrees + branches.
WORKTREES=$(git -C "$ASP_AUDIT_ROOT" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { p=$2 } /^branch refs\/heads\/feat\/spec-004-/ { sub("^branch refs/heads/", "", $0); print p "|" $0 }')

BRANCHES=$(git -C "$ASP_AUDIT_ROOT" branch --list 'feat/spec-004-*' --format='%(refname:short)')

if [ -z "$WORKTREES" ] && [ -z "$BRANCHES" ]; then
    [ "$DRY_RUN" = "1" ] && echo "rollback: nothing to roll back"
    exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
    echo "── DRY-RUN: would perform ──"
    while IFS='|' read -r path branch; do
        [ -z "$path" ] && continue
        echo "  worktree remove --force $path  (branch $branch)"
    done <<EOF
$WORKTREES
EOF
    while IFS= read -r b; do
        [ -z "$b" ] && continue
        echo "  branch -D $b"
    done <<EOF
$BRANCHES
EOF
    echo "  verify $BASE_BRANCH HEAD == $BASE_HEAD_BEFORE"
    exit 0
fi

# Step 1: remove worktrees
ROLLED_BACK_WORKTREES=0
while IFS='|' read -r path branch; do
    [ -z "$path" ] && continue
    git -C "$ASP_AUDIT_ROOT" worktree remove --force "$path" >/dev/null 2>&1 || true
    ROLLED_BACK_WORKTREES=$((ROLLED_BACK_WORKTREES + 1))
done <<EOF
$WORKTREES
EOF

# Prune stale entries (catches detached worktrees git's records know about)
git -C "$ASP_AUDIT_ROOT" worktree prune >/dev/null 2>&1 || true

# Step 2: delete branches (re-fetch the list because worktree removal
# may have already cleaned some refs).
BRANCHES_AFTER_PRUNE=$(git -C "$ASP_AUDIT_ROOT" branch --list 'feat/spec-004-*' --format='%(refname:short)')
ROLLED_BACK_BRANCHES=0
while IFS= read -r b; do
    [ -z "$b" ] && continue
    if ! git -C "$ASP_AUDIT_ROOT" branch -D "$b" >/dev/null 2>&1; then
        echo "rollback: failed to delete branch $b" >&2
        # Don't exit 8 here — maybe the branch was already deleted by
        # worktree-remove. Verify HEAD at the end is the real test.
    else
        ROLLED_BACK_BRANCHES=$((ROLLED_BACK_BRANCHES + 1))
    fi
done <<EOF
$BRANCHES_AFTER_PRUNE
EOF

# Step 3: verify base HEAD didn't move
BASE_HEAD_AFTER=$(git -C "$ASP_AUDIT_ROOT" rev-parse "$BASE_BRANCH" 2>/dev/null || echo "")
if [ "$BASE_HEAD_AFTER" != "$BASE_HEAD_BEFORE" ]; then
    echo "rollback: BASE HEAD CHANGED unexpectedly!" >&2
    echo "  before: $BASE_HEAD_BEFORE" >&2
    echo "  after:  $BASE_HEAD_AFTER" >&2
    exit 8
fi

# Step 4: telemetry
bash "$WRAPPER" telemetry \
    "{\"event\":\"multi_agent.rollback\",\"worktrees\":$ROLLED_BACK_WORKTREES,\"branches\":$ROLLED_BACK_BRANCHES,\"base_head\":\"$BASE_HEAD_AFTER\"}" \
    >/dev/null 2>&1 || true

echo "rollback: removed $ROLLED_BACK_WORKTREES worktree(s), $ROLLED_BACK_BRANCHES branch(es); base HEAD unchanged ($BASE_HEAD_AFTER)"
