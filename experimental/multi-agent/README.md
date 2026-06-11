# Experimental: Multi-Agent Worktree 並行

<!-- Status: FROZEN (v5.0, ADR-017) -->

> **凍結中（v5.0 起）**。本目錄內容不維護、不演進、不進預設安裝路徑
> （install.sh 只複製 `.asp/*` 與 `.claude/skills/*`）。
>
> **解凍條件**：出現「單一 session 無法完成」的實際案例（非假設場景）。
> 解凍時：建解凍 ADR → `make test-experimental` 重建綠基準 → 評估遷移成本。
>
> **長期方向**：改建於 Claude Code 原生 subagent（Agent tool / 自訂 agent
> registry），而非自管 git worktree 池。

## 內容

| 目錄 | 內容 | 來源 |
|------|------|------|
| `scripts/` | dispatch / converge / rollback / scope-guard / worktree-gc / worktree-list / audit-write / _validate_audit_root（8 支，SPEC-004） | `.asp/scripts/multi-agent/` |
| `agents/` | 10 個角色 yaml + team_compositions.yaml（場景表） | `.asp/agents/` |
| `skills/` | asp-dispatch / asp-team-pick / asp-handoff | `.claude/skills/asp/` |
| `profiles/` | orchestrator_multi_agent.md（task_orchestrator Part G，ADR-015 抽出） | `.asp/profiles/` |
| `tests/` | test_spec_004_* ×7 + validate_audit_root + converge_crypto_gate + perf/ | `tests/` |

歷史決策：ADR-010（UA orchestration patterns）、SPEC-004（worktree 隔離，驗收 21/21）。
凍結不否定其驗收——只反映「無實際使用案例下暫停維護投資」（ADR-017）。

## 手動啟用（解凍前不建議）

1. `Makefile.inc` 由 core 的 `-include experimental/multi-agent/Makefile.inc` 自動載入
   （目錄存在即生效）——`make agent-worktree-list` 等 targets 可用。
2. scope-guard PreToolUse hook（v5 已自 `.claude/settings.json` 移除）需手動加回：

```json
"PreToolUse": [{
  "matcher": "Write|Edit|NotebookEdit",
  "hooks": [{"type": "command",
    "command": "bash \"$CLAUDE_PROJECT_DIR\"/experimental/multi-agent/scripts/scope-guard.sh \"$CLAUDE_TOOL_INPUT_FILE_PATH\""}]
}]
```

3. skills 需自行複製到 `~/.claude/skills/asp/`（router 條目已自 SKILL.md 移除）。
4. 測試：`make test-experimental`（不在 `make test` 快速路徑——凍結代碼不阻擋日常 commit）。

## 角色 ↔ Skill 映射（自 SKILL.md 遷入，v5）

| Agent 角色 | 對應 Skill | 角色定義 |
|-----------|-----------|---------|
| Orchestrator | asp-dispatch | 任務分類 + 團隊推薦 + 分派 |
| arch / spec | asp-plan | ADR + SPEC |
| dep-analyst | asp-impact | 依賴圖 + 並行標記 |
| qa | asp-dev-qa-loop | 獨立驗證 + 偷渡偵測 |
| sec | asp-ship (Step 9) | OWASP + 憑證掃描 |
| reality | asp-reality-check | 懷疑主義驗收 |
| doc | asp-ship | 文件管線 |
| tdd / impl / integ | （asp-plan TDD 步驟 / SPEC 實作 / asp-dispatch converge） | |
