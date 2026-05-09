# SPEC-004：Multi-Agent Worktree 硬性隔離

> 結構完整的規格書讓 AI 零確認直接執行。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-004 |
| **關聯 ADR** | D-001（v4-decision-log）；ADR-002（Iron Rules） |
| **估算複雜度** | 中 |
| **建議模型** | Sonnet（涉及 git plumbing + multi-agent orchestration，需要精準 shell 操作） |
| **HITL 等級** | strict（涉及 worktree 建立 + 跨 branch merge，需人類審查） |
| **狀態** | Draft |
| **日期** | 2026-05-10 |

---

## 🎯 目標（Goal）

讓 multi-agent 並行任務真正以**檔案系統層級隔離**運作：每個 Worker 在獨立的 git worktree 中工作，由 Orchestrator 在 `converge_tracks` 階段以 git merge 匯流。取代 v3.7 廢止的 `.agent-lock.yaml` 軟性檔案鎖（D-001 決策已標記廢止，但 v4.0 未實作替代方案）。

**為誰有價值**：跑 multi-agent 並行任務的 L4-L5 使用者。目前 v4.0 處於「無隔離機制」狀態，必須改為單軌序列執行才安全；本 SPEC 解放並行能力。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| task_manifests | list[TaskManifest] | Orchestrator 拆解結果 | 至少 1 個任務；每個任務有獨立 `agent_role` |
| base_branch | string | git 當前 HEAD（預設） | 必須存在於 local repo |
| max_parallel | int | `.ai_profile` 或 CLI 參數 | 1-10（超過 10 視為異常，要求人類確認） |
| worktree_root | path | 預設 `.asp-worktrees/` | 必須在 repo root 內，不可指向 repo 外 |

**TaskManifest schema**（沿用 v3.7，新增 `worktree_branch` 欄位）：

```yaml
task_id: TASK-001
agent: worker-a
agent_role: impl
scope:
  allow:  [src/store/, src/api/routes.go]
  forbid: [src/auth/, src/config/]
worktree_branch: feat/spec-004-task-001  # NEW: Orchestrator 指派
input:
  - docs/specs/SPEC-XXX.md
output:
  - src/store/feature_x.go
  - tests/store/feature_x_test.go
done_when: "make test-filter FILTER=feature_x 全數通過"
```

---

## 📤 輸出規格（Expected Output）

**成功情境**（單一任務完成）：

```jsonc
{
  "task_id": "TASK-001",
  "status": "success",
  "worktree_path": ".asp-worktrees/task-001/",
  "worktree_branch": "feat/spec-004-task-001",
  "files_modified": ["src/store/feature_x.go", "tests/store/feature_x_test.go"],
  "test_result": { "passed": 12, "failed": 0 },
  "merge_status": "pending_orchestrator_converge"
}
```

**Orchestrator converge 完成後**：

```jsonc
{
  "spec_id": "SPEC-XXX",
  "tracks_converged": ["TASK-001", "TASK-002", "TASK-003"],
  "merge_strategy": "sequential_no_conflict",  // or "rebase_required"
  "conflicts": [],
  "final_branch": "feat/spec-xxx",
  "worktrees_cleaned": 3
}
```

**失敗情境**：

| 錯誤類型 | 退出碼 | 處理方式 |
|----------|-------|----------|
| Worktree 路徑指向 repo 外 | 1 | 拒絕建立，要求人類修正配置 |
| Worker 修改超出 `scope.allow` | 2 | Worker 中止任務、寫入 `.asp-bypass-log.ndjson`，回報 Orchestrator |
| Merge 衝突 | 3 | Orchestrator 暫停 converge、列出衝突檔案、等待人類解決 |
| Worktree 殘留 > max_parallel | 4 | `make agent-worktree-gc` 清理（>2 小時 idle 視為異常） |

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| 建立新 git worktree | 每個 task dispatch 時 | `.git/worktrees/`、`.asp-worktrees/` | `git worktree list` 含新分支；P1 |
| 建立新 branch | worktree 建立時 | git refs | `git branch --list feat/spec-004-*`；P1 |
| 寫入 task manifest | dispatch 後 | `.asp-task-manifests/TASK-XXX.yaml` | YAML 檔案存在且 schema valid；P2 |
| Merge 到 base branch | converge 階段 | base branch HEAD | `git log` 含合併 commit；P5 |
| 清理 worktree | 任務完成 / GC 觸發時 | `.asp-worktrees/`、`.git/worktrees/` | `git worktree prune` 無殘留；B3 |
| 寫入 telemetry 事件 | dispatch / converge / fail 時 | `.asp-telemetry.ndjson` | NDJSON 含 `multi_agent.dispatch` event；驗證見 telemetry SPEC |

> 每個副作用都有對應驗證 ID（見測試矩陣）。G5 Gate 會檢查。

---

## ⚠️ 邊界條件（Edge Cases）

- **Case 1**：兩個 Worker 的 `scope.allow` 重疊 → Orchestrator 必須在 dispatch 前偵測並拒絕，要求重新拆解
- **Case 2**：Worker 在 worktree 中執行 `git push`（破壞性操作）→ 鐵則攔截，要求人類確認
- **Case 3**：base_branch 在 Worker 工作期間有新 commit（並行 commit）→ converge 時 rebase，rebase 失敗則暫停等人類
- **Case 4**：Worker 異常終止（process killed、context overflow）→ worktree 保留，下次 session 啟動時 `make agent-worktree-gc` 列出 stale worktree
- **Case 5**：磁碟空間不足以建 worktree → dispatch 階段 `df -h` 預檢，< 1GB 警告、< 100MB 拒絕
- **Case 6**：Worker 嘗試 `cd ..` 跳出 worktree → scope.forbid 強制執行，違反則寫入 bypass log
- **Case 7**：兩個 task 都修改 base branch 共用檔案（無法靠 scope 完全隔離的情況，例如 `Makefile`）→ Orchestrator dispatch 前合併到單軌、不並行
- **Case 8**：使用者中途切換 base_branch → Orchestrator 暫停所有 worker、寫 escalation log

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | 1. 對所有未 converge 的 worktree 執行 `git worktree remove --force`<br>2. 刪除對應的 feature branch（`git branch -D feat/spec-004-*`）<br>3. base branch 不受影響（因為還沒 merge） |
| **資料影響** | 無（worktree 內未 commit 的工作會遺失，但 task manifest 會保留為復原參考） |
| **回滾驗證** | `git worktree list` 只剩 base、`git branch -a` 無 `feat/spec-004-*`、base branch HEAD 與 dispatch 前一致 |
| **回滾已測試** | ☐ 是（需在 SPEC 實作階段補上 rollback 整合測試） |

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入條件 | 預期結果 | 對應場景 |
|---|------|---------|---------|---------|
| P1 | ✅ 正向 | 2 個 task，scope 不重疊 | 兩個 worktree 建立成功，各自完成、converge 無衝突 | S1 |
| P2 | ✅ 正向 | 1 個 task，含 task manifest 寫入 | `.asp-task-manifests/TASK-001.yaml` 存在且 schema valid | S2 |
| P3 | ✅ 正向 | task 完成後 cleanup | worktree 移除、branch 保留供 PR review | S3 |
| P4 | ✅ 正向 | converge 階段，3 個 task 序列 merge | base branch 有 3 個 merge commit、無衝突 | S4 |
| P5 | ✅ 正向 | telemetry 事件寫入 | `.asp-telemetry.ndjson` 含 `multi_agent.dispatch/converge/fail` 各事件類型 | S5 |
| N1 | ❌ 負向 | scope.allow 指向 repo 外 | dispatch 階段拒絕，退出碼 1 | S6 |
| N2 | ❌ 負向 | Worker 修改 forbid 路徑 | Worker 中止、bypass log 寫入、Orchestrator 收到 fail 回報 | S7 |
| N3 | ❌ 負向 | converge 時 merge 衝突 | Orchestrator 暫停、列出衝突檔案、退出碼 3 | S8 |
| N4 | ❌ 負向 | worktree_root 指向 `/etc` | 拒絕建立，安全警告 | S9 |
| B1 | 🔶 邊界 | max_parallel = 10 | 10 個 worktree 並行不衝突 | S10 |
| B2 | 🔶 邊界 | max_parallel = 11 | 要求人類確認後才繼續 | S11 |
| B3 | 🔶 邊界 | worktree idle > 2 小時 | `make agent-worktree-gc` 標記為 stale 並清理 | S12 |
| B4 | 🔶 邊界 | 磁碟可用 < 100MB | dispatch 拒絕；< 1GB 顯示警告 | S13 |
| B5 | 🔶 邊界 | base_branch 中途有新 commit | converge rebase；衝突時 N3 路徑 | S14 |

---

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: Multi-Agent Worktree 硬性隔離
  作為 ASP 的 multi-agent orchestrator
  我想要把每個 Worker 任務放到獨立的 git worktree
  以便檔案系統層級保證並行不會互相覆寫

  Background:
    Given ASP v4.1+ 已安裝且 .ai_profile 設定 mode: multi-agent
    And base_branch 為 main，HEAD 乾淨無 uncommitted changes

  # --- 正向場景 ---

  Scenario: S1 - 兩個 scope 不重疊的任務並行完成
    Given Orchestrator 收到兩個 task：TASK-001 (scope.allow=[src/store/]) 與 TASK-002 (scope.allow=[src/api/])
    When Orchestrator 執行 dispatch_parallel(tasks)
    Then 在 .asp-worktrees/task-001/ 與 .asp-worktrees/task-002/ 各建立 worktree
    And 兩個 worktree 對應的 branch 為 feat/spec-004-task-001 與 feat/spec-004-task-002
    And 兩個 Worker 的工作不會出現在對方的 worktree 中

  Scenario: S2 - Task manifest 寫入持久化
    Given 一個合法的 TaskManifest（含 task_id=TASK-001、agent_role=impl）
    When Orchestrator dispatch
    Then .asp-task-manifests/TASK-001.yaml 存在
    And YAML 內容含 task_id、agent_role、worktree_branch、scope 全部欄位

  Scenario: S3 - 任務完成後 worktree 清理
    Given TASK-001 已完成，狀態為 success
    When Orchestrator 執行 cleanup_worktree(TASK-001)
    Then .asp-worktrees/task-001/ 不存在
    And `git worktree list` 不含 task-001 entry
    But feat/spec-004-task-001 branch 保留供後續 PR review

  Scenario: S4 - 三軌序列 converge 無衝突
    Given TASK-001、TASK-002、TASK-003 均完成且 scope 不重疊
    When Orchestrator 執行 converge_tracks([TASK-001, TASK-002, TASK-003])
    Then base branch 上有 3 個 merge commit，依 task_id 順序
    And `git log --oneline` 顯示三個合併
    And worktrees_cleaned == 3

  Scenario: S5 - Telemetry 事件記錄
    Given multi-agent dispatch 與 converge 完整流程
    When 流程結束
    Then .asp-telemetry.ndjson 含 multi_agent.dispatch 事件
    And 含 multi_agent.converge 事件
    And 每個事件有 timestamp、task_id、status

  # --- 負向場景 ---

  Scenario: S6 - scope.allow 指向 repo 外被拒絕
    Given 一個 TaskManifest，scope.allow 含 "/etc/passwd"
    When Orchestrator dispatch
    Then dispatch 失敗，退出碼為 1
    And stderr 含 "scope.allow path outside repo: /etc/passwd"
    And 沒有 worktree 被建立

  Scenario: S7 - Worker 修改 forbid 路徑被攔截
    Given TASK-001 的 scope.forbid 包含 src/auth/
    When Worker 嘗試修改 src/auth/login.go
    Then Worker 中止任務，退出碼為 2
    And .asp-bypass-log.ndjson 新增一筆記錄，actor=worker-a、reason="scope_violation"
    And Orchestrator 收到 status=failed 的回報

  Scenario: S8 - converge 階段 merge 衝突
    Given TASK-001 與 TASK-002 因為 base_branch 中途有新 commit 導致衝突
    When Orchestrator converge
    Then converge 暫停，退出碼為 3
    And stderr 列出衝突檔案清單
    And 等待人類執行手動 merge 或 rebase

  Scenario: S9 - worktree_root 指向系統路徑被拒絕
    Given .ai_profile 設定 worktree_root: "/etc/asp-worktrees"
    When Orchestrator 啟動
    Then 啟動失敗
    And 錯誤訊息含 "worktree_root must be inside repo"

  # --- 邊界場景 ---

  Scenario Outline: S10/S11 - max_parallel 邊界
    When Orchestrator dispatch <count> 個 task
    Then 結果為 <result>

    Examples:
      | count | result                                   |
      | 10    | 全部建立成功                              |
      | 11    | 暫停並請求人類確認，未建立任何 worktree   |

  Scenario: S12 - Stale worktree GC
    Given 一個 worktree 的 last_activity_ts 早於 2 小時前
    When 執行 `make agent-worktree-gc`
    Then 該 worktree 被識別為 stale
    And 被移除（.asp-worktrees/ 與 .git/worktrees/ 都清乾淨）
    And 對應的 task manifest 標記為 abandoned

  Scenario Outline: S13 - 磁碟空間預檢
    Given 磁碟可用空間為 <available>
    When dispatch 嘗試建立 worktree
    Then 行為為 <behavior>

    Examples:
      | available | behavior              |
      | 5GB       | 正常建立              |
      | 500MB     | 顯示警告但繼續        |
      | 50MB      | 拒絕建立，退出碼為 4  |

  Scenario: S14 - base_branch 並行 commit
    Given Orchestrator dispatch 後，使用者在 base_branch commit 了新內容
    When Worker 完成、Orchestrator converge
    Then converge 自動 rebase
    And 若 rebase 成功，繼續 merge
    And 若 rebase 衝突，路徑同 S8
```

---

## ✅ 驗收標準（Done When）

- [ ] `make test-filter FILTER=spec-004` 全數通過（至少 14 個正向 + 9 個負向/邊界場景）
- [ ] `make lint` 無 error
- [ ] `multi_agent.md` 移除 v3.7 廢止警告，加入 v4.1 worktree 章節（取代第 82-126 行被砍掉的內容）
- [ ] `make agent-worktree-gc` Makefile target 實作完成
- [ ] `make agent-worktree-list` 顯示當前所有 worktree + age + task_id
- [ ] `.asp/scripts/multi-agent/dispatch.sh` 與 `converge.sh` 實作
- [ ] 副作用連動已驗證（見 Side Effects 表中所有驗證 ID）
- [ ] Rollback plan 已測試（`make spec-004-rollback-test`）
- [ ] 已更新 `docs/architecture.md`（multi-agent 子系統圖加入 worktree 層）
- [ ] 已更新 `CHANGELOG.md`（v4.1 entry）
- [ ] Telemetry 事件 schema 加入 `multi_agent.dispatch/converge/fail`
- [ ] 與 ADR-002 Iron Rule A/B/C 不衝突（worktree 內 hook 仍生效）

---

## 🔗 追溯性（Traceability）

<!-- 此區塊於實作完成後回填，非 SPEC 建立時填寫 -->

| 實作檔案 | 測試檔案 | 最後驗證日期 |
|----------|----------|-------------|
| （實作時填入） | （實作時填入） | YYYY-MM-DD |

---

## 📊 非功能需求（Non-Functional Requirements）

| 類別 | 需求 | 驗證方式 |
|------|------|----------|
| **效能** | dispatch 單一 worktree < 5 秒；converge 單一 task < 10 秒（無衝突） | benchmark in tests/ |
| **可擴展性** | max_parallel 至少支援 10 個 worker 並行不衝突 | B1 場景 |
| **安全** | scope.allow/forbid 路徑必須在 repo 內（防 path traversal） | N1/N4 場景 |
| **可恢復性** | Stale worktree GC 在 SessionStart 時不阻塞、< 2 秒 | session-audit hook 整合測試 |
| **相容性** | git ≥ 2.20（worktree 成熟版本） | install.sh 預檢 |

---

## 📊 可觀測性（Observability）

| 面向 | 說明 |
|------|------|
| **關鍵指標** | dispatch 數量、converge 成功率、merge 衝突率、stale worktree 數量、平均任務完成時間 |
| **日誌** | dispatch/converge 為 INFO；scope_violation/conflict/disk_low 為 WARN；rollback 為 ERROR |
| **告警** | stale worktree > 5 個 / 24 小時、converge 失敗率 > 20% / 7 天、scope_violation 任意一筆（高敏感） |
| **如何偵測故障** | `make agent-worktree-list` 顯示堆積；`.asp-telemetry.ndjson` 含 `multi_agent.fail` 事件；`.asp-bypass-log.ndjson` 含 `scope_violation` actor=worker |

---

## 🚫 禁止事項（Out of Scope）

- **不要修改**：v3.7 已廢止的 `.agent-lock.yaml` 機制（D-001 已決議淘汰，本 SPEC 不重啟）
- **不要引入新依賴**：只用 git ≥ 2.20 的 worktree feature，不引入 GitPython 等套件
- **不實作 cross-repo worktree**：本 SPEC 限定單 repo 內並行；跨 repo 屬未來工作
- **不取代 hook 信任邊界**：worktree 內仍須執行 `session-audit.sh`（Iron Rule A 不可繞過）

---

## 📎 參考資料（References）

- **相關 ADR**：D-001（v4-decision-log.md，廢止 file-lock 採用 worktree）
- **被取代的機制**：v3.7 `.agent-lock.yaml` + `make agent-lock-gc`（已於 commit `10adbbe` 廢止）
- **現有設計**：`docs/multi-agent-architecture.md` v3.0 角色制（保留，本 SPEC 只變動隔離層）
- **git worktree 文件**：https://git-scm.com/docs/git-worktree
- **外部參考**：Anthropic SubAgents `/clear` between roles（D-001 對齊依據）
