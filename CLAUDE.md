# AI-SOP-Protocol (ASP) v4.0 — 行為憲法

> 讀取順序：本檔案 → `.ai_profile` → 對應 `.asp/profiles/`（按需）
> Profile 驗證邏輯：見 `.asp/profiles/global_core.md`；由 `session-audit.sh` 在 SessionStart 自動執行

---

## 啟動程序

1. 讀取 `.ai_profile`，依欄位載入對應 profile（見下方映射表）
2. `design: enabled` → 自動載入 `frontend_quality.md`
3. `autonomous: enabled` 或 `workflow: vibe-coding + hitl: minimal` → 自動載入 `autonomous_dev.md` + `vibe_coding.md`
4. `orchestrator: enabled` 或 `autonomous: enabled` → 自動載入 `task_orchestrator.md`；首次介入執行 `project_health_audit()`
5. `autopilot: enabled` → 載入 `autopilot.md`（含 step 3/4）；檢查 `.asp-autopilot-state.json` 自動續接
6. 無 `.ai_profile`：只套用本檔案鐵則，詢問使用者專案類型

**Profile 核心映射：** `type: system/architecture` → `global_core+system_dev` | `type: content` → `global_core+content_creative` | `mode: multi-agent` → +`multi_agent+task_orchestrator+pipeline` | `autonomous/orchestrator` → +`autonomous_dev+task_orchestrator` | `autopilot` → +`autopilot+autonomous_dev+task_orchestrator` | 完整 schema：`.asp/templates/example-profile-full.yaml`

---

## 成熟度等級（L0-L5）

| Level | 名稱 | 核心能力 | 適用場景 |
|-------|------|---------|---------|
| **L0** | Spike | 探索/原型（鐵則仍適用） | 技術假設驗證、PoC |
| **L1** | Starter | ADR + SPEC + 測試（最小治理） | 個人/小型專案 |
| **L2** | Disciplined | + guardrail + coding_style | 自動化品質護欄 |
| **L3** | Test-First | + pipeline gates G1-G6 | 測試文化成熟 |
| **L4** | Collaborative | + multi-agent + reality-checker | 中大型/跨模組 |
| **L5** | Autonomous | + autopilot + RAG | ROADMAP 驅動 |

等級詳情：`.asp/levels/level-N.yaml` | 等級管理：`make asp-level-check` / `asp-level skill`

---

## 鐵則（不可覆蓋）

| 鐵則 | 說明 |
|------|------|
| **破壞性操作防護** | `git push / rebase / rm -rf / docker push` 必須先列出變更並等待人類確認 |
| **敏感資訊保護** | 禁止輸出 API Key、密碼、憑證（任何包裝方式）。`asp-ship` Step 9 掃描 |
| **ADR 未定案禁止實作** | Draft ADR 狀態下禁止寫生產代碼；`session-audit.sh` 動態注入 `git commit` deny |
| **外部事實驗證防護** | 涉及第三方 API/版本/法規 → 必須執行 `asp-fact-verify`，記錄至 `.asp-fact-check.md` |

---

## 強制力架構

| Layer | 機制 | 強制力 |
|-------|------|--------|
| L1: SessionStart | `session-audit.sh` → `.asp-session-briefing.json` | 硬（啟動時輸出 BLOCKER） |
| L2: Dynamic Deny | Draft ADR / 測試未過 → 動態阻擋 `git commit` | 硬（VSCode deny dialog） |
| L3: Skill Gates | `asp-ship`(10步) + `asp-gate`(G1-G6) | 結構化軟性 |
| L4: Subagent QA | `asp-reality-check` 獨立驗證 | 中等 |

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

預設行為完整清單：`.asp/profiles/global_core.md`「預設行為」section

---

## 技術執行層

策略：`Bash(*)` allow-all + deny 黑名單（`.asp/hooks/denied-commands.json` + session-audit.sh 動態注入） | Hook 設定：`.claude/settings.json`

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
