#!/usr/bin/env bash
# audit-check.sh — 「要不要審計」前置判斷（v5 Phase 2，ADR-015/SPEC-011）
#
# 自 task_orchestrator.md 統一入口 Step 0 下沉：baseline 存在性 / 過期（預設
# 7 天）/ 必要檔案缺失。審計本體仍是 `make audit-health`（不寫第二套）。
#
# 用法：audit-check.sh [--project DIR] [--max-age-days N]
# 輸出：單行 JSON {baseline_exists, age_days, stale, missing_files, audit_required}
# 退出碼：0 = baseline 新鮮且無缺檔 | 2 = 需要審計（無/過期/損毀 baseline 或缺檔）
#         | 4 缺 jq | 1 參數錯誤

set -euo pipefail

PROJECT="."
MAX_AGE_DAYS=7

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --max-age-days) MAX_AGE_DAYS="$2"; shift 2 ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 4; }
[ -d "$PROJECT" ] || { echo "ERROR: project dir not found: $PROJECT" >&2; exit 1; }

BASELINE="$PROJECT/.asp-audit-baseline.json"
EXISTS=false
STALE=false
AGE_DAYS=0

if [ -f "$BASELINE" ] && jq -e . "$BASELINE" >/dev/null 2>&1; then
  EXISTS=true
  LAST=$(jq -r '.last_audit // empty' "$BASELINE")
  if [ -n "$LAST" ]; then
    LAST_TS=$(date -u -d "$LAST" +%s 2>/dev/null || echo 0)
    NOW_TS=$(date -u +%s)
    AGE_DAYS=$(( (NOW_TS - LAST_TS) / 86400 ))
    [ "$AGE_DAYS" -ge "$MAX_AGE_DAYS" ] && STALE=true
  else
    STALE=true
  fi
fi
# 損毀或不存在 → 視同缺失（EXISTS=false 即 audit_required）

MISSING=$(for f in README.md CHANGELOG.md; do
  [ -f "$PROJECT/$f" ] || printf '%s\n' "$f"
done | jq -Rn '[inputs | select(length>0)]')

REQUIRED=false
{ [ "$EXISTS" = false ] || [ "$STALE" = true ] || [ "$(jq 'length' <<< "$MISSING")" -gt 0 ]; } && REQUIRED=true

jq -cn \
  --argjson exists "$EXISTS" --argjson age "$AGE_DAYS" --argjson stale "$STALE" \
  --argjson missing "$MISSING" --argjson required "$REQUIRED" \
  '{baseline_exists: $exists, age_days: $age, stale: $stale, missing_files: $missing, audit_required: $required}'

[ "$REQUIRED" = true ] && exit 2
exit 0
