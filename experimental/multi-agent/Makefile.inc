# experimental/multi-agent/Makefile.inc — 凍結元件 targets（v5 ADR-017）
# 由 core .asp/Makefile.inc 的 `-include experimental/multi-agent/Makefile.inc`
# 載入：目錄存在才生效；安裝到一般專案（無此目錄）時 targets 自然消失。

EXP_MA := experimental/multi-agent

agent-worktree-list: ## [frozen] 列出 multi-agent worktrees
	@bash $(EXP_MA)/scripts/worktree-list.sh

agent-worktree-gc: ## [frozen] 回收過期 worktrees
	@bash $(EXP_MA)/scripts/worktree-gc.sh

agent-worktree-gc-dry-run: ## [frozen] 預覽 worktree 回收
	@bash $(EXP_MA)/scripts/worktree-gc.sh --dry-run

agent-rollback: ## [frozen] 回滾 multi-agent 任務（TASK=...）
	@bash $(EXP_MA)/scripts/rollback.sh --task "$$TASK"

agent-rollback-dry-run: ## [frozen] 預覽回滾
	@bash $(EXP_MA)/scripts/rollback.sh --task "$$TASK" --dry-run

agent-team-recommend: ## [frozen] 場景化團隊推薦（見 agents/team_compositions.yaml）
	@echo "（frozen）場景表：$(EXP_MA)/agents/team_compositions.yaml；skill: $(EXP_MA)/skills/asp-team-pick.md"

test-experimental: ## [frozen] 跑凍結元件測試（不在 make test 快速路徑）
	@PASS=0; FAIL=0; \
	for t in $(EXP_MA)/tests/test_*.sh; do \
		if bash "$$t" >/dev/null 2>&1; then PASS=$$((PASS+1)); echo "  ✅ $$t"; \
		else FAIL=$$((FAIL+1)); echo "  ❌ $$t"; fi; \
	done; \
	echo "test-experimental: $$PASS passed, $$FAIL failed"; \
	[ "$$FAIL" -eq 0 ]

lint-experimental: ## [frozen] shellcheck 凍結腳本
	@shellcheck $(EXP_MA)/scripts/*.sh $(EXP_MA)/tests/*.sh $(EXP_MA)/tests/perf/*.sh && echo "✅ lint-experimental passed"

.PHONY: agent-worktree-list agent-worktree-gc agent-worktree-gc-dry-run \
        agent-rollback agent-rollback-dry-run agent-team-recommend \
        test-experimental lint-experimental
