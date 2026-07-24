# 研究：ASP 向 mattpocock/skills 借鏡 —— 逐 skill 深度分析

> 日期：2026-07-24 ｜ 支撐 ADR：**ADR-030**（全局管理決策）｜ 事實查證：**FC-009**
> 方法：2 個 read-only Explore agent 讀完 `mattpocock/skills` 的 `engineering/` + `productivity/` + `misc/` 全部 `SKILL.md`（plugin v1.2.0，安裝於 `~/.claude/plugins/marketplaces/mattpocock/`），逐一套用「借用處置」框架。
> 本文為**逐 skill 詳析**（單一真相來源）；ADR-030 僅載策略、框架與摘要表並指向本文。

---

## 0. 前提與關鍵結構事實

- **ASP 與 Pocock 正交互補**：ASP 差異化＝enforcement substrate（hook 讓「跳過」機械可偵測，ADR-020）；Pocock 差異化＝可組合工程紀律 + **明確不奪走控制權**（反 GSD/BMAD/Spec-Kit）。→「純 skills 化」＝拆 enforcement＝丟護城河，否決。
- **grilling 家族 = 基底 + 兩個薄別名**：`grilling`（model-invoked，真正的訪談迴圈）；`grill-me`（user-invoked 別名，「Run a `/grilling` session.」）；`grill-with-docs`（user-invoked，「Run a `/grilling` session, using `/domain-modeling`.」）。即 **grill-with-docs = grilling ∘ domain-modeling**。
- **ASP 已 soft-depend `grill-with-docs`**：`asp-context` 列它為 trigger word、`docs/agents/domain.md` 指它為外部依賴。借用只是把既成依賴正式化。
- **重複安裝、版本漂移**：mattpocock/skills 已 user-global 安裝**兩份**（plugin `mattpocock-skills:*` v1.2.0 + 舊 loose copy `~/.agents/skills/` symlink，名稱較舊如 `to-issues`/`diagnose`），**未 wire 進 ASP repo**。命名空間與 `asp-*` 不撞。

### 借用處置框架
| 處置 | 意義 |
|---|---|
| **ALREADY-HAVE** | ASP 已有強等價物 → 交叉連結、至多挑點子 |
| **ADOPT** | 外部依賴、不複製（harness 中立的紀律） |
| **VENDOR** | 複製進 ASP repo、pin 版、過 `test_skill_lint.sh` |
| **ADAPT-MERGE** | 把想法融入指定既有 asp skill |
| **BUILD-ASP-NATIVE** | 治理耦合、ASP 自寫（有 enforcement 可掛） |
| **SKIP** | 超出 ASP 範圍 |

### 5 條貫穿整合規則
1. **ADR 格式漂移防護（最關鍵）**：grilling / domain-modeling 用 Matt 格式寫 ADR/CONTEXT.md。任何借用**只借訪談/紀律，書寫一律導回 `asp-plan`/`asp-context` 模板**，ASP 維持單一真相來源、過 lint。
2. **Invocation taxonomy**：仿 grill trio——一個 model-invoked 基底 + user-invoked 別名（零 context load）。VENDOR/ADAPT 的 model-invoked 者登記進 `asp` router；純 reference 設 user-invoked/零觸發。
3. **Lint 閘**：VENDOR / ADAPT-MERGE 產物須過 `tests/test_skill_lint.sh`（ADR-023）；ADOPT（外部依賴）不過 lint。
4. **分支豁免**：ADOPT 的 `prototype`/`research` 需 ship-gate 對 `prototype/*`、`research/*` 分支豁免，否則 enforcement 與丟棄式流程打架。
5. **淨複雜度（ADR-010/022）**：以「停止重造 + 採用外部 + SKIP 4 個」抑制新增；但 ⚠️ **VENDOR/ADAPT-MERGE 落地會增 ADR-022 棘輪的 `skills.total_lines`**（棘輪只量 `.asp/profiles`/`.claude/skills/asp`/`.asp/levels` total_lines，見 `asp-metrics.sh`，**不**量 `docs/adr`）→ **不預先宣稱棘輪軸 ≤0**，各 SPEC `make asp-metrics` 實測。`domain-modeling` 三準則降的是 **ADR 篇數**（可觀測、但**非**棘輪軸）。

---

## 1. ADOPT（外部依賴、填補真缺口）

### grilling（+ grill-me / grill-with-docs）
- **做什麼**：一次一題、relentless 訪談，沿**決策樹**逐 branch 解依賴；每題附**建議答**；可從環境查到的**事實自動查、不問**，只把**決策**丟給人；終止於「確認的共識」，未確認前不動手。`grill-with-docs` 額外在決策成形當下**即時**寫 glossary/ADR。
- **ASP 現況**：Assumption-Checkpoint（`global_core.md`）只是**一次性、批次、非對抗**（emit→stop→confirm）；**無**迭代對抗式訪談。互補而非競爭。
- **處置**：**ADOPT**（依賴 as-is），**不 vendor、不自寫**。
- **理由**：治理中立的互動 primitive，無 enforcement hook 可掛，自寫是 gold-plating（浪費 ADR-022 預算）；且 ASP 已 soft-depend。
- **整合**：作 `asp-plan` 前端供大型/模糊工作；Assumption-Checkpoint 續為預設輕量閘、grilling 為升級。**硬規則（規則 1）：只借訪談，決策成形後把 ADR/CONTEXT.md 書寫交回 `asp-plan`/`asp-context` 模板**——這是全報告最重要整合約束（否則兩套 ADR 模板打同一個 `docs/adr/`）。
- **摩擦**：全面套用會增訪談摩擦 → **bound 到大型工作**（opt-in）；對真正模糊的工作淨降 rework。未來若要「這計畫被 grill 過嗎」的 gate artifact，才考慮 BUILD-NATIVE（roadmap，非現在）。

### diagnosing-bugs
- **做什麼**：硬 bug 6 階段。**Phase 1 即精髓：先建可紅化 repro loop（一條已跑過、能驅動 bug 路徑並斷言確切症狀的指令）再談假設**（「若你在此指令存在前就讀 code 建理論，stop」）；再最小化、產 3–5 個可證偽假設、一次一變數插 `[DEBUG-xxxx]`、在正確 seam 修 + 回歸、清理、post-mortem。
- **ASP 現況**：**無**。dev-qa-loop 與 reality-checker/test-engineer 驗**結果**，不治**根因診斷**。
- **處置**：**ADOPT**。
- **理由**：「loop-before-hypothesis」正是 ASP 珍視的機械、可偵測跳過的紀律，且真缺口。
- **整合**：`asp` router 的「壞了」on-ramp；Phase 6 post-mortem「什麼能預防它」→ `asp-plan` ADR 觸發、「無好 seam＝發現」→ `asp-impact`。
- **摩擦**：**降**（取代無結構 debug）；無新治理物件，對 ADR-022 中性。

### prototype
- **做什麼**：丟棄式 code 回答設計問題（LOGIC：把 state machine 推過難例／UI：一 route 多變體 URL 切換）；規則：day-one 丟棄、一鍵跑、不持久化、免打磨、**做完 capture**（把驗證後的決策折回正式碼）。
- **ASP 現況**：**無**。`[spike]` 豁免是相關概念、非 skill。
- **處置**：**ADOPT**。
- **理由**：ASP 全缺；「capture 驗證後決策」直餵 ASP 決策記錄文化。
- **整合**：驗證後 snippet→`asp-plan` SPEC/ADR。**catch（規則 4）**：丟棄分支 commit 須豁免 ship-gate/Draft-ADR-擋-commit，否則 enforcement 打架。
- **摩擦**：**降**（取代 ad-hoc 亂試）；唯一新增是小 hook 豁免規則。

### research
- **做什麼**：起背景 agent 查**一手來源**（官方 docs/source/spec/first-party API，非二手；每個宣稱回溯到擁有它的來源），寫單一 md 引用每條，存 repo notes 慣例。
- **ASP 現況**：**無**（external-review 是跨廠商 code review；context 是領域詞彙）。
- **處置**：**ADOPT**。
- **理由**：便宜、harness 中立、「一手來源」精神＝`asp-reality-check` 的懷疑。
- **整合**：輸出→`asp-plan`/`asp-context`；同 prototype 的 `research/*` 分支豁免。
- **摩擦**：**降**（委外讀取 legwork、主線乾淨）。

### resolving-merge-conflicts
- **做什麼**：5 步——看 merge/rebase 狀態；**為每個衝突找一手來源（commit/PR/issue 原意）**；逐 hunk 保留雙方意圖、不可 `--abort`、不發明新行為；跑專案自動檢查；完成 merge。
- **ASP 現況**：`/asp:merge` 只做**乾淨** merge，不治**衝突 hunk 解析**。
- **處置**：**ADOPT**，從 `/asp:merge` 交叉連結。
- **理由**：小（921 bytes）、harness 中立、補 `/asp:merge` 缺口。
- **整合**：step 4「跑檢查」走 `asp-ship`/`asp-gate`。**張力**：其「never --abort」vs 鐵則「破壞性前停」——解衝突本身非破壞、但最終 commit 仍尊重 ship-gate 停點。
- **摩擦**：**降**，無新治理物件。

---

## 2. VENDOR / BUILD-NATIVE（複製進 repo，屬 enforcement 或共享基底）

### git-guardrails-claude-code ⭐（全套最乾淨借用）
- **做什麼**：裝一個 **PreToolUse Bash hook**，於執行前**擋**危險 git（`push`、`reset --hard`、`clean -f`、`branch -D`、`checkout .`/`restore .`）→ exit 2 + BLOCKED 訊息。
- **ASP 現況**：有 hook 強制力一般化 + `/asp:merge` 破壞前停，但**無**具體 git-blocking PreToolUse hook。
- **處置**：**VENDOR**（複製 script+wiring、訊息改 ASP 口吻、過 lint）；ASP hook 層若 bespoke 則 **BUILD-ASP-NATIVE**。
- **理由**：**這就是 ASP 思想的縮影**——讓禁止動作機械上不可能、非僅勸阻。屬 enforcement substrate，不該是「不保證裝了」的外部依賴。
- **整合**：接進 ASP `PreToolUse` 層（現有 `denied-commands.json` + `pretooluse-ship-gate.sh` 旁）；訊息用 ASP 鐵則語氣；過 `asp-skill-author` lint。
- **摩擦**：**降風險**且落在 ADR-022 預算內（它本身就是治理）。全套最清晰淨正向。

### codebase-design（條件式）
- **做什麼**：**架構詞彙層**——精確術語（module/interface/depth/seam/adapter/leverage/locality，「別用 component/service/API/boundary 替代」）；deletion test；「interface 即 test surface」；「一個 adapter＝假想 seam、兩個＝真 seam」。附 DEEPENING.md、DESIGN-IT-TWICE.md（起 3+ 平行 subagent、各給不同約束設計介面再比）。
- **ASP 現況**：**無**（`asp-context` 是**領域**詞彙；這是**架構**詞彙，正交軸）。
- **處置**：**VENDOR（條件）**——僅在採 ≥1 依賴它的 skill（如 improve-codebase-architecture）時才 vendor；否則 **SKIP**（守 ADR-010）。
- **理由**：是 tdd/diagnosing-bugs/improve-arch 共同倚賴的基底；pin 一次比每個借用 skill 各懸一個外部引用低耦合。
- **整合**：作 `asp-plan`（SPEC seam 設計）/`asp-impact`（adapter/seam 爆炸半徑）之下的詞彙 reference；design-it-twice 平行 subagent 可供 `asp-plan` 介面決策；過 lint。
- **摩擦**：**中性偏降**（reference、近零叫用成本；且**阻止** ASP 自造架構術語）。

### improve-codebase-architecture（條件、依賴 codebase-design）
- **做什麼**：掃**深化機會**（淺→深模組），以 git hot-spot 加權、用 deletion test，產**視覺 HTML 報告**（Tailwind+Mermaid、before/after、Strong/Worth-exploring/Speculative 徽章）寫 **OS temp（非 repo）**，再 grill 選中者。
- **ASP 現況**：**部分**（`asp-audit`＝治理健康；`asp-impact`＝依賴爆炸半徑；**無**架構深度重構維度）。
- **處置**：**ADOPT/VENDOR（獨立、條件）**，從 `asp-audit` 交叉連結；**依賴 codebase-design**。
- **理由**：獨立工作流（掃→報告→grill），併入 `asp-audit` 會臃腫；是 diagnosing-bugs「無好 seam」post-mortem 的自然接手。
- **整合**：報告寫 temp 已合 ASP「不污染 repo」；grill 迴圈用 `asp-context`/`asp-plan`（「把否決記成 ADR 免 review 再提」）。
- **摩擦**：**增**一 skill + codebase-design 依賴——僅在 ASP 要「enforcement 健康之外的架構品質維度」時才值得，否則依 ADR-010 延後。

---

## 3. ADAPT-MERGE（融入既有 asp skill，不新增競爭 skill）

### tdd → `asp-dev-qa-loop` + `asp-review-checklist`
- **做什麼**：red→green + 讓測試值得留的規則——**測公開介面行為**、**只測預先同意的 seam**（「寫測試前先寫下 seam 並與人確認」）、三反模式（implementation-coupled、**tautological**「斷言用與 code 同法重算期望值、by construction 必過」、horizontal slicing→改寫**垂直 tracer-bullet**）、「重構不在迴圈內（屬 review）」。
- **ASP 現況**：**部分**（dev-qa-loop/test-engineer/review-checklist 治**何時/是否**有測試，非**test-first 方法**與 seam 協定/反模式）。
- **處置**：**ADAPT-MERGE**——把 seam 協定 + 3 反模式融入 dev-qa-loop + review-checklist；不新增競爭 skill（免 router 歧義）。**tautological test 反模式**尤其該進 review-checklist。
- **整合**：「只測預先同意 seam→與人確認」對映 Assumption-Checkpoint；共用 codebase-design 的 **seam** 詞彙。
- **摩擦**：**降**（融入、無新 skill）；若當獨立 skill 採則**增** router surface → 融入、別加。

### domain-modeling → `asp-context`（主動紀律）+ `asp-plan`（ADR 三準則）
- **做什麼**：主動建模——挑戰與 glossary 衝突的術語、把模糊語 canonical 化、用邊例壓測、對照 code 找矛盾、**即時 inline** 更新 CONTEXT.md（純 glossary、無實作細節）、**ADR 三準則**才提 ADR（**難逆 ∧ 意外 ∧ 真權衡**）。
- **ASP 現況**：**強等價**（`asp-context` 維 CONTEXT.md、`asp-plan` 寫 ADR），但缺「挑戰/sharpen」主動迴圈與 ADR-worthiness 濾網。
- **處置**：**複合——ALREADY-HAVE（書寫面：CONTEXT.md/ADR 由 `asp-context`/`asp-plan` 已覆蓋，無需借）+ ADAPT-MERGE（三準則融入 `asp-plan`）**。（本節置於 §3 是因唯一可執行的借用動作＝「三準則 MERGE」；§6 摘要表據此在兩列各列一半。）
- **理由**：**三準則直接反制 ASP 最大結構風險**——因 Draft-ADR **擋 commit**，ASP 有 ADR 灌水的結構誘因；worthiness gate 正是 ADR-022 要的護欄。
- **整合**：挑戰/sharpen prompt 融入 `asp-context`；三準則作 `asp-plan` scaffold ADR 前置條件；「CONTEXT.md 純 glossary」設 lint 檢查。
- **摩擦**：**降**——ADR 濾網實測降治理量。

### to-tickets → `asp-plan`（ROADMAP）+ `asp-autopilot` + `asp-impact`
- **做什麼**：把 plan/spec 拆**垂直 tracer-bullet 切片**（每片切穿各層、一個 fresh context window 能裝完）、宣告 **blocking edges**、走 **frontier**（blocker 已完成者）；寬重構用 **expand→migrate-in-batches→contract**（依爆炸半徑排序保 CI 綠）。
- **ASP 現況**：**部分**（autopilot 跑 ROADMAP、plan 產計畫，但無垂直切片/blocking edge/expand-contract 明文）。
- **處置**：**ADAPT-MERGE**。
- **理由**：ROADMAP 得垂直切片與依賴邊之嚴謹；**expand-contract 寬重構**尤有價值、直連 `asp-impact`。
- **整合**：「垂直切片、可 demo、一 context window」作 ROADMAP-item 驗收準則；用 `asp-impact` 判是否寬重構。
- **摩擦**：**微增、淨正**（融入既有、無新物件；expand-contract 免「大爆炸重構破壞一切」）。

### wayfinder → `asp-plan`（僅概念）
- **做什麼**：把「大到一個 session 裝不下」的工作規劃為**決策 ticket 的共享地圖**（`wayfinder:map`）——「問題的解是**決策**、非要執行的 build 切片」；「Plan, don't do」；一 ticket 一 session；**fog of war**（未指定隨 frontier 前進才升為 ticket）；**Out of scope 永不升級**；霧散後交 `/to-spec`。
- **ASP 現況**：**部分/無**（autopilot 是**執行**迴圈，無**霧中決策映射**規劃器）。
- **處置**：**ADAPT-MERGE（僅概念）**——借 decision-vs-execution ticket + fog-of-war + out-of-scope-never-graduates 進 `asp-plan` 大型模式；**SKIP 整套 map 機器**。
- **理由**：概念對綠地規劃有力，但整套 map+native-blocking+one-decision-per-session 是「最耗認知的流程」、重子系統、與 plan+autopilot+ROADMAP 重疊。
- **摩擦**：整套 vendor 會**大增**複雜度（ADR-022 最大風險）→ 只借詞彙/概念。

### writing-great-skills → `asp-skill-author`
- **做什麼**：reference（無步驟）——好 skill 的詞彙/理論：invocation taxonomy（model/user-invoked、router skill）、兩種 load（context load / cognitive load）、資訊層級 + progressive disclosure、**leading words**、失敗模式（premature completion、duplication、sediment、sprawl、no-op、negation）。
- **ASP 現況**：**部分**（`asp-skill-author` 是 **lint-gated 機械**、但缺此設計**理論**）。
- **處置**：**ADAPT-MERGE**（把詞彙/失敗模式清單融入 asp-skill-author reference）；退路 VENDOR 為 companion。
- **理由**：ASP 已用 lint 強制 skill 品質，補「為什麼」讓 authored skill 一次過 lint。
- **摩擦**：**降**（少跑幾輪 lint、skill 更緊）。強合 ADR-010。

### handoff → `asp-autopilot`（session-checkpoint）
- **做什麼**：把對話壓縮成 handoff 文件（**OS temp**）給 fresh agent；含「suggested skills」、redact 機密、**reference 而非複製**既有 artifact。
- **ASP 現況**：**部分/強**（autopilot `make session-checkpoint` + `/asp:review-work`）。
- **處置**：**ADAPT-MERGE**（借 redaction + suggested-skills + reference-don't-duplicate 進 session-checkpoint）；機制本身 ALREADY-HAVE。
- **理由**：ASP 有機制、但 temp-dir 目標 off-brand——ASP 要 tracked/可強制 artifact，非 ephemeral temp 檔。
- **摩擦**：**降**（checkpoint 更好、無新 skill）。

### setup-matt-pocock-skills → ASP setup / `asp-level`
- **做什麼**：prompt 驅動的 per-repo bootstrap：explore→present→confirm→write，一段一段；配 issue tracker、triage 標籤、domain-doc 版面；寫 `docs/agents/*.md` + CLAUDE.md 的 `## Agent skills` 區塊。
- **ASP 現況**：**部分**（有 `asp-level` + 自己的 install；且**此 skill 產的 `docs/agents/domain.md` 正是 `asp-context` 已消費的**）。
- **處置**：**ADOPT** 其 domain.md 產出；**ADAPT-MERGE**「一段一段、先給建議答、寫前確認」UX 進 ASP-native setup/`asp-level`。
- **摩擦**：中性偏降（形式化既有依賴）。

---

## 4. ALREADY-HAVE（ASP 已有、只挑點子）

### code-review → `asp-review`(+checklist)
- **挑點子**：把 **12-smell Fowler 基線**（Mysterious Name、Duplicated Code、Feature Envy、Data Clumps、Primitive Obsession…，各「是什麼→怎麼修」）作**判斷型 heuristic**（非硬違規）進 `asp-review-checklist`；加 **Standards-vs-Spec 雙軸**（分開報告、免一軸遮另一軸）。ASP 已有「repo 標準覆蓋基線、略過工具強制項」。
- **摩擦**：中性（additive checklist bullet、無新 skill/gate）。

### to-spec → `asp-plan`
- **挑點子**：**seam-sketch**（「理想 seam 數＝1」）與明確 **Testing Decisions** 段融入 `asp-plan` SPEC。`asp-plan` 已擁 SPEC，別 fork。

### implement → `asp-ship`/dev-qa-loop/gates
- **ALREADY-HAVE（等於 SKIP 借用）**：Pocock `implement` 是慣例型 orchestrator；ASP 版是同形但**機械強制**的超集。借用只會加冗餘 surface、與 gate bookkeeping 衝突。僅為 Pocock 心智模型的使用者交叉連結。

### ask-matt → `asp` router
- **挑點子**：加**敘事 flow-map**（pipeline plan→ship→gate→review→release + on-ramps）進 `asp` router SKILL.md（保雙語 trigger）；**smart-zone/context 衛生**（把 grill→spec→tickets 收在單一 ≤120k window）值得原樣偷給 `asp-autopilot`（ROADMAP item 間何時清 context）。
- **摩擦**：**降**（可導航性、doc-only）。

---

## 5. SKIP

| Skill | 為何 SKIP |
|---|---|
| **triage** | issue intake 子系統（labels、`.out-of-scope/` KB、PR 作請求面）與 ASP enforcement 核心正交；整套引入＝為 ASP 不擁的關切 import 一整套詞彙/KB。**專案可選**：要 intake 時其 `ready-for-agent` 輸出可乾淨餵 autopilot，但別進強制核心。 |
| **setup-pre-commit** | Husky+lint-staged+Prettier+typecheck 的 **npm 專屬**實作；commit-time-gate **概念** ASP 已原生擁有（asp-ship + gate hook）、且語言中立。 |
| **scaffold-exercises** | 綁 Matt 課程工具（`ai-hero-cli`），零治理相關。 |
| **migrate-to-shoehorn** | 窄 TS 測試 codemod（`@total-typescript/shoehorn`），非治理能力。 |

---

## 6. 摘要處置表

| 處置 | Skills |
|---|---|
| **ADOPT** | grilling(+grill-me/grill-with-docs, opt-in)、diagnosing-bugs、prototype、research、resolving-merge-conflicts |
| **VENDOR / BUILD-NATIVE** | git-guardrails-claude-code ⭐、codebase-design（條件）、improve-codebase-architecture（條件、依賴 codebase-design） |
| **ADAPT-MERGE** | tdd→dev-qa-loop/checklist、domain-modeling→context/plan（三準則）、to-tickets→plan/autopilot、wayfinder(概念)→plan、writing-great-skills→skill-author、handoff→autopilot、setup-matt-pocock-skills→setup/level |
| **ALREADY-HAVE** | code-review、to-spec、implement、ask-matt、domain-modeling(書寫面) |
| **SKIP** | triage、setup-pre-commit、scaffold-exercises、migrate-to-shoehorn |

**最高價值、最低摩擦**（清缺口、無治理臃腫）：`diagnosing-bugs`、`prototype`、`research`（皆 ADOPT、皆降複雜度、僅需 `prototype/*`+`research/*` 分支 hook 豁免）。
**最高槓桿的複雜度*減少*器**：`domain-modeling` **三準則**融入 `asp-plan`（反制 Draft-ADR-擋-commit 造成的 ADR 灌水）。
**最清晰的 enforcement 借用**：`git-guardrails-claude-code`（VENDOR/BUILD-NATIVE）。
**最大 ADR-022 風險**：`wayfinder` 整套 map 機器 → 只借概念。

---

## 7. deprecated / in-progress / personal（僅列一行，不分析）

**deprecated/**：`design-an-interface`（平行 subagent 設計多介面）、`qa`（對話式回報 bug 開 issue）、`request-refactor-plan`（訪談式小 commit 重構計畫）、`ubiquitous-language`（抽 DDD glossary，已被 domain-modeling 取代）。
**in-progress/**：`batch-grill-me`（一輪問完 frontier 全部問題）、`claude-handoff`（交給 fresh **背景** agent）、`loop-me`、`setup-ts-deep-modules`、`to-questionnaire`、`wizard`、`writing-beats/fragments/shape`。
**personal/**：`edit-article`、`obsidian-vault`。

**Watch（值得 ASP 一瞥）**：
- `batch-grill-me` —— 介於「一次性 Assumption-Checkpoint」與「完整迭代 grilling」之間的中間態，或可作 ASP 的中量級 checkpoint。
- `claude-handoff` —— 背景 agent 交接，比 temp-file `handoff` 更接近 `asp-autopilot` 模型。

---

## 8. 與 ASP 治理鐵則的自洽（ADR-010 / ADR-022）
- **ADR-010（最小採納/摩擦評估）**：4 個 SKIP + 多數 ADOPT（外部依賴、零維護）+ 融入而非新增，皆通過。條件式（codebase-design/improve-arch）明確標「僅在採依賴者時」。
- **ADR-022（治理複雜度預算棘輪）**：⚠️ 棘輪機械量測的是 `.asp/profiles`、`.claude/skills/asp`、`.asp/levels` 的 total_lines（見 `asp-metrics.sh:47-49,251-252`），**不**量 `docs/adr`/`docs/research`。故：ADOPT（外部依賴）不增這些軸；但 **VENDOR（×3）+ ADAPT-MERGE（×7 融入既有 asp-* skill）會增 `skills.total_lines`**——**不宣稱棘輪軸 ≤0**，須各 SPEC 落地時 `make asp-metrics` 實測，並以 SKIP 4 個抑制。`domain-modeling` 三準則降的是 **ADR 篇數**（可觀測、但非棘輪軸）。`wayfinder` 整套已降為「僅概念」以避大增。

## 9. 關聯
- **ADR-030**（本文的管理決策）、**ADR-028**（pi 替代 harness，同「內容可攜/enforcement adapter」軸）、**ADR-020**（AI 遺忘/機械強制＝護城河依據）、**ADR-010/022**（反過度設計自證）、**ADR-023/024**（skill lint / 生命週期）。
- **FC-009**（maka + mattpocock/skills 事實查證）。
