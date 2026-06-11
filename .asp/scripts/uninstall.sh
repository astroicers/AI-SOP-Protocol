#!/usr/bin/env bash
# ASP Uninstall — 從專案或 user-level 乾淨移除 ASP
#
# 用法：
#   bash uninstall.sh                  # 互動式移除當前專案 ASP 設定
#   bash uninstall.sh --dry-run        # 列出即將移除的項目，不執行
#   bash uninstall.sh --yes            # 非互動式（自動確認所有提示）
#   bash uninstall.sh --user-level     # 移除 ~/.claude/ 的 ASP user-level 設定
#   bash uninstall.sh --user-level --yes
#
# 保留項目（不會刪除）：
#   .ai_profile               — 專案設定，使用者自行填寫
#   docs/adr/                 — ADR 文件，使用者撰寫
#   docs/specs/               — SPEC 文件，使用者撰寫
#   docs/architecture.md      — 架構文件，使用者撰寫
#   .asp-bypass-log.ndjson    — Audit trail（告知位置）
#   .asp-fact-check.md        — 外部事實查核記錄（告知位置）

set -uo pipefail

# ─── 跨平台 sed -i（與 install.sh 一致）─────────────────────────────
SED_INPLACE() {
  if [ "$(uname)" = "Darwin" ]; then sed -i '' "$@"; else sed -i "$@"; fi
}

# ─── 旗標解析 ───────────────────────────────────────────────────────
DRY_RUN=false
USER_LEVEL=false
AUTO_YES=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=true ;;
    --user-level) USER_LEVEL=true ;;
    --yes|-y)     AUTO_YES=true ;;
  esac
done

# ─── 工具函式 ───────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'

info()    { echo "  $1"; }
success() { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
dry()     { echo -e "  [DRY] 移除: $1"; }

confirm() {
  local msg="$1"
  if [ "$AUTO_YES" = true ] || [ ! -t 0 ]; then return 0; fi
  printf "  %s [y/N] " "$msg"
  read -r ans
  [ "${ans,,}" = "y" ]
}

do_remove() {
  # $1 = 路徑   $2 = 描述
  local target="$1" desc="${2:-}"
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then return; fi
  if [ "$DRY_RUN" = true ]; then
    dry "$target${desc:+ ($desc)}"
  else
    rm -rf "$target"
    success "移除: $target${desc:+ ($desc)}"
  fi
}

# ─── jq 輔助：清理 settings.json 內的 ASP hooks ────────────────────
clean_settings_json() {
  local file="$1"
  [ -f "$file" ] || return 0
  if ! command -v jq &>/dev/null; then
    warn "無 jq，請手動移除 $file 內的 session-audit / clean-allow-list hooks"
    return 0
  fi
  local before after
  before=$(jq -r '(.hooks.SessionStart // []) | length' "$file" 2>/dev/null || echo 0)
  jq '
    .hooks.SessionStart = [
      (.hooks.SessionStart // [])[] |
      select(
        (.hooks // []) |
        all(.command | test("(session-audit|clean-allow-list)\\.sh") | not)
      )
    ] |
    if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end |
    if ((.hooks // {}) | length) == 0 then del(.hooks) else . end
  ' "$file" > "$file.asp-tmp" && mv "$file.asp-tmp" "$file"
  after=$(jq -r '(.hooks.SessionStart // []) | length' "$file" 2>/dev/null || echo 0)
  local removed=$(( before - after ))
  if [ "$removed" -gt 0 ]; then
    success "清理 $file — 移除 $removed 個 ASP hooks（使用者 hooks 保留）"
  else
    info "    $file 內無 ASP hooks，跳過"
  fi
}

# ─── Makefile 清理：移除 ASP include 行 ────────────────────────────
clean_makefile() {
  [ -f "Makefile" ] || return 0
  if grep -qF '.asp/Makefile.inc' Makefile || grep -qF '.claude/asp/Makefile.inc' Makefile; then
    if [ "$DRY_RUN" = true ]; then
      dry "Makefile（移除 ASP include 行）"
    else
      SED_INPLACE '/# ASP targets/d; /Makefile\.inc/d' Makefile
      success "清理 Makefile — 移除 ASP include 行"
    fi
  fi
}

# ─── CLAUDE.md 處理 ─────────────────────────────────────────────────
clean_claude_md() {
  [ -f "CLAUDE.md" ] || return 0
  if grep -q "AI-SOP-Protocol" CLAUDE.md; then
    if grep -q "CLAUDE.md.pre-asp" . 2>/dev/null || [ -f "CLAUDE.md.pre-asp" ]; then
      # 有備份 — 可還原
      if [ "$DRY_RUN" = true ]; then
        dry "CLAUDE.md（還原自 CLAUDE.md.pre-asp）"
      elif confirm "偵測到 CLAUDE.md.pre-asp，是否還原原始 CLAUDE.md？"; then
        mv CLAUDE.md.pre-asp CLAUDE.md
        success "CLAUDE.md 已還原"
      fi
    else
      # 無備份 — ASP 產生的整份 CLAUDE.md
      if [ "$DRY_RUN" = true ]; then
        dry "CLAUDE.md（ASP 產生，整份移除）"
      elif confirm "CLAUDE.md 是 ASP 產生的，是否移除？"; then
        rm -f CLAUDE.md
        success "移除 CLAUDE.md"
      else
        warn "保留 CLAUDE.md（手動清理 ASP 段落）"
      fi
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════
# 模式 B：User-level 移除
# ═══════════════════════════════════════════════════════════════════
if [ "$USER_LEVEL" = true ]; then
  echo ""
  echo -e "${RED}ASP User-level 移除${NC}"
  echo "════════════════════════════════"
  if [ "$DRY_RUN" = true ]; then
    echo "  ── DRY RUN 模式（不實際執行）──"
  fi
  echo ""

  USER_CLAUDE="${HOME}/.claude"

  # skills
  do_remove "$USER_CLAUDE/skills/asp" "ASP skills"

  # ~/.claude/asp/（profiles/hooks/templates/levels/agents/config）
  do_remove "$USER_CLAUDE/asp" "ASP profiles/hooks/templates"

  # sync script
  do_remove "$USER_CLAUDE/scripts/asp-sync.sh" "ASP sync 腳本"

  # user-level CLAUDE.md
  if [ -f "$USER_CLAUDE/CLAUDE.md" ] && grep -q "ASP User-level Rules\|AI-SOP-Protocol" "$USER_CLAUDE/CLAUDE.md" 2>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
      dry "$USER_CLAUDE/CLAUDE.md（ASP user-level 鐵則）"
    elif confirm "移除 ~/.claude/CLAUDE.md（ASP user-level 鐵則）？"; then
      rm -f "$USER_CLAUDE/CLAUDE.md"
      success "移除 ~/.claude/CLAUDE.md"
    fi
  fi

  echo ""
  warn "各專案內的 .asp/ 需個別執行模式 A（在專案目錄跑 uninstall.sh）"
  echo ""

  if [ "$DRY_RUN" = false ]; then
    echo -e "  ${GREEN}User-level ASP 移除完成${NC}"
  else
    echo "  [DRY RUN 完成 — 以上為預覽，未實際移除任何檔案]"
  fi
  echo ""
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════
# 模式 A：專案層移除（預設）
# ═══════════════════════════════════════════════════════════════════
echo ""
echo -e "${RED}ASP 專案移除${NC}"
echo "════════════════════════════════"
echo "  目錄：$(pwd)"
if [ "$DRY_RUN" = true ]; then
  echo "  ── DRY RUN 模式（不實際執行）──"
fi
echo ""

# 安全檢查：確認在 git repo 內
if ! git rev-parse --git-dir &>/dev/null 2>&1; then
  echo -e "${YELLOW}⚠  目前不在 git repo 內，請在專案根目錄執行${NC}"
  exit 1
fi

# 偵測是否有 ASP 設定
HAS_ASP=false
[ -d ".asp" ] && HAS_ASP=true
[ -d ".claude/skills/asp" ] && HAS_ASP=true
[ -f ".ai_profile" ] && HAS_ASP=true

if [ "$HAS_ASP" = false ]; then
  echo "  未偵測到 ASP 設定，無需移除"
  exit 0
fi

# ── 1. .asp/ 整個目錄（舊架構核心）
do_remove ".asp" "ASP 核心（profiles/hooks/scripts/templates/levels）"

# ── 2. .claude/skills/asp/（舊架構 skill layer，新架構由 ~/.claude/ 提供）
do_remove ".claude/skills/asp" "ASP skills（改由 ~/.claude/skills/asp/ 提供）"

# ── 3. .claude/agents/（ASP subagent 定義）
if [ -d ".claude/agents" ]; then
  # 只移除 ASP 產生的 agents（以 reality-checker 等為代表）
  ASP_AGENTS=$(find .claude/agents -name "reality-checker*.md" -o -name "asp-*.md" 2>/dev/null | wc -l)
  if [ "$ASP_AGENTS" -gt 0 ]; then
    if [ "$DRY_RUN" = true ]; then
      dry ".claude/agents/（$ASP_AGENTS 個 ASP agent 定義）"
    else
      find .claude/agents -name "reality-checker*.md" -o -name "asp-*.md" 2>/dev/null | xargs rm -f
      # 若目錄已空則移除
      rmdir .claude/agents 2>/dev/null || true
      success "移除 .claude/agents/ 內的 ASP agent 定義"
    fi
  fi
fi

# ── 4. .claude/settings.json — 清理 ASP hooks（保留使用者 hooks）
if [ "$DRY_RUN" = true ]; then
  if [ -f ".claude/settings.json" ] && grep -q "session-audit\|clean-allow-list" .claude/settings.json 2>/dev/null; then
    dry ".claude/settings.json（移除 ASP hooks，保留其他設定）"
  fi
else
  clean_settings_json ".claude/settings.json"
fi

# ── 5. Makefile — 移除 ASP include 行
if [ "$DRY_RUN" = true ]; then
  if [ -f "Makefile" ] && (grep -qF '.asp/Makefile.inc' Makefile || grep -qF '.claude/asp/Makefile.inc' Makefile) 2>/dev/null; then
    dry "Makefile（移除 -include .asp/Makefile.inc 行）"
  fi
else
  clean_makefile
fi

# ── 6. CLAUDE.md — 依情況處理
if [ "$DRY_RUN" = true ]; then
  [ -f "CLAUDE.md" ] && grep -q "AI-SOP-Protocol" CLAUDE.md 2>/dev/null && dry "CLAUDE.md（ASP 行為憲法）"
else
  clean_claude_md
fi

# ── 7. 備份檔清理（可選）
BACKUP_FILES=(CLAUDE.md.pre-asp CLAUDE.md.pre-upgrade Makefile.pre-asp-upgrade)
for bf in "${BACKUP_FILES[@]}"; do
  if [ -f "$bf" ]; then
    if [ "$DRY_RUN" = true ]; then
      dry "$bf（ASP 安裝時的備份）"
    elif confirm "移除備份檔 $bf？"; then
      rm -f "$bf"
      success "移除 $bf"
    fi
  fi
done

# ── 8. 保留項目告知
echo ""
echo "  ── 以下項目已保留（使用者資料）──"
KEPT=()
[ -f ".ai_profile" ]               && KEPT+=(".ai_profile")
[ -d "docs/adr" ]                  && KEPT+=("docs/adr/")
[ -d "docs/specs" ]                && KEPT+=("docs/specs/")
[ -f "docs/architecture.md" ]      && KEPT+=("docs/architecture.md")
[ -f ".asp-bypass-log.ndjson" ]    && KEPT+=(".asp-bypass-log.ndjson（audit trail）")
[ -f ".asp-fact-check.md" ]        && KEPT+=(".asp-fact-check.md（外部事實記錄）")
[ -f ".asp-telemetry.jsonl" ]      && KEPT+=(".asp-telemetry.jsonl（telemetry 記錄）")

for item in "${KEPT[@]}"; do
  info "    保留：$item"
done

echo ""
if [ "$DRY_RUN" = false ]; then
  echo -e "  ${GREEN}專案 ASP 移除完成${NC}"
  echo ""
  echo "  若要移除 user-level ASP（~/.claude/）："
  echo "    bash uninstall.sh --user-level"
  echo ""
  echo "  若要重新安裝新架構 ASP："
  echo "    bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.sh)"
else
  echo "  [DRY RUN 完成 — 以上為預覽，未實際移除任何檔案]"
  echo "  執行移除：bash uninstall.sh --yes"
fi
echo ""
