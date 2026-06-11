#!/usr/bin/env bash
# classify-task.sh — 任務分類 + bug 領域偵測（v5 Phase 2，ADR-015/SPEC-011）
#
# 自 task_orchestrator.md 偽代碼下沉：classify_task()（原 :242-268）與
# detect_bug_domain()（原 :1199-1281）。規則資料 = rules/classification.json。
# 新增 confidence 與 await_required 欄位——hitl:minimal 矛盾的機械側修正：
#   confidence = top_type_hits / total_hits（無命中 → GENERAL, 0.3）
#   await_required = NOT (hitl == minimal AND confidence >= threshold)
#
# 用法：
#   classify-task.sh [--hitl minimal|standard|strict] [--rules FILE] [--domain] "<任務描述>"
#   echo "<任務描述>" | classify-task.sh --stdin [...]
#
# 輸出：單行 JSON（stdout）；錯誤訊息一律 stderr
# 退出碼：0 成功（含 GENERAL fallback）| 2 空輸入/參數錯誤 | 3 rules 檔缺失或非法 | 4 缺 jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES="$SCRIPT_DIR/rules/classification.json"
HITL="standard"
MODE="classify"
USE_STDIN=0
TASK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --hitl) HITL="$2"; shift 2 ;;
    --rules) RULES="$2"; shift 2 ;;
    --domain) MODE="domain"; shift ;;
    --stdin) USE_STDIN=1; shift ;;
    --*) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
    *) TASK="$1"; shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 4; }

[ "$USE_STDIN" = 1 ] && TASK=$(cat)
# 空輸入（含全空白）→ exit 2
if [ -z "${TASK//[[:space:]]/}" ]; then
  echo "ERROR: 任務描述為空。用法：classify-task.sh [--hitl LEVEL] [--domain] \"<描述>\"" >&2
  exit 2
fi
case "$HITL" in minimal|standard|strict) ;; *) echo "ERROR: hitl 值無效：$HITL" >&2; exit 2 ;; esac

if [ ! -f "$RULES" ] || ! jq -e . "$RULES" >/dev/null 2>&1; then
  echo "ERROR: 規則檔缺失或非法 JSON：$RULES" >&2
  exit 3
fi

# ── 關鍵字計數：對 TASK 做大小寫不敏感的子字串比對 ──
count_hits() { # $1 = JSON array of keywords → stdout: 每行一個命中的 keyword
  local kw
  while IFS= read -r kw; do
    [ -n "$kw" ] || continue
    if echo "$TASK" | grep -qiF -- "$kw"; then
      printf '%s\n' "$kw"
    fi
  done < <(jq -r '.[]' <<< "$1")
}

if [ "$MODE" = "domain" ]; then
  # ── bug 領域偵測：依陣列順序（優先序）取第一個命中 ──
  N=$(jq '.bug_domains | length' "$RULES")
  i=0
  while [ "$i" -lt "$N" ]; do
    rule=$(jq -c ".bug_domains[$i]" "$RULES")
    hits=$(count_hits "$(jq -c '.keywords' <<< "$rule")")
    if [ -n "$hits" ]; then
      jq -c '{domain: .domain, add_agents: .add_agents, grep_hint: .grep_hint,
              force_full_test: (.force_full_test // false),
              force_state_scan: (.force_state_scan // false)}' <<< "$rule"
      exit 0
    fi
    i=$((i + 1))
  done
  jq -cn '{domain: "general", add_agents: [], grep_hint: null, force_full_test: false, force_state_scan: false}'
  exit 0
fi

# ── 任務分類：全類計數 → priority 序取最高命中類 ──
THRESHOLD=$(jq -r '.confidence_threshold // 0.8' "$RULES")
TOTAL_HITS=0
BEST_TYPE=""; BEST_HITS=0; BEST_REASON=""; BEST_MATCHED="[]"; BEST_POST="[]"
declare -A TYPE_HITS=()

N=$(jq '.types | length' "$RULES")
i=0
while [ "$i" -lt "$N" ]; do
  rule=$(jq -c ".types[$i] " "$RULES")
  t=$(jq -r '.type' <<< "$rule")
  hits=$(count_hits "$(jq -c '.keywords' <<< "$rule")")
  n=0; [ -n "$hits" ] && n=$(echo "$hits" | grep -c .)
  TYPE_HITS[$t]=$n
  TOTAL_HITS=$((TOTAL_HITS + n))
  # priority 序 = 陣列順序：只在「嚴格更多命中於更高優先類之前未命中」時取代——
  # 即第一個有命中的類勝出（陣列已按 priority 排序），但保留各類計數作 competing
  if [ -z "$BEST_TYPE" ] && [ "$n" -gt 0 ]; then
    BEST_TYPE="$t"; BEST_HITS="$n"
    BEST_REASON=$(jq -r '.reason' <<< "$rule")
    BEST_MATCHED=$(printf '%s\n' "$hits" | jq -Rn '[inputs | select(length>0)]')
    BEST_POST=$(jq -c '.post_checks // []' <<< "$rule")
  fi
  i=$((i + 1))
done

if [ -z "$BEST_TYPE" ]; then
  TYPE=$(jq -r '.fallback.type' "$RULES")
  CONF=$(jq -r '.fallback.confidence' "$RULES")
  REASON=$(jq -r '.fallback.reason' "$RULES")
  MATCHED="[]"; POST="[]"
else
  TYPE="$BEST_TYPE"; REASON="$BEST_REASON"; MATCHED="$BEST_MATCHED"; POST="$BEST_POST"
  CONF=$(awk -v a="$BEST_HITS" -v b="$TOTAL_HITS" 'BEGIN{printf "%.2f", a/b}')
fi

# competing：其他類的命中數（>0 者）
# 注意 pipefail：迴圈最後一個 [ -gt 0 ] 為 false 時會污染 pipeline 退出碼，補 true 歸零
COMPETING=$({ for t in "${!TYPE_HITS[@]}"; do
  [ "$t" = "$TYPE" ] && continue
  [ "${TYPE_HITS[$t]}" -gt 0 ] && printf '%s\t%s\n' "$t" "${TYPE_HITS[$t]}"
done; true; } | jq -Rn '[inputs | select(length>0) | split("\t") | {(.[0]): (.[1]|tonumber)}] | add // {}')

AWAIT=$(awk -v c="$CONF" -v t="$THRESHOLD" -v h="$HITL" \
  'BEGIN{ print (h == "minimal" && c >= t) ? "false" : "true" }')

jq -cn \
  --arg type "$TYPE" --argjson confidence "$CONF" --argjson matched "$MATCHED" \
  --argjson competing "$COMPETING" --arg reason "$REASON" --argjson post "$POST" \
  --argjson await "$AWAIT" --arg hitl "$HITL" --argjson threshold "$THRESHOLD" \
  '{type: $type, confidence: $confidence, matched: $matched, competing: $competing,
    reason: $reason, post_checks: $post, await_required: $await, hitl: $hitl, threshold: $threshold}'
