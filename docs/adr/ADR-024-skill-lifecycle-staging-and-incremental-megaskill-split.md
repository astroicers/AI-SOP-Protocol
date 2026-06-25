# [ADR-024]: Skill lifecycle staging index and incremental (non-big-bang) mega-skill split

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-25 |
| **決策者** | ASP framework maintainers（待人類核准） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

> ⬆️ 由 `Draft` 升 `Accepted`：使用者 2026-06-25 透過 `/asp:approve-adr ADR-024`（多次呼叫並明示「ADR-24 我同意」）、看完本指令摘要的決策（選項 D：生命週期分階索引純加 + lint-gated 漸進拆，明確不採 big-bang 全拆）與 Verification Evidence（破壞半徑探針 `exit 0`、BLAST_RADIUS hooks=2/tests=12/skills=6/router=14 → 排除選項 A）後明確同意直升（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。直升不跳過實質驗證——POC（破壞半徑量測）已完成，僅省 FIRM 中間 label。

---

## 背景（Context）

借鏡報告 §4②（`docs/research/2026-06-23-addyosmani-agent-skills-deep-borrow.md`）+ 反思報告 #39 §2：借 addyosmani 的 **6 階段 SDLC + 扁平單一職責 skill**，對治 ASP 的 mega-skill 巨型化。① 的 lint（ADR-023，PR #51）已上線，其 **R6 行數 advisory 持續點名 3 個 mega-skill**：`asp-autopilot`(829) / `asp-gate`(419) / `asp-ship`(306)。② 落 #39 路線圖 P1，依賴 ①（拆出的子 skill 須過 ① 的 R1/R2/R4/R4b schema 門檻）。

**但 ② 是報告自評的高風險項。** POC 探針 `docs/research/poc-megaskill-split-risk.sh` 實測 mega-skill 的「破壞半徑」：

```
BLAST_RADIUS: hooks=2 tests=12 skills=6 router_lines=17   （~37 處硬編引用）
```

- **hooks=2**：`session-audit.sh`、`pretooluse-ship-gate.sh` 硬編 mega-skill 名/段落 → 拆名會使 L1/L1.5 強制力失效。
- **tests=12**：`test_ship_step96`、`test_auto_gate_*`、`test_autopilot_*`、`test_separation` 等釘住名稱/段落 → 拆 → 測試紅。
- **skills=6 + router=17**：跨 skill 互引 + 路由列 → 拆 → 交叉引用/路由漂移。

> **數字註記**：選項 D 的分階索引實作自身在 SKILL.md 新增 3 列 mega-skill 引用 → `router_lines` 由**決策當下量測 14** 升至**索引上線後 17**（總 ~34→~37）。本檔現用 17（可重現值）；第 11 行升級 blockquote 的 14 為決策當下快照（依鐵則不回填升級後產生的值）。blast radius 結論不變（皆遠超 big-bang 閾值）。

⇒ **big-bang 全拆 = 高 churn、高破壞**，與 ADR-010「不為抄形式而動既有層」相悖。本 ADR 採**最小、可逆、不破壞**的路徑。

---

## 評估選項（Options Considered）

### 選項 A：big-bang 全拆（mega-skill → 多個單一職責子 skill）
- **優點**：最貼 addyosmani 扁平結構；單檔最短。
- **缺點**：blast radius ~37 處（hooks/12 測試/6 skill/17 router），一次性大改；hook 硬編名一拆即失強制力。
- **風險**：**高**——撞鐵則（改 hook 強制力）、大量測試紅、交叉引用漂移。為抄形式而動既有層（違 ADR-010）。

### 選項 B：薄入口 + references/ 漸進揭示（不拆 skill 數）
- **優點**：壓 token；不改 skill 名（hook/測試不破）。
- **缺點**：Claude Code 對「skill 內 references/ 按需載入」的支援未驗（recon 未證實）；① lint 掃 `*.md`，references 放哪不被誤掃需設計。
- **風險**：中——機制未驗，貿然採用是賭。

### 選項 C：混合（只拆內聚高、破壞低者；其餘漸進揭示或不動）
- **優點**：風險可控。
- **缺點**：仍需逐案判斷「哪個夠安全」，且每拆一個仍動該 skill 的引用。
- **風險**：中。

### 選項 D：生命週期分階索引（純加）+ lint-gated 漸進拆（採用）
- **優點**：**分階索引是 SKILL.md 純加法**（加一個「階段→skill」索引表，不改既有意圖路由、不改 mega-skill、不動任何引用）→ 零破壞、可逆。**拆分改為機會式漸進**：① 的 R6 advisory 已是持續的「該拆」信號，待某 mega-skill 因他因被動到時、在 ① lint 門檻下拆一塊，而非一次性大改。
- **缺點**：mega-skill 短期仍長（R6 advisory 持續亮）；分階是「視圖」非「重構」。
- **風險**：**低**——不動 hook/測試/引用；分階純加；拆分逐案走 ① 門檻。

---

## ADR-010 摩擦評估（自證：② 不是「為抄 addyosmani 扁平形式而拆」）

| 鏡頭 | 評估 |
|------|------|
| **新增元件清單** | (1) SKILL.md「階段→skill」索引表＝**純加一個 markdown 表**，複用既有 router 檔，無新檔/無新層；(2) 漸進拆＝**複用 ① 的 lint R6 advisory 作信號 + R1/R4 作驗收門檻**，無新機制。**無新 orchestration 層。** |
| **與既有層重疊？** | **不重疊**——分階索引是 router 的新 view，不取代意圖路由（兩者並存）；漸進拆掛在 ① 既有 lint 上。 |
| **overhead vs 節省** | overhead ≈ 1 個索引表（數十行，一次性）+ 逐案拆的個別成本；**big-bang 的 ~37 處 churn 被避免**。節省＝使用者「現在在哪/下一步」可見 + 拆分被 lint 門檻保護。**淨值為正且風險最低。** |
| **結論** | **通過**——選 D（最小、純加、可逆）。**機械化判準**：分階索引上線後 `make test` 仍 exit 0（純加不破測試）+ 每次漸進拆的子 skill 過 ① lint。**翻盤點**：big-bang 全拆（選項 A）經 blast-radius 探針證實高破壞，**明確不採**；選項 B（references 漸進揭示）因 Claude Code 機制未驗，**留待單獨 spike**，本 ADR 不納入。 |

---

## 決策（Decision）

採 **選項 D**：
1. **立即（Accepted 後實作）**：SKILL.md 新增「**生命週期階段索引**」表——把 16 個 skill 映射到 DEFINE/PLAN/BUILD/VERIFY/REVIEW/SHIP（+ Meta），**純加法**，不改既有意圖路由、不動 mega-skill 與其引用。
2. **漸進（無時程，機會式）**：mega-skill 拆分**不做 big-bang**；以 ① 的 R6 advisory 為持續信號，待 mega-skill 因他因被動到時，在 ① 的 lint 門檻下拆出一塊內聚子 skill（每次小、可測、過 lint）。
3. **明確不採**：選項 A（big-bang，blast radius ~37，撞 hook/測試/ADR-010）；選項 B（references 漸進揭示）因機制未驗**另案 spike**，不在本 ADR。

本決策為 `Draft` 提案——**禁止對應生產代碼**（分階索引實作須待人類核准升 Accepted）。POC 探針（破壞半徑量測，spike）已完成。

---

## POC 計畫（de-risk，spike，已完成）

- **探針**：`docs/research/poc-megaskill-split-risk.sh`（放 docs/research/、不接 Makefile/CI/tests）。
- **驗的假設**：big-bang 全拆的破壞半徑是否大到應排除選項 A。
- **結果**：`BLAST_RADIUS: hooks=2 tests=12 skills=6 router_lines=17`（exit 0）→ **證實全拆高破壞**，支持選 D。
- 報告：`docs/research/2026-06-25-poc-megaskill-split-risk.md`。

---

## 後果（Consequences）

**正面影響：**
- 使用者/AI 可從 SKILL.md 看到「現在在 SDLC 哪一階段、下一步哪個 skill」（借 addyosmani 進度地圖價值），零破壞。
- mega-skill 拆分被 ① lint 門檻保護、逐案進行，不冒 big-bang 風險。

**負面影響 / 技術債：**
- mega-skill 短期仍長（asp-autopilot 829 等），R6 advisory 持續亮——這是**刻意保留的可見技術債信號**，非忽略。
- 分階索引需隨新增 skill 維護（與 ① meta-skill 的 router 註冊同步）。

**後續追蹤：**
- [ ] `[Accepted 後]` SKILL.md 加「生命週期階段索引」表（16 skill → 6 階段，純加）
- [ ] `[Accepted 後]` `asp-skill-author` meta-skill 補「新 skill 須標 SDLC 階段 + 登記階段索引」
- [ ] `[漸進/機會式]` mega-skill 逐案拆（asp-autopilot 優先，R6 最高）——每次過 ① lint，不 big-bang
- [ ] `[另案 spike]` 驗 Claude Code「skill + references/ 按需載入」機制（選項 B）→ 成立才考慮 autopilot 用此模式

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 分階索引零破壞 | 加表後 `make test` 仍 exit 0 | make test | 實作時 |
| big-bang 風險已量化規避 | blast radius 探針 exit 0 + 印 ~37 | POC 探針 | 已完成 |
| 漸進拆受門檻保護 | 每個拆出子 skill 過 ① lint（R1/R2/R4/R4b） | tests/test_skill_lint.sh | 每次拆時 |
| R6 advisory 收斂 | mega-skill 數逐季下降（非一次歸零） | ① lint advisory | 每季 |

> **重新評估條件**：若 ① 的 references/ spike（選項 B）證實 Claude Code 支援按需載入且與 lint 相容 → 重議 autopilot 改薄入口；若漸進拆長期停滯（R6 advisory 數年不降）→ 重議是否需排程式拆分。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - **ADR-023**（① skill lint，已 Accepted）——本 ADR 的拆分驗收門檻 + R6 信號來源
  - **ADR-010**（最小採納 / 摩擦評估）——本 ADR 須通過（拒絕 big-bang 為抄形式而動既有層）
  - **ADR-022**（治理複雜度棘輪）——拆分增 skill 檔數但降單檔行數；棘輪管 profile 行數，與本 ADR 不衝突
  - **ADR-020**（AI 遺忘 / 機械強制）——hook 硬編 mega-skill 名是「不可 big-bang 拆」的關鍵約束來源
  - `docs/research/2026-06-23-addyosmani-agent-skills-deep-borrow.md` §4②、`docs/research/2026-06-23-addyosmani-borrow-fix-roadmap.md`（②定義）
  - `docs/research/poc-megaskill-split-risk.sh` / `2026-06-25-poc-megaskill-split-risk.md`（blast radius 證據）
  - **#39 路線圖 P1**

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由**人類**將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。AI 不可自行升級狀態。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | 已執行（AI 記錄事實，非升級狀態）：`docs/research/poc-megaskill-split-risk.sh`（分支 `asp/skill-author-lint`）`exit 0`，**BLAST_RADIUS: hooks=2 tests=12 skills=6 router_lines=17**（~37 處硬編引用）→ 證實 big-bang 全拆高破壞，支持選 D。報告：`docs/research/2026-06-25-poc-megaskill-split-risk.md`。 |
| **驗證日期** | （待填，人類） |
| **驗證者** | （待填，人類） |
| **驗證摘要** | POC 已驗：big-bang 全拆 blast radius ~37（hooks/12 測試/6 skill/17 router）→ 排除選項 A，採選項 D（分階索引純加 + lint-gated 漸進拆）。選項 B（references 漸進揭示）機制未驗，另案 spike。 |
