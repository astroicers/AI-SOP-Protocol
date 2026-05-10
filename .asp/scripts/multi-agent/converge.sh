#!/usr/bin/env bash
# converge.sh — SPEC-004 B3: Orchestrator merge entry point.
#
# For each --task, rebases the worker branch onto base, then merges into
# base with --no-ff. After successful merge, removes the worktree (branch
# preserved for PR review). On any conflict, aborts the in-flight rebase/
# merge cleanly and writes an escalation log entry; previously merged tasks
# in the same converge call remain on base (partial success per SPEC §S8).
#
# Usage:
#   converge.sh --task <TASK_ID> [--task <TASK_ID> ...] [--base <branch>]
#
# Required env: ASP_AUDIT_ROOT
# Optional env: ASP_HITL_MODE=mock — skip human prompts, write escalation
#               log instead (SPEC §S11 mock semantics).
#
# Exit codes:
#   0  all listed tasks merged successfully
#   2  bad arguments (missing --task / unknown flag / task not found)
#   3  merge or rebase conflict (escalation log written; partial state OK)
#   7  ASP_AUDIT_ROOT validation failed

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_validate_audit_root.sh"

WRAPPER="$SCRIPT_DIR/audit-write.sh"

usage() {
    cat <<EOF >&2
Usage: $0 --task <TASK_ID> [--task <TASK_ID> ...] [--base <branch>]

  --task <TASK_ID>    Task to converge (may repeat for sequential merge)
  --base <branch>     Target branch (default: main)

Required env: ASP_AUDIT_ROOT
Exit: 0=ok, 2=bad args, 3=conflict, 7=ASP_AUDIT_ROOT invalid
EOF
}

# ── Argument parsing ───────────────────────────────────────────────────

TASKS=""
BASE_BRANCH="main"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --task) TASKS="$TASKS $2"; shift 2 ;;
        --base) BASE_BRANCH="$2";  shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "converge: unknown arg '$1'" >&2; usage; exit 2 ;;
    esac
done

# Validate audit root BEFORE checking tasks — ordering matches dispatch.sh
# so users see the most fundamental error first.
validate_audit_root || exit $?

if [ -z "$TASKS" ]; then
    echo "converge: at least one --task <TASK_ID> required" >&2
    exit 2
fi

# ── Helpers ────────────────────────────────────────────────────────────

# emit_telemetry <event> <task_id> <status> [extra_kv]
# extra_kv is appended verbatim inside the JSON object, e.g. ',"reason":"x"'
emit_telemetry() {
    local event="$1"; local tid="$2"; local status="$3"; local extra="${4:-}"
    bash "$WRAPPER" telemetry \
        "{\"event\":\"$event\",\"task_id\":\"$tid\",\"status\":\"$status\"$extra}" \
        >/dev/null 2>&1 || true
}

# emit_escalation <task_id> <reason> <details>
emit_escalation() {
    local tid="$1"; local reason="$2"; local details="$3"
    # Sanitize details: collapse to single line, drop double-quotes that would
    # break JSON. Belt-and-braces; the wrapper rejects multi-line anyway.
    local safe
    safe=$(printf '%s' "$details" | tr '\n' ' ' | tr -d '"' | sed 's/[[:space:]]\+/ /g')
    bash "$WRAPPER" escalation \
        "{\"task_id\":\"$tid\",\"reason\":\"$reason\",\"details\":\"$safe\"}" \
        >/dev/null 2>&1 || true
}

# Resolve a TASK ID to its (worktree_dir, branch). Reads the persisted manifest.
resolve_task() {
    local tid="$1"
    local mf="$ASP_AUDIT_ROOT/.asp-task-manifests/$tid.yaml"
    if [ ! -f "$mf" ]; then
        echo "converge: task manifest not found for $tid (looked in $mf)" >&2
        return 2
    fi
    TASK_BRANCH=$(grep -E '^worktree_branch:' "$mf" | head -1 | sed 's/^worktree_branch:[[:space:]]*//')
    if [ -z "$TASK_BRANCH" ]; then
        TASK_BRANCH="feat/spec-004-$(printf '%s' "$tid" | tr '[:upper:]' '[:lower:]')"
    fi
    TASK_WORKTREE="$ASP_AUDIT_ROOT/.asp-worktrees/$(printf '%s' "$tid" | tr '[:upper:]' '[:lower:]')"
    return 0
}

# Abort any in-progress rebase/merge in a worktree. Used before propagating
# a conflict exit so the worktree isn't left in a half-state.
abort_rebase_in_worktree() {
    local worktree="$1"
    if [ ! -d "$worktree" ]; then return 0; fi
    # Use git -C so we operate on the worktree, not the main repo.
    git -C "$worktree" rebase --abort >/dev/null 2>&1 || true
    git -C "$worktree" merge --abort >/dev/null 2>&1 || true
}

# ── Per-task converge loop ─────────────────────────────────────────────

# We process tasks sequentially. SPEC §S8 explicitly defines partial-success
# behavior: if TASK-A merges and TASK-B then conflicts, TASK-A stays on base.
# This is intentional — undoing TASK-A would discard verified work and break
# the "every successful task is recoverable from base" property.
#
# Reason classification: a conflict on a task that comes AFTER another task
# already merged in this same converge call is task_merge_conflict (S8). A
# conflict on the very first task (or one with nothing previously merged this
# round) is base_branch_rebase_conflict (S14) — the conflict came from
# changes that landed on base before converge started.
TASKS_MERGED_THIS_RUN=0

for tid in $TASKS; do
    if ! resolve_task "$tid"; then
        exit 2
    fi

    # Sanity: branch must exist (otherwise dispatch never ran for this task)
    if ! git -C "$ASP_AUDIT_ROOT" rev-parse --verify "$TASK_BRANCH" >/dev/null 2>&1; then
        echo "converge: branch $TASK_BRANCH does not exist for $tid" >&2
        emit_telemetry "multi_agent.fail" "$tid" "branch_missing"
        exit 2
    fi

    # Step 1: rebase task branch onto base. We do this in the worktree so the
    # rebase's working tree is the worktree's, leaving main repo untouched.
    if [ ! -d "$TASK_WORKTREE" ]; then
        echo "converge: worktree dir missing for $tid: $TASK_WORKTREE" >&2
        emit_telemetry "multi_agent.fail" "$tid" "worktree_missing"
        exit 2
    fi

    REBASE_STDERR=$(mktemp)
    if ! git -C "$TASK_WORKTREE" rebase "$BASE_BRANCH" >/dev/null 2>"$REBASE_STDERR"; then
        # Rebase conflict (B5/S14)
        CONFLICT_FILES=$(git -C "$TASK_WORKTREE" diff --name-only --diff-filter=U 2>/dev/null || true)
        echo "converge: rebase $TASK_BRANCH onto $BASE_BRANCH failed for $tid" >&2
        if [ -n "$CONFLICT_FILES" ]; then
            echo "  conflict files:" >&2
            printf '    %s\n' $CONFLICT_FILES >&2
        fi
        abort_rebase_in_worktree "$TASK_WORKTREE"
        # Distinguish task-vs-task from task-vs-base per SPEC §S8/S14.
        if [ "$TASKS_MERGED_THIS_RUN" -gt 0 ]; then
            REASON="task_merge_conflict"
        else
            REASON="base_branch_rebase_conflict"
        fi
        emit_escalation "$tid" "$REASON" "$CONFLICT_FILES"
        emit_telemetry "multi_agent.fail" "$tid" "$REASON" \
            ",\"conflict_files\":\"$(printf '%s' "$CONFLICT_FILES" | tr '\n' ' ' | sed 's/[[:space:]]*$//')\""
        rm -f "$REBASE_STDERR"
        exit 3
    fi
    rm -f "$REBASE_STDERR"

    # Step 2: merge task branch into base from the main repo. Use --no-ff so
    # the merge commit is always present (matches P4 "3 merge commits"
    # assertion). Run in main repo, not worktree, because we're updating
    # base_branch HEAD.
    MERGE_STDERR=$(mktemp)
    if ! git -C "$ASP_AUDIT_ROOT" merge --no-ff "$TASK_BRANCH" \
            -m "merge: converge $tid" >/dev/null 2>"$MERGE_STDERR"; then
        # Task-vs-task conflict (N3/S8). Note: with rebase-then-merge above,
        # this should be rare (rebase already aligned with base). It can still
        # happen if a previously-merged task in this same converge call left
        # a state the rebase couldn't anticipate.
        CONFLICT_FILES=$(git -C "$ASP_AUDIT_ROOT" diff --name-only --diff-filter=U 2>/dev/null || true)
        echo "converge: merge $TASK_BRANCH into $BASE_BRANCH failed for $tid" >&2
        if [ -n "$CONFLICT_FILES" ]; then
            echo "  conflict files:" >&2
            printf '    %s\n' $CONFLICT_FILES >&2
        fi
        git -C "$ASP_AUDIT_ROOT" merge --abort >/dev/null 2>&1 || true
        emit_escalation "$tid" "task_merge_conflict" "$CONFLICT_FILES"
        emit_telemetry "multi_agent.fail" "$tid" "task_merge_conflict" \
            ",\"conflict_files\":\"$(printf '%s' "$CONFLICT_FILES" | tr '\n' ' ' | sed 's/[[:space:]]*$//')\""
        rm -f "$MERGE_STDERR"
        exit 3
    fi
    rm -f "$MERGE_STDERR"

    # Step 3: cleanup worktree (branch preserved for PR review per P3).
    git -C "$ASP_AUDIT_ROOT" worktree remove --force "$TASK_WORKTREE" >/dev/null 2>&1 || true

    emit_telemetry "multi_agent.converge" "$tid" "success"
    TASKS_MERGED_THIS_RUN=$((TASKS_MERGED_THIS_RUN + 1))
done
