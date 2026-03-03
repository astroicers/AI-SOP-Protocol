# AI-SOP-Protocol — Makefile
# 目的：封裝重複指令，節省 Token，降低操作失誤風險
# 使用方式：依專案需求保留/修改對應區塊
# ASP_MAKEFILE_VERSION=2.0.0

APP_NAME ?= app-service
VERSION  ?= latest

# --- 條件載入：讀取 .ai_profile 的 type 欄位 ---
# content 類型專案隱藏 Docker/Test/Lint/Deploy targets
ASP_TYPE := $(shell grep '^type:' .ai_profile 2>/dev/null | awk '{print $$2}')

.PHONY: help \
        build clean deploy logs \
        test test-filter coverage lint \
        diagram \
        adr-new adr-list \
        spec-new spec-list \
        postmortem-new postmortem-list \
        agent-done agent-status agent-reset agent-locks agent-unlock agent-lock-gc \
        session-checkpoint session-log \
        rag-index rag-search rag-stats rag-rebuild \
        guardrail-log guardrail-reset

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
	@echo "📐 Docs:        diagram"
endif
	@echo "📋 ADR:         adr-new TITLE=... | adr-list"
	@echo "📄 Spec:        spec-new TITLE=... | spec-list"
	@echo "🔥 Postmortem:  postmortem-new TITLE=... | postmortem-list"
	@echo "🤖 Agent:       agent-done TASK=... STATUS=... | agent-status | agent-reset | agent-unlock FILE=... | agent-lock-gc"
	@echo "💾 Session:     session-checkpoint NEXT=... | session-log"
	@echo "🧠 RAG:         rag-index | rag-search Q=... | rag-stats | rag-rebuild"
	@echo "🛡  Guardrail:   guardrail-log | guardrail-reset"
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
	@go test ./... -v -race -coverprofile=coverage.out 2>/dev/null && exit 0 || true
	@pytest ./tests -v --cov=. 2>/dev/null && exit 0 || true
	@npm test 2>/dev/null && exit 0 || true
	@echo "⚠️  未偵測到測試框架，請手動設定"

test-filter:
	@if [ -z "$(FILTER)" ]; then echo "使用方式：make test-filter FILTER=xxx"; exit 1; fi
	@echo "🧪 Running filtered: $(FILTER)"
	@go test ./... -run $(FILTER) -v 2>/dev/null && exit 0 || true
	@pytest ./tests -k $(FILTER) -v 2>/dev/null && exit 0 || true
	@npm test -- --grep "$(FILTER)" 2>/dev/null && exit 0 || true

coverage:
	@go tool cover -html=coverage.out 2>/dev/null || \
	coverage html && open htmlcov/index.html 2>/dev/null || \
	echo "⚠️  請先執行 make test"

lint:
	@echo "🔍 Linting..."
	@golangci-lint run ./... 2>/dev/null && exit 0 || true
	@flake8 . 2>/dev/null && exit 0 || true
	@npm run lint 2>/dev/null && exit 0 || true
	@echo "⚠️  未偵測到 Lint 工具"

#---------------------------------------------------------------------------
# Architecture Diagram（type: content 時隱藏）
#---------------------------------------------------------------------------

diagram:
	@echo "📐 Generating architecture diagram..."
	@# 從 architecture.md 提取 mermaid 區塊再餵給 mmdc
	@awk '/```mermaid/{flag=1;next}/```/{flag=0}flag' docs/architecture.md > /tmp/arch.mmd 2>/dev/null || true
	@mmdc -i /tmp/arch.mmd -o docs/architecture.png 2>/dev/null || \
	echo "⚠️  請安裝 mermaid-cli: npm install -g @mermaid-js/mermaid-cli"

else
# --- content 類型的 stub targets（避免 make: *** No rule to make target 錯誤）---
build clean deploy logs test test-filter coverage lint diagram:
	@echo "⚠️  此指令不適用於 content 類型專案（目前 type: $(ASP_TYPE)）"
endif

#---------------------------------------------------------------------------
# ADR 管理
#---------------------------------------------------------------------------

adr-new:
	@if [ -z "$(TITLE)" ]; then read -p "ADR 標題: " TITLE; fi; \
	mkdir -p docs/adr; \
	COUNT=$$(ls docs/adr/ADR-*.md 2>/dev/null | wc -l | tr -d ' '); \
	NUM=$$(printf "%03d" $$((COUNT + 1))); \
	SLUG=$$(echo "$(TITLE)" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-'); \
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
		echo "  $$TITLE [$$STATUS]"; \
	done || echo "  (無 ADR)"

#---------------------------------------------------------------------------
# Spec 管理
#---------------------------------------------------------------------------

spec-new:
	@if [ -z "$(TITLE)" ]; then read -p "規格書標題: " TITLE; fi; \
	mkdir -p docs/specs; \
	COUNT=$$(ls docs/specs/SPEC-*.md 2>/dev/null | wc -l | tr -d ' '); \
	NUM=$$(printf "%03d" $$((COUNT + 1))); \
	SLUG=$$(echo "$(TITLE)" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-'); \
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
	COUNT=$$(ls docs/postmortems/PM-*.md 2>/dev/null | wc -l | tr -d ' '); \
	NUM=$$(printf "%03d" $$((COUNT + 1))); \
	SLUG=$$(echo "$(TITLE)" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-'); \
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
# Multi-Agent
#---------------------------------------------------------------------------

agent-done:
	@if [ -z "$(TASK)" ] || [ -z "$(STATUS)" ]; then \
		echo "使用方式：make agent-done TASK=TASK-001 STATUS=success"; exit 1; fi
	@mkdir -p .agent-events
	@echo "{\"task\":\"$(TASK)\",\"status\":\"$(STATUS)\",\"ts\":\"$$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"reason\":\"$(REASON)\"}" \
		>> .agent-events/completed.jsonl
	@echo "✅ Hook fired: $(TASK) → $(STATUS)"

agent-status:
	@echo "=== Agent 事件紀錄 ==="; \
	if [ -f .agent-events/completed.jsonl ]; then \
		python3 -c "import sys,json; \
[print(f'  [{l[\"status\"].upper()}] {l[\"task\"]} @ {l[\"ts\"]}') \
for l in (json.loads(x) for x in open('.agent-events/completed.jsonl'))]" 2>/dev/null || \
		cat .agent-events/completed.jsonl; \
	else echo "  (無事件紀錄)"; fi

agent-reset:
	@rm -f .agent-events/completed.jsonl
	@echo "🧹 Agent 事件紀錄已清空"

agent-unlock:
	@if [ -z "$(FILE)" ]; then echo "使用方式：make agent-unlock FILE=src/store/user.go"; exit 1; fi
	@if [ -f .agent-lock.yaml ]; then \
		python3 -c "import yaml; data = yaml.safe_load(open('.agent-lock.yaml')) or {}; data.get('locked_files', {}).pop('$(FILE)', None); yaml.dump(data, open('.agent-lock.yaml','w')); print('🔓 已解鎖: $(FILE)')" 2>/dev/null || echo "⚠️  需要 pip install pyyaml"; \
	else echo "  (無鎖定記錄)"; fi

agent-lock-gc:
	@echo "🧹 清理逾時鎖定（> 2 小時）..."
	@if [ -f .agent-lock.yaml ]; then \
		python3 -c "import yaml,datetime; f=open('.agent-lock.yaml'); data=yaml.safe_load(f) or {}; f.close(); locks=data.get('locked_files',{}); now=datetime.datetime.utcnow(); removed=[k for k,v in list(locks.items()) if now>datetime.datetime.fromisoformat(v.get('expires','2000-01-01').replace('Z',''))]; [locks.pop(k) for k in removed]; yaml.dump(data,open('.agent-lock.yaml','w')); print(f'已清理 {len(removed)} 個逾時鎖定：{removed}' if removed else '無逾時鎖定')" 2>/dev/null || echo "⚠️  需要 pip install pyyaml"; \
	else echo "  (無鎖定記錄)"; fi

agent-locks:
	@if [ -f .agent-lock.yaml ]; then \
		echo "🔒 文件鎖定清單："; cat .agent-lock.yaml; \
	else echo "  (無文件鎖定)"; fi

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
# RAG 知識庫
#---------------------------------------------------------------------------

rag-index:
	@echo "🔍 Building RAG index (incremental)..."
	@python3 .asp/scripts/rag/build_index.py \
		--source docs/ \
		--source .asp/profiles/ \
		--output .rag/index \
		--model all-MiniLM-L6-v2 \
		--incremental 2>/dev/null || \
	echo "⚠️  請先執行: pip install chromadb sentence-transformers"

rag-search:
	@if [ -z "$(Q)" ]; then echo "使用方式：make rag-search Q=\"你的問題\""; exit 1; fi
	@python3 .asp/scripts/rag/search.py --query "$(Q)" --top-k 3 2>/dev/null || \
	echo "⚠️  RAG 尚未初始化，請先執行 make rag-index"

rag-stats:
	@python3 .asp/scripts/rag/stats.py 2>/dev/null || \
	echo "⚠️  RAG 尚未初始化，請先執行 make rag-index"

rag-rebuild:
	@rm -rf .rag/index
	@$(MAKE) rag-index

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
