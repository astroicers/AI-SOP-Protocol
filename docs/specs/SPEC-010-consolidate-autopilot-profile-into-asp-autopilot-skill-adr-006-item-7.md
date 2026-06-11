# SPEC-010：Consolidate autopilot profile into asp-autopilot skill (ADR-006 Item 7)

> 結構完整的規格書讓 AI 零確認直接執行。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-010 |
| **關聯 ADR** | ADR-006（Item 7，Accepted）；牽動 ADR-001 / ADR-012 Relations |
| **估算複雜度** | 中（純文件搬遷 + 引用收斂，無行為變更） |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

執行 ADR-006 Item 7：**刪除 `.asp/profiles/autopilot.md`，執行邏輯收斂入 `.claude/skills/asp/asp-autopilot.md`**（依 ADR-007 multi_agent.md 先例：完整刪除、不留 stub）。結束 C2 漂移（autopilot 雙身：profile 582→616 行 + skill 238 行並存）。**行為零變更**——SPEC-008/009 的 provenance 閘等執行規格原文遷移，由既有契約測試（retarget 後）保真。

> **誠實修正 ADR-006 估算**：Item 7 寫「-566 行、低風險」是在 SPEC-008/009 之前；現 profile 內含活的安全閘（248-300 行），真實風險=中、淨刪行數約 -90~-120（閘與執行規格必須活著搬走，僅真重複段落消失）。

---

## 📥 輸入規格（Inputs）

| 參數 | 型別 | 來源 | 限制條件 |
|------|------|------|----------|
| 遷移源 | markdown | `.asp/profiles/autopilot.md`（616 行） | 全文為準；搬遷後刪除 |
| 遷移地 | markdown | `.claude/skills/asp/asp-autopilot.md`（238 行） | 既有 Part（操作視圖）不動；新增 Part 2（完整執行規格，canonical） |
| 引用清單 | grep | `CLAUDE.md`、`.asp/scripts/validate-profile.sh`、tests×2、ADR-001/006/012 | 全部收斂或標記 |

### 章節去向對照表（migration ledger，可稽核）

| Profile 章節（行） | 去向 |
|---|---|
| 啟用前提 (16-24) | **捨棄** — 條件 2（ROADMAP.yaml 存在）由 skill Phase 1a 覆蓋；條件 1/3（`.ai_profile` 的 `autopilot: enabled` + autonomous_dev/task_orchestrator 已載入）為 **CLAUDE.md 啟動程序的前置責任**（architectural delegation，非 skill 執行範圍）——G2 review F3 修正 |
| 前置文件動態探測 (25-60) | **遷入 Part 2**（detect_required_documents 偽代碼僅此處有） |
| CLAUDE.md 專案描述自動產生 + Phase 6.5 README (61-135) | **遷入 Part 2** |
| Profile 自動載入 auto_configure_profiles (136-166) | **遷入 Part 2** |
| 核心流程 Phase 0.5–5（167-481，**含 SPEC-008/009 provenance 閘 248-300**） | **遷入 Part 2 原文**（契約測試保真） |
| Session Bridge 狀態檔 (482-510) | **遷入 Part 2**（schema 僅此處完整） |
| ROADMAP 更新規則 (511-532) | **遷入 Part 2** |
| 安全邊界（完整三表 533-584） | **遷入 Part 2**（skill 零確認策略僅摘要版，保留並指向 Part 2） |
| Context 管理 (585-597) | **捨棄** — skill Phase 3（60%/75% 閾值）已覆蓋 |
| 與其他 Profile 的關係 (598-616) | **改寫後遷入**（autopilot 已非 profile；改述 skill 與 autonomous_dev/task_orchestrator profiles 的關係） |

---

## 📤 輸出規格（Expected Output）

- `asp-autopilot.md` = 既有操作視圖 + **「Part 2 — 完整執行規格（canonical）」**；檔頭註明「v4.4 起本 skill 為 autopilot 唯一 canonical source（ADR-006 Item 7）」。
- `.asp/profiles/autopilot.md` **不存在**；安裝副本由既有 `rsync --delete`（install.sh/asp-update）自動清除。
- 引用全收斂：CLAUDE.md 啟動程序/映射表改指 skill；validate-profile.sh 不再 echo 已刪檔案；ADR-001 Relations 標記 Item 7 已執行（C2 結案）；ADR-012 Relations 同步。
- 契約測試 retarget 後全綠（遷移保真證明）。

**失敗情境**：任一契約斷言在 skill 中找不到對應原文 → 遷移不完整，禁止刪 profile。

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響 | **驗證方式** |
|--------|---------|------|------------|
| `~/.claude/asp/profiles/autopilot.md` 將於下次 sync 被刪 | rsync --delete | 安裝副本 | release note 註記；asp-update 後人工複驗 |
| `.ai_profile` 的 `autopilot: enabled` 語意不變 | 啟動程序讀 CLAUDE.md | 載入指向 skill 而非 profile | 測試 T3（CLAUDE.md 無 profile 殘留引用） |
| ADR-001「被取代（部分）」段定案 | Relations 更新 | 文件一致性 | grep 驗證 |

---

## ⚠️ 邊界條件（Edge Cases）

- **E1（契約測試斷言遺失）**：搬遷時任何閘關鍵字（is_external_provenance / blocked_by_provenance / git log -S / `[bot]` / FIRM 豁免規則）漏搬 → retarget 後測試紅 → 阻止刪檔。
- **E2（歷史文件引用）**：ADR-001/008/012、SPEC-007/008/009、CHANGELOG、gate-log 等**歷史記錄**中的 `.asp/profiles/autopilot.md` 字樣**不改**（歷史事實）；只收斂「會被執行/載入」的活引用（CLAUDE.md、validate-profile.sh、SKILL.md、README、docs/autopilot.md 若有）。
- **E3（雙寫期）**：搬遷與刪除在**同一 commit**，無雙 canonical 窗口。
- **E4（舊版安裝者）**：未跑 asp-update 的機器仍有舊 profile —— CLAUDE.md（repo 版）已不再指向它，故不會被載入；release note 提醒。

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | `git revert` 本 commit：profile 復活、skill 回 238 行、引用復原 |
| **資料影響** | 零（純文件） |
| **回滾驗證** | revert 後契約測試（指回 profile 路徑）全綠 |
| **回滾已測試** | ☐（純文字 revert，低風險） |

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入 | 預期 | 場景 |
|---|------|------|------|------|
| P1 | ✅ | `test_autopilot_provenance_gate.sh` retarget → skill | 15/15（閘原文保真） | S1 |
| P2 | ✅ | `test_inbox_triage.sh` retarget → skill | 20/20（DP4 契約保真） | S1 |
| P3 | ✅ | 新 `test_autopilot_consolidation.sh` | profile 已刪 + skill 含 canonical 標記 + ledger 各「遷入」節錨點存在 | S2 |
| N1 | ❌ | 活引用掃描 | CLAUDE.md / validate-profile.sh / SKILL.md 無 `.asp/profiles/autopilot.md` 活引用 | S3 |
| B1 | 🔶 | 歷史文件 | ADR/SPEC/CHANGELOG 歷史引用**不**被改動 | S4 |

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: autopilot profile 整併入 skill（ADR-006 Item 7）
  作為 ASP 維護者
  我想要 autopilot 只有一個 canonical 定義
  以便 消除 C2 雙身漂移且行為零變更

  Background:
    Given ADR-006 已 Accepted 且 Item 7 為其明文承諾

  Scenario: S1 - 契約測試 retarget 後保真
    When 兩個既有契約測試的目標路徑改為 asp-autopilot.md
    Then 15/15 與 20/20 全綠（閘與 DP4 原文存在於 skill）

  Scenario: S2 - profile 刪除且 skill 成為 canonical
    Then .asp/profiles/autopilot.md 不存在
    And asp-autopilot.md 含 canonical 標記與 Part 2 完整執行規格
    And ledger 標記「遷入」的每一節在 skill 中有對應錨點

  Scenario: S3 - 活引用收斂
    Then CLAUDE.md、validate-profile.sh、SKILL.md 不含已刪 profile 的活引用

  Scenario: S4 - 歷史不可竄改
    Then 既有 ADR/SPEC/CHANGELOG/gate-log 中的歷史路徑字樣維持原樣
```

---

## ✅ 驗收標準（Done When）

- [x] `tests/test_autopilot_provenance_gate.sh`（15/15）+ `tests/test_inbox_triage.sh`（20/20）retarget → 全綠（2026-06-11）
- [x] 新 `tests/test_autopilot_consolidation.sh` 17/17（S2/S3/S4）
- [x] `.asp/profiles/autopilot.md` 已刪（git rm）；skill 含 canonical 標記 + Part 2（829 行）
- [x] CLAUDE.md 啟動程序 + Profile 映射改指 skill；validate-profile.sh 更新（bash -n 過）
- [x] ADR-001 / ADR-012 Relations 更新（C2 結案）——Accepted ADR 內文變更**僅限 Relations/追蹤段交叉引用**，且**由人類 review+merge PR 核可後才生效**（AI 不自行宣告；G2 review F1+F2 修正：原「ADR-006 Item 7 勾選」無 checkbox 可勾且撞 no-modify-Accepted-ADR 規則，已移除——完成證據改由本清單前三項承載）；各 ADR 修訂均經 G1 auto-gate review（log 見 .asp-gate-log/20260611T073000Z-G1-*.md）
- [x] `make test` 0 回歸、`make lint` RC=0
- [x] CHANGELOG（含誠實行數修正：實際 ≈ +213/-616，非 ADR-006 原估 -566）+ 本 SPEC Traceability 回填

---

## 🔗 追溯性（Traceability）

| 實作檔案 | 測試檔案 | 最後驗證日期 |
|----------|----------|-------------|
| `.claude/skills/asp/asp-autopilot.md`（+Part 2，238→829 行） | `test_autopilot_provenance_gate.sh`、`test_inbox_triage.sh`（retarget） | 2026-06-11 |
| `.asp/profiles/autopilot.md`（刪除） | `test_autopilot_consolidation.sh`（新，17 斷言） | 2026-06-11 |
| `CLAUDE.md`、`.asp/scripts/validate-profile.sh`、ADR-001/009/012 Relations/追蹤段 | 同上 S3/S4 | 2026-06-11 |

---

## 📊 可觀測性（Observability）

| 面向 | 說明 |
|------|------|
| **如何偵測故障** | autopilot 行為退化 = 契約測試紅；活引用殘留 = consolidation 測試 N1 紅 |
| **如何確認成功** | `make test` 全綠 + skill 含 canonical 標記 + `.asp/profiles/autopilot.md` 不存在（三項皆 grep/ls 可驗） |

## 🚫 禁止事項（Out of Scope）

- 不改 autopilot 任何**行為**（純搬遷；行為變更須另開 SPEC）
- 不動其他 profiles（autonomous_dev / task_orchestrator 照舊）
- 不改歷史文件中的路徑字樣（E2）
- 不處理 docs/autopilot.md 使用者文件的深度改寫（僅必要的路徑修正）

## 📎 參考資料

- [ADR-006](../adr/ADR-006-feature-audit-roadmap.md) Item 7（:89）
- ADR-007 先例：multi_agent.md 完整刪除、無 stub
- 契約測試：`test_autopilot_provenance_gate.sh`（15）、`test_inbox_triage.sh`（20）
- [ADR-012](../adr/ADR-012-define-operator-autopilot-interaction-trust-model.md)（閘的權威定義）
