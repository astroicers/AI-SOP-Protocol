---
name: asp-context
description: |
  管理專案 CONTEXT.md（領域詞彙表）的建立、更新與術語一致性審查。
  Triggers: context, 詞彙, vocabulary, 術語, domain, grill-with-docs,
  context 不存在, 建立 context, 更新詞彙, term check, 術語衝突
---

# asp-context — 領域詞彙表管理

## 適用場景

1. **初始化**：專案尚無 `CONTEXT.md`，需從現有 ADR/SPEC/代碼建立詞彙表
2. **更新**：新術語出現（新 ADR、新 SPEC、新模組），需加入詞彙表
3. **術語審查**：PRD/SPEC/ADR 中出現的術語與現有 CONTEXT.md 衝突或未收錄

---

## Mode A：初始化（CONTEXT.md 不存在）

### Step 1：掃描現有知識來源

```bash
make adr-list        # 列出所有 ADR 及狀態
ls docs/specs/       # 列出所有 SPEC
```

閱讀每份 Accepted ADR 的 Context 段落，提取關鍵名詞。
閱讀每份 SPEC 的 Goal 與 Side Effects 段落，提取領域術語。

### Step 2：識別術語候選

對每個候選術語，判斷：
- 是否在多份文件重複出現？（出現 ≥2 次 → 應收錄）
- 是否有模糊的同義詞？（有 → 必須收錄，明確禁用同義詞）
- 是否有縮寫？（有 → 收錄縮寫對照）

### Step 3：向使用者確認術語表草稿

輸出格式：
```
以下術語準備加入 CONTEXT.md：

| 術語 | 定義 | 避免使用 | 來源 |
|------|------|---------|------|
| ... | ... | ... | ADR-001 |

確認後寫入？
```

**STOP：等待使用者確認，不可自動寫入。**

### Step 4：寫入 CONTEXT.md

複製 `.asp/templates/CONTEXT_Template.md` 到 `CONTEXT.md`，填入確認的術語。

```bash
cp .asp/templates/CONTEXT_Template.md ./CONTEXT.md
```

---

## Mode B：更新（CONTEXT.md 已存在）

### Step 1：讀取觸發術語

從使用者輸入或當前 ADR/SPEC 中識別需要新增/修改的術語。

### Step 2：與現有 CONTEXT.md 比對

```bash
cat CONTEXT.md
```

檢查：
- 術語是否已存在？（存在 → 提示使用者是否要更新定義）
- 是否與現有術語衝突？（衝突 → 明確指出衝突點）
- 是否有遺漏的關聯術語？

### Step 3：向使用者確認變更

輸出格式：
```
CONTEXT.md 變更草稿：

新增：
- [術語]：[定義]

修改：
- [術語]：[舊定義] → [新定義]（原因：...）

確認後寫入？
```

**STOP：等待使用者確認。**

### Step 4：Edit CONTEXT.md

在對應的 section 加入或修改術語條目。更新文件頂端的「最後更新」日期。

---

## Mode C：術語一致性審查

當 ASP 工具（asp-plan、asp-gate、asp-review）偵測到術語疑慮時觸發。

### Step 1：讀取 CONTEXT.md 詞彙表

### Step 2：掃描目標文件

```bash
# 掃描 ADR 或 SPEC 中的術語
grep -i "[suspected_term]" docs/adr/*.md docs/specs/*.md
```

### Step 3：輸出術語衝突報告

```
術語審查結果：

⚠️  衝突：文件使用「[使用的詞]」，CONTEXT.md 定義為「[正確詞]」
    出現位置：ADR-002 line 14、SPEC-003 line 8
    建議：將文件中的詞統一改為「[正確詞]」

✅  已收錄術語：[列表]
❓  未收錄術語：[列表]（建議透過 Mode B 更新 CONTEXT.md）
```

---

## 與其他 Skills 的協作

| 觸發點 | 行為 |
|--------|------|
| `asp-plan` 寫 SPEC 前 | 建議先確認術語是否在 CONTEXT.md（Mode C） |
| `asp-gate G2` SPEC 審查 | 自動執行術語一致性檢查（Mode C） |
| `asp-review` 代碼審查 | 若發現 ADR 術語不一致，觸發 Mode C |
| 新術語在 ADR 出現 | 提示使用者執行 Mode B |

---

## Common Rationalizations

| 藉口 | 反駁 |
|------|------|
| 「CONTEXT.md 太小的專案不需要」 | 有 2+ ADR 的專案就值得建立。成本是一次性的，收益是每次 session。 |
| 「術語大家都懂，不需要寫下來」 | AI 每次 session 重新開始，沒有共同記憶。不寫下來就是每次重新解釋。 |
| 「等術語穩定再建立」 | CONTEXT.md 是 living document，隨 ADR 演進。沒有「穩定」的時機。 |
| 「AI 可以從 ADR 自己理解術語」 | AI 必須閱讀所有 ADR 才能理解術語，成本比讀一份 CONTEXT.md 高很多。 |