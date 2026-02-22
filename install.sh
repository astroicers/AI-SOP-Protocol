#!/usr/bin/env bash
# AI-SOP-Protocol 安裝腳本
# 用途：在新專案或現有專案中快速植入 ASP

set -euo pipefail

PROTOCOL_REPO="https://github.com/YOUR_USERNAME/ai-sop-protocol"
PROTOCOL_DIR=".asp-tmp"

# 跨平台 sed
SED_INPLACE() {
    if [ "$(uname)" = "Darwin" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

echo ""
echo "🤖 AI-SOP-Protocol 安裝程式"
echo "=============================="

# 自動偵測專案類型
detect_type() {
    if [ -f "go.mod" ] || [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ]; then
        echo "system"
    elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
        echo "system"
    elif [ -f "package.json" ] && grep -qE '"react"|"vue"|"next"' package.json 2>/dev/null; then
        echo "system"
    else
        echo "content"
    fi
}

echo ""
DETECTED=$(detect_type)
echo "🔍 自動偵測專案類型：$DETECTED"
read -rp "確認類型（Enter 使用偵測值，或輸入 system/content/architecture）: " PROJECT_TYPE
PROJECT_TYPE="${PROJECT_TYPE:-$DETECTED}"

read -rp "專案名稱（Enter 使用目錄名）: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-$(basename "$(pwd)")}"

echo ""
read -rp "啟用 RAG 知識庫？（y/N）: " ENABLE_RAG
ENABLE_RAG="${ENABLE_RAG:-n}"

read -rp "啟用 Guardrail 護欄？（y/N）: " ENABLE_GUARDRAIL
ENABLE_GUARDRAIL="${ENABLE_GUARDRAIL:-n}"

read -rp "HITL 等級（minimal/standard/strict，Enter 使用 standard）: " HITL_LEVEL
HITL_LEVEL="${HITL_LEVEL:-standard}"

echo ""
echo "📥 安裝 AI-SOP-Protocol..."

# 建立必要目錄
mkdir -p docs/adr docs/specs

# 複製核心檔案
if git ls-remote "$PROTOCOL_REPO" &>/dev/null 2>&1; then
    git clone --depth=1 "$PROTOCOL_REPO" "$PROTOCOL_DIR" 2>/dev/null
    cp "$PROTOCOL_DIR/CLAUDE.md" ./CLAUDE.md
    cp -r "$PROTOCOL_DIR/profiles" ./profiles
    cp -r "$PROTOCOL_DIR/templates" ./templates
    cp -r "$PROTOCOL_DIR/scripts" ./scripts
    cp -r "$PROTOCOL_DIR/advanced" ./advanced
    [ ! -f "Makefile" ] && cp "$PROTOCOL_DIR/Makefile" ./Makefile
    [ ! -f ".gitignore" ] && cp "$PROTOCOL_DIR/.gitignore" ./.gitignore
    rm -rf "$PROTOCOL_DIR"
    echo "✅ 從 GitHub 安裝完成"
else
    echo "⚠️  無法連接 GitHub，請手動複製以下目錄："
    echo "   CLAUDE.md / profiles/ / templates/ / Makefile / .gitignore"
fi

# 建立 .ai_profile
RAG_VAL="disabled"
[ "${ENABLE_RAG,,}" = "y" ] && RAG_VAL="enabled"

GUARDRAIL_VAL="disabled"
[ "${ENABLE_GUARDRAIL,,}" = "y" ] && GUARDRAIL_VAL="enabled"

cat > .ai_profile << EOF
type: ${PROJECT_TYPE}
mode: single
workflow: standard
rag: ${RAG_VAL}
guardrail: ${GUARDRAIL_VAL}
hitl: ${HITL_LEVEL}
name: ${PROJECT_NAME}
EOF

echo "✅ 已建立 .ai_profile"

# 初始化 ADR-001（若不存在）
if ! ls docs/adr/ADR-001-*.md &>/dev/null 2>&1; then
    ADR_FILE="docs/adr/ADR-001-initial-technology-stack.md"
    cp templates/ADR_Template.md "$ADR_FILE"
    SED_INPLACE "s/ADR-000/ADR-001/g" "$ADR_FILE"
    SED_INPLACE "s/決策標題/初始技術棧選型/g" "$ADR_FILE"
    SED_INPLACE "s/YYYY-MM-DD/$(date +%Y-%m-%d)/g" "$ADR_FILE"
    echo "✅ 已建立 ADR-001（請填入實際技術棧）"
fi

# 初始化 architecture.md（若不存在）
if [ ! -f "docs/architecture.md" ]; then
    cp templates/architecture_spec.md docs/architecture.md
    SED_INPLACE "s/PROJECT_NAME/${PROJECT_NAME}/g" docs/architecture.md
    echo "✅ 已建立 docs/architecture.md"
fi

# 設定 RAG git hook
if [ "${ENABLE_RAG,,}" = "y" ] && [ -d ".git" ]; then
    HOOK_FILE=".git/hooks/post-commit"
    cat > "$HOOK_FILE" << 'HOOKEOF'
#!/usr/bin/env bash
if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "^docs/"; then
    echo "📚 docs/ 有異動，更新 RAG 索引..."
    make rag-index --silent 2>/dev/null || true
fi
HOOKEOF
    chmod +x "$HOOK_FILE"
    echo "✅ 已設定 RAG git hook（post-commit）"
fi

echo ""
echo "🎉 安裝完成！"
echo ""
echo "下一步："
echo "  1. 編輯 .ai_profile 確認設定"
echo "  2. 更新 docs/adr/ADR-001-*.md 填入實際技術棧"
echo "  3. 更新 docs/architecture.md 繪製架構圖"
echo "  4. 修改 Makefile 中的 APP_NAME"
if [ "${ENABLE_RAG,,}" = "y" ]; then
    echo "  5. pip install chromadb sentence-transformers"
    echo "  6. make rag-index"
fi
echo ""
echo "啟動 Claude Code 後，輸入："
echo "  「請讀取 CLAUDE.md，依照 .ai_profile 載入對應 Profile」"
echo ""
