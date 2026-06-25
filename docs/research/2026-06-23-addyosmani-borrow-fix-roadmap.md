<!-- Last Updated: 2026-06-23 | Status: Draft | Audience: Maintainers -->

# addyosmani/agent-skills 借鏡修復路線圖（①→⑤）

本檔為**規劃文件**，非實作。把借鏡報告 `docs/research/2026-06-23-addyosmani-agent-skills-deep-borrow.md`（PR #50）§4 的五個借鏡點，排成可逐一執行的 ADR-first 修復路線。每項標：對應 ADR / P-level、依賴、機械化形態、狀態。**路線獨立成檔**（不入 ADR-023 正文），以免單一 ADR 綁定 ADR-024/P3 諸項的編號決策（ADR 應只決策自身範圍）。

> **鐵則邊界（貫穿全線）**：每項的生產代碼只能在它自己的 ADR 升 `Accepted`（人類核准）後才寫；`Draft` 階段最多做 POC 探針（spike，放 `docs/research/`、不接 Makefile/CI/tests）。逐項皆須過 ADR-010 摩擦評估、且採「機械化版本而非散文」（報告 §3 翻譯規則）。

---

## 全線總覽

| 項 | 內容 | 對應 ADR / P-level | 依賴 | 機械化形態 | 狀態 |
|----|------|-------------------|------|-----------|------|
| **①** | `asp-skill-author` meta-skill + skill 級品質 lint | **ADR-023 / P1** | 嫁接 ADR-021（已 Accepted）；無上游依賴 | meta-skill（判斷型）+ lint（硬擋/advisory 分級） | **✅ 已實作（PR #51 merged）** |
| **②** | skill 依生命週期分階 + mega-skill 拆小 | **P1（建議獨立 ADR-024）** | 依賴 ①（lint 為拆出子 skill 的 schema 驗收門檻） | 拆分後每子 skill 過 ① 的 schema lint；R6 行數 advisory 為「該拆」信號 | **✅ ADR-024 Accepted + 分階索引（PR #52）** |
| **③** | plugin marketplace 為活證（補強 ADR-021） | **ADR-021（強化，非新 ADR）** | 無——是 ADR-021 的現成第三方證據 | 不新增元件（是證據） | **✅ 已補 ADR-021 VE（PR #52, 2026-06-25）** |
| **④** | scope 紀律量化為機械信號 | **P3（建議獨立 ADR）** | 接既有 `asp-impact`；複用 metrics | advisory 非硬 gate | 待起（P3） |
| **⑤** | 規則 provenance（次要真缺口） | **P3 條件式（建議獨立 ADR）** | 接既有 rule-hits telemetry | 條件式 provenance 欄，非新層 | 待起（P3，條件觸發） |

### 依賴鏈

```
ADR-021（Accepted，分發）
   └─ ① ADR-023（P1，本批：meta-skill + lint）── 嫁接點 + ② 的 schema 驗收門檻
         └─ ② P1（mega-skill 拆小，建議 ADR-024）── 依賴 ① 的 lint 先在
   ③ 已在 ADR-021（活證，補強非新 ADR）
   ④ P3（接 asp-impact，advisory）── 獨立，與 ① 同源思路（① 管 skill 體積、④ 管 diff 範圍）
   ⑤ P3 條件式（接 rule-hits telemetry）── 獨立，條件觸發
```

---

## ① meta-skill + lint（ADR-023 / P1）— 本批進行中

- **借什麼**：addyosmani CONTRIBUTING 四標準（Specific/Verifiable/Battle-tested/Minimal）的**可機械化那一半**，翻成 exit-code 級 lint；判斷型那一半由 meta-skill 教。
- **改/新增哪些檔**（`Accepted` 後）：`.claude/skills/asp/asp-skill-author.md`（新 meta-skill）、`tests/test_skill_lint.sh`（複用 `tests/lib/common.sh`）、`.claude/skills/asp/SKILL.md`（router 補一列）、CI 接線。
- **本批已交付**：ADR-023 Draft + POC 探針 `docs/research/poc-skill-lint-spike.sh` + POC 報告（baseline）。
- **詳見**：`docs/adr/ADR-023-adopt-skill-authoring-meta-skill-and-skill-level-lint.md`。

## ② mega-skill 拆小 + 生命週期分階（P1，建議 ADR-024）

- **借什麼**：addyosmani 6 階段 SDLC（DEFINE→…→SHIP）+ 24 個單一職責小 skill 的**扁平可發現結構**，作為「ASP mega-skill 怎麼拆」的具體參照。
- **改哪些檔**：`asp-autopilot.md`（≈829 行）、`asp-gate.md`（≈419 行）拆成單一職責子 skill；`SKILL.md` 母路由補「階段→下一步」進度地圖（薄路由、不含工作流）。
- **依賴 ①（修正後論述）**：拆出的每個子 skill 須**各自通過 ① 的 schema lint（存在性/frontmatter 驗收）**作為「拆出來的東西仍是合格 skill」的機械門檻。⚠️ 注意：lint **驗不出「拆得對不對」（職責是否單一）**——那仍需人審（`asp:review-work`）；① 的 R6 行數 advisory 只能當「該拆」的信號，不能當「拆對了」的驗收。（此依賴關係為設計推導，非報告 §4 原文。）
- **落點**：P1（報告 §4② 標「併入 #39 §2 既有提案」；本路線建議獨立 ADR-024 以利單獨審查，與報告不衝突）。

## ③ plugin marketplace 為活證（補強 ADR-021，非新 ADR）

- **借什麼**：addyosmani **已在官方 Claude Code plugin marketplace** 跑同品類庫（skills + commands + hooks），是 ADR-021「低風險」判斷的現成第三方對照樣本。
- **怎麼做**：**不開新 ADR**——把 addyosmani 列為 ADR-021 Verification Evidence 的補強證據 / FC-004 殘留 POC 的對照樣本。
- **落點**：報告 §4③ 標「P1 / 強化 ADR-021」；本路線精確化為「**屬 ADR-021 補強證據，非新工作項**」（③ 不是新 skill，而是現成的活證據）。

## ④ scope 紀律量化為機械信號（P3，建議獨立 ADR）

- **借什麼**：addyosmani「scope 過大即警訊」的精神（具體數字僅見二手、一手未載，見報告 §4 註與 FC-005，故**只借精神不照搬數字**）。
- **怎麼做**：把 ASP 質性的「輕量改動」升為可偵測信號——`git diff` 檔數/行數超閾值 → 提示「可能是多任務、建議拆」。**advisory 非硬 gate**（避免偽硬 gate 撞 ADR-020）。
- **改哪些檔**：接既有 `asp-impact`；複用 metrics。與 ① 的 R6 行數 advisory **同源思路、作用對象不同**（① 管單一 skill 體積、④ 管一次 diff 的範圍）。
- **落點**：P3。獨立 ADR（P3 開時編號），須過 ADR-010 摩擦評估。

## ⑤ 規則 provenance（P3 條件式，建議獨立 ADR）

- **借什麼**：addyosmani 明引 Hyrum's Law / Beyoncé Rule 等讓「why/來源」可追溯。
- **怎麼做**：規則可選加「來源/why」欄（引 STRIDE/既有 ADR），附加於既有 `rule-hits` telemetry（`~/.claude/asp/metrics/rule-hits.jsonl`），**非新層**。
- **條件式**：僅在規則數成長到「追溯成本 > 維護成本」時啟動，且須過 ADR-022 複雜度棘輪（避免欄位/ADR 通膨）。
- **落點**：P3 條件式。獨立 ADR（P3 開時編號）。

---

## 執行節奏建議

1. **本批**（PR #50）：① ADR-023 Draft + POC + 本路線圖。等人類 `/asp:approve-adr ADR-023` 升 `Accepted` → 實作 ①。
2. **① Accepted 後**：起 ②（ADR-024，依賴 ① 的 lint 在位）。
3. **③**：隨時可補進 ADR-021 的補強證據（不阻塞）。
4. **P3 階段**（與 ADR-022 複雜度棘輪同期評估）：④ → ⑤（條件式）。

> 每項各自走 ADR 流程、需人類核准；本路線圖只排序與規劃，不升任何 ADR、不寫任何生產代碼。
