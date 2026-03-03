# Autonomous Development Profile

適用：AI 全自動開發，人類僅在關鍵節點審核。
載入條件：`.ai_profile` 中 `autonomous: enabled`
          或 `workflow: vibe-coding` + `hitl: minimal`（後相容）

> **設計原則**：用明確規則取代模糊的「信任 AI 判斷」。
> AI 不是「自由行動」，而是在精確定義的邊界內自主決策。

---

## 啟用前提

必須同時滿足：
1. `.ai_profile` 設定 `autonomous: enabled`（或同時設 `workflow: vibe-coding` + `hitl: minimal`）
2. 所有待實作功能的 ADR 已為 `Accepted` 狀態（可透過「批次預審」一次完成）
3. 每個功能有對應的 SPEC（AI 可自行建立，但必須遵循 SPEC_Template.md）

---

## AI 自主決策邊界

### 可自主執行（不暫停）

| 類別 | 範圍 | 條件 |
|------|------|------|
| **檔案建立** | 新增程式碼 / 設定 / 文件檔案 | 在 SPEC 範圍內 |
| **檔案修改** | 編輯既有程式碼 | 在 SPEC 範圍內 |
| **SPEC 建立** | `make spec-new` + 填寫內容 | 對應 ADR 已 Accepted |
| **測試撰寫** | 新增 / 修改測試檔案 | TDD 流程的一部分 |
| **文件更新** | 更新 ROADMAP / README / CHANGELOG | 功能完成後同步 |
| **Bug 自動修復** | `make test` 失敗 → 讀錯誤 → 修 → 重跑 | 最多 3 次重試 |
| **命名決策** | 變數 / 函數 / 檔案命名 | 跟隨既有 codebase 慣例 |
| **Pattern 選擇** | 選擇實作 pattern | 優先複用既有 pattern |

### 必須暫停（等待人類確認）

| 類別 | 觸發條件 |
|------|----------|
| **git push** | 鐵則，所有情況 |
| **git rebase** | 鐵則，所有情況 |
| **docker push / deploy** | 鐵則，所有情況 |
| **刪除檔案** | `rm` 任何非暫存檔案 |
| **範圍超出** | 實作中發現需求超出當前 SPEC / 版本範圍 |
| **新增外部依賴** | pyproject.toml / package.json 等新增 dependency |
| **DB Schema 變更** | 新增/修改資料庫結構（除非 SPEC 明確指定） |
| **Bug 修復失敗** | 同一問題重試 3 次仍失敗 |

### 禁止（即使 autonomous 模式也不可）

| 類別 | 說明 |
|------|------|
| **ADR 狀態變更** | AI 不可自行將 ADR 從 Draft 改為 Accepted |
| **跳過 TDD** | 新功能必須測試先於代碼，autonomous 模式不豁免 |
| **跳過 SPEC** | 非 trivial 功能必須有 SPEC 再實作 |
| **環境硬編碼** | 禁止針對特定環境或目標的硬編碼邏輯（如寫死 IP、主機名、資料庫端點等） |

---

## 自動修復循環

```
FUNCTION auto_fix_loop(test_command, max_retries=3):

  FOR attempt IN 1..max_retries:
    result = EXECUTE(test_command)

    IF result.passed:
      LOG("測試通過（第 {attempt} 次）")
      RETURN SUCCESS

    // 分析失敗原因
    errors = parse_test_failures(result.output)

    FOR error IN errors:
      fix = diagnose_and_fix(error)
      APPLY(fix)

    LOG("第 {attempt} 次修復完成，重新測試...")

  // 超過重試次數
  LOG("重試 {max_retries} 次仍失敗")
  PAUSE_AND_REPORT(errors)
  RETURN FAILURE
```

---

## Stage 驅動開發流程

autonomous 模式下，開發按 Stage 推進，每個 Stage 是一個完整的功能交付單元：

```
FUNCTION execute_stage(stage):

  // 1. Pre-flight
  VERIFY adr_status(stage.adr) == "Accepted"

  // 2. SPEC
  IF NOT exists(stage.spec):
    CREATE spec_from_template(stage)

  // 3. TDD
  WRITE tests(stage.test_file)
  EXECUTE("make test-filter FILTER={stage.filter}")  // 預期：全部 FAIL

  // 4. Implementation
  IMPLEMENT(stage.source_files)

  // 5. Verification
  auto_fix_loop("make test")

  // 6. Documentation
  UPDATE docs(stage.affected_docs)

  // 7. Checkpoint
  LOG("Stage {stage.name} 完成")
  // 不暫停，繼續下一個 Stage
```

---

## Context 管理（長 session 保護）

autonomous 模式的 session 通常很長，必須主動管理 context：

| 觸發條件 | 動作 |
|----------|------|
| 完成一個 Stage | 輸出 Stage 完成摘要（修改了哪些檔案、測試結果） |
| context 使用率 > 70% | `make session-checkpoint NEXT="..."` |
| 連續 3 個檔案修改無 `make test` | 立刻執行 `make test` |
| 偵測到 context decay 信號 | 停止開發，輸出 checkpoint，建議新 session |

---

## 與其他 Profile 的關係

```
autonomous_dev.md
  ├── 依賴 vibe_coding.md（hitl: minimal 定義）
  ├── 依賴 system_dev.md（ADR/SPEC/TDD 流程）
  ├── 依賴 global_core.md（鐵則 + 連帶修復）
  └── 可選 guardrail.md（敏感資訊保護）
```

不與 `multi_agent.md` 或 `committee.md` 同時啟用。autonomous 模式是單 agent 高速執行。
