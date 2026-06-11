#!/usr/bin/env bash
# rule-stats.sh — 規則命中率統計（v5 ADR-018 方案 A）
#
# 從 rule-registry.yaml 枚舉全部 rule_id（零命中必出現），統計：
#   - session-audit 類：~/.claude/asp/metrics/rule-hits.jsonl（90 天窗）
#   - gate-log 類：./.asp-gate-log/*.md 的 `gate:` frontmatter（機械統計）
# disposition：active｜待刪候選（零命中∧非 exempt∧observed_by∉{none,manual}）
#              ｜不可觀測（none/manual）｜鐵則豁免（exempt）
#
# 用法：rule-stats.sh [--days N(=90)] [--project NAME]
# env：ASP_RULE_REGISTRY / ASP_METRICS_FILE / ASP_GATE_LOG_DIR 可覆寫（測試用）
# 退出碼：0 正常（含有待刪候選）| 2 registry 缺失或不可解析

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY="${ASP_RULE_REGISTRY:-$SCRIPT_DIR/../config/rule-registry.yaml}"
METRICS="${ASP_METRICS_FILE:-$HOME/.claude/asp/metrics/rule-hits.jsonl}"
GATE_LOG_DIR="${ASP_GATE_LOG_DIR:-./.asp-gate-log}"
DAYS=90
PROJECT_FILTER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --project) PROJECT_FILTER="$2"; shift 2 ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
[ -f "$REGISTRY" ] || { echo "ERROR: rule-registry not found: $REGISTRY" >&2; exit 2; }

# registry 解析：id<TAB>observed_by<TAB>exempt<TAB>enabled_since
RULES=$(awk '
  /^  - id: /        { if (id != "") print id "\t" ob "\t" ex "\t" es; id=$3; ob="?"; ex="false"; es="-" }
  /observed_by: /    { ob=$2 }
  /exempt: true/     { ex="true" }
  /enabled_since: /  { es=$2; gsub(/"/,"",es) }
  END                { if (id != "") print id "\t" ob "\t" ex "\t" es }
' "$REGISTRY")
[ -n "$RULES" ] || { echo "ERROR: no rules parsed from $REGISTRY" >&2; exit 2; }

CUTOFF=$(date -u -d "$DAYS days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ)

# jsonl 聚合（窗內，optional project filter）：rule_id<TAB>hits<TAB>last_hit
HITS=""
if [ -f "$METRICS" ]; then
  HITS=$(jq -r --arg cutoff "$CUTOFF" --arg proj "$PROJECT_FILTER" '
    select(.ts >= $cutoff) | select($proj == "" or .project == $proj) | .rule_id + "\t" + .ts
  ' "$METRICS" 2>/dev/null | sort | awk -F'\t' '
    { count[$1]++; if ($2 > last[$1]) last[$1] = $2 }
    END { for (k in count) print k "\t" count[k] "\t" last[k] }
  ')
fi

# gate-log 聚合：GATE-Gn<TAB>count<TAB>last（以檔名 ISO 時戳判窗）
GATE_HITS=""
if [ -d "$GATE_LOG_DIR" ]; then
  CUTOFF_COMPACT=$(echo "$CUTOFF" | tr -d ':-')
  GATE_HITS=$(for f in "$GATE_LOG_DIR"/*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    ts="${base%%-*}"
    [ "$ts" \> "$CUTOFF_COMPACT" ] || [ "$ts" = "$CUTOFF_COMPACT" ] || continue
    g=$(grep -m1 '^gate: ' "$f" 2>/dev/null | awk '{print $2}')
    [ -n "$g" ] && printf 'GATE-%s\t%s\n' "$g" "$ts"
  done | sort | awk -F'\t' '
    { count[$1]++; if ($2 > last[$1]) last[$1] = $2 }
    END { for (k in count) print k "\t" count[k] "\t" last[k] }
  ')
fi

lookup() { # $1=id $2=data → "hits<TAB>last"
  echo "$2" | awk -F'\t' -v id="$1" '$1 == id { print $2 "\t" $3; found=1 } END { if (!found) print "0\t-" }'
}

echo ""
echo "📊 ASP Rule Hit Stats（近 ${DAYS} 天${PROJECT_FILTER:+，project=$PROJECT_FILTER}）"
echo "═══════════════════════════════════════════════════════════"
printf '%-22s | %5s | %-20s | %s\n' "rule_id" "hits" "last_hit" "disposition"
printf -- '─%.0s' {1..75}; echo ""

CANDIDATES=""
CUTOFF_DATE="${CUTOFF%%T*}"
while IFS=$'\t' read -r id ob ex es; do
  case "$ob" in
    gate-log) HL=$(lookup "$id" "$GATE_HITS") ;;
    *)        HL=$(lookup "$id" "$HITS") ;;
  esac
  N="${HL%%$'\t'*}"; LAST="${HL##*$'\t'}"
  if [ "$ex" = "true" ]; then
    DISP="鐵則豁免"
  elif [ "$ob" = "none" ] || [ "$ob" = "manual" ]; then
    DISP="不可觀測（$ob）"
  elif [ "$N" = "0" ]; then
    # F-9 累積期保護：enabled_since 晚於統計窗起點 → 資料累積期，非待刪訊號
    if [ "$es" != "-" ] && [ "$es" \> "$CUTOFF_DATE" ]; then
      DISP="資料累積期（since $es）"
    else
      DISP="待刪候選"
      CANDIDATES="$CANDIDATES $id"
    fi
  else
    DISP="active"
  fi
  printf '%-22s | %5s | %-20s | %s\n' "$id" "$N" "$LAST" "$DISP"
done <<< "$RULES"

echo ""
if [ -n "$CANDIDATES" ]; then
  echo "🗑  待刪候選（${DAYS} 天零命中，下個 minor 版本評估移除——移除動作仍走 ADR）："
  for c in $CANDIDATES; do echo "   - $c"; done
  echo "   注意：GATE-G3..G6 的 gate-log 記錄自 v5 起累積，初期零命中屬資料累積期（ADR-018）。"
else
  echo "✅ 無待刪候選——所有可觀測規則於窗內皆有命中。"
fi
echo ""
exit 0
