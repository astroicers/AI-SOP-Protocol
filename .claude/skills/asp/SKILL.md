---
name: asp
description: |
  Use when working with AI-SOP-Protocol (ASP) framework workflows.
  Handles: planning new features, architecture decisions, ADR creation, SPEC writing,
  pre-commit checklists, code review, project health audits, autopilot execution,
  QA verification, security review, reality checks, impact analysis,
  pipeline gate evaluation, enforcement status.
  Triggers: asp-plan, asp-ship, asp-audit, asp-review, asp-autopilot,
  asp-dev-qa-loop, asp-reality-check, asp-impact, asp-gate,
  plan feature, new feature, create ADR, write SPEC, pre-commit check, ready to commit,
  code review, health audit, check project health, autopilot, run roadmap,
  verify, qa, security, reality check, impact analysis,
  計劃功能, 新功能, 建立 ADR, 寫規格, 提交前, 準備提交, 程式碼審查, 審查,
  健康審計, 健康檢查, 自動執行, 跑 roadmap, 審計,
  驗證, 品質, 安全, 影響分析.
---

# ASP Skill Router

> **注意**：此目錄（`.claude/skills/asp/`）為 **source copy**（版本控制）。
> 安裝後的 active 版本在 `~/.claude/skills/asp/`，由 `bash ~/.claude/scripts/asp-sync.sh` 同步。

AI-SOP-Protocol (ASP) 的 Claude Code skill 命名空間。根據用戶意圖自動路由到對應的子 skill。

## 子 Skill 路由表

### 核心工作流（v2.x）

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| 規劃新功能 / 建立 ADR / 寫 SPEC | plan, new feature, 計劃, 新功能, 設計, ADR, SPEC | asp-plan |
| 提交前檢查 | ship, commit, 提交, pre-commit, 準備提交 | asp-ship |
| 健康審計 | audit, health check, 審計, 健康, project status | asp-audit |
| 程式碼審查 | review, code review, 審查, 幫我看 | asp-review |
| 審查清單 / 面向定義 / 反模式庫 | review checklist, 審查清單, review dimensions, finding format, 面向定義 | asp-review-checklist |
| 自動執行 ROADMAP | autopilot, run roadmap, 自動執行, 續接, resume | asp-autopilot |

### 品質驗證與影響分析

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| 獨立品質驗證 / Dev↔QA 迴路 | verify, qa, 驗證, 品質, quality check, dev qa loop, qa loop | asp-dev-qa-loop |
| 懷疑主義驗收 | reality check, 夠了嗎, is this ready, 能交了嗎, final check | asp-reality-check |
| 依賴影響分析 | impact, impact analysis, 影響, 影響分析, what does this affect | asp-impact |

> Multi-agent 任務分派（asp-dispatch / asp-team-pick / asp-handoff）已於 v5 凍結為
> Experimental（ADR-017）——見 `experimental/multi-agent/README.md`（含手動啟用方式）。

### 強制力與品質門檻（v3.4）

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| Pipeline 品質門檻評估 | gate, G1-G6, quality gate, 品質門檻, 關卡 | asp-gate |

### 成熟度等級（v3.5）

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| ASP 成熟度評估與升級 | level, maturity, 成熟度, 等級, level check, 升級 ASP, 我該升到哪一級 | asp-level |

### v4.0 新增 Skill（抽自 Profile）

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| 升級處理 / 緊急問題 | escalate, P0, P1, 緊急, 卡住, critical | （非 skill）依 `global_core.md`「升級路徑」章節處理（v5 ADR-014/017；asp-handoff 已凍結至 experimental/） |
| Dev↔QA 品質迴路 | dev qa loop, qa loop, 開發品質迴路 | asp-dev-qa-loop |
| 領域詞彙管理 / CONTEXT.md 建立與更新 | context, 詞彙, vocabulary, 術語, domain, grill-with-docs, context 不存在, 術語衝突 | asp-context |
| 外部 AI 跨廠商 review（Layer 3） | external review, Layer 3, cross-vendor review, 外部審查, 跨廠商審查, crypto review, high-stakes review | asp-external-review |
| 版本發布 / CHANGELOG / Release PR | release, 發布, 版本, version bump, tag, changelog, CHANGELOG, release pr | asp-release |

### v5 新增 Skill（meta，ADR-023）

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| 撰寫/重構 ASP skill（過 skill 級 lint） | write skill, author skill, new skill, skill lint, skill frontmatter, 寫 skill, 新增 skill, 撰寫技能, skill 規範, 過 lint, skill 必備段 | asp-skill-author |

> **注意**：`asp-fact-verify`、`asp-assumption-checkpoint`、`asp-bug-classify`、`asp-change-cascade` 已於 v4.2 移除（邏輯內嵌於 `global_core.md` Profile）。相關行為由 `global_core.md` 的 Fact Verification Gate / 需求變更回溯協議 / Bug 分類章節直接覆蓋。

## 生命週期階段索引（SDLC stage index，ADR-024）

> 借 addyosmani 6 階段，提供「現在在 SDLC 哪一階段、下一步用哪個 skill」的**視圖**。**意圖路由（上方各表）仍為主**；本表純加、不取代。新增 skill 時須於此登記階段（見 `asp-skill-author`）。

| 階段 | Skills |
|------|--------|
| **Meta**（跨階段/治理） | `asp`(router) · `asp-skill-author` · `asp-level` · `asp-audit` |
| **DEFINE**（需求/領域） | `asp-context`（領域詞彙） |
| **PLAN**（架構/規劃） | `asp-plan`（ADR/SPEC） · `asp-impact`（依賴影響分析） |
| **BUILD**（實作） | `asp-autopilot`（ROADMAP 執行迴圈） |
| **VERIFY**（驗證） | `asp-dev-qa-loop` · `asp-reality-check` · `asp-gate`（G1–G6，跨管線） |
| **REVIEW**（審查） | `asp-review` · `asp-review-checklist` · `asp-external-review`（Layer 3 跨廠商） |
| **SHIP**（交付） | `asp-ship`（pre-commit） · `asp-release`（版本/CHANGELOG） |

## 執行後 — 主動提示下一步（v3.5）

完成任一子 skill 後，**主動**在回覆末尾提供「建議的下一步」，協助使用者理解 workflow 的前後關係。**不可**自動執行下一步（違反 HITL 原則），只做提示：

| 剛完成的 skill | 建議的下一步 |
|---------------|------------|
| `asp-plan`（建立 ADR/SPEC 後） | 👉 下一步：等 ADR Accepted → `/asp-gate G1,G2` → 寫測試（TDD）→ `/asp-gate G3` |
| `asp-gate G1,G2`（PASS） | 👉 下一步：撰寫測試檔案（應 FAIL）→ `/asp-gate G3` |
| `asp-gate G3`（PASS） | 👉 下一步：實作 production code → `/asp-gate G4` |
| `asp-gate G4`（PASS） | 👉 下一步：`/asp-gate G5` → `/asp-reality-check` |
| `asp-gate G5`（PASS） | 👉 下一步：`/asp-ship` → `/asp-gate G6` |
| `asp-ship`（GO） | 👉 下一步：人類審查並 `git commit`；若有 bypass 記錄可跑 `make asp-bypass-review` |
| `asp-audit`（有 blocker） | 👉 下一步：逐項修復 blocker → `make asp-refresh` |
| `asp-review`（NEEDS_WORK） | 👉 下一步：根據 finding 修復 → 重跑 `/asp-review` |
| `asp-reality-check`（NEEDS_WORK） | 👉 下一步：補足反面證據對應項目 → 重跑 `/asp-reality-check` |
| `asp-level-check`（未達 graduation） | 👉 下一步：修復 checklist 未通過項目 → 重跑 `/asp-level` |
| `asp-level-check`（通過） | 👉 下一步：`make asp-level-upgrade` 準備升級（需使用者確認） |
| `asp-context`（初始化完成） | 👉 下一步：執行 `asp-plan` 新功能時術語已備妥；或在 `asp-gate G2` 做術語審查 |
| `asp-context`（Mode C 發現衝突） | 👉 下一步：修正 ADR/SPEC 中的術語 → 重跑 `/asp-gate G2` |
| `asp-release`（PR 建立後） | 👉 下一步：人工審查 CHANGELOG → Merge PR → `git tag v{ver} && git push origin v{ver}` |
| `asp-skill-author`（寫完 skill 後） | 👉 下一步：`bash tests/test_skill_lint.sh` 自驗（R1/R2 必過）→ 登記 SKILL.md 路由 → `asp-sync` 同步 → `/asp-ship` |

### 原則

- **只建議，不執行**：除非使用者明確說「繼續」或「下一步吧」
- **預設顯示 1 個建議**，若使用者請求詳細才列出多選項
- **若當前階段卡住**（gate fail、blocker 未解），只建議修復路徑，不建議跳級

## 如何使用

每個子 skill 是自包含的——載入時不需要 `.ai_profile` 已設定，行為邏輯直接編碼在 skill 文件中。

當用戶請求匹配上表中任一觸發詞時，讀取並遵循對應的子 skill 文件（`.claude/skills/asp/asp-*.md`）。

## 角色 ↔ Skill 映射

v5 起隨 multi-agent 凍結移至 `experimental/multi-agent/README.md`（ADR-017）。

## 參考資源

- 入門指南：`docs/where-to-start.md`
- Profile 說明：`.asp/profiles/`
- Experimental（multi-agent，凍結）：`experimental/multi-agent/README.md`（角色定義 / 團隊組成 / `docs/multi-agent-architecture.md` 標 FROZEN）
- Showcase（telemetry/RAG/ai-performance）：`showcase/README.md`
- 所有指令：`make help`
