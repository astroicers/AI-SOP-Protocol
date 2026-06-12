<!-- Last Updated: 2026-06-12 | Status: Draft (Deferred) | Related ADR: ADR-008 | Note: 實作延後，全部測試列 Stage 2 PENDING（見文末），Stage 2 落地前不謊報 executable -->
# SPEC-005：asp-diagram skill — Mermaid 架構圖管理

> 結構完整的規格書讓 AI 零確認直接執行。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-005 |
| **關聯 ADR** | ADR-008 |
| **估算複雜度** | 中 |
| **建議模型** | Sonnet（路由邏輯 + 模板，無重 IO） |
| **HITL 等級** | standard（與既有 asp-* skill 一致） |

---

## 🎯 目標（Goal）

建立 `asp-diagram` skill，把 Mermaid 圖文件納入 ASP 治理層；支援 Mode A（初始化掃描 + 建索引，預設不搬家）、Mode B（git diff 偵測架構變動後同步單張圖，含明確映射演算法）、Mode C（校對圖與程式碼差異，CI 友善的 `--strict` 模式），並掛入 `asp-plan`（Step 5 提示）與 `asp-ship`（Step 9.5 WARN，明確 include/exclude glob）執行流程。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| `mode` | enum `A` / `B` / `C` | trigger word 或 CLI 參數 | 缺省由 trigger word 判斷；多重匹配時詢問 |
| `target` | path \| `auto` | CLI 或自動偵測 | Mode B/C 可指定單張圖檔；Mode A 全掃 `docs/` |
| `since_ref` | git ref | optional | Mode B 預設 `HEAD~1`，可改 `main` / `origin/main` |
| `dry_run` | bool flag | CLI | 預覽變更，不寫檔（Mode A/B） |
| `strict` | bool flag | CLI | Mode C 專用：發現任一 drift 即 exit 1（給 CI 用） |

---

## 📐 核心演算法定義（決定 Mode A/B/C 可否 deterministic 執行）

### Algo-A：Mode A 「架構檔」識別 + slug 規則

**Step 1 — 架構檔 glob（按優先序）：**

```
INCLUDE_GLOBS=(
  "docs/architecture.md"
  "docs/multi-agent-architecture.md"
  "docs/adr/ADR-*.md"
  "docs/specs/SPEC-*.md"
  ".asp/profiles/*.md"
  ".asp/agents/*.yaml"
  ".asp/templates/architecture_spec.md"
)
EXCLUDE_GLOBS=(
  "docs/archive/**"
  "**/CHANGELOG.md"
)
```

**Step 2 — Mermaid 區塊抽取：**
- 對每個 INCLUDE 命中的檔案，用 `awk '/```mermaid/{flag=1;n++;print FILENAME":"n":"NR;next}/```/{flag=0}'` 列出「檔案 + 區塊序號 + 起始行號」。
- 每個 mermaid 區塊 = 1 個索引條目。
- 圖種偵測：抓第一個非空 token（`flowchart` / `sequenceDiagram` / `stateDiagram-v2` / `graph` / `gantt`），無法判定則標 `unknown`。

**Step 3 — Slug 規則（idempotent）：**
- Source file path → slug：`{path}` 中 `/` 換 `-`、`.md/.yaml` 移除、小寫、不含序號。
- 多區塊在同檔：`{slug}-block-{n}`（n 從 1 起）。
- 範例：
  - `docs/architecture.md` block 1 → `architecture-block-1`
  - `.asp/profiles/autopilot.md` 唯一區塊 → `asp-profiles-autopilot`
- **Mode A 預設 index-only**：只在 `docs/diagrams/README.md` 加 inline 連結 `[architecture-block-1](../architecture.md#L25)`，**不創建** `docs/diagrams/architecture-block-1.md`。
- **`--create` 旗標（opt-in）**：用此 slug 為新建 `docs/diagrams/{slug}.md` 的檔名，套用 `DIAGRAM_Template.md`。

### Algo-B：Mode B file → diagram 映射（按優先序，命中即停）

```
For each changed file `F` in `git diff --name-only $since_ref HEAD`:

  Priority 1 — Frontmatter 反查：
    對 docs/diagrams/*.md 逐一讀 frontmatter；若任一檔的 `source_files:` 列表
    含 `F` 的完整路徑或前綴 → 命中該圖檔。

  Priority 2 — Slug 反推：
    用 Algo-A Step 3 規則由 `F` 推出候選 slug；
    若 `docs/diagrams/{slug}.md` 或 `docs/diagrams/{slug}-block-*.md` 存在 → 命中。

  Priority 3 — 路徑 last segment 匹配：
    取 `F` 的 basename（去副檔名），檢查 `docs/diagrams/*{basename}*.md` 是否存在。

  若三層全 miss → 加入 unmatched 清單，最後印「找不到對應圖：F → 建議跑 Mode A --create」。
```

**多檔變更**：對每個 changed file 獨立跑映射；若同一張圖被多檔命中 → 只更新一次但合併 `source_files`。

### Algo-C：Mode C drift 偵測（明確區分機械可驗證 vs AI 啟發式）

**機械層（可在測試中 assert）：**
- 圖檔 frontmatter `source_files` 列出的檔案是否仍存在？不存在 → 報 `MISSING_SOURCE`（drift type 1）。
- `source_files` 中任一檔的 git history（`git log --follow`）顯示已重命名 → 報 `RENAMED_SOURCE`（drift type 2，不算誤報）。
- 圖檔 `last_updated_commit` hash 之後，`source_files` 列出的檔案有新 commit → 報 `STALE_SINCE_COMMIT`（drift type 3，提示候選但不確定真有 drift）。

**啟發式層（AI 判斷，標明為 advisory）：**
- 圖中提到的節點名稱（如「dispatch」「converge」）若無法在 `source_files` 內 grep 到 → 報 `LABEL_NOT_FOUND_ADVISORY`（drift type 4，**標 advisory，使用者需自行判斷**）。
- 此層不在自動測試覆蓋範圍；testing 只驗 drift types 1-3。

**Exit code：**
- 預設：exit 0（純報告，drift count 印於 stdout）。
- `--strict`：drift types 1-3 任一發生 → exit 1；type 4 advisory 不觸發 exit 1（因為 AI 判斷不穩定）。

### Algo-S95：Step 9.5 觸發 glob

**Include（任一檔在 `git diff --cached --name-only` 命中）：**
- `docs/architecture.md`
- `docs/multi-agent-architecture.md`
- `.asp/profiles/*.md`
- `.asp/agents/*.yaml`

**Exclude（即使 include 命中也跳過）：**
- ADR / SPEC **僅修改 Status 行**：用 `git diff --cached -U0 docs/adr/*.md docs/specs/*.md` 抽 +/- 行，若所有非 `^[+-]{3}` 變更行匹配 `^[+-]\| \*\*狀態\*\*` 或 `^[+-]Status:` → 視為 status-only 變更，跳過。
- `docs/archive/**` 全部排除。
- 純註解或空白行變更（diff 後 trim 為空）→ 排除。

**輸出**：
- 命中 → 印 WARN：「偵測到架構檔變動：{file_list}。建議跑 `/asp-diagram Mode B`。」
- 不 BLOCK，不影響 commit 流程。

---

## 📤 輸出規格（Expected Output）

**Mode A 成功（預設 index-only）：**
- 建 `docs/diagrams/README.md` 索引（一行一張，含 inline 連結到 source file）。
- 不創建 `docs/diagrams/{slug}.md`（除非 `--create` 旗標）。
- console 印「索引建立：{count} 條，跨 {file_count} 檔案」。

**Mode A 成功（`--create` 旗標）：**
- 為每個未存在的 slug 創建 `docs/diagrams/{slug}.md`，套用 `.asp/templates/DIAGRAM_Template.md`，frontmatter 填：
  ```yaml
  ---
  title: <auto-derived from source heading or slug>
  diagram_type: <flowchart|sequenceDiagram|stateDiagram-v2|graph|gantt|unknown>
  source_files:
    - <source file path>
  last_updated_commit: <git rev-parse HEAD>
  last_updated_date: <YYYY-MM-DD>
  ---
  ```

**Mode B 成功：**
- 更新單一目標檔的 mermaid 區塊（**保留其他段落**：Notes、Updated、frontmatter 其他欄位）。
- 重寫 `last_updated_commit` + `last_updated_date`。
- console 印「更新了 {file} 的 mermaid 區塊（{n} 行），保留 {m} 段落原文」。

**Mode C 成功（預設）：**
- 列差異報告，每行格式：`{drift_type}: {圖檔} ↔ {source}:{line} — {說明}`。
- exit code 0（純報告）。

**Mode C 成功（`--strict`）：**
- drift types 1-3 任一發生 → exit 1。
- type 4 (advisory) 不影響 exit code。

**失敗情境：**

| 錯誤類型 | 處理方式 |
|----------|----------|
| `docs/diagrams/` 不存在（Mode B/C） | 提示「請先跑 `/asp-diagram Mode A`」；exit 1 |
| Mermaid 語法錯誤 | `make diagram-lint` 列檔名 + 行號；exit 1 |
| Mode B 找不到對應圖（三層映射皆 miss） | 列建議檔名 + 「跑 Mode A --create」；exit 1 |
| `git diff` 範圍為空（Mode B） | 印「無架構變動」；exit 0 |
| In-skill gating 偵測到非 ASP 上下文（如「database schema diagram」） | 印「此請求看似非 ASP 架構圖，建議改用通用 mermaid 工具；若仍要繼續請加 `--force`」；exit 0 |

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| 新增/修改 `docs/diagrams/*.md` | Mode A `--create` / B | `make doc-audit` | `make diagram-lint` + `git diff` 確認非目標段落零變動 |
| 新增 `docs/diagrams/README.md` | Mode A 首次 | 圖總索引 | `grep -c '^- ' docs/diagrams/README.md` ≥ 11 |
| `asp-ship` 多一步 Step 9.5（WARN 級） | 每次 commit（命中 Algo-S95 include glob 且未被 exclude） | 提交流程 | `tests/test_asp_ship_step95.sh`（驗 include 觸發 + exclude 跳過 + status-only 跳過） |
| `asp-plan` Step 5 結尾多一句提示 | 每次規劃完 ADR/SPEC | 規劃流程 | grep `asp-plan.md` 文字 |
| `SKILL.md` router 新增一列 | 一次性 | trigger word 路由 | `tests/test_skill_router_diagram.sh`（驗新列存在 + trigger 命中 + in-skill gating 有效） |
| `Makefile.inc` 新增 4 個 target + 1 個 alias | 一次性 | 構建系統 | `make help` 含 `diagram-init` / `diagram-list` / `diagram-sync` / `diagram-lint` / `diagram-render`（既有 `make diagram` 保留為 deprecated alias） |

---

## ⚠️ 邊界條件（Edge Cases）

- **無 `docs/diagrams/`**：Mode B/C 不自動建立目錄，明確提示「請先跑 Mode A」。
- **既有 11 個內嵌 Mermaid 區塊不搬家**：Mode A 在 `README.md` 以 inline 連結（`../architecture.md#L25`）收錄，原檔不動。
- **編輯既有 `docs/architecture.md` 內嵌區塊（known limitation）**：因無對應 `docs/diagrams/*.md`，Mode B 映射 Priority 1/2/3 全 miss → 落到 unmatched 清單。Step 9.5 仍會 WARN 提示「考慮跑 Mode B 或手動更新 inline 區塊」，由人類判斷。此為刻意保留的灰色地帶（ADR-008「兩層治理風險」），避免強制搬家。
- **Step 9.5 在 ADR/SPEC Status-only commit 觸發誤判**：由 Algo-S95 exclude 規則處理（status-only 變更跳過）→ 對應測試 `tests/test_asp_ship_step95.sh` 必涵蓋此案例。
- **大型 diff**：Mode B 對每個 changed file 獨立跑映射；若同圖被多檔命中只更新一次。
- **trigger word `diagram` 誤觸**：採 in-skill gating（skill 本體入口偵測「database」「SQL」「ER diagram」「sequence diagram for API」等關鍵字 → 早期 redirect 退出）。**不**改 router（router 為單關鍵詞匹配，SKILL.md:102，改動風險高）。
- **Mode C false positive**：drift type 2（rename）透過 `git log --follow` 自動排除；type 4（label not found）標 advisory，不影響 `--strict` exit code。
- **空 git history**（fresh clone 無 HEAD~1）：Mode B 退回比對 working tree vs HEAD；再失敗則退 `since_ref=$(git rev-list --max-parents=0 HEAD)`（root commit）。
- **`docs/diagrams/` 已存在但無 README.md**：Mode A 補 README.md，不覆蓋既有 `*.md`。

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | (1) `git revert` 新 skill commit；(2) `SKILL.md` 移除新列；(3) `asp-ship.md` 移除 Step 9.5；(4) `asp-plan.md` 移除 Step 5 提示句；(5) Makefile.inc 移除新 targets（保留既有 `diagram` target 不動）；(6) 保留 `docs/diagrams/` 內容（純文件，無破壞性）。 |
| **資料影響** | 零；所有產出物均為新檔，移除 skill 後檔案仍可手動維護。 |
| **回滾驗證** | (1) `make test` 全綠；(2) `/asp-plan` / `/asp-ship` 正常運作；(3) router 路由 `diagram` 觸發詞回到 fallback；(4) `make diagram` 仍可 render PNG（向後相容）。 |
| **回滾已測試** | ☐ 預定於 Stage 2 落地前在 fixture 上 drill：建 `tests/fixtures/asp-diagram-rollback/` 模擬 skill + ship Step 9.5 已落地狀態 → revert → 驗 4 項回滾驗證皆通過。**Rollback drill 為 Stage 2 必跑項目（autopilot 不可略過此 manual check）**。 |

> 雖非 DB schema 變更，但本 SPEC 修改 `asp-ship.md` 與 `asp-plan.md`（每個 commit 都會走的共用基礎設施），rollback drill 列為**必跑** manual check。G5 Gate 對此類「共用基礎設施修改」會檢查 rollback 已測試。

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入條件 | 預期結果 | 對應場景 |
|---|------|---------|---------|---------|
| P1 | ✅ 正向 | Mode A 對空 `docs/diagrams/` 跑（無 `--create`） | 建 README.md ≥ 11 條連結；不建 `docs/diagrams/*.md` 新檔 | S1 |
| P2 | ✅ 正向 | Mode B + 修改 `.asp/profiles/autopilot.md` 且 `docs/diagrams/asp-profiles-autopilot.md` 存在 | Priority 1/2 命中、更新 mermaid 區塊、保留 ## Notes 段、`source_files` 自動合併 | S2 |
| P3 | ✅ 正向 | Mode C 預設模式對 drift type 1 (MISSING_SOURCE) 圖 | stdout 印 1 行 drift；exit 0 | S3 |
| P4 | ✅ 正向 | Mode C `--strict` 對 drift type 1 | exit 1 | S3b |
| P5 | ✅ 正向 | Mode A `--create` 旗標對新檔 | 建 `docs/diagrams/{slug}.md`，frontmatter 完整 | S9 |
| N1 | ❌ 負向 | Mode B 對 `tests/some_test.sh` 變動且無對應圖（三層映射皆 miss） | 印「找不到對應圖」+ exit 1 | S4 |
| N2 | ❌ 負向 | `docs/diagrams/bad.md` 含故意錯誤的 mermaid 區塊 | `make diagram-lint` exit ≠ 0，列檔名 + 行號 | S5 |
| N3 | ❌ 負向 | trigger 「draw a diagram of database schema」（in-skill gating） | skill 早期 redirect，exit 0 不執行 Mode A | S10 |
| B1 | 🔶 邊界 | Mode A 第二次跑（idempotent） | 不重複建檔，README.md timestamps 更新，既有 frontmatter 其他欄位保留 | S6 |
| B2 | 🔶 邊界 | Mode B 一次多檔變更，2 檔對應同一張圖 | 圖只更新一次，`source_files` 合併兩個來源 | S7 |
| B3 | 🔶 邊界 | Mode C 對 renamed source（drift type 2） | 透過 `git log --follow` 不誤報 | S8 |
| B4 | 🔶 邊界 | Step 9.5：ADR Status-only commit | Algo-S95 exclude 命中，**不** WARN | S11 |
| B5 | 🔶 邊界 | Step 9.5：`.asp/profiles/autopilot.md` 內容變更 | Algo-S95 include 命中，WARN | S12 |

> 正向 5、負向 3、邊界 5 — 滿足 G2 / Reality Checker 最低要求。

---

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: asp-diagram skill 三模式
  作為 ASP 框架使用者
  我想要建立、同步、校對 Mermaid 架構圖
  以便圖與程式碼/決策保持一致，過期可被偵測

  Background:
    Given AI-SOP-Protocol repo 已 clone
    And `.claude/skills/asp/asp-diagram.md` 已存在
    And `.claude/skills/asp/SKILL.md` router 含 asp-diagram 列

  # --- 正向 ---

  Scenario: S1 — Mode A 初次建索引（預設 index-only）
    Given docs/diagrams/ 不存在
    And docs/ 內已有 11 個內嵌 Mermaid 區塊
    When 執行 /asp-diagram Mode A
    Then docs/diagrams/README.md 建立
    And README.md 列出至少 11 條圖連結（指向 source file 行號）
    And 既有內嵌區塊未被搬家
    And docs/diagrams/ 內**不**創建 *.md 新檔

  Scenario: S2 — Mode B Priority 1 命中 frontmatter
    Given .asp/profiles/autopilot.md 在 HEAD~1 已修改
    And docs/diagrams/asp-profiles-autopilot.md 存在
    And 該圖檔 frontmatter source_files 列 ".asp/profiles/autopilot.md"
    When 執行 /asp-diagram Mode B
    Then asp-profiles-autopilot.md 的 mermaid 區塊更新
    And frontmatter 的 last_updated_commit 重寫為當前 HEAD
    And 該檔的 ## Notes 區塊原文逐字保留

  Scenario: S3 — Mode C 預設模式列 drift（不 exit 1）
    Given docs/diagrams/multi-agent.md frontmatter source_files 列已不存在的 `.asp/scripts/multi-agent/legacy.sh`
    When 執行 /asp-diagram Mode C
    Then stdout 印「MISSING_SOURCE: multi-agent.md ↔ .asp/scripts/multi-agent/legacy.sh — 來源檔案不存在」
    And exit code = 0

  Scenario: S3b — Mode C --strict 對 drift type 1 exit 1
    Given 同 S3 條件
    When 執行 /asp-diagram Mode C --strict
    Then exit code = 1

  Scenario: S9 — Mode A --create 建新圖檔
    Given docs/diagrams/ 已有 README.md 但無 `architecture-block-1.md`
    When 執行 /asp-diagram Mode A --create
    Then docs/diagrams/architecture-block-1.md 建立
    And 該檔套用 .asp/templates/DIAGRAM_Template.md
    And frontmatter 含 source_files、last_updated_commit、diagram_type

  # --- 負向 ---

  Scenario: S4 — Mode B 找不到對應圖（三層映射全 miss）
    Given 修改了 tests/test_unrelated.sh 但 docs/diagrams/ 無對應檔
    When 執行 /asp-diagram Mode B
    Then 印出「找不到對應圖：tests/test_unrelated.sh → 建議跑 Mode A --create」
    And exit code = 1

  Scenario: S5 — Mermaid 語法錯誤
    Given docs/diagrams/bad.md 含故意錯誤的 mermaid 區塊
    When 執行 make diagram-lint
    Then exit code ≠ 0
    And 輸出含檔名 bad.md 與行號

  Scenario: S10 — In-skill gating 攔截 database schema 誤觸
    Given 使用者請求「draw a diagram of database schema」
    When asp-diagram skill 載入
    Then skill 偵測 "database schema" 關鍵字
    And 印「此請求看似非 ASP 架構圖，建議改用通用 mermaid 工具」
    And 不執行 Mode A
    And exit code = 0

  # --- 邊界 ---

  Scenario: S6 — Mode A idempotent
    Given docs/diagrams/README.md 已存在
    When 再次執行 /asp-diagram Mode A
    Then 不重複建立檔案
    And README.md last_updated 欄位更新
    And 既有 frontmatter 其他欄位保留

  Scenario: S7 — Mode B 多檔對同圖
    Given HEAD~1..HEAD 修改了 `.asp/profiles/autopilot.md` 與 `.asp/profiles/multi_agent.md`
    And docs/diagrams/asp-profiles-autopilot.md 的 source_files 同時包含這兩檔
    When 執行 /asp-diagram Mode B
    Then 該圖只被更新一次
    And source_files 合併（保持兩個來源）

  Scenario: S8 — Mode C rename 不誤報
    Given .asp/profiles/multi_agent.md 已從 .asp/profiles/multiagent.md 重命名（git log --follow 可追溯）
    And docs/diagrams/asp-profiles-multi-agent.md 的 source_files 仍指舊名
    When 執行 /asp-diagram Mode C
    Then 報告 drift type 2 (RENAMED_SOURCE) 而非 MISSING_SOURCE
    And exit code = 0（預設模式）

  Scenario: S11 — Step 9.5：ADR Status-only 不 WARN
    Given commit 只改 docs/adr/ADR-008-*.md 第 5 行的「狀態」欄位（Draft → Accepted）
    When 執行 /asp-ship
    Then Step 9.5 透過 Algo-S95 exclude 判斷為 status-only
    And **不** 輸出 WARN

  Scenario: S12 — Step 9.5：profile 內容變更觸發 WARN
    Given commit 改了 .asp/profiles/autopilot.md 的內容（非 status 欄位）
    When 執行 /asp-ship
    Then Step 9.5 偵測 Algo-S95 include 命中
    And 輸出 WARN「偵測到架構檔變動：.asp/profiles/autopilot.md。建議跑 /asp-diagram Mode B」
    And **不** BLOCK commit
```

---

## ✅ 驗收標準（Done When）

### 🤖 automated_checks（Stage 2 落地時填齊；目前只列**已可執行**的檢查）

```yaml
automated_checks:
  # Stage 1（本 SPEC 接受時）— 只需驗檔案存在性，不依賴尚未寫好的測試
  - cmd: "test -f docs/adr/ADR-008-introduce-asp-diagram-skill-for-mermaid-governance.md && test -f docs/specs/SPEC-005-asp-diagram-skill.md"
    description: "Stage 1：ADR-008 與 SPEC-005 草案存在"

  # Stage 2（實作落地後啟用，當前列為 PENDING — autopilot 會跳過 PENDING 行）
  # PENDING: bash tests/test_asp_diagram_mode_a.sh
  # PENDING: bash tests/test_asp_diagram_mode_b.sh
  # PENDING: bash tests/test_asp_diagram_mode_c.sh
  # PENDING: bash tests/test_skill_router_diagram.sh
  # PENDING: bash tests/test_asp_ship_step95.sh
  # PENDING: make diagram-lint
```

> **為何不直接列為 automated_checks**：reality-checker 指出測試腳本不存在會讓 autopilot Phase 2 abort。本 SPEC 處於 Draft 階段，Stage 2 落地前不該謊報「executable」。Stage 2 PR 落地時應把 6 行 PENDING 改為正式 automated_checks。

### 👤 manual_checks

- [ ] `.claude/skills/asp/asp-diagram.md` 已建立，含 Algo-A / Algo-B / Algo-C / Algo-S95 完整內容
- [ ] `.claude/skills/asp/SKILL.md` router 新增 asp-diagram 列
- [ ] `.claude/skills/asp/asp-ship.md` 插入 Step 9.5（含 Algo-S95 exclude 規則）
- [ ] `.claude/skills/asp/asp-plan.md` Step 5 結尾加 `/asp-diagram Mode A` 提示
- [ ] `.asp/templates/DIAGRAM_Template.md` 已建立
- [ ] `.asp/Makefile.inc` 新增 `diagram-init` / `diagram-list` / `diagram-sync` / `diagram-lint` / `diagram-render`（既有 `diagram` 保留為 deprecated alias 指向 `diagram-render`）
- [ ] `CLAUDE.md` 常用指令表新增 `make diagram-init` / `make diagram-lint`
- [ ] `docs/where-to-start.md` 提到新 skill
- [ ] `CHANGELOG.md` 加對應版本條目
- [ ] 6 個測試檔已建立並全綠
- [ ] Rollback drill 已在 fixture 上完成（見 Rollback Plan）
- [ ] 首次 `/asp-diagram Mode A` 跑完，目測 `docs/diagrams/README.md` 含 11 條既有 inline 連結

---

## 🔗 追溯性（Traceability v2）

```yaml
traceability:
  candidate_files:
    - path: ".claude/skills/asp/asp-diagram.md"
      role: implementation
    - path: ".claude/skills/asp/SKILL.md"
      role: integration
    - path: ".claude/skills/asp/asp-ship.md"
      role: integration
    - path: ".claude/skills/asp/asp-plan.md"
      role: integration
    - path: ".asp/templates/DIAGRAM_Template.md"
      role: template
    - path: ".asp/Makefile.inc"
      role: tooling
    - path: "docs/diagrams/README.md"
      role: documentation
    - path: "tests/test_asp_diagram_mode_a.sh"
      role: test
    - path: "tests/test_asp_diagram_mode_b.sh"
      role: test
    - path: "tests/test_asp_diagram_mode_c.sh"
      role: test
    - path: "tests/test_skill_router_diagram.sh"
      role: test
    - path: "tests/test_asp_ship_step95.sh"
      role: test
    - path: "tests/fixtures/asp-diagram/"
      role: test-fixture
    - path: "tests/fixtures/asp-diagram-rollback/"
      role: test-fixture
  last_verified: null
```

---

## 📊 非功能需求（NFR）

| 類別 | 需求 | 驗證方式 |
|------|------|----------|
| 效能 | Mode A 對 ≤ 50 個 markdown 檔的全掃 < 5s；Step 9.5 git diff scan < 2s | `time` benchmark in Stage 2 |
| 安全 | 不執行任何 mermaid 內容；僅讀寫 `docs/diagrams/` 與索引 | code review |
| 相容性 | 既有 11 個內嵌 mermaid 區塊不被修改；保留 inline 用法；既有 `make diagram` target 保留為 deprecated alias | `git diff` 對既有檔 = 空；`make diagram` 仍可產 PNG |

---

## 🔌 整合健康檢查（Integration Healthchecks）

**不適用** — 無外部 API 整合。Mermaid 為 GitHub/VSCode 原生 render，零網路依賴。

> 可選 PNG render 沿用既有 `make diagram` target 與 `mmdc`（nice-to-have）。**Backward compat 決策**：保留 `make diagram` 為 deprecated alias，新名稱 `make diagram-render`；CHANGELOG 列 deprecation timeline（建議 v4.4.0 之後移除舊 alias）。

---

## 📊 可觀測性（Observability）

| 面向 | 說明 |
|------|------|
| **關鍵指標** | `asp-ship` Step 9.5 觸發次數、Mode A/B/C 各自呼叫次數（從 `.asp-bypass-log.ndjson` + telemetry 推算） |
| **日誌** | Mode A/B 寫檔時 INFO；Mode C 報告差異時 INFO；找不到對應圖時 WARN；in-skill gating redirect 時 INFO |
| **告警** | 無自動告警（人類查 `make audit-health` 觀察「`docs/diagrams/README.md` 存在且非空」是否綠燈） |
| **如何偵測故障** | `make audit-health` 加一項 `diagram-index-exists`；Step 9.5 若反覆被 bypass 3+ 次 → 下次 `asp-audit` 觸發 blocker（既有機制，無需新增） |

---

## 🚫 禁止事項（Out of Scope）

- 不自動搬遷既有 11 個內嵌 Mermaid 區塊（policy：先索引、不搬家；見 ADR-008「known limitation」）。
- Mode C 不自動修圖（人類決策邊界）。
- 不引入除 `mmdc`（既有 optional）以外的新依賴。
- 不修改任何 ADR-007 schema v2 相關檔（範圍隔離）。
- 不修改 `asp-ship.md` Step 1-9 與 Step 10（只插入 Step 9.5）。
- 不改 SKILL.md router 的「單關鍵詞匹配」機制（router 變動風險高；改用 in-skill gating 處理 `diagram` 誤觸）。
- 不刪除既有 `make diagram` target（保留為 deprecated alias，至少維持兩個版本）。

---

## 📎 參考資料（References）

- **相關 ADR**：ADR-008（本 SPEC 對應決策）、ADR-007（schema v2 — 觸發 architecture.md 同步需求）
- **現有類似實作**：`.claude/skills/asp/asp-plan.md`（5 步驟風格）、`asp-ship.md`（10 步驟風格）、`asp-context.md`（Mode A/B/C 模式）
- **既有 11 個 Mermaid 區塊**：
  - `docs/architecture.md`（4 區塊：lines 25, 85, 154, 278）
  - `docs/multi-agent-architecture.md`（5 區塊：lines 33, 114, 200, 269, 305）
  - `.asp/templates/architecture_spec.md`（2 區塊：lines 19, 44）
- **外部文件**：
  - GitHub Mermaid 支援子集（落地實作前由 `/asp-fact-verify` 確認最新支援的圖種與語法版本）
- **既有 Makefile target**：`.asp/Makefile.inc:213`（`make diagram` PNG render，保留為 deprecated alias）
- **Bypass log 格式**：`.asp/hooks/session-audit.sh:56-65`（當前格式 `.asp-bypass-log.ndjson`；`.asp-bypass-log.json` 已 deprecated）
- **Router 匹配機制**：`SKILL.md:102`（單關鍵詞「任一觸發詞」匹配）
