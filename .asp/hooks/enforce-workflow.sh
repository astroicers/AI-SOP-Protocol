#!/usr/bin/env bash
# ASP Hook: enforce-workflow.sh
# PreToolUse (Edit|Write) — 工作流斷點，依 HITL 等級攔截檔案修改
#
# 對應規則：
#   - vibe_coding.md「HITL 等級」與「無條件暫停」
#   - system_dev.md「標準開發流程」ADR→設計→測試→實作
#   - global_core.md「連帶修復」

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0

# --- 讀取 HITL 等級 ---
HITL="standard"
PROFILE="${CLAUDE_PROJECT_DIR:-.}/.ai_profile"
if [ -f "$PROFILE" ]; then
    HITL_LINE=$(grep -E '^\s*hitl:\s*' "$PROFILE" 2>/dev/null || true)
    if [ -n "$HITL_LINE" ]; then
        HITL=$(echo "$HITL_LINE" | sed 's/.*hitl:\s*//' | tr -d '[:space:]')
    fi
fi

# 標準化 HITL 值
case "$HITL" in
    minimal|standard|strict) ;;
    *) HITL="standard" ;;
esac

# --- 分類檔案 ---
# 取檔名（不含路徑前綴）— 用於 basename 比對
BASENAME=$(basename "$FILE_PATH")

classify_file() {
    local fp="$1"

    # 敏感模組（unconditional）
    if echo "$fp" | grep -qiE '/(auth|crypto|security|secrets)/'; then
        echo "sensitive"
        return
    fi

    # 共用介面（unconditional）
    if echo "$fp" | grep -qiE '(\.proto|\.graphql|openapi\.|swagger\.)$'; then
        echo "interface"
        return
    fi
    if echo "$fp" | grep -qiE '/(interfaces|contracts)/'; then
        echo "interface"
        return
    fi

    # 文件/設定
    if echo "$fp" | grep -qiE '(^|/)docs/'; then
        echo "doc"
        return
    fi
    if echo "$fp" | grep -qiE '\.(md|txt|rst)$'; then
        echo "doc"
        return
    fi
    if echo "$fp" | grep -qiE '(^|/)(LICENSE|\.ai_profile|\.gitignore)'; then
        echo "doc"
        return
    fi
    if echo "$fp" | grep -qiE '(^|/)\.asp/'; then
        echo "doc"
        return
    fi

    # 測試檔案
    if echo "$fp" | grep -qiE '(^|/)(tests?|__tests__|spec)/'; then
        echo "test"
        return
    fi
    if echo "$fp" | grep -qiE '(_test\.|\.test\.|_spec\.|\.spec\.)[^/]*$'; then
        echo "test"
        return
    fi

    # 其餘皆為原始碼
    echo "source"
}

CATEGORY=$(classify_file "$FILE_PATH")

# --- 偵測刪除操作 ---
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
IS_DELETION=false

if [ "$TOOL_NAME" = "Edit" ]; then
    NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // "non-empty"')
    if [ -z "$NEW_STRING" ] || [ "$NEW_STRING" = "" ]; then
        IS_DELETION=true
    fi
fi

# 刪除操作覆蓋分類（unconditional）
if [ "$IS_DELETION" = true ]; then
    CATEGORY="deletion"
fi

# --- 決策矩陣 ---
ask_confirmation() {
    local reason="$1"
    jq -n --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: $reason
        }
    }'
    exit 0
}

SHORT_PATH=$(echo "$FILE_PATH" | sed "s|.*/\(.*/.*/.*\)|\1|")

case "$CATEGORY" in
    sensitive)
        ask_confirmation "🔒 ASP 斷點：修改 auth/crypto/security 模組 ($SHORT_PATH)，任何 HITL 等級都需確認（vibe_coding.md）"
        ;;
    interface)
        ask_confirmation "🔒 ASP 斷點：修改共用介面/API 合約 ($SHORT_PATH)，任何 HITL 等級都需確認（vibe_coding.md）"
        ;;
    deletion)
        ask_confirmation "⚠️ ASP 斷點：偵測到刪除現有代碼 ($SHORT_PATH)，任何 HITL 等級都需確認（vibe_coding.md）"
        ;;
    source)
        if [ "$HITL" = "standard" ] || [ "$HITL" = "strict" ]; then
            ask_confirmation "📋 ASP 工作流檢查點 (hitl: $HITL)：修改原始碼 ($SHORT_PATH)，請確認已按 ADR→設計→測試→實作 流程進行。緊急修復可覆蓋。（system_dev.md）"
        fi
        ;;
    test)
        if [ "$HITL" = "strict" ]; then
            ask_confirmation "📋 ASP 工作流檢查點 (hitl: strict)：所有檔案修改均需確認 ($SHORT_PATH)"
        fi
        ;;
    doc)
        if [ "$HITL" = "strict" ]; then
            ask_confirmation "📋 ASP 工作流檢查點 (hitl: strict)：所有檔案修改均需確認 ($SHORT_PATH)"
        fi
        ;;
esac

# 未攔截：放行
exit 0
