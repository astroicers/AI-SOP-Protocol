# SPEC-008：Autopilot provenance gate for external-sourced tasks (ADR-012 DP2)

> 結構完整的規格書讓 AI 零確認直接執行。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-008 |
| **關聯 ADR** | ADR-012（INV-2、DP1、DP2、DP8；reviewer F2 防線） |
| **估算複雜度** | 低（profile 行為契約 + 文字契約測試） |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

在 autopilot 既有逐任務 ADR 閘（`.asp/profiles/autopilot.md:248-273`）**前**加入 provenance 檢查：帶**外部來源標記**的 ROADMAP 任務，必須有人類 **Accepted ADR** 才可執行（DP8 過渡期：triage-accept 未落地前，外部非架構任務一律 blocked）；**人類手寫任務的既有機制逐字不變**（DP3）。這是 SPEC-007（producer 側封旁路）之後的 **consumer 側第二層防線**——即使外部任務經任何路徑進入 ROADMAP（歷史注入、手動複製、未來 SPEC-009 通道），仍須人類授權才跑。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| ROADMAP task | YAML object | `ROADMAP.yaml` | 既有欄位；外部任務帶 `source_type` / `triggered_by` / `source_ref`（inbox 注入 schema 既有欄位） |
| provenance 判別 | 規則 | autopilot.md 新函式 `is_external_provenance(task)` | external ⇔ `source_type` 存在且 ≠ `manual`，**或** `triggered_by` 存在且 ∉ {`human`, `maintainer`}；人類手寫任務通常無這些欄位 → internal |
| ADR 狀態 | string | `FIND_ADR(task.adr)` | Draft / FIRM / Accepted |

---

## 📤 輸出規格（Expected Output）

**Phase 2 驗證行為（per task）：**

| 任務 | 條件 | 行為 |
|------|------|------|
| 外部來源 | 無 `adr:` | `blocked`（log：INV-2，等 Accepted ADR 或 SPEC-009 triage） |
| 外部來源 | `adr:` 非 Accepted（含 Draft、**FIRM**、不存在） | `blocked`（外部任務**不適用 FIRM 🟡 豁免**——INV-2 要求人類 Accept 全閘） |
| 外部來源 | `adr:` = Accepted | 放行至既有流程 |
| 人類手寫（無外部標記） | 任何 | **走既有 248-273 邏輯，逐字不變**（Draft→blocked、FIRM→🟡、adr:null→智能評估） |

**附帶輸出**：外部任務**不**觸發自動建 Draft ADR（避免 C1 噪音——外部 Draft ADR 由 asp-op pivot 產出，DP5）。

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| 外部任務被標 `blocked` 並寫回 ROADMAP | Phase 2 驗證 | ROADMAP.yaml task.status（reuse 既有 blocked 機制 282-291） | 文字契約測試 T2/T3/T4 |
| 人類手寫路徑零變更 | 任何 | autopilot 既有機制（DP3 向後相容） | 契約測試 T5：既有閘關鍵行仍存在且未被改寫 |
| asp-autopilot skill 摘要同步 | 文件一致性 | `.claude/skills/asp/asp-autopilot.md`（gate 摘要段） | 契約測試 T6 |

> 註：`.asp/profiles/` 為 source；`~/.claude/asp/profiles/` 安裝副本由既有 install/sync 流程更新（不在本 SPEC 範圍）。

---

## ⚠️ 邊界條件（Edge Cases）

- **Case 1（誤判風險，reviewer F2）**：人類手寫但誤帶 `triggered_by: customer` 的任務會被當外部 → 保守方向正確（INV-2「不確定往嚴」）；解法 = 人類補 Accepted ADR 或移除標記（其本人有權）。
- **Case 2（FIRM 外部任務）**：明文 blocked——FIRM 豁免僅限內部路徑。
- **Case 3（歷史已注入任務）**：INBOX-7 類歷史任務若曾進 ROADMAP，重跑 autopilot 即被本閘攔下（第二層防線生效證明）。
- **Case 4（blocked 下游展開）**：reuse 既有 `expand_dependents`（283）——依賴外部 blocked 任務的下游任務一併 blocked。

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | `git revert` 本 SPEC 的 commit（profile + skill + tests 為純文字變更） |
| **資料影響** | 無；被標 blocked 的任務狀態可由人類手動改回 pending |
| **回滾驗證** | revert 後契約測試 T1-T4 應 FAIL（閘不存在）、T5 仍 PASS（既有閘未動） |
| **回滾已測試** | ☐（純文字 revert，低風險） |

---

## 🧪 測試矩陣（Test Matrix）

> autopilot.md 為 AI 解讀的 profile（pseudocode），無可執行迴圈——本 SPEC 採**文字契約測試**（同 SPEC-007 對 session-audit.sh 的 S3 模式）：以 grep 斷言 profile 含正確閘邏輯、且既有邏輯未被破壞。

| # | 類型 | 輸入條件 | 預期結果 | 對應場景 |
|---|------|---------|---------|---------|
| P1 | ✅ 正向 | autopilot.md 內容 | 含 `is_external_provenance` 定義（source_type/triggered_by 規則） | S1 |
| P2 | ✅ 正向 | 同上 | 含「外部 + 無 ADR → blocked」邏輯與 INV-2 引用 | S2 |
| P3 | ✅ 正向 | 同上 | 含「外部 + 非 Accepted（含 FIRM）→ blocked、無 🟡 豁免」 | S3 |
| N1 | ❌ 負向 | 同上 | 外部任務**不**觸發自動建 Draft ADR（provenance 閘段內無 make adr-new） | S4 |
| B1 | 🔶 邊界 | 同上 | 既有內部閘逐字保留（FIND_ADR/FIRM 🟡/assess_architecture_impact 仍在） | S5 |
| B2 | 🔶 邊界 | asp-autopilot skill | 摘要含 provenance 閘一行 | S6 |

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: Autopilot 外部來源 provenance 閘（ADR-012 DP2）
  作為 ASP 維護者
  我想要 autopilot 對外部來源任務強制人類 Accepted ADR 授權
  以便 即使外部任務進入 ROADMAP 也無法未經人類授權執行（INV-2 第二層防線）

  Background:
    Given .asp/profiles/autopilot.md 為 autopilot 行為的 source of truth

  Scenario: S1 - provenance 判別函式存在
    Then autopilot.md 定義 is_external_provenance
    And 規則涵蓋 source_type 與 triggered_by 欄位

  Scenario: S2 - 外部無 ADR 任務被 blocked
    Then autopilot.md 含外部任務無 adr 即 blocked 的邏輯
    And 該段引用 INV-2 與 SPEC-009 過渡語意

  Scenario: S3 - 外部任務不適用 FIRM 豁免
    Then autopilot.md 明示外部任務 ADR 非 Accepted（含 FIRM）→ blocked

  Scenario: S4 - 外部任務不自動建 Draft ADR
    Then provenance 閘段落內不出現 make adr-new

  Scenario: S5 - 內部路徑零變更（DP3）
    Then 既有 ADR 閘關鍵邏輯仍存在：FIND_ADR、FIRM 🟡、assess_architecture_impact、blocked_by_adr

  Scenario: S6 - skill 摘要同步
    Then .claude/skills/asp/asp-autopilot.md 提及外部來源 provenance 閘
```

---

## ✅ 驗收標準（Done When）

- [x] `.asp/profiles/autopilot.md` Phase 2 含 provenance 閘（is_external_provenance + 外部授權規則 + blocked 合流），插於既有 ADR 閘之前
- [x] 外部任務規則 = 無 ADR / 非 Accepted（含 FIRM）→ blocked；Accepted → 放行；不自動建 Draft ADR
- [x] 既有內部閘邏輯逐字保留（DP3）——僅於迴圈頂加 provenance-blocked 跳過守衛（不動既有判斷行）
- [x] `.claude/skills/asp/asp-autopilot.md` 前置檢查表同步一列
- [x] `tests/test_autopilot_provenance_gate.sh` 15/15（TDD：先 10 FAIL 後全綠）
- [x] `make test` 0 回歸（RC=0）
- [x] CHANGELOG + 本 SPEC Traceability 回填

---

## 🔗 追溯性（Traceability）

| 實作檔案 | 測試檔案 | 最後驗證日期 |
|----------|----------|-------------|
| `.asp/profiles/autopilot.md`（Phase 2 provenance 閘 + blocked 合流） | `tests/test_autopilot_provenance_gate.sh`（15 斷言） | 2026-06-11 |
| `.claude/skills/asp/asp-autopilot.md`（前置檢查表同步） | 同上 S6 | 2026-06-11 |

---

## 📊 非功能需求（Non-Functional Requirements）

| 類別 | 需求 | 驗證方式 |
|------|------|----------|
| 安全 | INV-2 consumer 側強制：外部任務無人類 Accepted ADR 不得執行 | 契約測試 + code review |
| 相容性 | 人類手寫路徑零變更（DP3） | T5/B1 |

## 📊 可觀測性（Observability）

| 面向 | 說明 |
|------|------|
| **日誌** | 外部任務被閘下時 LOG 🔒 行（含 task.id、原因、INV-2 引用） |
| **如何偵測故障** | 外部標記任務在無 Accepted ADR 下出現於執行佇列 = 閘失效 |

## 🚫 禁止事項（Out of Scope）

- 不實作 triage-accept 機制與 human-author 檢查（SPEC-009）
- 不改 asp-op（跨 repo pivot ADR）
- 不改 inbox-ingest / session-audit（SPEC-007 已完）
- 不改 task_orchestrator.md 的 assess_architecture_impact

## 📎 參考資料（References）

- [ADR-012](../adr/ADR-012-define-operator-autopilot-interaction-trust-model.md) INV-2 / DP1 / DP2 / DP8、reviewer F2
- 既有閘：`.asp/profiles/autopilot.md:248-273`；blocked 機制 `:282-291`
- 文字契約測試先例：`tests/test_inbox_ingest_no_bypass.sh` S3
