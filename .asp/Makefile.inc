# AI-SOP-Protocol — ASP Targets (included by project Makefile)
# 勿直接編輯此檔案，升級 ASP 時會自動覆蓋
# ASP_MAKEFILE_VERSION=3.4.0

# --- 條件載入：讀取 .ai_profile 的 type 欄位 ---
# content 類型專案隱藏 Docker/Test/Lint/Deploy targets
ASP_TYPE := $(shell grep '^type:' .ai_profile 2>/dev/null | awk '{print $$2}')

.PHONY: help \
        build clean deploy logs \
        test test-filter coverage lint i18n-check \
        diagram \
        adr-new adr-list \
        spec-new spec-list \
        postmortem-new postmortem-list \
        agent-done \
        session-checkpoint session-log \
        guardrail-log guardrail-reset \
        audit-health audit-quick doc-audit tech-debt-list \
        task-start \
        profile-validate \
        audit-baseline-init \
        asp-unlock-commit asp-refresh asp-enforcement-status \
        runbook-list runbook-view \
        ci-install \
        daily-audit \
        doc-new srs-new sds-new uiux-spec-new deploy-spec-new

#---------------------------------------------------------------------------
# Help
#---------------------------------------------------------------------------

help:
	@echo ""
	@echo "AI-SOP-Protocol 指令速查（type: $(or $(ASP_TYPE),未設定)）"
	@echo "========================="
	@echo ""
ifneq ($(ASP_TYPE),content)
	@echo "📦 Container:   build | clean | deploy | logs"
	@echo "🧪 Test:        test | test-filter FILTER=xxx | coverage | lint"
	@echo "🌐 i18n:        i18n-check"
	@echo "📐 Docs:        diagram"
endif
	@echo "📋 ADR:         adr-new TITLE=... | adr-list"
	@echo "📄 Spec:        spec-new TITLE=... | spec-list"
	@echo "🔥 Postmortem:  postmortem-new TITLE=... | postmortem-list"
	@echo "🤖 Agent:       agent-done TASK=... STATUS=..."
	@echo "🤖 Agent v3:    agent-handoff-list | agent-tracks | agent-escalation-log"
	@echo "🤖 Agent Init:  audit-baseline-init"
	@echo "💾 Session:     session-checkpoint NEXT=... | session-log"
	@echo "🛡  Guardrail:   guardrail-log | guardrail-reset"
	@echo "🏥 Audit:       audit-health | audit-quick | doc-audit | tech-debt-list"
	@echo "🔒 Enforce:     asp-unlock-commit | asp-refresh | asp-enforcement-status"
	@echo "📌 Task:        task-start DESC=..."
	@echo "🔍 Profile:     profile-validate"
	@echo "🚀 Autopilot:   autopilot-init | autopilot-validate | autopilot-status | autopilot-reset"
	@echo "📝 Documents:   doc-new TYPE=srs|sds|uiux|deploy"
	@echo "📚 Runbook:     runbook-list | runbook-view SCENARIO=..."
	@echo "🧩 Experimental/Showcase targets：目錄存在時自動載入（-include；見 experimental/ 與 showcase/ README）"
	@echo "🔧 CI:          ci-install (copy GitHub Actions workflow to .github/workflows/)"
	@echo "📆 Daily:       daily-audit (generate .asp-daily-report.md; see cron-setup.md)"
	@echo ""

#---------------------------------------------------------------------------
# Docker / Container（type: content 時隱藏）
#---------------------------------------------------------------------------
ifneq ($(ASP_TYPE),content)

build:
	@echo "🔨 Building $(APP_NAME):$(VERSION)..."
	docker build -t $(APP_NAME):$(VERSION) .

clean:
	@echo "🧹 Cleaning..."
	rm -rf ./tmp/* 2>/dev/null || true
	docker-compose down --rmi local --volumes --remove-orphans 2>/dev/null || true
	docker rmi $$(docker images '$(APP_NAME)' -q) 2>/dev/null || true

deploy:
	@echo "🚀 Deploying $(APP_NAME):$(VERSION)..."
	docker-compose up -d --force-recreate
	docker-compose ps

logs:
	docker-compose logs -f --tail=100

#---------------------------------------------------------------------------
# Test（type: content 時隱藏）
#---------------------------------------------------------------------------

test:
	@echo "🧪 Running tests..."
	@if [ -f "go.mod" ]; then go test ./... -v -race -coverprofile=coverage.out; \
	elif [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null; then npm test; \
	else \
	    HAS_BASH=0; HAS_PYTEST=0; FAIL=0; \
	    if ls tests/*.sh >/dev/null 2>&1; then HAS_BASH=1; fi; \
	    if command -v pytest >/dev/null 2>&1 && ls tests/*.py >/dev/null 2>&1; then HAS_PYTEST=1; fi; \
	    if [ $$HAS_BASH -eq 1 ]; then \
	        echo "── bash tests ──"; \
	        BPASS=0; BFAIL=0; \
	        for f in tests/*.sh; do \
	            echo "  → $$f"; bash "$$f" && BPASS=$$((BPASS+1)) || BFAIL=$$((BFAIL+1)); \
	        done; \
	        echo "bash tests: $$BPASS passed, $$BFAIL failed"; \
	        [ $$BFAIL -eq 0 ] || FAIL=$$((FAIL+BFAIL)); \
	    fi; \
	    if [ $$HAS_PYTEST -eq 1 ]; then \
	        echo "── pytest ──"; \
	        pytest ./tests -v || FAIL=$$((FAIL+1)); \
	    fi; \
	    if [ $$HAS_BASH -eq 0 ] && [ $$HAS_PYTEST -eq 0 ]; then \
	        echo "⚠️  未偵測到測試框架（go.mod / package.json / tests/*.sh / pytest）"; exit 1; \
	    fi; \
	    [ $$FAIL -eq 0 ]; \
	fi

test-filter:
	@if [ -z "$(FILTER)" ]; then echo "使用方式：make test-filter FILTER=xxx"; exit 1; fi
	@echo "🧪 Running filtered: $(FILTER)"
	@if [ -f "go.mod" ]; then go test ./... -run $(FILTER) -v; \
	elif command -v pytest >/dev/null 2>&1 && { [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -d "tests" ]; }; then pytest ./tests -k $(FILTER) -v; \
	elif [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null; then npm test -- --grep "$(FILTER)"; \
	else echo "⚠️  未偵測到測試框架"; exit 1; fi

coverage:
	@go tool cover -html=coverage.out 2>/dev/null || \
	coverage html && open htmlcov/index.html 2>/dev/null || \
	echo "⚠️  請先執行 make test"

lint:
	@echo "🔍 Linting..."
	@LINT_RAN=0; LINT_FAIL=0; \
	if [ -f "go.mod" ] && command -v golangci-lint >/dev/null 2>&1; then \
		echo "── go ──"; LINT_RAN=1; golangci-lint run ./... || LINT_FAIL=1; \
	fi; \
	if command -v flake8 >/dev/null 2>&1 && ls *.py >/dev/null 2>&1; then \
		echo "── python ──"; LINT_RAN=1; flake8 . || LINT_FAIL=1; \
	fi; \
	if [ -f "package.json" ] && grep -q '"lint"' package.json 2>/dev/null; then \
		echo "── npm ──"; LINT_RAN=1; npm run lint || LINT_FAIL=1; \
	fi; \
	if ls tests/*.sh >/dev/null 2>&1; then \
		LINT_RAN=1; \
		if command -v shellcheck >/dev/null 2>&1; then \
			echo "── shellcheck (.asp v5 scripts + tests) ──"; \
			shellcheck -S warning -e SC1090,SC1091,SC2086,SC2207 \
				.asp/scripts/asp-metrics.sh .asp/scripts/asp-compile.sh \
				.asp/scripts/level-resolve.sh .asp/scripts/orchestrator/*.sh tests/*.sh \
				|| LINT_FAIL=1; \
		else \
			echo "── bash -n (shellcheck not installed) ──"; \
			for f in .asp/scripts/orchestrator/*.sh tests/*.sh; do \
				bash -n "$$f" || { echo "syntax error: $$f"; LINT_FAIL=1; }; \
			done; \
		fi; \
	fi; \
	if [ $$LINT_RAN -eq 0 ]; then \
		echo "⚠️  No applicable linter found for this project"; \
	elif [ $$LINT_FAIL -ne 0 ]; then \
		echo "❌ lint failures (see above)"; exit 1; \
	else \
		echo "✅ lint passed"; \
	fi

#---------------------------------------------------------------------------
# i18n Check（type: content 時隱藏）
#---------------------------------------------------------------------------

i18n-check:
	@echo "🌐 Checking i18n consistency..."
	@LOCALE_DIR=$$(find . -maxdepth 4 -type d \( -name "locales" -o -name "i18n" -o -name "messages" -o -name "translations" -o -name "lang" \) ! -path '*/node_modules/*' ! -path '*/.git/*' | head -1); \
	if [ -z "$$LOCALE_DIR" ]; then \
		echo "⚠️  未偵測到語系目錄（locales/i18n/messages/translations/lang）"; \
		exit 0; \
	fi; \
	echo "  語系目錄：$$LOCALE_DIR"; \
	BASE_FILE=$$(ls $$LOCALE_DIR/*.json 2>/dev/null | head -1); \
	if [ -z "$$BASE_FILE" ]; then \
		echo "⚠️  語系目錄中未找到 JSON 檔案"; \
		exit 0; \
	fi; \
	BASE_COUNT=$$(python3 -c "import json; print(len(json.load(open('$$BASE_FILE'))))" 2>/dev/null || echo "ERR"); \
	if [ "$$BASE_COUNT" = "ERR" ]; then \
		echo "⚠️  無法解析 $$BASE_FILE（需要 python3）"; \
		exit 0; \
	fi; \
	echo "  基準檔案：$$BASE_FILE ($$BASE_COUNT keys)"; \
	FAIL=0; \
	for f in $$LOCALE_DIR/*.json; do \
		COUNT=$$(python3 -c "import json; print(len(json.load(open('$$f'))))" 2>/dev/null); \
		if [ "$$COUNT" != "$$BASE_COUNT" ]; then \
			echo "  ❌ $$f: $$COUNT keys (expected $$BASE_COUNT)"; \
			FAIL=1; \
		else \
			echo "  ✅ $$f: $$COUNT keys"; \
		fi; \
	done; \
	if [ "$$FAIL" = "1" ]; then \
		echo ""; \
		echo "❌ i18n key 數量不一致，請同步所有語系檔案"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ 所有語系檔案 key 數量一致"; \
	fi

#---------------------------------------------------------------------------
# Architecture Diagram（type: content 時隱藏）
#---------------------------------------------------------------------------

diagram:
	@echo "📐 Generating architecture diagram..."
	@{ \
	  echo '<!DOCTYPE html>'; \
	  echo '<html lang="zh-TW"><head><meta charset="UTF-8">'; \
	  echo '<title>ASP Architecture Diagrams</title>'; \
	  echo '<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>'; \
	  echo '<style>body{font-family:sans-serif;max-width:1200px;margin:0 auto;padding:2rem}'; \
	  echo 'h2{border-bottom:2px solid #333;padding-bottom:.5rem;margin-top:3rem}'; \
	  echo '.mermaid{background:#f8f8f8;padding:1rem;border-radius:8px;margin:1rem 0}</style>'; \
	  echo '</head><body>'; \
	  echo '<h1>ASP Architecture Diagrams</h1>'; \
	  for src in docs/architecture.md docs/multi-agent-architecture.md; do \
	    [ -f "$$src" ] || continue; \
	    echo "<h2>$$src</h2>"; \
	    awk '/^```mermaid$$/{found=1; block=""; next} found && /^```$$/{print "<div class=\"mermaid\">\n" block "</div>"; found=0; next} found{block=block $$0 "\n"}' "$$src"; \
	  done; \
	  echo '<script>mermaid.initialize({startOnLoad:true,theme:"default"});</script>'; \
	  echo '</body></html>'; \
	} > docs/architecture.html
	@echo "✅ docs/architecture.html 已產生（在瀏覽器開啟即可查看）"

else
# --- content 類型的 stub targets（避免 make: *** No rule to make target 錯誤）---
build clean deploy logs test test-filter coverage lint i18n-check diagram:
	@echo "⚠️  此指令不適用於 content 類型專案（目前 type: $(ASP_TYPE)）"
endif

#---------------------------------------------------------------------------
# ADR 管理
#---------------------------------------------------------------------------

adr-new:
	@if [ -z "$(TITLE)" ]; then read -p "ADR 標題: " TITLE; fi; \
	mkdir -p docs/adr; \
	MAX=$$(ls docs/adr/ADR-*.md 2>/dev/null | sed -n 's|.*/ADR-\([0-9]\{3\}\)-.*|\1|p' | sort -n | tail -1 | sed 's/^0*//'); \
	NUM=$$(printf "%03d" $$(( $${MAX:-0} + 1 ))); \
	SLUG=$$(echo "$(TITLE)" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-'); \
	[ -z "$$SLUG" ] && SLUG="untitled"; \
	FILE="docs/adr/ADR-$$NUM-$$SLUG.md"; \
	cp .asp/templates/ADR_Template.md $$FILE; \
	SED_I=$$([ "$$(uname)" = "Darwin" ] && echo "sed -i ''" || echo "sed -i"); \
	$$SED_I "s/ADR-000/ADR-$$NUM/g" $$FILE; \
	$$SED_I "s/決策標題/$(TITLE)/g" $$FILE; \
	$$SED_I "s/YYYY-MM-DD/$$(date +%Y-%m-%d)/g" $$FILE; \
	echo "✅ 已建立: $$FILE"

adr-list:
	@echo "📋 ADR 列表："; \
	ls docs/adr/ADR-*.md 2>/dev/null | while read f; do \
		STATUS=$$(grep -m1 "狀態" $$f | grep -o '`[^`]*`' | tr -d '`'); \
		TITLE=$$(head -1 $$f | sed 's/# //'); \
		case "$$STATUS" in \
			Draft)    ICON="🔴";; \
			FIRM)     ICON="🟡";; \
			Accepted) ICON="✅";; \
			*)        ICON="⬜";; \
		esac; \
		echo "  $$ICON $$TITLE [$$STATUS]"; \
	done || echo "  (無 ADR)"

#---------------------------------------------------------------------------
# Spec 管理
#---------------------------------------------------------------------------

spec-new:
	@if [ -z "$(TITLE)" ]; then read -p "規格書標題: " TITLE; fi; \
	mkdir -p docs/specs; \
	MAX=$$(ls docs/specs/SPEC-*.md 2>/dev/null | sed -n 's|.*/SPEC-\([0-9]\{3\}\)-.*|\1|p' | sort -n | tail -1 | sed 's/^0*//'); \
	NUM=$$(printf "%03d" $$(( $${MAX:-0} + 1 ))); \
	SLUG=$$(echo "$(TITLE)" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-'); \
	[ -z "$$SLUG" ] && SLUG="untitled"; \
	FILE="docs/specs/SPEC-$$NUM-$$SLUG.md"; \
	cp .asp/templates/SPEC_Template.md $$FILE; \
	SED_I=$$([ "$$(uname)" = "Darwin" ] && echo "sed -i ''" || echo "sed -i"); \
	$$SED_I "s/SPEC-000/SPEC-$$NUM/g" $$FILE; \
	$$SED_I "s/功能名稱/$(TITLE)/g" $$FILE; \
	echo "✅ 已建立: $$FILE"

spec-list:
	@echo "📋 Spec 列表："; \
	ls docs/specs/SPEC-*.md 2>/dev/null | while read f; do echo "  $$f"; done || echo "  (無 Spec)"

#---------------------------------------------------------------------------
# Postmortem
#---------------------------------------------------------------------------

postmortem-new:
	@if [ -z "$(TITLE)" ]; then read -p "Postmortem 標題: " TITLE; fi; \
	mkdir -p docs/postmortems; \
	MAX=$$(ls docs/postmortems/PM-*.md 2>/dev/null | sed -n 's|.*/PM-\([0-9]\{3\}\)-.*|\1|p' | sort -n | tail -1 | sed 's/^0*//'); \
	NUM=$$(printf "%03d" $$(( $${MAX:-0} + 1 ))); \
	SLUG=$$(echo "$(TITLE)" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-'); \
	[ -z "$$SLUG" ] && SLUG="untitled"; \
	FILE="docs/postmortems/PM-$$NUM-$$SLUG.md"; \
	cp .asp/templates/Postmortem_Template.md $$FILE; \
	SED_I=$$([ "$$(uname)" = "Darwin" ] && echo "sed -i ''" || echo "sed -i"); \
	$$SED_I "s/PM-000/PM-$$NUM/g" $$FILE; \
	$$SED_I "s/事件標題/$(TITLE)/g" $$FILE; \
	$$SED_I "s/YYYY-MM-DD/$$(date +%Y-%m-%d)/g" $$FILE; \
	echo "✅ 已建立: $$FILE"

postmortem-list:
	@echo "🔥 Postmortem 列表："; \
	ls docs/postmortems/PM-*.md 2>/dev/null | while read f; do \
		SEVERITY=$$(grep -m1 "嚴重等級" $$f | grep -o '`[^`]*`' | tr -d '`'); \
		TITLE=$$(head -1 $$f | sed 's/# //'); \
		echo "  $$TITLE [$$SEVERITY]"; \
	done || echo "  (無 Postmortem)"

#---------------------------------------------------------------------------
# Runbooks
#---------------------------------------------------------------------------

runbook-list: ## 列出可用的場景 Runbook
	@echo "📚 Runbook 列表（docs/runbooks/）："; \
	ls docs/runbooks/*.md 2>/dev/null | while read f; do \
		TITLE=$$(head -1 $$f | sed 's/# //'); \
		MODE=$$(grep -m1 '^\*\*模式\*\*' $$f | sed 's/.*：//;s/ |.*//' | tr -d ' '); \
		echo "  $$(basename $$f .md)  $$TITLE"; \
	done || echo "  (無 Runbook)"

runbook-view: ## 檢視 Runbook (SCENARIO=startup-mvp|incident-response|enterprise-feature)
	@if [ -z "$(SCENARIO)" ]; then echo "用法: make runbook-view SCENARIO=startup-mvp"; exit 1; fi
	@FILE="docs/runbooks/$(SCENARIO).md"; \
	if [ ! -f "$$FILE" ]; then echo "❌ 找不到 $$FILE。可用場景："; make runbook-list; exit 1; fi; \
	cat "$$FILE"

#---------------------------------------------------------------------------
# Multi-Agent
#---------------------------------------------------------------------------

agent-done: ## Worker 完成回報 (TASK=xxx STATUS=success|failed [REASON=...])
	@if [ -z "$(TASK)" ] || [ -z "$(STATUS)" ]; then echo "用法: make agent-done TASK=TASK-001 STATUS=success [REASON=...]"; exit 1; fi
	@mkdir -p .agent-events .agent-events/handoffs
	@TS=$$(date -u +%Y-%m-%dT%H:%M:%SZ); \
	SEQ=$$(date +%Y%m%d-%H%M%S); \
	echo "{\"task\":\"$(TASK)\",\"status\":\"$(STATUS)\",\"ts\":\"$$TS\",\"reason\":\"$(REASON)\"}" >> .agent-events/completed.jsonl; \
	HID="HANDOFF-$$SEQ"; \
	printf "handoff_type: TASK_COMPLETE\ntask_id: \"%s\"\ntimestamp: \"%s\"\nstatus: \"%s\"\nreason: \"%s\"\n" "$(TASK)" "$$TS" "$(STATUS)" "$(REASON)" > ".agent-events/handoffs/$$HID.yaml"; \
	echo "{\"id\":\"$$HID\",\"type\":\"TASK_COMPLETE\",\"task\":\"$(TASK)\",\"status\":\"$(STATUS)\",\"ts\":\"$$TS\"}" >> .agent-events/handoffs/index.jsonl; \
	echo "✅ $(TASK) $(STATUS) — $$HID"

# v3.7 file-lock deprecated stubs（agent-unlock / agent-lock-gc / agent-locks）
# 已於 v5.0 移除（ADR-017，依 v4.1 預告）。

# ─── Agent Handoff（v3.0；讀取 .agent-events/，無凍結路徑依賴故留 core）───
.PHONY: agent-handoff-list agent-handoff-view agent-tracks agent-track-status agent-escalation-log

agent-handoff-list: ## 列出所有交接單
	@echo "═══ Agent Handoffs ═══"
	@if [ -f .agent-events/handoffs/index.jsonl ]; then \
		cat .agent-events/handoffs/index.jsonl | tail -20; \
	else \
		echo "  (無交接單)"; \
	fi

agent-handoff-view: ## 檢視交接單 (ID=HANDOFF-xxx)
	@if [ -z "$(ID)" ]; then echo "用法: make agent-handoff-view ID=HANDOFF-xxx"; exit 1; fi
	@if [ -f ".agent-events/handoffs/$(ID).yaml" ]; then \
		cat ".agent-events/handoffs/$(ID).yaml"; \
	else \
		echo "交接單不存在: $(ID)"; exit 1; \
	fi

agent-tracks: ## 顯示當前並行軌道狀態
	@echo "═══ Parallel Tracks ═══"
	@if [ -f .asp-agent-session.json ]; then \
		python3 -c "import json; d=json.load(open('.asp-agent-session.json')); \
		[print(f\"  Track {t['id']}: {t['status']} (task: {t['task']}, agent: {t['agent']})\") for t in d.get('active_tracks',[])]" 2>/dev/null \
		|| echo "  (無法讀取 session 狀態)"; \
	else \
		echo "  (無活躍 session)"; \
	fi

agent-track-status: ## 特定軌道詳情 (TRACK=A)
	@if [ -z "$(TRACK)" ]; then echo "用法: make agent-track-status TRACK=A"; exit 1; fi
	@if [ -f .asp-agent-session.json ]; then \
		python3 -c "import json; d=json.load(open('.asp-agent-session.json')); \
		tracks=[t for t in d.get('active_tracks',[]) if t['id']=='$(TRACK)']; \
		print(json.dumps(tracks[0],indent=2,ensure_ascii=False)) if tracks else print('Track $(TRACK) 不存在')" 2>/dev/null; \
	else \
		echo "  (無活躍 session)"; \
	fi

agent-escalation-log: ## 顯示升級歷史
	@echo "═══ Escalation Log ═══"
	@find .agent-events/handoffs/ -name "*.yaml" -exec grep -l "handoff_type: ESCALATION" {} \; 2>/dev/null \
		| while read f; do \
			echo "---"; \
			grep -E "^(severity|task_id|reason|timestamp):" "$$f"; \
		done || echo "  (無升級記錄)"

# ─── Agent Init（v3.3）───────────────────────────────────────────
audit-baseline-init: ## 初始化審計基線
	@echo "🏥 建立審計基線..."
	@SRC=$$(find . -name "*.go" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.js" 2>/dev/null | grep -v node_modules | grep -v .git | grep -v vendor | grep -v '_test\.' | grep -v '.test\.' | grep -v '.spec\.' | grep -v 'test_' | wc -l | tr -d ' '); \
	TST=$$(find . \( -name "*_test.*" -o -name "*.test.*" -o -name "*.spec.*" -o -name "test_*" \) 2>/dev/null | grep -v node_modules | grep -v .git | wc -l | tr -d ' '); \
	SPC=$$(ls docs/specs/SPEC-*.md 2>/dev/null | wc -l | tr -d ' '); \
	ADR=$$(ls docs/adr/ADR-*.md 2>/dev/null | wc -l | tr -d ' '); \
	TD=$$(grep -rn "TODO[^(]\|FIXME" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" --include="*.js" . 2>/dev/null | grep -v node_modules | grep -v .git | wc -l | tr -d ' '); \
	if [ $$SRC -gt 0 ]; then R=$$(echo "scale=2; $$TST / $$SRC" | bc 2>/dev/null || echo "0"); else R="0"; fi; \
	printf '{"last_audit":"%s","test_coverage_ratio":%s,"spec_count":%s,"adr_count":%s,"blockers":0,"warnings":0,"info":0,"lint_warning_count":0,"todo_fixme_count":%s,"side_effects_unverified":0,"rollback_untested_count":0}\n' \
		"$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$R" "$$SPC" "$$ADR" "$$TD" | python3 -m json.tool > .asp-audit-baseline.json 2>/dev/null; \
	echo "✅ .asp-audit-baseline.json 已建立"; \
	cat .asp-audit-baseline.json
	@grep -q "asp-audit-baseline.json" .gitignore 2>/dev/null || echo ".asp-audit-baseline.json" >> .gitignore

#---------------------------------------------------------------------------
# Session 管理
#---------------------------------------------------------------------------

session-checkpoint:
	@mkdir -p docs
	@printf "\n## Checkpoint：$$(date '+%Y-%m-%d %H:%M')\n- 當前任務：$(TASK)\n- 狀態：$(STATUS)\n- 下一步：$(NEXT)\n" \
		>> docs/session-log.md
	@echo "✅ Checkpoint 已儲存"

session-log:
	@tail -30 docs/session-log.md 2>/dev/null || echo "(無 Session 紀錄)"

#---------------------------------------------------------------------------
# Guardrail
#---------------------------------------------------------------------------

guardrail-log:
	@if [ -f .guardrail/rejected.jsonl ]; then \
		python3 -c "import json; \
[print(f'[{l[\"type\"]}] {l[\"ts\"]}: {l[\"query\"][:60]}...') \
for l in (json.loads(x) for x in open('.guardrail/rejected.jsonl'))]" 2>/dev/null; \
	else echo "(無護欄觸發紀錄)"; fi

guardrail-reset:
	@rm -f .guardrail/rejected.jsonl
	@echo "🧹 護欄紀錄已清除"

#---------------------------------------------------------------------------
# 強制力管理（Enforcement）
#---------------------------------------------------------------------------

asp-unlock-commit: ## 解除動態 commit 阻擋（修復 ADR/測試問題後使用）
	@UNLOCKED=0; \
	for SETTINGS in ".claude/settings.local.json" ".claude/settings.json"; do \
		[ -f "$$SETTINGS" ] || continue; \
		BEFORE=$$(jq '.permissions.deny | length' "$$SETTINGS" 2>/dev/null || echo 0); \
		jq '.permissions.deny = [.permissions.deny[]? | select(test("git commit") | not)]' \
			"$$SETTINGS" > "$${SETTINGS}.tmp" 2>/dev/null && mv "$${SETTINGS}.tmp" "$$SETTINGS" || rm -f "$${SETTINGS}.tmp"; \
		AFTER=$$(jq '.permissions.deny | length' "$$SETTINGS" 2>/dev/null || echo 0); \
		if [ "$$BEFORE" != "$$AFTER" ]; then echo "🔓 $$SETTINGS：deny $$BEFORE → $$AFTER"; UNLOCKED=1; fi; \
	done; \
	[ "$$UNLOCKED" = "1" ] || echo "（無 git commit 動態 deny 可解除）"; \
	echo "   ⚠️  下次 session 啟動時會重新評估（ADR-011：動態 deny 在 settings.local.json）"

asp-refresh: ## 重新執行 session 審計（修復問題後使用）
	@echo "🔄 重新執行 session 審計..."; \
	CLAUDE_PROJECT_DIR="$$(pwd)" bash .asp/hooks/clean-allow-list.sh 2>&1; \
	CLAUDE_PROJECT_DIR="$$(pwd)" bash .asp/hooks/session-audit.sh 2>&1; \
	echo ""; \
	echo "✅ 審計完成，briefing 已更新"

asp-enforcement-status: ## 顯示當前強制力狀態
	@echo ""; \
	echo "🔒 ASP 強制力狀態"; \
	echo "================================="; \
	echo ""; \
	echo "── Deny List（硬性阻擋）──"; \
	for SF in ".claude/settings.json" ".claude/settings.local.json"; do \
		[ -f "$$SF" ] || continue; \
		jq -r '.permissions.deny[]?' "$$SF" 2>/dev/null | while read -r rule; do \
			echo "  🚫 $$rule"; \
		done; \
	done; \
	echo ""; \
	echo "── Session Briefing ──"; \
	if [ -f ".asp-session-briefing.json" ]; then \
		BLOCKERS=$$(jq '.blockers | length' ".asp-session-briefing.json"); \
		WARNS=$$(jq '.warnings | length' ".asp-session-briefing.json"); \
		DYNCOUNT=$$(jq '.dynamic_deny | length' ".asp-session-briefing.json"); \
		echo "  Blockers: $$BLOCKERS | Warnings: $$WARNS | Dynamic deny: $$DYNCOUNT patterns"; \
		if [ "$$BLOCKERS" -gt 0 ]; then \
			jq -r '.blockers[]' ".asp-session-briefing.json" | while read -r b; do \
				echo "  🔴 $$b"; \
			done; \
		fi; \
	else \
		echo "  (尚未執行 session 審計)"; \
	fi; \
	echo ""; \
	echo "── Gate State ──"; \
	if [ -f ".asp-gate-state.json" ]; then \
		jq -r '.gates | to_entries[] | "  \(.key): \(.value.status)"' ".asp-gate-state.json"; \
	else \
		echo "  (尚未初始化)"; \
	fi; \
	echo ""; \
	echo "── Bypass Log（近 7 天）──"; \
	if [ -f ".asp-bypass-log.json" ]; then \
		TOTAL=$$(jq 'length' ".asp-bypass-log.json" 2>/dev/null || echo 0); \
		RECENT=$$(jq --arg d "$$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
			'[.[] | select(.timestamp >= $$d)] | length' ".asp-bypass-log.json" 2>/dev/null || echo 0); \
		echo "  Total: $$TOTAL | Last 7 days: $$RECENT （檢視：make asp-bypass-review）"; \
	else \
		echo "  (無記錄)"; \
	fi; \
	echo ""

asp-bypass-review: ## 檢視 bypass 記錄（AI 繞過 skill 的歷史）
	@if [ ! -f ".asp-bypass-log.json" ]; then \
		echo "📋 .asp-bypass-log.json 不存在 — 尚未有任何 bypass 記錄"; \
		exit 0; \
	fi; \
	TOTAL=$$(jq 'length' ".asp-bypass-log.json"); \
	echo ""; \
	echo "📋 ASP Bypass Log"; \
	echo "================================="; \
	echo "Total entries: $$TOTAL"; \
	echo ""; \
	LIMIT=$${LIMIT:-20}; \
	echo "── 最近 $$LIMIT 筆 ──"; \
	jq -r ".[-$$LIMIT:] | reverse | .[] | \
		\"[\(.timestamp)] \(.skill) / \(.step)\n  reason: \(.reason)\n  actor: \(.actor // \"unknown\")\n\"" \
		".asp-bypass-log.json" 2>/dev/null || echo "  (jq 解析失敗 — 檔案可能損壞)"; \
	echo ""; \
	echo "── 按 skill 分組 ──"; \
	jq -r 'group_by(.skill) | .[] | "  \(.[0].skill): \(length) 次"' ".asp-bypass-log.json"; \
	echo ""; \
	echo "💡 若某 skill bypass 次數過高，考慮：(1) 補強 skill 文件 (2) 在 CLAUDE.md 加入對應鐵則"

asp-level-check: ## 檢查當前 ASP 成熟度等級與 graduation 進度（v5：loose/standard/autonomous）
	@LEVEL=$$(bash .asp/scripts/level-resolve.sh 2>/dev/null); \
	if [ -z "$$LEVEL" ]; then \
		echo "⚠️  .ai_profile 無 level 欄位 — 使用 Level 推斷規則（三級制）"; \
		if grep -q 'autopilot: enabled\|autonomous: enabled\|mode: multi-agent' .ai_profile 2>/dev/null; then LEVEL=autonomous; \
		elif grep -q 'openapi: enabled\|coding_style: enabled' .ai_profile 2>/dev/null; then LEVEL=standard; \
		else LEVEL=loose; fi; \
		echo "   推斷等級：$$LEVEL（建議在 .ai_profile 中補上 \`level: $$LEVEL\`）"; \
	fi; \
	LEVEL_FILE=".asp/levels/$$LEVEL.yaml"; \
	if [ ! -f "$$LEVEL_FILE" ]; then echo "❌ $$LEVEL_FILE 不存在"; exit 1; fi; \
	echo ""; \
	echo "🎯 ASP Level Check"; \
	echo "=================="; \
	echo ""; \
	NAME=$$(grep -E '^name:' "$$LEVEL_FILE" | head -1 | sed 's/name: *//'); \
	TAGLINE=$$(grep -E '^tagline:' "$$LEVEL_FILE" | sed 's/tagline: *//'); \
	echo "Current: $$LEVEL ($$NAME)"; \
	echo "         $$TAGLINE"; \
	echo ""; \
	echo "已啟用 profile (從 $$LEVEL_FILE)："; \
	awk '/^profiles:/{flag=1; next} /^[a-z]/{flag=0} flag && /^  -/{print "  "$$0}' "$$LEVEL_FILE"; \
	echo ""; \
	NEXT_LEVEL=$$(grep -E '^next_level:' "$$LEVEL_FILE" | awk '{print $$2}'); \
	if [ "$$NEXT_LEVEL" = "null" ] || [ -z "$$NEXT_LEVEL" ]; then \
		echo "✅ 已在最高等級 (autonomous)"; \
	else \
		NEXT_FILE=".asp/levels/$$NEXT_LEVEL.yaml"; \
		NEXT_NAME=$$(grep -E '^name:' "$$NEXT_FILE" | head -1 | sed 's/name: *//'); \
		echo "Next Level: $$NEXT_LEVEL ($$NEXT_NAME)"; \
		echo ""; \
		echo "📋 $$LEVEL Graduation Checklist（shell 可驗證的項目）："; \
		awk '/^graduation_checklist:/{flag=1; next} /^[a-z]/{flag=0} flag' "$$LEVEL_FILE" | \
			awk '/- id:/{id=$$3} /description:/{desc=$$0; sub(/[^"]*"/,"",desc); sub(/".*/,"",desc); print "  ["id"] "desc}'; \
		echo ""; \
		echo "💡 執行 skill /asp-level 獲得逐項驗證與升級建議"; \
	fi; \
	echo ""

asp-level-upgrade: ## 升級到下一個 ASP 等級（需先通過 asp-level-check）
	@CURRENT=$$(bash .asp/scripts/level-resolve.sh 2>/dev/null); \
	if [ -z "$$CURRENT" ]; then echo "❌ .ai_profile 無 level 欄位，先執行 make asp-level-check"; exit 1; fi; \
	LEVEL_FILE=".asp/levels/$$CURRENT.yaml"; \
	NEXT=$$(grep -E '^next_level:' "$$LEVEL_FILE" | awk '{print $$2}'); \
	if [ "$$NEXT" = "null" ] || [ -z "$$NEXT" ]; then echo "✅ 已在最高等級 ($$CURRENT)"; exit 0; fi; \
	NEXT_FILE=".asp/levels/$$NEXT.yaml"; \
	if [ ! -f "$$NEXT_FILE" ]; then echo "❌ $$NEXT_FILE 不存在"; exit 1; fi; \
	NEXT_NAME=$$(grep -E '^name:' "$$NEXT_FILE" | head -1 | sed 's/name: *//'); \
	echo "🚀 升級 $$CURRENT → $$NEXT ($$NEXT_NAME)"; \
	echo ""; \
	cp .ai_profile ".ai_profile.backup-$$CURRENT"; \
	echo "✅ 已備份 .ai_profile → .ai_profile.backup-$$CURRENT"; \
	echo ""; \
	echo "📋 請用 skill /asp-level 完成以下步驟："; \
	echo "   1. 根據 $$NEXT_FILE 的 ai_profile_hint 更新 .ai_profile"; \
	echo "   2. 執行 make asp-refresh"; \
	echo "   3. 跑 make asp-level-check 確認新等級"

asp-level-list: ## 列出所有 ASP 等級
	@echo ""; \
	echo "🎯 ASP Maturity Levels (v5)"; \
	echo "==========================="; \
	for n in loose standard autonomous; do \
		f=".asp/levels/$$n.yaml"; \
		if [ -f "$$f" ]; then \
			NM=$$(grep -E '^name:' "$$f" | head -1 | sed 's/name: *//'); \
			TG=$$(grep -E '^tagline:' "$$f" | sed 's/tagline: *//'); \
			AL=$$(grep -E '^aliases:' "$$f" | sed 's/aliases: *//;s/#.*//'); \
			echo "  $$n ($$NM, legacy $$AL) — $$TG"; \
		fi; \
	done; \
	echo ""; \
	echo "詳細資訊：cat .asp/levels/{loose,standard,autonomous}.yaml"; \
	echo "等級檢查：make asp-level-check"

asp-bypass-record: ## 寫入 bypass 記錄（內部使用，或手動記錄：SKILL=asp-ship STEP=5 REASON="..."）
	@if [ -z "$(SKILL)" ] || [ -z "$(STEP)" ] || [ -z "$(REASON)" ]; then \
		echo "❌ 用法：make asp-bypass-record SKILL=asp-ship STEP=Step5 REASON=\"...\" [ACTOR=ai|user]"; \
		exit 1; \
	fi; \
	ACTOR="$${ACTOR:-ai}"; \
	TS=$$(date -u +%Y-%m-%dT%H:%M:%SZ); \
	ENTRY=$$(jq -n --arg t "$$TS" --arg s "$(SKILL)" --arg st "$(STEP)" --arg r "$(REASON)" --arg a "$$ACTOR" \
		'{timestamp:$$t, skill:$$s, step:$$st, reason:$$r, actor:$$a}'); \
	if [ ! -f ".asp-bypass-log.json" ]; then echo "[]" > ".asp-bypass-log.json"; fi; \
	jq ". + [$$ENTRY]" ".asp-bypass-log.json" > ".asp-bypass-log.json.tmp" && \
		mv ".asp-bypass-log.json.tmp" ".asp-bypass-log.json"; \
	echo "✅ Bypass 記錄已寫入 (.asp-bypass-log.json)"

asp-bypass-migrate: ## Migrate .asp-bypass-log.json → .ndjson + 建立 hash chain (Iron Rule B, ADR-019)
	@if [ -f .asp-bypass-log.json ]; then \
	    python3 -c "import json,sys; [print(json.dumps(e)) for e in json.load(open('.asp-bypass-log.json'))]" \
	    >> .asp-bypass-log.ndjson && echo "[ASP] Migrated bypass log to NDJSON (.asp-bypass-log.ndjson)"; \
	else echo "[ASP] No .asp-bypass-log.json to migrate"; fi
	@$(MAKE) -s asp-bypass-rechain
.PHONY: asp-bypass-migrate

asp-bypass-rechain: ## 重算 bypass log hash chain 並啟用 (Iron Rule B, ADR-019/SPEC-012)
	@if [ -f .asp-bypass-log.ndjson ]; then \
	    bash .asp/scripts/bypass-hash.sh rechain .asp-bypass-log.ndjson && \
	    echo "1" > .asp-bypass-log.chained && \
	    awk 'END{print NR}' .asp-bypass-log.ndjson > .asp-bypass-log.hwm && \
	    echo "[ASP] Bypass log hash chain 已重算並啟用（$$(awk 'END{print NR}' .asp-bypass-log.ndjson) 筆，.chained marker 已設）"; \
	else echo "[ASP] No .asp-bypass-log.ndjson to rechain"; fi
.PHONY: asp-bypass-rechain

asp-update: ## Sync ASP core from local repo to ~/.claude/ (profiles/hooks/skills)
	@bash ~/.claude/scripts/asp-sync.sh
.PHONY: asp-update

asp-l0-audit: ## Run L0 Spike Lifecycle Audit (Active vs Zombie diagnosis + Promotion Gate checks)
	@bash .asp/scripts/l0-audit.sh .
.PHONY: asp-l0-audit


security-scan: ## Run Semgrep ASP security rules (D-002 deterministic SAST)
	@if command -v semgrep &>/dev/null; then \
	    semgrep --config=.semgrep/asp-security.yml . --quiet; \
	    echo "[ASP] security-scan complete"; \
	else \
	    echo "[ASP] semgrep not installed — skip security scan"; \
	    echo "[ASP] Install: pip install semgrep"; \
	fi
.PHONY: security-scan ci-install daily-audit

ci-install: ## Install ASP CI workflow to .github/workflows/asp-ci.yml (P2)
	@DEST=".github/workflows/asp-ci.yml"; \
	TEMPLATE=".asp/templates/github-actions-ci.yml"; \
	if [ ! -f "$$TEMPLATE" ]; then echo "❌ $$TEMPLATE not found — run make asp-update first"; exit 1; fi; \
	if [ -f "$$DEST" ]; then \
		echo "⚠️  $$DEST already exists"; \
		printf "Overwrite? [y/N] "; read -r ANS; \
		[ "$$ANS" = "y" ] || { echo "Aborted."; exit 0; }; \
	fi; \
	mkdir -p .github/workflows; \
	cp "$$TEMPLATE" "$$DEST"; \
	echo "✅ CI workflow installed → $$DEST"; \
	echo ""; \
	echo "Next steps:"; \
	echo "  1. Review $$DEST and adjust language setup if needed"; \
	echo "  2. git add $$DEST && git commit -m 'ci: add ASP CI workflow'"; \
	echo "  3. Push → GitHub Actions will run on your next PR"

#---------------------------------------------------------------------------
# 專案健康審計
#---------------------------------------------------------------------------

audit-health:
	@echo ""
	@echo "🏥 專案健康審計（完整掃描）"
	@echo "================================="
	@echo ""
	@BLOCKERS=0; WARNINGS=0; INFOS=0; \
	\
	echo "── 1. 測試覆蓋 ──"; \
	SRC_COUNT=0; TEST_COUNT=0; \
	for ext in go ts tsx js jsx py java rb sh; do \
		SRC_COUNT=$$((SRC_COUNT + $$(find . -name "*.$$ext" ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/vendor/*' ! -name '*_test.*' ! -name '*.test.*' ! -name '*.spec.*' ! -name 'test_*' ! -path '*/test*/*' ! -path '*/tests/*' 2>/dev/null | wc -l))); \
		TEST_COUNT=$$((TEST_COUNT + $$(find . \( -name "*_test.$$ext" -o -name "*.test.$$ext" -o -name "*.spec.$$ext" -o -name "test_*.$$ext" \) ! -path '*/node_modules/*' ! -path '*/.git/*' 2>/dev/null | wc -l))); \
	done; \
	if [ $$SRC_COUNT -gt 0 ]; then \
		RATIO=$$(echo "scale=0; $$TEST_COUNT * 100 / $$SRC_COUNT" | bc 2>/dev/null || echo "?"); \
		echo "  Source files: $$SRC_COUNT | Test files: $$TEST_COUNT | Coverage ratio: $${RATIO}%"; \
		if [ $$TEST_COUNT -eq 0 ] && [ $$SRC_COUNT -gt 5 ]; then \
			echo "  🔴 BLOCKER: 專案有 $$SRC_COUNT 個 source files 但無任何測試"; \
			BLOCKERS=$$((BLOCKERS + 1)); \
		elif [ "$$RATIO" != "?" ] && [ $$RATIO -lt 30 ]; then \
			echo "  🟡 WARNING: 測試覆蓋率低於 30%"; \
			WARNINGS=$$((WARNINGS + 1)); \
		else \
			echo "  ✅ OK"; \
		fi; \
	else echo "  ⚪ 無 source files"; fi; \
	echo ""; \
	\
	echo "── 1c. E2E 測試（全端專案）──"; \
	HAS_FE=0; HAS_BE=0; \
	[ -d "frontend" ] && HAS_FE=1; \
	([ -d "backend" ] || [ -d "api" ] || [ -d "server" ]) && HAS_BE=1; \
	if [ $$HAS_FE -eq 1 ] && [ $$HAS_BE -eq 1 ]; then \
		if [ ! -f "playwright.config.ts" ] && [ ! -f "playwright.config.js" ]; then \
			echo "  🔴 BLOCKER: 全端專案缺少 Playwright 設定"; \
			BLOCKERS=$$((BLOCKERS + 1)); \
		else \
			E2E_DIR=""; \
			for d in e2e tests/e2e frontend/e2e; do [ -d "$$d" ] && E2E_DIR="$$d" && break; done; \
			if [ -z "$$E2E_DIR" ]; then \
				echo "  🔴 BLOCKER: 全端專案缺少 E2E 測試目錄"; \
				BLOCKERS=$$((BLOCKERS + 1)); \
			else \
				E2E_N=$$(find "$$E2E_DIR" \( -name "*.spec.ts" -o -name "*.e2e.ts" -o -name "*.test.ts" \) 2>/dev/null | wc -l | tr -d ' '); \
				if [ $$E2E_N -eq 0 ]; then echo "  🔴 BLOCKER: E2E 目錄存在但無測試"; BLOCKERS=$$((BLOCKERS + 1)); \
				elif [ $$E2E_N -lt 3 ]; then echo "  🟡 WARNING: E2E 僅 $$E2E_N 個（建議 ≥ 3）"; WARNINGS=$$((WARNINGS + 1)); \
				else echo "  ✅ E2E 測試 $$E2E_N 個"; fi; \
			fi; \
		fi; \
	else echo "  ⚪ 非全端專案，跳過"; fi; \
	echo ""; \
	\
	echo "── 2. SPEC 覆蓋 ──"; \
	SPEC_COUNT=$$(ls docs/specs/SPEC-*.md 2>/dev/null | wc -l | tr -d ' '); \
	echo "  SPEC 數量: $$SPEC_COUNT"; \
	if [ $$SPEC_COUNT -eq 0 ] && [ $$SRC_COUNT -gt 5 ]; then \
		echo "  🟡 WARNING: 專案有代碼但無任何 SPEC"; \
		WARNINGS=$$((WARNINGS + 1)); \
	else echo "  ✅ OK"; fi; \
	echo ""; \
	\
	echo "── 3. ADR 覆蓋 ──"; \
	ADR_COUNT=$$(ls docs/adr/ADR-*.md 2>/dev/null | wc -l | tr -d ' '); \
	DRAFT_WITH_CODE=0; \
	for f in docs/adr/ADR-*.md; do \
		[ -f "$$f" ] || continue; \
		STATUS=$$(grep -m1 "狀態" "$$f" 2>/dev/null | grep -o '`[^`]*`' | tr -d '`'); \
		ADR_ID=$$(basename "$$f" .md | grep -o 'ADR-[0-9]*'); \
		if [ "$$STATUS" = "Draft" ]; then \
			if grep -r "$$ADR_ID" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" . >/dev/null 2>&1; then \
				echo "  🔴 BLOCKER: $$ADR_ID 狀態為 Draft 但已有實作代碼（鐵則違反）"; \
				BLOCKERS=$$((BLOCKERS + 1)); \
				DRAFT_WITH_CODE=$$((DRAFT_WITH_CODE + 1)); \
			fi; \
		elif [ "$$STATUS" = "FIRM" ]; then \
			if grep -r "$$ADR_ID" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" . >/dev/null 2>&1; then \
				echo "  🟡 WARNING: $$ADR_ID 狀態為 FIRM（POC 驗證中）— 允許 commit，待人類升級至 Accepted"; \
				WARNINGS=$$((WARNINGS + 1)); \
			fi; \
		fi; \
	done; \
	echo "  ADR 數量: $$ADR_COUNT"; \
	if [ $$DRAFT_WITH_CODE -eq 0 ]; then echo "  ✅ OK"; fi; \
	echo ""; \
	\
	echo "── 4. 文件完整性 ──"; \
	for doc in README.md CHANGELOG.md; do \
		if [ ! -f "$$doc" ]; then \
			echo "  🟡 WARNING: 缺少 $$doc"; \
			WARNINGS=$$((WARNINGS + 1)); \
		else echo "  ✅ $$doc exists"; fi; \
	done; \
	if [ ! -f "docs/architecture.md" ] && [ "$(ASP_TYPE)" != "content" ] && [ $$SRC_COUNT -gt 10 ]; then \
		echo "  🟡 WARNING: 缺少 docs/architecture.md（系統專案建議有架構文件）"; \
		WARNINGS=$$((WARNINGS + 1)); \
	fi; \
	echo ""; \
	\
	echo "── 5. 程式碼衛生 ──"; \
	DEP_COUNT=$$(grep -r "DEPRECATED\|@deprecated" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" --include="*.js" . 2>/dev/null | grep -v node_modules | grep -v .git | wc -l | tr -d ' '); \
	TODO_NO_OWNER=$$(grep -rn "TODO[^(]" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" --include="*.js" . 2>/dev/null | grep -v node_modules | grep -v .git | wc -l | tr -d ' '); \
	FIXME_COUNT=$$(grep -rn "FIXME" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" --include="*.js" . 2>/dev/null | grep -v node_modules | grep -v .git | wc -l | tr -d ' '); \
	TECH_DEBT=$$(grep -rn "tech-debt:" --include="*.go" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.java" --include="*.rb" --include="*.sh" . 2>/dev/null | grep -v node_modules | grep -v .git | grep -v .asp/profiles | grep -v .asp/templates | grep -v .asp/hooks | grep -v .asp/scripts | wc -l | tr -d ' '); \
	if [ $$DEP_COUNT -gt 0 ]; then echo "  🟡 WARNING: $$DEP_COUNT 個 DEPRECATED 標記待清理"; WARNINGS=$$((WARNINGS + 1)); fi; \
	if [ $$TODO_NO_OWNER -gt 0 ]; then echo "  🟡 WARNING: $$TODO_NO_OWNER 個 TODO 無 owner"; WARNINGS=$$((WARNINGS + 1)); fi; \
	if [ $$FIXME_COUNT -gt 0 ]; then echo "  🟢 INFO: $$FIXME_COUNT 個 FIXME"; INFOS=$$((INFOS + 1)); fi; \
	if [ $$TECH_DEBT -gt 0 ]; then echo "  🟢 INFO: $$TECH_DEBT 個 tech-debt 標記"; INFOS=$$((INFOS + 1)); fi; \
	if [ $$DEP_COUNT -eq 0 ] && [ $$TODO_NO_OWNER -eq 0 ]; then echo "  ✅ OK"; fi; \
	echo ""; \
	\
	echo "── 6. 依賴健康 ──"; \
	LOCK_OK=1; \
	if [ -f "package.json" ] && [ ! -f "package-lock.json" ] && [ ! -f "yarn.lock" ] && [ ! -f "pnpm-lock.yaml" ]; then \
		echo "  🟡 WARNING: 有 package.json 但無 lock file"; WARNINGS=$$((WARNINGS + 1)); LOCK_OK=0; \
	fi; \
	if [ -f "pyproject.toml" ] && [ ! -f "poetry.lock" ] && [ ! -f "requirements.txt" ]; then \
		echo "  🟡 WARNING: 有 pyproject.toml 但無 lock file"; WARNINGS=$$((WARNINGS + 1)); LOCK_OK=0; \
	fi; \
	if [ -f "go.mod" ] && [ ! -f "go.sum" ]; then \
		echo "  🟡 WARNING: 有 go.mod 但無 go.sum"; WARNINGS=$$((WARNINGS + 1)); LOCK_OK=0; \
	fi; \
	if [ $$LOCK_OK -eq 1 ]; then echo "  ✅ OK"; fi; \
	echo ""; \
	\
	echo "── 7. 文件新鮮度 ──"; \
	STALE=0; \
	for spec in docs/specs/SPEC-*.md; do \
		[ -f "$$spec" ] || continue; \
		IMPL=$$(grep -A5 "追溯性\|Traceability" "$$spec" 2>/dev/null | grep -oE '[a-zA-Z0-9_/.-]+\.(go|ts|py|java|js)' | head -5); \
		for impl_file in $$IMPL; do \
			if [ -f "$$impl_file" ]; then \
				SPEC_DATE=$$(git log -1 --format=%at -- "$$spec" 2>/dev/null || echo 0); \
				IMPL_DATE=$$(git log -1 --format=%at -- "$$impl_file" 2>/dev/null || echo 0); \
				if [ "$$IMPL_DATE" -gt "$$SPEC_DATE" ] 2>/dev/null; then \
					SPEC_NAME=$$(basename "$$spec"); \
					echo "  🟡 WARNING: $$SPEC_NAME 的實作檔案 $$impl_file 較新（doc-stale）"; \
					WARNINGS=$$((WARNINGS + 1)); \
					STALE=$$((STALE + 1)); \
				fi; \
			fi; \
		done; \
	done; \
	if [ $$STALE -eq 0 ]; then \
		SPEC_COUNT=$$(ls docs/specs/SPEC-*.md 2>/dev/null | wc -l | tr -d ' '); \
		if [ "$$SPEC_COUNT" -gt 0 ]; then \
			HAS_TRACE=$$(grep -rl "追溯性\|Traceability" docs/specs/SPEC-*.md 2>/dev/null | wc -l | tr -d ' '); \
			if [ "$$HAS_TRACE" = "0" ]; then \
				echo "  🟡 WARNING: $$SPEC_COUNT 個 SPEC 均無 Traceability 資料，無法驗證新鮮度"; \
				WARNINGS=$$((WARNINGS + 1)); \
			else \
				echo "  ✅ OK"; \
			fi; \
		else \
			echo "  ✅ OK（無 SPEC）"; \
		fi; \
	fi; \
	echo ""; \
	\
	echo "── 8. 測試品質（v3.3）──"; \
	EMPTY_TESTS=0; \
	for ext in go ts js py java; do \
		for tf in $$(find . \( -name "*_test.$$ext" -o -name "*.test.$$ext" -o -name "*.spec.$$ext" \) ! -path '*/node_modules/*' ! -path '*/.git/*' 2>/dev/null); do \
			case $$ext in \
				go) A=$$(grep -c "assert\|require\.\|t\.Error\|t\.Fatal" "$$tf" 2>/dev/null || echo 0);; \
				py) A=$$(grep -c "assert\|assertEqual\|assertTrue" "$$tf" 2>/dev/null || echo 0);; \
				ts|js) A=$$(grep -c "expect(\|assert\." "$$tf" 2>/dev/null || echo 0);; \
				java) A=$$(grep -c "assert\|assertEquals" "$$tf" 2>/dev/null || echo 0);; \
				*) A=1;; \
			esac; \
			if [ "$$A" = "0" ]; then \
				echo "  🟡 WARNING: $$tf 沒有 assertion（空測試）"; \
				WARNINGS=$$((WARNINGS + 1)); EMPTY_TESTS=$$((EMPTY_TESTS + 1)); \
			fi; \
		done; \
	done; \
	if [ $$EMPTY_TESTS -eq 0 ]; then echo "  ✅ 無空測試"; fi; \
	echo ""; \
	\
	echo "── 9. SPEC 場景覆蓋（v3.2）──"; \
	NO_MATRIX=0; \
	for spec in docs/specs/SPEC-*.md; do \
		[ -f "$$spec" ] || continue; \
		HM=$$(grep -c "測試矩陣\|Test Matrix" "$$spec" 2>/dev/null || echo 0); \
		if [ "$$HM" = "0" ]; then \
			echo "  🟡 WARNING: $$(basename $$spec) 缺少測試矩陣"; \
			WARNINGS=$$((WARNINGS + 1)); NO_MATRIX=$$((NO_MATRIX + 1)); \
		fi; \
	done; \
	if [ $$NO_MATRIX -eq 0 ] && [ $$SPEC_COUNT -gt 0 ]; then echo "  ✅ 所有 SPEC 有測試矩陣"; \
	elif [ $$SPEC_COUNT -eq 0 ]; then echo "  ⚪ 無 SPEC"; fi; \
	echo ""; \
	\
	echo "=================================" ; \
	echo "🏥 審計摘要：🔴 $$BLOCKERS blocker | 🟡 $$WARNINGS warning | 🟢 $$INFOS info"; \
	if [ $$BLOCKERS -gt 0 ]; then \
		echo "⚠️  有 blocker 需先修復才能開始主任務"; \
	fi; \
	echo ""
	@echo "📊 更新審計基線..."
	@printf '{"last_audit":"%s","test_coverage_ratio":%s,"spec_count":%s,"adr_count":%s,"blockers":%s,"warnings":%s,"info":%s,"lint_warning_count":0,"todo_fixme_count":%s,"side_effects_unverified":0,"rollback_untested_count":0}\n' \
		"$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$${RATIO:-0}" "$${SPEC_COUNT:-0}" "$${ADR_COUNT:-0}" "$${BLOCKERS:-0}" "$${WARNINGS:-0}" "$${INFOS:-0}" "$${TODO_NO_OWNER:-0}" > .asp-audit-baseline.json 2>/dev/null
	@grep -q "asp-audit-baseline.json" .gitignore 2>/dev/null || echo ".asp-audit-baseline.json" >> .gitignore
	@echo "  ✅ .asp-audit-baseline.json 已更新"

audit-quick:
	@echo "🏥 快速審計（僅 blocker）..."
	@BLOCKERS=0; \
	for f in docs/adr/ADR-*.md; do \
		[ -f "$$f" ] || continue; \
		STATUS=$$(grep -m1 "狀態" "$$f" 2>/dev/null | grep -o '`[^`]*`' | tr -d '`'); \
		ADR_ID=$$(basename "$$f" .md | grep -o 'ADR-[0-9]*'); \
		if [ "$$STATUS" = "Draft" ]; then \
			if grep -r "$$ADR_ID" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" . >/dev/null 2>&1; then \
				echo "  🔴 BLOCKER: $$ADR_ID Draft 但有實作代碼"; \
				BLOCKERS=$$((BLOCKERS + 1)); \
			fi; \
		elif [ "$$STATUS" = "FIRM" ]; then \
			if grep -r "$$ADR_ID" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" . >/dev/null 2>&1; then \
				echo "  🟡 FIRM: $$ADR_ID POC 驗證中（允許 commit）"; \
			fi; \
		fi; \
	done; \
	SRC_COUNT=$$(find . -name "*.go" -o -name "*.ts" -o -name "*.py" -o -name "*.java" | grep -v node_modules | grep -v .git | grep -v vendor | wc -l); \
	TEST_COUNT=$$(find . \( -name "*_test.*" -o -name "*.test.*" -o -name "*.spec.*" -o -name "test_*" \) | grep -v node_modules | grep -v .git | wc -l); \
	if [ $$TEST_COUNT -eq 0 ] && [ $$SRC_COUNT -gt 5 ]; then \
		echo "  🔴 BLOCKER: $$SRC_COUNT source files, 0 test files"; \
		BLOCKERS=$$((BLOCKERS + 1)); \
	fi; \
	if [ $$BLOCKERS -eq 0 ]; then echo "  ✅ 無 blocker"; fi

doc-audit:
	@echo "📄 文件新鮮度掃描..."
	@STALE=0; \
	for spec in docs/specs/SPEC-*.md; do \
		[ -f "$$spec" ] || continue; \
		IMPL=$$(grep -A5 "追溯性\|Traceability" "$$spec" 2>/dev/null | grep -oE '[a-zA-Z0-9_/.-]+\.(go|ts|py|java|js)' | head -5); \
		for impl_file in $$IMPL; do \
			if [ -f "$$impl_file" ]; then \
				SPEC_DATE=$$(git log -1 --format=%at -- "$$spec" 2>/dev/null || echo 0); \
				IMPL_DATE=$$(git log -1 --format=%at -- "$$impl_file" 2>/dev/null || echo 0); \
				if [ "$$IMPL_DATE" -gt "$$SPEC_DATE" ] 2>/dev/null; then \
					SPEC_NAME=$$(basename "$$spec"); \
					echo "  🟡 STALE: $$SPEC_NAME ← $$impl_file (impl newer)"; \
					STALE=$$((STALE + 1)); \
				fi; \
			fi; \
		done; \
	done; \
	if [ $$STALE -eq 0 ]; then echo "  ✅ 所有 SPEC 文件同步（或無 Traceability 資料）"; fi

tech-debt-list:
	@echo "🔧 Tech Debt 彙總"
	@echo "================================="
	@echo ""
	@echo "── tech-debt: 標記 ──"
	@grep -rn "tech-debt:" --include="*.go" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.java" --include="*.md" . 2>/dev/null | grep -v node_modules | grep -v .git | grep -v '.asp/profiles/' | grep -v '.asp/templates/' || echo "  (none)"
	@echo ""
	@echo "── TODO 無 owner ──"
	@grep -rn "TODO[^(]" --include="*.go" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.java" . 2>/dev/null | grep -v node_modules | grep -v .git || echo "  (none)"
	@echo ""
	@echo "── FIXME ──"
	@grep -rn "FIXME" --include="*.go" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.java" . 2>/dev/null | grep -v node_modules | grep -v .git || echo "  (none)"
	@echo ""
	@echo "── DEPRECATED ──"
	@grep -rn "DEPRECATED\|@deprecated" --include="*.go" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.java" . 2>/dev/null | grep -v node_modules | grep -v .git || echo "  (none)"
	@echo ""
	@echo "── scenario-pending ──"
	@grep -rn "scenario-pending" . --include="*.md" 2>/dev/null | grep -v node_modules | grep -v .git | grep -v .asp/profiles || echo "  (無)"
	@echo "── test-pending ──"
	@grep -rn "test-pending" . --include="*.md" 2>/dev/null | grep -v node_modules | grep -v .git | grep -v .asp/profiles || echo "  (無)"

#---------------------------------------------------------------------------
# 任務協調
#---------------------------------------------------------------------------

task-start:
	@if [ -z "$(DESC)" ]; then echo "使用方式：make task-start DESC=\"任務描述\""; exit 1; fi
	@mkdir -p docs
	@echo "{\"desc\":\"$(DESC)\",\"ts\":\"$$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"started\"}" \
		>> docs/task-log.jsonl
	@echo "📌 任務已記錄：$(DESC)"

#---------------------------------------------------------------------------
# Autopilot
#---------------------------------------------------------------------------

autopilot-init:
	@if [ -f "ROADMAP.yaml" ]; then \
		echo "⚠️  ROADMAP.yaml already exists"; \
	else \
		cp .asp/templates/ROADMAP_Template.yaml ROADMAP.yaml; \
		echo "✅ Created ROADMAP.yaml from template"; \
	fi

inbox-triage:
	@bash .asp/scripts/inbox-triage.sh

autopilot-validate:
	@echo "🔍 Validating ROADMAP.yaml..."
	@python3 -c '\
import yaml, sys, os;\
data = yaml.safe_load(open("ROADMAP.yaml"));\
tasks = [t for m in data.get("milestones",[]) for t in m.get("tasks",[])];\
ids = [t["id"] for t in tasks];\
errors = [];\
[errors.append(t["id"]+" depends on unknown "+d) for t in tasks for d in (t.get("depends_on") or []) if d not in ids];\
[errors.append(t["id"]+" references missing "+t["adr"]) for t in tasks if t.get("adr") and not any(t["adr"] in f for f in (os.listdir("docs/adr") if os.path.isdir("docs/adr") else []))];\
docs = data.get("documents",{});\
[errors.append("Document "+k+": "+v+" not found") for k,v in docs.items() if v and not os.path.exists(v)];\
pending = sum(1 for t in tasks if t.get("status")=="pending");\
print("  Tasks: "+str(len(tasks))+" | Pending: "+str(pending)+" | Errors: "+str(len(errors)));\
[print("  \u274c "+e) for e in errors];\
sys.exit(1 if errors else 0)'
	@echo "📝 Updating CLAUDE.md project description..."
	@ASP_SCRIPT="$$(dirname "$$(realpath "$$(command -v make)")" 2>/dev/null)"; \
	  if [ -f ".asp/scripts/update-project-description.py" ]; then \
	    python3 .asp/scripts/update-project-description.py; \
	  else echo "  ℹ️  update-project-description.py not found, skipping"; fi

autopilot-status:
	@echo "🤖 Autopilot Status"
	@echo "==================="
	@if [ -f ".asp-autopilot-state.json" ]; then \
		python3 -c '\
import json; s=json.load(open(".asp-autopilot-state.json"));\
print("  Status:    "+s["status"]);\
print("  Sessions:  "+str(s["session_count"]));\
print("  Current:   "+s.get("current_task","N/A"));\
print("  Completed: "+str(len(s["completed"]))+"/"+str(s.get("total_tasks","?")));\
print("  Failed:    "+str(len(s.get("failed",[]))));\
print("  Blocked:   "+str(len(s.get("blocked",[]))));\
print("  Exit:      "+s.get("exit_reason","N/A"))'; \
	else echo "  (No autopilot state — not started)"; fi
	@echo ""
	@if [ -f "ROADMAP.yaml" ]; then \
		python3 -c '\
import yaml; data=yaml.safe_load(open("ROADMAP.yaml"));\
tasks=[t for m in data.get("milestones",[]) for t in m.get("tasks",[])];\
by_status={};\
[by_status.setdefault(t.get("status","pending"),[]).append(t["id"]) for t in tasks];\
print("  ROADMAP progress:");\
[print("    "+s+": "+str(len(by_status[s]))) for s in ["completed","in_progress","pending","blocked","failed","skipped"] if s in by_status]'; \
	else echo "  (No ROADMAP.yaml)"; fi

autopilot-reset:
	@rm -f .asp-autopilot-state.json
	@echo "🧹 Autopilot state cleared (ROADMAP.yaml unchanged)"

## doc-new TYPE=srs|sds|uiux|deploy — create a doc from template (replaces srs-new/sds-new/uiux-spec-new/deploy-spec-new)
doc-new:
	@if [ -z "$(TYPE)" ]; then \
		echo "使用方式：make doc-new TYPE=srs|sds|uiux|deploy"; exit 1; fi
	@mkdir -p docs
	@case "$(TYPE)" in \
		srs)    TMPL=SRS_Template.md;       DEST=docs/SRS.md ;; \
		sds)    TMPL=SDS_Template.md;       DEST=docs/SDS.md ;; \
		uiux)   TMPL=UIUX_SPEC_Template.md; DEST=docs/UIUX_SPEC.md ;; \
		deploy) TMPL=DEPLOY_SPEC_Template.md; DEST=docs/DEPLOY_SPEC.md ;; \
		*) echo "未知 TYPE=$(TYPE)。支援：srs | sds | uiux | deploy"; exit 1 ;; \
	esac; \
	if [ ! -f "$$DEST" ]; then \
		cp .asp/templates/$$TMPL $$DEST; \
		echo "✅ Created $$DEST from template"; \
	else echo "ℹ️  $$DEST already exists"; fi

# Backwards-compat aliases (deprecated, use doc-new TYPE= instead)
srs-new:         ; @$(MAKE) doc-new TYPE=srs
sds-new:         ; @$(MAKE) doc-new TYPE=sds
uiux-spec-new:   ; @$(MAKE) doc-new TYPE=uiux
deploy-spec-new: ; @$(MAKE) doc-new TYPE=deploy

#---------------------------------------------------------------------------
# Profile 驗證
#---------------------------------------------------------------------------

profile-validate:
	@bash .asp/scripts/validate-profile.sh

#---------------------------------------------------------------------------
# v5 Orchestrator 確定性腳本（ADR-015/SPEC-011）
#---------------------------------------------------------------------------

orch-classify: ## 任務分類（TASK="..." [HITL=minimal|standard|strict] [DOMAIN=1]）
	@bash .asp/scripts/orchestrator/classify-task.sh $(if $(filter 1,$(DOMAIN)),--domain,) --hitl "$${HITL:-standard}" "$$TASK"

orch-audit-check: ## 審計前置判斷（exit 2 = 需要審計）
	@bash .asp/scripts/orchestrator/audit-check.sh --project "$$(pwd)"

orch-round: ## 後置審計輪數（ACTION=get|increment|reset，exit 4 = 達上限）
	@bash .asp/scripts/orchestrator/post-audit-round.sh --"$${ACTION:-get}" --project "$$(pwd)"

orch-debt-log: ## 記錄 tech-debt（CATEGORY=... DESC="..." [SEVERITY=HIGH|MED|LOW] [DUE=YYYY-MM-DD]）
	@bash .asp/scripts/orchestrator/tech-debt-log.sh --category "$$CATEGORY" --desc "$$DESC" \
		$(if $(SEVERITY),--severity "$(SEVERITY)",) $(if $(DUE),--due "$(DUE)",)

.PHONY: orch-classify orch-audit-check orch-round orch-debt-log

#---------------------------------------------------------------------------
# v5 Metrics（ADR-013：基線量測與對照）
#---------------------------------------------------------------------------

rule-stats: ## 規則命中率統計（90 天窗；DAYS=N 覆寫）— 零命中列待刪候選 (ADR-018)
	@bash .asp/scripts/rule-stats.sh --days "$${DAYS:-90}"

.PHONY: rule-stats

asp-compile: ## Compile .ai_profile → .asp-compiled-profile.md (ADR-016)
	@bash .asp/scripts/asp-compile.sh --project "$$(pwd)"

asp-compile-check: ## Recompile only if stale (mtime check)
	@bash .asp/scripts/asp-compile.sh --project "$$(pwd)" --check

.PHONY: asp-compile asp-compile-check

asp-metrics: ## Show repo metrics JSON (lines / rules / context tax)
	@bash .asp/scripts/asp-metrics.sh --repo-root "$$(pwd)"

asp-metrics-baseline: ## Write metrics baseline to .asp-metrics-baseline.json (committed)
	@bash .asp/scripts/asp-metrics.sh --repo-root "$$(pwd)" --output .asp-metrics-baseline.json

asp-metrics-compare: ## Compare current metrics vs baseline (BASELINE=.asp-metrics-baseline.json)
	@bash .asp/scripts/asp-metrics.sh --repo-root "$$(pwd)" --compare "$${BASELINE:-.asp-metrics-baseline.json}"

.PHONY: asp-metrics asp-metrics-baseline asp-metrics-compare

# ─── Telemetry ───────────────────────────────────────────────────────────────
daily-audit: ## Generate daily health report to .asp-daily-report.md (P3)
	@CLAUDE_PROJECT_DIR="$$(pwd)" bash .asp/scripts/daily-audit.sh

#---------------------------------------------------------------------------
# v5 分區（ADR-017）：Experimental / Showcase targets 隨目錄存在自動載入
# （安裝到一般專案時無這兩個目錄，targets 自然消失——零 stub 維護）
#---------------------------------------------------------------------------
-include experimental/multi-agent/Makefile.inc
-include showcase/Makefile.inc
