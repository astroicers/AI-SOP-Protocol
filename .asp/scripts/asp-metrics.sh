#!/usr/bin/env bash
# asp-metrics.sh — v5 瘦身重構基線量測（ADR-013, Phase 0）
#
# 量測三項：
#   1. 各 profile / skill / level 行數與總行數
#   2. 規則清點：grep -cE 'MUST|禁止|🔴' 逐檔計數（pattern 寫入輸出 JSON）
#   3. 三種典型 .ai_profile 組態的 context 稅（= 依 profile-map.yaml 展開
#      後的 Markdown 行數合計；含 requires 遞移展開）
#
# 組態模擬的唯一資料來源 = .asp/config/profile-map.yaml（與 Phase 3
# asp-compile 共用，保證對照組與實驗組量尺一致）。本腳本內禁止硬編碼
# 任何 field→profile 映射。
#
# 用法：
#   bash .asp/scripts/asp-metrics.sh [--repo-root DIR] [--output FILE]
#        [--compare BASELINE.json [--assert-reduction N]]
#        [--simulate "field=value,field=value"] [--quiet]
#
# 退出碼：0 成功 | 1 參數錯誤 | 2 缺 jq | 3 profiles 目錄不存在
#         4 profile-map.yaml 缺失或不可解析 | 5 --assert-reduction 未達標

set -uo pipefail

REPO_ROOT="$(pwd)"
OUTPUT=""
COMPARE=""
SIMULATE=""
ASSERT_REDUCTION=""
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --compare) COMPARE="$2"; shift 2 ;;
    --simulate) SIMULATE="$2"; shift 2 ;;
    --assert-reduction) ASSERT_REDUCTION="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }

PROFILES_DIR="$REPO_ROOT/.asp/profiles"
SKILLS_DIR="$REPO_ROOT/.claude/skills/asp"
LEVELS_DIR="$REPO_ROOT/.asp/levels"
MAP_FILE="$REPO_ROOT/.asp/config/profile-map.yaml"
RULE_PATTERN='MUST|禁止|🔴'

[ -d "$PROFILES_DIR" ] || { echo "ERROR: $PROFILES_DIR not found" >&2; exit 3; }
[ -f "$MAP_FILE" ] || { echo "ERROR: $MAP_FILE not found" >&2; exit 4; }

# ── 解析 profile-map.yaml 的 rules 段（when<TAB>load 對） ──
MAP_RULES=$(awk '
  /^rules:/ { in_rules=1; next }
  /^[a-z_]+:/ { if (!/^rules:/) in_rules=0 }
  in_rules && /- when:/ { line=$0; sub(/.*when:[ ]*"/,"",line); sub(/".*/,"",line); w=line; next }
  in_rules && /load:/   { line=$0; sub(/.*load:[ ]*"/,"",line); sub(/".*/,"",line); print w "\t" line }
' "$MAP_FILE")
[ -n "$MAP_RULES" ] || { echo "ERROR: no rules parsed from $MAP_FILE" >&2; exit 4; }

# ── 行數 / 規則計數工具 ──
count_lines() { awk 'END{print NR}' "$1"; }
count_rules() { grep -cE "$RULE_PATTERN" "$1" 2>/dev/null || true; }

# 收集 dir → "name<TAB>lines<TAB>rules" 清單
collect() { # $1=dir $2=glob
  local f
  for f in "$1"/$2; do
    [ -f "$f" ] || continue
    printf '%s\t%s\t%s\n' "$(basename "$f")" "$(count_lines "$f")" "$(count_rules "$f")"
  done
}

PROFILE_ROWS=$(collect "$PROFILES_DIR" '*.md')
SKILL_ROWS=$([ -d "$SKILLS_DIR" ] && collect "$SKILLS_DIR" '*.md' || true)
LEVEL_ROWS=$([ -d "$LEVELS_DIR" ] && collect "$LEVELS_DIR" '*.yaml' || true)
CLAUDE_MD_LINES=0
[ -f "$REPO_ROOT/CLAUDE.md" ] && CLAUDE_MD_LINES=$(count_lines "$REPO_ROOT/CLAUDE.md")

rows_to_files_json() { # stdin rows → {"name": lines}
  jq -Rn '[inputs | select(length>0) | split("\t") | {(.[0]): (.[1]|tonumber)}] | add // {}'
}
rows_to_rules_json() { # stdin rows → {"name": rules}（僅 >0）
  jq -Rn '[inputs | select(length>0) | split("\t") | select((.[2]|tonumber) > 0) | {(.[0]): (.[2]|tonumber)}] | add // {}'
}
rows_sum() { # $1=column(2|3)
  awk -F'\t' -v c="$1" '{s+=$c} END{print s+0}'
}

# ── level 正規化：數字（v4 legacy）→ 名稱（v5），資料來源 = map 的 level_aliases ──
resolve_level() { # $1=value → stdout 正規名稱（無法解析時原樣輸出）
  case "$1" in
    loose|standard|autonomous) echo "$1"; return ;;
  esac
  local name=""
  name=$(awk -v n="$1" '
    /^level_aliases:/ { in_sec=1; next }
    /^[a-z_]+:/ { if (!/^level_aliases:/) in_sec=0 }
    in_sec && /- "/ {
      line=$0; gsub(/[" -]/,"",line)
      split(line, kv, "=")
      if (kv[1] == n) { print kv[2]; exit }
    }
  ' "$MAP_FILE")
  echo "${name:-$1}"
}

# ── 組態模擬：欄位集 → 載入 profiles（map 命中聯集 + requires 遞移展開） ──
get_requires() { # $1=profile name → stdout: 每行一個 require token
  local f="$PROFILES_DIR/$1.md" line
  [ -f "$f" ] || return 0
  line=$(grep -m1 '<!-- requires:' "$f" 2>/dev/null) || return 0
  line=${line#*requires:}; line=${line%-->*}
  echo "$line" | tr ',' '\n' | while IFS= read -r tok; do
    tok=$(echo "$tok" | awk '{print $1}')
    case "$tok" in
      ''|\(*) continue ;;
      *) echo "$tok" | grep -qE '^[a-z_][a-z0-9_]*$' && echo "$tok" ;;
    esac
  done
}

simulate_config() { # $1="k=v,k=v" → JSON {fields, profiles_loaded, missing_profiles, profile_lines, claude_md_lines, total}
  local spec="$1" loaded="" missing="" queue pair when load cond ok p req
  declare -A FIELDS=() SEEN=()
  IFS=',' read -ra _pairs <<< "$spec"
  for pair in "${_pairs[@]}"; do
    [ -n "$pair" ] || continue
    if [ "${pair%%=*}" = "level" ]; then
      FIELDS[level]="$(resolve_level "${pair#*=}")"
    else
      FIELDS["${pair%%=*}"]="${pair#*=}"
    fi
  done
  # 1) map 命中聯集（保持 map 順序）
  while IFS=$'\t' read -r when load; do
    ok=1
    IFS='&' read -ra _conds <<< "$when"
    for cond in "${_conds[@]}"; do
      [ "${FIELDS[${cond%%=*}]:-}" = "${cond#*=}" ] || { ok=0; break; }
    done
    if [ "$ok" = 1 ]; then
      for p in $load; do
        [ -n "${SEEN[$p]:-}" ] || { SEEN[$p]=1; loaded="$loaded $p"; }
      done
    fi
  done <<< "$MAP_RULES"
  # 2) requires 遞移展開（BFS）
  queue="$loaded"
  while [ -n "$queue" ]; do
    set -- $queue; queue=""
    for p in "$@"; do
      if [ ! -f "$PROFILES_DIR/$p.md" ]; then
        case " $missing " in *" $p "*) ;; *) missing="$missing $p" ;; esac
        continue
      fi
      while IFS= read -r req; do
        [ -n "$req" ] || continue
        [ -n "${SEEN[$req]:-}" ] || { SEEN[$req]=1; loaded="$loaded $req"; queue="$queue $req"; }
      done < <(get_requires "$p")
    done
  done
  # 3) 行數合計（幽靈引用計 0）
  local plines=0 ln
  for p in $loaded; do
    [ -f "$PROFILES_DIR/$p.md" ] || continue
    ln=$(count_lines "$PROFILES_DIR/$p.md"); plines=$((plines + ln))
  done
  jq -n \
    --arg spec "$spec" \
    --arg loaded "$(echo "$loaded" | xargs)" \
    --arg missing "$(echo "$missing" | xargs)" \
    --argjson plines "$plines" \
    --argjson cmd "$CLAUDE_MD_LINES" \
    '{
      fields: ($spec | split(",") | map(select(length>0) | split("=") | {(.[0]): .[1]}) | add // {}),
      profiles_loaded: ($loaded | if length>0 then split(" ") else [] end),
      missing_profiles: ($missing | if length>0 then split(" ") else [] end),
      profile_lines: $plines,
      claude_md_lines: $cmd,
      total: ($plines + $cmd)
    }'
}

# ── --simulate 模式：單一組態，直接輸出 ──
if [ -n "$SIMULATE" ]; then
  simulate_config "$SIMULATE"
  exit 0
fi

# ── 三種典型組態（欄位組合逐字對齊 install.sh apply_preset 1/3/5；
#    L3 加 design（簡報指定 system+design 組態）） ──
CFG_L1="type=content,level=1,mode=auto,workflow=standard,hitl=standard"
CFG_L3="type=system,level=3,mode=auto,workflow=standard,hitl=standard,design=enabled,frontend_quality=enabled,guardrail=enabled,coding_style=enabled"
CFG_L5="type=system,level=5,mode=multi-agent,workflow=vibe-coding,hitl=minimal,autonomous=enabled,orchestrator=enabled,autopilot=enabled,rag=enabled,guardrail=enabled,coding_style=enabled"

TAX_L1=$(simulate_config "$CFG_L1")
TAX_L3=$(simulate_config "$CFG_L3")
TAX_L5=$(simulate_config "$CFG_L5")

# ── 組裝完整 JSON ──
GIT_COMMIT=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
ASP_VERSION=$(cat "$REPO_ROOT/.asp/VERSION" 2>/dev/null || echo "unknown")

RESULT=$(jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg git_commit "$GIT_COMMIT" \
  --arg asp_version "$ASP_VERSION" \
  --arg pattern "$RULE_PATTERN" \
  --argjson profile_files "$(printf '%s\n' "$PROFILE_ROWS" | rows_to_files_json)" \
  --argjson skill_files "$(printf '%s\n' "$SKILL_ROWS" | rows_to_files_json)" \
  --argjson profile_rules "$(printf '%s\n' "$PROFILE_ROWS" | rows_to_rules_json)" \
  --argjson skill_rules "$(printf '%s\n' "$SKILL_ROWS" | rows_to_rules_json)" \
  --argjson profile_total "$(printf '%s\n' "$PROFILE_ROWS" | rows_sum 2)" \
  --argjson skill_total "$(printf '%s\n' "$SKILL_ROWS" | rows_sum 2)" \
  --argjson level_total "$(printf '%s\n' "$LEVEL_ROWS" | rows_sum 2)" \
  --argjson level_count "$(printf '%s\n' "$LEVEL_ROWS" | grep -c . || true)" \
  --argjson rules_total "$(( $(printf '%s\n' "$PROFILE_ROWS" | rows_sum 3) + $(printf '%s\n' "$SKILL_ROWS" | rows_sum 3) ))" \
  --argjson claude_md "$CLAUDE_MD_LINES" \
  --argjson tax_l1 "$TAX_L1" \
  --argjson tax_l3 "$TAX_L3" \
  --argjson tax_l5 "$TAX_L5" \
  '{
    schema_version: 1,
    generated_at: $generated_at,
    git_commit: $git_commit,
    asp_version: $asp_version,
    profiles: { count: ($profile_files | length), total_lines: $profile_total, files: $profile_files },
    skills:   { count: ($skill_files | length),   total_lines: $skill_total,   files: $skill_files },
    levels:   { count: $level_count, total_lines: $level_total },
    claude_md_lines: $claude_md,
    rules: { pattern: $pattern, total: $rules_total, per_profile: $profile_rules, per_skill: $skill_rules },
    context_tax: { L1_content: $tax_l1, L3_system_design: $tax_l3, L5_autonomous: $tax_l5 }
  }')

# ── --compare：對照表（Markdown） ──
if [ -n "$COMPARE" ]; then
  [ -f "$COMPARE" ] || { echo "ERROR: baseline not found: $COMPARE" >&2; exit 1; }
  echo "$RESULT" | jq -r --slurpfile base <(cat "$COMPARE") '
    def pct(b; c): if b == 0 then "n/a" else ((c - b) / b * 100 * 10 | round / 10 | tostring) + "%" end;
    def row(name; b; c): "| \(name) | \(b) | \(c) | Δ \(if c >= b then "+" else "" end)\(c - b) (\(pct(b; c))) |";
    . as $cur | $base[0] as $b |
    [
      "| 指標 | baseline | current | Δ |",
      "|---|---|---|---|",
      row("profiles.count";       $b.profiles.count;       $cur.profiles.count),
      row("profiles.total_lines"; $b.profiles.total_lines; $cur.profiles.total_lines),
      row("skills.total_lines";   $b.skills.total_lines;   $cur.skills.total_lines),
      row("levels.count";         $b.levels.count;         $cur.levels.count),
      row("rules.total";          $b.rules.total;          $cur.rules.total),
      row("context_tax.L1_content";       $b.context_tax.L1_content.total;       $cur.context_tax.L1_content.total),
      row("context_tax.L3_system_design"; $b.context_tax.L3_system_design.total; $cur.context_tax.L3_system_design.total),
      row("context_tax.L5_autonomous";    $b.context_tax.L5_autonomous.total;    $cur.context_tax.L5_autonomous.total)
    ] | .[]'
  if [ -n "$ASSERT_REDUCTION" ]; then
    FAILS=$(echo "$RESULT" | jq -r --slurpfile base <(cat "$COMPARE") --argjson n "$ASSERT_REDUCTION" '
      . as $cur | $base[0] as $b |
      ["L1_content","L3_system_design","L5_autonomous"] | map(
        . as $k |
        ($b.context_tax[$k].total) as $bt | ($cur.context_tax[$k].total) as $ct |
        if $bt > 0 and ((($bt - $ct) / $bt * 100) < $n) then "\($k): \((($bt - $ct) / $bt * 100 * 10 | round / 10))% < \($n)%" else empty end
      ) | .[]')
    if [ -n "$FAILS" ]; then
      echo "" >&2
      echo "ASSERT-REDUCTION FAILED (target ≥ ${ASSERT_REDUCTION}%):" >&2
      echo "$FAILS" >&2
      exit 5
    fi
    [ "$QUIET" = 1 ] || echo "✅ assert-reduction ≥ ${ASSERT_REDUCTION}% — all configs pass" >&2
  fi
  exit 0
fi

# ── 輸出 ──
if [ -n "$OUTPUT" ]; then
  echo "$RESULT" > "$OUTPUT"
  [ "$QUIET" = 1 ] || echo "✅ metrics written to $OUTPUT" >&2
else
  echo "$RESULT"
fi
