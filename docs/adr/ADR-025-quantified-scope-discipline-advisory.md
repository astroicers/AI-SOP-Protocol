# [ADR-025]: Quantified scope-discipline advisory in asp-ship Step 2

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-25 |
| **決策者** | ASP framework maintainers（待人類核准） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

> ⬆️ 由 `Draft` 升 `Accepted`：使用者 2026-06-25 明示「幫我 approve adr 25」、看完本指令摘要的決策（選項 B：增強 `asp-ship` Step 2 量化 scope advisory、零新層、advisory 鎖定永不硬 gate）與 Verification Evidence（POC 探針 `exit 0`、SCOPE_DIST total=40/<=8檔=29/>8檔=11/max=142）後明確同意直升（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。直升不跳過實質驗證——POC（分佈校準）已完成，僅省 FIRM 中間 label。

---

## 背景（Context）

借鏡報告 §4④（`docs/research/2026-06-23-addyosmani-agent-skills-deep-borrow.md`）：addyosmani 把「scope 紀律」當作工作流信號（只動被要求的；任務過大＝警訊）。報告主張把 ASP **質性**的「輕量改動」升為**可機械偵測的信號**——但明確只借精神、**不照搬** addyosmani 二手的「≤5 檔」硬數字（FC-005 已標：該數字一手未載）。落點 #39 路線圖 **P3**。

**誠實的起點：與既有層的重疊。** ASP 的 `asp-ship` **Step 2「確認變更範圍」已在做質性版**（`git status` / `git diff --stat`，檢查「是否有意外的變更」）。所以 ④ 不是新需求，而是「把已存在的 Step 2 從質性升為**量化 advisory**」。這決定了 ④ 必須是**增強既有步驟**，而非新增平行機制（否則撞 ADR-010「拒絕與既有層重疊」）。

**POC 校準（`docs/research/poc-scope-signal-distribution.sh`，已完成）**：ASP 自身近 40 個 non-merge commit 的改檔數分佈——
```
SCOPE_DIST: total=40  <=8檔=29  >8檔=11  max=142檔
```
→ (1) 閾值 **>8 檔** 可把「正常工作（29/40）」與「可能多任務（11/40）」分開；(2) **max=142 檔證實 ASP 有合法大 commit**（installer / v5 批次 / 大合併）→ scope 信號**必須 advisory，不能硬 gate**（硬擋會誤傷合法大改、撞 ADR-020「偽硬 gate」）。

---

## 評估選項（Options Considered）

### 選項 A：新增獨立 scope-check 機制（script / pre-commit hook）
- **優點**：職責獨立。
- **缺點**：與 `asp-ship` Step 2 功能重疊；新增一個機制/掃描點＝新層。
- **風險**：撞 ADR-010（為抄形式而與既有層重疊）；複雜度棘輪（ADR-022）淨增。

### 選項 B：把量化 advisory 加進 `asp-ship` Step 2（採用）
- **優點**：**複用既有 Step 2 + 既有 `git diff --stat`**，零新機制/層；advisory 與既有「確認變更範圍」同位；改動極小（Step 2 加一條閾值 advisory）。
- **缺點**：只在 `asp-ship`（commit 前）觸發，不涵蓋非 commit 場景（可接受——scope 信號本就最該在 commit 前提醒）。
- **風險**：低。

### 選項 C：放進 `asp-impact`
- **優點**：與依賴影響分析同處。
- **缺點**：`asp-impact` 是**按需**呼叫（影響分析時），非每次 commit；scope 信號該在 commit 前提醒 → 觸發點錯。
- **風險**：信號錯過時機。

### 選項 D：不做（④ 與 Step 2 重疊到不值得）
- **優點**：零新增。
- **缺點**：放棄「質性→量化」的小幅可機械化價值（量化 advisory 比「憑感覺」可重現）。
- **風險**：無，但漏掉一個低成本改善。

---

## ADR-010 摩擦評估（自證：④ 不是「為抄 scope 紀律形式而加層」）

| 鏡頭 | 評估 |
|------|------|
| **新增元件清單** | 0 個新機制。**只在 `asp-ship` Step 2 加一條量化 advisory**（複用既有 `git diff --stat` 的檔數）。無新 script、無新 hook、無新掃描點、無新 Makefile target。 |
| **與既有層重疊？** | ④ 的本質**就是**消除重疊——`asp-ship` Step 2 已在做質性 scope 檢查；④ 把它量化，是**增強同一步驟**而非平行新機制。與 ①（R6 skill 行數）同源思路、不同作用對象（① 管 skill 體積、④ 管一次 commit 的 diff 範圍），兩者都複用「size→advisory」模式，無互相重疊。 |
| **overhead vs 節省** | overhead ≈ `asp-ship` Step 2 加數行 + 一個閾值常數（POC 校準 >8）。節省＝把「憑感覺判斷改太大」變成可重現的量化 nudge。**淨值為正**（一次性極小 overhead）。 |
| **結論** | **通過**——零新層、複用既有步驟與 diff-stat、自我約束。**機械化判準**：advisory 觸發＝`git diff --cached --stat` 改檔數 > 8（exit code 不變、不阻擋 commit）。**翻盤點（誠實標註）**：POC max=142 證實 ASP 有合法大 commit → 本案**鎖定 advisory，永不升硬 gate**（升硬 gate 會撞 ADR-020 偽硬 gate + 誤傷合法大改）；閾值 8 為 POC 校準值，可隨分佈調整（advisory 不需精確）。 |

---

## 決策（Decision）

採 **選項 B**：在 `asp-ship` Step 2「確認變更範圍」**加一條量化 scope advisory**——當 `git diff --cached --stat` 的改檔數 **> 8** 時，輸出：「⚠️ scope advisory：本次改 N 檔（>8），可能是多個任務，建議評估是否拆分（借鏡 addyosmani scope discipline；advisory，不阻擋 commit）」。

- **advisory only，永不硬 gate**（POC max=142 證實合法大改存在）。
- **量測對象 = staged（`git diff --cached --stat`）**：scope advisory 量「即將 commit 的 staged 範圍」。既有 Step 2 用 `git diff --stat`；本案改用 `--cached` 量 staged，是**小幅增強而非零改動**（SPEC 階段須與 Step 2 既有「未暫存變更提醒」對齊量測對象）。複用既有 diff-stat 機制，零新機制/層。
- **落點演進（修正 roadmap）**：借鏡報告 roadmap 原定 ④「接 `asp-impact`」；本案改採 `asp-ship` Step 2（選項 C 駁回 asp-impact：按需呼叫、觸發時機錯）——決策優於原 roadmap，roadmap ④ 列已同步回寫。
- 借 addyosmani **精神**（scope 過大＝警訊），**不照搬**二手「≤5 檔」數字（FC-005）。閾值 8 為 **ASP 自身分佈校準值**（落在 7/9 commit 數的天然空隙、邊界穩健；他用專案應自校）。

本決策為 `Draft` 提案——**禁止對應生產代碼**（asp-ship Step 2 改動須待人類核准升 Accepted）。POC（分佈校準）已完成。

---

## POC 計畫（de-risk，spike，已完成）

- **探針**：`docs/research/poc-scope-signal-distribution.sh`（放 docs/research/、不接 Makefile/CI/tests）。
- **驗的假設**：(1) 是否存在能分開「正常/可能多任務」的閾值；(2) ASP 是否有合法大 commit（決定 advisory vs 硬 gate）。
- **結果**：`SCOPE_DIST: total=40 <=8檔=29 >8檔=11 max=142檔`（exit 0）→ 閾值 >8 可用；max=142 → 必 advisory。
- 報告：`docs/research/2026-06-25-poc-scope-signal-distribution.md`。

---

## 後果（Consequences）

**正面影響：**
- commit 前獲得可重現的 scope nudge（量化），借 addyosmani scope discipline 而不誤傷 ASP 合法大改。
- 與 ① 的 R6 形成一致的「size→advisory」家族（skill 體積 + diff 範圍）。

**負面影響 / 技術債：**
- 閾值 8 是 POC 當下校準值，分佈漂移時需重校（advisory 容忍誤差，影響低）。
- 只在 `asp-ship` 觸發，非 commit 路徑（如直接 git commit 繞過 asp-ship）不提醒——但 L1.5 ship-gate 本就只擋測試痕跡，scope 是 advisory，可接受。

**後續追蹤：**
- [ ] `[spike]` POC：分佈校準（已完成，`docs/research/poc-scope-signal-distribution.sh`）
- [ ] `[Accepted 後]` `asp-ship` Step 2 加量化 scope advisory（diff 檔數 >8 → 提示拆分；advisory）
- [ ] `[Accepted 後]` 文件同步：asp-ship skill 的 Step 2 說明 + 過程義務速查（若需）

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 零新機制/層 | 只改 asp-ship Step 2，無新 script/hook | 程式碼審查 | 實作時 |
| advisory 不阻擋 | scope >8 時印提示但 commit 照常（exit 0） | asp-ship 實測 | 實作時 |
| 閾值合理 | >8 檔分開正常/大改（POC：29 vs 11 / 40） | POC 探針 | 已完成 |
| 不誤傷合法大改 | 大 commit 只得 advisory、不被擋 | asp-ship 實測 | 實作時 |

> **重新評估條件**：若 advisory 噪音過高（正常工作頻繁觸發）→ 調高閾值或改百分位；若有人提議把它升硬 gate → 拒絕（撞 ADR-020 + 誤傷合法大改，POC max=142 為據）。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - **ADR-023**（① skill lint R6 行數 advisory）——同源「size→advisory」思路，不同作用對象
  - **ADR-020**（AI 遺忘 / 機械強制；偽硬 gate 之忌）——本案鎖定 advisory 的依據
  - **ADR-010**（最小採納 / 摩擦評估）——本 ADR 須通過（增強既有步驟、不加層）
  - **ADR-022**（治理複雜度棘輪）——本案僅加數行，棘輪淨增可忽略
  - `docs/research/2026-06-23-addyosmani-agent-skills-deep-borrow.md` §4④、`docs/research/2026-06-23-addyosmani-borrow-fix-roadmap.md`（④定義）
  - `docs/research/poc-scope-signal-distribution.sh` / `2026-06-25-poc-scope-signal-distribution.md`（分佈校準）
  - `.claude/skills/asp/asp-ship.md`（Step 2 = 增強目標）｜`.claude/skills/asp/asp-impact.md`（依賴影響，非 scope 觸發點）
  - **#39 路線圖 P3**

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由**人類**將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。AI 不可自行升級狀態。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | 已執行（AI 記錄事實，非升級狀態）：`docs/research/poc-scope-signal-distribution.sh`（分支 `asp/scope-signal`）`exit 0`，**SCOPE_DIST total=40 <=8檔=29 >8檔=11 max=142檔** → 閾值 >8 可用、max=142 證實必 advisory。報告：`docs/research/2026-06-25-poc-scope-signal-distribution.md`。 |
| **驗證日期** | （待填，人類） |
| **驗證者** | （待填，人類） |
| **驗證摘要** | POC 已驗：scope 信號可量化（閾值 >8 檔分開 29/11）；ASP 有合法大 commit（max=142）→ 鎖定 advisory；決策為「增強 asp-ship Step 2、零新層」。 |
