# SPEC-007：Close inbox-ingest ungated bypass (ADR-012 DP8)

> 結構完整的規格書讓 AI 零確認直接執行。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-007 |
| **關聯 ADR** | ADR-012（INV-2、DP8、T-14、reviewer F4） |
| **估算複雜度** | 低 |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

關閉 `inbox-ingest.sh` 在 SessionStart **無人類授權即自動把外部來源任務注入 ROADMAP** 的旁路——任何能寫 `.asp-task-inbox.json`（或 asp-op）者，目前都能讓任務以 `adr: null` 自動進入 autopilot 執行佇列。本 SPEC 把該注入動作改為**僅回報、不注入（held）**，使外部工作在「人類授權路徑（triage，SPEC-009）」落地前無法繞過 INV-2 進入執行。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| `.asp-task-inbox.json` | JSON array | `${CLAUDE_PROJECT_DIR}` | 既有 schema；每筆含 `status` / `source.type` / `triggered_by` |
| 觸發時機 | event | session-audit.sh 於 SessionStart 呼叫 `bash .asp/scripts/inbox-ingest.sh` | 非阻擋（exit 0） |
| `ROADMAP.yaml` | YAML | 專案根 | 可能不存在 |

> 注意：inbox 內所有任務皆屬**外部來源**（asp-op 從 GitHub issue 翻譯而來）。本 SPEC 不引入新輸入欄位。

---

## 📤 輸出規格（Expected Output）

**成功情境（有 pending 外部任務）：**
- **不**寫入 `ROADMAP.yaml`（核心改動）。
- **不**把 inbox 任務標為 `ingested`（保持 `pending`，留待授權路徑處理）。
- stderr 回報為「held」，明確指出需人類授權路徑：
  ```
  📥 ASP Inbox: ⚠️ 發現 N 個外部任務待人類授權（held）——SPEC-007 已關閉自動注入；授權路徑見 SPEC-009/asp-op pivot。未注入 ROADMAP。
  ```
- exit 0（非阻擋）。

**失敗 / 邊界情境：**

| 情境 | 行為 |
|------|------|
| inbox 不存在 / 空 | 靜默 exit 0（與現狀同） |
| 缺 jq / python3 | 提示並 exit 0（與現狀同；改動後 python3 可不再為必需） |
| ROADMAP 不存在 | 仍 exit 0；訊息改為「held」語意，不再叫使用者去 `make autopilot-init` 來接收 inbox |

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| ROADMAP.yaml **不再被 inbox-ingest 寫入** | SessionStart 有 pending 外部任務 | autopilot 執行佇列（外部任務不再無閘進入） | 測試 P1：跑 script 後 `git diff ROADMAP.yaml` 為空 |
| inbox 任務**保持 pending**（不再自動 `ingested`） | 同上 | `.asp-task-inbox.json` | 測試 P1：跑後 inbox 該筆 `status` 仍為 `pending` |
| SessionStart 訊息語意改變（注入 → held） | 每次 SessionStart | session-audit 的 A15.1 行 | 測試 P3：session-audit 輸出含「held」、不含「自動注入…至 ROADMAP」 |
| 人類手寫 ROADMAP 任務**完全不受影響** | 任何時候 | autopilot 既有機制（DP3） | 測試 P2：既有 ROADMAP 人類任務在跑 script 前後逐字不變 |

> session-audit.sh 的 A15.1 報告字串需同步調整以反映「held」語意（屬本 SPEC 範圍；屬同一致性的最小改動）。

---

## ⚠️ 邊界條件（Edge Cases）

- **Case 1（空 / 不存在 inbox）**：維持現狀靜默退出，無回報噪音。
- **Case 2（並發 SessionStart）**：本 SPEC 後 inbox-ingest 不再寫檔，**消除原本無 flock 的 ROADMAP 寫入競態**（順帶緩解缺口 #4）。
- **Case 3（已存在 ingested 的歷史任務）**：不回溯；僅改變「未來不再自動注入」。現有 INBOX-7（pending）將轉為 held、不注入。
- **Case 4（直推 `.asp-task-inbox.json` 攻擊）**：即使攻擊者寫入 inbox，也只會被 held 回報、不進 ROADMAP → T-14 攻擊面關閉。

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | `git checkout .asp/scripts/inbox-ingest.sh .asp/hooks/session-audit.sh`（還原為自動注入版本） |
| **資料影響** | 無破壞性資料變更：本 SPEC 只是**停止寫入**，未刪改 ROADMAP / inbox 內容；回滾後行為即恢復 |
| **回滾驗證** | 回滾後跑 script，確認 pending 外部任務重新被注入 ROADMAP（舊行為） |
| **回滾已測試** | ☐ 是（實作時補測試結果） |

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入條件 | 預期結果 | 對應場景 |
|---|------|---------|---------|---------|
| P1 | ✅ 正向 | inbox 有 1 筆 pending 外部任務 + ROADMAP 存在 | ROADMAP 未變更；inbox 該筆仍 pending；stderr 含「held」 | S1 |
| P2 | ✅ 正向 | ROADMAP 已含人類手寫任務 + inbox 有 pending | 人類任務逐字不變（DP3 向後相容） | S2 |
| P3 | ✅ 正向 | SessionStart 觸發 | session-audit 報告為「held」、不宣稱已注入 | S3 |
| N1 | ❌ 負向 | 直推偽造 inbox 任務（模擬攻擊） | 不進 ROADMAP，被 held 回報（T-14 關閉） | S4 |
| B1 | 🔶 邊界 | inbox 空 / 不存在 | 靜默 exit 0，無回報噪音 | S5 |
| B2 | 🔶 邊界 | ROADMAP 不存在 + inbox pending | exit 0；held 訊息；不誘導 `make autopilot-init` | S6 |

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: 關閉 inbox-ingest 無授權旁路（ADR-012 DP8）
  作為 ASP 維護者
  我想要 inbox-ingest 不再無人類授權就把外部任務注入 ROADMAP
  以便 滿足 INV-2「無外部工作可不經人類放行就跑」並關閉 T-14 攻擊面

  Background:
    Given 一個含 `.asp-task-inbox.json` 的測試專案
    And inbox 內任務皆為外部來源（source.type = github_issue）

  # --- 正向場景 ---

  Scenario: S1 - 有 pending 外部任務時不注入 ROADMAP
    Given inbox 有 1 筆 status=pending 的外部任務
    And ROADMAP.yaml 存在且含一個 milestone 的 tasks:
    When 執行 bash .asp/scripts/inbox-ingest.sh
    Then ROADMAP.yaml 內容與執行前逐字相同
    And 該 inbox 任務的 status 仍為 pending
    And stderr 含字串 "held"
    And 結束碼為 0

  Scenario: S2 - 人類手寫 ROADMAP 任務不受影響（DP3）
    Given ROADMAP.yaml 已含一筆人類手寫任務 H1
    And inbox 有 1 筆 pending 外部任務
    When 執行 bash .asp/scripts/inbox-ingest.sh
    Then 任務 H1 在 ROADMAP 中逐字不變

  Scenario: S3 - SessionStart 報告為 held 語意
    Given inbox 有 pending 外部任務
    When session-audit.sh 於 SessionStart 執行
    Then 其輸出表示外部任務為 "held / 待人類授權"
    And 其輸出不含「自動注入 N 個任務至 ROADMAP.yaml」

  # --- 負向場景 ---

  Scenario: S4 - 直推偽造 inbox 任務無法進入執行佇列（T-14）
    Given 攻擊者直接寫入一筆 pending 任務到 .asp-task-inbox.json
    When 執行 bash .asp/scripts/inbox-ingest.sh
    Then ROADMAP.yaml 未新增任何任務
    And 該任務被 held 回報

  # --- 邊界場景 ---

  Scenario Outline: S5/S6 - 邊界輸入安全退出
    Given <inbox 狀態> 且 <roadmap 狀態>
    When 執行 bash .asp/scripts/inbox-ingest.sh
    Then 結束碼為 0
    And ROADMAP.yaml 未被寫入

    Examples:
      | inbox 狀態 | roadmap 狀態 |
      | 不存在     | 存在         |
      | 空陣列     | 存在         |
      | 有 pending | 不存在       |
```

---

## ✅ 驗收標準（Done When）

- [x] `inbox-ingest.sh` 在任何情況下**都不寫入 `ROADMAP.yaml`**（移除 Python 注入區塊；改為 held 回報）
- [x] inbox 任務**不再被自動標為 `ingested`**（保持 pending 待授權）
- [x] `session-audit.sh` 的 inbox 報告字串改為 held 語意（A15.1 不再宣稱已注入，INFO→WARNING）
- [x] 新增測試 `tests/test_inbox_ingest_no_bypass.sh` 涵蓋 P1/P2/P3/N1/B1/B2，14/14 通過；`tests/test_task_inbox.sh` 同步改寫為 held 契約（8/8 通過）
- [x] `make test` 既有測試 0 回歸（RC=0；lint findings 與 baseline 完全相同，既有 2 檔 lint 債屬技術債輪）
- [x] 已更新 `CHANGELOG.md`
- [x] 已回填本 SPEC 的 Traceability 區塊

---

## 🔗 追溯性（Traceability）

| 實作檔案 | 測試檔案 | 最後驗證日期 |
|----------|----------|-------------|
| `.asp/scripts/inbox-ingest.sh`（held-mode 重寫） | `tests/test_inbox_ingest_no_bypass.sh`（14 斷言，S1-S6） | 2026-06-11 |
| `.asp/hooks/session-audit.sh`（A15.1 INFO→WARNING + held 語意） | `tests/test_task_inbox.sh`（舊注入契約→held 契約改寫，8 斷言） | 2026-06-11 |

---

## 📊 非功能需求（Non-Functional Requirements）

| 類別 | 需求 | 驗證方式 |
|------|------|----------|
| 安全 | 關閉 T-14 inbox-poisoning 攻擊面：外部 inbox 內容不得在無人類授權下進入 ROADMAP | N1 測試 + code review |
| 相容性 | 向後相容：人類手寫 ROADMAP 流程與 autopilot 既有機制零變更（DP3） | P2 回歸測試 |

---

## 📊 可觀測性（Observability）

| 面向 | 說明 |
|------|------|
| **關鍵指標** | held 任務數（stderr 回報）；ROADMAP 是否被 inbox-ingest 寫入（應恆為否） |
| **日誌** | held 任務以 WARN 級別回報於 SessionStart stderr |
| **如何偵測故障** | 若 ROADMAP 出現 `triggered_by:` / `[自動注入自 inbox]` 標記的新任務，代表旁路未關閉（迴歸） |

---

## 🚫 禁止事項（Out of Scope）

- **不**在本 SPEC 實作人類授權 / triage 機制（屬 **SPEC-009**：triage-accept）。本 SPEC 只「關閉旁路」，不「開放受控路徑」。
- **不**改 autopilot 的逐任務閘（屬 **SPEC-008**：provenance + 影響閘）。
- **不**改 asp-op（屬 asp-operator repo 的影響分類 pivot ADR）。
- **不**刪除 `.asp-task-inbox.json` 既有資料或 inbox schema。

---

## 📎 參考資料（References）

- 相關 ADR：[ADR-012](../adr/ADR-012-define-operator-autopilot-interaction-trust-model.md)（INV-2、DP8、T-14、後續追蹤「封 inbox-ingest 旁路」）
- 威脅條目：[threat-model-v4.0.md](../security/threat-model-v4.0.md) T-14
- 現有實作：`.asp/scripts/inbox-ingest.sh`（注入邏輯 line 86-153）、`.asp/hooks/session-audit.sh`（SessionStart 呼叫端）
- 後續 SPEC：SPEC-008（provenance+影響閘）、SPEC-009（triage-accept 受控路徑）
