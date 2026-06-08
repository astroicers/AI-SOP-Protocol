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

    # Stage D: must be a git repo — verified via `git rev-parse`, which works for
    # plain repos, worktrees, and submodules alike.
    # NB: do NOT shortcut on the mere existence of a `.git` entry — a git worktree's
    # `.git` is a FILE, so `[ ! -e .git ]` is false and the real check would be
    # skipped (the old bug, see ADR-010 Pattern B).
    if ! git -C "$ASP_AUDIT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        echo "ASP_AUDIT_ROOT is not a git repo: $ASP_AUDIT_ROOT" >&2
        return $ASP_AUDIT_ROOT_FAIL_EXIT
    fi

    # Stage D2 (ADR-010 Pattern B, human-approved 2026-06-08): reject a git
    # WORKTREE as the audit root. A worktree's --git-dir (e.g. .git/worktrees/foo)
    # differs from its --git-common-dir (the main repo's .git); in a plain repo or
    # submodule the two are identical. Audit/bypass/escalation NDJSON MUST be
    # written to the MAIN repo (SPEC-004 §🔒 共享狀態檔案路徑策略) — a worktree audit
    # root is silently destroyed by `git worktree remove --force`, breaking Iron
    # Rule B (append-only audit trail). Override only when intentional via
    # ASP_ALLOW_WORKTREE_AUDIT_ROOT=1 (fail-closed by default).
    if [ "${ASP_ALLOW_WORKTREE_AUDIT_ROOT:-}" != "1" ]; then
        local _git_dir _common_dir
        _git_dir=$(git -C "$ASP_AUDIT_ROOT" rev-parse --absolute-git-dir 2>/dev/null)
        _common_dir=$(git -C "$ASP_AUDIT_ROOT" rev-parse --git-common-dir 2>/dev/null)
        # --git-common-dir may be relative; resolve it to an absolute path so the
        # comparison is reliable across git versions.
        case "$_common_dir" in
            /*) ;;
            *) _common_dir=$(cd "$ASP_AUDIT_ROOT" 2>/dev/null && cd "$_common_dir" 2>/dev/null && pwd) ;;
        esac
        if [ -n "$_git_dir" ] && [ -n "$_common_dir" ] && [ "$_git_dir" != "$_common_dir" ]; then
            echo "ASP_AUDIT_ROOT is a git worktree; audit must target the main repo (SPEC-004 §🔒). Set ASP_ALLOW_WORKTREE_AUDIT_ROOT=1 to override: $ASP_AUDIT_ROOT" >&2
            return $ASP_AUDIT_ROOT_FAIL_EXIT
        fi
    fi

    return 0
}
