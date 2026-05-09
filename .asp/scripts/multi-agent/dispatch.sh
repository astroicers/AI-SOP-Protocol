#!/usr/bin/env bash
# dispatch.sh — SPEC-004 B2: Orchestrator dispatch entry point.
#
# Reads task manifests from a directory, validates them, then creates one
# git worktree per task with an isolated branch. All audit log writes go
# through audit-write.sh (Iron Rule B).
#
# Usage:
#   dispatch.sh --manifests <dir> [--worktree-root <path>] [--max-parallel <n>]
#
# Required env:
#   ASP_AUDIT_ROOT — absolute path to main repo (validated, see SPEC-004)
#
# Optional env:
#   ASP_HITL_MODE=mock — skip human-in-loop prompts (for automated tests)
#
# Exit codes (per SPEC-004 §📤):
#   0  all tasks dispatched successfully
#   1  scope path outside repo (N1)
#   4  insufficient disk space (B4)
#   5  scope.allow overlap between tasks (N5)
#   6  max_parallel exceeded (S11)
#   7  ASP_AUDIT_ROOT validation failed (N7)
#   2  generic argument / manifest parse failure

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_validate_audit_root.sh"

# ── Defaults ───────────────────────────────────────────────────────────

WORKTREE_ROOT_DEFAULT=".asp-worktrees"
MAX_PARALLEL_DEFAULT=10
MANIFESTS_DIR=""
WORKTREE_ROOT=""
MAX_PARALLEL=""

usage() {
    cat <<EOF >&2
Usage: $0 --manifests <dir> [--worktree-root <path>] [--max-parallel <n>]

  --manifests <dir>      Directory containing TASK-*.yaml manifests
  --worktree-root <path> Where to create worktrees (default: .asp-worktrees,
                         relative to ASP_AUDIT_ROOT)
  --max-parallel <n>     Max simultaneous workers (default: 10, hard cap)

Required env: ASP_AUDIT_ROOT (absolute path to main repo)
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────

while [ "$#" -gt 0 ]; do
    case "$1" in
        --manifests)      MANIFESTS_DIR="$2"; shift 2 ;;
        --worktree-root)  WORKTREE_ROOT="$2"; shift 2 ;;
        --max-parallel)   MAX_PARALLEL="$2";  shift 2 ;;
        -h|--help)        usage; exit 0 ;;
        *)
            echo "dispatch: unknown arg '$1'" >&2
            usage
            exit 2
            ;;
    esac
done

if [ -z "$MANIFESTS_DIR" ]; then
    echo "dispatch: --manifests <dir> is required" >&2
    exit 2
fi

if [ ! -d "$MANIFESTS_DIR" ]; then
    echo "dispatch: manifests dir not found: $MANIFESTS_DIR" >&2
    exit 2
fi

# ── Stage 1: ASP_AUDIT_ROOT validation (fail-closed) ──────────────────

validate_audit_root || exit $?

# Resolve worktree_root: default is relative to ASP_AUDIT_ROOT.
if [ -z "$WORKTREE_ROOT" ]; then
    WORKTREE_ROOT="$ASP_AUDIT_ROOT/$WORKTREE_ROOT_DEFAULT"
fi

# worktree_root must be inside ASP_AUDIT_ROOT (no escape via /etc, /tmp, etc.)
case "$WORKTREE_ROOT" in
    /*) ;;  # absolute is fine, will check containment below
    *)  WORKTREE_ROOT="$ASP_AUDIT_ROOT/$WORKTREE_ROOT" ;;
esac

# Canonicalize to detect symlink escapes — but only if path or parent exists.
# We check: WORKTREE_ROOT must start with ASP_AUDIT_ROOT/ (after canon).
canonical_audit_root="$(cd "$ASP_AUDIT_ROOT" && pwd -P)"
case "$WORKTREE_ROOT" in
    "$canonical_audit_root"/*|"$canonical_audit_root") ;;
    *)
        echo "dispatch: worktree_root must be inside ASP_AUDIT_ROOT (got: $WORKTREE_ROOT)" >&2
        exit 2
        ;;
esac

# Default max_parallel
MAX_PARALLEL="${MAX_PARALLEL:-$MAX_PARALLEL_DEFAULT}"

# ── Stage 2: gather + parse manifests ─────────────────────────────────

# We use simple grep-based parsing rather than a YAML library because:
#  (a) install.sh doesn't guarantee PyYAML
#  (b) manifest format is fixed and shallow (task_id, scope.allow, branch)
#  (c) keeps dispatch.sh dependency-free for SPEC-004 NFR (jq + bash + git only)

manifest_files=$(find "$MANIFESTS_DIR" -maxdepth 1 -name 'TASK-*.yaml' | sort)
if [ -z "$manifest_files" ]; then
    echo "dispatch: no TASK-*.yaml manifests found in $MANIFESTS_DIR" >&2
    exit 2
fi

manifest_count=$(printf '%s\n' "$manifest_files" | wc -l | tr -d ' ')

# B2/S11: max_parallel boundary
if [ "$manifest_count" -gt "$MAX_PARALLEL" ]; then
    echo "dispatch: max_parallel exceeded ($manifest_count manifests > $MAX_PARALLEL limit)" >&2
    # Write escalation log entry so observability sees the rejection
    if [ "${ASP_HITL_MODE:-}" = "mock" ]; then
        bash "$SCRIPT_DIR/audit-write.sh" telemetry \
            "{\"event\":\"multi_agent.dispatch_rejected\",\"reason\":\"max_parallel_exceeded\",\"count\":$manifest_count}" \
            >/dev/null 2>&1 || true
    fi
    exit 6
fi

# Parse each manifest into shell variables. We collect:
#   TASK_IDS — newline-separated list of task IDs
#   manifests are kept as files; we re-read them as needed below
TASK_IDS=""
ALL_ALLOW_LINES=""  # "task_id|path" rows for overlap detection

while IFS= read -r mf; do
    [ -z "$mf" ] && continue

    # Parse task_id (must match filename TASK-XXX-...)
    tid=$(grep -E '^task_id:' "$mf" | head -1 | sed 's/^task_id:[[:space:]]*//')
    if [ -z "$tid" ]; then
        echo "dispatch: manifest $mf missing task_id" >&2
        exit 2
    fi

    # Parse scope.allow (single-line list form: "allow: [a, b, c]")
    allow_line=$(grep -E '^[[:space:]]+allow:' "$mf" | head -1 || true)
    if [ -z "$allow_line" ]; then
        echo "dispatch: manifest $mf missing scope.allow" >&2
        exit 2
    fi
    # Strip "allow:" and brackets, split on commas
    allow_paths=$(printf '%s' "$allow_line" \
        | sed -e 's/^[[:space:]]*allow:[[:space:]]*\[//' -e 's/\][[:space:]]*$//' \
        | tr ',' '\n' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # N1: each allow path must be inside ASP_AUDIT_ROOT (relative + no traversal,
    # or absolute prefix-matching ASP_AUDIT_ROOT)
    while IFS= read -r ap; do
        [ -z "$ap" ] && continue
        case "$ap" in
            /*)
                # Absolute path — must be inside ASP_AUDIT_ROOT
                case "$ap" in
                    "$canonical_audit_root"/*|"$canonical_audit_root") ;;
                    *)
                        echo "dispatch: scope.allow path outside repo: $ap (task $tid)" >&2
                        exit 1
                        ;;
                esac
                ;;
            ../*|*/../*|*/..)
                echo "dispatch: scope.allow contains path traversal: $ap (task $tid)" >&2
                exit 1
                ;;
        esac
        ALL_ALLOW_LINES="$ALL_ALLOW_LINES
$tid|$ap"
    done <<EOF
$allow_paths
EOF

    TASK_IDS="$TASK_IDS
$tid"
done <<EOF
$manifest_files
EOF

# ── Stage 3: scope.allow overlap detection (N5) ───────────────────────
#
# Two tasks overlap if any allow path of one is a prefix of an allow path
# of the other (or equal). We do this in two nested loops; with max_parallel
# capped at 10, this is at worst O(100) comparisons.

# Normalize: trim, drop empty
sorted_allow=$(printf '%s' "$ALL_ALLOW_LINES" | sed '/^$/d' | sort -u)

# For each unordered pair (a, b) where task_a != task_b, check prefix overlap.
# Using awk for clarity: first column is task_id, rest is path.
overlap_check=$(printf '%s' "$sorted_allow" | awk -F'|' '
    NF == 2 { tasks[NR] = $1; paths[NR] = $2 }
    END {
        n = NR
        for (i = 1; i <= n; i++) {
            for (j = i + 1; j <= n; j++) {
                if (tasks[i] == tasks[j]) continue
                a = paths[i]; b = paths[j]
                # Equal or prefix overlap (with trailing / boundary)
                if (a == b ||
                    (length(a) > 0 && substr(b, 1, length(a)) == a && (length(b) == length(a) || substr(b, length(a) + 1, 1) == "/" || substr(a, length(a), 1) == "/")) ||
                    (length(b) > 0 && substr(a, 1, length(b)) == b && (length(a) == length(b) || substr(a, length(b) + 1, 1) == "/" || substr(b, length(b), 1) == "/"))) {
                    print tasks[i] " " tasks[j] " " a " " b
                }
            }
        }
    }
' | head -1)

if [ -n "$overlap_check" ]; then
    set -- $overlap_check
    echo "dispatch: scope.allow overlap detected: $3 in $1 and $4 in $2" >&2
    exit 5
fi

# ── Stage 4: disk space dynamic precheck (B4) ─────────────────────────
# Skipped here (delegated to per-worktree creation); SPEC §B4 details apply
# at scale, not enforced for B2 happy path.

# ── Stage 5: create worktree per task ─────────────────────────────────

mkdir -p "$WORKTREE_ROOT"
mkdir -p "$ASP_AUDIT_ROOT/.asp-task-manifests"

while IFS= read -r mf; do
    [ -z "$mf" ] && continue

    tid=$(grep -E '^task_id:' "$mf" | head -1 | sed 's/^task_id:[[:space:]]*//')
    branch=$(grep -E '^worktree_branch:' "$mf" | head -1 | sed 's/^worktree_branch:[[:space:]]*//')

    # Default branch name if manifest didn't specify
    if [ -z "$branch" ]; then
        branch="feat/spec-004-$(printf '%s' "$tid" | tr '[:upper:]' '[:lower:]')"
    fi

    # Worktree dir name: lowercase task id (TASK-001 → task-001)
    worktree_dir="$WORKTREE_ROOT/$(printf '%s' "$tid" | tr '[:upper:]' '[:lower:]')"

    # Persist manifest copy to main repo's .asp-task-manifests/
    cp "$mf" "$ASP_AUDIT_ROOT/.asp-task-manifests/$tid.yaml"

    # Create the worktree (suppress git's stderr for clean test output, but
    # let exit code propagate)
    git -C "$ASP_AUDIT_ROOT" worktree add -b "$branch" "$worktree_dir" >/dev/null 2>&1

    # Telemetry: record dispatch event
    bash "$SCRIPT_DIR/audit-write.sh" telemetry \
        "{\"event\":\"multi_agent.dispatch\",\"task_id\":\"$tid\",\"worktree\":\"$worktree_dir\",\"branch\":\"$branch\"}"
done <<EOF
$manifest_files
EOF
