# Changelog

All notable changes to AI-SOP-Protocol will be documented in this file.

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
