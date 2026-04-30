---
name: asp-fact-verify
description: |
  Use when verifying external facts before implementing features or writing specs.
  Handles: API signature verification, library version confirmation, framework usage
  validation, regulatory reference checking, external service fact-checking.
  Triggers: fact verify, 外部事實, 查證 API, 確認版本, verify fact,
  fact check, 事實查證, 版本確認, API 確認, 外部查證, check version,
  verify api, 查文件, 確認文件.
---

# ASP Fact Verify Skill

外部事實驗證閘（Fact Verification Gate）。本 skill 自包含，完整流程直接內嵌，不依賴外部 profile。

LLM 幻覺 API 簽章、函式行為是常見問題。ASP evidence-based 精神延伸至外部資料：不可引用訓練資料記憶作為「事實」。

---

## 觸發條件

任何任務涉及以下資訊時，必須先執行本 skill，不得依賴 AI 訓練資料：

- 第三方函式庫的 API 簽章、參數、回傳格式
- Framework 的最新用法（尤其 AI/ML、Web framework 更新頻繁）
- 官方文件中的預設值、deprecation 狀態、版本相容性
- 協定規範（HTTP status code 含義、JSON Schema 語法細節）
- 外部服務的存在性、定價、功能集
- 法規條文、標準規範編號

**豁免**：純內部實作（無任何外部依賴）、trivial 修改

---

## 執行程序

### Step 1：識別事實點

列出任務中涉及的所有外部事實點：

```
□ 識別所有版本號（package.json / requirements.txt / Cargo.toml 等）
□ 識別所有外部 API 呼叫點（endpoint、參數、回傳格式）
□ 識別所有第三方框架用法
□ 識別所有引用的規範或法規條文
```

### Step 2：逐點查證（優先順序由上而下）

```
1. 專案內 rag_context（若 rag: enabled）
   → 先檢查專案內是否已有鎖定版本記錄

2. context7 MCP（若可用）
   → 查詢最新的官方文件

3. WebFetch 官方文件 URL
   → 直接讀取官方來源（非第三方部落格）

4. WebSearch（多來源交叉驗證）
   → 若官方文件無法取得，用多個來源比對
```

### Step 3：5 元素校對（人事時地物）

查證時同時確認以下 5 個維度：

| 元素 | 確認內容 |
|------|---------|
| **人（Who）** | 作者 / 維護者 / 官方組織是誰 |
| **事（What）** | 函式 / API 的實際行為（不只是簽章） |
| **時（When）** | 文件日期 vs 今天日期 — 警覺版本差異 |
| **地（Where）** | 官方文件 URL（非第三方部落格或 Stack Overflow 二手資訊） |
| **物（Which）** | 版本號是否符合專案鎖定版本（package.json / requirements.txt 等） |

### Step 4：記錄到 `.asp-fact-check.md`

每次查證後，追加以下格式到 `.asp-fact-check.md`：

```markdown
| 事實點 | 聲稱值 | 驗證來源 | 驗證結果 | 日期 |
|--------|--------|---------|---------|------|
| {函式庫/API 名稱} | {聲稱的值} | {驗證來源 URL} | {結果} | {YYYY-MM-DD} |
```

驗證結果格式：
- `PASS` — 確認正確（附來源）
- `FAIL` — 確認錯誤（說明實際值）
- `UNVERIFIED` — 無法確認（需標注在 SPEC 中）

### Step 5：判決輸出

```
PASS：所有事實點均通過驗證 → 可繼續進入 ADR/SPEC 撰寫
FAIL：發現至少一個事實點錯誤 → 必須先修正，再重跑驗證
UNVERIFIED：有事實點無法確認 → 在 SPEC 中標注 [UNVERIFIED]，等待人類確認
```

---

## `.asp-fact-check.md` 記錄範例

```markdown
| 事實點 | 聲稱值 | 驗證來源 | 驗證結果 | 日期 |
|--------|--------|---------|---------|------|
| axios 版本 | 1.6.x | package.json | PASS — 確認 1.6.8 | 2026-04-30 |
| OpenAI Chat endpoint | /v1/chat/completions | 官方文件 | PASS — 確認 | 2026-04-30 |
| GDPR 第 17 條 | 被遺忘權 | EUR-Lex | UNVERIFIED — 需法務確認 | 2026-04-30 |
| Next.js App Router | 14.x 預設啟用 | nextjs.org/docs | PASS — 確認 14.2 | 2026-04-30 |
```

---

## 輸出格式（回覆使用者）

```
FACT VERIFICATION GATE — {任務名稱}

識別的事實點（{N} 個）：
1. {事實點 1}：{聲稱值}
2. {事實點 2}：{聲稱值}
...

查證結果：
1. {事實點 1}：PASS — {驗證來源} 確認為 {實際值}
2. {事實點 2}：FAIL — 實際值為 {實際值}，需修正聲稱值
3. {事實點 3}：UNVERIFIED — {原因}，已在 SPEC 中標注 [UNVERIFIED]

整體判決：{PASS / FAIL / UNVERIFIED}

已記錄至：.asp-fact-check.md
{PASS → 可繼續 / FAIL → 修正後重跑 / UNVERIFIED → 人類確認後繼續}
```

---

## 繞過藉口與反駁

| 藉口 | 反駁 |
|------|------|
| 「這個 API 很穩定，憑記憶寫就好」 | 「穩定 API」仍有 deprecated 警告、新參數、行為變更。引用記憶 = 押注沒變 |
| 「查證太慢，先寫再說」 | 寫錯再 debug 更慢。查證 30 秒 vs debug 15 分鐘 |
| 「官方文件 404，用 Stack Overflow 答案」 | SO 答案通常版本過期。先嘗試 GitHub repo 的 README 或 source code |
| 「這只是小功能，不需要查證」 | 事實點的重要性與任務大小無關。一個錯誤的版本號可以讓整個 build 失敗 |

---

## 無法查證時的標準聲明

若無法查證，必須明確標注：

```
（根據訓練資料，可能過時，請驗證）
```

不可偽裝成事實輸出，不可省略此聲明。