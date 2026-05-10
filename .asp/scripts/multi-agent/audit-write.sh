#!/usr/bin/env bash
# audit-write.sh — SPEC-004 B1: Stage 2 fail-safe wrapper for audit logs.
#
# Single entry point for any Worker (in worktree or main repo) to append to
# the global audit trail files (.asp-bypass-log.ndjson / .asp-telemetry.ndjson).
# Direct >> append is forbidden — see SPEC-004 §🚨 ASP_AUDIT_ROOT Fail-Safe.
#
# Why a wrapper instead of inline append?
#   1. Centralized validation (one path to harden vs N callers to audit)
#   2. Guarantees ASP_AUDIT_ROOT is checked at every write, not just dispatch
#   3. Makes it observable: future addition of metrics/checksum/rotation is
#      a single-file change
#
# Usage:
#   audit-write.sh <log_type> <json_payload>
#
#   log_type:    "bypass" | "telemetry"
#   json_payload: a single-line JSON object (caller responsibility to escape)
#
# Exit codes:
#   0  success
#   2  bad arguments (missing/invalid log_type or payload)
#   7  ASP_AUDIT_ROOT validation failed (Iron Rule B fail-closed)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/_validate_audit_root.sh"

usage() {
    cat <<EOF >&2
Usage: $0 <log_type> <json_payload>
  log_type:     bypass | telemetry
  json_payload: single-line JSON object
Exit codes: 0=ok, 2=bad args, 7=ASP_AUDIT_ROOT invalid
EOF
}

# ── Stage 0: argument validation ───────────────────────────────────────

if [ "$#" -ne 2 ]; then
    echo "audit-write: expected 2 args, got $#" >&2
    usage
    exit 2
fi

LOG_TYPE="$1"
PAYLOAD="$2"

case "$LOG_TYPE" in
    bypass)      LOG_FILE=".asp-bypass-log.ndjson" ;;
    telemetry)   LOG_FILE=".asp-telemetry.ndjson" ;;
    escalation)  LOG_FILE=".asp-escalation.ndjson" ;;
    *)
        echo "audit-write: unknown log_type '$LOG_TYPE' (expected: bypass|telemetry|escalation)" >&2
        exit 2
        ;;
esac

# Reject empty payload — silent acceptance would hide bugs in callers.
if [ -z "$PAYLOAD" ]; then
    echo "audit-write: payload is empty" >&2
    exit 2
fi

# Reject multi-line payload — NDJSON requires one entry per line.
case "$PAYLOAD" in
    *$'\n'*)
        echo "audit-write: payload contains newline (NDJSON requires single line)" >&2
        exit 2
        ;;
esac

# Reject oversized payload — POSIX O_APPEND atomicity only holds < PIPE_BUF
# (4096 on Linux). Larger writes can interleave under concurrent access.
PAYLOAD_BYTES=$(printf '%s' "$PAYLOAD" | wc -c | tr -d ' ')
if [ "$PAYLOAD_BYTES" -ge 4096 ]; then
    echo "audit-write: payload too large ($PAYLOAD_BYTES bytes, max 4095 for atomic append)" >&2
    exit 2
fi

# ── Stage 2: validate ASP_AUDIT_ROOT (fail-closed, no fallback) ────────

validate_audit_root || exit $?

# ── Append (POSIX O_APPEND, atomic for < PIPE_BUF writes) ──────────────

TARGET="$ASP_AUDIT_ROOT/$LOG_FILE"
printf '%s\n' "$PAYLOAD" >>"$TARGET"
