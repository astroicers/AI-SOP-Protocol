#!/usr/bin/env bash
# inbox-ingest.sh — 回報 .asp-task-inbox.json 的 pending 外部任務（held，不注入）
#
# 使用時機：session-audit.sh 在 SessionStart 時自動呼叫
# 手動執行：bash .asp/scripts/inbox-ingest.sh
#
# SPEC-007（ADR-012 INV-2 / DP8 / T-14）：
#   外部來源任務不得在無人類授權下進入 ROADMAP.yaml。
#   本 script 自 SPEC-007 起「只回報、不注入、不標 ingested」（held）。
#   受控的人類授權路徑由 SPEC-009（triage-accept）/ asp-op pivot 提供。
#
# 規則：
#   1. 只回報 status: pending 的 inbox 任務（保持 pending，留待授權路徑處理）
#   2. 永不寫入 ROADMAP.yaml；永不修改 inbox 檔案
#   3. 永遠 exit 0（不阻擋 session）

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
INBOX_FILE="${PROJECT_DIR}/.asp-task-inbox.json"
LOG_PREFIX="📥 ASP Inbox"

command -v jq &>/dev/null || { echo "${LOG_PREFIX}: jq 未安裝，跳過 inbox 檢查" >&2; exit 0; }

# inbox 不存在 → 靜默退出（正常情況）
[ -f "$INBOX_FILE" ] || exit 0

# inbox 無 pending → 靜默退出
PENDING_COUNT=$(jq '[.[] | select(.status == "pending")] | length' "$INBOX_FILE" 2>/dev/null || echo 0)
[ "$PENDING_COUNT" -gt 0 ] || exit 0

# ── held 回報（SPEC-007：不注入、不標 ingested）──
echo "${LOG_PREFIX}: ⚠️  ${PENDING_COUNT} 個外部任務待人類授權（held）— SPEC-007 已關閉自動注入，授權路徑見 SPEC-009 / asp-op pivot。未注入 ROADMAP。" >&2

while IFS= read -r task_json; do
    TASK_ID=$(echo "$task_json" | jq -r '.id // "INBOX-?"')
    TITLE=$(echo "$task_json" | jq -r '.title // "Untitled"')
    SOURCE_REF=$(echo "$task_json" | jq -r '.source.ref // ""')
    echo "${LOG_PREFIX}:   ⏸️  held: ${TASK_ID}「${TITLE}」(${SOURCE_REF})" >&2
done < <(jq -c '.[] | select(.status == "pending")' "$INBOX_FILE" 2>/dev/null)

exit 0
