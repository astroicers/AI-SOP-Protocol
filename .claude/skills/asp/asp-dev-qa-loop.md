---
name: asp-dev-qa-loop
description: |
  Use when running the Dev↔QA quality loop in multi-agent ASP workflows.
  Handles: module-by-module Dev→QA→Fix iteration, checksum smuggling detection,
  independent QA verification, integration validation, QA_FAIL escalation.
  Triggers: dev qa loop, dev-qa, qa loop, 開發品質迴路, 跑 dev qa,
  dev qa 迴路, 模組驗證, module verification, qa verify, dev qa cycle,
  impl qa loop, 邊做邊驗.
---

# ASP Dev-QA Loop Skill

即時品質迴路：實作期間 QA agent 逐模組即時驗證，不等全部完成。本 skill 自包含，流程邏輯直接內嵌，不依賴外部 profile。

## 設計原則

- **邊做邊驗**（而非做完再驗）：每個模組完成後立刻由 QA 獨立驗證
- **不信任 impl 的自我回報**：QA 獨立執行測試，不接受 impl 的 claimed_test_output
- **偷渡偵測**：QA 對比 impl 的測試 checksum，防止 impl 偷改測試讓測試通過
- **3× 失敗升級**：單一模組連續 3 次 QA FAIL → 觸發 asp-escalate P2

## auto_fix_loop vs dev_qa_loop

| | auto_fix_loop | dev_qa_loop |
|---|---|---|
| **層級** | 低層（impl agent 內部） | 高層（impl + qa agent 協作） |
| **觸發者** | impl agent 自行跑測試 | qa agent 獨立驗證 |
| **信任模型** | impl 信任自己的測試結果 | qa 不信任 impl 的自我回報 |
| **防護** | 振盪/級聯/偷渡偵測 | 偷渡偵測 + 覆蓋率 + 獨立測試 |

---

## 核心流程

```
輸入：task（含 spec.affected_modules）、impl_agent、qa_agent

FOR 每個 module IN affected_modules:
  ┌─────────────────────────────────────┐
  │ impl_agent 實作此模組               │
  │   - 內部已跑 auto_fix_loop          │
  │   - 產出：                          │
  │     * claimed_test_output           │
  │     * files_modified                │
  │     * test_checksums_after          │
  └─────────────────────────────────────┘
              ↓
  ┌─────────────────────────────────────┐
  │ qa_agent 立刻驗證此模組             │
  │   → 見 QA 驗證步驟                  │
  └─────────────────────────────────────┘
              ↓
  IF qa_result == QA_FAIL:
    retry = 0
    WHILE retry < 3:
      建立 QA_FAIL 交接單（含完整失敗原因）
      impl_agent 修復
      qa_agent 重新驗證
      IF QA_PASS → BREAK
      retry += 1

    IF retry >= 3:
      → 觸發 asp-escalate P2
        reason: "模組 {module} 在 Dev↔QA 迴路中 3 次驗證失敗"
      CONTINUE（跳至下一模組）

  LOG("模組 {module}: QA PASS")

ALL modules 通過後：
  → 整合驗證（見整合驗證步驟）
```

---

## QA 驗證步驟（逐模組）

QA agent 收到 impl 的產出後，執行以下 3 個檢查：

### 步驟 1：獨立執行測試

```bash
make test-filter FILTER={module}
```

- **不接受** impl 的 `claimed_test_output`
- 若測試未全部通過 → 記錄失敗清單

### 步驟 2：比對 impl 自稱結果（信任但驗證）

```
IF impl.claimed_test_output != 獨立測試輸出:
  → 記錄差異：「impl 自稱的測試結果與獨立驗證不符」
  → 這可能是 checksum smuggling 的前兆
```

### 步驟 3：Checksum Smuggling Detection

```bash
# 計算當前測試檔案的 checksum
sha256sum {test_files_for_module}

# 對比 impl 在實作前記錄的 original_test_checksums
IF 當前 checksums != impl.original_test_checksums:
  → 記錄：「測試檔案被修改（偷渡風險）」
  → 嚴重性升級：若測試被改過 → 立刻升級為 P1（偷渡比 QA fail 更嚴重）
```

### QA 判決

```
IF 任何步驟有 issue:
  → QA_FAIL（附完整 issues 清單）
ELSE:
  → QA_PASS（附 3 項通過的 evidence）
     evidence[0]: "獨立測試通過"
     evidence[1]: "impl 自我回報一致"
     evidence[2]: "偷渡偵測通過"
```

---

## QA_FAIL 交接單格式

當 QA_FAIL 時，使用 TASK_COMPLETE 類型的交接單（status: failed）：

```yaml
handoff_type: TASK_COMPLETE
task_id: "{TASK-NNN}"
timestamp: "{ISO 8601}"
from_agent:
  role: "qa"
status: "failed"

failure_context:
  root_cause_analysis: |
    {說明哪個驗證步驟失敗，為什麼}
  attempted_fixes: []   # QA 不嘗試修復，僅回報
  guard_triggered: null  # null | smuggling（若 checksum 不符）
  remaining_failures:
    - "{失敗項目 1}"
    - "{失敗項目 2}"

artifacts:
  test_output: |
    {獨立測試的完整輸出，不可摘要}
  files_modified: []    # QA 不修改檔案
  test_checksums:
    "{test_file_path}": "{sha256:...}"
```

---

## 整合驗證步驟

所有模組通過後執行：

```bash
make test    # 全量測試（非 test-filter）
```

若整合測試 FAIL：
- 觸發 asp-escalate P2，reason: "整合驗證失敗"
- 列出失敗的測試及相關模組

若整合測試 PASS：
- 建立最終 TASK_COMPLETE（status: success）
- 填入 `success_context.spec_done_when_status`（逐項驗證 SPEC 的 Done-When 條件）

---

## 進入條件

以下條件須**全部**滿足才能啟動 dev_qa_loop：

1. `mode: multi-agent`（需要 impl 和 qa 是不同 agent）
2. 團隊包含 `qa` 角色
3. task 的 SPEC 有明確的 `affected_modules`（或視整個 task 為單一 module）

若不滿足（單 agent 模式）：qa 驗證改由同一 agent 執行，但仍須遵循 3 個檢查步驟的邏輯。

---

## 3x 失敗升級協議

模組連續 3 次 QA FAIL 時：

```
1. 呼叫 asp-escalate，severity=P2
   reason: "模組 {module} 在 Dev↔QA 迴路中 3 次驗證失敗"
   context:
     qa_result: {最後一次的完整 QA 結果}
     impl_attempts: 3
     
2. 跳過此模組，繼續下一個模組（不卡死整個 task）

3. 若偷渡偵測觸發（checksum 被修改）→ 升級為 P1，不是 P2
```