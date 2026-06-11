# Orchestrator Multi-Agent — 並行任務分派協調（task_orchestrator Part G 抽出）

<!-- requires: global_core, system_dev, task_orchestrator -->
<!-- optional: autonomous_dev, reality_checker -->
<!-- conflicts: loose_mode -->

<!-- Status: FROZEN candidate — v5 Phase 2（ADR-015）自 task_orchestrator.md Part G
     :891-1130 逐字抽出；Phase 4（ADR-017）隨 multi-agent 整體移入 experimental/。
     凍結中：勿改本檔內文（解凍條件見 experimental/multi-agent/README.md，Phase 4 後）。 -->

載入條件：`mode: multi-agent`（由 profile-map.yaml 綁定，與 task_orchestrator 一併載入）

> 以下內文為 task_orchestrator.md Part G 逐字搬移（含 Phase 1 對原 :1061 的
> ADR-014 D5 修正——與 v4.3 pristine 歸檔的唯一已知差異）。

---

## Part G: Multi-Agent 整合

> **v4.3 合併**：`multi_agent.md` 內容已整合於此。原 canonical source 為 `multi_agent.md`（v4.2 前），v4.3 起本節為唯一來源。
> Autonomous Worker 擴展規則見 `autonomous_dev.md`「Multi-Agent 整合」。

適用：`mode: multi-agent`，並行任務分治、大型功能拆解。

> **與 committee 模式的區別**（committee mode 已於 2026-05-10 deprecated）：
> - `multi-agent`：實作期使用，需求已確定，拆分為並行子任務加速執行。
> - ~~`committee`：決策期使用。~~ → 已 archive；高風險決策改用 `/asp-plan` + ADR + 人類 review。

> ⚠️ **v3.7「Context 全量傳遞」機制已廢止（D-001, 2026-05-04）**：
> 新作法採 `/clear` + scratchpad（檔案路徑 + hash + 邊界限制）取代 context dump，
> 避免跨 agent prompt injection 污染。完整 worktree 隔離架構已於 v4.1 實作（SPEC-004 Accepted）。

### 角色分派

Orchestrator 根據 `team_compositions.yaml` 選擇角色：

```
FUNCTION assign_roles(task_type, complexity):
  scenario = match_scenario(task_type, complexity)  // from team_compositions.yaml
  team = scenario.agents
  FOR role IN team:
    role_def = LOAD(".asp/agents/{role}.yaml")
    // role_def 提供 description / personality / capabilities / decision_examples
  RETURN team
```

> **v4.1.1**：scope 強制在 SPEC-004 的 TASK manifest（`scope.allow` / `scope.forbid`）+ git worktree 檔案系統隔離。Agent yaml 的 `scope_constraints` / `max_spawn_depth` 是描述性欄位，無 enforcement 程式碼。

### Orchestrator 職責

開始並行任務前，必須完成：

```
1. 讀取 docs/architecture.md 與 docs/adr/ 確認現況
2. 將需求拆解為低耦合子任務
3. 為每個子任務定義 Task Manifest（見下）
4. 指派 Worker，設定 Done Definition（呼叫 assign_roles(type, complexity)）
```

> ⚠️ v3.7「建立 `.agent-lock.yaml` 登記文件鎖定」已廢止（D-001, 2026-05-04）。
> 改用 git worktree 硬性隔離（SPEC-004），每 agent 一個 worktree，無需檔案鎖。

### Task Manifest 格式

```yaml
task_id: TASK-001
agent: worker-a
scope:
  allow:  [src/store/, src/api/routes.go]
  forbid: [src/auth/, src/config/]
input:
  - docs/specs/SPEC-XXX.md
output:
  - src/store/feature_x.go
  - tests/store/feature_x_test.go
done_when: "make test-filter FILTER=feature_x 全數通過"
agent_role: impl          # role from .asp/agents/
track: A                  # parallel track identifier
level: 0                  # topological level (0=independent)
```

### 衝突隔離（v4.1 起：git worktree 硬性隔離）

每個 Worker 在獨立的 git worktree 中工作，由 Orchestrator 在 `converge` 階段以 git merge 匯流。隔離由檔案系統層保證，**不靠 AI 自律**。

```bash
# Dispatch：為每個 task 建 worktree + branch
# ASP_AUDIT_ROOT 錨定「主 repo」（git-common-dir）—— 即使從 worktree 內執行也指向主 repo，
# audit/bypass/escalation NDJSON 一律寫主 repo（SPEC-004 §🔒）。worktree 作 audit root 會被
# _validate_audit_root Stage D2 以 exit 7 擋下（ADR-010 Pattern B fail-closed）。
ASP_AUDIT_ROOT="$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")" \
    bash .asp/scripts/multi-agent/dispatch.sh --manifests <dir>

# Converge：rebase + merge 每個完成的 task
ASP_AUDIT_ROOT="$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")" \
    bash .asp/scripts/multi-agent/converge.sh --task TASK-001 --task TASK-002

# List + GC（運維）
make agent-worktree-list
make agent-worktree-gc-dry-run
make agent-worktree-gc
```

**強制要求**：
- `ASP_AUDIT_ROOT` 必填，必須是主 repo 的絕對路徑。未設定 / 相對路徑 / 非 git repo → exit 7。
- 所有 Worker 寫入 bypass / telemetry / escalation log 一律走 `audit-write.sh` wrapper。
- `max_parallel` 硬上限 10 個 worker；超過 → exit 6。
- scope.allow 重疊偵測在 dispatch 階段拒絕（exit 5）。

**規格書**：`docs/specs/SPEC-004-multi-agent-worktree-isolation.md`（Accepted）

**退出碼**：1=scope/path outside repo / 2=bad args / 3=merge conflict / 4=disk space / 5=scope overlap / 6=max_parallel / 7=ASP_AUDIT_ROOT invalid / 8=rollback verify failed / 13=install runtime precheck failed

### 並行軌道

```
FUNCTION plan_parallel_execution(sub_tasks):
  graph = build_dependency_graph(sub_tasks)
  levels = topological_levels(graph)

  execution_plan = []
  FOR level_num, tasks IN levels:
    track_group = {
      level: level_num,
      tracks: [],
      marker: "[P]" if LEN(tasks) > 1 else "[S]"
    }
    FOR task IN tasks:
      track = {
        task: task,
        assigned_role: select_role(task),
        locked_files: task.scope.allow,
        track_id: NEXT_TRACK_ID()
      }
      track_group.tracks.append(track)
    execution_plan.append(track_group)

  // 鎖衝突偵測
  FOR group IN execution_plan:
    all_locks = flatten(t.locked_files FOR t IN group.tracks)
    IF has_duplicates(all_locks):
      resolve_lock_conflicts(group)  // 移到下一層 or 指派 integ agent

  RETURN execution_plan


FUNCTION converge_tracks(completed_tracks, integ_agent):
  handoffs = [track.final_handoff FOR track IN completed_tracks]
  conflicts = integ_agent.detect_conflicts(handoffs)
  IF conflicts:
    FOR conflict IN conflicts:
      IF conflict.resolvable:
        integ_agent.resolve(conflict)
      ELSE:
        escalate(severity="P1", reason="並行軌道不可解衝突", context={conflict})
  result = EXECUTE("make test")
  IF result.failed:
    INVOKE_SKILL("/asp-dev-qa-loop", task=integration_task, dev=integ_agent, qa=qa_agent)
```

### MCP 安全邊界

Worker Agent 可自行執行：
- filesystem MCP：讀寫自己 scope 內的文件
- bash MCP：`make test-filter`、`make lint`

需要 Orchestrator 審核才能執行：
- git push / git merge
- 刪除操作（rm、DROP TABLE）
- 外部 API 的寫入操作
- 環境變數修改 / Docker image 推送

### Worker 完成流程

```
FUNCTION on_worker_done(handoff):
  task = handoff.task_id
  test_result = EXECUTE("make test-filter FILTER={task.manifest.scope.filter}")

  IF test_result.passed:
    IF pipeline_active:
      gate_result = evaluate_gate(current_gate, artifacts, gate_agents)
    IF autonomous_enabled:
      // 可自動合併到工作分支（非主分支）
    ELSE:
      AWAIT human_confirm("merge")
  ELSE:
    IF task.retry_count < MAX_RETRIES(2):  // 升級路徑隨 global_core 永遠載入（ADR-014 D5）
      memory_hint = get_memory_hint(task, handoff.failure_context)
      reassign(task, create_handoff(REASSIGNMENT, memory_ref=memory_hint))
    ELSE:
      escalate(severity="P1", reason="Worker auto_fix + Orchestrator 重派皆耗盡", task_id=task.id)
```

#### Worker 輸出契約（`.asp-out/`，ADR-010 Pattern A）

每個 Worker 在自己的 worktree 內，把產出落在固定的 canonical 目錄（與 `.asp-worktrees/<task>/` 並列），讓 Orchestrator 能**確定性定位**產出（強化 v4.1 D-001 scratchpad 慣例）：

```
.asp-worktrees/<task-id>/.asp-out/
  summary.txt      # 一行 summary（agent 對 Orchestrator 回傳的唯一內容）
  diff.txt         # → TASK_COMPLETE.artifacts.diff_summary
  test-output.txt  # → TASK_COMPLETE.artifacts.test_output
  checksums.json   # → TASK_COMPLETE.artifacts.test_checksums（smuggling 偵測）
  handoff.yaml     # TASK_COMPLETE.yaml 實例
```

- **強制檔名**（ASP 風格：**log 不擋**，經 `audit-write.sh` telemetry，不新增 fail-closed 卡點）：
  `^(summary|diff|test-output|checksums|handoff)\.(txt|json|yaml)$`
- **Worker 對 Orchestrator 只回一行**（其餘細節落 `.asp-out/`，避免噪音淹沒上下文）：
  `TASK-NNN <status> | out=<path> | files=<n> | tests=<summary>`
- 暫定**僅約定 + log**；未來如需 converge 自動收集再接線（ADR-010 §7 Q5）。

### Sub-Agent 深度準則（設計約束，非執行性）

- Orchestrator 是任務拆解唯一入口
- Worker 遇到超出能力的子問題 → 上報 escalation_target，由 Orchestrator 重新分派
- Worker 若呼叫 Task 工具，子 agent 結果以 tool response 形式注入主迴圈，不可再派生第三層

### 交接單類型參考

| 類型 | 用途 | 產生方 |
|------|------|--------|
| `TASK_COMPLETE` | Worker 完成單一任務 | Worker |
| `REASSIGNMENT` | Orchestrator 重派任務（含 memory hint） | Orchestrator |
| `PHASE_GATE` | Pipeline 階段轉換（G1-G6 通過） | Orchestrator |
| `ESCALATION` | 重試耗盡，升級至人類 | Orchestrator |
| `SESSION_BRIDGE` | 跨 session 上下文保留 | Orchestrator |
| `SPRINT_SUMMARY` | Sprint 邊界彙總（autopilot 跨 session 用） | Orchestrator |

交接單格式詳見 `.asp/templates/handoff/`。

### Dispatch 入口函數

當 `mode: multi-agent` 且 TASK_GENERAL 分解出多個獨立子任務時：

```
FUNCTION multi_agent_dispatch(sub_tasks):

  FOR sub_task IN sub_tasks:
    manifest = {
      task_id:   "TASK-{NNN}",
      workflow:  sub_task.type,
      scope:     infer_scope(sub_task),
      input:     [sub_task.spec],
      output:    infer_outputs(sub_task),
      done_when: sub_task.spec.done_when
    }
    team = recommend_team(sub_task.type, sub_task)
    manifest.agent_role = select_role_for_subtask(sub_task, team)

  CALL orchestrator_dispatch(manifests)
  EXECUTE("make test")  // 跨任務整合測試
```

---

