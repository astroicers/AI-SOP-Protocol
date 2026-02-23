#!/usr/bin/env bash
# ASP Hook: enforce-side-effects.sh
# PreToolUse (Bash) — 攔截危險指令，觸發 Claude Code 原生確認對話框
#
# 對應規則：
#   - CLAUDE.md 鐵則「副作用防護」
#   - global_core.md「副作用防護」清單
#   - system_dev.md「部署前檢查清單」
#
# 已知限制：
#   - 無法攔截 bash -c "..." / eval "..." / $(...) 等間接執行
#   - Shell 註解中的指令名稱可能誤觸發（低頻）

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$COMMAND" ] && exit 0

# 共用：輸出 ask 確認 JSON 並退出
ask() {
    jq -n --arg reason "$1" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: $reason
        }
    }'
    exit 0
}

# --- 部署指令（含檢查清單）---
if echo "$COMMAND" | grep -qiE '(^|\s|&&|\|)(make\s+deploy|docker[[:space:]-]compose\s+up)(\s|$|;)'; then
    ask "$(cat <<'MSG'
🔒 ASP 副作用防護：部署操作需確認

部署前檢查清單（system_dev.md）：
  □ 環境變數完整（對照 .env.example）
  □ 所有測試通過（make test）
  □ ADR 已標記 Accepted
  □ architecture.md 與當前代碼一致
  □ Dockerfile 無明顯優化缺失
MSG
)"
fi

# --- 版本控制副作用 ---
if echo "$COMMAND" | grep -qiE '(^|\s|&&|\|)git\s+(push|merge|rebase)(\s|$|;)'; then
    ask "🔒 ASP 副作用防護：git 操作（push/merge/rebase）需確認才能執行（global_core.md）"
fi

# --- 版本發布 ---
if echo "$COMMAND" | grep -qiE '(^|\s|&&|\|)(git\s+tag|npm\s+(publish|version)|yarn\s+publish)(\s|$|;)'; then
    ask "🔒 ASP 副作用防護：版本發布操作（tag/publish）需確認（global_core.md）"
fi

# --- K8s / Helm ---
if echo "$COMMAND" | grep -qiE '(^|\s|&&|\|)(helm\s+upgrade|kubectl\s+(apply|delete))(\s|$|;)'; then
    ask "🔒 ASP 副作用防護：Kubernetes 操作（helm/kubectl）需確認（global_core.md）"
fi

# --- Docker 推送/部署 ---
if echo "$COMMAND" | grep -qiE '(^|\s|&&|\|)docker\s+(push|deploy)(\s|$|;)'; then
    ask "🔒 ASP 副作用防護：Docker 推送/部署操作需確認（global_core.md）"
fi

# --- 破壞性刪除（rm -rf, rm -fr, rm -r, find -delete）---
if echo "$COMMAND" | grep -qiE '(^|\s|&&|\|)rm\s+-[a-z]*r' || echo "$COMMAND" | grep -qiE '(^|\s|&&|\|)find\s+.*-delete'; then
    ask "🔒 ASP 副作用防護：破壞性刪除操作（rm -rf / find -delete）需確認（global_core.md）"
fi

# --- 安全指令：放行 ---
exit 0
