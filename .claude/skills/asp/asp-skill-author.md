---
name: asp-skill-author
description: |
  Authoring guide for ASP-style skills. Teaches how to write a new asp-* skill that
  passes the machine-checked skill lint (tests/test_skill_lint.sh, ADR-023): frontmatter
  schema, required sections, bilingual triggers, Red Flags, verification, router registration.
  Use when creating a new ASP skill, restructuring an existing skill, or before submitting
  a skill to the plugin marketplace (ADR-021).
  Triggers: write skill, author skill, new skill, skill lint, skill frontmatter, skill schema,
  asp-skill-author, 寫 skill, 新增 skill, 撰寫技能, 技能撰寫, skill 規範, skill 寫作,
  skill 品質, 過 lint, skill 必備段, 怎麼寫 skill.
---

# ASP Skill Author — 怎麼寫一個過 lint 的 ASP skill

> meta-skill（ADR-023 ①）。把「怎麼寫好一個 ASP skill」的判斷型內容教給你；可機械驗的部分由 `tests/test_skill_lint.sh` 把關。兩者一一對應：凡 lint 能驗的，本 skill 列為硬規則；lint 驗不了的（Battle-tested），誠實標為人審。

## 適用場景

- 新增一個 `asp-*` skill（最常見）。
- 重構既有 skill 的結構（補必備段、收斂標題寫法）。
- 送 skill 進 plugin marketplace 前的前置把關（ADR-021：plugin 要求 frontmatter 規範）。
- 不適用：純內容/散文文件（非可路由的能力單元）、`docs/` 報告。

## 工作流

### Step 1：frontmatter schema（R1 + R2，硬擋）

```yaml
---
name: asp-<kebab-case>          # R1：^[a-z0-9-]+$，asp 命名空間須 asp- 前綴
description: |                   # R2：block scalar、第三人稱、含 Triggers:/Use when
  <一句用途，第三人稱（禁以「我」/「I 」起手）>
  Use when <觸發情境>; ...
  Triggers: <英文詞>, <繁中詞>, ...   # 雙語（R3 advisory，CLAUDE.md 語言鐵則）
---
```

- `name` = 檔名（去 `.md`）。`description` 第三人稱描述「做什麼 + 何時用」。
- **與上游 CSO 的張力（ADR-023 §7.3 已裁決）**：ASP 採寬鬆版——description **可**摘要 workflow（既有 skill 慣例，如「Executes 10 ordered checks」），lint 不擋。

### Step 2：必備段（R4 核心三段 + R4b 步驟段）

每個內容 skill（router 除外）須含這四類段落（標題用同義表任一變體即可，見下）：

| 必備段 | 同義標題（任一） | lint |
|--------|----------------|------|
| 適用場景 | `## 適用場景` / `使用情境` / `When to Invoke` / `核心原則` / `前置…` | R4 |
| 工作流/步驟 | `## 步驟` / `## Step N` / `## 工作流` / `## Phase` / `情境` / `維度` / G1… | R4b |
| Verification | `## Verification` / `驗證` / `判定` / `結論` / `Calibration` / `輸出` | R4 |
| 下一步 | `## 下一步` / `Next Steps` / `參考` / `搭配` / `相關檔案` | R4 |

> **provenance**：「適用場景/下一步」是 ASP 既有慣例（非 addyosmani 原始四標準）；本 meta-skill 把它們列為必備是 ASP 的設計選擇（ADR-023）。
> 若你的標題用了表外的新變體，**請補進 `tests/test_skill_lint.sh` 的同義表**（POC §2 已證實「同義表過時 → 假陰性」是真技術債，例：曾漏抓 asp-audit 的「維度」）。

### Step 3：觸發詞（R3 advisory，雙語）

- 動詞優先、症狀導向（描述「問題」不描述工具特定症狀）。
- **中英雙語**（繁中對照，CLAUDE.md 鐵則）；涵蓋同義詞、錯誤訊息、工具名。
- 好例：`commit, pre-commit, 提交前, 準備提交`；壞例：只有 `ship`（覆蓋不足、缺中文）。

### Step 4：Red Flags（R5 advisory，discipline 型必備）

- discipline/強制力型 skill（會被 AI 找藉口繞過的）須附「藉口×反駁」表，格式沿用 `asp-reality-check` / `asp-plan` 的 `| 藉口 | 反駁 |` 兩欄。
- **ADR-020 反諷（必讀）**：別把 Red Flags 當成「靠 in-context 維持」的護欄——skill 本體 load 後**仍是 in-context，長對話壓縮會蒸發**。寫進 skill 本體只能**降低（非消除）**蒸發，**非 hook 級強制**；真正的硬兜底走 hook（L1.5 ship-gate）。所以 Red Flags 是輔助，不是強制力本身。

### Step 5：Verification（R4 的一部分，二元 exit criteria）

- 對應 addyosmani「Verifiable」：每個 skill 須有**二元可測**的完成判準（沿用 ASP「Done When 須二元可測」）。
- 避免「看起來對」；要可被外部信號確認（測試 exit code / gate PASS / reviewer sign-off）。

### Step 6：註冊回 SKILL.md router + 同步

1. 在 `.claude/skills/asp/SKILL.md`（source copy）的「子 Skill 路由表」新增一列（用戶意圖 / 觸發詞 / 載入的 Skill）。
2. 視情況在「執行後建議下一步」表補一列（router 原則：只建議不執行）。
3. `bash ~/.claude/scripts/asp-sync.sh` 同步到 active `~/.claude/skills/asp/`（**asp-sync 不自我更新**，改 asp-sync 本身須另跑 install）。

### Step 7：跑 lint 自驗（吃自己的狗糧）

```bash
bash tests/test_skill_lint.sh    # 你的新 skill 也會被掃；R1/R2 必過、R4/R4b 勿留 advisory
```

## lint 規則 ↔ addyosmani 四標準（機械判定對照）

| 四標準 | 本 skill 教（判斷型） | lint 機械驗 | 分級 |
|--------|---------------------|------------|------|
| Specific | Step N 編號步驟、每步可執行 | R1 name / R2 desc / R4b 步驟段存在 | 硬擋 |
| Verifiable | 二元 exit criteria | R4 Verification 段存在 | 硬擋(repo advisory 過渡) |
| Minimal | 100 行才拆支援檔、token 紀律 | R6 行數閾值 | advisory |
| Battle-tested | 「先看 AI 無 skill 時怎麼失敗再寫」 | **無法靜態驗 → 人審** | 人審（誠實標註，不假裝機械化） |

## Red Flags（AI 寫 skill 時的藉口 × 反駁）

| 藉口 | 反駁 |
|------|------|
| 「這 skill 很小，frontmatter 隨便寫」 | R1/R2 是硬擋；缺 name/description/Triggers 直接 exit 1。 |
| 「步驟我寫成一段散文就好」 | 散文撞 ADR-020（壓縮蒸發）；用編號步驟 + 二元判定。 |
| 「Verification 之後再補」 | 「之後」不存在；無 exit criteria 的 skill 無法被驗收。 |
| 「Red Flags 表放對話裡提醒就好」 | in-context 會蒸發；Red Flags 要寫進 skill 本體固定段。 |
| 「meta-skill 自己不用過 lint 吧」 | 吃自己的狗糧——本 skill 亦受 R1–R6 掃描，違反 Minimal 就拆。 |

## Verification

- **二元判準**：`bash tests/test_skill_lint.sh` → `exit 0`，且新 skill 在 repo 審計區**無 R1/R2 fail、無 R4/R4b advisory**（R6 行數除非 mega-skill）。
- 新 skill 已登記於 `SKILL.md` 路由表（grep 得到該列）。
- R7 Battle-tested 由人類（`asp:review-work` 或 PR review）確認，非本 lint。

## 下一步

- 寫完 → `bash tests/test_skill_lint.sh` 自驗 → 過 → `/asp-ship` 提交。
- 若新標題變體未被同義表涵蓋 → 補 `tests/test_skill_lint.sh` 同義表（連同新 skill 一起 commit）。
- 相關：ADR-023（本 skill 依據）、ADR-021（marketplace 前置把關）、ADR-020（散文蒸發反諷）、`asp-plan`（規劃新功能時的上游）。
