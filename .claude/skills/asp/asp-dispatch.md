---
name: asp-dispatch
description: |
  Multi-agent task dispatch — classify task, recommend team, plan parallel execution.
  Triggers: dispatch, assign, 分派, 指派, 組隊
---

# ASP Dispatch — 多 Agent 任務分派

## 前置條件

- `.ai_profile` 已設定 `mode: multi-agent`
- `task_orchestrator.md` + `multi_agent.md` 已載入

## 工作流

### Step 1: 讀取任務

讀取使用者需求，確認上下文完整。

### Step 2: 分類任務

執行 `classify_task(request)` (task_orchestrator.md Part B)：
- NEW_FEATURE / BUGFIX / MODIFICATION / REMOVAL / GENERAL

向使用者確認分類結果。

### Step 3: 推薦團隊

根據 `.asp/agents/team_compositions.yaml` 的場景表：

```bash
# 查看可用場景
cat .asp/agents/team_compositions.yaml
```

選擇匹配的場景，列出建議的 agent 角色清單。

### Step 4: 依賴分析（如 parallel: true）

如果場景標記 `parallel: true`：
1. 執行 `analyze_requirement()` 識別模組
2. 執行 `decompose()` 拆分子任務
3. 執行 `plan_parallel_execution()` 產生軌道規劃：
   - Level 0: 獨立根（完全並行）
   - Level 1+: 依賴前層（層內並行）
4. 檢查鎖衝突

### Step 5: 產生 Task Manifest

為每個子任務建立 Task Manifest（multi_agent.md 格式）：

```yaml
task_id: TASK-{NNN}
agent: {role_id}
scope:
  allow: [...]
  forbid: [...]
input:
  - docs/specs/SPEC-{NNN}.md
output:
  - {expected output files}
done_when: "{testable condition}"
track: {A|B|C|...}     # if parallel
level: {0|1|2|...}     # topological level
```

### Step 6: 分派

向使用者確認分派計劃，然後：

```bash
# v4.1+ 統一入口（SPEC-004 Accepted；取代 v3.7 .agent-lock.yaml soft lock）
ASP_AUDIT_ROOT="$(git rev-parse --show-toplevel)" \
    bash .asp/scripts/multi-agent/dispatch.sh --manifests <manifests-dir>
```

dispatch.sh 自動：
1. 兩階段驗證 ASP_AUDIT_ROOT（fail-closed，exit 7 若驗證失敗）
2. scope.allow 重疊偵測（exit 5 若兩 task 範圍重疊）
3. 為每個 task 建獨立 git worktree + branch（檔案系統層硬隔離）
4. 寫 task manifest 到主 repo `.asp-task-manifests/<TID>.yaml`
5. emit `multi_agent.dispatch` telemetry

> ⚠️ v3.7 的 `.agent-lock.yaml` soft lock 已於 2026-05-09 (commit `10adbbe`) 廢止。
> 不要再呼叫 `make agent-unlock` / `make agent-lock-gc`，這些 target 是 deprecated。
> 改用 `make agent-worktree-list` / `make agent-worktree-gc` 管理 worktree 生命週期。

完整退出碼語意 + 場景：見 `docs/specs/SPEC-004-multi-agent-worktree-isolation.md`。

## 參考

- SPEC-004 多代理 worktree 規格：`docs/specs/SPEC-004-multi-agent-worktree-isolation.md`
- 角色定義：`.asp/agents/*.yaml`
- 團隊組成：`.asp/agents/team_compositions.yaml`
- 管線階段：`.asp/profiles/pipeline.md`
- 任務分類：`.asp/profiles/task_orchestrator.md` Part B
