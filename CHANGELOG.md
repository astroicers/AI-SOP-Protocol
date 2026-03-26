# Changelog

All notable changes to AI-SOP-Protocol will be documented in this file.

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
