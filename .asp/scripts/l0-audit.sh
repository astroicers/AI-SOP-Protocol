#!/usr/bin/env bash
# L0 Spike Lifecycle Audit
# Usage: bash .asp/scripts/l0-audit.sh [project-dir]
#        make asp-l0-audit
#
# Detects Zombie L0 vs Active L0, checks Promotion Gate triggers.
# Exit 0 always (non-blocking diagnostic tool).

set -uo pipefail

PROJECT_DIR="${1:-.}"
AI_PROFILE="${PROJECT_DIR}/.ai_profile"

echo "=== L0 Lifecycle Audit: $(basename "$(realpath "$PROJECT_DIR")") ==="

# Check if .ai_profile exists
if [ ! -f "$AI_PROFILE" ]; then
    echo "No .ai_profile — not an ASP-governed project, skipping L0 audit"
    exit 0
fi

RAW_LEVEL=$(grep "^level:" "$AI_PROFILE" 2>/dev/null | awk '{print $2}' | tr -d '"')
LEVEL=$(bash "$(dirname "$0")/level-resolve.sh" "$RAW_LEVEL" 2>/dev/null || echo "")
if [ "$LEVEL" != "loose" ]; then
    echo "Level: ${RAW_LEVEL:-unknown} — not loose, audit not applicable"
    exit 0
fi

echo "Level: loose (spike/exploration lifecycle audit; v5 併自 L0)"
echo ""

DAYS_SINCE=0

# --- Promotion Gate Checks ---
echo "## Promotion Gate Triggers"

# Trigger 1: External committer
if git -C "$PROJECT_DIR" log --all --format='%ae' 2>/dev/null | sort -u | grep -v "$(git -C "$PROJECT_DIR" config user.email 2>/dev/null)" | grep -q "@"; then
    echo "  WARNING: External committer detected — must evaluate upgrade to L1"
else
    echo "  OK: No external committers"
fi

# Trigger 2: 60-day clock
FIRST_COMMIT_DATE=$(git -C "$PROJECT_DIR" log --reverse --format='%ci' 2>/dev/null | head -1)
if [ -n "$FIRST_COMMIT_DATE" ]; then
    NOW_S=$(date +%s)
    FIRST_S=$(date -d "$FIRST_COMMIT_DATE" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S %z" "$FIRST_COMMIT_DATE" +%s 2>/dev/null || echo "$NOW_S")
    DAYS_SINCE=$(( (NOW_S - FIRST_S) / 86400 ))
    if [ "$DAYS_SINCE" -gt 60 ]; then
        echo "  WARNING: Repo is ${DAYS_SINCE} days old (>60) — audit active vs zombie"
    else
        echo "  OK: Repo age ${DAYS_SINCE} days (<=60)"
    fi
fi

echo ""
echo "## Active vs Zombie Diagnosis"

# Q1: Recent commits?
RECENT_COMMITS=$(git -C "$PROJECT_DIR" log --since="30 days ago" --oneline 2>/dev/null | wc -l)
if [ "$RECENT_COMMITS" -gt 0 ]; then
    echo "  OK: Active — $RECENT_COMMITS commits in last 30 days"
else
    echo "  WARNING: Zombie signal — 0 commits in last 30 days"
fi

# Q2: File complexity
TOTAL_FILES=$(git -C "$PROJECT_DIR" ls-files 2>/dev/null | wc -l)
if [ "$TOTAL_FILES" -gt 200 ]; then
    echo "  WARNING: Complexity signal — $TOTAL_FILES tracked files (>200 for a spike?)"
else
    echo "  OK: File count $TOTAL_FILES (reasonable for L0)"
fi

echo ""
echo "## Recommendation"
if [ "$RECENT_COMMITS" -gt 0 ] && [ "$DAYS_SINCE" -le 60 ]; then
    echo "  Active L0 — no action required"
elif [ "$RECENT_COMMITS" -eq 0 ]; then
    echo "  Zombie L0 — decide: upgrade to L1 or archive/delete"
else
    echo "  Long-running L0 — review graduation checklist: docs/level0-spike-mode.md"
fi

echo ""
echo "Reference: docs/level0-spike-mode.md"
