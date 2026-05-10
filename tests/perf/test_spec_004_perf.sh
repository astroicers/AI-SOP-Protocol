#!/usr/bin/env bash
# test_spec_004_perf.sh — SPEC-004 B6 perf benchmarks
#
# Measures p50 / p95 / max latency for dispatch.sh and converge.sh, plus
# the full-scale S18 stress test (10 workers × 1000 entries). Output is
# both human-readable (stdout) and JSON-friendly (--json mode) for the
# benchmarks.md table.
#
# Usage:
#   bash tests/perf/test_spec_004_perf.sh                     # human report
#   bash tests/perf/test_spec_004_perf.sh --json              # JSON only
#   bash tests/perf/test_spec_004_perf.sh --skip-stress       # skip 10×1000
#   bash tests/perf/test_spec_004_perf.sh --runs 10           # samples (default 10)
#
# This is NOT in `make test` — it takes 30-60s and is a release-gate tool,
# not a CI test. Run it manually before each release / when changing perf-
# sensitive code paths.

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNS=10
JSON_ONLY=0
SKIP_STRESS=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)         JSON_ONLY=1; shift ;;
        --skip-stress)  SKIP_STRESS=1; shift ;;
        --runs)         RUNS="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \?//' | head -25
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

DISPATCH="$ASP_ROOT/.asp/scripts/multi-agent/dispatch.sh"
CONVERGE="$ASP_ROOT/.asp/scripts/multi-agent/converge.sh"
WRAPPER="$ASP_ROOT/.asp/scripts/multi-agent/audit-write.sh"

TEST_BASE=$(mktemp -d /tmp/asp-perf-XXXXXX)
trap 'rm -rf "$TEST_BASE"' EXIT

# ── helpers ─────────────────────────────────────────────────────────────

# percentile <p> <sorted_values...>
# p in [0,100]. Uses nearest-rank method (no interpolation).
percentile() {
    local p="$1"; shift
    local n=$#
    local rank=$(awk -v p="$p" -v n="$n" 'BEGIN { r = int((p/100) * n + 0.5); if (r < 1) r = 1; if (r > n) r = n; print r }')
    eval echo "\${$rank}"
}

# Run one dispatch+converge cycle, output elapsed seconds (3 decimals)
time_one_dispatch() {
    local dir="$1"
    local start end
    start=$(date +%s%N)
    ASP_AUDIT_ROOT="$dir" bash "$DISPATCH" --manifests "$dir/manifests" >/dev/null 2>&1
    end=$(date +%s%N)
    awk -v s="$start" -v e="$end" 'BEGIN { printf "%.3f\n", (e - s) / 1e9 }'
}

time_one_converge() {
    local dir="$1"; local tid="$2"
    local start end
    start=$(date +%s%N)
    ASP_AUDIT_ROOT="$dir" bash "$CONVERGE" --task "$tid" >/dev/null 2>&1
    end=$(date +%s%N)
    awk -v s="$start" -v e="$end" 'BEGIN { printf "%.3f\n", (e - s) / 1e9 }'
}

setup_repo() {
    local dir="$1"
    rm -rf "$dir"
    git init -q -b main "$dir"
    cd "$dir"
    git config user.email t@t && git config user.name t
    mkdir -p src/store src/api src/auth
    echo s > src/store/x && echo a > src/api/x && echo u > src/auth/x
    git add -A && git commit -q -m init
    cd "$ASP_ROOT"

    mkdir -p "$dir/manifests"
    cat > "$dir/manifests/TASK-001.yaml" <<EOF
task_id: TASK-001
agent: worker-a
agent_role: impl
scope:
  allow: [src/store/]
  forbid: []
worktree_branch: feat/spec-004-task-001
EOF
}

# ── Dispatch latency benchmark ──────────────────────────────────────────

[ "$JSON_ONLY" = 0 ] && echo "── Dispatch latency: $RUNS samples (1 task per dispatch) ──"

DISPATCH_TIMES=()
for i in $(seq 1 "$RUNS"); do
    DIR="$TEST_BASE/dispatch-$i"
    setup_repo "$DIR"
    t=$(time_one_dispatch "$DIR")
    DISPATCH_TIMES+=("$t")
    [ "$JSON_ONLY" = 0 ] && printf "  run %02d: %ss\n" "$i" "$t"
done

# Sort numerically
DISPATCH_SORTED=($(printf '%s\n' "${DISPATCH_TIMES[@]}" | sort -n))
DISPATCH_P50=$(percentile 50 "${DISPATCH_SORTED[@]}")
DISPATCH_P95=$(percentile 95 "${DISPATCH_SORTED[@]}")
DISPATCH_MAX="${DISPATCH_SORTED[$((RUNS - 1))]}"

[ "$JSON_ONLY" = 0 ] && echo "  → p50=${DISPATCH_P50}s  p95=${DISPATCH_P95}s  max=${DISPATCH_MAX}s"
[ "$JSON_ONLY" = 0 ] && echo ""

# ── Converge latency benchmark ──────────────────────────────────────────

[ "$JSON_ONLY" = 0 ] && echo "── Converge latency: $RUNS samples (1 task per converge, no conflict) ──"

CONVERGE_TIMES=()
for i in $(seq 1 "$RUNS"); do
    DIR="$TEST_BASE/converge-$i"
    setup_repo "$DIR"
    # dispatch first
    ASP_AUDIT_ROOT="$DIR" bash "$DISPATCH" --manifests "$DIR/manifests" >/dev/null 2>&1
    # worker commits something so converge has actual work
    cd "$DIR/.asp-worktrees/task-001"
    echo "modified" > src/store/x
    git add -A && git commit -q -m "worker change"
    cd "$ASP_ROOT"
    t=$(time_one_converge "$DIR" "TASK-001")
    CONVERGE_TIMES+=("$t")
    [ "$JSON_ONLY" = 0 ] && printf "  run %02d: %ss\n" "$i" "$t"
done

CONVERGE_SORTED=($(printf '%s\n' "${CONVERGE_TIMES[@]}" | sort -n))
CONVERGE_P50=$(percentile 50 "${CONVERGE_SORTED[@]}")
CONVERGE_P95=$(percentile 95 "${CONVERGE_SORTED[@]}")
CONVERGE_MAX="${CONVERGE_SORTED[$((RUNS - 1))]}"

[ "$JSON_ONLY" = 0 ] && echo "  → p50=${CONVERGE_P50}s  p95=${CONVERGE_P95}s  max=${CONVERGE_MAX}s"
[ "$JSON_ONLY" = 0 ] && echo ""

# ── S18 full-scale stress test (10 × 1000) ──────────────────────────────

STRESS_RESULT="skipped"
STRESS_LINES=0
STRESS_INVALID=0
STRESS_DURATION="0.000"

if [ "$SKIP_STRESS" = 0 ]; then
    [ "$JSON_ONLY" = 0 ] && echo "── S18 stress: 10 workers × 1000 entries (full-scale per SPEC §S18) ──"

    DIR="$TEST_BASE/stress"
    rm -rf "$DIR"
    git init -q -b main "$DIR"
    cd "$DIR" && git config user.email t@t && git config user.name t
    echo init > x && git add x && git commit -q -m init && cd "$ASP_ROOT"

    NUM_WORKERS=10
    ENTRIES_PER_WORKER=1000
    TOTAL_EXPECTED=$((NUM_WORKERS * ENTRIES_PER_WORKER))

    start=$(date +%s%N)
    PIDS=""
    for w in $(seq 1 "$NUM_WORKERS"); do
        (
            for i in $(seq 1 "$ENTRIES_PER_WORKER"); do
                ASP_AUDIT_ROOT="$DIR" bash "$WRAPPER" bypass "{\"w\":$w,\"i\":$i}" 2>/dev/null
            done
        ) &
        PIDS="$PIDS $!"
    done
    for pid in $PIDS; do wait "$pid"; done
    end=$(date +%s%N)
    STRESS_DURATION=$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.3f", (e - s) / 1e9 }')

    LOG="$DIR/.asp-bypass-log.ndjson"
    STRESS_LINES=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ' || echo 0)
    if command -v jq >/dev/null 2>&1; then
        STRESS_INVALID=$(jq -r -c . "$LOG" 2>&1 >/dev/null | wc -l | tr -d ' ' || echo 0)
    fi

    if [ "$STRESS_LINES" = "$TOTAL_EXPECTED" ] && [ "$STRESS_INVALID" = "0" ]; then
        STRESS_RESULT="pass"
    else
        STRESS_RESULT="fail"
    fi

    [ "$JSON_ONLY" = 0 ] && {
        echo "  expected lines: $TOTAL_EXPECTED"
        echo "  actual lines:   $STRESS_LINES"
        echo "  invalid JSON:   $STRESS_INVALID"
        echo "  duration:       ${STRESS_DURATION}s"
        echo "  result:         $STRESS_RESULT"
        echo ""
    }
fi

# ── Summary ──

if [ "$JSON_ONLY" = 1 ]; then
    cat <<EOF
{
  "runs": $RUNS,
  "dispatch": {"p50": $DISPATCH_P50, "p95": $DISPATCH_P95, "max": $DISPATCH_MAX},
  "converge": {"p50": $CONVERGE_P50, "p95": $CONVERGE_P95, "max": $CONVERGE_MAX},
  "stress": {"result": "$STRESS_RESULT", "expected": $((NUM_WORKERS * ENTRIES_PER_WORKER)), "actual_lines": $STRESS_LINES, "invalid_json": $STRESS_INVALID, "duration_seconds": $STRESS_DURATION}
}
EOF
else
    echo "═══════════════════════════════════════"
    echo "  SPEC-004 perf summary"
    echo "  dispatch  p95 = ${DISPATCH_P95}s   (SPEC budget: < 5s)"
    echo "  converge  p95 = ${CONVERGE_P95}s   (SPEC budget: < 10s)"
    if [ "$SKIP_STRESS" = 0 ]; then
        echo "  S18       = $STRESS_RESULT (10 × 1000 in ${STRESS_DURATION}s)"
    fi
    echo "═══════════════════════════════════════"
fi

# Exit code: 0 if SPEC budgets met AND stress passed (or skipped)
DISPATCH_OK=$(awk -v v="$DISPATCH_P95" 'BEGIN { print (v < 5) ? 1 : 0 }')
CONVERGE_OK=$(awk -v v="$CONVERGE_P95" 'BEGIN { print (v < 10) ? 1 : 0 }')
STRESS_OK=1
[ "$STRESS_RESULT" = "fail" ] && STRESS_OK=0

if [ "$DISPATCH_OK" = 1 ] && [ "$CONVERGE_OK" = 1 ] && [ "$STRESS_OK" = 1 ]; then
    exit 0
else
    exit 1
fi
