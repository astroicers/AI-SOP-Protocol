#!/usr/bin/env bash
# validate-profile.sh — 驗證 .ai_profile 的 Profile 依賴完整性
# 執行：make profile-validate 或直接 bash .asp/scripts/validate-profile.sh

set -uo pipefail

PROFILE_FILE="${1:-.ai_profile}"
ERRORS=0
WARNINGS=0
FIXED=0

echo ""
echo "🔍 ASP Profile 驗證"
echo "================================="

if [ ! -f "$PROFILE_FILE" ]; then
  echo "⚠️  找不到 $PROFILE_FILE"
  echo "   提示：複製 .asp/templates/ 中的範例 profile 開始"
  echo ""
  exit 1
fi

echo "📄 讀取: $PROFILE_FILE"
echo ""

# 讀取各欄位
get_field() {
  grep "^${1}:" "$PROFILE_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'"
}

TYPE=$(get_field "type")
LEVEL=$(get_field "level")
MODE=$(get_field "mode")
WORKFLOW=$(get_field "workflow")
HITL=$(get_field "hitl")
AUTONOMOUS=$(get_field "autonomous")
ORCHESTRATOR=$(get_field "orchestrator")
DESIGN=$(get_field "design")
FRONTEND_QUALITY=$(get_field "frontend_quality")
AUTOPILOT=$(get_field "autopilot")
RAG=$(get_field "rag")
OPENAPI=$(get_field "openapi")
CODING_STYLE=$(get_field "coding_style")

echo "── 已設定欄位 ──"
[ -n "$TYPE" ]            && echo "  type:             $TYPE"
[ -n "$LEVEL" ]           && echo "  level:            L$LEVEL"
[ -n "$MODE" ]            && echo "  mode:             $MODE"
[ -n "$WORKFLOW" ]        && echo "  workflow:         $WORKFLOW"
[ -n "$HITL" ]            && echo "  hitl:             $HITL"
[ -n "$AUTONOMOUS" ]      && echo "  autonomous:       $AUTONOMOUS"
[ -n "$ORCHESTRATOR" ]    && echo "  orchestrator:     $ORCHESTRATOR"
[ -n "$DESIGN" ]          && echo "  design:           $DESIGN"
[ -n "$FRONTEND_QUALITY" ] && echo "  frontend_quality: $FRONTEND_QUALITY"
[ -n "$AUTOPILOT" ]       && echo "  autopilot:        $AUTOPILOT"
[ -n "$RAG" ]             && echo "  rag:              $RAG"
[ -n "$OPENAPI" ]         && echo "  openapi:          $OPENAPI"
[ -n "$CODING_STYLE" ]    && echo "  coding_style:     $CODING_STYLE"
echo ""

echo "── 依賴驗證 ──"

# 規則 1：type 必填
if [ -z "$TYPE" ]; then
  echo "  🔴 ERROR: 缺少必填欄位 type（system | content | architecture）"
  ERRORS=$((ERRORS + 1))
else
  echo "  ✅ type: $TYPE"
fi

# 規則 1a：level 值範圍（v5：loose | standard | autonomous；遺留數字 0-5 自動映射，ADR-014）
RESOLVED_LEVEL=""
if [ -n "$LEVEL" ]; then
  LEVEL_RESOLVE="$(dirname "$0")/level-resolve.sh"
  # deprecation 提示由本腳本以 WARNING 形式輸出，故丟棄 level-resolve 自帶的 stderr 提示
  RESOLVED_LEVEL=$(bash "$LEVEL_RESOLVE" "$LEVEL" 2>/dev/null) || RESOLVED_LEVEL=""
  if [ -z "$RESOLVED_LEVEL" ]; then
    echo "  🔴 ERROR: level 值無效：「$LEVEL」（允許值：loose | standard | autonomous｜遺留數字 0-5）"
    ERRORS=$((ERRORS + 1))
  else
    if [ "$RESOLVED_LEVEL" != "$LEVEL" ]; then
      echo "  🟡 WARNING: level: $LEVEL 為 v4 數字等級，已自動視為 level: $RESOLVED_LEVEL"
      echo "     → 請更新 $PROFILE_FILE 為 level: $RESOLVED_LEVEL；數字等級將於 v6 移除"
      WARNINGS=$((WARNINGS + 1))
    fi
    LEVEL_FILE=".asp/levels/$RESOLVED_LEVEL.yaml"
    if [ -f "$LEVEL_FILE" ]; then
      LEVEL_NAME=$(grep -E '^name:' "$LEVEL_FILE" | head -1 | sed 's/name: *//')
      echo "  ✅ level: $RESOLVED_LEVEL ($LEVEL_NAME)"
    else
      echo "  ✅ level: $RESOLVED_LEVEL"
    fi
  fi
else
  echo "  🟢 INFO: level 未設定（建議補上 level: loose 以明確成熟度）"
fi

# 規則 2：design: enabled → frontend_quality 必須也是 enabled
if [ "$DESIGN" = "enabled" ] && [ "$FRONTEND_QUALITY" != "enabled" ]; then
  echo "  🟡 WARNING: design: enabled 時，frontend_quality 應同時設為 enabled"
  echo "     → 自動補全建議：在 $PROFILE_FILE 加入 frontend_quality: enabled"
  WARNINGS=$((WARNINGS + 1))
  # 自動補全（用 awk 取代 sed -i：跨平台，避開 BSD/macOS 的 `sed -i` 與 `a\` 語法差異）
  if ! grep -q "^frontend_quality:" "$PROFILE_FILE"; then
    if awk '/^design:/{print; print "frontend_quality: enabled"; next} {print}' \
         "$PROFILE_FILE" > "${PROFILE_FILE}.tmp" && mv "${PROFILE_FILE}.tmp" "$PROFILE_FILE"; then
      echo "     ✅ 已自動加入 frontend_quality: enabled"
      FIXED=$((FIXED + 1))
    else
      rm -f "${PROFILE_FILE}.tmp" 2>/dev/null || true
    fi
  fi
else
  [ "$DESIGN" = "enabled" ] && echo "  ✅ design + frontend_quality: 均已啟用"
fi

# 規則 3：autopilot: enabled → autonomous + orchestrator 應為 enabled（自動載入，不強制但建議）
if [ "$AUTOPILOT" = "enabled" ]; then
  echo "  ✅ autopilot: enabled（autonomous + task_orchestrator 會自動載入）"
  if [ "$AUTONOMOUS" = "enabled" ]; then
    echo "  ✅ autonomous: enabled（明確設定，佳）"
  else
    echo "  🟢 INFO: autonomous 未明確設定，autopilot 啟動時會自動載入"
  fi
fi

# 規則 4：autonomous: enabled（HITL 等級定義已內建 global_core，ADR-014 D2）
if [ "$AUTONOMOUS" = "enabled" ]; then
  echo "  ✅ autonomous: enabled"
  if [ "$WORKFLOW" = "vibe-coding" ]; then
    echo "  🟡 WARNING: workflow: vibe-coding 與 autonomous 衝突（loose_mode × autonomous_dev）"
    echo "     → 將忽略 loose_mode（保留較嚴格者，ADR-014 D8）；建議改 workflow: standard"
    WARNINGS=$((WARNINGS + 1))
  fi
fi

# 規則 4a：guardrail 欄位 deprecated（v5 三層回應已內建 global_core，ADR-014 D6）
if grep -q '^guardrail: *enabled' "$PROFILE_FILE" 2>/dev/null; then
  echo "  🟢 INFO: guardrail 欄位已 deprecated — 範疇與敏感資訊三層回應已內建 global_core，欄位忽略"
fi

# 規則 5：mode: multi-agent → v5 凍結為 Experimental（ADR-017）
if [ "$MODE" = "multi-agent" ]; then
  echo "  🟡 WARNING: mode: multi-agent — multi-agent 已凍結為 Experimental（v5），預設安裝不含此功能"
  echo "     → 建議改 mode: auto；確需使用請見 repo experimental/multi-agent/README.md"
  WARNINGS=$((WARNINGS + 1))
fi

# 規則 6：rag: enabled → v5 移為 Showcase 元件（ADR-017）
if [ "$RAG" = "enabled" ]; then
  if [ -f "$HOME/.claude/asp/.showcase-installed" ]; then
    if [ -d ".rag/index" ] || [ -d ".asp/rag/" ]; then
      echo "  ✅ rag: enabled（Showcase 已安裝，索引存在）"
    else
      echo "  🟡 WARNING: rag: enabled 但索引不存在，執行 make rag-index 建立"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo "  🟡 WARNING: rag: enabled — RAG 為 Showcase 元件（v5），預設未安裝"
    echo "     → 執行 install.sh --with-showcase 裝回，或改 rag: disabled"
    WARNINGS=$((WARNINGS + 1))
  fi
fi

# 規則 7：hitl 值驗證
if [ -n "$HITL" ] && [ "$HITL" != "minimal" ] && [ "$HITL" != "standard" ] && [ "$HITL" != "strict" ]; then
  echo "  🔴 ERROR: hitl 值無效：「$HITL」（允許值：minimal | standard | strict）"
  ERRORS=$((ERRORS + 1))
fi

# 規則 8：workflow 值驗證
if [ -n "$WORKFLOW" ] && [ "$WORKFLOW" != "standard" ] && [ "$WORKFLOW" != "vibe-coding" ]; then
  echo "  🔴 ERROR: workflow 值無效：「$WORKFLOW」（允許值：standard | vibe-coding）"
  ERRORS=$((ERRORS + 1))
fi

# 規則 9：mode 值驗證
if [ -n "$MODE" ] && [ "$MODE" != "single" ] && [ "$MODE" != "auto" ] && [ "$MODE" != "multi-agent" ] && [ "$MODE" != "committee" ]; then
  echo "  🔴 ERROR: mode 值無效：「$MODE」（允許值：single | auto | multi-agent；committee 已於 2026-05-10 deprecated）"
  ERRORS=$((ERRORS + 1))
fi
if [ "$MODE" = "auto" ]; then
    echo "  ℹ️ mode: auto — AI 將根據任務複雜度自動判斷是否並行"
fi

echo ""
echo "── 載入的 Profile 清單 ──"
echo "  必載："

case "$TYPE" in
  system|architecture)
    echo "    • global_core.md"
    echo "    • system_dev.md"
    ;;
  content)
    echo "    • global_core.md"
    echo "    • content_creative.md"
    ;;
  "")
    echo "    （type 未設定，無法列出）"
    ;;
  *)
    echo "    🔴 ERROR: 未知 type 值：$TYPE"
    ERRORS=$((ERRORS + 1))
    ;;
esac

echo "  條件載入（依 .asp/config/profile-map.yaml，single source of truth — ADR-013）："
if [ "$MODE" = "multi-agent" ]; then
    echo "    • task_orchestrator.md（含 multi-agent 協調邏輯，v4.3+）"
    echo "    • pipeline.md（auto）"
fi
if [ "$MODE" = "multi-agent" ] && [ "$AUTONOMOUS" = "enabled" ]; then
    echo "    • reality_checker.md（auto）"
fi
[ "$MODE" = "committee" ]           && echo "    • ⚠️  committee.md (DEPRECATED 2026-05-10 — archived to docs/archive/profiles/; please use single/auto/multi-agent)"
[ "$WORKFLOW" = "vibe-coding" ]     && echo "    • loose_mode.md（v5 併自 vibe coding + spike mode）"
[ "$RESOLVED_LEVEL" = "loose" ]     && echo "    • loose_mode.md（loose 等級 auto）"
[ "$RAG" = "enabled" ]              && echo "    • rag_context.md"
[ "$DESIGN" = "enabled" ]           && echo "    • design_dev.md" && echo "    • frontend_quality.md（auto）"
[ "$CODING_STYLE" = "enabled" ]     && echo "    • coding_style.md"
[ "$OPENAPI" = "enabled" ]          && echo "    • openapi.md"
[ "$ORCHESTRATOR" = "enabled" ]     && echo "    • task_orchestrator.md"
[ "$AUTONOMOUS" = "enabled" ]       && echo "    • autonomous_dev.md" && echo "    • task_orchestrator.md（auto）"
[ "$AUTOPILOT" = "enabled" ]        && echo "    • asp-autopilot skill Part 2（v4.4 起取代 autopilot.md profile）" && echo "    • autonomous_dev.md（auto）" && echo "    • task_orchestrator.md（auto）"

echo ""
echo "================================="
echo "驗證結果：🔴 $ERRORS error | 🟡 $WARNINGS warning | 🔧 $FIXED auto-fixed"

if [ $ERRORS -gt 0 ]; then
  echo "❌ 請修復上述 error 後重新驗證"
  exit 1
elif [ $WARNINGS -gt 0 ]; then
  echo "⚠️  有 warning，建議處理後執行"
else
  echo "✅ 驗證通過"
fi
echo ""
