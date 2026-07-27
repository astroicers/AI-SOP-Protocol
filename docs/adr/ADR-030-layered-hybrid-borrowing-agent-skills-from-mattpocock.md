# [ADR-030]: Layered hybrid — 逐 skill 借鏡 mattpocock/skills；可攜 Agent Skills 內容 + 每 harness enforcement adapter

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-07-24 |
| **決策者** | ASP framework maintainers（人類 2026-07-24 核准直升） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）
>
> **[2026-07-24 升級記錄]** `Draft → Accepted`：經人類透過 `/asp:approve-adr 030` 於本日明確授權直升（「確認直升」）。本 ADR 為**評估／策略型**——Accepted 的是**方向**（選項 B 分層 hybrid + 逐 skill 借用處置框架），**不含生產代碼**；各借用實作仍待後續 SPEC（首個 POC：git-guardrails 借用 SPEC）。直升**跳過 FIRM 的 POC 驗證**，檔尾 Verification Evidence 四欄留白，將由各借用 SPEC 於實作時回填。

---

## 背景（Context）

延續 ADR-028（pi 作為替代 enforcement harness），評估重新展開，新增兩條線：(1) 把 **maka**（`maka-agent/maka-agent`）納入 harness 地景；(2) ASP 是否向 **mattpocock/skills**（Agent Skills 典範）借鏡——「純 skills 化」或其他整合，尤其 `grill-with-docs` 等值得學。

**核心策略洞察**：ASP 與 mattpocock/skills **哲學相反、正交互補**——
- ASP 差異化 = **enforcement substrate**（hook 讓「跳過」機械可偵測：Draft-ADR 擋 commit、ship-gate、G1–G6 bookkeeping、四鐵則）＝ADR-020「AI 遺忘為一級威脅」的落地。
- Pocock 差異化 = **可組合工程紀律 + 明確不奪走控制權**（反 GSD/BMAD/Spec-Kit）。
- 一句話：**ASP 管「不准跳過流程」，Pocock 管「流程內容怎麼做得好」。**
- ∴「純 skills 化 = 拆 enforcement = 變成另一個 Pocock」，丟掉護城河，且 enforcement 正是 ADR-028 認定綁死 Claude Code 那層 → 否決。

**與 ADR-028 收斂到同一個軸**：Pocock 用 **Agent Skills 標準（`SKILL.md`）= 跨 harness 可攜**。北極星：**內容層 → Agent Skills 標準（可攜、可與 Pocock 組合）；enforcement 層 → 每 harness 一個 adapter（ASP 核心）**。

**已完成逐 skill 深讀**：2 個 read-only Explore agent 讀完 mattpocock/skills `engineering/`+`productivity/`+`misc/` 全部 `SKILL.md`，逐一套「借用處置」框架。**完整逐 skill 詳析見 `docs/research/2026-07-24-mattpocock-skills-deep-borrow.md`（單一真相來源）**；本 ADR 只載策略、框架、摘要與跨切規則。

**關鍵事實**（見研究文件 §0、FC-010）：ASP 是扁平命名空間 + 意圖路由，**無** Pocock 的 user/model invocation 分層；`grilling` 是真缺口且 ASP 已 soft-depend `grill-with-docs`；mattpocock/skills 已 user-global 安裝**兩份、版本漂移、未 wire 進 repo**。

### Harness 地景（含 maka watchlist）
| Harness | 狀態 | 對 ASP 的意義 |
|---|---|---|
| Claude Code | 現任、primary | enforcement 全落地；ASP 護城河所在 |
| pi（ADR-028） | 已評估、中等 adapter 工作量 | 內容近原樣可攜；enforcement 需 adapter |
| **maka** | **watchlist（早期）** | 見下 |

**maka watchlist（FC-010，誠實邊界）**：README 明載——local-first workspace（Electron+TUI+CLI+headless，TS）、**有 permission engine**（「File writes, Shell, and dangerous tool calls pass through the permission engine」，利 L1.5/L2 deny）、支援 **API key + 訂閱 OAuth**（Claude/Codex/Copilot/Cursor）、「run from source / under active development」。**NOT STATED（標 unknown）**：SKILL.md / Agent Skills 標準、subagents、擴充可訂閱的 hook/lifecycle、讀 CLAUDE.md、Claude Code 相容。→ maka 於「內容=Agent Skills 可攜」這條**比 pi 弱**（無明載 Agent Skills 支援），但 permission engine 對 enforcement 是加分。**未達 ADR-028 式完整逐層對應成熟度 → 列 watchlist，成熟後再評。**

---

## 評估選項（Options Considered）

### 選項 A：純 skills 化（拆掉 enforcement，ASP 變純 skill bundle）
- **優點**：極簡、天生跨 harness 可攜、與 Pocock 生態無縫。
- **缺點**：丟掉 enforcement 護城河與 ADR-020 機械強制；正是 ADR-028 認定綁 Claude Code 的那層。**否決**。
- **風險**：ASP 失去存在理由。

### 選項 B（建議）：分層 hybrid + 逐 skill 借用處置框架
- **優點**：enforcement 核心保留為每 harness adapter（續 ADR-028）；可攜內容遷 Agent Skills 標準、引入 user/model 分層；**逐 skill** 決定 ADOPT/VENDOR/ADAPT-MERGE/ALREADY-HAVE/SKIP，多為淨簡化（停止重造 + 採用）。
- **缺點**：維護兩套 harness 綁定（內容共用）；外部依賴版本漂移；遷移成本。
- **風險**：格式漂移（Pocock 與 ASP 兩套 ADR 模板）——由跨切規則 1 防護。

### 選項 C：選擇性借鏡（只挑幾個 vendor、不動結構）
- **優點**：最小改動。
- **缺點**：不設北極星，錯過「內容標準化提升可攜」與生態組合的槓桿。**為 B 的第一步子集，不作為終點。**

### 選項 D：維持現狀（續 soft-reference）
- **優點**：零工作量。
- **缺點**：兩份重複安裝的漂移不治、grilling 依賴不正式、內容不可攜。

---

## 決策（Decision）

採 **選項 B**，狀態 `Draft`、待人類核准。子決策：
- **(a)** 北極星＝content（Agent Skills 標準）/ enforcement（每 harness adapter）分層。
- **(b)** 採用**逐 skill 借用處置框架**；**摘要處置表**（下）為決策快照，**細節以研究文件為單一真相來源**。
- **(c)** 五條跨切整合規則（見下），**尤其規則 1「ADR 格式漂移防護」**：任何借用只借訪談/紀律，ADR/CONTEXT.md 書寫一律導回 `asp-plan`/`asp-context` 模板。
- **(d)** 為 asp skill 引入 **user-invoked 編排 / model-invoked 紀律** invocation taxonomy。
- **(e)** 清理兩份重複 mattpocock 安裝（版本漂移）。
- **(f)** maka 列 watchlist（不做完整對應）。
- **(g)** **實作全部延到後續 SPEC**（e.g. `spec: borrow-grilling-and-git-guardrails`、`spec: asp-plan-adr-3-criteria`、`spec: asp-skills-standard-migration`、`asp-pi-adapter`〔ADR-028〕）。Draft→Accepted 不解除「無 SPEC 前禁止實作」。

### 摘要處置表（快照；細節見研究文件）
| 處置 | Skills |
|---|---|
| **ADOPT**（外部依賴、填缺口） | grilling(+grill-me/grill-with-docs, opt-in)、diagnosing-bugs、prototype、research、resolving-merge-conflicts |
| **VENDOR / BUILD-NATIVE**（屬 enforcement/共享基底） | git-guardrails-claude-code ⭐、codebase-design（條件）、improve-codebase-architecture（條件） |
| **ADAPT-MERGE**（融入既有 asp skill） | tdd、**domain-modeling（三準則）**、to-tickets、wayfinder(概念)、writing-great-skills、handoff、setup-matt-pocock-skills |
| **ALREADY-HAVE**（挑點子） | code-review（12-smell+雙軸）、to-spec（seam-sketch）、implement、ask-matt（flow-map+smart-zone）、**domain-modeling（書寫面）** |

> `domain-modeling` 為**複合處置**：書寫面（CONTEXT.md/ADR）ALREADY-HAVE（asp-context/asp-plan 已覆蓋）；三準則 ADAPT-MERGE 入 asp-plan。故上表兩列各列一半（詳研究文件 §3）。
| **SKIP** | triage、setup-pre-commit、scaffold-exercises、migrate-to-shoehorn |

### 五條跨切整合規則
1. **ADR 格式漂移防護（最關鍵）**：只借訪談/紀律，書寫導回 ASP 模板、過 lint。
2. **Invocation taxonomy**：model-invoked 基底 + user-invoked 別名（零 context load）；model-invoked 者登記進 `asp` router。
3. **Lint 閘**：VENDOR/ADAPT-MERGE 過 `tests/test_skill_lint.sh`（ADR-023）；ADOPT 不過 lint。
4. **分支豁免**：`prototype`/`research` 需 ship-gate 對 `prototype/*`、`research/*` 分支豁免。
5. **淨複雜度**：以「停止重造 + 採用外部 + SKIP 4 個」抑制；⚠️ **VENDOR/ADAPT-MERGE 落地會增 ADR-022 棘輪的 `skills.total_lines`**（棘輪不量 `docs/adr`），**不預先宣稱 ≤0**、各 SPEC `make asp-metrics` 實測；`domain-modeling` 三準則降的是 ADR 篇數（非棘輪軸）。

---

## 後果（Consequences）

**正面影響：**
- 少重造輪子、內容跨 harness 可攜、與生態可組合；`git-guardrails` 補強 enforcement；`domain-modeling` 三準則降 ADR 灌水。
- 把「已 soft-depend `grill-with-docs`」正式化、消除兩份安裝漂移。

**負面影響 / 技術債：**
- 外部依賴版本漂移（兩份安裝為前車之鑑）；ADR 格式漂移風險（由規則 1 防護）；invocation taxonomy 重整 churn；須守住 enforcement 護城河不被稀釋。

**後續追蹤：**
- [ ] 若核准 → 開各 SPEC（借 grilling+git-guardrails、asp-plan 三準則、Agent Skills 標準遷移、taxonomy 重整、清重複安裝）。
- [ ] maka 成熟後再評完整逐層對應。

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 逐 skill 處置涵蓋率 | 100%（engineering+productivity+misc 全覆蓋） | 研究文件 §6 摘要表 | 本 ADR（已達） |
| ADR 格式漂移防護落地 | bool＝true（借用只走 ASP 模板書寫） | SPEC 實作 + lint | borrow SPEC |
| 兩份重複安裝去重 | bool＝true | `~/.claude/plugins` 與 `~/.agents/skills` 盤點 | cleanup SPEC |
| ADR 篇數（domain-modeling 三準則融入後） | 下降（可觀測指標，**非** ADR-022 棘輪軸） | ADR 計數 | 融入後 90 天 |
| `skills.total_lines`（ADR-022 真正棘輪軸） | **不宣稱 ≤0**——VENDOR×3 + ADAPT-MERGE×7 融入既有 skill 預期**增**，各借用 SPEC 落地時 `make asp-metrics` 實測；以 SKIP 4 個抑制 | `asp-metrics.sh` | 各借用 SPEC |

**重新評估條件**：mattpocock/skills 改版（skill 增刪/重命名）、maka 成熟到可完整對應、或 ASP enforcement 架構變更時，須重審本 ADR 與研究文件。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - **`docs/research/2026-07-24-mattpocock-skills-deep-borrow.md`** —— 逐 skill 詳析（本 ADR 的細節單一來源）。
  - **ADR-028**（pi 替代 harness）——同「內容可攜 / enforcement adapter」軸。
  - **ADR-020**（AI 遺忘 / 機械強制）——「純 skills 化否決」與「保留 enforcement 護城河」的依據。
  - **ADR-010**（最小採納 / 摩擦評估）——本案多為淨簡化，須通過。
  - **ADR-022**（治理複雜度預算棘輪，量測 `profiles`/`skills`/`levels` 的 total_lines）——ADOPT 外部不增棘輪軸；但 VENDOR/ADAPT-MERGE 落地會增 `skills.total_lines`，**不宣稱 ≤0**、各 SPEC 實測，以 SKIP 4 個抑制；三準則降的是 ADR 篇數（非棘輪軸）。
  - **ADR-016**（compiled profile）、**ADR-023/024**（skill lint / SDLC 生命週期）——內容遷移與 taxonomy 的落點。
  - **FC-010**（maka + mattpocock/skills 事實查證）。

---

## Verification Evidence（升級至 FIRM 時必填）

| 欄位 | 內容 |
|------|------|
| POC 分支／測試結果 | （待人類核准後，於借用 SPEC 補：git-guardrails hook 實測擋危險 git、grilling 前端 + 書寫導回 ASP 模板 POC、prototype/research 分支豁免 POC） |
| 驗證日期 | — |
| 驗證者 | — |
| 驗證摘要 | — |
