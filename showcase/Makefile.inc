# showcase/Makefile.inc — Showcase 元件 targets（v5 ADR-017）
# 由 core .asp/Makefile.inc 的 `-include showcase/Makefile.inc` 載入：
# 目錄存在才生效；安裝到一般專案時 targets 自然消失（裝回 ~/.claude/asp 的
# 使用者由原始佈局路徑直接呼叫 python3/bash）。

SHOWCASE := showcase

rag-index: ## [showcase] 建立 RAG 索引
	@python3 $(SHOWCASE)/rag/scripts/build_index.py

rag-search: ## [showcase] 查詢 RAG（Q="..."）
	@python3 $(SHOWCASE)/rag/scripts/search.py "$$Q"

rag-stats: ## [showcase] RAG 索引統計
	@python3 $(SHOWCASE)/rag/scripts/stats.py

rag-rebuild: ## [showcase] 重建 RAG 索引
	@python3 $(SHOWCASE)/rag/scripts/build_index.py --rebuild

asp-telemetry-collect: ## [showcase] 收集 telemetry 事件
	@python3 $(SHOWCASE)/telemetry/collect.py
	@echo "[ASP] Telemetry event collected"

asp-telemetry-report: ## [showcase] telemetry 近 7 天報表
	@python3 $(SHOWCASE)/telemetry/report.py --days 7

asp-telemetry-prune: ## [showcase] 清理 90 天前 telemetry
	@python3 $(SHOWCASE)/telemetry/prune.py --days 90

asp-performance-review: ## [showcase] AI 表現月度回顧
	@python3 $(SHOWCASE)/ai-performance/monthly-review.py

asp-performance-review-update: ## [showcase] 月度回顧 + 更新 trust-tier
	@python3 $(SHOWCASE)/ai-performance/monthly-review.py --update

.PHONY: rag-index rag-search rag-stats rag-rebuild \
        asp-telemetry-collect asp-telemetry-report asp-telemetry-prune \
        asp-performance-review asp-performance-review-update
