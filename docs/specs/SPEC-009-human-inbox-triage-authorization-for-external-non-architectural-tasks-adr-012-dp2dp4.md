# SPEC-009：Human inbox-triage authorization for external non-architectural tasks (ADR-012 DP2/DP4)

> 結構完整的規格書讓 AI 零確認直接執行。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-009 |
| **關聯 ADR** | ADR-012（DP2 非架構授權、DP4 human-author、DP8 過渡期終止） |
| **估算複雜度** | 中 |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

提供外部**非架構**任務的受控人類放行通道：人類執行 `make inbox-triage` 檢視 held 任務、逐件核准/駁回；核准者寫入 ROADMAP（帶 `triage_accepted_by`）並由**人類自己 commit**——該 commit 的作者即 DP4 要求的機械可驗證授權記號。autopilot provenance 閘（SPEC-008）擴充：外部任務若帶 triage 記號**且引入 commit 作者非 bot** → 放行（管線深度仍由既有 severity 分類決定，DP2）。本 SPEC 落地後 **DP8 過渡期終止**（外部非架構路徑啟用）。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| held 任務 | JSON | `.asp-task-inbox.json`（status=pending） | SPEC-007 held 機制的產物 |
| 人類決定 | 互動 y/n/s 或 CLI 旗標 | `make inbox-triage`（互動）；`--approve <ID>` / `--reject <ID>`（scripting/測試） | 寫入後**由人類 git commit**（工具不 commit） |
| 核准者身分 | string | `git config user.name` | 寫入 `triage_accepted_by` |
| 引入 commit 作者 | git history | autopilot 閘以 `git log -S "id: {task.id}" -- ROADMAP.yaml` 查 | bot 樣式（`[bot]`／`asp-op`／`autopilot`）→ 拒絕（DP4） |

---

## 📤 輸出規格（Expected Output）

**核准（approve）：**
- 任務寫入 ROADMAP 第一個 milestone 的 `tasks:`（沿用原注入 schema + 新欄位 `triage_accepted_by` / `triage_accepted_at`；`adr: null`、`status: pending`、保留 provenance 標記）。
- inbox 該筆 `status: pending → triaged`（不再出現在 held 回報）。
- 工具提示人類自行 `git commit`（授權在 commit 作者，不在工具）。

**駁回（reject）：** inbox 該筆 `status: pending → rejected`；不碰 ROADMAP。

**autopilot 閘行為（SPEC-008 擴充）：**

| 外部任務 | 條件 | 行為 |
|----------|------|------|
| 有 Accepted ADR | — | 放行（架構級授權，原 SPEC-008 邏輯） |
| 無 Accepted ADR、有 `triage_accepted_by` | 引入 commit 作者**非 bot** | 放行 → 管線深度由 severity 分類決定 |
| 無 Accepted ADR、有 `triage_accepted_by` | 引入 commit 作者**是 bot**（`[bot]`/asp-op/autopilot） | `blocked`（DP4：bot 不可自核） |
| 兩者皆無 | — | `blocked`（INV-2，原 SPEC-008 邏輯） |

**失敗情境：**

| 情境 | 行為 |
|------|------|
| ROADMAP.yaml 不存在 | 提示 `make autopilot-init`，exit 1（triage 需有目的地） |
| 無 held 任務 | 提示後 exit 0 |
| `--approve` 指定不存在/非 pending 的 ID | 錯誤訊息，exit 1 |
| jq/python3 缺 | 提示，exit 1（triage 是主動操作，可硬性要求） |

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| ROADMAP 新增帶 triage 記號的任務 | approve | autopilot 任務佇列 | 測試 T2：欄位齊全（id/provenance/triage_accepted_by） |
| inbox status 轉移 pending→triaged/rejected | approve/reject | held 回報（SPEC-007）自動減少 | 測試 T2/T3：jq 驗 status |
| autopilot 閘新增 triage 分支 | profile 更新 | `.asp/profiles/autopilot.md` SPEC-008 閘段 | 契約測試 S7 |
| session-audit / inbox-ingest held 訊息指向 `make inbox-triage` | 文件一致性 | A15.1 + held 提示 | 測試 S8（grep） |
| **DP8 過渡期終止** | 本 SPEC 落地 | ADR-012 DP8 語意 | CHANGELOG 記錄 |

---

## ⚠️ 邊界條件（Edge Cases）

- **Case 1（bot 自核，DP4 核心攻擊）**：autopilot/asp-op 自行寫 `triage_accepted_by` 並 commit → 閘查引入 commit 作者撞 bot 樣式 → blocked。
- **Case 2（squash/rebase 混淆作者）**：人類 squash 他人變更時作者歸 squash 者（仍為人類）→ 可接受；bot squash 人類變更 → 變 bot 作者 → 保守 blocked（INV-2「不確定往嚴」）。
- **Case 3（重複 approve 同 source_ref）**：寫入前查 ROADMAP 既有 `source_ref` 去重（沿用原 inbox-ingest 去重邏輯）。
- **Case 4（並發）**：triage 是人類主動單點操作，無 SessionStart 並發；寫入仍為單程序檔案操作。

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | `git revert` 本 SPEC commit；已 triage 進 ROADMAP 的任務由人類手動移除或標 blocked |
| **資料影響** | inbox status 轉移可手動改回 pending |
| **回滾驗證** | revert 後 `make inbox-triage` target 不存在；閘退回 SPEC-008 行為（外部全 blocked 除非 Accepted ADR） |
| **回滾已測試** | ☐（純文字/腳本 revert，低風險） |

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入條件 | 預期結果 | 對應場景 |
|---|------|---------|---------|---------|
| P1 | ✅ 正向 | `--approve INBOX-X`（pending 存在、ROADMAP 存在） | ROADMAP 含該任務 + `triage_accepted_by`；inbox 轉 `triaged` | S1 |
| P2 | ✅ 正向 | `--reject INBOX-X` | inbox 轉 `rejected`；ROADMAP 不變 | S2 |
| P3 | ✅ 正向 | approve 後再 approve 同 source_ref | 去重拒絕，ROADMAP 只一筆 | S3 |
| N1 | ❌ 負向 | ROADMAP 不存在 | exit 1 + 提示 autopilot-init | S4 |
| N2 | ❌ 負向 | approve 不存在的 ID | exit 1 + 錯誤訊息 | S5 |
| B1 | 🔶 邊界 | 無 held 任務 | exit 0 + 提示 | S6 |
| P4 | ✅ 正向（契約） | autopilot.md | 閘含 triage_accepted_by 分支 + git log 作者驗證 + bot 樣式拒絕（DP4） | S7 |
| B2 | 🔶 邊界（契約） | autopilot.md + session-audit.sh | SPEC-008 既有斷言不破壞；held 訊息指向 make inbox-triage | S8 |

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: 外部非架構任務的人類 triage 授權（ADR-012 DP2/DP4）
  作為 ASP 維護者
  我想要 held 任務經人類核准（其 commit 即授權記號）後才進入 autopilot 佇列
  以便 開通外部非架構路徑而不破壞 INV-2（DP8 過渡期終止）

  Background:
    Given 沙箱專案含 held inbox 任務與 ROADMAP.yaml

  Scenario: S1 - approve 寫入 ROADMAP 並轉 triaged
    When 執行 inbox-triage --approve INBOX-X
    Then ROADMAP 含該任務且帶 triage_accepted_by 與 provenance 標記
    And inbox 該筆 status 為 triaged

  Scenario: S2 - reject 不碰 ROADMAP
    When 執行 inbox-triage --reject INBOX-X
    Then inbox 該筆 status 為 rejected
    And ROADMAP 內容不變

  Scenario: S3 - 重複 approve 去重
    Given INBOX-X 已 approve 過（ROADMAP 已含其 source_ref）
    When 再次 approve 相同 source_ref 的任務
    Then ROADMAP 中該 source_ref 僅一筆

  Scenario: S4 - 無 ROADMAP 即失敗
    Given ROADMAP.yaml 不存在
    When 執行 inbox-triage --approve INBOX-X
    Then exit code 非 0 且提示 autopilot-init

  Scenario: S5 - 不存在的 ID
    When 執行 inbox-triage --approve INBOX-NOPE
    Then exit code 非 0

  Scenario: S6 - 無 held 任務安全退出
    Given inbox 無 pending 任務
    When 執行 inbox-triage
    Then exit code 為 0

  Scenario: S7 - autopilot 閘含 DP4 人類驗證
    Then autopilot.md 閘含 triage_accepted_by 分支
    And 含 git log 引入 commit 作者驗證與 bot 樣式拒絕

  Scenario: S8 - 既有契約不破壞 + 訊息導向 triage
    Then SPEC-008 契約測試仍全過
    And session-audit 或 inbox-ingest 的 held 訊息提及 make inbox-triage
```

---

## ✅ 驗收標準（Done When）

- [x] `.asp/scripts/inbox-triage.sh` 實作（互動 + `--approve`/`--reject`；工具不 git commit）
- [x] `make inbox-triage` target
- [x] autopilot.md 閘擴充 triage 分支（含 DP4 bot 樣式拒絕）；SPEC-008 既有契約測試 15/15 不回退
- [x] held 訊息（inbox-ingest + session-audit A15.1）指向 `make inbox-triage`
- [x] `tests/test_inbox_triage.sh` 20/20（TDD：先 17 FAIL 後全綠）
- [x] `make test` 0 回歸（RC=0）
- [x] CHANGELOG（記 DP8 過渡期終止）+ 本 SPEC Traceability 回填

---

## 🔗 追溯性（Traceability）

| 實作檔案 | 測試檔案 | 最後驗證日期 |
|----------|----------|-------------|
| `.asp/scripts/inbox-triage.sh`（新） | `tests/test_inbox_triage.sh`（20 斷言） | 2026-06-11 |
| `.asp/Makefile.inc`（inbox-triage target） | 同上 S9 | 2026-06-11 |
| `.asp/profiles/autopilot.md`（閘 triage 分支 + DP4） | 同上 S7 + `test_autopilot_provenance_gate.sh` 15/15 | 2026-06-11 |
| `.asp/scripts/inbox-ingest.sh` + `.asp/hooks/session-audit.sh`（held 訊息導向） | 同上 S8 | 2026-06-11 |

---

## 📊 非功能需求（Non-Functional Requirements）

| 類別 | 需求 | 驗證方式 |
|------|------|----------|
| 安全 | DP4：授權記號的引入 commit 作者可機械驗證為非 bot；bot 自核 0 例通過 | 契約測試 S7 + code review |
| 相容性 | SPEC-007/008 行為不回退（held 不變、內部路徑不變） | 既有測試 0 回歸 |

## 📊 可觀測性（Observability）

| 面向 | 說明 |
|------|------|
| **日誌** | triage 操作逐筆輸出（approve/reject/dedup）；autopilot 閘 triage 放行/拒絕各有 LOG 行 |
| **如何偵測故障** | bot-authored triage 記號被放行 = DP4 失效（契約測試守住） |

## 🚫 禁止事項（Out of Scope）

- 不改 asp-op（架構級 Draft-ADR pivot 屬 asp-operator repo ADR）
- 不自動 commit / push（授權必須是人類的 commit）
- 不實作 GitHub UI / PR 型 triage（設計決策已否決）

## 📎 參考資料（References）

- [ADR-012](../adr/ADR-012-define-operator-autopilot-interaction-trust-model.md) DP2/DP4/DP8
- SPEC-007（held 機制）、SPEC-008（provenance 閘）
- 原注入 schema：git history `a445de8^:.asp/scripts/inbox-ingest.sh`（YAML block :86-126）
