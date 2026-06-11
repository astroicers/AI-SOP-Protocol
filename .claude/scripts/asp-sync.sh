#!/usr/bin/env bash
# asp-sync.sh — 從 AI-SOP-Protocol repo 同步 ASP 到 ~/.claude/
#
# 用法：
#   bash ~/.claude/scripts/asp-sync.sh            # 互動式（有差異時詢問確認）
#   bash ~/.claude/scripts/asp-sync.sh --yes      # 非互動式（自動同步）
#   bash ~/.claude/scripts/asp-sync.sh --dry-run  # 只顯示差異，不同步
#
# 同步範圍：
#   ~/.claude/asp/         ← .asp/（profiles/hooks/templates/levels/config/scripts）
#   ~/.claude/skills/asp/  ← .claude/skills/asp/（所有 asp-*.md skills）
#   ~/.claude/CLAUDE.md    ← .claude/CLAUDE.md（user-level 鐵則，若已是 ASP 版本）
#
# v5（ADR-017）：若 ~/.claude/asp/.showcase-installed marker 存在，rsync --delete
# 後會自 showcase/ 補同步裝回內容（telemetry/RAG/ai-performance），避免抹掉
# 使用者以 install.sh --with-showcase 安裝的元件。

set -euo pipefail

ASP_REPO="${HOME}/AI-SOP-Protocol"
USER_CLAUDE="${HOME}/.claude"
USER_ASP="${USER_CLAUDE}/asp"
USER_SKILLS="${USER_CLAUDE}/skills/asp"

DRY_RUN=false
AUTO_YES=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes|-y)  AUTO_YES=true ;;
  esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
success() { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }

# ─── Source 驗證 ─────────────────────────────────────────────────
if [ ! -d "$ASP_REPO" ]; then
  echo "ERROR: ASP repo not found at $ASP_REPO"
  echo "       請先 git clone https://github.com/astroicers/AI-SOP-Protocol $ASP_REPO"
  exit 1
fi
if [ ! -d "$ASP_REPO/.asp" ] || [ ! -d "$ASP_REPO/.claude/skills/asp" ]; then
  echo "ERROR: ASP repo 結構不完整（缺少 .asp/ 或 .claude/skills/asp/）"
  exit 1
fi

# ─── 版本資訊 ────────────────────────────────────────────────────
REPO_VERSION=$(cat "$ASP_REPO/.asp/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
INSTALLED_VERSION=$(cat "$USER_ASP/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "not installed")

echo ""
echo "🔄 ASP Sync"
echo "  repo:      v${REPO_VERSION} (${ASP_REPO})"
echo "  installed: v${INSTALLED_VERSION}"
if [ "$DRY_RUN" = true ]; then
  echo "  ── DRY RUN 模式（不實際同步）──"
fi
echo ""

# ─── Showcase marker（v5 ADR-017）────────────────────────────────
SHOWCASE_MARKER="$USER_ASP/.showcase-installed"
SHOWCASE_INSTALLED=false
[ -f "$SHOWCASE_MARKER" ] && SHOWCASE_INSTALLED=true

# ─── 差異偵測 ────────────────────────────────────────────────────
DIFF_ASP=$(diff -rq --exclude="*.pyc" --exclude="__pycache__" \
  --exclude=".showcase-installed" --exclude="telemetry" --exclude="rag" \
  --exclude="rag-auto-index.sh" --exclude="rag_context.md" --exclude="ai-performance" \
  "$USER_ASP" "$ASP_REPO/.asp" 2>/dev/null || true)
DIFF_SKILLS=$(diff -rq \
  "$USER_SKILLS" "$ASP_REPO/.claude/skills/asp" 2>/dev/null || true)

if [ -z "$DIFF_ASP" ] && [ -z "$DIFF_SKILLS" ]; then
  echo "  Already in sync — v${INSTALLED_VERSION} 是最新版本"
  echo ""
  exit 0
fi

# 列出差異摘要
if [ -n "$DIFF_ASP" ]; then
  echo "  ~/.claude/asp/ 差異："
  diff -rq --exclude="*.pyc" --exclude="__pycache__" \
    "$USER_ASP" "$ASP_REPO/.asp" 2>/dev/null | sed 's/^/    /' | head -20 || true
fi
if [ -n "$DIFF_SKILLS" ]; then
  echo "  ~/.claude/skills/asp/ 差異："
  diff -rq "$USER_SKILLS" "$ASP_REPO/.claude/skills/asp" 2>/dev/null | sed 's/^/    /' | head -20 || true
fi
echo ""

# ─── 確認 ────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY RUN — 未實際同步]"
  echo "  執行同步：bash ~/.claude/scripts/asp-sync.sh --yes"
  echo ""
  exit 0
fi

if [ "$AUTO_YES" = false ] && [ -t 0 ]; then
  printf "  同步 v${INSTALLED_VERSION} → v${REPO_VERSION}？[y/N] "
  read -r CONFIRM
  if [ "${CONFIRM,,}" != "y" ]; then
    echo "  已取消"
    exit 0
  fi
fi

# ─── 同步執行 ────────────────────────────────────────────────────
mkdir -p "$USER_ASP" "$USER_SKILLS"

if command -v rsync &>/dev/null; then
  rsync -a --delete \
    --exclude="*.pyc" --exclude="__pycache__" --exclude=".showcase-installed" \
    "$ASP_REPO/.asp/" "$USER_ASP/"
  rsync -a --delete \
    "$ASP_REPO/.claude/skills/asp/" "$USER_SKILLS/"
else
  # rsync 不可用時 fallback
  rm -rf "$USER_ASP" && cp -r "$ASP_REPO/.asp" "$USER_ASP"
  rm -rf "$USER_SKILLS" && cp -r "$ASP_REPO/.claude/skills/asp" "$USER_SKILLS"
fi

# ─── Showcase 補同步（v5 ADR-017：--delete 後依 marker 裝回）────────
if [ "$SHOWCASE_INSTALLED" = true ] && [ -d "$ASP_REPO/showcase" ]; then
  mkdir -p "$USER_ASP/scripts" "$USER_ASP/hooks" "$USER_ASP/profiles"
  cp -r "$ASP_REPO/showcase/telemetry"   "$USER_ASP/scripts/telemetry"
  cp -r "$ASP_REPO/showcase/rag/scripts" "$USER_ASP/scripts/rag"
  cp -f "$ASP_REPO/showcase/rag/hooks/rag-auto-index.sh" "$USER_ASP/hooks/"
  cp -f "$ASP_REPO/showcase/rag/profiles/rag_context.md" "$USER_ASP/profiles/"
  cp -r "$ASP_REPO/showcase/ai-performance" "$USER_ASP/ai-performance"
  touch "$SHOWCASE_MARKER"
  success "Showcase 補同步（marker: .showcase-installed）"
fi

# hooks 需要執行權限
chmod +x "$USER_ASP/hooks/"*.sh "$USER_ASP/scripts/"*.sh "$USER_ASP/scripts/orchestrator/"*.sh 2>/dev/null || true

# user-level CLAUDE.md 同步（只更新 ASP 版本）
USER_CLAUDE_MD="$USER_CLAUDE/CLAUDE.md"
SRC_CLAUDE_MD="$ASP_REPO/.claude/CLAUDE.md"
if [ -f "$SRC_CLAUDE_MD" ]; then
  if [ ! -f "$USER_CLAUDE_MD" ] || grep -q "ASP User-level Rules\|AI-SOP-Protocol" "$USER_CLAUDE_MD" 2>/dev/null; then
    cp "$SRC_CLAUDE_MD" "$USER_CLAUDE_MD"
    success "~/.claude/CLAUDE.md"
  else
    warn "~/.claude/CLAUDE.md 不是 ASP 版本，跳過（避免覆蓋使用者自訂內容）"
  fi
fi

# ─── 完成 ────────────────────────────────────────────────────────
SKILL_COUNT=$(find "$USER_SKILLS" -name "*.md" | wc -l)
PROFILE_COUNT=$(find "$USER_ASP/profiles" -name "*.md" 2>/dev/null | wc -l || echo 0)

success "~/.claude/asp/（${PROFILE_COUNT} profiles + hooks/templates/levels）"
success "~/.claude/skills/asp/（${SKILL_COUNT} skills）"

echo ""
echo "  同步完成：v${INSTALLED_VERSION} → v${REPO_VERSION}"
echo ""
