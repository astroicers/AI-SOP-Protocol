#!/usr/bin/env bash
# POC-1: 行數棘輪 gate（ADR-022）—— demonstrable proof。
# ⚠️ 探索性 POC，非生產強制：本檔不接進 CI / commit gate（生產強制屬 ADR Accepted 後）。
# 邏輯: current profiles.total_lines > baseline 且無豁免 → exit 1（gate red）; 否則 exit 0。
# 複用既有真實 metric（asp-metrics.sh），不重實作行數計算，避免 metric 漂移。
#
# 用法:
#   bash docs/research/poc1-linecount-ratchet-probe.sh              # 用 asp-metrics 現值
#   bash docs/research/poc1-linecount-ratchet-probe.sh --current N  # 覆寫現值（demo violation，不必真灌肥檔）
#   ASP_COMPLEXITY_BUDGET_OK=1 bash ... --current N                 # 豁免（ADR 認列逃生門的 POC 代理）
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASELINE_JSON="$REPO_ROOT/.asp-metrics-baseline.json"
METRICS="$REPO_ROOT/.asp/scripts/asp-metrics.sh"
EXEMPT="${ASP_COMPLEXITY_BUDGET_OK:-0}"

CURRENT_OVERRIDE=""
[ "${1:-}" = "--current" ] && CURRENT_OVERRIDE="${2:-}"

command -v jq >/dev/null || { echo "POC-1: 缺 jq" >&2; exit 3; }
baseline=$(jq -r '.profiles.total_lines' "$BASELINE_JSON")

if [ -n "$CURRENT_OVERRIDE" ]; then
  current="$CURRENT_OVERRIDE"
else
  current=$(bash "$METRICS" 2>/dev/null | jq -r '.profiles.total_lines')
fi

echo "行數棘輪: current=$current  baseline=$baseline  exempt=$EXEMPT"

if [ "$current" -gt "$baseline" ]; then
  if [ "$EXEMPT" = "1" ]; then
    echo "⚠️ 超過 baseline 但有豁免（ASP_COMPLEXITY_BUDGET_OK=1，須附認列複雜度的 ADR）→ 放行 exit 0"
    exit 0
  fi
  echo "❌ VIOLATION: profiles.total_lines $current > baseline $baseline → 治理複雜度膨脹，gate red"
  echo "   修法: 砍等量行數，或附一份認列複雜度增加的 ADR（ASP_COMPLEXITY_BUDGET_OK=1）"
  exit 1
fi

echo "✅ PASS: $current ≤ $baseline（複雜度未超 baseline）"
exit 0
