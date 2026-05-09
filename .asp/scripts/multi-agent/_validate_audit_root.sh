#!/usr/bin/env bash
# _validate_audit_root.sh — SPEC-004 Stage 1+2 ASP_AUDIT_ROOT 驗證
#
# 提供共享函式 validate_audit_root，被 audit-write.sh 與 dispatch.sh 共用。
#
# 設計原則：fail-closed。任何驗證失敗 → caller 必須 abort，禁止 fallback。
# 詳見 docs/specs/SPEC-004-multi-agent-worktree-isolation.md
# §🚨 ASP_AUDIT_ROOT Fail-Safe 規格.

# Exit code 7 is the SPEC-004 sentinel for ASP_AUDIT_ROOT validation failure.
ASP_AUDIT_ROOT_FAIL_EXIT=7

# validate_audit_root: prints nothing on success, prints reason to stderr on
# failure. Returns 0 on pass, 7 on fail.
#
# Validation order matters: cheapest checks first, so callers see the most
# fundamental problem before deeper ones. (e.g. unset is reported before
# "not absolute".)
validate_audit_root() {
    # Stage A: must be set and non-empty
    if [ -z "${ASP_AUDIT_ROOT:-}" ]; then
        echo "ASP_AUDIT_ROOT must be set (Iron Rule B requirement, SPEC-004)" >&2
        return $ASP_AUDIT_ROOT_FAIL_EXIT
    fi

    # Stage B: must be absolute (start with /)
    case "$ASP_AUDIT_ROOT" in
        /*) ;;
        *)
            echo "ASP_AUDIT_ROOT must be absolute path (got: $ASP_AUDIT_ROOT)" >&2
            return $ASP_AUDIT_ROOT_FAIL_EXIT
            ;;
    esac

    # Stage C: path must exist and be a directory
    if [ ! -d "$ASP_AUDIT_ROOT" ]; then
        echo "ASP_AUDIT_ROOT path not found or not a directory: $ASP_AUDIT_ROOT" >&2
        return $ASP_AUDIT_ROOT_FAIL_EXIT
    fi

    # Stage D: must be a git repo (has .git/ directory or file, or is recognized
    # by git rev-parse). We check for .git/ first because it's cheap and avoids
    # spawning a git process when obvious.
    if [ ! -e "$ASP_AUDIT_ROOT/.git" ]; then
        # Fall through to git rev-parse for edge cases (e.g. submodules, where
        # .git is a file pointing elsewhere). git -C exits non-zero if not a
        # repo.
        if ! git -C "$ASP_AUDIT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
            echo "ASP_AUDIT_ROOT is not a git repo (no .git/ found): $ASP_AUDIT_ROOT" >&2
            return $ASP_AUDIT_ROOT_FAIL_EXIT
        fi
    fi

    return 0
}
