# SPEC-012：bypass log hash chain

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-012 |
| **關聯 ADR** | ADR-019 |
| **估算複雜度** | 中 |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

為 `.asp-bypass-log.ndjson` 每筆記錄建立 per-entry hash chain，使 Iron Rule B 能偵測「等量替換」與「單點 HWM 竄改」兩項 TD-002 已記殘留 —— 把無痕抹除一筆鐵則稽核的成本從「改一個數字」提高到「重算整條 chain」。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| bypass entry | JSON object（NDJSON 一行） | `make asp-bypass-record` / asp-ship bypass 路徑 | 含 timestamp/skill/step/reason/actor |
| 既有 log | `.asp-bypass-log.ndjson` | 本機（gitignored） | 可能為舊格式（無 hash 欄）→ 需遷移 |

---

## 📤 輸出規格（Expected Output）

**寫入端（append）：** 每筆 entry 補兩欄
```json
{"timestamp":"...","skill":"asp-ship","step":"Step1","reason":"...","actor":"ai","prev":"<前筆 h 或 GENESIS>","h":"<sha256(prev + canonical_without_h)>"}
```

**驗證端（session-audit Iron Rule B）：**

| 情境 | 結果 |
|------|------|
| chain 完整 | 無 BLOCKER（HWM 截斷檢查照舊互補） |
| 任一筆 `h` 不符 / `prev` 斷裂 | BLOCKER：列出首個斷裂的行號 |
| 舊格式（chain 未啟用 `chained=0`/未設） | 不報 chain BLOCKER（容錯，提示遷移），HWM 仍生效 |
| chain 已啟用（`chained=1`）但某筆缺 `h` | **BLOCKER**（防「刪 hash 欄降級」繞過 — FIND-2，見 Edge Cases） |

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| Iron Rule B 段新增 chain 驗證 | 每次 session-audit | `.asp/hooks/session-audit.sh`（hook stdout / briefing blockers） | `test_iron_rule_b_hashchain.sh` N1/N2 |
| 寫入端計算並串接 hash | append bypass 記錄 | `make asp-bypass-record` 寫入路徑 | append 後 chain 驗證通過（P1） |
| 既有 log 一次性遷移補算 chain | 升級後首次 | 遷移腳本 / make target | 遷移後 chain 驗證通過（B2） |
| chain-enabled marker（HWM sidecar 記 `chained=1`） | 遷移 / 首次 hash 寫入 | `.asp-bypass-log.hwm`（升級為記 `chained`） | N7：啟用後刪 hash 欄 → BLOCKER |
| 共用 canonical 函式 `bypass-hash.sh` | 寫入/驗證/遷移三端 | 新腳本（單一實作點，FIND-1） | P1 三端算出同 hash |
| rule-registry `IRON-B` desc 更新 | 實作完成 | `.asp/config/rule-registry.yaml` | `test_rule_registry.sh` 仍綠 |

---

## ⚠️ 邊界條件（Edge Cases）

- 空 log（0 筆）→ chain 驗證 trivially pass，無 BLOCKER。
- 首筆 `prev` = 常數 `GENESIS`；非首筆 `prev` 必須等於前一筆的 `h`，否則 BLOCKER。
- **canonical 規範（FIND-1，單一實作點 `bypass-hash.sh`，寫入/驗證/遷移三端共用）**：
  `canonical = jq -cS '<entry 去掉 h 欄>'`（compact + key 字典序排序）；
  `material = prev + "\n" + canonical`；
  `h = printf '%s' "$material" | sha256sum | cut -d' ' -f1`（小寫 hex）。
  三端任一偏離即同內容算出不同 hash → 全 chain 假陽性，故**必須抽共用函式**，禁止各自 inline。
- **容錯降級防護（FIND-2，HIGH）**：chain 一旦啟用即在 HWM sidecar 記 `chained=1`。
  此後「log 非空但任一筆缺 `h`」→ **BLOCKER**（不再容錯）。容錯僅適用 `chained=0/未設` 的純未遷移舊 log。
  這擋住「等量替換後連 `prev`/`h` 欄一起刪、降級回容錯分支」的繞過（否則 TD-002 修補形同虛設）。
  **誠實殘留**：`chained` marker 本地仍可竄改（刪 HWM 或改 `chained=0`）→ 繞過成本提高到「同步改
  log + HWM」，但**非 tamper-proof**；真正防護需 ADR-019 選項 C 外部信任錨。此殘留記入 ADR-019 後續追蹤。
- 等量替換（改一筆 `reason` 保持行數）→ 該筆 `h` 不符 → BLOCKER（HWM 偵測不到，由 chain 補上）。
- 中間筆被竄改 → 其 `h` 變 → 後續所有 `prev` 斷裂 → BLOCKER 指向首斷裂點。
- HWM 被同步降低以掩飾刪行 → chain `prev` 斷裂仍 BLOCKER（chain 對 HWM 竄改的獨立防護，N5）。

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | `git revert` SPEC-012 commits；`prev`/`h` 為附加欄，舊 session-audit 忽略未知欄位 → 向後相容 |
| **資料影響** | bypass log 內容不丟（只加欄位）；遷移可逆（移除 `prev`/`h` 回原格式，不損 reason/actor 等稽核欄） |
| **回滾驗證** | revert 後 `make test` 全綠；session-audit 退回 HWM-only 行為 |
| **回滾已測試** | ☐ 否（實作時補：模擬 revert 後跑 test_iron_rule_b_truncation.sh 確認 HWM 路徑仍生效） |

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入條件 | 預期結果 | 對應場景 |
|---|------|---------|---------|---------|
| P1 | ✅ 正向 | 正常 append（正確 prev/h）；寫入/驗證/遷移三端同 hash | 無 BLOCKER | S1 |
| P2 | ✅ 正向 | 空 log（0 筆） | 無 BLOCKER | S1 |
| N1 | ❌ 負向 | 等量替換（改一筆內容、行數不變） | chain BLOCKER | S2 |
| N2 | ❌ 負向 | 竄改中間筆 h | chain 斷裂 BLOCKER（指向首斷點） | S2 |
| N3 | ❌ 負向 | 刪一筆中間（行數降） | HWM BLOCKER（既有）+ chain 斷裂 | S2 |
| N4 | ❌ 負向 | 純舊格式 log（`chained=0`，無 hash 欄） | 不假陽性（容錯），僅提示遷移 | S3 |
| N5 | ❌ 負向 | 刪一筆 + **同步降 HWM** 騙過截斷檢查 | chain `prev` 斷裂仍 BLOCKER（獨立於 HWM） | S2 |
| N6 | ❌ 負向 | 非首筆 `prev` 偽設 GENESIS | BLOCKER | S2 |
| N7 | ❌ 負向 | `chained=1` 後移除某筆 hash 欄（FIND-2 繞過） | BLOCKER（不降級容錯） | S2 |
| B1 | 🔶 邊界 | 首筆 prev=GENESIS | 驗證通過 | S3 |
| B2 | 🔶 邊界 | 舊格式 log 遷移後（`chained=1`） | chain 嚴格驗證通過 | S3 |

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: bypass log hash chain（Iron Rule B 防竄改）
  作為 ASP 治理機制
  我想要 每筆 bypass 稽核記錄以 hash 串接
  以便 偵測等量替換與單點 HWM 竄改

  Background:
    Given 一個含 hash chain 的 .asp-bypass-log.ndjson

  Scenario: S1 - 正常 append 與空 log 不報錯
    Given chain 完整（或 log 為空）
    When session-audit 跑 Iron Rule B
    Then 不產生 chain BLOCKER

  Scenario: S2 - 竄改被偵測
    Given 一條完整的 chain
    When 某一筆 entry 的內容被等量替換或 h 被竄改
    And session-audit 跑 Iron Rule B
    Then 產生 BLOCKER 並指出首個斷裂的行號

  Scenario Outline: S3 - 邊界
    When chain 狀態為 "<state>"
    Then 結果為 "<result>"

    Examples:
      | state            | result        |
      | 首筆 GENESIS     | 驗證通過      |
      | 舊格式未遷移     | 容錯+提示遷移 |
      | 舊格式已遷移     | 嚴格驗證通過  |
```

---

## ✅ 驗收標準（Done When）

- [ ] `bash tests/test_iron_rule_b_hashchain.sh` 全綠（P1/P2/N1–N7/B1/B2，含 FIND-2 繞過 N7、HWM 獨立性 N5、canonical 三端一致 P1）
- [ ] `make test` 全綠（既有測試零回歸，特別 `test_iron_rule_b_truncation.sh`、`test_rule_registry.sh`）
- [ ] 既有 `.asp-bypass-log.ndjson`（2 筆）遷移後 chain 驗證通過
- [ ] 手動驗證：等量替換一筆 → session-audit 輸出 BLOCKER
- [ ] `make lint` 無 error
- [ ] 已更新 `CHANGELOG.md`、Iron Rule B 註解、rule-registry `IRON-B` desc

---

## 🚫 禁止事項（Out of Scope）

- 不做選項 C（chain tip 外部信任錨定）— ADR-019 列為後續獨立 ADR
- 不引入 secret/HMAC（ADR-019 選項 B 已否決為 security theater）
- 不改變 bypass log 的 gitignored / local-only 性質（TD-002 決策）

---

## 📎 參考資料（References）

- 相關 ADR：ADR-019（威脅模型：tamper-evidence 非 tamper-proof）
- 現有類似實作：`.asp/hooks/session-audit.sh` §Iron Rule B（HWM 邏輯）；`tests/test_iron_rule_b_truncation.sh`
- 外部文件：TD-002（`docs/tech-debt-2026-06-08.md`）
