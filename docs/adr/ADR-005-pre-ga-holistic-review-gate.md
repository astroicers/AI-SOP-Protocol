# [ADR-005]: GA Tag 前須由獨立 Reality-Checker 做 Holistic Review

| 欄位 | 內容 |
|------|------|
| **狀態** | `Draft` |
| **日期** | 2026-05-10 |
| **決策者** | astroicers（待確認）|
| **觸發事件** | v4.1.0 GA → v4.1.1 review-fix 落差 |

---

## 背景（Context）

v4.1.0 GA tag 由 AI 在 7 batch 連續實作後自評「SPEC-004 Done When 18/18 = 100%」並打上。獨立 reality-checker 在 GA tag 之後做 holistic review，抓到 4 個真實問題：

1. `make agent-worktree-{list,gc,gc-dry-run}` 沒注入 `ASP_AUDIT_ROOT` → 功能完全不可用
2. `asp-dispatch.md` Step 6 仍指示 v3.7 廢止的 `.agent-lock.yaml`
3. 退出碼 4 三處定義不一致
4. `telemetry.md` 主表漏 2 個已實作的 event 型別

加上 SPEC-004 Done When 計數虛報：
- #1 「7P+8N+6B = 21 項全綠」實際 19/21（B4/N2 無測試）
- #1 「96 assertions」實際 113
- #8 「P1-P7 / N1-N8 / B1-B6 全驗證」實際 N2 + B4 沒驗證

落差成因：**AI 實作完一條 Done When 就勾 [x]，但「實作宣稱完成」≠「測試實際 cover 該場景」**。在沒有獨立檢驗的情況下，AI 對自己的工作有系統性的樂觀偏誤。

v4.1.1 review-fix 釋出後（commit `7259662`），落差被誠實記錄並修正，但**這個 process gap 本身需要制度化的對策**，否則 v4.2 GA 又會重蹈覆轍。

---

## 評估選項（Options Considered）

### 選項 A：維持現狀，靠 AI 自律
- **優點**：零流程開銷
- **缺點**：v4.1.0 已證明這條路不可行 — AI 連續實作後對自己的勾選有系統性偏誤
- **風險**：每次 GA 都是 review-fix patch 的循環

### 選項 B：人類在 GA 前手動審核
- **優點**：人類眼光最可靠、零工具依賴
- **缺點**：規模 N 個 Done When 時人類只能抽樣、容易漏掉細節 drift（reality-checker 抓的 4 個都是文件層細節，人類肉眼掃 18 條清單時容易跳過）；增加人類 toil
- **風險**：成為 release 瓶頸，反而誘使「先打 tag 後補 review」

### 選項 C：制度化「GA tag 前必須有獨立 reality-checker holistic review」（本決策）
- **優點**：
  - 獨立 agent 沒有 implementation context 偏袒，符合 D-008 「Reality Checker 三層獨立性」精神
  - holistic review 同時驗證實作 vs SPEC、實作 vs 鐵則、文件 vs 實作三個面向，覆蓋 v4.1.0 漏的所有類型 finding
  - 流程開銷低（一次 agent invocation，~10 分鐘）
- **缺點**：增加一個「GA 前必經」步驟、需要明確 release runbook 文件化
- **風險**：若 reality-checker 太挑剔，每次都會延遲 GA — 必須定義「✅ OK / ⚠️ 需修正 / ❌ 嚴重不一致」的處理規則，避免 ⚠️ 變成 release blocker

---

## 決策（Decision）

**選擇選項 C**：所有版本號變動超過 patch level（即 minor / major release，例如 v4.1.0、v4.2.0、v5.0.0、含 alpha/beta/rc 預發布版本）的 GA tag，**必須**先由獨立 reality-checker agent 做 holistic review，確認三層級（SPEC / 鐵則 / 文件）一致性。Patch release（例如 v4.1.1、v4.0.1）豁免，因為通常本身就是 review-fix。

### Holistic review 三層級（reviewer 必須各別出結論）

| 層級 | 檢查重點 | 證據要求 |
|------|---------|---------|
| **L1: 實作 vs SPEC** | Done When 是否每條都有測試 cover；退出碼語意一致；Out of Scope 沒被偷渡違反 | 列出 file:line |
| **L2: 實作 vs ASP 鐵則** | 7 條 Iron Rules 是否被遵守；廢止機制是否還有殘留引用 | 列出 file:line |
| **L3: 文件 vs 實作雙向同步** | README / architecture.md / profile / runbook / CHANGELOG / SPEC Gherkin 與實作一致 | 列出 file:line |

### Reviewer 輸出規則

每層級必須給 **✅ OK / ⚠️ 需修正 / ❌ 嚴重不一致** 結論，附 file:line 證據，最後分類：

- **建議發 patch（v4.x.y+1）修哪些**
- **哪些可以留待下個 minor**
- **哪些是 reviewer 多慮了**

### Release gate 處理規則

| Reviewer 結論 | 處理 |
|--------------|------|
| 全 ✅ | GA tag 通過 |
| 任一 ⚠️ | **修完才能打 GA tag**；或 GA tag 同時備好 patch（v4.x.y+1）commit |
| 任一 ❌ | **必須回到 SPEC 階段**重新評估，不可 ship |

### 觸發點

由人類在 release runbook 第 N 步觸發（不是 AI 自動觸發 — 避免 reviewer 成為被 review 對象）。

---

## 後果（Consequences）

### 正面

- v4.1.0 GA → v4.1.1 review-fix 的 1 day 修補循環不再發生
- SPEC Done When 真的有測試 cover 才能勾，不能 AI 自評
- Documentation drift（runbook、profile、telemetry doc）在 GA 前抓到
- v3.7 / 廢止機制的殘留引用有制度化的清理檢查點

### 負面

- 每次 minor release 增加 1 個 reviewer agent invocation（成本：1 個 Sonnet/Opus 對話約 5-15 分鐘）
- Release runbook 須增加 review 步驟 + ⚠️ 處理流程
- 可能產生過度挑剔的 reviewer，需要校正「⚠️ 需修正」vs「reviewer 多慮了」的 calibration

### 對既有流程的影響

- `docs/runbooks/` 須新增 `release-runbook.md` 描述 GA 流程含 review gate
- `make` target：考慮加 `make release-prereview` 自動 spawn reviewer agent（v4.2 評估）
- SPEC Template 維持不變，但 Done When 勾選後須在 commit message 標明「測試覆蓋 IDs」

---

## 落實時程

| 階段 | 項目 | 排程 |
|------|------|------|
| ADR 接受 | 人類 review 本 ADR 並改 Accepted | TBD（人類決定） |
| Release runbook | `docs/runbooks/release-runbook.md` 含 review gate 步驟 | v4.2 開工前 |
| 第一次套用 | v4.2.0 GA 前必跑 holistic review | v4.2.0 release time |
| 評估有效性 | v4.2.0 ship 後是否還有 review-fix patch | v4.2.0 + 7 days |

---

## 關聯文件

- 觸發事件 commit：`7fc9d30`（v4.1.0 GA）→ `7259662`（v4.1.1 review-fix）
- v4.1.1 CHANGELOG entry：說明 4 個真實問題 + Done When 虛報
- D-008（v4-decision-log）：Reality Checker 三層獨立性原則 — 本 ADR 是其在 release process 層面的具體應用
- ADR-002：Iron Rules — 鐵則 review 屬 holistic review 的 L2 層
- SPEC-004：v4.1.0 工作對象，本 ADR 由其落差催生

---

## 變更歷史

- 2026-05-10：初稿，狀態 Draft，等待人類 review
