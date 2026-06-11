#!/usr/bin/env bash
# ASP SessionStart Hook: session-audit.sh
# 在 clean-allow-list.sh 之後執行
#
# 功能：
#   1. Profile 驗證（A1: 7 rules）
#   2. 檔案結構掃描（A5: 11 rules）
#   3. ADR Draft 掃描 + 動態 deny（A3: 鐵則）
#   4. Tech Debt 過期掃描（A8: 7 rules）
#   5. 依賴健康檢查（A9: 5 rules）
#   6. 健康審計 baseline 檢查（A14: 7 rules）
#   7. 產生 .asp-session-briefing.json + 動態 deny patterns
#
# 此 hook 永遠 exit 0（不阻擋 session 啟動）

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
BRIEFING_FILE="${PROJECT_DIR}/.asp-session-briefing.json"
SETTINGS_FILE="${PROJECT_DIR}/.claude/settings.json"
# ADR-011: ASP 動態 deny 寫入 gitignored 的 settings.local.json（與 tracked settings.json
# / 使用者 deny 隔離）。Claude Code 以 deny-first 合併各 scope 的 deny（FC-001 已查證）。
LOCAL_SETTINGS_FILE="${PROJECT_DIR}/.claude/settings.local.json"
PROFILE_FILE="${PROJECT_DIR}/.ai_profile"

# 需要 jq
command -v jq &>/dev/null || {
    echo "⚠️ ASP session-audit: jq 未安裝，跳過審計" >&2
    exit 0
}

# ─── 收集器 ───
BLOCKERS=()
WARNINGS=()
INFOS=()
DYNAMIC_DENY=()

# ═══════════════════════════════════════════
# Iron Rule A: Hook Integrity Verification
# ═══════════════════════════════════════════
if git -C "${PROJECT_DIR}" rev-parse --git-dir &>/dev/null; then
    for CRITICAL_FILE in ".asp/hooks/denied-commands.json" ".asp/hooks/session-audit.sh"; do
        if git -C "${PROJECT_DIR}" show "HEAD:${CRITICAL_FILE}" &>/dev/null 2>&1; then
            CURRENT_HASH=$(sha256sum "${PROJECT_DIR}/${CRITICAL_FILE}" 2>/dev/null | cut -d' ' -f1)
            GIT_HASH=$(git -C "${PROJECT_DIR}" show "HEAD:${CRITICAL_FILE}" 2>/dev/null | sha256sum | cut -d' ' -f1)
            if [ "${CURRENT_HASH}" != "${GIT_HASH}" ]; then
                STAGED=$(git -C "${PROJECT_DIR}" diff --cached --name-only 2>/dev/null | grep -c "${CRITICAL_FILE}") || STAGED=0
                if [ "${STAGED}" -eq 0 ]; then
                    BLOCKERS+=("Iron Rule A: ${CRITICAL_FILE} modified outside git (hash mismatch). Run: git diff ${CRITICAL_FILE}")
                fi
            fi
        fi
    done
fi

# ═══════════════════════════════════════════
# Iron Rule B: Append-Only Bypass Log Integrity
# ═══════════════════════════════════════════
NDJSON_LOG="${PROJECT_DIR}/.asp-bypass-log.ndjson"
JSON_LOG="${PROJECT_DIR}/.asp-bypass-log.json"
HWM_FILE="${PROJECT_DIR}/.asp-bypass-log.hwm"
if [ -f "${JSON_LOG}" ] && [ ! -f "${NDJSON_LOG}" ]; then
    WARNINGS+=("Iron Rule B: .asp-bypass-log.json exists but not migrated to .ndjson format. Run: make asp-bypass-migrate")
fi
# TD-002: the bypass log is GITIGNORED (local-only — see .gitignore), so a
# git/HEAD baseline is ALWAYS empty and can never see a truncation. Instead track
# a high-water-mark of the line count across sessions in a sidecar. The append-only
# invariant means the count is monotonically non-decreasing, so any drop below the
# recorded HWM ⇒ audit entries were removed (whether committed or not, and even if
# they were appended-then-erased within a session). `awk END{print NR}` counts an
# unterminated final line too, so the check can't be gamed by toggling the trailing
# newline. The HWM is ratcheted UP only — a truncation keeps tripping the BLOCKER
# until the log is restored or the HWM is deliberately reset.
# Known residuals (documented, out of scope for a line-count heuristic): an
# equal-count entry REPLACEMENT, and tampering with the .hwm sidecar itself —
# both require a per-entry hash-chain to detect.
if [ -f "${NDJSON_LOG}" ]; then
    LINE_COUNT=$(awk 'END{print NR}' "${NDJSON_LOG}" 2>/dev/null)
    case "${LINE_COUNT}" in (''|*[!0-9]*) LINE_COUNT=0 ;; esac
    HWM_COUNT=0
    if [ -f "${HWM_FILE}" ]; then
        HWM_COUNT=$(cat "${HWM_FILE}" 2>/dev/null)
        case "${HWM_COUNT}" in (''|*[!0-9]*) HWM_COUNT=0 ;; esac
    fi
    if [ "${LINE_COUNT}" -lt "${HWM_COUNT}" ]; then
        BLOCKERS+=("Iron Rule B: .asp-bypass-log.ndjson shrank from ${HWM_COUNT} to ${LINE_COUNT} lines (append-only violated — audit entries removed). Restore the log, or reset the high-water-mark if intentional: rm ${HWM_FILE##*/}")
    elif [ "${LINE_COUNT}" -gt "${HWM_COUNT}" ]; then
        echo "${LINE_COUNT}" > "${HWM_FILE}" 2>/dev/null || true
    fi
fi

# ─── 輔助函數 ───
get_field() {
    grep "^${1}:" "$PROFILE_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'"
}

# ═══════════════════════════════════════════
# 1. Profile 驗證（A1: 7 rules）
# ═══════════════════════════════════════════
if [ -f "$PROFILE_FILE" ]; then
    TYPE=$(get_field "type")
    MODE=$(get_field "mode")
    HITL=$(get_field "hitl")
    AUTONOMOUS=$(get_field "autonomous")
    DESIGN=$(get_field "design")
    FRONTEND_QUALITY=$(get_field "frontend_quality")
    ORCHESTRATOR=$(get_field "orchestrator")
    AUTOPILOT=$(get_field "autopilot")

    # A1.5: type 必填
    if [ -z "$TYPE" ]; then
        BLOCKERS+=("A1.5: .ai_profile 缺少必填欄位 type")
    fi

    # A1.1: design → frontend_quality 依賴
    if [ "$DESIGN" = "enabled" ] && [ "$FRONTEND_QUALITY" != "enabled" ]; then
        WARNINGS+=("A1.3: design: enabled 但 frontend_quality 未啟用")
    fi

    # A1.4: multi-agent — v5 凍結為 Experimental（ADR-017；保留檢查容錯舊 profile）
    if [ "$MODE" = "multi-agent" ]; then
        WARNINGS+=("A1.4: mode: multi-agent — multi-agent 為 Experimental（v5 預設未安裝）；建議 mode: auto，或依 experimental/multi-agent/README.md 手動啟用")
    fi

    # hitl 值（用於 deny 嚴格度）
    HITL_LEVEL="${HITL:-standard}"
else
    WARNINGS+=("A1: .ai_profile 不存在，僅套用 CLAUDE.md 鐵則")
    TYPE=""
    HITL_LEVEL="standard"
fi

# ═══════════════════════════════════════════
# 1.5 Compiled Profile（A16，v5 ADR-016）
#     mtime 比對與重編全部委派 asp-compile --check（單一實作點）；
#     任何失敗都不擋 session（衝突=WARNING、其他=INFO 回退散文載入）
# ═══════════════════════════════════════════
COMPILED_OK=false
COMPILED_LINES=0
COMPILE_SCRIPT=""
for c in "${PROJECT_DIR}/.asp/scripts/asp-compile.sh" "${HOME}/.claude/asp/scripts/asp-compile.sh"; do
    [ -f "$c" ] && COMPILE_SCRIPT="$c" && break
done
if [ -n "$COMPILE_SCRIPT" ] && [ -f "$PROFILE_FILE" ]; then
    timeout 15 bash "$COMPILE_SCRIPT" --project "$PROJECT_DIR" --check --quiet >/dev/null 2>&1
    COMPILE_RC=$?
    case "$COMPILE_RC" in
        0) COMPILED_OK=true ;;
        1) WARNINGS+=("A16.1: profile 衝突，編譯中止——.ai_profile 設定互斥（跑 bash ${COMPILE_SCRIPT} 看衝突對）") ;;
        *) INFOS+=("A16.2: asp-compile 失敗 (rc=${COMPILE_RC})，回退散文 profile 載入") ;;
    esac
fi
[ -f "${PROJECT_DIR}/.asp-compiled-profile.md" ] && [ "$COMPILED_OK" = true ] \
    && COMPILED_LINES=$(awk 'END{print NR}' "${PROJECT_DIR}/.asp-compiled-profile.md")

# ═══════════════════════════════════════════
# 2. 檔案結構掃描（A5: 11 rules）
# ═══════════════════════════════════════════
MISSING_FILES=()
[ ! -f "$PROJECT_DIR/README.md" ]    && MISSING_FILES+=("README.md")
[ ! -f "$PROJECT_DIR/CHANGELOG.md" ] && MISSING_FILES+=("CHANGELOG.md")

# Makefile 檢查（A5.9）
if [ ! -f "$PROJECT_DIR/Makefile" ] && [ ! -f "$PROJECT_DIR/.asp/Makefile.inc" ]; then
    MISSING_FILES+=("Makefile")
fi

# Lock file 檢查（A5.3）
if [ -f "$PROJECT_DIR/package.json" ] && [ ! -f "$PROJECT_DIR/package-lock.json" ] && [ ! -f "$PROJECT_DIR/yarn.lock" ] && [ ! -f "$PROJECT_DIR/pnpm-lock.yaml" ]; then
    WARNINGS+=("A5.3: package.json 存在但無 lock file")
fi
if [ -f "$PROJECT_DIR/pyproject.toml" ] && [ ! -f "$PROJECT_DIR/poetry.lock" ] && [ ! -f "$PROJECT_DIR/uv.lock" ]; then
    WARNINGS+=("A5.3: pyproject.toml 存在但無 lock file")
fi

# .env.example 檢查（A5.4）
if [ -f "$PROJECT_DIR/.env" ] && [ ! -f "$PROJECT_DIR/.env.example" ]; then
    WARNINGS+=("A5.4: .env 存在但無 .env.example 範本")
fi

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    WARNINGS+=("A5: 缺失檔案: ${MISSING_FILES[*]}")
fi

# ═══════════════════════════════════════════
# 3. ADR Draft 掃描（A3: 鐵則）
# ═══════════════════════════════════════════
DRAFT_ADRS=()
FIRM_ADRS=()
ADR_DIR=""
for dir in "$PROJECT_DIR/docs/adr" "$PROJECT_DIR/docs/ADR" "$PROJECT_DIR/adr"; do
    [ -d "$dir" ] && ADR_DIR="$dir" && break
done

if [ -n "$ADR_DIR" ]; then
    while IFS= read -r adr_file; do
        [ -f "$adr_file" ] || continue
        # TD-004: anchor on the canonical 狀態/Status LABEL cell, then match the
        # status word anywhere in the VALUE cell — regardless of backticks, bold,
        # or in-cell annotations like （待確認）. This repo mixes formats:
        # `| **狀態** | `Draft` |`, `| **狀態** | Draft |` (no backticks, as in
        # SPEC-001/SPEC-004), and annotated `| **狀態** | `Draft`（待確認） |` all
        # denote a real status — a too-strict regex would let a genuinely-Draft ADR
        # bypass the commit BLOCKER. The label anchor keeps body prose out: the
        # status legend line `Draft`→`FIRM`→`Accepted` and a `驗證摘要` cell that
        # merely mentions `Draft` are NOT matched (their label cell is not 狀態).
        if grep -qiE "\|[[:space:]]*\*{0,2}(狀態|Status)\*{0,2}[[:space:]]*\|[^|]*\bDraft\b" "$adr_file" 2>/dev/null; then
            DRAFT_ADRS+=("$(basename "$adr_file")")
        elif grep -qiE "\|[[:space:]]*\*{0,2}(狀態|Status)\*{0,2}[[:space:]]*\|[^|]*\bFIRM\b" "$adr_file" 2>/dev/null; then
            FIRM_ADRS+=("$(basename "$adr_file")")
        fi
    done < <(find "$ADR_DIR" -name "ADR-*.md" -o -name "adr-*.md" 2>/dev/null)
fi

if [ ${#DRAFT_ADRS[@]} -gt 0 ]; then
    BLOCKERS+=("A3.1 鐵則: ADR Draft 存在 [${DRAFT_ADRS[*]}] — git commit 已被動態阻擋")
    DYNAMIC_DENY+=("Bash(git commit *)" "Bash(git commit)")
fi

if [ ${#FIRM_ADRS[@]} -gt 0 ]; then
    WARNINGS+=("A3.2 FIRM ADR: [${FIRM_ADRS[*]}] — 允許 commit，audit 輸出 🟡 YELLOW FLAG（需 Verification Evidence）")
fi

# ═══════════════════════════════════════════
# 4. Tech Debt 過期掃描（A8: 7 rules）
# ═══════════════════════════════════════════
OVERDUE_COUNT=0
TODAY=$(date +%Y-%m-%d)

# 掃描整個專案的 tech-debt 標記（排除 .git）
while IFS= read -r line; do
    due_date=$(echo "$line" | grep -oP 'DUE:\s*\K\d{4}-\d{2}-\d{2}' || true)
    if [ -n "$due_date" ] && [[ "$due_date" < "$TODAY" ]]; then
        OVERDUE_COUNT=$((OVERDUE_COUNT + 1))
    fi
# 排除框架文件路徑（profiles/templates/skills/runbooks 內的標記為「格式範例」非真實債務；
# 其範例日期過期會造成 A8.3 假陽性——2026-06-11 曾誤報 global_core.md 範例為 3 筆逾期 HIGH）
done < <(grep -rn "tech-debt:.*HIGH.*DUE:" "$PROJECT_DIR" --include="*.md" --include="*.sh" --include="*.yaml" --include="*.json" --exclude-dir=".git" 2>/dev/null \
    | grep -vE '(\.asp/profiles/|\.asp/templates/|\.claude/skills/|docs/runbooks/)' || true)

if [ "$OVERDUE_COUNT" -gt 0 ]; then
    WARNINGS+=("A8.3: $OVERDUE_COUNT 筆 HIGH tech-debt 已逾期")
fi

# ═══════════════════════════════════════════
# 5. 依賴健康檢查（A9: 5 rules）
# ═══════════════════════════════════════════
LOOSE_DEP_COUNT=0
if [ -f "$PROJECT_DIR/package.json" ]; then
    LOOSE_DEP_COUNT=$(grep -cE '"(\*|latest)"' "$PROJECT_DIR/package.json" 2>/dev/null) || LOOSE_DEP_COUNT=0
fi
if [ "$LOOSE_DEP_COUNT" -gt 0 ]; then
    WARNINGS+=("A9.2: package.json 有 $LOOSE_DEP_COUNT 筆鬆散版本（* 或 latest）")
fi

# ═══════════════════════════════════════════
# 6. 健康審計 baseline 檢查（A14: 7 rules）
# ═══════════════════════════════════════════
BASELINE_STALE=false
BASELINE_EXISTS=false
if [ -f "$PROJECT_DIR/.asp-audit-baseline.json" ]; then
    BASELINE_EXISTS=true
    last_audit=$(jq -r '.last_audit // ""' "$PROJECT_DIR/.asp-audit-baseline.json" 2>/dev/null)
    if [ -n "$last_audit" ]; then
        # 計算天數差（相容 GNU date）
        last_ts=$(date -d "$last_audit" +%s 2>/dev/null || echo 0)
        now_ts=$(date +%s)
        if [ "$last_ts" -gt 0 ]; then
            days_old=$(( (now_ts - last_ts) / 86400 ))
            if [ "$days_old" -gt 7 ]; then
                BASELINE_STALE=true
                INFOS+=("A14.2: 健康審計 baseline 已 ${days_old} 天未更新（建議執行 make audit-health）")
            fi
        fi
    fi
else
    INFOS+=("A14.1: .asp-audit-baseline.json 不存在（建議執行 make audit-health）")
fi

# ═══════════════════════════════════════════
# 7. Task Inbox held 回報（inbox-ingest.sh，SPEC-007）
# ═══════════════════════════════════════════
# SPEC-007（ADR-012 INV-2/DP8/T-14）：外部任務不再自動注入 ROADMAP，
# 僅回報 held；人類授權路徑由 SPEC-009 / asp-op pivot 提供。
INBOX_FILE="${PROJECT_DIR}/.asp-task-inbox.json"
INBOX_SCRIPT="${PROJECT_DIR}/.asp/scripts/inbox-ingest.sh"
if [ -f "$INBOX_FILE" ] && [ -f "$INBOX_SCRIPT" ]; then
    INBOX_PENDING=$(jq '[.[] | select(.status == "pending")] | length' "$INBOX_FILE" 2>/dev/null || echo 0)
    if [ "$INBOX_PENDING" -gt 0 ]; then
        bash "$INBOX_SCRIPT" 2>&1 | grep -v "^$" || true
        WARNINGS+=("A15.1: Task Inbox ${INBOX_PENDING} 個外部任務 held（人類授權：make inbox-triage）")
    fi
fi

# ═══════════════════════════════════════════
# 8. 測試結果檢查（A4.7: commit 前需 test）
# ═══════════════════════════════════════════
TEST_RESULT_EXISTS=false
if [ -f "$PROJECT_DIR/.asp-test-result.json" ]; then
    TEST_RESULT_EXISTS=true
    test_passed=$(jq -r '.passed // false' "$PROJECT_DIR/.asp-test-result.json" 2>/dev/null)
    if [ "$test_passed" != "true" ]; then
        INFOS+=("A4.7: 上次測試未通過，commit 前需重新執行 make test")
    fi
fi

# ═══════════════════════════════════════════
# 9. 產生 briefing JSON
# ═══════════════════════════════════════════
{
    # 用 heredoc 構建 JSON 避免複雜的 jq 參數傳遞
    cat <<JSONEOF
{
  "version": "1.0",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hitl_level": "$HITL_LEVEL",
  "profile": {
    "exists": $([ -f "$PROFILE_FILE" ] && echo true || echo false),
    "type": "${TYPE:-null}"
  },
  "blockers": $(if [ ${#BLOCKERS[@]} -gt 0 ]; then printf '%s\n' "${BLOCKERS[@]}" | jq -R . | jq -s .; else echo '[]'; fi),
  "warnings": $(if [ ${#WARNINGS[@]} -gt 0 ]; then printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .; else echo '[]'; fi),
  "infos": $(if [ ${#INFOS[@]} -gt 0 ]; then printf '%s\n' "${INFOS[@]}" | jq -R . | jq -s .; else echo '[]'; fi),
  "draft_adrs": $(if [ ${#DRAFT_ADRS[@]} -gt 0 ]; then printf '%s\n' "${DRAFT_ADRS[@]}" | jq -R . | jq -s .; else echo '[]'; fi),
  "firm_adrs": $(if [ ${#FIRM_ADRS[@]} -gt 0 ]; then printf '%s\n' "${FIRM_ADRS[@]}" | jq -R . | jq -s .; else echo '[]'; fi),
  "missing_files": $(if [ ${#MISSING_FILES[@]} -gt 0 ]; then printf '%s\n' "${MISSING_FILES[@]}" | jq -R . | jq -s .; else echo '[]'; fi),
  "overdue_tech_debt_count": $OVERDUE_COUNT,
  "loose_dependency_count": $LOOSE_DEP_COUNT,
  "baseline_stale": $BASELINE_STALE,
  "baseline_exists": $BASELINE_EXISTS,
  "test_result_exists": $TEST_RESULT_EXISTS,
  "compiled_profile_ok": $COMPILED_OK,
  "compiled_profile_lines": $COMPILED_LINES,
  "dynamic_deny": $(if [ ${#DYNAMIC_DENY[@]} -gt 0 ]; then printf '%s\n' "${DYNAMIC_DENY[@]}" | jq -R . | jq -s .; else echo '[]'; fi)
}
JSONEOF
} > "$BRIEFING_FILE" 2>/dev/null || true

# ═══════════════════════════════════════════
# 10. 同步動態 deny 到 settings.local.json（ADR-011：自我清除 / 冪等）
#     ASP 只寫 gitignored 的 settings.local.json，**永不觸碰 tracked settings.json**
#     （使用者 / 團隊 deny 的家）。settings.local.json 不進 git → 動態 deny 不會被 commit
#     → 根除 tracked/gitignored 狀態分裂（換機卡死 / 暫態污染）。Claude Code 以 deny-first
#     合併各 scope 的 deny（FC-001），故強制力等價。
#     sidecar (.asp-managed-deny.json) 記錄「ASP 實際注入」的條目，reconcile 只移除這些
#     ASP-owned 條目；使用者若也在 settings.local.json 放相同字串，不會被記為 owned 而誤刪。
# ═══════════════════════════════════════════
MANAGED_DENY_STATE="${PROJECT_DIR}/.asp-managed-deny.json"
# 只在「有 deny 要注入（Draft 存在）」或「local 設定已存在（需 reconcile/自清）」時才動作——
# 避免在無 Draft 的乾淨專案憑空建立空的 settings.local.json。
if command -v jq &>/dev/null \
   && { [ ${#DYNAMIC_DENY[@]} -gt 0 ] || [ -f "$LOCAL_SETTINGS_FILE" ]; }; then
    if [ ! -f "$LOCAL_SETTINGS_FILE" ]; then
        mkdir -p "$(dirname "$LOCAL_SETTINGS_FILE")" 2>/dev/null || true
        echo '{"permissions":{"deny":[]}}' > "$LOCAL_SETTINGS_FILE" 2>/dev/null || true
    fi
    if [ -f "$MANAGED_DENY_STATE" ]; then
        PREV_MANAGED=$(jq -c 'if type=="array" then . else [] end' "$MANAGED_DENY_STATE" 2>/dev/null)
    fi
    [ -z "${PREV_MANAGED:-}" ] && PREV_MANAGED='[]'
    if [ ${#DYNAMIC_DENY[@]} -gt 0 ]; then
        ADD_DENY=$(printf '%s\n' "${DYNAMIC_DENY[@]}" | jq -R . | jq -s .)
    else
        ADD_DENY='[]'
    fi
    #   cleaned = deny − PREV_MANAGED（只移除 ASP 先前注入的，不碰使用者自有的）
    #   added   = ADD_DENY − cleaned（本次實際新增者＝使用者原本沒有的）→ 記為下次可移除集合
    RECON=$(jq -c --argjson prev "$PREV_MANAGED" --argjson add "$ADD_DENY" '
            ((.permissions.deny // []) - $prev) as $cleaned
            | { settings: (.permissions.deny = (($cleaned + $add) | unique)),
                added: ($add - $cleaned) }
        ' "$LOCAL_SETTINGS_FILE" 2>/dev/null)
    # 覆寫前驗證 .tmp 非空且為合法 JSON（cmp -s 只比「不同」不比「合法」；第二次 jq 寫入
    # 若因磁碟滿等失敗會留下壞檔）。settings.local.json 為本地可重建檔，故不另存 .bak。
    if [ -n "$RECON" ] \
       && echo "$RECON" | jq -e '.settings' > "${LOCAL_SETTINGS_FILE}.tmp" 2>/dev/null \
       && [ -s "${LOCAL_SETTINGS_FILE}.tmp" ] \
       && jq -e . "${LOCAL_SETTINGS_FILE}.tmp" >/dev/null 2>&1; then
        if cmp -s "${LOCAL_SETTINGS_FILE}.tmp" "$LOCAL_SETTINGS_FILE"; then
            rm -f "${LOCAL_SETTINGS_FILE}.tmp"
        else
            mv "${LOCAL_SETTINGS_FILE}.tmp" "$LOCAL_SETTINGS_FILE"
        fi
        # 記錄本次 ASP 實際擁有的注入集合（可能為空 → 下次不移除任何條目）
        echo "$RECON" | jq -c '.added' > "$MANAGED_DENY_STATE" 2>/dev/null || true
    else
        rm -f "${LOCAL_SETTINGS_FILE}.tmp" 2>/dev/null || true
    fi
fi

# ═══════════════════════════════════════════
# 11. 輸出摘要（SessionStart hook stdout 會被 AI 讀取）
# ═══════════════════════════════════════════
echo ""
echo "## ASP Session Audit"

if [ ${#BLOCKERS[@]} -gt 0 ]; then
    echo "### BLOCKERS"
    for b in "${BLOCKERS[@]}"; do echo "- $b"; done
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "### WARNINGS"
    for w in "${WARNINGS[@]}"; do echo "- $w"; done
fi

if [ ${#INFOS[@]} -gt 0 ]; then
    echo "### INFO"
    for i in "${INFOS[@]}"; do echo "- $i"; done
fi

if [ ${#BLOCKERS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
    echo "All clear."
fi

echo "---"
echo "Briefing: .asp-session-briefing.json | Dynamic deny: ${#DYNAMIC_DENY[@]} patterns"
echo ""

# 永遠成功（不阻擋 session）
exit 0
