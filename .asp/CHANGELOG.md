# ASP Changelog

本檔案記錄 AI-SOP-Protocol 框架本身的版本變更，供升級時參考。

---

## v3.3.0 — 穩定度強化

### 新增 — Pipeline Gate 強化

- **G3 測試品質檢查**：偵測空測試（無 assertion 的測試檔案）+ assertion 數 vs 場景數比例
- **G4 TODO/FIXME 標記**：自動掃描修改的檔案，記錄為 tech-debt（不阻擋但強制記錄）
- **G5 Warning 檢查**：lint warning 數量不可增加（與基線比對）
- **G5 Side Effects 驗證**：SPEC 列出的每個副作用必須有對應的驗證方式
- **G5 Rollback 測試**：架構/Schema 變更的 Rollback Plan 必須經過測試
- **G6 Traceability 驗證**：SPEC Traceability 引用的檔案必須存在
- **G2 Observability 驗證**：使用者面向功能必須定義可觀測性

### 新增 — 回歸基線比對

- execute_modification() 和 execute_bugfix() 實作前捕獲測試基線
- 實作後比對：之前通過但現在失敗的測試 = 回歸（BLOCKER）
- 偵測測試消失（可能被誤刪）

### 新增 — SPEC 模板擴充

- **Observability 區塊**：關鍵指標、日誌、告警、故障偵測方式（使用者面向功能必填）
- **Side Effects 驗證列**：每個副作用必須說明驗證方式
- **Rollback 測試欄位**：回滾步驟 + 資料影響 + 回滾驗證 + 回滾已測試

### 新增 — 審計基線擴充

- `lint_warning_count`：lint warning 數量追蹤
- `todo_fixme_count`：技術債標記追蹤
- `side_effects_unverified`：未驗證副作用數
- `rollback_untested_count`：未測試回滾計劃數

---

## v3.2.0 — Gherkin BDD 驗收場景 + 正負向測試矩陣

### 新增 — SPEC 模板強制擴充

- **測試矩陣（Test Matrix）**：正向(P)/負向(N)/邊界(B) 三類測試案例表列
  - 非 trivial 任務強制填寫（正向 ≥1 + 負向 ≥1）
  - 每行對應一個 Gherkin 場景 ID
- **驗收場景（Acceptance Scenarios）**：Gherkin Feature 格式
  - Given-When-Then 結構化行為描述
  - 非 trivial 任務強制撰寫（與 TDD 同等級）
  - Scenario Outline + Examples 支援參數化測試

### 新增 — 測試骨架自動產生

- `generate_test_skeleton()`：從 Gherkin 場景產生測試檔案骨架
- `verify_scenario_coverage()`：矩陣行 ↔ 場景 ↔ 測試三方覆蓋驗證

### 新增 — 品質門強制執行

- G2 Gate：場景完整性驗證（BLOCK 級）+ Reality Checker 場景品質檢查（攔截敷衍場景）
- G3 Gate：場景 ↔ 測試映射驗證（每個場景有測試、測試數 ≥ 場景數）

### 新增 — Bug 修復場景矩陣

- execute_bugfix() Phase 4.5：Bug 必須有重現場景（N1）
- 根據根因領域自動追加典型負向案例

### 新增 — CLAUDE.md 預設行為

- 「Gherkin 場景先於測試」列入預設行為表（與 TDD 同等級）
- 豁免條件：trivial 或 config-only

### 新增 — 場景自動維護（MODIFICATION 流程）

- `execute_modification()` Phase 4.5：自動偵測與新行為矛盾的既有場景並更新
  - `scenario_conflicts_with()`：比對場景的 Given/When/Then 與修改請求
  - `sync_test_matrix()`：矩陣行與場景 ID 同步（移除過時行、新增缺失行）
  - `regenerate_test_skeleton()`：增量更新測試骨架（更新註解、保留 assertion body、標記 DEPRECATED）
- 解決「場景維護負擔」問題：AI 在 MODIFICATION 流程中自動維護場景，不需人工同步

---

## v3.1.0 — 根因領域偵測 + Agent Memory 主動檢查

### 新增 — 根因領域偵測

- **`detect_bug_domain()`**：Bug 修復時自動偵測問題的根因領域
  - 7 個領域規則：auth, concurrency, data_integrity, api_contract, state_machine, boundary, null_safety
  - 根據領域自動追加專精角色（如 auth → +sec, concurrency → +dep-analyst）
  - 領域增強掃描：根據 domain 擴大 grep 範圍
  - 資料層 bug 強制全量測試，狀態機 bug 強制 state scan
  - 插入點：execute_bugfix() Phase 2.5

### 新增 — Agent Memory 主動檢查

- **`proactive_memory_check()`**：任務開始**之前**查詢歷史記憶
  - 模組歷史查詢：「這個 module 常出什麼問題？」
  - 領域策略查詢：「這類 bug 怎麼修最有效？」（含成功率）
  - 團隊有效性查詢：「什麼團隊組成對這個領域最有效？」
  - 修復前預掃描：自動 grep 歷史高頻問題
  - 低成功率警告：領域歷史成功率 <50% 時主動警告
  - 插入點：execute_bugfix() Phase 2.7

### 升級 — Agent Memory 記錄格式

- `fix_strategies` 新增欄位：`domain`、`root_cause_class`、`recommended_agents`
- `common_failures` 新增欄位：`domain`
- `team_effectiveness` 新增欄位：`domains_encountered`
- `update_memory()` 升級：所有事件記錄包含 domain 資訊

### 升級 — 團隊組成

- `team_compositions.yaml` 新增 `domain_adjustments` 區塊（7 個領域規則）

---

## v3.0.0 — Multi-Agent 協作系統升級

> 借鏡 spec-kit、agent-teams、agency-agents、apify/agent-skills、Schoger design workflow 五個外部專案，
> 全面升級 multi-agent 系統的角色分工、交接協議、品質管線、即時驗證、升級路由、Agent 記憶。

### 新增 — Agent 角色目錄

- **10 個專精角色**（4 部門）取代通用 Worker-a/Worker-b
  - 架構與規劃：Architect (`arch`), Spec Writer (`spec`), Dependency Analyst (`dep-analyst`)
  - 實作：Test Author (`tdd`), Implementer (`impl`), Integrator (`integ`)
  - 品質與驗證：QA Verifier (`qa`), Security Reviewer (`sec`), Reality Checker (`reality`)
  - 文件：Doc Writer (`doc`)
- **角色定義檔案**：`.asp/agents/*.yaml`（含職責、輸入/輸出、成功指標、scope 約束）
- **場景化團隊組成表**：`.asp/agents/team_compositions.yaml`（8 種場景 + 動態調整規則）

### 新增 — 交接協議

- **5 種結構化交接模板**：`.asp/templates/handoff/`
  - `TASK_COMPLETE`：Worker → Orchestrator，含完整 context（取代 completed.jsonl 3 欄位）
  - `REASSIGNMENT`：Orchestrator → 新 Worker，含前任完整診斷 + Agent Memory hint
  - `ESCALATION`：P0-P3 嚴重度分級升級
  - `PHASE_GATE`：管線階段品質門結果
  - `SESSION_BRIDGE`：跨 session 交接（含 agent 協調狀態）
- **Context 全量傳遞**：交接單包含完整測試輸出、完整 diff、完整 SPEC 引用（不摘要）

### 新增 — 6 階段品質管線

- **管線 Profile**：`.asp/profiles/pipeline.md`
  - SPECIFY → G1 → PLAN → G2 → FOUNDATION → G3 → BUILD → G4 → HARDEN → G5 → DELIVER → G6 → DONE
  - 6 道品質門 `evaluate_gate()`，門檻失敗最多重試 2 次
  - 階段可跳過規則（trivial bugfix 只走 BUILD → HARDEN）
- **Reality Checker**：`.asp/profiles/reality_checker.md`
  - 預設 NEEDS_WORK，需 ≥3 正面證據 + 0 反面證據才放行
  - 參與 G2、G5、G6，擁有否決權
  - 獨立執行 `make test`（不信任任何 agent 自我回報）
- **品質門報告模板**：`.asp/templates/gate_report.md`

### 新增 — Dev↔QA 即時迴路

- **Dev↔QA Loop Profile**：`.asp/profiles/dev_qa_loop.md`
  - 從「做完再驗」→「邊做邊驗」（逐模組 QA 驗證）
  - 與 `auto_fix_loop()` 互補：低層（impl 內部自修） + 高層（qa 獨立驗證）
  - 每模組最多 3 次修復迴路，超過走升級協議

### 新增 — P0-P3 升級協議

- **升級 Profile**：`.asp/profiles/escalation.md`
  - P0（緊急：安全/資料遺失） → 暫停所有軌道
  - P1（高：重試耗盡/不可解衝突） → 暫停當前軌道
  - P2（中：QA fail 3x/scope 超出） → 重新分派
  - P3（低：tech debt/文件過期） → backlog
  - 取代散佈各 profile 的 `PAUSE_AND_REPORT()`，統一路由

### 新增 — Agent 學習記憶

- **記憶 Profile**：`.asp/profiles/agent_memory.md`
  - Session Memory（`.asp-agent-session.json`）：agent 分派、軌道、交接單
  - Project Memory（`.asp-agent-memory.yaml`）：修復策略成功率、團隊效能、失敗模式
  - Reassignment 時自動查詢相似修復策略，提供 memory hint
  - 90 天自動修剪

### 新增 — 5 個 Claude Code Skill

- `asp-dispatch`：多 Agent 任務分派（分類 + 團隊推薦 + 並行規劃）
- `asp-qa`：獨立品質驗證（偷渡偵測 + 覆蓋率 + 獨立測試）
- `asp-security`：安全審查（OWASP Top 10 + 憑證掃描 + 攻擊面分析）
- `asp-reality-check`：懷疑主義驗收（預設 NEEDS_WORK）
- `asp-impact`：依賴影響分析（依賴圖 + 並行標記 + 風險評分）

### 新增 — 架構文件

- `docs/multi-agent-architecture.md`：含 6 張 Mermaid 流程圖
  - 系統總覽圖、交接協議序列圖、Dev↔QA 對比圖、升級路由圖、並行拓撲圖
  - 10 角色部門表、8 場景團隊推薦表、檔案結構參考

### 新增 — mode: auto（預設模式）

- **`mode: auto`** 取代 `mode: single` 成為預設值
  - AI 根據 `decompose()` 結果自動判斷是否啟動 multi-agent 並行
  - 2+ 個獨立子任務 → 自動切換 multi-agent
  - 否則 → 等同 single mode
  - 使用者零配置：安裝後無需修改 .ai_profile 即享有自動並行能力
- `mode: single` 保留為「強制單 agent」選項

### 升級 — 既有 Profile

- **multi_agent.md**：通用 Worker → 角色制；flat lock → track/level lock；agent-done → 結構化交接單；plan_parallel_execution() + converge_tracks()
- **task_orchestrator.md**：新增 Part I recommend_team() + Part J execute_with_pipeline()
- **autonomous_dev.md**：auto_fix_loop 防護觸發改走 escalate()；新增 Dev↔QA 迴路整合
- **autopilot.md**：Phase 0.5 載入 Agent Memory
- **SKILL.md**：路由表 5 → 10 個 skill

### 升級 — 基礎設施

- **Makefile.inc**：新增 8 個 agent 管理目標（handoff-list/view, tracks, escalation-log, memory-show/prune, team-recommend）
- **CLAUDE.md**：Profile 對應表新增 multi-agent v3.0 條目；Makefile 速查新增 7 行
- **README.md**：核心能力表新增 5 行；新增「Multi-Agent 協作架構」段落；常用指令新增 4 行

### 向後相容

- `mode: single` 時所有角色由同一 agent 扮演，管線仍執行，無交接單
- `.agent-lock.yaml` 新增欄位為 optional，v2.x 格式繼續可用
- 無 `escalation.md` 時 fallback 到 PAUSE_AND_REPORT
- 無 `team_compositions.yaml` 時 fallback 到通用 Worker 分派
- `mode: single` 仍有效——已安裝使用者的 `.ai_profile` 不受影響
- `mode: auto` 是新安裝的預設值

---

## v2.7.0

- **CLAUDE.md 專案描述自動產生**：autopilot 從 ROADMAP.yaml + `.ai_profile` + SRS 自動產生 CLAUDE.md 的「專案概覽」區塊
  - 新增 `## 專案概覽` 區塊（含 `ASP-AUTO-PROJECT-DESCRIPTION` 標記）
  - 新增 `.asp/scripts/update-project-description.py` 腳本
  - `make autopilot-validate` 驗證通過後自動呼叫
  - autopilot 每次啟動時（Phase 1.5）自動檢查並更新
  - 冪等：內容沒變則不寫入
- **Onboarding 流程文件化**：`docs/autopilot.md` 和 `README.md` 更新為完整 onboarding 流程

---

## v2.6.0

- **Autopilot Profile**：新增 `.asp/profiles/autopilot.md`，ROADMAP 驅動持續自動執行
  - 6 階段偽代碼（Resume → Load & Configure → Validate → Queue → Health Audit → Execute Loop → Complete）
  - 零確認執行：所有 13 個暫停點改為自主處理策略（skip + record）
  - 動態前置文件探測：根據 ROADMAP.yaml 的 `stack` / `requires` 自動判斷必要文件
  - 自動 Profile 載入：根據 ROADMAP.yaml 元資料載入對應 Profile
  - 跨 Session 續接：`.asp-autopilot-state.json` 存儲執行狀態
  - 安全邊界：繼承 autonomous_dev 全部規則 + 14 項 autopilot 專屬自主處理策略
- **前置文件模板**：
  - `ROADMAP_Template.yaml`：專案元資料（stack/requires/conventions/architecture/quality/security/observability）+ milestones/tasks
  - `SRS_Template.md`：需求規格（FR/US/UC/資料模型/介面規格/追溯矩陣）
  - `SDS_Template.md`：設計規格（系統架構/模組設計/資料設計/API 合約/安全設計）
  - `UIUX_SPEC_Template.md`：UI/UX 規格（Design System/頁面流程/元件規格/響應式/無障礙/動畫）
  - `DEPLOY_SPEC_Template.md`：部署規格（環境定義/Container/CI-CD/監控/災難復原）
- **Makefile.inc 新增 targets**：
  - `autopilot-init` / `autopilot-validate` / `autopilot-status` / `autopilot-reset`
  - `srs-new` / `sds-new` / `uiux-spec-new` / `deploy-spec-new`
- **install.sh**：支援 `autopilot` 欄位
- **CLAUDE.md**：autopilot 欄位 + Profile 對應表 + 啟動程序 step 4b + ADR 鐵則備註

---

## v2.5.0

- **Makefile 非破壞性安裝（Breaking Change）**：
  - **Include-based 架構**：ASP targets 移至 `.asp/Makefile.inc`（ASP 完全擁有），專案 Makefile 改為 stub + `-include .asp/Makefile.inc`
  - **非 ASP 專案保護**：目標專案有自己的 Makefile 時，僅追加 include 指令，不覆蓋原有內容
  - **升級相容**：舊版 ASP Makefile（含 `AI-SOP-Protocol` 標記）自動轉換為 stub + include 模式
  - **install.sh 重構**：移除 4 層覆蓋式 Makefile 偵測邏輯，改為 3 分支 include-based 邏輯

---

## v2.4.1

- **install.sh Bug 修復**：
  - **Makefile 升級偵測**：修復舊版 Makefile（有 `guardrail-log` 但無 `ASP_MAKEFILE_VERSION`）不會被升級的問題。改用 `audit-health` 作為最新版本標記
  - **settings.local.json jq 錯誤**：修復 JSON 檔案非 object 類型時 jq 報錯。新增 type guard 跳過非 object 檔案
- **clean-allow-list.sh**：同步修復相同的 jq type guard 問題

---

## v2.4.0

- **框架穩健性優化**：提升 task_orchestrator 的可執行性與錯誤恢復能力
  - **Helper Function 定義**：新增 Part H，定義 ~12 個先前未規格化的函數（`is_core_module`、`determine_change_level`、`analyze_requirement`、`decompose` 等），含 pseudocode 與判定範例
  - **L1-L4 量化**：`determine_change_level()` 加入量化門檻與判定範例表，消除分類模糊性
  - **後置審計 Circuit Breaker**：最多 2 輪，超過記入 tech-debt，防止 infinite loop
  - **ADR Pre-flight Timeout**：30 分鐘逾時機制，提供繼續等待/暫存/跳過三個選項
  - **Gate 防護**：Design/OpenAPI Gate 呼叫前檢查 profile 是否載入，未載入時 WARN + tech-debt 而非靜默失敗
  - **auto_fix_loop 失敗處理**：D1/D2/D3 工作流加入 guard_triggered 檢查，三重防護觸發時 PAUSE 不繼續
  - **新鮮度維度修復**：SPEC 存在但無 Traceability 時發出 WARNING（不再靜默跳過）
  - **交叉引用表**：Part H 結尾新增 helper function → 來源 profile 對照表
- **Makefile 修復**：
  - `make test` / `make test-filter`：偵測框架後才執行，測試失敗正確傳播 exit code，無框架時 exit 1（不再靜默成功）
  - `audit-health` 維度 7：SPEC 存在但無 Traceability 時輸出 WARNING
- **CLAUDE.md 更新**：Makefile 速查表補齊所有 target（coverage、lint、diagram、agent-locks、rag-stats、guardrail、task-report 等），Profile 對應表去除冗餘列
- **跨 Profile 交叉引用**：
  - `multi_agent.md`「Autonomous 模式整合」加 canonical source 註記
  - `autonomous_dev.md`「Multi-Agent 整合」加擴展來源註記
  - `task_orchestrator.md` Part G 加 routing-only 註記
- **Trivial 統一定義**：`global_core.md` 新增量化標準（檔案 ≤ 2、行數 ≤ 10、不涉及商業邏輯），不確定時視為 non-trivial
- **SPEC Template**：Traceability 區塊加 HTML 註解標註「實作完成後回填」

---

## v2.3.0

- **Task Orchestrator Profile**：新增 `task_orchestrator.md`，統一任務入口與協調層
  - 任務分類：自動識別 5 種任務類型（新增/修復/修改/移除/複合）並路由到對應工作流
  - 架構影響評估：自動判斷是否需要 ADR
  - REMOVAL 工作流：全新的功能移除流程（依賴分析→deprecation 評估→安全移除→零殘留驗證）
  - 文件產出管線：所有任務類型共用，自動更新 CHANGELOG/README/architecture/SPEC
  - 完成報告：結構化報告含健康改善指標
  - Multi-Agent 整合：TASK_GENERAL 可分解為並行子任務
  - 載入：`orchestrator: enabled` 或 `autonomous: enabled` 時自動載入
- **專案健康審計**：`task_orchestrator.md` 內建 7 維度掃描 + 強制補齊機制
  - 測試覆蓋、SPEC 覆蓋、ADR 覆蓋、文件完整性、程式碼衛生、依賴健康、文件新鮮度
  - 分級報告：Blocker / Warning / Info
  - 觸發時機：首次介入專案自動觸發、距上次審計 > 7 天、`make audit-health`
  - 審計基線追蹤：`.asp-audit-baseline.json`
- **軟工缺陷修復**：
  - **雙向可追溯性**：SPEC Template 新增 Traceability 區塊（實作檔案、測試檔案、最後驗證日期）
  - **文件新鮮度追蹤**：`global_core.md` 新增技術強制機制，不再純靠 AI 自律
  - **非功能需求（NFR）**：SPEC Template 新增 optional 的效能/安全/可用性/相容性區塊
  - **測試金字塔**：`system_dev.md` 新增單元→整合→契約→E2E 指引
  - **Hotfix 流程**：`system_dev.md` 新增生產環境緊急修復流程（簡化 Gate + 24h 回填義務）
  - **分支與合併**：`system_dev.md` 新增輕量分支策略指引
  - **Tech Debt 彙總**：`global_core.md` 新增規則，`make tech-debt-list` 掃描全專案
- **Makefile 新增 targets**：
  - `audit-health`：完整專案健康掃描（7 維度）
  - `audit-quick`：快速 blocker 檢查
  - `doc-audit`：文件新鮮度掃描
  - `tech-debt-list`：tech-debt/TODO/FIXME/DEPRECATED 彙總
  - `task-start`/`task-status`/`task-report`：任務記錄與統計
- **install.sh**：支援 `orchestrator` 欄位，模式 2/4 自動啟用，安裝完成提示 `make audit-health`

## v2.2.0

- **Frontend Quality Profile**：新增 `frontend_quality.md`，獨立的前端工程品質驗證
  - i18n 硬編碼偵測 + 語系一致性驗證 pseudocode
  - 顏色值驗證（禁止硬編碼 hex/rgb）
  - 元件三態驗證 pseudocode
  - Error/Loading/Empty 標準化規範
  - Accessibility 自動化驗證 pseudocode
  - 載入：`frontend_quality: enabled` 或 `design: enabled` 時自動載入
- **Design Token 同步**：`design_dev.md` 新增 Token ↔ CSS 雙向驗證 pseudocode
- **design: disabled UI 兜底**：`system_dev.md` 新增 `ui_baseline_rules`
- **DEPRECATED 程式碼追蹤**：`global_core.md` 新增清理計畫規範
- **提交前自審擴充**：清潔度 +3 項、新增「前端元件完整性」區塊
- **TDD 場景擴充**：前端互動元件建議基本測試
- **設計 Review 擴充**：a11y checklist 新增 4 項
- **Makefile**：新增 `i18n-check` target
- **install.sh**：支援 `frontend_quality` 欄位

## v2.1.0

- **Autonomous + Multi-Agent 可組合**：分層授權（Worker scope 內自主、Orchestrator 全專案協調）
- **Profile 衝突驗證**：新增 `<!-- conflicts: -->` 標籤
- **安裝簡化**：從多題 y/N 精簡為 2 題（專案類型 + 開發風格）
- **專案偵測擴充**：Rust/Java/C#/C++/Ruby/Elixir/PHP + 架構偵測

## v2.0.0

- **Autonomous 開發模式**：新增 `autonomous_dev.md` profile，支援 AI 全自動開發
  - auto_fix_loop 含振盪偵測、串聯失敗偵測、測試篡改偵測
  - 批次 ADR 預審流程
- **Hook 架構重構**：移除 PreToolUse hooks（enforce-workflow.sh、enforce-side-effects.sh），改用 Claude Code 內建權限系統
  - 僅保留 SessionStart hook（clean-allow-list.sh）
  - install.sh 自動清理舊版 hooks
- **SPEC 模板增強**：
  - 新增「副作用與連動（Side Effects）」區塊
  - 新增「回退方案（Rollback Plan）」子區塊
  - Done When 增加副作用驗證 checkbox
  - 「建議模型」和「HITL 等級」標記為 optional
- **迴歸預防協議擴充**：6 步驟（根因→重現→全專案掃描→狀態依賴掃描→下游驗證→分類標記）
- **Postmortem 流程**：新增模板（5 Whys）、Makefile targets、觸發條件定義
- **穩定度導向**：
  - coding_style.md 新增穩定度導向編碼規則 + 安全編碼基線
  - system_dev.md 新增變更影響評估、穩定狀態驗證、Schema 變更治理、提交前自審、依賴管理規範
  - TDD 場景新增 UI/樣式調整豁免、文件/配置變更豁免
- **Context 管理**：主動預防措施（定期壓縮、品質自驗、不可繼承資訊清單）
- **Profile 交叉引用**：所有 profile 加入 `<!-- requires: -->` / `<!-- optional: -->` 標頭
- **RAG 增量索引**：build_index.py 支援 `--incremental`，SHA-256 manifest 追蹤
- **連動性補強**：
  - 文件原子化拆為正向 + 反向規則（ADR 廢止→掃 SPEC、設計變更→標記 drift、OpenAPI 變更→掃前後端）
  - ADR 執行規則加入 Deprecated/Superseded 反向掃描
  - Pre-Implementation Gate 新增步驟 6「歷史教訓查詢」（RAG 啟用時查 Postmortem）
  - 新增「需求變更回溯協議」：4 級（細節修改 / SPEC 推翻 / ADR 推翻 / 方向 Pivot）
- **Makefile 條件載入**：讀取 `.ai_profile` 的 `type`，content 專案隱藏 Docker/Test/Diagram targets

## v1.6.0

- 新增 `coding_style.md` profile（程式碼風格治理）
- 新增 `openapi.md` profile（API-First 工作流）
- 擴充 `design_dev.md`（UI/UX 設計治理）

## v1.4.0

- 吸收 context engineering 最佳實踐（壓縮觸發、衰退模式、token 經濟學）
- install.sh 顯示 commit hash

## v1.3.0

- 遷移至 SessionStart hook + 內建權限系統
- 移除 PreToolUse hook 中的 deny 策略

## v1.2.0

- Profile 決策流程改為偽代碼格式
- Hook 策略改為 hybrid（git push 使用內建權限）

## v1.1.0

- 新增 SPEC 存在性檢查
- 支援升級安裝

## v1.0.0

- 初始版本
- Profile 系統：global_core、system_dev、content_creative、vibe_coding、multi_agent、committee、guardrail、rag_context
- Makefile 封裝、ADR/SPEC 模板、install.sh
