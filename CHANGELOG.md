# Changelog

All notable changes to AI-SOP-Protocol will be documented in this file.

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
