# AI-SOP-Protocol (ASP) v4.0 — 行為憲法

> 讀取順序：本檔案 → `.ai_profile` → 對應 `~/.claude/asp/profiles/`（按需）
> Profile 驗證邏輯：見 `~/.claude/asp/profiles/global_core.md`；由 `session-audit.sh` 在 SessionStart 自動執行

---

## 啟動程序

0. **（v5，ADR-016）** `.asp-compiled-profile.md` 存在 → **直接讀取之**（asp-compile 編譯產物，
   檔頭列來源清單與行數；SessionStart hook 已做 mtime 比對自動重編）。不存在或 briefing 顯示
   `compiled_profile_ok: false` → 走下列散文載入（fallback）
1. 讀取 `.ai_profile`，依欄位載入對應 profile（見下方映射表）
2. `design: enabled` → 自動載入 `frontend_quality.md`
3. `autonomous: enabled` 或 `workflow: vibe-coding + hitl: minimal` → 自動載入 `autonomous_dev.md`（HITL 等級定義已內建 `global_core.md`，ADR-014）；單獨 `workflow: vibe-coding` → 載入 `loose_mode.md`
4. `orchestrator: enabled` 或 `autonomous: enabled` → 自動載入 `task_orchestrator.md`；首次介入執行 `project_health_audit()`
5. `autopilot: enabled` → 載入 `asp-autopilot` skill 之 Part 2 完整執行規格（v4.4 起為唯一 canonical source，ADR-006 Item 7；含 step 3/4）；檢查 `.asp-autopilot-state.json` 自動續接
6. 無 `.ai_profile`：只套用本檔案鐵則，詢問使用者專案類型

**Profile 核心映射（機械版 = `~/.claude/asp/config/profile-map.yaml`，single source of truth，ADR-013）：** `type: system/architecture` → `global_core+system_dev` | `type: content` → `global_core+content_creative` | `mode: multi-agent` → +`task_orchestrator+pipeline` + 🟡 Experimental 警告（v5 ADR-017：multi-agent 已凍結，Part G 內容在 experimental/multi-agent/profiles/） | `autonomous/orchestrator` → +`autonomous_dev+task_orchestrator` | `autopilot` → `asp-autopilot` skill Part 2 +`autonomous_dev+task_orchestrator`（v4.4：autopilot profile 已整併入 skill） | guardrail / escalation 已內建 `global_core`（v5，ADR-014） | 完整 schema：`~/.claude/asp/templates/example-profile-full.yaml`

---

## 成熟度等級（v5 三級制，ADR-014）

| Level | 核心能力 | 適用場景 | 吸收的 v4 等級 |
|-------|---------|---------|---------------|
| **loose** | 探索豁免（`[spike]` 標記）+ ADR/SPEC/測試入門（鐵則仍適用） | 技術假設驗證、PoC、個人/小型專案 | L0, L1 |
| **standard** | + coding_style + pipeline gates G1-G6 | 自動化品質護欄、測試文化成熟 | L2, L3 |
| **autonomous** | + orchestrator + autonomous_dev + autopilot + RAG + reality-checker | ROADMAP 驅動、中大型/跨模組 | L4, L5 |

舊數字值（0-5）由 `level-resolve.sh` 自動映射並印 deprecation 提示（v6 移除）。
等級詳情：`~/.claude/asp/levels/{loose,standard,autonomous}.yaml` | 等級管理：`make asp-level-check` / `asp-level skill`

---

## 鐵則（不可覆蓋）

| 鐵則 | 說明 |
|------|------|
| **破壞性操作防護** | `git push origin main / --force / rebase / rm -rf / docker push / gh pr merge` 必須人類確認；`git push origin feature/* 或 asp/*` 由 autopilot auto-PR 流程允許 |
| **敏感資訊保護** | 禁止輸出 API Key、密碼、憑證（任何包裝方式）。`asp-ship` Step 9 掃描 |
| **ADR 未定案禁止實作** | `Draft` ADR 禁止生產代碼；`FIRM` ADR 允許 commit（需 Verification Evidence，audit 輸出 🟡）；`session-audit.sh` 動態注入 deny |
| **外部事實驗證防護** | 涉及第三方 API/版本/法規 → 必須查證並記錄至 `.asp-fact-check.md`（邏輯由 `global_core.md` Fact Verification Gate 執行） |

> **規則存留治理（v5 ADR-018）**：`make rule-stats` 顯示 90 天零命中的規則，於下個 minor
> 版本評估移除（移除動作本身仍走 ADR）。**鐵則（上表 4 條 + Iron Rule A/B/C，registry
> `exempt: true`）豁免此條**——鐵則語意不變是 v5 紅線。命中記錄：`~/.claude/asp/metrics/rule-hits.jsonl`。

---

## 強制力架構

| Layer | 機制 | 強制力 |
|-------|------|--------|
| L1: SessionStart | `session-audit.sh` → `.asp-session-briefing.json` | 硬（啟動時輸出 BLOCKER） |
| L2: Dynamic Deny | `Draft` ADR / 測試未過 → 動態阻擋 `git commit`；`FIRM` ADR → 允許但記錄 bypass log | 硬（VSCode deny dialog） |
| L3: Skill Gates | `asp-ship`(10步，含 Step 9.6 gate-log 後驗) + `asp-gate`(G1-G6) + `asp-plan` Step 5.5 auto-gate（ADR-009 + SPEC-006 已落地：staged ADR/SPEC 機械觸發 G1/G2 subagent，報告存 `.asp-gate-log/`） | 結構化軟性 |
| L4: Subagent QA | `asp-reality-check` 獨立驗證（on-demand） | 中等 |

**AI 必須**：Session 啟動時讀取 `.asp-session-briefing.json`，向使用者報告 BLOCKER。

**必須調用 Skill 的時機（跳過須輸出 ⚠️ ASP BYPASS 警告，見 `asp-ship` Step 10）：**
- 實作前 → `/asp-gate G1,G2` → 測試寫完 → `/asp-gate G3` → 實作完 → `/asp-gate G4`
- 任何 git commit 前 → `/asp-ship` | 驗證階段 → `/asp-gate G5` + `/asp-reality-check`

---

## 標準工作流

```
需求 → [ADR 建立] → SDD 設計 → TDD 測試 → 實作 → 文件同步 → 確認後部署
         ↑ 架構影響時必須        ↑ 預設行為，可調整
```

預設行為完整清單：`~/.claude/asp/profiles/global_core.md`「預設行為」section

---

## 技術執行層

策略：`Bash(*)` allow-all + deny 黑名單（`~/.claude/asp/hooks/denied-commands.json` + session-audit.sh 動態注入） | Hook 設定：`.claude/settings.json`

---

## 常用指令

| 動作 | 指令 |
|------|------|
| 新增 ADR | `make adr-new TITLE="..."` |
| 新增 SPEC | `make spec-new TITLE="..."` |
| 執行測試 | `make test` |
| 健康審計 | `make audit-health` |
| 重新執行審計 | `make asp-refresh` |
| 解除 commit 阻擋 | `make asp-unlock-commit` |

完整指令：`make help` | 入門文件：`docs/where-to-start.md`

## Agent skills

| Role | Detail |
|------|--------|
| Issue tracker | GitHub Issues (`astroicers/AI-SOP-Protocol`) — see `docs/agents/issue-tracker.md` |
| Triage labels | `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix` — see `docs/agents/triage-labels.md` |
| Domain docs | `CONTEXT.md` at root + `docs/adr/` — see `docs/agents/domain.md` |
