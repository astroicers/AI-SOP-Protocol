---
name: asp
description: |
  Use when working with AI-SOP-Protocol (ASP) framework workflows.
  Handles: planning new features, architecture decisions, ADR creation, SPEC writing,
  pre-commit checklists, code review, project health audits, autopilot execution,
  multi-agent dispatch, QA verification, security review, reality checks, impact analysis,
  pipeline gate evaluation, enforcement status.
  Triggers: asp-plan, asp-ship, asp-audit, asp-review, asp-autopilot,
  asp-dispatch, asp-qa, asp-security, asp-reality-check, asp-impact, asp-gate,
  plan feature, new feature, create ADR, write SPEC, pre-commit check, ready to commit,
  code review, health audit, check project health, autopilot, run roadmap,
  dispatch, assign, verify, qa, security, reality check, impact analysis,
  計劃功能, 新功能, 建立 ADR, 寫規格, 提交前, 準備提交, 程式碼審查, 審查,
  健康審計, 健康檢查, 自動執行, 跑 roadmap, 審計,
  分派, 指派, 驗證, 品質, 安全, 影響分析.
---

# ASP Skill Router

AI-SOP-Protocol (ASP) 的 Claude Code skill 命名空間。根據用戶意圖自動路由到對應的子 skill。

## 子 Skill 路由表

### 核心工作流（v2.x）

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| 規劃新功能 / 建立 ADR / 寫 SPEC | plan, new feature, 計劃, 新功能, 設計, ADR, SPEC | asp-plan |
| 提交前檢查 | ship, commit, 提交, pre-commit, 準備提交 | asp-ship |
| 健康審計 | audit, health check, 審計, 健康, project status | asp-audit |
| 程式碼審查 | review, code review, 審查, 幫我看 | asp-review |
| 自動執行 ROADMAP | autopilot, run roadmap, 自動執行, 續接, resume | asp-autopilot |

### Multi-Agent 協作（v3.0）

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| 多 Agent 任務分派 | dispatch, assign, 分派, 指派, 組隊 | asp-dispatch |
| 獨立品質驗證 | verify, qa, 驗證, 品質, quality check | asp-qa |
| 安全審查 | security, security review, 安全, 安全審查, 資安 | asp-security |
| 懷疑主義驗收 | reality check, 夠了嗎, is this ready, 能交了嗎, final check | asp-reality-check |
| 依賴影響分析 | impact, impact analysis, 影響, 影響分析, what does this affect | asp-impact |

### 強制力與品質門檻（v3.4）

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| Pipeline 品質門檻評估 | gate, G1-G6, quality gate, 品質門檻, 關卡 | asp-gate |

## 如何使用

每個子 skill 是自包含的——載入時不需要 `.ai_profile` 已設定，行為邏輯直接編碼在 skill 文件中。

當用戶請求匹配上表中任一觸發詞時，讀取並遵循對應的子 skill 文件（`.claude/skills/asp/asp-*.md`）。

## 角色 ↔ Skill 映射（v3.0）

| Agent 角色 | 對應 Skill | 角色定義 |
|-----------|-----------|---------|
| Orchestrator | asp-dispatch | 任務分類 + 團隊推薦 + 分派 |
| arch | asp-plan | ADR + 架構影響評估 |
| spec | asp-plan | SPEC 七欄位撰寫 |
| dep-analyst | asp-impact | 依賴圖 + 並行標記 |
| qa | asp-qa | 獨立驗證 + 偷渡偵測 |
| sec | asp-security | OWASP + 憑證掃描 |
| reality | asp-reality-check | 懷疑主義品質門驗收 |
| doc | asp-ship | 文件管線 + 提交前檢查 |
| tdd | (由 asp-plan 的 TDD 步驟覆蓋) | TDD 測試撰寫 |
| impl | (核心開發角色，遵循 SPEC + auto_fix_loop) | 生產代碼實作 |
| integ | (由 asp-dispatch 的 converge_tracks 覆蓋) | 並行軌道匯流 |

## 參考資源

- 入門指南：`docs/where-to-start.md`
- Profile 說明：`.asp/profiles/`
- 角色定義：`.asp/agents/*.yaml`
- 團隊組成：`.asp/agents/team_compositions.yaml`
- 架構文件：`docs/multi-agent-architecture.md`
- 所有指令：`make help`
