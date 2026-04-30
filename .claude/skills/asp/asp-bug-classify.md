---
name: asp-bug-classify
description: |
  Use when classifying bug severity to determine the appropriate fix workflow.
  Handles: trivial vs non-trivial determination, bug type labeling, workflow
  recommendations (direct fix vs SPEC-first), quantitative classification criteria.
  Triggers: bug classify, bug severity, 分類 bug, 這是 trivial 嗎, 這個 bug 要 SPEC 嗎,
  classify bug, bug classification, trivial or not, 這個 bug 嚴不嚴重, bug 等級,
  需要寫 SPEC 嗎, need spec for this bug, bug type.
---

# ASP Bug Classify Skill

Bug 嚴重度分類器。本 skill 自包含，判斷標準直接內嵌，不依賴外部 profile。

---

## Trivial vs Non-Trivial 判斷函數

以下為完整的量化判斷標準，**任一客觀指標命中即為 non-trivial，不可覆蓋**：

```
FUNCTION classify_bug_severity(bug):
  // ─── 客觀指標（任一命中 → non-trivial，不可覆蓋）───

  IF bug.affected_files > 2:
    RETURN "non-trivial"
    // 理由：跨模組影響，改動範圍超出單一修復點

  IF bug.changed_lines > 10:
    RETURN "non-trivial"
    // 理由：行數多代表邏輯複雜，trivial 修復通常是 1-3 行

  IF bug.modifies_conditional_logic:
    RETURN "non-trivial"
    // 觸發：if / switch / match / ternary 邏輯變更
    // 理由：條件邏輯變更可能引入新的邊界條件

  IF bug.modifies_db_query:
    RETURN "non-trivial"
    // 觸發：SQL / ORM / NoSQL 查詢變更
    // 理由：查詢變更影響資料完整性，需要迴歸防護

  IF bug.modifies_api_response:
    RETURN "non-trivial"
    // 觸發：API 回傳格式、狀態碼、欄位名稱變更
    // 理由：API 合約變更影響所有消費者

  IF bug.touches_auth_or_permission:
    RETURN "non-trivial"
    // 觸發：認證、授權、session、JWT、RBAC 邏輯
    // 理由：安全相關，任何變更需要完整驗證

  // ─── 以上全部未命中 → trivial（可直接修復）───
  RETURN "trivial"
  // trivial 範例：typo、配置值、import 排序、註解修正
```

**不確定時視為 non-trivial**（保守原則）。

---

## Bug 類型標籤

Commit message 中必須標記分類：

| 標籤 | 說明 | 範例觸發條件 |
|------|------|------------|
| `[bug:logic]` | 邏輯錯誤（條件判斷、演算法錯誤） | 計算結果錯誤、流程順序錯誤 |
| `[bug:boundary]` | 邊界條件未處理（off-by-one、null、empty） | 空陣列、最大值、零值未處理 |
| `[bug:concurrency]` | 並發問題（race condition、deadlock） | 多線程共享狀態 |
| `[bug:integration]` | 整合/介面不匹配（API 合約、版本差異） | 第三方 API 回傳格式變更 |
| `[bug:config]` | 配置錯誤（環境變數、預設值、設定檔） | 錯誤的 timeout 值、缺少必填設定 |
| `[bug:security]` | 安全相關（注入、越權、敏感資訊洩漏） | SQL injection、XSS、未授權存取 |

---

## 輸出格式（執行此 skill 時）

```
BUG CLASSIFY — {bug 描述}

判斷指標：
□ affected_files > 2：{N 個檔案} → {命中/未命中}
□ changed_lines > 10：{預估 N 行} → {命中/未命中}
□ modifies_conditional_logic：{是/否} → {命中/未命中}
□ modifies_db_query：{是/否} → {命中/未命中}
□ modifies_api_response：{是/否} → {命中/未命中}
□ touches_auth_or_permission：{是/否} → {命中/未命中}

判決：{TRIVIAL / NON-TRIVIAL}

Bug 類型標籤：{[bug:logic] | [bug:boundary] | [bug:concurrency] | [bug:integration] | [bug:config] | [bug:security]}

建議工作流：
```

---

## 建議工作流（依判決結果）

### Trivial → 直接修復

```
1. 直接修復（不需要 SPEC）
2. 說明豁免理由（在 commit message 中）
3. 執行快速驗證（make test-filter 對應模組）
4. 全專案 grep 掃描相似位置（無豁免）
   格式：`grep -r "pattern" . --include="*.ext"` → {N 處}
5. Commit message 格式：
   fix({module}): {描述} [bug:{type}]
   根因：{function} 未處理 {edge_case}，導致 {symptom}
   trivial 豁免：{符合哪個 trivial 條件}
```

### Non-Trivial → SPEC-First 工作流

```
1. 建立 Bug SPEC：
   make spec-new TITLE="BUG-{描述}"
   
2. SPEC 必須包含：
   - Goal：修復 {symptom}，防止重演
   - Background：根因分析（{module} 的 {function} 未處理 {edge_case}）
   - 重現步驟（作為 Edge Cases 的一部分）
   - Done-When：包含「重現測試從 FAIL 變 PASS」

3. 先寫重現測試（TDD）：
   - 撰寫能重現此 Bug 的測試
   - 修復前：此測試必須 FAIL
   - 修復後：此測試必須 PASS
   - 此測試永久保留（regression guard）

4. 實作修復

5. 全專案掃描相似位置（`make test` 全量）

6. Postmortem 觸發評估：
   - Bug 影響 production → 必須建立 Postmortem
   - Bug 修復重試 > 3 次 → 必須建立 Postmortem
   - 資料遺失或不一致 → 必須建立 Postmortem
   - 需要 rollback → 必須建立 Postmortem

7. Commit message 格式：
   fix({module}): {描述} [bug:{type}]
   根因：{module} 的 {function} 未處理 {edge_case}，導致 {symptom}
   SPEC: SPEC-{NNN}
```

---

## 決策範例

| Bug 描述 | Trivial/Non-trivial | 類型標籤 | 理由 |
|----------|---------------------|---------|------|
| 修改 README typo | Trivial | 無需標籤 | 不涉及程式碼 |
| 修正 timeout 預設值 | Trivial | `[bug:config]` | 1 行修改，無邏輯變更 |
| 修正錯誤的 error message | Trivial | `[bug:logic]` | 文字變更，不影響邏輯 |
| 修正 null 指標錯誤（1 個檔案，5 行） | Non-trivial | `[bug:boundary]` | modifies_conditional_logic |
| API 回傳缺少欄位 | Non-trivial | `[bug:integration]` | modifies_api_response |
| SQL 查詢少了 WHERE 條件 | Non-trivial | `[bug:logic]` | modifies_db_query |
| 認證 token 未正確失效 | Non-trivial | `[bug:security]` | touches_auth_or_permission |