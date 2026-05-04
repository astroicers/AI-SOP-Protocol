# Changelog

All notable changes to AI-SOP-Protocol will be documented in this file.

## [Unreleased] - 2026-05-04

### Added
- **mattpocock/skills 整合**: 全局安裝 12 個 engineering skills（`diagnose`、`tdd`、`grill-with-docs`、`to-prd`、`to-issues`、`triage`、`improve-codebase-architecture`、`zoom-out`、`grill-me`、`caveman`、`write-a-skill`、`setup-matt-pocock-skills`）至 `~/.agents/skills/`，symlink 至 `~/.claude/skills/`
- **`docs/agents/` 設定目錄**: 新增 `issue-tracker.md`（GitHub Issues + `gh` CLI）、`triage-labels.md`（5 個 canonical triage 狀態）、`domain.md`（single-context，`CONTEXT.md` + `docs/adr/`）
- **`CLAUDE.md` Agent skills 區塊**: 新增 `## Agent skills` section，讓 mattpocock skills 能讀取 issue tracker、triage labels、domain docs 設定

### Fixed
- **`.claude/settings.json` deny 重複注入**: `npx skills@latest add` installer 將 `ask` 陣列複製為 `deny`，造成危險指令從「跳彈窗確認」變為「靜默拒絕」，與 ASP 鐵則設計不符；已移除多餘 `deny` 區塊，還原為 `ask` 行為

## [3.6.0] - 2026-04-22

### Added
- **G5.5 Cross-Component Parity Gate**: 新 gate 在 G5 與 G6 之間，驗證跨 module / 跨 service 契約對齊。檢查 SPEC 是否含 Cross-Component Invariants section、grep 全 repo callsite、mock 對稱檢查、round-trip test 是否存在。
- **G6.5 Post-Deploy SIT Gate**: 新 gate 在 G6 之後，要求 deploy 完 + ArgoCD synced 後跑 SIT round-trip 才算「完成」；FAIL 時 AI 提議 rollback infra image tag PR。請求使用者 UI 驗證**之前**必過此 gate。
- **`docs/spec-driven-dev.md` Cross-Component Invariants section**: SPEC 模板必填欄位（涉及跨 module 契約時），明示 invariant、SSOT、consumer、現有格式的 grep 證據。

### Rationale
2026-04-21/22 PoC 出現連續 21 小時、6+ deploy 才穩住的 incident（PM-002）：兩個 cross-component invariant violation（shard key padding asymmetry + envelope decrypt asymmetry）存活 ≥ 3.5 月。原因是 ASP G1-G6 流程每層自洽通過，但**沒有任何一道 gate 檢查「跨 module 真的能合作」**。G5.5 + G6.5 補上這層。詳見 `backup-infrastructure/docs/postmortems/PM-002-shard-key-and-decrypt-cross-component-asymmetries.md`。

## [3.5.1] - 2026-04-10

### Added
- **`global_core.md` 工作目錄紀律**: 新增「工作目錄紀律」段落，要求 AI 在多 root / subagent 接手 / 相對路徑情境下明確確認 cwd，存取專案外路徑必須等待使用者確認
- **`global_core.md` 外部資料校對**: 新增「外部資料校對」段落，要求 API / 函式簽章等資訊必須透過 RAG / context7 / WebFetch 查證，以「人事時地物 5 元素」對齊
- 兩個段落皆含 Common Rationalizations 藉口反駁表

### Rationale
差距分析發現使用者個人全域 CLAUDE.md 有 2 條通用紀律 ASP 尚未涵蓋（工作目錄確認、外部資料校對）。這兩條是語言/技術棧中立的通用紀律，適合納入 `global_core.md`。其他個人偏好（繁體中文、套件管理工具、硬體環境）刻意保留在使用者個人全域，不進入框架層。

## [3.5.0] - 2026-04-10

### Added
- **Maturity Levels 系統（L1-L5）**: 借鑒 addyosmani/agent-skills 與 slavingia/skills 的 journey-based 設計。取代 20 個 profile 的扁平組合，使用者從 L1 Starter 開始逐級升級（L1→L2 Disciplined→L3 Test-First→L4 Collaborative→L5 Autonomous）
  - 新增 `.asp/levels/level-1.yaml` ~ `level-5.yaml`（含 profile 組合、graduation_checklist、prerequisites）
  - 新增 `asp-level` skill（評估 / 升級 / 降級）
  - 新增 Makefile targets: `asp-level-check`、`asp-level-upgrade`、`asp-level-list`
  - `.ai_profile` 新增 `level:` 欄位；legacy 專案支援 level 推斷規則
  - `install.sh` 新增 L1-L5 選單（替代扁平 preset，保留 P 選項作向後相容）
- **Anti-Rationalization Tables**: 借鑒 agent-skills 的反合理化設計。在 asp-ship、asp-plan、asp-gate、asp-reality-check、asp-level 五個 skill 新增 `## Common Rationalizations` 段落，系統性封堵 AI 常見繞過藉口
- **Evidence-Based Gate Output**: Gate 與 Ship 輸出升級為結構化證據模式
  - 每個檢查項目必須附 `command` + `exit_code` + `evidence_excerpt`
  - Skip 事件必須寫入 `.asp-bypass-log.json`（append-only）
  - 預設摘要模式 + verbose 詳情模式
- **Bypass Log 系統**
  - 新增 `.asp-bypass-log.json`（append-only 紀錄所有 skip 事件）
  - 新增 Makefile targets: `asp-bypass-review`、`asp-bypass-record`
  - `asp-enforcement-status` 顯示近 7 天 bypass 統計
- **Specialist Subagent Personas**: 擴充 `reality-checker` 模式
  - `.claude/agents/security-auditor.md`（OWASP Top 10 獨立審查，read-only）
  - `.claude/agents/test-engineer.md`（測試品質與 TDD 紀律審查，read-only）
  - 可透過 Agent tool 直接召喚，不需啟用 `multi_agent` profile
- **Router Next-Step Suggestions**: SKILL.md router 新增「執行後主動提示下一步」規則，每個 skill 完成後提示 workflow 下一階段（只建議、不自動執行）

### Changed
- **CLAUDE.md**: 新增 `.ai_profile` `level:` 欄位、Maturity Levels 章節、新 Makefile targets 速查
- **install.sh**: 互動式安裝新增 L1-L5 等級選單；`.ai_profile` 欄位補充 loop 納入 `level`
- **asp-ship**: Step 10 分為 10a（測試結果）/ 10b（bypass 記錄）；新增 Evidence-Based Output 說明
- **asp-gate**: 新增 Evidence-Based Output JSON 格式範例、skip 自動記錄規則

### Design Origin
本版本的演化方向來自分析兩個外部框架：
- addyosmani/agent-skills — Anti-rationalization tables + evidence-based verification
- slavingia/skills — Journey-based skill sequencing

ASP 保留 4 層強制力架構（Hook + Dynamic Deny + Gate + Subagent）作為核心差異化，在此之上吸收兩者的新手友善設計。

## [3.4.0] - 2026-03-26

### Added
- **4-layer enforcement architecture**: 借鏡 sd0x-dev-flow 的 hook 強制力設計，在 VSCode 插件限制下實現最大規則覆蓋
- **Smart SessionStart audit** (`session-audit.sh`): Session 啟動時自動執行 7 維度專案審計，產生 `.asp-session-briefing.json`
- **Dynamic deny list**: 根據專案狀態（Draft ADR、測試未通過）動態注入 `git commit` deny pattern，VSCode 彈出阻擋對話框
- **`asp-gate` skill**: Pipeline G1-G6 品質門檻評估器，結果寫入 `.asp-gate-state.json`
- **`reality-checker` subagent** (`.claude/agents/reality-checker.md`): 獨立 context 的懷疑論者，預設 NEEDS_WORK，用於 G5 交叉驗證
- **`asp-verify.sh` script**: 獨立驗證腳本（test + lint + credential scan + debug scan）
- **Mandatory skill invocation table**: CLAUDE.md 新增強制 skill 調用點表，含繞過警告格式
- **`asp-ship` v3.4**: 從 7 步驟擴展為 10 步驟（+Session briefing +Lint +Security scan +記錄結果）
- **Makefile targets**: `asp-unlock-commit`、`asp-refresh`、`asp-enforcement-status`

### Changed
- **`clean-allow-list.sh`**: 新增動態 deny 清理邏輯（每次 session 先清理再重新評估）
- **`settings.json`**: 註冊 `session-audit.sh` 為第二個 SessionStart hook
- **CLAUDE.md 鐵則**: ADR 禁止實作規則標記為「v3.4 硬性執行」
- **SKILL.md router**: 新增 asp-gate 路由

### Technical Notes
- VSCode Claude Code 插件不支援 PreToolUse/PostToolUse/Stop hooks（GitHub #21736, #13744, #13339）
- 強制力設計繞過此限制：使用 SessionStart + deny list（硬性）+ skill（結構化軟性）+ subagent（中等）
- 規則覆蓋：78 條可強制規則中，18 條硬性阻擋 + 53 條結構化軟性 + 7 條 subagent 驗證

## [2.15.0] - 2026-03-22

### Added
- **E2E Test Gate**: 全端專案（同時具有 frontend/ + backend/）強制 Playwright E2E 測試
- **Pre-Implementation Gate Step 5c**: Playwright 設定檔 + e2e/ 目錄不存在 → BLOCK
- **Testing Pyramid enforcement**: E2E 從「建議」升級為「有前後端時必須」
- **Health audit dimension 1c**: E2E 測試審計，缺少設定/目錄/測試檔 → BLOCKER
- **Pre-commit checklist**: 使用者流程修改需驗證 E2E 覆蓋

## [2.14.0] - 2026-03-19

### Added
- **Security BLOCK**: coding_style 安全違規（SQL injection、hardcoded secrets、raw HTML）從 SUGGEST 升級為 BLOCK，無豁免
- **Pre-commit report**: 提交前自審必須輸出 5 維度通過/失敗結論報告
- **Bug grep evidence**: Bug 修復後 grep 全專案必須輸出 grep 指令本身作為證據
- **Bug classification function**: `classify_bug_severity()` 以客觀指標取代主觀判斷
- **Frontend verification triggers**: 4 個驗證函數加入明確觸發時機表
- **Breaking change BLOCK**: OpenAPI breaking change 偵測到即 BLOCK，強制版本遞增
- **Profile conflict detection**: `validate_profile_config()` 啟動時自動驗證依賴/衝突
- **Autopilot script safety**: script 呼叫加入存在性檢查，不存在時 WARN 而非報錯

## [2.13.0] - 2026-03-19

### Added
- **Design system BLOCK**: `design: enabled` 時若 `design-system/` 不存在 → BLOCK
- **Design token WARN**: `design-system/` 存在但缺 `tokens.yaml` → WARN
- **Design Gate integration**: `system_dev.md` Step 4a 強制呼叫 `before_ui_work()`
- **API Test Gate**: 通用 Step 5b，後端 API 修改時強制整合測試
- **verify_token_sync alignment**: pre-commit 與 SPEC Done When 參數對齊
- **Pencil MCP section**: design_dev 新增已知問題速查表與標準流程
- **Frontend quality responsibility table**: 明確劃分 design_dev 與 frontend_quality 職責
- **Vibe coding Design Gate pause**: `hitl: minimal` 暫停條件新增 Design Gate

## [2.12.0] - 2026-03-18

### Added
- **Skill Layer**: 5 個 Claude Code 原生 skill（asp-plan/ship/audit/review/autopilot）
- **SKILL.md router**: 根據使用者意圖自動路由到對應子 skill
- Reduced onboarding friction with skill-based entry points

## [2.11.0] - 2026-03-18

### Changed
- Autopilot Phase 2 auto-generates SPEC for all tasks (mandatory)
- Autopilot Phase 2 smart assessment for ADR necessity

## [2.10.0] - 2026-03-17

### Added
- Autopilot auto-generates/revises README.md on completion

## [2.9.0] - 2026-03-17

### Changed
- **Deny-list permission model**: Allow Bash(*) + deny dangerous commands
- SessionStart hook ensures deny rules are correctly applied

## [2.8.0] - 2026-03-16

### Changed
- Restructured README and autopilot docs into SOP format

## [2.7.0] - 2026-03-15

### Added
- Auto-generate CLAUDE.md project description from ROADMAP.yaml

## [2.6.0] - 2026-03-12

### Added
- **Autopilot Profile** (`.asp/profiles/autopilot.md`): Roadmap-driven continuous execution with cross-session resume, dynamic prerequisite detection, and automatic profile loading
- **ROADMAP Template** (`.asp/templates/ROADMAP_Template.yaml`): Structured project metadata including tech stack, requirements, conventions, architecture, quality, security, and observability
- **SRS Template** (`.asp/templates/SRS_Template.md`): Software Requirements Specification with FR/US/UC, data model, interface spec, and traceability matrix
- **SDS Template** (`.asp/templates/SDS_Template.md`): Software Design Specification with system architecture, module design, data design, API contracts, and security design
- **UI/UX Spec Template** (`.asp/templates/UIUX_SPEC_Template.md`): Design system, page flow, component spec, responsive rules, accessibility, and animation
- **Deploy Spec Template** (`.asp/templates/DEPLOY_SPEC_Template.md`): Environment definition, container spec, CI/CD pipeline, monitoring, and disaster recovery
- **Makefile targets**: `autopilot-init`, `autopilot-validate`, `autopilot-status`, `autopilot-reset`, `srs-new`, `sds-new`, `uiux-spec-new`, `deploy-spec-new`
- **install.sh**: `autopilot` field support in `.ai_profile`
- **CLAUDE.md**: Autopilot field, Profile mapping, startup procedure step 4b, Makefile quickref

### Changed
- **Zero-confirmation autopilot**: All 13 pause points removed; autopilot runs continuously to token exhaustion with auto-handling strategies (skip + record)
- `.asp/VERSION`: 2.5.0 → 2.6.0
- `.gitignore`: Added `.asp-autopilot-state.json`

## [2.5.0] - 2026-03-12

### Changed
- Non-destructive Makefile installation via include-based architecture

## [2.4.1] - 2026-03-12

### Fixed
- install.sh Makefile upgrade detection and jq type guard

## [2.4.0] - 2026-03-12

### Added
- Task orchestrator and health audit
- Framework robustness improvements

## [2.3.0] - 2026-03-12

### Added
- Task orchestrator profile

## [2.2.0] - 2026-03-12

### Added
- Frontend quality profile

## [2.1.0] - 2026-03-12

### Added
- Autonomous + multi-agent composability via layered authorization
