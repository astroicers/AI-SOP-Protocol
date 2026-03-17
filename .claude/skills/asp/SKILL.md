---
name: asp
description: |
  Use when working with AI-SOP-Protocol (ASP) framework workflows.
  Handles: planning new features, architecture decisions, ADR creation, SPEC writing,
  pre-commit checklists, code review, project health audits, autopilot execution.
  Triggers: asp-plan, asp-ship, asp-audit, asp-review, asp-autopilot,
  plan feature, new feature, create ADR, write SPEC, pre-commit check, ready to commit,
  code review, health audit, check project health, autopilot, run roadmap,
  計劃功能, 新功能, 建立 ADR, 寫規格, 提交前, 準備提交, 程式碼審查, 審查,
  健康審計, 健康檢查, 自動執行, 跑 roadmap, 審計.
---

# ASP Skill Router

AI-SOP-Protocol (ASP) 的 Claude Code skill 命名空間。根據用戶意圖自動路由到對應的子 skill。

## 子 Skill 路由表

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| 規劃新功能 / 建立 ADR / 寫 SPEC | plan, new feature, 計劃, 新功能, 設計, ADR, SPEC | asp-plan |
| 提交前檢查 | ship, commit, 提交, pre-commit, 準備提交 | asp-ship |
| 健康審計 | audit, health check, 審計, 健康, project status | asp-audit |
| 程式碼審查 | review, code review, 審查, 幫我看 | asp-review |
| 自動執行 ROADMAP | autopilot, run roadmap, 自動執行, 續接, resume | asp-autopilot |

## 如何使用

每個子 skill 是自包含的——載入時不需要 `.ai_profile` 已設定，行為邏輯直接編碼在 skill 文件中。

當用戶請求匹配上表中任一觸發詞時，讀取並遵循對應的子 skill 文件（`.claude/skills/asp/asp-*.md`）。

## 參考資源

- 入門指南：`docs/where-to-start.md`
- Profile 說明：`.asp/profiles/`
- 所有指令：`make help`
