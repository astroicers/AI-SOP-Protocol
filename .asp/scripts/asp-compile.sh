#!/usr/bin/env bash
# asp-compile.sh — Profile 依賴解析編譯器（v5 Phase 3，ADR-016）
#
# 把 .ai_profile → profile 載入集合的解析從 LLM runtime 移到編譯期：
#   選集（profile-map.yaml rules）→ requires DFS 後序展開（拓撲序、循環偵測）
#   → 衝突兩段式裁決（ADR-014 D3/D8）→ 產出 .asp-compiled-profile.md（gitignored）。
#
# 用法：
#   asp-compile.sh [--project DIR] [--asp-root DIR] [--profile FILE]
#                  [--check] [--list] [--quiet]
#   --check : 產物比 .ai_profile / map / 來源 profile / 本腳本都新 → fresh 不重編
#   --list  : 只印「選集 + requires 展開」後的集合（衝突裁決前——與 asp-metrics
#             --simulate 的 profiles_loaded 契約鎖定），不寫產物
#
# 退出碼：0 成功/fresh | 1 conflicts | 2 .ai_profile 缺失或欄位驗證失敗
#         | 3 map 缺失/不可解析 | 5 requires 循環 | 6 缺 jq

set -uo pipefail

PROJECT="."
ASPR=""
PROFILE=""
CHECK=0
LIST=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --asp-root) ASPR="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --check) CHECK=1; shift ;;
    --list) LIST=1; shift ;;
    --quiet) QUIET=1; shift ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 6; }

[ -n "$ASPR" ] || { if [ -d "$PROJECT/.asp" ]; then ASPR="$PROJECT/.asp"; else ASPR="$HOME/.claude/asp"; fi; }
[ -n "$PROFILE" ] || PROFILE="$PROJECT/.ai_profile"
MAP_FILE="$ASPR/config/profile-map.yaml"
PROFILES_DIR="$ASPR/profiles"
ARTIFACT="$PROJECT/.asp-compiled-profile.md"

say() { [ "$QUIET" = 1 ] || echo "$@"; }

[ -f "$PROFILE" ] || { echo "ERROR: .ai_profile not found: $PROFILE" >&2; exit 2; }
[ -f "$MAP_FILE" ] || { echo "ERROR: profile-map not found: $MAP_FILE" >&2; exit 3; }

# ── map 解析（與 asp-metrics 同文法；無規則 = 不可解析） ──
MAP_RULES=$(awk '
  /^rules:/ { in_rules=1; next }
  /^[a-z_]+:/ { if (!/^rules:/) in_rules=0 }
  in_rules && /- when:/ { line=$0; sub(/.*when:[ ]*"/,"",line); sub(/".*/,"",line); w=line; next }
  in_rules && /load:/   { line=$0; sub(/.*load:[ ]*"/,"",line); sub(/".*/,"",line); print w "\t" line }
' "$MAP_FILE")
[ -n "$MAP_RULES" ] || { echo "ERROR: no rules parsed from $MAP_FILE" >&2; exit 3; }

# ── 欄位驗證（不複寫驗證邏輯）；error → exit 2 ──
# ASP_COMPILE_SKIP_VALIDATE=1：呼叫端（如 validate-profile.sh 自身印載入清單時）
# 已在做欄位驗證，跳過此處二次驗證以打破 validate ↔ compile 互呼遞迴（ADR-013 Phase 3）
if [ "${ASP_COMPILE_SKIP_VALIDATE:-0}" != "1" ] && [ -f "$ASPR/scripts/validate-profile.sh" ]; then
  if ! (cd "$PROJECT" && bash "$ASPR/scripts/validate-profile.sh" "$PROFILE" >/dev/null 2>&1); then
    echo "ERROR: .ai_profile 欄位驗證失敗（執行 make profile-validate 看細節）" >&2
    exit 2
  fi
fi

# ── 欄位讀取 + level 正規化 ──
get_field() { grep "^${1}:" "$PROFILE" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'"; }
declare -A FIELDS=()
while IFS= read -r line; do
  case "$line" in
    \#*|'') continue ;;
    *:*) k="${line%%:*}"; v=$(echo "${line#*:}" | awk '{print $1}' | tr -d '"' | tr -d "'")
         [ -n "$k" ] && [ -n "$v" ] && FIELDS["$k"]="$v" ;;
  esac
done < "$PROFILE"
if [ -n "${FIELDS[level]:-}" ] && [ -f "$ASPR/scripts/level-resolve.sh" ]; then
  RESOLVED=$(bash "$ASPR/scripts/level-resolve.sh" "${FIELDS[level]}" 2>/dev/null) || RESOLVED=""
  [ -n "$RESOLVED" ] && FIELDS[level]="$RESOLVED"
fi

# ── 選集：map 命中聯集（記錄各 profile 的來源 when，供衝突裁決） ──
declare -A SEEN=() VIA=()
ORDER=""
while IFS=$'\t' read -r when load; do
  ok=1
  IFS='&' read -ra conds <<< "$when"
  for cond in "${conds[@]}"; do
    [ "${FIELDS[${cond%%=*}]:-}" = "${cond#*=}" ] || { ok=0; break; }
  done
  if [ "$ok" = 1 ]; then
    for p in $load; do
      VIA[$p]="${VIA[$p]:-}|$when"
      [ -n "${SEEN[$p]:-}" ] || { SEEN[$p]=1; ORDER="$ORDER $p"; }
    done
  fi
done <<< "$MAP_RULES"

# ── requires DFS 後序展開（拓撲序；循環 → exit 5；幽靈 → WARNING） ──
get_requires() { # $1=name
  local f="$PROFILES_DIR/$1.md" line
  [ -f "$f" ] || return 0
  line=$(grep -m1 '<!-- requires:' "$f" 2>/dev/null) || return 0
  line=${line#*requires:}; line=${line%-->*}
  echo "$line" | tr ',' '\n' | while IFS= read -r tok; do
    tok=$(echo "$tok" | awk '{print $1}')
    case "$tok" in ''|\(*) continue ;; *) echo "$tok" | grep -qE '^[a-z_][a-z0-9_]*$' && echo "$tok" ;; esac
  done
}
get_conflicts() { # $1=name
  local f="$PROFILES_DIR/$1.md" line
  [ -f "$f" ] || return 0
  line=$(grep -m1 '<!-- conflicts:' "$f" 2>/dev/null) || return 0
  line=${line#*conflicts:}; line=${line%-->*}
  echo "$line" | tr ',' '\n' | while IFS= read -r tok; do
    tok=$(echo "$tok" | awk '{print $1}')
    case "$tok" in ''|\(*) continue ;; *) echo "$tok" | grep -qE '^[a-z_][a-z0-9_]*$' && echo "$tok" ;; esac
  done
}

TOPO=""
declare -A STATE=()   # ""=unvisited, V=visiting, D=done
GHOSTS=""
visit() { # $1=name；回傳非 0 = 循環
  local n="$1" req
  case "${STATE[$n]:-}" in
    D) return 0 ;;
    V) echo "ERROR: requires 循環偵測：$n" >&2; return 5 ;;
  esac
  if [ ! -f "$PROFILES_DIR/$n.md" ]; then
    case " $GHOSTS " in *" $n "*) ;; *) GHOSTS="$GHOSTS $n" ;; esac
    STATE[$n]=D
    return 0
  fi
  STATE[$n]=V
  while IFS= read -r req; do
    [ -n "$req" ] || continue
    visit "$req" || return $?
  done < <(get_requires "$n")
  STATE[$n]=D
  TOPO="$TOPO $n"
  return 0
}
for p in $ORDER; do
  visit "$p" || exit 5
done

# ── --list：契約輸出（衝突裁決前的展開集合，不含幽靈） ──
if [ "$LIST" = 1 ]; then
  for p in $TOPO; do echo "$p"; done
  for g in $GHOSTS; do echo "WARNING: 幽靈引用（無對應檔案，已忽略）：$g" >&2; done
  exit 0
fi

# ── 衝突兩段式裁決（ADR-014 D3/D8） ──
FINAL="$TOPO"
for p in $TOPO; do
  case " $FINAL " in *" $p "*) ;; *) continue ;; esac
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    case " $FINAL " in *" $c "*) ;; *) continue ;; esac
    # p 宣告與 c 衝突，且兩者都在載入集
    p_derived=0
    case "${VIA[$p]:-}" in *"workflow=vibe-coding"*) p_derived=1 ;; esac
    case "${VIA[$p]:-}" in *"level="*) p_derived=0 ;; esac
    if [ "$p_derived" = 1 ]; then
      echo "WARNING: $p（由 workflow=vibe-coding 衍生）與 $c 衝突 → 丟棄 $p（保留較嚴格者，ADR-014 D3/D8）" >&2
      FINAL=$(echo " $FINAL " | sed "s/ $p / /g" | xargs)
      break
    else
      echo "ERROR: profile 衝突：$p × $c（.ai_profile 設定互斥——顯式 level/欄位組合，無法自動裁決）" >&2
      echo "       修法：移除其一（例如 autopilot: disabled，或 level 改 standard/autonomous）" >&2
      exit 1
    fi
  done < <(get_conflicts "$p")
done

# ── --check：mtime 比對（單一實作點） ──
if [ "$CHECK" = 1 ] && [ -f "$ARTIFACT" ]; then
  ART_TS=$(stat -c %Y "$ARTIFACT" 2>/dev/null || echo 0)
  NEWEST=0
  for f in "$PROFILE" "$MAP_FILE" "$0"; do
    ts=$(stat -c %Y "$f" 2>/dev/null || echo 0); [ "$ts" -gt "$NEWEST" ] && NEWEST=$ts
  done
  for p in $FINAL; do
    f="$PROFILES_DIR/$p.md"
    [ -f "$f" ] || continue
    ts=$(stat -c %Y "$f" 2>/dev/null || echo 0); [ "$ts" -gt "$NEWEST" ] && NEWEST=$ts
  done
  if [ "$ART_TS" -ge "$NEWEST" ]; then
    say "✅ compiled profile fresh（$ARTIFACT，無需重編）"
    exit 0
  fi
fi

# ── 產出 ──
TMP_BODY=$(mktemp)
trap 'rm -f "$TMP_BODY"' EXIT
SOURCES=""
for p in $FINAL; do
  f="$PROFILES_DIR/$p.md"
  [ -f "$f" ] || continue
  n=$(awk 'END{print NR}' "$f")
  SOURCES="$SOURCES $p($n)"
  {
    echo ""
    echo "<!-- ─── profile: $p ($n lines) ─── -->"
    echo ""
    cat "$f"
  } >> "$TMP_BODY"
done
for g in $GHOSTS; do
  echo "WARNING: 幽靈引用（無對應檔案，已忽略）：$g" >&2
done

ASP_VERSION=$(cat "$ASPR/VERSION" 2>/dev/null || echo unknown)
MAP_VERSION=$(grep -m1 '^version:' "$MAP_FILE" | awk '{print $2}')
BODY_LINES=$(awk 'END{print NR}' "$TMP_BODY")
TOTAL_LINES=$((BODY_LINES + 9))

{
  echo "<!-- ═══ ASP COMPILED PROFILE — generated by asp-compile.sh (ADR-016); DO NOT EDIT ═══"
  echo "compiled_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "asp_version: $ASP_VERSION"
  echo "map_version: ${MAP_VERSION:-unknown}"
  echo "sources:$SOURCES"
  echo "total_lines: $TOTAL_LINES"
  echo "fallback: 本檔不存在或過期時，依 CLAUDE.md 映射載入散文 profile"
  echo "═══ -->"
  cat "$TMP_BODY"
} > "$ARTIFACT"

if [ "$TOTAL_LINES" -gt 2500 ]; then
  echo "WARNING: 編譯產物 $TOTAL_LINES 行 > 2,500 門檻——考慮收斂 .ai_profile 啟用面（ADR-016）" >&2
fi
say "✅ compiled → $ARTIFACT（${TOTAL_LINES} 行，sources:$SOURCES）"
exit 0
