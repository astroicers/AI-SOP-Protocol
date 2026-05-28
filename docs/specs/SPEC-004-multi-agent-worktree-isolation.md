# SPEC-004：Multi-Agent Worktree 硬性隔離

> 結構完整的規格書讓 AI 零確認直接執行。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-004 |
| **關聯 ADR** | SDS §10 D-001 addendum (2026-05-10)；`docs/archive/v4-refactor/v4-decision-log.md` D6（worktree 索引）；ADR-002（Iron Rules） |
| **估算複雜度** | 中 |
| **建議模型** | Sonnet（涉及 git plumbing + multi-agent orchestration，需要精準 shell 操作） |
| **HITL 等級** | strict（涉及 worktree 建立 + 跨 branch merge，需人類審查） |
| **狀態** | Accepted |
| **日期** | 2026-05-10 |

---

## 🎯 目標（Goal）

讓 multi-agent 並行任務真正以**檔案系統層級隔離**運作：每個 Worker 在獨立的 git worktree 中工作，由 Orchestrator 在 `converge_tracks` 階段以 git merge 匯流。取代 v3.7 廢止的 `.agent-lock.yaml` 軟性檔案鎖（決策見 SDS §10 D-001 addendum 與 `docs/archive/v4-refactor/v4-decision-log.md` D6；v4.0 已標記廢止但未實作替代方案）。

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
| Worktree 路徑指向 repo 外 / 路徑驗證失敗 | 1 | 拒絕建立，要求人類修正配置 |
| 引數錯誤 / manifest 解析失敗 / scope 違規（`scope-guard.sh` PreToolUse 攔截，N2） | 2 | 任務中止、寫入 `.asp-bypass-log.ndjson`，回報 Orchestrator |
| Merge / Rebase 衝突（task-vs-task 或 task-vs-base） | 3 | Orchestrator 暫停 converge、列出衝突檔案、寫 escalation log、等待人類解決 |
| 磁碟空間不足（dispatch B4 動態預檢，`dispatch.sh` Stage 4） | 4 | 拒絕 dispatch；available < repo_size × max_parallel × 1.2 時 exit 4 |
| scope.allow 重疊 | 5 | dispatch 階段拒絕、要求重新拆解 task |
| max_parallel 超過上限 | 6 | dispatch 階段拒絕；mock 模式寫 escalation log |
| ASP_AUDIT_ROOT 驗證失敗（fail-closed） | 7 | 任何 multi-agent 腳本立即拒絕、stderr 印明確原因 |
| Rollback 後 base HEAD 意外被改動 | 8 | rollback.sh 偵測到 base 移動 → 立即 abort、不繼續清理 |
| install.sh runtime precheck 失敗（git/bash/jq/python3 版本不符） | 13 | install.sh Phase 0 拒絕安裝；可用 ASP_SKIP_PRECHECK=1 強制 |

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| 建立新 git worktree | 每個 task dispatch 時 | `.git/worktrees/`、`.asp-worktrees/` | `git worktree list` 含新分支；P1 |
| 建立新 branch | worktree 建立時 | git refs | `git branch --list feat/spec-004-*`；P1 |
| 寫入 task manifest | dispatch 後 | `.asp-task-manifests/TASK-XXX.yaml` | YAML 檔案存在且 schema valid；P2 |
| Merge 到 base branch | converge 階段 | base branch HEAD | `git log` 含合併 commit；P5 |
| 清理 worktree | 任務完成 / GC 觸發時 | `.asp-worktrees/`、`.git/worktrees/` | `git worktree prune` 無殘留；B3 |
| 寫入 telemetry 事件 | dispatch / converge / fail 時 | 主 repo 的 `.asp-telemetry.ndjson` | NDJSON 含 `multi_agent.dispatch` event；P5 |
| **Append bypass log** | Worker 偵測 scope_violation 時 | **主 repo 的 `.asp-bypass-log.ndjson`**（非 worktree 內） | NDJSON 新增 actor=worker-N 一筆；P6（new） |

> 每個副作用都有對應驗證 ID（見測試矩陣）。G5 Gate 會檢查。

### 🔒 共享狀態檔案路徑策略（Iron Rule B 完整性保障）

以下檔案是**全域 audit trail**，所有 Worker 必須寫入主 repo 路徑（非 worktree 內），否則 Iron Rule B（bypass log append-only）的全局審計會破裂：

| 檔案 | 路徑策略 | 並行寫入安全性 |
|------|---------|--------------|
| `.asp-bypass-log.ndjson` | 主 repo 根目錄（不在 worktree 內） | NDJSON append（POSIX `O_APPEND` 對 < PIPE_BUF=4096 bytes 的 write 是 atomic）；單筆 entry 必須 < 4KB |
| `.asp-telemetry.ndjson` | 主 repo 根目錄 | 同上 |
| `.asp-task-manifests/TASK-XXX.yaml` | 主 repo 根目錄；每 task 一個獨立檔案 | 不同 task 寫不同檔案，無競態 |

**Worker 寫入機制**：Worker 在 worktree 中啟動時，環境變數 `ASP_AUDIT_ROOT` 由 dispatch.sh 注入，指向主 repo 根。所有寫入 bypass log / telemetry 的程式碼必須 resolve 到 `${ASP_AUDIT_ROOT}/.asp-bypass-log.ndjson`，**禁止使用相對路徑**（會被 worktree cwd 拐進去）。

#### 🚨 ASP_AUDIT_ROOT Fail-Safe 規格（Iron Rule B 強制要求）

`ASP_AUDIT_ROOT` 是 Iron Rule B 全局審計的 single source of truth，**任何 silently fallback 到相對路徑的行為都會讓 Iron Rule B 靜默失效**，因此必須採 fail-closed 設計。

**驗證時機**（兩階段，缺一不可）：

| 階段 | 執行者 | 驗證內容 | 失敗行為 |
|------|-------|---------|---------|
| **Stage 1: dispatch 階段** | `dispatch.sh` 在建立 worktree 之前 | ① `ASP_AUDIT_ROOT` 已設定（非空字串）；② 是 absolute path（以 `/` 開頭）；③ 路徑存在且為目錄；④ 該目錄下存在 `.git/` 或被 `git rev-parse --show-toplevel` 認可為主 repo | 拒絕建立任何 worktree；退出碼 7；stderr 印明確原因 |
| **Stage 2: Worker 寫入階段** | Worker 寫入 audit log 前的 wrapper（`.asp/scripts/multi-agent/audit-write.sh`） | 同 Stage 1 全部四項 | 拒絕寫入；退出碼 7；Worker 同時 abort 任務、寫入 escalation log（用 hard-coded 主 repo 路徑作為最後手段，因為此時 audit-write 本身已失效） |

**禁止的 fallback 行為**：

- ❌ `ASP_AUDIT_ROOT` 未設定時 fallback 到 `$(pwd)` 或 `.`（會寫到 worktree 內）
- ❌ `ASP_AUDIT_ROOT` 為相對路徑時自動 resolve 到 absolute（會掩蓋使用者錯誤配置）
- ❌ `ASP_AUDIT_ROOT` 指向不存在的目錄時 mkdir -p（會建立非預期的 audit trail location）
- ❌ Worker 收到驗證失敗訊息後仍繼續執行任務（即使把 task 結果丟掉，也已洩漏 scope_violation 等敏感事件未被記錄）

**強制路徑**：所有 audit log 寫入必須透過 `audit-write.sh` wrapper，禁止直接 `>>` append。wrapper 在 Stage 2 失敗時必須讓 caller process 結束，不可 silent。

**對應測試**：S15（正向）+ N7（負向，新增）+ N8（負向，新增）。

**並行寫入驗證**：實作完成後須跑壓力測試 — 10 個 Worker 同時 append 1000 筆 bypass log entry（總 10,000 筆），驗證 NDJSON 完整性（行數 = 10,000、所有 line 可被 `jq -c .` 解析）。對應測試 S18。

### 🪝 Iron Rule A 在 worktree 中的掛載機制

每個 worktree 是獨立 working directory，但**共享 `.git/`**。Hook 掛載策略：

| Hook | 掛載方式 | 為什麼 |
|------|---------|--------|
| `session-audit.sh`（SessionStart） | 透過 `.claude/settings.json` 設定 — settings.json 在 base branch 已 commit，所有 worktree 自動繼承 | settings.json 是 git-tracked，worktree checkout 時自動帶過去 |
| `clean-allow-list.sh`（PreToolUse） | 同上 | 同上 |
| `denied-commands.json`（dynamic deny） | 由 session-audit.sh 在 session 啟動時動態生成 — 每個 worktree 啟動 Claude Code session 時各自生成一份 | 每個 Worker 有獨立 deny list，不互相干擾 |

**驗證**：在 worktree 中啟動 Claude Code，session-audit.sh 必須執行；`.asp-session-briefing.json` 必須在 worktree 根產生（不在主 repo）。對應測試 P7（new）。

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
| P6 | ✅ 正向 | bypass log 寫入路徑 | 主 repo 的 `.asp-bypass-log.ndjson` 接收所有 worktree 的記錄（非 worktree 內） | S15 |
| P7 | ✅ 正向 | Iron Rule A hook 在 worktree 啟動 | worktree 中啟動 Claude session 時 `session-audit.sh` 執行、`.asp-session-briefing.json` 產生於 worktree 根 | S16 |
| N1 | ❌ 負向 | scope.allow 指向 repo 外 | dispatch 階段拒絕，退出碼 1 | S6 |
| N2 | ❌ 負向 | Worker 修改 forbid 路徑 | Worker 中止、bypass log 寫入、Orchestrator 收到 fail 回報 | S7 |
| N3 | ❌ 負向 | 兩個 task branch 之間 merge 衝突 | Orchestrator 暫停、列出衝突檔案、退出碼 3 | S8 |
| N4 | ❌ 負向 | worktree_root 指向 `/etc` | 拒絕建立，安全警告 | S9 |
| N5 | ❌ 負向 | scope.allow 重疊（兩 task 都含 `src/store/`） | dispatch 前偵測並拒絕，要求重新拆解、退出碼 5 | S17 |
| N6 | ❌ 負向 | 10 worker × 1000 entry 並行壓測 bypass log | NDJSON 共 10,000 行、`jq -c .` 全部可解析、無 truncated line | S18（並行寫入安全性） |
| N7 | ❌ 負向 | `ASP_AUDIT_ROOT` 未設定時 dispatch 啟動 | dispatch.sh 拒絕建立 worktree、退出碼 7、stderr 含「ASP_AUDIT_ROOT must be set」 | S20 |
| N8 | ❌ 負向 | `ASP_AUDIT_ROOT` 為相對路徑（例如 `.`）時 dispatch 啟動 | 拒絕、退出碼 7、stderr 含「ASP_AUDIT_ROOT must be absolute path」 | S21 |
| B1 | 🔶 邊界 | max_parallel = 10 | 10 個 worktree 並行不衝突 | S10 |
| B2 | 🔶 邊界 | max_parallel = 11 | 要求人類確認後才繼續（**human-in-loop，自動測試靠 mock 確認 prompt，不真的等人**） | S11 |
| B3 | 🔶 邊界 | worktree idle > 2 小時 | `make agent-worktree-gc` 標記為 stale 並清理 | S12 |
| B4 | 🔶 邊界 | 磁碟可用 < (repo_size × max_parallel × 1.2) | dispatch 拒絕；< 1.5 倍顯示警告 | S13 |
| B5 | 🔶 邊界 | base_branch 中途有新 commit、與 task branch 有衝突 | converge rebase 失敗 → human-in-loop 暫停（**自動測試靠 mock 確認 escalation log，不真的等人**） | S14 |
| B6 | 🔶 邊界 | Worker process killed（SIGKILL） | worktree 保留、task manifest 標記 abandoned、下次 GC 清理 | S19 (new) |

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

  Scenario: S8 - 兩個 task branch 之間 merge 衝突
    Given TASK-001 與 TASK-002 都修改了 src/shared/util.go 同一行（scope 設計時未發現重疊）
    And base_branch HEAD 在 dispatch 後沒有變動
    When Orchestrator converge TASK-001 後再 converge TASK-002
    Then converge 暫停於 TASK-002 的 merge 步驟，退出碼為 3
    And stderr 列出衝突檔案：src/shared/util.go
    And mock 模式下 escalation log 寫入 .asp-escalation.ndjson 含 reason="task_merge_conflict"
    But base_branch 已包含 TASK-001 的 merge commit（部分成功）

  Scenario: S9 - worktree_root 指向系統路徑被拒絕
    Given .ai_profile 設定 worktree_root: "/etc/asp-worktrees"
    When Orchestrator 啟動
    Then 啟動失敗
    And 錯誤訊息含 "worktree_root must be inside repo"

  # --- 邊界場景 ---

  Scenario Outline: S10/S11 - max_parallel 邊界
    Given 環境變數 ASP_HITL_MODE=mock（自動測試用，跳過實際等待）
    When Orchestrator dispatch <count> 個 task
    Then 結果為 <result>
    And mock 模式下，>10 task 時 .asp-escalation.ndjson 含一筆 reason="max_parallel_exceeded" 的記錄

    Examples:
      | count | result                                                       |
      | 10    | 全部建立成功                                                  |
      | 11    | 拒絕並寫入 escalation log（mock 模式不真的等人，回傳退出碼 6）|

  Scenario: S12 - Stale worktree GC
    Given 一個 worktree 的 last_activity_ts 早於 2 小時前
    When 執行 `make agent-worktree-gc`
    Then 該 worktree 被識別為 stale
    And 被移除（.asp-worktrees/ 與 .git/worktrees/ 都清乾淨）
    And 對應的 task manifest 標記為 abandoned

  Scenario Outline: S13 - 磁碟空間動態預檢
    Given repo 大小為 100 MB
    And max_parallel 為 5
    And 預算為 100 × 5 = 500 MB（最低需求 × 1.2 = 600 MB；警告線 × 1.5 = 750 MB）
    And 磁碟可用空間為 <available>
    When dispatch 嘗試建立 worktree
    Then 行為為 <behavior>

    Examples:
      | available | behavior              |
      | 2GB       | 正常建立              |
      | 700MB     | 顯示警告但繼續（介於 600MB 與 750MB） |
      | 500MB     | 拒絕建立，退出碼為 4（< 600MB 門檻）  |

  Scenario: S14 - base_branch 並行 commit（與 task branch 衝突）
    Given Orchestrator dispatch 後，使用者在 base_branch commit 了修改 src/api/routes.go 的內容
    And TASK-001 的 worker branch 也修改了 src/api/routes.go 的同一段
    And 環境變數 ASP_HITL_MODE=mock
    When Orchestrator converge TASK-001
    Then converge 自動嘗試 rebase task branch onto base_branch
    And rebase 因衝突失敗
    And mock 模式下 .asp-escalation.ndjson 含 reason="base_branch_rebase_conflict"
    And 退出碼為 3（與 S8 同），但 escalation reason 不同（區別於 task-vs-task）

  # --- S15+：bypass log 路徑、Iron Rule A 掛載、scope 重疊、並行壓測、process kill ---

  Scenario: S15 - bypass log 寫入路徑強制為主 repo
    Given 一個 Worker 在 .asp-worktrees/task-001/ 中執行
    And 環境變數 ASP_AUDIT_ROOT 指向主 repo 根
    When Worker 偵測 scope_violation 並寫入 bypass log
    Then 主 repo 根的 .asp-bypass-log.ndjson 新增一筆記錄
    But .asp-worktrees/task-001/.asp-bypass-log.ndjson 不存在（不可被建立）

  Scenario: S16 - Iron Rule A hook 在 worktree 中正常掛載
    Given .asp-worktrees/task-001/ 已建立
    When 在該 worktree 中啟動新的 Claude Code session
    Then session-audit.sh 執行（透過 .claude/settings.json 繼承自 base branch）
    And worktree 根產生 .asp-session-briefing.json
    And 主 repo 根的 .asp-session-briefing.json 不被覆蓋（兩份獨立）
    And worktree 內的 dynamic deny list 不污染主 repo

  Scenario: S17 - scope.allow 重疊 dispatch 階段拒絕
    Given TASK-001 的 scope.allow = ["src/store/", "src/api/"]
    And TASK-002 的 scope.allow = ["src/store/"] （與 TASK-001 重疊）
    When Orchestrator 執行 dispatch_parallel([TASK-001, TASK-002])
    Then dispatch 失敗，退出碼為 5
    And stderr 含 "scope.allow overlap detected: src/store/ in TASK-001 and TASK-002"
    And 沒有 worktree 被建立

  Scenario: S18 - bypass log 並行寫入安全性壓測
    Given 10 個 Worker 進程啟動（皆在獨立 worktree）
    And 每個 Worker 各 append 1000 筆 bypass log entry（每筆 < 4KB）
    When 全部 Worker 完成
    Then .asp-bypass-log.ndjson 共 10,000 行
    And 每一行被 `jq -c .` 解析成功（無 truncated 或 interleaved JSON）
    And 沒有 line 包含其他 line 的部分內容（POSIX O_APPEND atomicity 驗證）

  Scenario: S19 - Worker process killed 後狀態正確
    Given Worker A 在 .asp-worktrees/task-001/ 中執行
    When Worker A 被 SIGKILL 終止（模擬 OOM 或手動 kill）
    Then .asp-worktrees/task-001/ 目錄保留
    And .asp-task-manifests/TASK-001.yaml 由 Orchestrator 標記為 abandoned
    And 下次執行 `make agent-worktree-gc` 時清理該 worktree
    But base_branch 不受影響（worker 未來得及 commit）

  # --- ASP_AUDIT_ROOT fail-safe（Iron Rule B 全局審計後門封堵） ---

  Scenario: S20 - ASP_AUDIT_ROOT 未設定時 dispatch 拒絕啟動
    Given 環境變數 ASP_AUDIT_ROOT 未設定（unset）或為空字串
    When dispatch.sh 啟動
    Then dispatch 立即失敗，退出碼為 7
    And stderr 含 "ASP_AUDIT_ROOT must be set"
    And 沒有 worktree 被建立
    And 沒有 audit log（bypass / telemetry）被寫入任何位置

  Scenario Outline: S21 - ASP_AUDIT_ROOT 非絕對路徑或無效路徑時 dispatch 拒絕
    Given 環境變數 ASP_AUDIT_ROOT = <value>
    When dispatch.sh 啟動
    Then dispatch 失敗，退出碼為 7
    And stderr 含 <error_msg>
    And 沒有 worktree 被建立

    Examples:
      | value                          | error_msg                                            |
      | "."                            | "ASP_AUDIT_ROOT must be absolute path"               |
      | "../some-rel"                  | "ASP_AUDIT_ROOT must be absolute path"               |
      | "/tmp/does-not-exist"          | "ASP_AUDIT_ROOT path not found or not a directory"   |
      | "/tmp/not-a-git-repo"          | "ASP_AUDIT_ROOT is not a git repo (no .git/ found)"  |
```

---

## ✅ 驗收標準（Done When）

1. [x] `make test-filter FILTER=spec-004` 通過（測試矩陣 7 P + 8 N + 6 B = 21 項全覆蓋）— 7 個 spec-004 測試檔，含 `test_spec_004_scope_guard.sh`（12 assertions，S7/N2）+ `test_spec_004_dispatch.sh` 新增 S13/B4（3 assertions）；dispatch.sh Stage 4 磁碟空間動態預檢（exit 4/warning）+ scope-guard.sh PreToolUse 攔截（exit 2 + bypass log）均已實作。v4.2 補完。
2. [x] `make lint` 無 error — shellcheck -S warning 對所有 .asp/scripts/multi-agent/ + tests/ 通過；commit (this batch)
3. [x] `multi_agent.md` 中所有指向 v4.1 worktree 的廢止警告改為指向已實作章節（不再用「將實作」字樣，且不用任何行號描述位置）— commit 5a91b8e
4. [x] `multi_agent.md` 新增「Multi-agent worktree 隔離」章節，描述使用方式與限制 — commit 5a91b8e
5. [x] `make agent-worktree-gc` Makefile target 實作完成 — commit 04e866f
6. [x] `make agent-worktree-list` 顯示當前所有 worktree + age + task_id — commit 04e866f
7. [x] `.asp/scripts/multi-agent/dispatch.sh` 與 `converge.sh` 實作 — commit 4257c0c (B2) + 761cc73 (B3)
8. [x] 副作用連動已驗證 — Side Effects 表中 P1-P7 / N1-N8 / B1-B6 全綠（21/21）。N2 由 `scope-guard.sh` PreToolUse hook 攔截；B4 由 `dispatch.sh` Stage 4 動態預檢實作；均有自動化測試覆蓋。
9. [x] Rollback plan 已測試（`make spec-004-rollback-test`）— rollback.sh + 15 assertions cover 三個 task dispatch、partial converge、dry-run、空 repo、ASP_AUDIT_ROOT validation；commit (this batch)
10. [x] 已更新 `docs/architecture.md`（multi-agent 子系統圖加入 worktree 層）— commit 5a91b8e
11. [x] 已更新 `CHANGELOG.md`（v4.1 entry）— commit 5a91b8e
12. [x] Telemetry 事件 schema 加入 `multi_agent.dispatch/converge/fail`（同步擴充 `docs/telemetry.md` event-type 章節）— 含 gc + dispatch_rejected 共 5 種；commit 5a91b8e
13. [x] `install.sh` 預檢 git ≥ 2.20、bash ≥ 4.4、jq ≥ 1.6、python3 ≥ 3.10，缺任一者 abort 安裝（exit 13）；ASP_SKIP_PRECHECK=1 escape hatch；22 assertions cover version_at_least + missing-binary + outdated-binary scenarios；commit (this batch)
14. [x] 與 ADR-002 Iron Rule A/B/C 不衝突（S15+S16 場景驗證）— B5 test_spec_004_audit_integration.sh
15. [x] 提供 `docs/specs/SPEC-004-benchmarks.md` — 含基準環境實測數據（含 WSL2 / NFS / 大型 repo 偏離結果）— 本版交付
16. [x] `ASP_AUDIT_ROOT` 環境變數機制實作 + 文件化（dispatch.sh 注入、bypass log / telemetry 寫入點 resolve）— commit 41d0bdd
17. [x] `ASP_AUDIT_ROOT` Fail-Safe 兩階段驗證實作（dispatch 階段 + Worker 寫入階段；fail-closed 不 fallback）；`audit-write.sh` wrapper 為唯一寫入點；S20/S21 場景全綠 — commit 41d0bdd + 4257c0c
18. [x] 提供 `docs/archive/v4-refactor/v4-decision-log.md` D6 條目（worktree 決策索引），確保 SPEC 引用可追溯 — commit c795684（檔案於 2026-05-10 cleanup wave 2 archive）

**v4.2.0 完成度**：

- ✅ 完整完成：18 / 18 條（全部）
- N2 補完：`scope-guard.sh` PreToolUse hook（`tests/test_spec_004_scope_guard.sh` 12 assertions）
- B4 補完：`dispatch.sh` Stage 4 動態磁碟預檢（exit 4 / warning，`tests/test_spec_004_dispatch.sh` S13 3 assertions）

> **誠實補完記錄（v4.2.0）**：v4.1.1 誠實標記 16+2partial，說明 N2/B4 是 placeholder。本版（v4.2.0）補足兩項，測試覆蓋確認後升為 18/18。

---

## 🔗 追溯性（Traceability）

<!-- 此區塊於實作完成後回填，非 SPEC 建立時填寫 -->

| 實作檔案 | 測試檔案 | 最後驗證日期 |
|----------|----------|-------------|
| （實作時填入） | （實作時填入） | YYYY-MM-DD |

---

## 📊 非功能需求（Non-Functional Requirements）

### 基準環境（Reference Environment）

所有效能 / 可擴展性 / 可恢復性指標的驗收必須在以下基準環境中量測，否則指標不成立：

| 維度 | 基準規格 |
|------|---------|
| **OS** | Linux x86_64（Ubuntu 22.04 LTS 或同等 kernel ≥ 5.15）、macOS 13+ |
| **檔案系統** | ext4 / APFS（**不**接受 NTFS、網路掛載 NFS / SMB） |
| **磁碟** | 本地 SSD（NVMe 或 SATA），可用空間 ≥ 5 × repo 大小 |
| **CPU / RAM** | ≥ 4 cores、≥ 8 GB RAM |
| **Repo 大小** | 中型 repo（≤ 500 MB checkout、≤ 50,000 commit、無 LFS 巨檔） |
| **git 版本** | ≥ 2.20 |
| **WSL2** | 接受，但須在 Linux 檔案系統路徑（`/home/...`）；**不**接受 `/mnt/c/...` 跨檔系操作 |

> 偏離基準環境（例如 WSL2 跨 `/mnt/c`、網路磁碟、Windows NTFS）時 NFR 指標**不適用**，但功能正確性仍須保證。實作完成時須在 `docs/specs/SPEC-004-benchmarks.md` 提供基準環境的實測數據。

### 指標

| 類別 | 需求（基準環境下） | 驗證方式 |
|------|------|----------|
| **效能** | dispatch 單一 worktree p95 < 5 秒；converge 單一 task p95 < 10 秒（無衝突）；NFR 不適用環境須在實測報告註明 | `tests/perf/test_spec_004_perf.sh`（10 次取 p95） |
| **可擴展性** | max_parallel 支援 10 個 worker 並行不衝突；超過 10 須觸發 escalation（S11） | B1 + S18 並行壓測 |
| **磁碟容量預檢** | dispatch 階段檢查 `df -BM` 可用空間：< (repo_size × max_parallel × 1.5) 警告；< (repo_size × max_parallel × 1.2) 拒絕。**不再用固定 100MB / 1GB 門檻** | S13 用動態值替代 |
| **安全** | scope.allow/forbid 路徑必須在 repo 內（防 path traversal）；env var ASP_AUDIT_ROOT 必須是 absolute path | N1/N4/S15 場景 |
| **可恢復性** | Stale worktree GC 在 SessionStart hook 中執行 < 2 秒（10 個 stale worktree 情況下） | session-audit hook 整合測試 |
| **相容性** | git ≥ 2.20、bash ≥ 4.4、jq ≥ 1.6、python3 ≥ 3.10（dispatch.sh / converge.sh / agent-worktree-gc 共用依賴） | install.sh 預檢、Done When #13 |
| **API 預算（外部依賴）** | 10 worker 並行 = 10 × LLM API token budget；本 SPEC **不**負責 token rate limit 策略，由上層 orchestrator 決定 | 文件說明，不寫成測試 |

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

- **相關決策**：
  - `docs/archive/v4-refactor/v4-architecture-sds.md` §10 D-001 addendum (2026-05-10) — 完整 alternatives + rationale
  - `docs/archive/v4-refactor/v4-decision-log.md` D6 — worktree 決策索引
- **被取代的機制**：v3.7 `.agent-lock.yaml` + `make agent-lock-gc`（已於 commit `10adbbe` 廢止）
- **現有設計**：`docs/multi-agent-architecture.md` v3.0 角色制（保留，本 SPEC 只變動隔離層）
- **git worktree 文件**：https://git-scm.com/docs/git-worktree
- **外部參考**：Anthropic SubAgents `/clear` between roles（D-001 對齊依據）
