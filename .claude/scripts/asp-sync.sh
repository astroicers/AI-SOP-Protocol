#!/usr/bin/env bash
# asp-sync.sh — 從 AI-SOP-Protocol repo 同步 ASP 到 ~/.claude/
#
# 用法：
#   bash ~/.claude/scripts/asp-sync.sh            # 互動式（有差異時詢問確認）
#   bash ~/.claude/scripts/asp-sync.sh --yes      # 非互動式（自動同步）
#   bash ~/.claude/scripts/asp-sync.sh --dry-run  # 只顯示差異，不同步
#
# 同步範圍：
#   ~/.claude/asp/          ← .asp/（profiles/hooks/templates/levels/config/scripts）
#   ~/.claude/skills/asp/   ← .claude/skills/asp/（所有 asp-*.md skills）
#   ~/.claude/commands/asp/ ← .claude/commands/asp/（自訂 slash 指令，/asp:approve-adr 等；選用）
#   ~/.claude/CLAUDE.md     ← .claude/CLAUDE.md（user-level 鐵則，若已是 ASP 版本）
#
# v5（ADR-017）：若 ~/.claude/asp/.showcase-installed marker 存在，rsync --delete
# 後會自 showcase/ 補同步裝回內容（telemetry/RAG/ai-performance），避免抹掉
# 使用者以 install.sh --with-showcase 安裝的元件。

set -euo pipefail

ASP_REPO="${ASP_REPO:-${HOME}/AI-SOP-Protocol}"   # 可由 env 覆寫（本地測試 / 非家目錄 repo）
USER_CLAUDE="${HOME}/.claude"
USER_ASP="${USER_CLAUDE}/asp"
USER_SKILLS="${USER_CLAUDE}/skills/asp"
USER_CMDS="${USER_CLAUDE}/commands/asp"
SELF_SRC="${ASP_REPO}/.claude/scripts/asp-sync.sh"     # 自我更新來源
SELF_DST="${USER_CLAUDE}/scripts/asp-sync.sh"          # 已安裝副本

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

# is_downgrade <installed> <source> — 0 (true) iff 兩者皆 semver 且 source < installed。
# 非 semver（unknown / not installed / 含非數字點字元）一律回 1（不誤判方向）。
is_downgrade() {
  local installed="$1" source="$2"
  case "$installed" in ''|*[!0-9.]*) return 1;; esac   # 含非數字非點 → 非版本
  case "$source"    in ''|*[!0-9.]*) return 1;; esac
  case "$installed" in *[0-9]*) ;; *) return 1;; esac   # 須含至少一個數字（擋純點 "." ".."）
  case "$source"    in *[0-9]*) ;; *) return 1;; esac
  [ "$installed" = "$source" ] && return 1
  [ "$(printf '%s\n%s\n' "$installed" "$source" | sort -V | head -1)" = "$source" ]
}

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

# ─── 版本方向（ADR-020 類：防止無聲降級）───
DOWNGRADE=false; UPGRADE=false
if   is_downgrade "$INSTALLED_VERSION" "$REPO_VERSION"; then DOWNGRADE=true   # 來源 < 已安裝
elif is_downgrade "$REPO_VERSION" "$INSTALLED_VERSION"; then UPGRADE=true     # 已安裝 < 來源
fi

echo ""
echo "🔄 ASP Sync"
echo "  repo:      v${REPO_VERSION} (${ASP_REPO})"
echo "  installed: v${INSTALLED_VERSION}"
if [ "$DOWNGRADE" = true ]; then
  warn "偵測到降級：已安裝 v${INSTALLED_VERSION} 比來源 v${REPO_VERSION} 新"
  echo "     來源：${ASP_REPO}（$(git -C "$ASP_REPO" log -1 --oneline 2>/dev/null || echo '非 git / 未知 commit')）"
  echo "     來源 repo 可能停在舊 commit。請先 cd ${ASP_REPO} && git pull，或確認來源未指向舊版。"
fi
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
  --exclude="metrics" \
  "$USER_ASP" "$ASP_REPO/.asp" 2>/dev/null || true)
DIFF_SKILLS=$(diff -rq \
  "$USER_SKILLS" "$ASP_REPO/.claude/skills/asp" 2>/dev/null || true)
# commands/asp：來源不存在（舊 repo）→ 無差異；來源在但目標未裝 → 視為需同步
# （升級情境：已裝舊版 ASP 但無 commands/asp。目標缺時 diff 報錯會被 2>/dev/null||true 吞成空字串，故需顯式判斷）
if [ -d "$ASP_REPO/.claude/commands/asp" ]; then
  if [ -d "$USER_CMDS" ]; then
    DIFF_CMDS=$(diff -rq "$USER_CMDS" "$ASP_REPO/.claude/commands/asp" 2>/dev/null || true)
  else
    DIFF_CMDS="(commands/asp 尚未安裝)"
  fi
else
  DIFF_CMDS=""
fi
# asp-sync 自身：已安裝副本與 repo 版不同 → 視為需同步（否則「只有 asp-sync 變」時會誤判 already-in-sync 而不自我更新）
if [ -f "$SELF_SRC" ] && ! cmp -s "$SELF_SRC" "$SELF_DST" 2>/dev/null; then DIFF_SELF="asp-sync.sh changed"; else DIFF_SELF=""; fi

if [ -z "$DIFF_ASP" ] && [ -z "$DIFF_SKILLS" ] && [ -z "$DIFF_CMDS" ] && [ -z "$DIFF_SELF" ]; then
  echo "  Already in sync — v${INSTALLED_VERSION} 是最新版本"
  echo ""
  exit 0
fi

# 列出差異摘要
if [ -n "$DIFF_ASP" ]; then
  echo "  ~/.claude/asp/ 差異："
  diff -rq --exclude="*.pyc" --exclude="__pycache__" --exclude="metrics" \
    --exclude=".showcase-installed" --exclude="telemetry" --exclude="rag" \
    --exclude="rag-auto-index.sh" --exclude="rag_context.md" --exclude="ai-performance" \
    "$USER_ASP" "$ASP_REPO/.asp" 2>/dev/null | sed 's/^/    /' | head -20 || true
fi
if [ -n "$DIFF_SKILLS" ]; then
  echo "  ~/.claude/skills/asp/ 差異："
  diff -rq "$USER_SKILLS" "$ASP_REPO/.claude/skills/asp" 2>/dev/null | sed 's/^/    /' | head -20 || true
fi
if [ -n "$DIFF_CMDS" ]; then
  echo "  ~/.claude/commands/asp/ 差異："
  if [ -d "$USER_CMDS" ]; then
    diff -rq "$USER_CMDS" "$ASP_REPO/.claude/commands/asp" 2>/dev/null | sed 's/^/    /' | head -20 || true
  else
    echo "    $DIFF_CMDS"   # 目標未安裝：印狀態文字（直接 diff 不存在路徑會空白）
  fi
fi
echo ""

# ─── 確認 ────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY RUN — 未實際同步]"
  echo "  執行同步：bash ~/.claude/scripts/asp-sync.sh --yes"
  echo ""
  exit 0
fi

# 降級守門：非互動預設中止（ASP_ALLOW_DOWNGRADE=1 覆寫）；互動需額外確認。
if [ "$DOWNGRADE" = true ]; then
  if [ "$AUTO_YES" = true ] || [ ! -t 0 ]; then
    if [ "${ASP_ALLOW_DOWNGRADE:-0}" != "1" ]; then
      warn "已中止：非互動模式預設不執行降級。確定要降級請設 ASP_ALLOW_DOWNGRADE=1 重跑。"
      echo ""
      exit 1
    fi
    warn "ASP_ALLOW_DOWNGRADE=1 — 強制降級"
  else
    printf "  ⚠️ 確定要降級 v${INSTALLED_VERSION} → v${REPO_VERSION}（會覆蓋成舊版）？[y/N] "
    read -r CONFIRM || CONFIRM=""
    if [ "${CONFIRM,,}" != "y" ]; then echo "  已取消"; exit 0; fi
  fi
elif [ "$AUTO_YES" = false ] && [ -t 0 ]; then
  printf "  同步 v${INSTALLED_VERSION} → v${REPO_VERSION}？[y/N] "
  read -r CONFIRM || CONFIRM=""
  if [ "${CONFIRM,,}" != "y" ]; then
    echo "  已取消"
    exit 0
  fi
fi

# ─── 同步執行 ────────────────────────────────────────────────────
mkdir -p "$USER_ASP" "$USER_SKILLS"

if command -v rsync &>/dev/null; then
  rsync -a --delete \
    --exclude="*.pyc" --exclude="__pycache__" --exclude=".showcase-installed" --exclude="metrics" \
    "$ASP_REPO/.asp/" "$USER_ASP/"
  rsync -a --delete \
    "$ASP_REPO/.claude/skills/asp/" "$USER_SKILLS/"
  # commands/asp（選用）：mirror 至專屬子目錄；--delete 安全，不碰共用頂層 ~/.claude/commands/
  if [ -d "$ASP_REPO/.claude/commands/asp" ]; then
    mkdir -p "$USER_CMDS"
    rsync -a --delete "$ASP_REPO/.claude/commands/asp/" "$USER_CMDS/"
  fi
else
  # rsync 不可用時 fallback（保護 runtime 生成的 metrics/，勿隨 rm -rf 抹除遙測）
  if [ -d "$USER_ASP/metrics" ]; then
    METRICS_BAK=$(mktemp -d)
    cp -r "$USER_ASP/metrics" "$METRICS_BAK/"
  else
    METRICS_BAK=""
  fi
  rm -rf "$USER_ASP" && cp -r "$ASP_REPO/.asp" "$USER_ASP"
  if [ -n "$METRICS_BAK" ]; then
    cp -r "$METRICS_BAK/metrics" "$USER_ASP/" && rm -rf "$METRICS_BAK"
  fi
  rm -rf "$USER_SKILLS" && cp -r "$ASP_REPO/.claude/skills/asp" "$USER_SKILLS"
  if [ -d "$ASP_REPO/.claude/commands/asp" ]; then
    rm -rf "${USER_CMDS:?}"; mkdir -p "$(dirname "$USER_CMDS")"
    cp -r "$ASP_REPO/.claude/commands/asp" "$USER_CMDS"
  fi
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

# 自我更新：把最新 asp-sync.sh 裝回 ~/.claude/scripts/。asp-sync 過去不更新自己
# （只有 install.sh 會裝它）→ 改了 repo 版後已安裝副本會一直舊。用 temp + mv（atomic）
# 避免覆蓋「執行中」的腳本檔導致 bash 讀取錯亂（mv 換 dir entry，執行中行程仍持有舊 inode）。
if [ -n "$DIFF_SELF" ]; then
  mkdir -p "$USER_CLAUDE/scripts"
  if cp "$SELF_SRC" "$SELF_DST.tmp.$$" && chmod +x "$SELF_DST.tmp.$$"; then
    mv "$SELF_DST.tmp.$$" "$SELF_DST"
    success "~/.claude/scripts/asp-sync.sh（自我更新）"
  else
    rm -f "$SELF_DST.tmp.$$" 2>/dev/null || true
  fi
fi

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
if [ -d "$USER_CMDS" ]; then
  CMD_COUNT=$(find "$USER_CMDS" -name "*.md" | wc -l)
  success "~/.claude/commands/asp/（${CMD_COUNT} 自訂 slash 指令）"
fi

echo ""
if [ "$DOWNGRADE" = true ]; then
  echo "  降級完成：v${INSTALLED_VERSION} → v${REPO_VERSION}"
elif [ "$UPGRADE" = true ]; then
  echo "  升級完成：v${INSTALLED_VERSION} → v${REPO_VERSION}"
elif [ "$INSTALLED_VERSION" = "$REPO_VERSION" ]; then
  echo "  同步完成（同版本內容更新）：v${REPO_VERSION}"
else
  echo "  同步完成：v${INSTALLED_VERSION} → v${REPO_VERSION}"
fi
echo ""
