---
name: asp-assumption-checkpoint
description: |
  Use before starting any non-trivial task to surface and confirm assumptions.
  Handles: pre-task assumption listing, technical choice validation, scope boundary
  confirmation, stopping for user approval before proceeding.
  Triggers: assumption, checkpoint, 假設確認, 開始前確認, pre-task check,
  assumption checkpoint, 列出假設, 確認假設, before we start, 任務前確認,
  check assumptions, 先確認一下, 先列假設.
---

# ASP Assumption Checkpoint Skill

實作任何非 trivial 任務前，先輸出假設清單，等待使用者確認後才繼續。本 skill 自包含，不依賴外部 profile。

借鑒來源：huashu-design Checkpoint #3 "Early show" — "Stop, tell user what you've done, confirm next steps. Don't proceed silently."

---

## 觸發條件

滿足任一條件即觸發：

- 任務涉及 **2+ 個模組或檔案**
- 需要新增 **ADR 或 SPEC**
- 使用者要求「設計」「規劃」「架構」任何功能
- 實作前需要選擇**技術方案或資料結構**

**豁免條件**（無需 checkpoint）：

- trivial（符合 `classify_bug_severity()` 的 trivial 標準：affected_files <= 2，changed_lines <= 10，無條件邏輯/DB/API/認證變更）
- 使用者**此次**明確說「直接做」或「不用問」（此豁免不延續至下一個任務）

---

## 輸出格式（固定格式，不可省略）

執行本 skill 時，輸出以下格式，然後停下來等待使用者確認：

```
ASSUMPTIONS（在實作前確認）

| 假設 | 依據 | 若錯誤的風險 | 驗證方式 |
|------|------|------------|---------|
| {假設內容} | {依據來源} | {若這個假設錯了會怎樣} | {如何驗證} |
| {假設內容} | {依據來源} | {若這個假設錯了會怎樣} | {如何驗證} |

技術選擇：
- {技術/方案}（選擇原因：{因為...}）

範圍邊界（明確不含）：
- 不含：{排除的範圍 1}
- 不含：{排除的範圍 2}

---

Stop Point：以上假設是否正確？確認後再繼續。
```

---

## 假設表欄位說明

| 欄位 | 說明 | 範例 |
|------|------|------|
| **假設** | 具體的假設內容（避免模糊的「假設需求清楚」） | 「用戶 ID 為 UUID 格式，非自增整數」 |
| **依據** | 這個假設來自哪裡（SPEC 哪行、使用者說的、推測的） | SPEC-042 § Inputs、使用者說的、推測 |
| **若錯誤的風險** | 假設錯了，影響範圍有多大 | 「需要重寫所有 ID 相關查詢，影響 5 個模組」 |
| **驗證方式** | 如何確認假設正確（不可寫「無法驗證」，要有具體方法） | 「查 users 表 schema」、「詢問使用者」、「看 package.json」 |

---

## 常見假設類別（填表參考）

**技術假設：**
- 使用的框架/函式庫版本
- 資料庫 schema 結構
- 認證/授權機制
- API 協定（REST / GraphQL / gRPC）

**行為假設：**
- 邊界條件的預期行為
- 錯誤處理方式
- 並發/事務處理

**範圍假設：**
- 哪些功能在本次實作範圍內
- 哪些是已有系統的行為（不需要改）
- 向下相容性要求

**資料假設：**
- 輸入資料格式和驗證規則
- 現有資料的狀態（是否需要 migration）
- 資料量級（影響演算法選擇）

---

## 等待確認

輸出假設表後，**必須停下來**。不可：

- 自動繼續實作
- 「先做這部分，其他假設應該沒問題」
- 在使用者回覆前寫任何生產代碼

**可以做的事**（等待期間）：
- 說明假設表中任何一行的詳細思考過程
- 如果使用者問「某個假設是什麼意思」，解釋清楚

---

## 使用者確認後

使用者回覆後：

1. **全部確認** → 繼續實作
2. **部分修正** → 更新假設表，再次確認修正的部分
3. **假設根本錯誤（涉及架構）** → 觸發 `asp-assumption-checkpoint` 重新列表

---

## 繞過藉口與反駁

| 藉口 | 反駁 |
|------|------|
| 「需求很清楚，不需要確認假設」 | 清楚的需求仍有實作假設（技術方案、邊界）。確認假設 ≠ 確認需求 |
| 「先做了再修比較快」 | 方向錯誤的實作要整段打掉，假設確認 30 秒 vs 重做 30 分鐘 |
| 「使用者說『直接做』」 | 僅在使用者**此次**明確說「直接做」時豁免，不延續至下一個任務 |
| 「假設很明顯，不需要寫出來」 | 明顯的假設也可能是錯的。列出才能讓使用者確認或否定 |