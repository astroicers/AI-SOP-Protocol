#!/usr/bin/env bash
# level-resolve.sh — v5 成熟度等級名稱解析（ADR-014, Phase 1）
#
# 數字等級（v4 遺留 0-5）→ v5 名稱等級（loose | standard | autonomous）的
# 中央映射實作。所有解析 level 的位置（validate-profile.sh、Makefile.inc、
# install.sh、l0-audit.sh、asp-level skill）一律經由本腳本，禁止各自映射。
#
# 用法：
#   bash .asp/scripts/level-resolve.sh <value>   # value = loose|standard|autonomous|0-5
#   bash .asp/scripts/level-resolve.sh           # 無參數：讀 ./.ai_profile 的 level:
#
# 輸出：stdout = 正規名稱；數字輸入時 stderr 印 deprecation 提示
# 退出碼：0 解析成功 | 1 無效值 | 2 無參數且 .ai_profile 缺 level 欄位
# 資料來源：profile-map.yaml 的 level_aliases 段（env ASP_PROFILE_MAP 可覆寫；
#           缺檔時 fallback 內建表並印 stderr 警告）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAP_FILE="${ASP_PROFILE_MAP:-$SCRIPT_DIR/../config/profile-map.yaml}"

VALUE="${1:-}"
if [ -z "$VALUE" ]; then
  if [ -f ".ai_profile" ]; then
    VALUE=$(grep '^level:' .ai_profile 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'")
  fi
  [ -n "$VALUE" ] || exit 2
fi

# 名稱直通
case "$VALUE" in
  loose|standard|autonomous) echo "$VALUE"; exit 0 ;;
esac

# 數字 → 名稱
if echo "$VALUE" | grep -qE '^[0-5]$'; then
  NAME=""
  if [ -f "$MAP_FILE" ]; then
    NAME=$(awk -v n="$VALUE" '
      /^level_aliases:/ { in_sec=1; next }
      /^[a-z_]+:/ { if (!/^level_aliases:/) in_sec=0 }
      in_sec && /- "/ {
        line=$0; gsub(/[" -]/,"",line)
        split(line, kv, "=")
        if (kv[1] == n) { print kv[2]; exit }
      }
    ' "$MAP_FILE")
  fi
  if [ -z "$NAME" ]; then
    echo "⚠️  profile-map.yaml 不可用，使用內建 fallback 映射表" >&2
    case "$VALUE" in
      0|1) NAME=loose ;;
      2|3) NAME=standard ;;
      4|5) NAME=autonomous ;;
    esac
  fi
  cat >&2 <<EOF
⚠️  DEPRECATED: level: ${VALUE} 為 v4 數字等級，已自動視為 level: ${NAME}（0,1→loose｜2,3→standard｜4,5→autonomous）。
    請更新 .ai_profile 為 level: ${NAME}；數字等級將於 v6 移除。
EOF
  echo "$NAME"
  exit 0
fi

echo "ERROR: level 值無效：「$VALUE」（允許值：loose | standard | autonomous｜遺留數字 0-5）" >&2
exit 1
