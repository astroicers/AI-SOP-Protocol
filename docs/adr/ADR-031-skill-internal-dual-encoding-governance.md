<!-- Last Updated: 2026-07-29 | Status: Draft | Audience: ASP framework maintainers -->
# [ADR-031]: skill 內雙高度雙重編碼的治理（以 asp-autopilot Part1/Part2 為例）

| 欄位 | 內容 |
|------|------|
| **狀態** | `Draft` |
| **日期** | 2026-07-29 |
| **決策者** | ASP framework maintainers |
| **觸發事件** | skill 優化計畫階段 C——16-agent 診斷（PR #82 前置）發現 asp-autopilot 的體積主要來自 Part1/Part2 對同一組 gate 的雙重編碼，且**已 drift**（部分列僅存其中一表） |
| **關聯** | ADR-006（Item 7：asp-autopilot Part 2 為唯一 canonical 執行規格）；ADR-024（skill 分階 + 機會式漸進拆）；ADR-023（asp-skill-author）；ADR-030（writing-great-skills 失敗模式：duplication）；ADR-010（最小採納 / 摩擦評估）；階段 A（PR #82）、階段 B（PR #84） |

> **狀態說明：** `Draft`（初稿，**禁止實作生產碼**，skill 為行為 canonical 亦屬之）→ `Accepted`（人類審核後方可另立 SPEC 實作）。本 ADR 為設計/分流決策，不含實作。

---

## 背景（Context）

skill 優化計畫階段 A（精簡 −42 行，PR #82 merged）、階段 B（writing-great-skills 失敗模式判準融入 asp-skill-author，PR #84 merged）完成後，16-agent 診斷剩 **2 項 `restructure`**（行為性去重，須獨立審查/ADR）：`asp-autopilot`（829 行）與 `asp-plan`（236 行）。本 ADR 處置之。

### 已確認事實（本 session 診斷 + 親讀）

1. **雙重編碼位置**：asp-autopilot 的「autopilot 自動處理」概念在檔內編碼兩次——
   - **Part 1「零確認策略」**（L202-226）：6 列自動處理表 + 5 條仍需暫停（鐵則）+ Auto-PR 4 步。**摘要操作視圖**。
   - **Part 2「Autopilot 自主處理策略（零確認）」**（L773-796）：17 列自動行為表 + 禁止表。**canonical 完整規格**（ADR-006 Item 7 定為唯一 canonical source）。
2. **已 drift（核心問題，非美觀）**：兩表**不是**同一內容的兩種粒度而已，而是**已經不一致**——Part 1 有「Context 達 60%/75% → 存檔」列，Part 2 **無**；Part 2 有依賴循環/範圍超出/DB schema/新增外部依賴等 ~11 列，Part 1 **無**。同一「autopilot 遇到 X 怎麼辦」的規格，讀者從兩處讀到**不同答案集合**。
3. **Auto-PR 亦雙編碼**：Part 1 L222-226（散文 4 步）vs Part 2 L787-788（表列）——目前一致，但仍是兩處維護點。
4. **Phase 0.5 死碼**（L420-430）：`agent_memory` profile 於 v4.1.1 archive，其 `IF exists(...)` 永遠 false → 走 ELSE 空 init；`agent_memory`/`agent_session` 賦值後全檔無 downstream 引用（dead variables）。註解自承「此 IF 永遠 false…v4.2 將正式 deprecate」。

### 問題陳述

雙重編碼的成本不是「行數」（asp-autopilot 829 行，去重後 ~780，仍遠 >300、**不解 R6**——R6 靠 ADR-024 機會式拆，非本 ADR 目標）。真正的成本是 **duplication 的經典危害已實現**（ADR-030 借入的 writing-great-skills 判準）：同一意義兩處編碼 → 維護時漏改一處 → **drift → autopilot 執行規格內部不一致 → 行為歧義**。事實 2 證明 drift 已發生。

---

## 決策（Decision，Draft 待人類 Accept）

1. **asp-autopilot — Part 2 為單一 canonical，Part 1 收斂為指標性摘要**：
   - **前提（不可省）**：先**逐列比對** Part 1 ∪ Part 2，把 Part 1 獨有的列（Context 60%/75% 存檔等）**併入 Part 2**，確保 canonical 涵蓋全部規格、**零丟失**。
   - Part 1 收斂為 3–5 行速覽（「autopilot 自動處理多數情況、鐵則操作仍停；完整規格見下方 §Part 2」）+ 明確指向 Part 2。
   - Auto-PR 同理：Part 2 為 canonical，Part 1 縮為一行引用。
2. **Phase 0.5 死碼移除**（附帶，低風險）：刪 L420-430 dead block（行為不變，`agent_memory`/`agent_session` 無 downstream 引用）。
3. **asp-plan 反繞過表 — 不動**（守 ADR-010 摩擦評估）：收益小（~10 行），且收斂 negation 表會改變 anti-bypass 引導（行為性、風險不低），成本效益不划算。列為未來機會式，非本 ADR 範圍。

---

## 考慮的替代方案（Alternatives Considered）

- **(a) 全去重（Part 1 整段刪，只留 Part 2）**：最省行。**拒絕**——損失「快速理解入口」：讀者初次理解 autopilot 要直接啃 17 列詳表 + 禁止表。雙高度對「初次理解 vs 精確執行」兩種讀者路徑有 information hierarchy 價值（writing-great-skills：不同 tier），不該完全消除，只該**消除 drift 並縮短摘要**。
- **(b) 保留雙高度、完全不動**：零實作風險。**拒絕**——接受 drift 持續 = autopilot 規格內部不一致長存（正確性問題，非美觀）；且每次改 autopilot 行為要同步兩處，維護債持續累積。
- **(c) 本 ADR 選項（Part 2 canonical + Part 1 收斂摘要 + 先合併 drift）**：取平衡——消除 drift 源（單點維護）、保留快速入口（縮短摘要）、canonical 零丟失。**採納**。

---

## 後果（Consequences）

- **正面**：消除 Part1/Part2 drift（維護正確性——改 autopilot 行為只需改 Part 2 canonical）；autopilot 執行規格單一真相；Part 1 縮短提升可讀。示範「刻意雙高度 ≠ 放任 drift」的 skill 治理原則（可回饋 asp-skill-author 的 duplication 判準）。
- **負面/風險**：動 **ADR-006 canonical 執行規格**——實作須逐列比對（漏列 = 丟 autopilot 規格，直接影響執行行為）+ 獨立審查確認 canonical 零丟失 + Part 1 摘要正確指向。autopilot 行為難自動測（無單元測試覆蓋執行迴圈），驗證倚賴人類 + 對抗式審查。
- **中性/誠實標明**：**不解 R6**（autopilot 去重後仍 >300）——本 ADR 目標是**消 drift + 單點維護**，非降行數；若要降 R6 屬 ADR-024 機會式拆的範疇，另議。行數收益（~50 行）是副產品非目的。

---

## 實作 gate（Accepted 後）

ADR Accepted → 另立 SPEC（含：Part1∪Part2 逐列合併映射表、收斂後 Part 1 樣板、Phase 0.5 移除 diff）→ 實作 → **獨立 read-only 審查**（確認 canonical 零丟失、Part 1 摘要指向正確、autopilot 行為語意不變）→ asp-ship。**Draft 期間禁止動 asp-autopilot.md。**

---

## Verification Evidence（升 Accepted 時填）

| 欄位 | 內容 |
|------|------|
| 診斷證據 | 16-agent 診斷（wf_15dbedf9-57c）：asp-autopilot verdict=restructure，findings 列 Part1/Part2 雙重編碼 + drift + Phase 0.5 死碼 |
| 親讀佐證 | 本 ADR 事實 1-4 為主 agent 親讀 asp-autopilot.md L202-226 / L769-807 / L420-430 |
| 驗證日期 | — |
| 驗證者 | — |
