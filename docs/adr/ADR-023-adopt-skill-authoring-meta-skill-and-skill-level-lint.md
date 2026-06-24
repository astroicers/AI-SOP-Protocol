# [ADR-023]: Adopt skill-authoring meta-skill and machine-checked skill-level quality lint

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-23 |
| **決策者** | ASP framework maintainers（待人類核准） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

> ⬆️ 由 `Draft` 升 `Accepted`：使用者 2026-06-24 透過 `/asp:approve-adr ADR-023` 呼叫、看完本指令摘要的決策（選項 C：`asp-skill-author` meta-skill + skill 級機械化 lint，R1–R7 標硬擋/advisory/人審）與 Verification Evidence（POC 探針 `poc-skill-lint-spike.sh` `exit 0`、baseline `PASS=11 FAIL=4`，承重假設 1/2 已驗，假設 3〔git diff per-skill 偵測〕留實作確認）後明確同意直升（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。直升不跳過實質驗證——POC 證據已齊，僅省 FIRM 中間 label。

---

## 背景（Context）

借鏡報告 `docs/research/2026-06-23-addyosmani-agent-skills-deep-borrow.md`（PR #50）結論：能從 addyosmani/agent-skills 借的，集中在 ASP 的短處——skill 的打包、可發現性、**寫作品質工具化**。報告 §4①／§6 指出**唯一主要真缺口**：

- ASP 已有 15 個 `asp-*` skill，但**沒有「怎麼寫一個 ASP 風格 skill」的 meta-skill**，也**沒有任何 skill 級 lint**（task 級 G1–G6 gate 只驗 ADR/SPEC，不驗 skill 寫法）。
- 後果：既有 skill 風格不一（標題寫法多變、必備段缺漏：不足半數的 skill 才有 Common Rationalizations 表），且無機械門檻可防未來漂移。
- 新 skill 的品質目前**全靠人工 review**——無 reviewer 時即退化（報告 §3）。

addyosmani 的 CONTRIBUTING 把 skill 品質定為四標準（一手查證見 `.asp-fact-check.md` FC-005）：**Specific**（可執行步驟，非模糊建議）／**Verifiable**（清楚 exit criteria + 證據要求）／**Battle-tested**（真實 workflow，非理論）／**Minimal**（只放需要的內容）。這四標準在 addyosmani 是**人工** review 標準；ASP 要借的不是「概念」（抄概念 = 與既有層重疊，違 ADR-010），而是把可機械化的那一半翻成 **exit-code 級 lint**，無法機械化的（Battle-tested）誠實標註為人審。

**ADR-020 反諷必須內化**：不可照抄 addyosmani 的「in-context 反合理化表」當護欄——in-context 內容在長對話壓縮後會蒸發（ADR-020 已知失效模式）。ASP 的對策是把 Red Flags 寫進 **skill 本體的固定段**（每次 load skill 都帶）；惟須誠實：skill 本體 load 後**仍是 in-context**，比散在對話的內容更易被重新 load，但**仍非 hook 級強制**（見後果段，不可把它當成等同 ADR-020 hook 兜底的解方）。

**嫁接 ADR-021**（已 `Accepted`，plugin marketplace 為主要分發通道）：plugin 遷移後 skill 一律 namespaced，plugin 本就要求 frontmatter 規範。本 meta-skill 的 frontmatter 規範 + lint 正好是 plugin 遷移的**前置把關**（報告 §6：「最高槓桿單一動作」且「天然嫁接 ADR-021」）。落點 **#39 路線圖 P1**（②③④⑤ 的排序見 `docs/research/2026-06-23-addyosmani-borrow-fix-roadmap.md`，不入本 ADR 正文以免綁定後續編號決策）。

> **必備段清單範圍註記**：本 ADR 的「必備段」採 task ① 定義的五段（適用場景 / 步驟 / Red Flags / Verification / 下一步）。報告 §4① 原文只列三段（步驟 / Red Flags / Verification）；「適用場景 / 下一步」是 ASP skill 既有慣例的追加（A3 盤點：多數既有 skill 已用「適用場景」與「下一步/搭配」段），非報告原文主張，於此明標以免誤讀。

---

## 評估選項（Options Considered）

### 選項 A：只做 meta-skill（教 AI 怎麼寫 skill，不做機械 lint）
- **優點**：成本最低（1 個 doc-only skill）；立即提供 skill 撰寫指引；無 CI 接線維護。
- **缺點**：純散文指南**撞 ADR-020**——壓縮後蒸發，長對話中 AI 不會持續遵守；無機械門檻 → 漂移無法偵測，退回「全靠人工 review，無 reviewer 即退化」的現況（報告 §3）。
- **風險**：治理劇場——看似有規範，實則零強制力；與「機械化版本而非散文」判準直接衝突。

### 選項 B：只做 lint（機械驗 frontmatter/必備段，不寫 meta-skill）
- **優點**：有 exit-code 強制力；防漂移。
- **缺點**：lint 只會說「你缺 X 段」，**不教「X 段該怎麼寫得好」**；面對 fail 不知如何修正，易產生「為過 lint 硬塞空段」的形式合規；四標準中判斷型的一半（Specific 的「步驟可執行」、Verifiable 的「exit criteria 是否二元可測」）無對應教學載體。
- **風險**：lint 與「好 skill 長什麼樣」脫鉤 → 機械門檻淪為填空遊戲，品質不升反降。

### 選項 C：meta-skill + 機械化 lint 並行（採用）
- **優點**：meta-skill 教判斷型內容（怎麼寫好），lint 機械驗可驗的那一半（存在性 + schema）；**兩者一一對應**——凡 lint 能驗的，meta-skill 必明列為硬規則；凡 lint 驗不了的（Battle-tested），meta-skill 誠實標為人審項（不假裝機械化，呼應報告 §3 反諷）。四標準完整覆蓋，無治理劇場。
- **缺點**：需同時維護 1 meta-skill + 1 lint script，且需維護「同義標題對照表」（A3：標題有變體，否則假陰升高）。
- **風險**：若 lint 一上線就對既有 15 skill 硬 gate → 多數會 fail（A3 baseline，POC 實測為準），阻塞落地。**緩解**：advisory/blocking 分界（見決策段）。

---

## ADR-010 摩擦評估（自證：meta-skill + lint 不是「用更多治理治治理過載」）

本 ADR 新增 meta-skill 與 lint 機制，必須正面通過 ADR-010 摩擦評估，否則與「治理過載是病」自相矛盾。

| 鏡頭 | 評估 |
|------|------|
| **新增元件清單** | (1) `asp-skill-author` meta-skill（`.claude/skills/asp/`）＝**複用既有 skill 載入機制 + SKILL.md router 註冊**，無新載入層；(2) skill 級品質 lint（建議 `tests/test_skill_lint.sh`）＝**複用既有 `tests/*.sh` glob runner + `tests/lib/common.sh` 的 pass/fail/mk_test_dir**（A5 實證 repo 已有此 runner 慣例），**無新 orchestration 層、無新 Makefile target 架構**。helper 若新增須放 `tests/lib/` 子目錄（避開 runner glob，沿用既有約定）。 |
| **與既有層重疊？** | **不重疊**——A5 實證 repo 目前**無任何 skill 級 lint**（grep scripts/、Makefile 皆無 frontmatter/lint target），只有 task 級 G1–G6（驗 ADR/SPEC，**不驗 skill 寫法**）。與上游 `write-a-skill`/`writing-skills` 不重疊：那些教「通用 skill」，本 meta-skill 收斂「**ASP 方言**」（asp- 前綴、中英雙語 Triggers、ASP 必備段、router 註冊）。與 `asp-plan` Step 5.5「機械觸發判斷 / rationalization」**功能鄰近但不重疊**：R5 驗的是「skill **文件內**是否含 Red Flags 段」（靜態存在性），`test_asp_plan_step5_rationalization.sh` 驗的是「plan **流程**是否觸發判斷」（執行行為），作用對象不同。與 ADR-021 是**嫁接非疊層**：lint 是 plugin frontmatter 要求的前置把關，非新分發機制。對照 ADR-010 拒絕 UA 的同判準（不新建 orchestration 層）→ 本案無新層。 |
| **overhead vs 節省** | overhead ≈ (a) 1 lint test 檔（複用 runner，數十行）；(b) **meta-skill 本身的行數**——教五個必備段 + 四標準↔lint 對應表 + 「先看 AI 無 skill 怎麼失敗」可能偏長，**故 meta-skill 自身必須過 R6 行數 advisory，超閾值則用 progressive disclosure 拆 `references/`**（不可「用一個違反 Minimal 的 skill 去教 Minimal」）；(c) 同義標題對照表維護。節省＝15 個既有 skill 風格收斂 + 機械防未來漂移（取代人工 skill review 的存在性檢查）+ 前置把關 ADR-021 plugin frontmatter 要求。**淨值為正**——overhead 一次性且複用既有 runner，節省持續且隨 skill 數成長。 |
| **結論** | **通過**——不新建層、複用既有 runner/router、自我約束（meta-skill 吃自己的狗糧：本身納入 R1–R6 lint 掃描對象）、機械判定。**翻盤點（誠實標註，仿 ADR-022 可推導性軸降級處理）**：四標準中 Specific/Verifiable/Minimal 可機械化（降為「必備段存在性 + 行數閾值」）為硬/advisory gate；**Battle-tested 無法靜態驗 → 誠實標註為人審項**（歸 `asp:review-work` 或 PR review），**不假裝機械化**。R3 雙語 / R5 Red Flags / R6 行數降 advisory（避免既有 15 skill 大量 fail 阻塞落地）。**機械化判準（仿 ADR-022 軸降級，單一可對照語句）**：lint `exit 0` + R1/R2 既有全過 + meta-skill 自過 R6 ＝ 摩擦評估「機械化、低 overhead」成立；任一不成立則退回重議（見成功指標重評條件）。**待 POC 驗證的承重假設**見 POC 計畫（lint 可否便宜機械化、15 skill baseline 合規率、git diff per-skill 偵測可否零成本複用）。 |

---

## 決策（Decision）

採用 **選項 C**：新增 `asp-skill-author` meta-skill + skill 級品質 lint，兩者一一對應。本決策為 `Draft` 提案——**禁止對應生產代碼**（meta-skill 與 lint script 實作須等人類核准升 `Accepted`）。唯 POC 探針（spike，放 `docs/research/`、不接 Makefile/CI/tests）可在 `Draft` 階段做來 de-risk。落點 #39 路線圖 P1，嫁接 ADR-021。

### lint schema 具體檢查項（依 A3 baseline，每條標 硬擋/advisory）

把 addyosmani 四標準翻成機械判定（沿用報告 §3「誠實標註→機械判定」規則）：

| ID | 檢查項 | 機械判定 | 分級 | 對應四標準 | meta-skill 教學段 |
|----|--------|----------|------|-----------|------------------|
| **R1** | frontmatter `name` 存在 + `^[a-z0-9-]+$`（asp 命名空間須 `asp-` 前綴） | grep + regex；fail → exit 1 | **硬擋** | Specific | §frontmatter name |
| **R2** | frontmatter `description` 存在 + 非空 + 第三人稱（禁 `^I `/`我`）+ 含 `Triggers:` 或 `Use when` | parse + regex；fail → exit 1 | **硬擋** | Specific | §frontmatter description |
| **R3** | Triggers 行含繁中字元（中英雙語） | regex `[一-龥]`；fail → warn | **advisory** | Specific | §雙語觸發詞（CLAUDE.md 語言鐵則） |
| **R4** | 核心三段標題齊全（適用場景 / Verification / 下一步） | 同義標題對照表 grep；缺 → exit 1 | **硬擋（核心三段）** | Specific + Verifiable | §必備段 |
| **R4b** | 步驟段存在（Step/Phase/Mode/情境/G/面向 任一）且非空 | 同義標題對照表 grep | **硬擋** | Specific | §工作流 |
| **R5** | discipline 型 skill 含 Common Rationalizations / Red Flags 表 | 標題 grep（依 skill type） | **advisory** | Verifiable | §Red Flags |
| **R6** | Minimal 行數閾值（建議單一 skill ≤ 300 行 → advisory 警告；**meta-skill 自身亦受此規範**） | `wc -l` > 閾值 → warn | **advisory** | Minimal | §Minimal/token 紀律 |
| **R7** | Battle-tested（真實 workflow） | **無法靜態驗 → 不機械化** | **人審（誠實標註）** | Battle-tested | §「先看 AI 無 skill 時怎麼失敗」 |

> **必附「同義標題對照表」**（A3 證實標題有變體，如「適用場景」多數檔同用但仍有 `When to Invoke` 等變體、「步驟」有 Step/Phase/Mode/情境/G/面向 等多種）；否則 baseline 假陰性升高。
> **SKILL.md（router）須獨立豁免**——天生不符內容 skill schema（無步驟/Verification 段），lint 須分 router/content 兩種 profile。
> **meta-skill 吃自己的狗糧**：`asp-skill-author` 本身也是 `.claude/skills/asp/*.md`，本就會被 lint 掃描，須通過自己定義的 R1–R6（尤其 R6 行數）——這是防「meta-skill 退化成純散文無門檻」的自我約束。
> **R4 核心三段 provenance**：核心三段含「適用場景 / 下一步」係 ASP skill 既有慣例追加（見背景段註記），**非** addyosmani 原始四標準（Specific/Verifiable/Battle-tested/Minimal）；把 ASP 慣例段升為 R4 硬擋是本 ADR 的設計選擇，於此透明標註。

### advisory vs blocking 分界（避免一上線大量 fail）

- **新增/修改的 skill**：R1/R2/R4/R4b **硬 gate**（exit 1 擋 CI），R3/R5/R6 advisory，R7 人審。
- **既有 15 skill**：**先 advisory**，逐檔補齊後個別轉硬 gate；此漸進策略對齊報告「15 skill 風格漸進收斂」目標。**POC 例外（已實測）**：R1/R2（name/description 存在性）既有 15 skill **15/15 全過** → R1/R2 直接對全體硬 gate、不必 advisory 過渡（避免稀釋硬 gate 訊號）。R4/R4b **標題錨定**實測 **真缺段 4 檔**：asp-gate（缺下一步）、asp-plan（缺 Verification 標題）、asp-release（缺適用場景）、asp-review-checklist（缺三段）；advisory 過渡只為此四檔（其餘隨補段即清）。（註：POC spike 的寬鬆邏輯曾低估為 3 檔且含 asp-audit「維度」假陰性；**實作把 R4/R4b/STEP 一律錨定到段落標題**後修正為 4 檔——見 POC 報告 §4.5 與 code-review Finding #1。R6 @300 實測 3 檔：asp-autopilot(829)/asp-gate(419)/asp-ship(306)。）
- 分界機械化方式：lint 對 `git diff` 觸及的 skill 套硬 gate，對未觸及的既有 skill 套 advisory（**複用既有 diff 偵測，無新元件——此「零成本複用」假設列入 POC 待驗**）。

### 與上游 CSO 的張力裁決（description 是否可摘要 workflow）

上游 superpowers CSO 主張 description **不可摘要 workflow**；但 ASP 既有 15 skill 的 description **都摘要了 workflow**（如 asp-ship「Executes 10 ordered checks」）。**裁決：採 ASP 寬鬆版**（lint 不擋 workflow 摘要）——ASP skill 多為強制力門檻、本就要被完整讀；改嚴會讓 15 skill 全部 fail，與漸進收斂矛盾。此裁決明列於決策，避免成為 in-context 隱性假設（ADR-020）。

---

## POC 計畫（de-risk，spike）

> POC 屬 spike：放 `docs/research/`、**不接 Makefile/CI/tests**，`Draft` 階段允許做來 de-risk。POC 結果寫入下方 Verification Evidence 的「POC 分支/測試結果」「驗證摘要」欄（記錄事實，非升級狀態）；`驗證日期`/`驗證者` 留待人類簽。

**最高風險假設（POC 要驗的）：**
1. **lint 能否便宜機械化**——frontmatter parse + 必備段 grep + 同義標題對照表，能否用純 bash/grep（或極輕 python）達成，不需引入 YAML parser 依賴 / 新 orchestration 層。
2. **現有 15 skill baseline 合規率**——用嚴格 schema 跑全 15 檔，實測 pass/fail 數，確認「advisory 分界」是落地必要而非過度設計（並校正 recon A3 對「必備段覆蓋率/標題變異」的估計，Draft 不寫死數字）。
3. **git diff per-skill 偵測可否零成本複用**——advisory/blocking 分界宣稱「對 diff 觸及者硬 gate」複用既有 diff 偵測；POC 須確認這不會在實作時暴露成新元件（否則回頭破壞摩擦評估「無新層」的結論）。

**探針怎麼寫（仿 POC-1 exit-code 語意）：**
- 路徑：`docs/research/poc-skill-lint-spike.sh`，**不放 tests/、不接 Makefile target**。
- 輸入：掃 `.claude/skills/asp/*.md`（含 SKILL.md，驗證 router 豁免邏輯）。
- 邏輯：對每檔跑 R1/R2/R4/R4b 機械檢查（frontmatter regex + 同義標題對照表 grep），輸出每檔 PASS/FAIL + 缺漏項。
- **成功判準（exit code 語意，仿 POC-1）：**
  - `exit 0`＝探針成功執行且產出 baseline 數字（**不代表 15 skill 全合規**，只代表 lint 機制可機械運作）。
  - `exit 1`＝探針本身無法機械化（如必須引入重依賴 / 同義標題表覆蓋不了 → 翻盤點觸發，退回重議 gate 設計）。
  - stdout 印出 `PASS=N FAIL=M`（baseline 數字）+ 每檔缺漏項，供 ADR 摩擦評估對照。

---

## 後果（Consequences）

**正面影響：**
- 新 skill 有可執行的撰寫指引（meta-skill）+ 機械門檻（lint），不再全靠人工 review。
- 15 個既有 skill 風格可漸進收斂（advisory → 逐檔補齊 → 硬 gate）。
- 前置把關 ADR-021 plugin marketplace 的 frontmatter 規範要求（嫁接而非疊層）。

**負面影響 / 技術債：**
- 需維護「同義標題對照表」（標題有變體，表過時 → 假陰性）。
- 既有 15 skill 在 advisory 期間 lint 噪音，須有補齊節奏避免長期忽略。
- description workflow 摘要採 ASP 寬鬆版 → 與上游 CSO 分歧，未來上游若強化須重議（已記為已知張力）。
- **Red Flags 寫進 skill 本體只能「降低（非消除）」壓縮蒸發**——skill load 後仍是 in-context，比散在對話的內容更易被重新 load，但**非 hook 級強制**；真正的 hook 兜底仍是 ADR-020 的職責，本 ADR 不宣稱取代之。

**後續追蹤：**
- [ ] `[spike]` POC：lint 四標準機械化探針（`docs/research/poc-skill-lint-spike.sh`，不接 CI），實測 15 skill baseline 合規率
- [ ] `[Accepted 後]` 實作 `asp-skill-author` meta-skill（含必備段教學 + 四標準↔lint 對應表 + R7 人審項標註）
- [ ] `[Accepted 後]` 實作 `tests/test_skill_lint.sh`（複用 `tests/lib/common.sh`），含同義標題對照表 + router 豁免
- [ ] `[Accepted 後]` **meta-skill 吃自己的狗糧**：`asp-skill-author` 須通過自身定義的 R1–R6（尤其 R6 行數）
- [ ] `[Accepted 後]` 接 CI：新增/修改 skill 硬 gate，既有 15 skill advisory（R1/R2 若實測全過則直接硬 gate）
- [ ] `[Accepted 後]` SKILL.md router 補 `asp-skill-author` 一列 + 下一步建議；跑 asp-sync 同步 active（asp-sync 不自我更新）
- [ ] `[Accepted 後]` 既有 15 skill 逐檔補齊必備段，補齊後個別轉硬 gate
- [ ] `[Accepted 後]` 鐵則 / Iron Rule 豁免清單繼承（lint 不掃鐵則 exempt 規則）
- [ ] `[Accepted 後]` R5 advisory（discipline 型 skill 缺 Red Flags 表的提示）——語意判定難，本批延後（R1/R2/R3/R4/R4b/R6 已實作；R7 人審）。見 code-review Finding #3
- [ ] `[Accepted 後/②]` 既有 R4 真缺段 4 檔逐檔補段（asp-gate 下一步 / asp-plan Verification 標題 / asp-release 適用場景 / asp-review-checklist 三段）；R6 mega-skill 拆小併入 ADR-024

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| lint 機械化可行 | frontmatter parse + 必備段 grep 純 bash/grep（無重依賴） | POC 探針 exit 0 + 印 baseline | POC 完成時 |
| 15 skill baseline 合規率 | 實測 pass/fail（校正 A3 估計，advisory 分界必要性驗證） | POC 探針 stdout `PASS=N FAIL=M` | POC 完成時 |
| 四標準機械化覆蓋 | Specific/Verifiable/Minimal 可機械判定，Battle-tested 誠實標人審 | 程式碼審查 | 實作完成時 |
| 新增 skill 硬 gate 生效 | 新 skill 缺核心三段 → exit 1 | lint 腳本 + CI | 接 CI 時 |
| meta-skill 自過 lint | `asp-skill-author` 通過 R1–R6 | lint 掃自身 | 實作完成時 |
| 既有 skill 收斂進度 | advisory fail 數逐月下降 | lint advisory 報告 | 每月（落地後） |

> **重新評估條件**：若 POC 證實四標準中過半無法便宜機械化（須引入重依賴或同義標題表覆蓋不足）→ 退回 advisory-only，重議 gate 設計；若 git diff per-skill 偵測無法零成本複用（成新元件）→ 重審摩擦評估「無新層」結論；若 lint 噪音導致既有 skill 長期 advisory 被忽略 → 重議補齊節奏或降規模。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - **ADR-021**（plugin marketplace 為主要分發，已 `Accepted`）——本 meta-skill/lint 的天然分發嫁接點，frontmatter 前置把關
  - **ADR-020**（AI 遺忘為一級威脅 / 機械化過程義務）——「散文→機械判定」翻譯規則依據；「Red Flags 寫進 skill 本體只能降低非消除蒸發」的誠實邊界依據
  - **ADR-016**（compiled-profile 編譯產物）——skill 載入/同步機制脈絡
  - **ADR-010**（最小採納 / 摩擦評估鐵律）——本 ADR 須通過（見摩擦評估章）
  - **ADR-022**（治理複雜度棘輪）——「誠實標註→機械判定」翻譯規則 + 軸降級先例
  - `docs/research/2026-06-23-addyosmani-agent-skills-deep-borrow.md`（PR #50，蒸餾來源 + §4①/§6 範圍 + CONTRIBUTING 四標準）
  - `docs/research/2026-06-23-addyosmani-borrow-fix-roadmap.md`（②③④⑤ 排序路線圖，不入本 ADR 正文）
  - `.asp-fact-check.md` FC-005（addyosmani 四標準 + frontmatter 規範一手查證）
  - **#39 路線圖 P1**（本 ADR 對應 P1 主缺口）

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由**人類**將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。AI 不可自行升級狀態。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | 已執行（AI 記錄事實，非升級狀態）：`docs/research/poc-skill-lint-spike.sh`（分支 `asp/addyosmani-deep-borrow`）`exit 0`，baseline **PASS=11 FAIL=4 TOTAL=15**（嚴格 schema；router 豁免 R4/R4b）。報告：`docs/research/2026-06-23-poc-skill-lint-spike.md`。 |
| **驗證日期** | （待填，人類） |
| **驗證者** | （待填，人類） |
| **驗證摘要** | POC 已驗承重假設：(1) lint 可純 bash/grep 機械化、零重依賴（exit 0）；(2) R1/R2 既有 15 skill 全過 → 可直接硬 gate；(3) R4/R4b 4 個 fail → advisory 分界對 R4/R4b 必要；(4) 暴露同義標題表假陰性（asp-audit「維度」），證實該技術債真實。假設 3（diff per-skill 偵測零成本複用）未驗，留實作確認。**人類核准（驗證日期/驗證者簽署）後方可升 FIRM/Accepted。** |
