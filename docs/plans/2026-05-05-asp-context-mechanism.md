# ASP CONTEXT.md Mechanism Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 建立 ASP 的 CONTEXT.md domain vocabulary 機制，讓每次 session 開始時 AI 自動具備專案的領域語言共識，消除每次重新建立語境的成本。

**Architecture:** 新增 `asp-context` skill 處理 CONTEXT.md 的建立與維護；在 `global_core.md` SessionStart 加入 CONTEXT.md 自動讀取行為；在 `asp-plan` 與 `asp-gate` 加入 CONTEXT.md 術語一致性檢查；更新 README 反映新能力。這是單一連貫功能，不拆 feature branch。

**Tech Stack:** Markdown (SKILL.md format)、Bash（Makefile targets）、YAML（profile hooks）

---

> **Status: COMPLETED — 2026-05-09**
> Core artifacts delivered. No ADR-005 created (context mechanism documented in CLAUDE.md + SKILL.md instead). session-audit.sh integration deferred to v4.1.
>
> | Artifact | Status |
> |----------|--------|
> | `CONTEXT.md` (root vocabulary file) | ✅ |
> | `.claude/skills/asp/asp-context.md` skill | ✅ |
> | `SKILL.md` routing entry for `asp-context` | ✅ |
> | `asp-gate G2` terminology consistency check | ✅ |
> | `session-audit.sh` CONTEXT.md auto-read check | ❌ deferred to v4.1 |
> | `ADR-005-context-mechanism.md` | ❌ deferred — documented in SKILL.md routing instead |

## Task 1：建立 CONTEXT.md template

**Files:**
- Create: `.asp/templates/CONTEXT_Template.md`

**Step 1：寫 CONTEXT_Template.md**

```markdown
# CONTEXT.md — 專案領域詞彙表

> 由 `/asp-context` skill 維護。所有 ADR、SPEC、commit message 使用的術語必須與此表一致。
> 最後更新：YYYY-MM-DD

## 核心概念

<!-- 格式：
### 術語名稱
**定義：** 一句話定義
**避免使用：** [同義詞1, 同義詞2]（說明為何不用）
**相關 ADR：** ADR-XXX（可選）
-->

## 系統元件

## 流程與狀態

## 外部依賴

## 縮寫對照
```

**Step 2：確認 template 寫入正確**
```bash
ls .asp/templates/CONTEXT_Template.md
```
Expected: 檔案存在

**Step 3：Commit**
```bash
git add .asp/templates/CONTEXT_Template.md
git commit -m "feat(context): add CONTEXT_Template.md for domain vocabulary"
```

---

## Task 2：建立 asp-context skill

**Files:**
- Create: `.claude/skills/asp/asp-context.md`

**Step 1：寫 asp-context.md**

```markdown
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
```

**Step 2：確認 skill 寫入正確**
```bash
head -5 .claude/skills/asp/asp-context.md
```
Expected: 顯示 YAML front matter

**Step 3：Commit**
```bash
git add .claude/skills/asp/asp-context.md
git commit -m "feat(context): add asp-context skill for domain vocabulary management"
```

---

## Task 3：在 global_core.md 加入 CONTEXT.md 自動讀取行為

**Files:**
- Modify: `.asp/profiles/global_core.md`（在 SessionStart 行為區塊加入）

**Step 1：讀取 global_core.md 前 120 行，找到合適插入點**
```bash
grep -n "SessionStart\|session\|啟動\|讀取\|預設行為" .asp/profiles/global_core.md | head -20
```

**Step 2：在「預設行為」或「session 啟動」段落加入以下內容**

找到適當位置（SessionStart 相關行為描述後），插入：

```markdown
### CONTEXT.md 自動讀取（Session 啟動）

若 `CONTEXT.md` 存在於 repo root，**必須在本次 session 第一次動手前讀取**：

```bash
cat CONTEXT.md
```

讀取後：
- 所有後續輸出（ADR、SPEC、commit message、PR description）的術語必須與 CONTEXT.md 一致
- 若輸出中使用了「避免使用」欄的同義詞，視為術語違規，須修正
- 若需要的術語未收錄，標記為 ❓ 並建議使用者執行 `/asp-context`

若 `CONTEXT.md` **不存在**：靜默略過，不提示使用者創建（lazy creation 原則）。
```

**Step 3：確認插入正確**
```bash
grep -n "CONTEXT.md 自動讀取" .asp/profiles/global_core.md
```
Expected: 顯示行號

**Step 4：Commit**
```bash
git add .asp/profiles/global_core.md
git commit -m "feat(context): global_core reads CONTEXT.md at session start"
```

---

## Task 4：在 asp-plan 加入術語一致性檢查

**Files:**
- Modify: `.claude/skills/asp/asp-plan.md`

**Step 1：讀取 asp-plan.md，找 Step 4（SPEC 撰寫）的位置**
```bash
grep -n "Step 4\|SPEC\|術語\|Goal\|Done When" .claude/skills/asp/asp-plan.md | head -15
```

**Step 2：在 Step 4（建立 SPEC）的開頭加入術語預檢**

在「建立 SPEC」步驟的 **最前面** 插入：

```markdown
**術語預檢（若 CONTEXT.md 存在）：**

撰寫 SPEC 前，確認以下術語已在 CONTEXT.md 收錄：
- SPEC Goal 中使用的核心名詞
- 輸入/輸出的資料結構名稱
- Side Effects 涉及的系統元件名稱

若術語未收錄 → 提示使用者執行 `/asp-context`（Mode B）補充後再繼續。
若 CONTEXT.md 不存在 → 略過此步。
```

**Step 3：確認插入**
```bash
grep -n "術語預檢" .claude/skills/asp/asp-plan.md
```

**Step 4：Commit**
```bash
git add .claude/skills/asp/asp-plan.md
git commit -m "feat(context): asp-plan checks CONTEXT.md terms before SPEC writing"
```

---

## Task 5：在 asp-gate G2 加入術語審查

**Files:**
- Modify: `.claude/skills/asp/asp-gate.md`

**Step 1：讀取 asp-gate.md，找 G2（SPEC 審查）的位置**
```bash
grep -n "G2\|SPEC\|7 field\|七欄" .claude/skills/asp/asp-gate.md | head -15
```

**Step 2：在 G2 checklist 末尾加入術語一致性項目**

在 G2 的 checklist 項目後（PASS/FAIL 判斷前）加入：

```markdown
- [ ] **術語一致性**（若 CONTEXT.md 存在）：SPEC 中的核心術語與 CONTEXT.md 一致，無使用「避免使用」同義詞
  - FAIL 條件：使用了 CONTEXT.md 明確標記「避免使用」的詞
  - SKIP 條件：CONTEXT.md 不存在
```

**Step 3：確認插入**
```bash
grep -n "術語一致性" .claude/skills/asp/asp-gate.md
```

**Step 4：Commit**
```bash
git add .claude/skills/asp/asp-gate.md
git commit -m "feat(context): asp-gate G2 checks CONTEXT.md term consistency"
```

---

## Task 6：在 asp-ship SKILL.md router 加入 asp-context 路由

**Files:**
- Modify: `.claude/skills/asp/SKILL.md`

**Step 1：讀取 SKILL.md，找到路由表**
```bash
grep -n "context\|詞彙\|vocabulary\|v4.0 新增" .claude/skills/asp/SKILL.md | head -10
```

**Step 2：在「v4.0 新增 Skill」表格加入 asp-context 路由**

在 v4.0 新增 Skill 表格中加入一行：

```markdown
| 領域詞彙管理 / CONTEXT.md 建立與更新 | context, 詞彙, vocabulary, 術語, domain, grill-with-docs, context 不存在, 術語衝突 | asp-context |
```

**Step 3：在「執行後建議下一步」表格加入 asp-context 條目**

```markdown
| `asp-context`（初始化完成） | 👉 下一步：執行 `asp-plan` 新功能時術語已備妥；或在 `asp-gate G2` 術語審查 |
| `asp-context`（Mode C 發現衝突） | 👉 下一步：修正 ADR/SPEC 中的術語 → 重跑 `/asp-gate G2` |
```

**Step 4：Commit**
```bash
git add .claude/skills/asp/SKILL.md
git commit -m "feat(context): register asp-context in skill router"
```

---

## Task 7：建立 ASP 自身的 CONTEXT.md

**Files:**
- Create: `CONTEXT.md`

**Step 1：掃描現有 ADR 提取術語**
```bash
make adr-list
grep -h "##\|###\|^- \*\*" docs/adr/*.md | head -50
```

**Step 2：寫入 ASP 自身的 CONTEXT.md**

根據掃描結果填寫，核心術語包括：
- ASP（AI-SOP-Protocol）
- Profile、Skill、Gate（G1-G6）
- SPEC、ADR
- HITL（Human-in-the-Loop）
- Session Briefing
- Bypass Log
- Reality Checker
- Smuggling（測試竄改）
- Maturity Level（L0-L5）
- Autopilot
- Pipeline

**Step 3：確認 CONTEXT.md 存在**
```bash
wc -l CONTEXT.md
```
Expected: 行數 > 30

**Step 4：Commit**
```bash
git add CONTEXT.md
git commit -m "feat(context): create ASP self-referential CONTEXT.md with framework glossary"
```

---

## Task 8：更新 CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

**Step 1：在 `## [Unreleased]` 區塊加入 Context 機制條目**

在 CHANGELOG.md 的 `## [Unreleased]` 段落的 `### Added` 下加入：

```markdown
- **CONTEXT.md Domain Vocabulary 機制**：新增 `asp-context` skill（Mode A 初始化 / Mode B 更新 / Mode C 術語審查）；`global_core.md` session 啟動時自動讀取 `CONTEXT.md`；`asp-plan` SPEC 撰寫前術語預檢；`asp-gate G2` 加入術語一致性審查；新增 `.asp/templates/CONTEXT_Template.md`；建立 ASP 框架自身的 `CONTEXT.md` 詞彙表
```

**Step 2：確認 CHANGELOG 更新**
```bash
grep -n "CONTEXT.md Domain" CHANGELOG.md
```

**Step 3：Commit**
```bash
git add CHANGELOG.md
git commit -m "docs(changelog): record CONTEXT.md mechanism addition"
```

---

## Task 9：更新 README.md

**Files:**
- Modify: `README.md`

**Step 1：讀取 README.md 現有「核心功能」區塊**
```bash
grep -n "核心功能\|Core\|##" README.md | head -20
```

**Step 2：在核心功能清單加入 CONTEXT.md 機制**

在現有功能列表中加入（版本標記 v4.1）：

```markdown
- **Domain Vocabulary 機制**（v4.1）：`CONTEXT.md` 詞彙表 + `asp-context` skill — session 啟動自動讀取術語、SPEC 撰寫前術語預檢、G2 gate 術語一致性審查，消除每次 session 重建語境的成本
```

**Step 3：確認現有「快速安裝」與「.ai_profile 設定」區塊是否需要更新**

檢查是否需要說明 CONTEXT.md 的存在：
```bash
grep -n "CONTEXT\|domain\|vocabulary" README.md
```

若「入門步驟」中未提及 CONTEXT.md，在 Quick Install 的 Step 3 後加入：

```markdown
**Step 4（選用）：建立領域詞彙表**

```bash
# 若專案已有 ADR/SPEC，可初始化詞彙表
# 開啟 Claude Code，執行：
/asp-context
```

CONTEXT.md 採 lazy creation：首次需要時再建立，不強制。
```

**Step 4：在 README 末尾或「競爭優勢」相關段落（若有）加入 CONTEXT.md 說明**

**Step 5：Commit**
```bash
git add README.md
git commit -m "docs(readme): document CONTEXT.md domain vocabulary mechanism (v4.1)"
```

---

## Task 10：驗證整合

**Step 1：確認所有新檔案存在**
```bash
ls .asp/templates/CONTEXT_Template.md \
   .claude/skills/asp/asp-context.md \
   CONTEXT.md
```
Expected: 全部存在，無 error

**Step 2：確認 skill router 有 asp-context 路由**
```bash
grep "asp-context" .claude/skills/asp/SKILL.md
```
Expected: 出現 2 次以上（路由表 + 下一步建議）

**Step 3：確認 global_core.md 有 CONTEXT.md 讀取段落**
```bash
grep "CONTEXT.md 自動讀取" .asp/profiles/global_core.md
```
Expected: 出現 1 次

**Step 4：確認 asp-plan 有術語預檢**
```bash
grep "術語預檢" .claude/skills/asp/asp-plan.md
```
Expected: 出現 1 次

**Step 5：確認 asp-gate G2 有術語一致性**
```bash
grep "術語一致性" .claude/skills/asp/asp-gate.md
```
Expected: 出現 1 次

**Step 6：確認 git log 有所有 commits**
```bash
git log --oneline -10
```
Expected: 看到 Task 1-9 的 commits

**Step 7：最終 commit（若有殘留未 commit 的變更）**
```bash
git status
# 若 clean，無需 commit
```

---

## 驗證標準

實作完成後，以下場景應可運作：

1. **新 session + CONTEXT.md 存在** → global_core 讀取 CONTEXT.md，後續術語輸出一致
2. **新 session + CONTEXT.md 不存在** → 靜默略過，無干擾
3. **執行 `/asp-context`** → skill router 路由到 asp-context.md
4. **執行 `asp-plan` 建立 SPEC** → 若 CONTEXT.md 存在，先做術語預檢
5. **執行 `/asp-gate G2`** → G2 checklist 包含術語一致性項目