<!-- Last Updated: 2026-06-23 | Status: Draft | Audience: Maintainers -->

# 深層借鏡研究：addyosmani/agent-skills —— 同品類最近的鏡子

本報告為**評估交付物**，非實作。深層研究 [`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills)（24 skill、6 階段 SDLC、MIT、已上 Claude Code 官方 plugin marketplace、65.7K★ 量級的「agent 工程紀律能力封裝庫」），對抗式判斷哪些 execution 細節能機械化遷移到 ASP，扣回 P0–P4 序列。所有「借鏡動作」皆為提案，需經 ADR 流程核准後方可落地。承接反思報告 P1 對同類庫的初步引用（`docs/research/2026-06-22-external-benchmark-reflection.md`）與 nuwa 深層研究的「誠實標註→機械判定」翻譯規則（`docs/research/2026-06-23-nuwa-skill-deep-borrow.md`）。第三方事實一手查證記於 `.asp-fact-check.md` FC-005（marketplace 另見 FC-004）。

## 0. 摘要（TL;DR）

使用者直覺「**很多地方很接近**」——正確，而且是**結構性**的。不同於 nuwa（persona 蒸餾，異品類），addyosmani 與 ASP 是**同一品類**：都把「資深工程師的工程紀律」封裝成可路由的能力單元。這是迄今最近的鏡子。三點結論：

1. **趨同即驗證**：addyosmani 四原則（process-not-prose / anti-rationalization / verification non-negotiable / progressive disclosure）幾乎逐條對應 ASP 既有機制（§2）。兩個獨立專案收斂到同一組原語 = 這些是 agent 治理的真不變量，ASP 核心架構押對了。
2. **借鏡是非對稱的**：addyosmani 停在「**散文紀律**」（靠 in-context 表格傾斜天平、純 markdown、人工 reviewer 把品質）；ASP 已**刻意越過**這階段進入「**機械強制**」（hook / deny / 編譯產物）。所以多數原語 ASP 已有且更強，照抄概念 = 與既有層重疊（違 ADR-010）。
3. **能借的集中在 ASP 的短處——skill 的打包、可發現、寫作品質工具化**：**主要真缺口** = 沒有「怎麼寫一個 ASP skill」的 meta-skill 與 skill 級 lint（§4 ①）；**次要真缺口** = 規則 provenance（§4 ⑤）；其餘為既有機制的結構/量化補強（§4 ②③④）。

## 1. 先破三個迷思（深層借鏡的起點）

| 迷思 | 一手查證後的真相 |
|------|-----------------|
| 「Anti-rationalization tables 是 addyosmani 的獨門設計，ASP 該抄」 | ASP 早有同構物且**更有牙**：4 條鐵則表、`asp-ship` Step 10 的 ASP BYPASS 警告、ADR-020 P1b 的「過程義務速查（compaction-safe）」、各 skill 的 Red Flags，外加 L1.5 PreToolUse hook 兜底。趨同不是抄襲，是同品類收斂。 |
| 「純 markdown + 跨 50 runtime + 一行安裝 = 更優架構」 | 那是「**無機械強制**」的代價，不是優勢。與 ASP 立身（hook/deny/編譯產物有牙）是**對立目標**——同 nuwa §1 的結論：可攜性與強制力此消彼長。 |
| 「65.7K★ / 24 skill = 設計成熟度更高」 | star 與數量反映**採用敘事與品類廣度**，非治理深度。兩者「深」的維度不同：addyosmani 深在打包/可發現/寫作紀律；ASP 深在強制力 + ADR 治理。互為鏡子，非高下。 |

## 2. 趨同地圖（本報告最有價值的一張表）

逐條對照 addyosmani 的 execution 與 ASP 已長出的胚胎/機制：

| addyosmani 原語 | 它的 execution | ASP 對應 | 判定 |
|----------------|---------------|---------|------|
| Anti-rationalization | 每 skill 一張「藉口×反駁」表（in-context 傾斜天平） | 鐵則表 + ASP BYPASS 警告 + 過程義務速查 + Red Flags + L1.5 hook | 已有，且多了 hook 牙齒；惟**分散、未成每-skill 標配結構** |
| Progressive disclosure + `using-agent-skills` meta-router | 「Maps incoming work to the right skill」+ references load-when-needed | `SKILL.md` 意圖母路由 + `.asp-compiled-profile.md` 編譯 + profile 組合載入 | **已有且更強**（編譯產物 + hook 注入，不只 in-context） |
| Verification non-negotiable（"'Seems right' is never sufficient"） | 每 skill 一段 Verification（要外部證據） | `reality-checker`（預設 NEEDS_WORK、read-only、職能分離）+ G5 + ADR Verification Evidence | **已有且更強**（獨立評者 + exit-code gate） |
| Scope discipline | 「只動被要求的」、任務過大即警訊 | 輕量改動可跳重 gate + `asp-impact` + minimal-change | 已有，但**質性、未量化為機械信號** |
| 6 階段 SDLC（DEFINE→…→SHIP）+ 每階一 slash command + 進度地圖 | skill 依階段分類，使用者知道「現在在哪/下一步」 | 標準工作流（需求→ADR→SDD→TDD→實作→文件→部署）+ 15 skill 經母路由依**意圖**分流 | 工作流已有；但 skill **未依階段分類、無進度地圖**（意圖路由 ≠ 階段路由） |
| 扁平、單一職責、可發現（24 小 skill） | 想要哪塊取哪塊 | mega-skill：`asp-autopilot`≈829 行、`asp-gate`≈419 行 | **較弱**（巨型化，#39 §2 已診斷） |
| CONTRIBUTING 品質四標準 + reviewer 規則 + frontmatter 驗證 | Specific/Verifiable/Battle-tested/Minimal + `gh pr list` 預檢 + 「frontmatter 須有效」 | 無 skill-authoring meta-skill、無 skill 級 lint（只有 task 級 G1–G6） | **真缺口** |
| 規則 provenance（明引 Hyrum's Law / Beyoncé Rule / Test Pyramid） | 每條規則「why/來源」可追溯 | skill 規則多無來源欄（STRIDE 等散見 profile） | 真缺口（次要） |

八列裡六列「已有/更強」、兩列「真缺口」——這就是「很接近」的精確形狀。

## 3. 非對稱借鏡的本質（最深的一層）

為什麼「已有」的不能照抄、「真缺口」才值得借？因為**執行者不同**：

- **addyosmani 的執行者 = 人 + 短上下文**：in-context 藉口表能「傾斜天平」、references「load only when needed」、人工 reviewer（62 open issues + reviewer checklist）守品質。這些在「人在讀、上下文短、有人審」的前提下有效。
- **ASP 的執行者 = 會被壓縮的 AI**（ADR-020「遺忘威脅」）：散文義務在長對話壓縮後**蒸發**、沒有人工 reviewer。

⇒ 同一條翻譯規則（#47）成立：**addyosmani 的任何點子遷移時，都得從「散文/人工」翻成「機械判定」（exit code / hook / frontmatter schema）**，否則就是換一種方式重蹈 ASP 正在治的病。

**最尖的反諷**：addyosmani 最招牌的 anti-rationalization table，本質就是 in-context 散文義務——正是 ADR-020 認定「壓縮後最先蒸發」的那一類。若照抄「每個 ASP skill 再多塞一張藉口表」，等於**增加壓縮債、反向放大原病**。ASP 對「預先反駁」的正解早已是「過程義務速查 one-liner（compaction-safe）+ L1.5 hook 兜底」。所以這裡要借的是「**預先反駁**」的**意圖**，絕不是「in-context 表格」的**形式**。

## 4. 真能遷移的（去重後扣回 P0–P4，每條過 ADR-010 摩擦評估）

| 借鏡動作 | 落點 | 內容（**機械化版本**） | ADR-010 摩擦評估結論 |
|---------|------|----------------------|---------------------|
| **① skill-authoring meta-skill + frontmatter/品質 lint**（唯一真缺口、最高槓桿） | **P1**（可獨立小 ADR） | 一個 `asp-skill-author` meta-skill（怎麼寫 ASP skill：name/description/triggers + 必備段 步驟/Red Flags/Verification）+ CI lint 驗 frontmatter schema 與必備段。把 addyosmani 人工四標準翻成機械 lint。 | **通過**：新增 = 1 meta-skill + 1 lint step（複用 `tests/lib/common.sh` runner，**無新 orchestration 層**）；不重疊（現無 skill 級 lint，只有 task 級 gate）；overhead 低、節省 = 15 skill 風格收斂 + 防漂移。 |
| **② skill 依生命週期分階 + mega-skill 拆小** | **P1**（併入 #39 §2 既有提案） | 借 addyosmani 6 階段骨架，把 `asp-autopilot`/`asp-gate` 拆成單一職責；`SKILL.md` 母路由補「階段→下一步」進度地圖（薄路由、不含工作流）。 | **通過**：複用既有母路由；不另開層；節省 = 可測/可重用/抗壓縮蒸發。 |
| **③ plugin marketplace 為活證** | **P1**（強化 ADR-021，非新提案） | addyosmani 已在官方 marketplace 跑同品類庫（skills+commands+hooks），是 ADR-021「低風險」的現成第三方對照樣本，補強 FC-004 殘留 POC。 | **通過**：不新增元件（是證據）；降低 ADR-021 不確定性。 |
| **④ scope 紀律量化為機械信號** | **P3**（接 `asp-impact`） | 把「輕量改動」從質性升為可偵測信號（diff 檔數/行數超閾值 → 提示「可能是多任務、建議拆」），**advisory 非硬 gate**。 | **通過（降級 advisory）**：複用 metrics；不阻擋 commit（避免偽硬 gate 撞 ADR-020）；overhead 低。 |
| **⑤ 規則 provenance 欄**（次要） | **P3** / 視情況小 ADR | skill 規則可選加「來源/why」欄（引 STRIDE/既有 ADR）增可追溯。 | **條件通過**：須防 ADR/欄位通膨（ADR-022 複雜度棘輪會計入）→ 僅在不增治理行數淨額時做。 |

> scope「≤5 檔」這個 addyosmani 的具體數字僅見二手、一手未載（FC-005），故 ④ 只借「量化為機械信號」的精神，不照搬該數字。

## 5. 千萬別照搬（會直接弄壞 ASP）

- **「每 skill 多塞 in-context 藉口表」→ §3 已證會放大壓縮蒸發病。** 借意圖（預先反駁），不借形式（表格）。
- **純 markdown / 多 runtime / 一行安裝至上 → 會把 ASP 還原成沒牙規範。** hook/編譯產物/installer 是 essential 且**故意不可攜**（ADR-016）；可攜層分離是 P4 的「誠實欄位」，不是丟掉強制力。
- **人工 reviewer 品質模型（issues + reviewer checklist）→ ASP 無人工 reviewer。** 不機械化就退化成治理劇場——必經「散文→機械」翻譯（§3）。
- **「/build auto 全自動實作所有任務」→ 撞鐵則**（ADR 須 Accepted、破壞性須人類確認、Draft 禁實作）。只抄階段結構，不抄全自動。
- **抄「概念」本身 → addyosmani 多數原語 ASP 已有且更強（§2）。** 抄概念 = 與既有層重疊，違 ADR-010 hard rule。只抄 ASP 真缺的（① 主要、⑤ 次要）+ 借成熟參照與量化補強（②③④）。

## 6. 收斂

addyosmani 給 ASP 的最大價值，是**一面最近的同品類鏡子**：§2 八列裡六列「已有/更強」，**證明 ASP 核心架構押對**；分歧的後三列，**精準照出 ASP 最關鍵的真債——skill 寫作/品質的工具化**。

- **最高槓桿單一動作** = §4 ①（`asp-skill-author` meta-skill + lint，落 **P1**），且天然嫁接 ADR-021 marketplace 遷移（plugin 本就要求 frontmatter 規範，lint 正好前置把關）。
- 本報告為 **P1（與 P3 部分）依據**。對應 ADR（① 可獨立小 ADR；② 併 P1 既有；④ 落 P3）各自走流程、需人類核准。**本報告不升任何 ADR**。

## 附錄：證據索引

- **addyosmani（一手，記於 FC-005）**：`README.md`（24 skill = 23 lifecycle + 1 meta；6 階段 DEFINE/PLAN/BUILD/VERIFY/REVIEW/SHIP；四原則；8 slash 指令；MIT）、`CONTRIBUTING.md`（Specific/Verifiable/Battle-tested/Minimal、100 行 bundling 門檻、frontmatter name/description、`gh pr list --state open` 預檢）、meta `using-agent-skills`、marketplace 指令 `/plugin marketplace add addyosmani/agent-skills`。二手脈絡：addyosmani.com/blog/agent-skills、O'Reilly Radar。
- **ASP**：`.claude/skills/asp/SKILL.md`（意圖母路由）、`asp-autopilot.md`(≈829)/`asp-gate.md`(≈419)（mega-skill）、`.asp-compiled-profile.md`(≈2082)、`asp-reality-check.md`（預設 NEEDS_WORK、read-only）、`CLAUDE.md`（4 鐵則 / 過程義務速查 compaction-safe / ASP BYPASS 警告）、ADR-010（摩擦評估）、ADR-016（編譯產物 essential/不可攜）、ADR-020（遺忘威脅/壓縮蒸發）、ADR-021（marketplace, FC-004）、#39 反思報告（P0–P4 / §2 mega-skill 診斷）、#47 nuwa 深層研究（誠實標註→機械判定翻譯規則）。
