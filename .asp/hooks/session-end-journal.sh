#!/usr/bin/env bash
# ASP SessionEnd Hook: session-end-journal.sh  (SPEC-014 / ADR-026 Feature A)
#
# 把本 session 的機械事實（commits / files / gates / test_status）+ 人工 note
# append 一行 JSON 到 .asp-session-journal.jsonl（append-only, gitignored）。
# 由 session-audit.sh 在下次 SessionStart 讀 tail-N 注入 → 關掉「經驗寫了沒人讀」缺口。
#
# 設計鐵則：
#   - Claude Code 忽略 SessionEnd 的 stdout / exit code（官方）→ 本 hook 為純副作用。
#   - 恆 exit 0，永不阻擋 session 結束。
#   - 無實質內容（無 commit/note/gate/test）不寫空條目，避免噪音。
#   - notes / observations only，永不等同 ADR（決策記憶走 ADR 人類把關）。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
JOURNAL="${PROJECT_DIR}/.asp-session-journal.jsonl"
MARKER="${PROJECT_DIR}/.asp-session-marker.json"
NOTES="${PROJECT_DIR}/.asp-session-notes.tmp"

command -v jq >/dev/null 2>&1 || exit 0

# ─── git 狀態 ───
git_ok=false
if command -v git >/dev/null 2>&1 && git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    git_ok=true
fi

HEAD_AFTER=""; BRANCH=""
if $git_ok; then
    HEAD_AFTER=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "")
    BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
fi

# ─── marker（SessionStart 寫入，供 diff 基準）───
HEAD_BEFORE=""
if [ -f "$MARKER" ]; then
    HEAD_BEFORE=$(jq -r '.head // empty' "$MARKER" 2>/dev/null || echo "")
    [ -z "$BRANCH" ] && BRANCH=$(jq -r '.branch // empty' "$MARKER" 2>/dev/null || echo "")
fi

# ─── commits + 改檔數（僅在 git 可用且 before≠after 時）───
COMMITS_JSON='[]'; FILES_COUNT=0
if $git_ok && [ -n "$HEAD_BEFORE" ] && [ -n "$HEAD_AFTER" ] && [ "$HEAD_BEFORE" != "$HEAD_AFTER" ]; then
    COMMITS_JSON=$(git -C "$PROJECT_DIR" log --format=%s "${HEAD_BEFORE}..${HEAD_AFTER}" 2>/dev/null \
        | jq -R . | jq -s . 2>/dev/null || echo '[]')
    FILES_COUNT=$(git -C "$PROJECT_DIR" diff --name-only "${HEAD_BEFORE}..${HEAD_AFTER}" 2>/dev/null \
        | wc -l | tr -d ' ')
fi
[ -z "$COMMITS_JSON" ] && COMMITS_JSON='[]'
[ -z "$FILES_COUNT" ] && FILES_COUNT=0

# ─── 本 session 新增的 gate-log（mtime 新於 marker；basename 以 sed 取，跨平台）───
GATES_JSON='[]'
if [ -d "$PROJECT_DIR/.asp-gate-log" ] && [ -f "$MARKER" ]; then
    GATES_JSON=$(find "$PROJECT_DIR/.asp-gate-log" -type f -newer "$MARKER" 2>/dev/null \
        | sed 's#.*/##' | jq -R . | jq -s . 2>/dev/null || echo '[]')
fi
[ -z "$GATES_JSON" ] && GATES_JSON='[]'

# ─── test_status ───
TEST_STATUS='null'
if [ -f "$PROJECT_DIR/.asp-test-result.json" ]; then
    if jq -e '.passed==true'  "$PROJECT_DIR/.asp-test-result.json" >/dev/null 2>&1; then
        TEST_STATUS='"passed"'
    elif jq -e '.passed==false' "$PROJECT_DIR/.asp-test-result.json" >/dev/null 2>&1; then
        TEST_STATUS='"failed"'
    fi
fi

# ─── 人工 notes（每行一條，make journal-note 暫存）───
NOTES_JSON='[]'
if [ -f "$NOTES" ]; then
    NOTES_JSON=$(grep . "$NOTES" 2>/dev/null | jq -R . | jq -s . 2>/dev/null || echo '[]')
fi
[ -z "$NOTES_JSON" ] && NOTES_JSON='[]'

# ─── 無實質內容 → 不寫空條目，僅清理 ───
if [ "$COMMITS_JSON" = '[]' ] && [ "$NOTES_JSON" = '[]' ] \
   && [ "$GATES_JSON" = '[]' ] && [ "$TEST_STATUS" = 'null' ]; then
    rm -f "$MARKER" "$NOTES" 2>/dev/null || true
    exit 0
fi

# ─── 組裝並 append 一行 JSON ───
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LINE=$(jq -cn \
    --arg ts "$TS" --arg branch "$BRANCH" \
    --arg hb "$HEAD_BEFORE" --arg ha "$HEAD_AFTER" \
    --argjson commits "$COMMITS_JSON" --argjson files "$FILES_COUNT" \
    --argjson gates "$GATES_JSON" --argjson notes "$NOTES_JSON" \
    --argjson test "$TEST_STATUS" \
    '{ts:$ts,branch:$branch,head_before:$hb,head_after:$ha,commits:$commits,files_changed_count:$files,gates:$gates,test_status:$test,notes:$notes}' \
    2>/dev/null) || LINE=""

if [ -n "$LINE" ]; then
    printf '%s\n' "$LINE" >> "$JOURNAL" 2>/dev/null || true
fi

rm -f "$MARKER" "$NOTES" 2>/dev/null || true
exit 0
