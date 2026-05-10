#!/usr/bin/env bash
# AI-SOP-Protocol 安裝腳本 v4.0 — User-level 架構
#
# 安裝架構：
#   Phase 1：ASP 核心裝到 ~/.claude/（所有專案共用，一次安裝）
#   Phase 2：在當前專案建立輕量設定（.ai_profile + CLAUDE.md + hooks 設定）
#
# 用法：
#   bash install.sh                          # 互動式安裝
#   ASP_TYPE=system ASP_LEVEL=2 bash install.sh  # 非互動式（CI / curl | bash）
#
# 移除：bash uninstall.sh

set -euo pipefail

PROTOCOL_REPO="https://github.com/astroicers/AI-SOP-Protocol"
TMP_DIR=$(mktemp -d /tmp/asp-install-XXXXX)
USER_CLAUDE="${HOME}/.claude"
USER_ASP="${USER_CLAUDE}/asp"
USER_SKILLS="${USER_CLAUDE}/skills/asp"

# 失敗時清理暫存目錄
trap 'rm -rf "$TMP_DIR"' EXIT

# ─── 工具函式 ────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
success() { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }

# 跨平台 sed -i
SED_INPLACE() {
  if [ "$(uname)" = "Darwin" ]; then sed -i '' "$@"; else sed -i "$@"; fi
}

# ─── Runtime precheck (SPEC-004 Done When #13) ───────────────────
#
# v4.1 multi-agent worktree (SPEC-004) 依賴：
#   git    ≥ 2.20  (worktree 成熟版本，--porcelain 含 branch/HEAD 行)
#   bash   ≥ 4.4   (associative array、$BASH_REMATCH 穩定行為)
#   jq     ≥ 1.6   (-c 模式輸出 NDJSON、telemetry 解析)
#   python3 ≥ 3.10 (telemetry/ai-performance 腳本用 type hints)
#
# 缺少任一者 → abort 安裝（fail-closed）。允許 user 用 ASP_SKIP_PRECHECK=1
# 強制跳過，但會印警告。
#
# 版本比較用 sort -V（GNU sort，BSD sort 也支援自 macOS 10.10+）。

version_at_least() {
    # version_at_least <required> <actual>  →  exit 0 iff actual >= required
    local required="$1" actual="$2"
    [ "$actual" = "$required" ] && return 0
    [ "$(printf '%s\n%s\n' "$required" "$actual" | sort -V | head -1)" = "$required" ]
}

precheck_runtime() {
    if [ "${ASP_SKIP_PRECHECK:-0}" = "1" ]; then
        warn "ASP_SKIP_PRECHECK=1 set — bypassing v4.1 runtime checks"
        return 0
    fi

    local missing=0

    # git
    if ! command -v git >/dev/null 2>&1; then
        echo "  ✗ git not installed (required: ≥ 2.20)" >&2
        missing=$((missing + 1))
    else
        local git_v
        git_v=$(git --version 2>/dev/null | sed -n 's/^git version \([0-9.]*\).*/\1/p')
        if ! version_at_least "2.20" "$git_v"; then
            echo "  ✗ git $git_v < 2.20 (worktree --porcelain stability)" >&2
            missing=$((missing + 1))
        else
            success "git $git_v ≥ 2.20"
        fi
    fi

    # bash
    if ! command -v bash >/dev/null 2>&1; then
        echo "  ✗ bash not installed (required: ≥ 4.4)" >&2
        missing=$((missing + 1))
    else
        local bash_v
        bash_v=$(bash --version 2>/dev/null | head -1 | sed -n 's/.*version \([0-9.]*\).*/\1/p')
        if ! version_at_least "4.4" "$bash_v"; then
            echo "  ✗ bash $bash_v < 4.4" >&2
            missing=$((missing + 1))
        else
            success "bash $bash_v ≥ 4.4"
        fi
    fi

    # jq
    if ! command -v jq >/dev/null 2>&1; then
        echo "  ✗ jq not installed (required: ≥ 1.6)" >&2
        echo "    install: apt-get install jq  /  brew install jq" >&2
        missing=$((missing + 1))
    else
        local jq_v
        jq_v=$(jq --version 2>/dev/null | sed -n 's/^jq-\([0-9.]*\).*/\1/p')
        if ! version_at_least "1.6" "$jq_v"; then
            echo "  ✗ jq $jq_v < 1.6" >&2
            missing=$((missing + 1))
        else
            success "jq $jq_v ≥ 1.6"
        fi
    fi

    # python3
    if ! command -v python3 >/dev/null 2>&1; then
        echo "  ✗ python3 not installed (required: ≥ 3.10)" >&2
        missing=$((missing + 1))
    else
        local py_v
        py_v=$(python3 --version 2>/dev/null | sed -n 's/^Python \([0-9.]*\).*/\1/p')
        if ! version_at_least "3.10" "$py_v"; then
            echo "  ✗ python3 $py_v < 3.10" >&2
            missing=$((missing + 1))
        else
            success "python3 $py_v ≥ 3.10"
        fi
    fi

    if [ "$missing" -gt 0 ]; then
        echo "" >&2
        echo "ERROR: $missing runtime requirement(s) missing for ASP v4.1 (SPEC-004)." >&2
        echo "       Install missing dependencies, OR set ASP_SKIP_PRECHECK=1 to bypass" >&2
        echo "       (multi-agent worktree features will not work without them)." >&2
        exit 13
    fi
}

# ─── 偵測專案類型 ─────────────────────────────────────────────────
detect_type() {
  if [ -f "docker-compose.yml" ] && [ -d "docs/adr" ]; then echo "architecture"; return; fi
  if ls */Dockerfile &>/dev/null 2>&1 || [ -d "terraform" ] || [ -d "pulumi" ] || [ -f "helmfile.yaml" ]; then
    echo "architecture"; return
  fi
  for f in go.mod Cargo.toml pom.xml package.json requirements.txt pyproject.toml Dockerfile Makefile; do
    [ -f "$f" ] && echo "system" && return
  done
  echo "content"
}

# ─── Preset ───────────────────────────────────────────────────────
apply_preset() {
  case "$1" in
    1) ASP_LEVEL=1; HITL_LEVEL=standard; WORKFLOW=standard; MODE=auto
       ENABLE_AUTONOMOUS=n; ENABLE_ORCHESTRATOR=n; ENABLE_AUTOPILOT=n
       ENABLE_RAG=n; ENABLE_GUARDRAIL=n; ENABLE_CODING_STYLE=n ;;
    2) ASP_LEVEL=2; HITL_LEVEL=standard; WORKFLOW=standard; MODE=auto
       ENABLE_AUTONOMOUS=n; ENABLE_ORCHESTRATOR=n; ENABLE_AUTOPILOT=n
       ENABLE_RAG=n; ENABLE_GUARDRAIL=y; ENABLE_CODING_STYLE=y ;;
    3) ASP_LEVEL=3; HITL_LEVEL=standard; WORKFLOW=standard; MODE=auto
       ENABLE_AUTONOMOUS=n; ENABLE_ORCHESTRATOR=n; ENABLE_AUTOPILOT=n
       ENABLE_RAG=n; ENABLE_GUARDRAIL=y; ENABLE_CODING_STYLE=y ;;
    4) ASP_LEVEL=4; HITL_LEVEL=standard; WORKFLOW=standard; MODE=multi-agent
       ENABLE_AUTONOMOUS=n; ENABLE_ORCHESTRATOR=y; ENABLE_AUTOPILOT=n
       ENABLE_RAG=n; ENABLE_GUARDRAIL=y; ENABLE_CODING_STYLE=y ;;
    5) ASP_LEVEL=5; HITL_LEVEL=minimal; WORKFLOW=vibe-coding; MODE=multi-agent
       ENABLE_AUTONOMOUS=y; ENABLE_ORCHESTRATOR=y; ENABLE_AUTOPILOT=y
       ENABLE_RAG=y; ENABLE_GUARDRAIL=y; ENABLE_CODING_STYLE=y ;;
    *) apply_preset 1 ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════
# 開場
# ═══════════════════════════════════════════════════════════════════
echo ""
echo "🤖 AI-SOP-Protocol 安裝程式 v4.1"
echo "======================================"
echo "  架構：User-level（~/.claude/asp/）— 所有專案共用"
echo ""

# ═══════════════════════════════════════════════════════════════════
# Phase 0：Runtime precheck (SPEC-004 Done When #13)
# ═══════════════════════════════════════════════════════════════════
echo "🔍 Phase 0：runtime 環境檢查（SPEC-004 v4.1 multi-agent worktree 依賴）"
echo "──────────────────────────────────────"
precheck_runtime
echo ""

# ═══════════════════════════════════════════════════════════════════
# Phase 1：User-level 安裝
# ═══════════════════════════════════════════════════════════════════
echo "📦 Phase 1：安裝 ASP 核心到 ~/.claude/"
echo "──────────────────────────────────────"

IS_USER_UPGRADE=false
if [ -d "$USER_ASP" ] || [ -d "$USER_SKILLS" ]; then
  IS_USER_UPGRADE=true
  INSTALLED_VERSION="unknown"
  [ -f "$USER_ASP/VERSION" ] && INSTALLED_VERSION=$(cat "$USER_ASP/VERSION" | tr -d '[:space:]')
  echo "  🔄 偵測到已安裝 ASP v${INSTALLED_VERSION}，執行升級"
fi

# clone ASP repo
echo "  從 GitHub 下載 ASP..."
if git clone --quiet --depth=1 "$PROTOCOL_REPO" "$TMP_DIR" 2>/dev/null; then
  NEW_VERSION=$(cat "$TMP_DIR/.asp/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
  NEW_COMMIT=$(git -C "$TMP_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  echo "  版本：v${NEW_VERSION} (${NEW_COMMIT})"

  # ~/.claude/asp/（profiles/hooks/templates/levels/agents/config）
  mkdir -p "$USER_ASP"
  for dir in profiles hooks templates levels agents config advanced; do
    if [ -d "$TMP_DIR/.asp/$dir" ]; then
      rm -rf "${USER_ASP:?}/$dir"
      cp -r "$TMP_DIR/.asp/$dir" "$USER_ASP/$dir"
    fi
  done
  cp -f "$TMP_DIR/.asp/VERSION" "$USER_ASP/VERSION" 2>/dev/null || true
  chmod +x "$USER_ASP/hooks/"*.sh 2>/dev/null || true

  # ~/.claude/skills/asp/
  mkdir -p "$USER_SKILLS"
  rm -rf "${USER_SKILLS:?}/"*
  cp -r "$TMP_DIR/.claude/skills/asp/." "$USER_SKILLS/"

  # ~/.claude/CLAUDE.md（user-level 鐵則）
  # 只有在不存在或已是 ASP 版本時才覆蓋
  USER_CLAUDE_MD="$USER_CLAUDE/CLAUDE.md"
  if [ ! -f "$USER_CLAUDE_MD" ] || grep -q "ASP User-level Rules\|AI-SOP-Protocol" "$USER_CLAUDE_MD" 2>/dev/null; then
    cp "$TMP_DIR/.claude/CLAUDE.md" "$USER_CLAUDE_MD" 2>/dev/null || \
    cat > "$USER_CLAUDE_MD" << 'UCLAUDEMD'
# ASP User-level Rules

> Applies to all projects. Project-specific rules go in each project's CLAUDE.md.

## 鐵則（不可覆蓋）

| 鐵則 | 說明 |
|------|------|
| 破壞性操作防護 | `git push / rebase / rm -rf / docker push` 必須先列出變更並等待人類確認 |
| 敏感資訊保護 | 禁止輸出 API Key、密碼、憑證（任何包裝方式） |
| ADR 未定案禁止實作 | Draft ADR 狀態下禁止寫生產代碼 |
| 外部事實驗證防護 | 涉及第三方 API/版本/法規 → 必須執行 asp-fact-verify，記錄至 .asp-fact-check.md |

## 成熟度等級（L0-L5）

| Level | 名稱 | 適用場景 |
|-------|------|---------|
| L0 | Spike | 技術假設驗證、PoC（≤5 working days） |
| L1 | Starter | 個人/小型專案（最小治理） |
| L2 | Disciplined | 自動化品質護欄 |
| L3 | Test-First | 測試文化成熟 + pipeline gates G1-G6 |
| L4 | Collaborative | 中大型/跨模組 + multi-agent |
| L5 | Autonomous | ROADMAP 驅動 + RAG |

Level details: see `~/.claude/skills/asp/` or `~/.claude/asp/levels/level-N.yaml`

## 啟動程序

1. 讀取專案 `.ai_profile`，依欄位載入對應 profile（見 `~/.claude/asp/profiles/global_core.md`）
2. 無 `.ai_profile`：只套用本鐵則，詢問使用者專案類型

## Agent skills

Invoke with `/skill-name`. All asp-* skills via `~/.claude/skills/asp/`.

| Skill | Purpose |
|-------|---------|
| /asp-plan | ADR + SPEC planning |
| /asp-ship | Pre-commit 10-step check |
| /asp-gate | Quality gates G1-G6 |
| /asp-audit | Project health audit |
| /asp-level | Maturity level management |
UCLAUDEMD
    success "~/.claude/CLAUDE.md（user-level 鐵則）"
  fi

  # ~/.claude/scripts/asp-sync.sh（後續更新用）
  mkdir -p "$USER_CLAUDE/scripts"
  cp "$TMP_DIR/.claude/scripts/asp-sync.sh" "$USER_CLAUDE/scripts/asp-sync.sh" 2>/dev/null || \
  cat > "$USER_CLAUDE/scripts/asp-sync.sh" << 'SYNCSH'
#!/usr/bin/env bash
# ASP sync — 從 AI-SOP-Protocol repo 同步到 ~/.claude/
# 用法：bash ~/.claude/scripts/asp-sync.sh
set -euo pipefail
ASP_REPO="${HOME}/AI-SOP-Protocol"
USER_CLAUDE="${HOME}/.claude"
USER_ASP="${USER_CLAUDE}/asp"
USER_SKILLS="${USER_CLAUDE}/skills/asp"
[ -d "$ASP_REPO" ] || { echo "ERROR: ASP repo not found at $ASP_REPO"; exit 1; }
DIFF=$(diff -rq "$USER_SKILLS" "$ASP_REPO/.claude/skills/asp" 2>/dev/null || true)
DIFF2=$(diff -rq "$USER_ASP" "$ASP_REPO/.asp" 2>/dev/null || true)
[ -z "$DIFF" ] && [ -z "$DIFF2" ] && { echo "Already in sync"; exit 0; }
echo "Changes detected. Syncing..."
if command -v rsync &>/dev/null; then
  rsync -a --delete "$ASP_REPO/.asp/" "$USER_ASP/"
  rsync -a --delete "$ASP_REPO/.claude/skills/asp/" "$USER_SKILLS/"
else
  rm -rf "$USER_ASP" && cp -r "$ASP_REPO/.asp" "$USER_ASP"
  rm -rf "$USER_SKILLS" && cp -r "$ASP_REPO/.claude/skills/asp" "$USER_SKILLS"
fi
chmod +x "$USER_ASP/hooks/"*.sh 2>/dev/null || true
echo "Synced $(find "$USER_SKILLS" -type f | wc -l) skill files + profiles/hooks/templates"
SYNCSH
  chmod +x "$USER_CLAUDE/scripts/asp-sync.sh"
  success "~/.claude/scripts/asp-sync.sh"

  if [ "$IS_USER_UPGRADE" = true ]; then
    success "User-level 升級完成（v${INSTALLED_VERSION} → v${NEW_VERSION}）"
  else
    success "User-level 安裝完成（v${NEW_VERSION}）"
  fi
else
  warn "無法連接 GitHub，跳過 user-level 安裝"
  warn "請手動執行：bash ~/.claude/scripts/asp-sync.sh"
  NEW_VERSION="local"
  NEW_COMMIT="local"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# Phase 2：專案輕量設定
# ═══════════════════════════════════════════════════════════════════
echo "📋 Phase 2：設定專案輕量層（$(pwd)）"
echo "──────────────────────────────────────"

# 升級偵測
IS_PROJECT_UPGRADE=false
if [ -f ".ai_profile" ] || [ -d ".asp" ]; then
  IS_PROJECT_UPGRADE=true
fi

# 舊架構清理提示
if [ -d ".asp" ]; then
  warn ".asp/ 偵測到舊架構 — 自動清理"
  rm -rf ".asp"
  success "移除 .asp/（已由 ~/.claude/asp/ 取代）"
fi
if [ -d ".claude/skills/asp" ]; then
  rm -rf ".claude/skills/asp"
  success "移除 .claude/skills/asp/（已由 ~/.claude/skills/asp/ 取代）"
fi

# 偵測類型 / 互動
DETECTED=$(detect_type)
DEFAULT_NAME="$(basename "$(pwd)")"

if [ -t 0 ]; then
  echo ""
  echo "  專案類型：[1] system  [2] content  [3] architecture  （偵測：$DETECTED）"
  read -rp "  選擇 (Enter 使用偵測值): " TYPE_CHOICE
  case "${TYPE_CHOICE:-}" in
    1) PROJECT_TYPE=system ;;
    2) PROJECT_TYPE=content ;;
    3) PROJECT_TYPE=architecture ;;
    *) PROJECT_TYPE="$DETECTED" ;;
  esac

  echo ""
  echo "  成熟度等級："
  echo "    [1] L1 Starter       — 最小治理（ADR + SPEC + 測試）"
  echo "    [2] L2 Disciplined   — + guardrail + coding_style"
  echo "    [3] L3 Test-First    — + pipeline gates G1-G6"
  echo "    [4] L4 Collaborative — + multi-agent"
  echo "    [5] L5 Autonomous    — + autopilot + RAG"
  read -rp "  選擇 level (Enter = L1): " LEVEL_CHOICE
  apply_preset "${LEVEL_CHOICE:-1}"
else
  PROJECT_TYPE="${ASP_TYPE:-$DETECTED}"
  apply_preset "${ASP_LEVEL:-1}"
  echo "  非互動模式 — type: $PROJECT_TYPE | level: L${ASP_LEVEL:-1}"
fi

PROJECT_NAME="$DEFAULT_NAME"
echo ""

# .ai_profile
if [ -f ".ai_profile" ]; then
  warn ".ai_profile 已存在，保留（如需重設請刪除後重跑）"
else
  cat > .ai_profile << PROFILE
type: ${PROJECT_TYPE}
level: ${ASP_LEVEL}
mode: ${MODE:-auto}
workflow: ${WORKFLOW:-standard}
hitl: ${HITL_LEVEL:-standard}
rag: $([ "${ENABLE_RAG:-n}" = "y" ] && echo enabled || echo disabled)
guardrail: $([ "${ENABLE_GUARDRAIL:-n}" = "y" ] && echo enabled || echo disabled)
autonomous: $([ "${ENABLE_AUTONOMOUS:-n}" = "y" ] && echo enabled || echo disabled)
orchestrator: $([ "${ENABLE_ORCHESTRATOR:-n}" = "y" ] && echo enabled || echo disabled)
autopilot: $([ "${ENABLE_AUTOPILOT:-n}" = "y" ] && echo enabled || echo disabled)
coding_style: $([ "${ENABLE_CODING_STYLE:-n}" = "y" ] && echo enabled || echo disabled)
name: ${PROJECT_NAME}
PROFILE
  success ".ai_profile"
fi

# CLAUDE.md（精簡版）
if [ -f "CLAUDE.md" ] && grep -q "AI-SOP-Protocol\|ASP" CLAUDE.md 2>/dev/null; then
  warn "CLAUDE.md 已存在（ASP 版），保留"
elif [ ! -f "CLAUDE.md" ]; then
  cat > CLAUDE.md << CLAUDEMD
# ${PROJECT_NAME} — AI 行為設定

> ASP v4.0 | 讀取順序：本檔案 → \`.ai_profile\` → \`~/.claude/CLAUDE.md\`（user-level 鐵則）
> Profile 邏輯與 ASP skills 詳見 \`~/.claude/asp/profiles/\` 與 \`~/.claude/skills/asp/\`

## 專案說明

[請填寫專案用途]

## 特殊規則（選填，覆蓋 user-level 預設）

[例如：禁止修改 legacy/ 目錄；必須保持向後相容]
CLAUDEMD
  success "CLAUDE.md（精簡版，≤15 行）"
fi

# .claude/settings.json（hooks 指向 user-level）
mkdir -p .claude
JQ_OK=false
command -v jq &>/dev/null && JQ_OK=true

HOOK_CMD_AUDIT="${HOME}/.claude/asp/hooks/session-audit.sh"
HOOK_CMD_ALLOW="${HOME}/.claude/asp/hooks/clean-allow-list.sh"

if [ "$JQ_OK" = true ]; then
  if [ -f ".claude/settings.json" ]; then
    # 升級：清理舊版 ASP hooks（project-local 路徑），加入 user-level 路徑
    jq --arg audit "$HOOK_CMD_AUDIT" --arg allow "$HOOK_CMD_ALLOW" '
      .hooks.SessionStart = [
        ((.hooks.SessionStart // [])[] |
          select((.hooks // []) | all(.command |
            test("(session-audit|clean-allow-list)\\.sh") | not))
        ),
        {"hooks": [
          {"type": "command", "command": $allow},
          {"type": "command", "command": $audit}
        ]}
      ] |
      .permissions.allow = ((.permissions.allow // []) + ["Bash(*)"] | unique)
    ' .claude/settings.json > .claude/settings.json.tmp \
      && mv .claude/settings.json.tmp .claude/settings.json
    success ".claude/settings.json（ASP hooks 更新為 user-level 路徑）"
  else
    jq -n --arg audit "$HOOK_CMD_AUDIT" --arg allow "$HOOK_CMD_ALLOW" '{
      "hooks": {
        "SessionStart": [{
          "hooks": [
            {"type": "command", "command": $allow},
            {"type": "command", "command": $audit}
          ]
        }]
      },
      "permissions": {
        "allow": ["Bash(*)"],
        "ask": [
          "Bash(git push *)", "Bash(git push)",
          "Bash(git rebase *)", "Bash(rm -rf *)", "Bash(rm -r *)",
          "Bash(docker push *)", "Bash(docker deploy *)"
        ]
      }
    }' > .claude/settings.json
    success ".claude/settings.json（hooks 指向 ~/.claude/asp/hooks/）"
  fi
else
  if [ ! -f ".claude/settings.json" ]; then
    cat > .claude/settings.json << HOOKJSON
{
  "hooks": {
    "SessionStart": [{
      "hooks": [
        {"type": "command", "command": "${HOME}/.claude/asp/hooks/clean-allow-list.sh"},
        {"type": "command", "command": "${HOME}/.claude/asp/hooks/session-audit.sh"}
      ]
    }]
  },
  "permissions": {
    "allow": ["Bash(*)"],
    "ask": ["Bash(git push *)", "Bash(git push)", "Bash(rm -rf *)", "Bash(rm -r *)"]
  }
}
HOOKJSON
    success ".claude/settings.json"
  fi
fi

# denied-commands 合併（從 user-level 讀取）
if [ "$JQ_OK" = true ] && [ -f "$USER_ASP/hooks/denied-commands.json" ]; then
  DENY_JSON=$(cat "$USER_ASP/hooks/denied-commands.json")
  jq --argjson ask "$DENY_JSON" '
    .permissions.ask = ((.permissions.ask // []) + $ask | unique)
  ' .claude/settings.json > .claude/settings.json.tmp \
    && mv .claude/settings.json.tmp .claude/settings.json
fi

# docs 目錄
mkdir -p docs/adr docs/specs
success "docs/adr/ docs/specs/"

# ADR-001（若無）
if ! ls docs/adr/ADR-001-*.md &>/dev/null 2>&1; then
  ADR_SRC="$USER_ASP/templates/ADR_Template.md"
  if [ -f "$ADR_SRC" ]; then
    cp "$ADR_SRC" docs/adr/ADR-001-initial-technology-stack.md
    SED_INPLACE "s/ADR-000/ADR-001/g; s/決策標題/初始技術棧選型/g; s/YYYY-MM-DD/$(date +%Y-%m-%d)/g" \
      docs/adr/ADR-001-initial-technology-stack.md
    success "docs/adr/ADR-001-initial-technology-stack.md（請填入技術棧）"
  fi
fi

# .gitignore（補充 ASP 相關條目）
ASP_GITIGNORE_ENTRIES=(
  ".asp-session-briefing.json"
  ".asp-audit-baseline.json"
  ".asp-bypass-log.ndjson"
  ".asp-telemetry.jsonl"
  ".asp-fact-check.md"
  ".asp-review-calibration.jsonl"
)
if [ -f ".gitignore" ]; then
  ADDED=0
  for entry in "${ASP_GITIGNORE_ENTRIES[@]}"; do
    if ! grep -qF "$entry" .gitignore; then
      echo "$entry" >> .gitignore
      ADDED=$((ADDED + 1))
    fi
  done
  [ "$ADDED" -gt 0 ] && success ".gitignore（補充 $ADDED 條 ASP 執行時檔案）"
fi

# ═══════════════════════════════════════════════════════════════════
# 完成
# ═══════════════════════════════════════════════════════════════════
echo ""
if [ "$IS_PROJECT_UPGRADE" = true ]; then
  echo "🎉 升級完成！（v${NEW_VERSION} @ ${NEW_COMMIT}）"
else
  echo "🎉 安裝完成！（v${NEW_VERSION} @ ${NEW_COMMIT}）"
fi
echo ""
echo "  每個專案只需："
echo "    .ai_profile           ← 專案設定"
echo "    CLAUDE.md             ← 精簡版行為設定"
echo "    .claude/settings.json ← hooks 指向 ~/.claude/asp/hooks/"
echo ""
echo "  ASP 核心在 ~/.claude/asp/（所有專案共用）"
echo "  更新 ASP：bash ~/.claude/scripts/asp-sync.sh"
echo ""
echo "  啟動 Claude Code，輸入："
echo "  「請讀取 CLAUDE.md，依照 .ai_profile 載入對應設定。」"
echo ""
echo "💡 建議：開始前執行 /asp-audit 做初始健康檢查"
echo ""
