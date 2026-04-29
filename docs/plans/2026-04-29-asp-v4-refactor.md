# ASP v4.0 完整重構實作計劃

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 `feature/v4-refactor` branch 上把 ASP v3.7 重構至 v4.0：CLAUDE.md 從 309 行壓縮至 ≤100 行、從 20 個 profile 抽出 8 個新 skill、新增 MCP Server SDS、telemetry 系統、STRIDE 威脅模型、L0 Spike 等級，並產出整合 SDS，不破壞現有 13 個 skill 的向後相容性。

**Architecture:** 「憲法壓縮 + Skill 增殖」模式：CLAUDE.md 成為純分派清單、過胖 profile 的邏輯轉為可獨立調用的 skill；新增 MCP Server 層作為 telemetry 與狀態查詢的結構化工具面。六條平行 Track (A–F) 同時推進，Track F (整合 SDS) 等所有 track 完成後才執行。

**Tech Stack:** Bash (hooks, telemetry), YAML (levels, disposition matrix), Markdown (profiles, skills, ADR, SPEC), JSON (baseline, session state), Python (telemetry scripts, 沿用現有 RAG scripts 基礎)

---

## 重要常數（執行前確認）

| 項目 | 現值 | 目標值 |
|------|------|--------|
| CLAUDE.md 行數 | 309 | ≤ 100 |
| Profile 數量 | 20 | 21（+spike_mode） |
| Skill 數量 | 13 | 21（+8 新 skill） |
| Level 數量 | 5 (L1-L5) | 6 (L0-L5) |
| ADR 數量 | 1 | 4（+ADR-002,003,004） |
| SPEC 數量 | 1 | 3（+SPEC-002,003） |
| docs/plans/ | 不存在 | 存在 |
| docs/security/ | 不存在 | 存在 |
| .asp/mcp/ | 不存在 | 存在 |
| .asp/scripts/telemetry/ | 不存在 | 存在 |

---

## Phase 0 — 分支與目錄建立（Track 所有）

### Task 0.1 — 建立 feature branch 與新目錄

**Files:**
- Create: `docs/plans/` (directory)
- Create: `docs/security/` (directory)
- Create: `.asp/mcp/` (directory)
- Create: `.asp/scripts/telemetry/` (directory)

**Step 1: 建立 feature branch**

```bash
cd /home/ubuntu/AI-SOP-Protocol
git checkout -b feature/v4-refactor
```
Expected: `Switched to a new branch 'feature/v4-refactor'`

**Step 2: 建立新目錄**

```bash
mkdir -p docs/plans docs/security .asp/mcp .asp/scripts/telemetry
```

**Step 3: 驗證**

```bash
git branch --show-current
ls -d docs/plans docs/security .asp/mcp .asp/scripts/telemetry
```
Expected: `feature/v4-refactor` 和 4 個目錄均列出

**Step 4: 建立此計劃檔案的 repo 副本**

```bash
cp /home/ubuntu/.claude/plans/asp-v4-0-tender-scroll.md docs/plans/2026-04-29-asp-v4-refactor.md
```

---

## Track A — 憲法重構（Phase 1–3）

### Task A1 — 基線量測 JSON

**Files:**
- Create: `.asp-baseline-v3.7.json`

**Step 1: 用 bash 收集全部量測值**

```bash
cd /home/ubuntu/AI-SOP-Protocol
# CLAUDE.md
echo "CLAUDE.md lines: $(wc -l < CLAUDE.md)"
echo "CLAUDE.md chars: $(wc -c < CLAUDE.md)"

# Profiles
echo "=== Profile line counts ==="
wc -l .asp/profiles/*.md | sort -rn

# Skills
echo "=== Skill line counts ==="
wc -l .claude/skills/asp/*.md | sort -rn

# Hooks
wc -l .asp/hooks/*.sh .asp/hooks/*.json

# Agents / Levels / Templates
ls .asp/agents/*.yaml | wc -l
ls .asp/levels/*.yaml | wc -l
ls .asp/templates/*.md .asp/templates/*.yaml 2>/dev/null | wc -l

# Global keyword density
grep -c "必須\|禁止\|不可\|鐵則\|BLOCKER" CLAUDE.md .asp/profiles/*.md 2>/dev/null | sort -t: -k2 -rn

# ADR / SPEC count
ls docs/adr/ADR-*.md | wc -l
ls docs/specs/SPEC-*.md | wc -l
```

**Step 2: 寫入 .asp-baseline-v3.7.json**

根據 Step 1 的輸出，寫入以下格式的 JSON（數字填入實際量測值）：

```json
{
  "version": "3.7.0",
  "captured_at": "2026-04-29T00:00:00+08:00",
  "branch": "main",
  "measurement_note": "v4.0 refactor pre-flight baseline",
  "claude_md": {
    "lines": 309,
    "estimated_tokens": 4500,
    "target_v4_lines": 100,
    "target_v4_tokens": 2500
  },
  "profiles": {
    "count": 20,
    "total_lines": 6419,
    "files": {
      "task_orchestrator.md": 1379,
      "autopilot.md": 566,
      "pipeline.md": 499,
      "system_dev.md": 493,
      "multi_agent.md": 444,
      "design_dev.md": 427,
      "global_core.md": 404,
      "autonomous_dev.md": 310,
      "agent_memory.md": 291,
      "openapi.md": 245,
      "frontend_quality.md": 218,
      "vibe_coding.md": 177,
      "coding_style.md": 177,
      "reality_checker.md": 154,
      "rag_context.md": 136,
      "dev_qa_loop.md": 138,
      "escalation.md": 115,
      "committee.md": 114,
      "content_creative.md": 67,
      "guardrail.md": 65
    },
    "reduction_candidates": ["task_orchestrator.md", "system_dev.md", "pipeline.md", "global_core.md"],
    "skill_extraction_sources": {
      "asp-handoff": "task_orchestrator.md + .asp/templates/handoff/",
      "asp-team-pick": "task_orchestrator.md + .asp/agents/team_compositions.yaml",
      "asp-escalate": "escalation.md",
      "asp-dev-qa-loop": "dev_qa_loop.md",
      "asp-fact-verify": "global_core.md (Fact Verification Gate section)",
      "asp-assumption-checkpoint": "global_core.md (Assumption Checkpoint section)",
      "asp-bug-classify": "global_core.md (classify_bug_severity function)",
      "asp-change-cascade": "global_core.md (需求變更回溯協議 L1-L4)"
    }
  },
  "skills": {
    "count": 13,
    "total_lines": 2048,
    "router_file": ".claude/skills/asp/SKILL.md",
    "target_v4_count": 21
  },
  "agents": {
    "count": 11
  },
  "levels": {
    "count": 5,
    "range": "L1-L5",
    "missing": ["L0"],
    "target_v4": ["L0", "L1", "L2", "L3", "L4", "L5"]
  },
  "hooks": {
    "session_audit_lines": 267,
    "clean_allow_list_lines": 77,
    "rag_auto_index_lines": 21
  },
  "docs": {
    "adr_count": 1,
    "spec_count": 1,
    "plans_exists": false,
    "security_exists": false
  },
  "keyword_density": {
    "description": "必須/禁止/不可/鐵則/BLOCKER 出現次數",
    "CLAUDE_md": 35,
    "global_core_md": 29,
    "system_dev_md": 53,
    "task_orchestrator_md": 17,
    "autonomous_dev_md": 15
  },
  "targets_v4": {
    "claude_md_max_lines": 100,
    "claude_md_max_tokens": 2500,
    "new_skills": ["asp-handoff", "asp-team-pick", "asp-escalate", "asp-dev-qa-loop", "asp-fact-verify", "asp-assumption-checkpoint", "asp-bug-classify", "asp-change-cascade"],
    "new_levels": ["L0"],
    "new_adrs": ["ADR-002-asp-v4-security", "ADR-003-asp-mcp-server", "ADR-004-asp-telemetry"],
    "new_specs": ["SPEC-002-asp-mcp-server", "SPEC-003-asp-v4-architecture-refactor"],
    "new_directories": ["docs/plans", "docs/security", ".asp/mcp", ".asp/scripts/telemetry"]
  }
}
```

**Step 3: 驗證**

```bash
jq '.version' .asp-baseline-v3.7.json
# Expected: "3.7.0"
jq '.targets_v4.new_skills | length' .asp-baseline-v3.7.json
# Expected: 8
```

---

### Task A2 — 基線敘述 Markdown

**Files:**
- Create: `.asp-baseline-v3.7.md`

**Step 1: 寫入基線敘述文件**

內容必須包含：
1. 執行摘要（3-5 條 observations）
2. Profile 臃腫分析（按行數排序，>300 行標記為「重構候選」）
3. Skill 覆蓋缺口（現有 13 個 skill 未覆蓋哪些 profile 邏輯）
4. v3.7 → v4.0 delta 摘要表格

```markdown
# ASP v3.7 → v4.0 基線量測報告

> 量測時間：2026-04-29 | Branch: main | ASP 版本：3.7.0

## 執行摘要

1. **CLAUDE.md 過胖**：309 行，估算 4500 tokens。L5 全套載入（global_core + 所有 optional）估算累計超過 30,000 tokens，影響每次 session 的有效 context 窗口。
2. **task_orchestrator.md 是最大瓶頸**：1,379 行（佔總 profile token 約 21%）。其中 handoff 模板、team-pick 邏輯、escalation 路由均為 capability（被呼叫才需要），不應每次 session 全量載入。
3. **8 條 profile 邏輯已具備 skill 化條件**：這些邏輯有自然語言觸發詞、無跨 session 狀態需求，符合 CONVERT_TO_SKILL 標準。
4. **L0 缺位**：ASP 從 L1 開始，沒有「探索性原型」等級。PoC、red team demo、CYBERSEC 講座 demo 等場景需要比 L1 更寬鬆的設定。
5. **無 telemetry**：目前無法量測「哪些 rule 真的抓到問題」「哪些 gate 從未失敗」，無法做 evidence-based 的 v4.0 效果驗證。

## Profile 臃腫分析（重構候選）

| Profile | 行數 | 狀態 | v4.0 建議動作 |
|---------|------|------|--------------|
| task_orchestrator.md | 1,379 | 🔴 重構候選 | 抽出 asp-handoff, asp-team-pick；核心路由留 profile |
| autopilot.md | 566 | 🟡 觀察 | 留 profile（stateful，跨 session 狀態） |
| pipeline.md | 499 | 🟡 觀察 | 留 profile（G1-G6 是 cross-cutting rule） |
| system_dev.md | 493 | 🔴 重構候選 | 抽出 asp-bug-classify, asp-change-cascade；TDD 規則留 profile |
| multi_agent.md | 444 | 🟡 觀察 | 留 profile（並行協調是 cross-cutting rule） |
| global_core.md | 404 | 🔴 重構候選 | 抽出 asp-fact-verify, asp-assumption-checkpoint；鐵則留 profile |
| autonomous_dev.md | 310 | 🟢 OK | 留 profile（auto_fix_loop 必須 implicit 套用） |
| escalation.md | 115 | 🔴 重構候選 | 整體轉為 asp-escalate skill |
| dev_qa_loop.md | 138 | 🔴 重構候選 | 整體轉為 asp-dev-qa-loop skill |

## Skill 覆蓋缺口

| 現有 Profile 邏輯 | 現有對應 Skill | 缺口 |
|------------------|--------------|------|
| Handoff protocol (task_orchestrator.md) | ❌ 無 | 需新增 asp-handoff |
| Team recommendation (task_orchestrator.md) | ❌ 無 | 需新增 asp-team-pick |
| P0-P3 escalation (escalation.md) | ❌ 無 | 需新增 asp-escalate |
| Dev↔QA loop (dev_qa_loop.md) | ❌ 無 | 需新增 asp-dev-qa-loop |
| Fact Verification Gate (global_core.md) | ❌ 無 | 需新增 asp-fact-verify |
| Assumption Checkpoint (global_core.md) | ❌ 無 | 需新增 asp-assumption-checkpoint |
| Bug severity classify (global_core.md) | ❌ 無 | 需新增 asp-bug-classify |
| Change cascade L1-L4 (global_core.md) | ❌ 無 | 需新增 asp-change-cascade |

## v3.7 → v4.0 Delta 摘要

| 元件 | v3.7 | v4.0 目標 | 變化 |
|------|------|----------|------|
| CLAUDE.md | 309 行 | ≤ 100 行 | -67% |
| Skills | 13 個 | 21 個 | +8 |
| Levels | L1-L5 (5 個) | L0-L5 (6 個) | +1 |
| ADR 數量 | 1 | 4 | +3 |
| SPEC 數量 | 1 | 3 | +2 |
| Telemetry | 無 | JSONL append-only | 新增 |
| MCP Server | 無 | ADR + SPEC (設計階段) | 新增 |
| Security | 無 | STRIDE 威脅模型 | 新增 |
```

**Step 2: 驗證**

```bash
wc -l .asp-baseline-v3.7.md
# Expected: ≥ 40 行
grep "v3.7\|v4.0\|Delta" .asp-baseline-v3.7.md | wc -l
# Expected: ≥ 3
```

---

### Task A3 — Disposition Matrix YAML

**Files:**
- Create: `.asp-disposition-matrix.yaml`

**Step 1: 寫入 disposition matrix**

```yaml
version: "4.0"
created_at: "2026-04-29"
description: "ASP v3.7 元件分類矩陣——決定每個元件在 v4.0 的去向"

# Disposition 定義：
# KEEP_AS_RULE: 留在 profile 或 hook（隱式觸發、cross-cutting constraint）
# CONVERT_TO_SKILL: 轉為 Claude Code skill（顯式觸發、capability）
# COMPRESS: 留在 CLAUDE.md 但大幅縮短
# REFERENCE: 從 CLAUDE.md 移除，改為指向 profile/docs 的單行連結
# ELIMINATE: 從 CLAUDE.md 完全移除（已有其他來源提供，或不再需要）
# KEEP_IN_PROFILE: 留在 .asp/profiles/ 不動

entries:

  # ── CLAUDE.md sections ──
  - id: claude_md.startup_procedure
    current: "CLAUDE.md lines 18-28"
    lines: 11
    disposition: COMPRESS
    target: "CLAUDE.md (≤ 6 行精簡版)"
    rationale: "啟動邏輯是 cross-cutting rule，必須在 CLAUDE.md 可見；但 step 4a/4b 細節移到 profiles"

  - id: claude_md.validate_profile_config_function
    current: "CLAUDE.md lines 29-60"
    lines: 32
    disposition: REFERENCE
    target: "一行：Profile 驗證邏輯見 .asp/profiles/global_core.md"
    rationale: "30 行 pseudocode 在 CLAUDE.md 佔比過高；session-audit.sh 已在 hook 層實作，不需要在 constitution 重複"

  - id: claude_md.ai_profile_schema
    current: "CLAUDE.md lines 62-75"
    lines: 14
    disposition: COMPRESS
    target: "CLAUDE.md (≤ 8 行：只保留 type/level/mode/workflow 四個最關鍵欄位)"
    rationale: "完整 schema 留在 .asp/templates/example-profile-*.yaml；CLAUDE.md 只給快速參考"

  - id: claude_md.profile_mapping_table
    current: "CLAUDE.md lines 77-105"
    lines: 29
    disposition: COMPRESS
    target: "CLAUDE.md (≤ 10 行：type/mode 映射；optional flags 移到 level-N.yaml)"
    rationale: "核心映射（type → profiles）必須可見；optional flag 細節已在 level files"

  - id: claude_md.maturity_levels_table
    current: "CLAUDE.md lines 107-138"
    lines: 32
    disposition: COMPRESS
    target: "CLAUDE.md (≤ 8 行：L0-L5 一行一個 level，link to .asp/levels/)"
    rationale: "詳細描述留在 .asp/levels/level-N.yaml；CLAUDE.md 只需一行 per level"

  - id: claude_md.maturity_level_management
    current: "CLAUDE.md lines 140-155"
    lines: 16
    disposition: REFERENCE
    target: "一行：等級管理指令見 make asp-level-* 或 .asp/levels/README.md"
    rationale: "操作指令已在 Makefile；不需要在 CLAUDE.md 重複"

  - id: claude_md.maturity_inference_rules
    current: "CLAUDE.md lines 156-172"
    lines: 17
    disposition: ELIMINATE
    target: "刪除"
    rationale: "Legacy 相容規則在 level: 欄位設定後不再需要；session-audit.sh 已有 fallback 邏輯"

  - id: claude_md.iron_rules
    current: "CLAUDE.md lines 174-186"
    lines: 13
    disposition: KEEP
    target: "CLAUDE.md (保留，但每條精簡到 1-2 行)"
    rationale: "4 條鐵則是不可覆蓋的 cross-cutting constraints，必須在 constitution 可見"

  - id: claude_md.enforcement_architecture_table
    current: "CLAUDE.md lines 188-200"
    lines: 13
    disposition: COMPRESS
    target: "CLAUDE.md (4 行 table，移除 Bypass 警告段落→REFERENCE)"
    rationale: "4 層架構表必須可見；bypass 警告是 capability，移到 asp-ship skill"

  - id: claude_md.mandatory_skill_invocations
    current: "CLAUDE.md lines 202-225"
    lines: 24
    disposition: COMPRESS
    target: "CLAUDE.md (≤ 8 行：只保留 G1/G4/G6 三個最關鍵觸發點)"
    rationale: "完整觸發表仍然需要，但可以壓縮；詳細版移到 .asp/profiles/global_core.md"

  - id: claude_md.bypass_warning_format
    current: "CLAUDE.md lines 227-237"
    lines: 11
    disposition: REFERENCE
    target: "一行：Bypass 警告格式見 asp-ship skill Step 10"
    rationale: "已在 asp-ship.md 中有完整 bypass 記錄邏輯，CLAUDE.md 重複"

  - id: claude_md.default_behaviors_table
    current: "CLAUDE.md lines 239-261"
    lines: 23
    disposition: REFERENCE
    target: "移到 .asp/profiles/global_core.md 的「預設行為」section"
    rationale: "預設行為是 rule 但已有 profile 存放；CLAUDE.md 只需一行指引"

  - id: claude_md.standard_workflow_diagram
    current: "CLAUDE.md lines 263-269"
    lines: 7
    disposition: KEEP
    target: "CLAUDE.md（保留 ASCII diagram + 1 行說明）"
    rationale: "標準工作流程圖是 onboarding 的核心視覺錨點，必須在 CLAUDE.md 可見"

  - id: claude_md.makefile_full_table
    current: "CLAUDE.md lines 271-335"
    lines: 65
    disposition: ELIMINATE
    target: "完全移除，改為一行：執行 make help 取得完整指令"
    rationale: "65 行 Makefile 速查表是最大的 token 浪費；make help 已可提供同等資訊"

  - id: claude_md.technical_execution_hooks
    current: "CLAUDE.md lines 337-353"
    lines: 17
    disposition: COMPRESS
    target: "CLAUDE.md (≤ 4 行：allow/deny 策略 + hook 指向)"
    rationale: "技術執行細節留在 .asp/hooks/README.md；CLAUDE.md 只需方向性說明"

  # ── Profiles ──
  - id: profile.global_core.communication_norms
    current: ".asp/profiles/global_core.md"
    disposition: KEEP_IN_PROFILE
    rationale: "溝通規範是 cross-cutting constraint，必須 implicit 套用"

  - id: profile.global_core.working_dir_discipline
    current: ".asp/profiles/global_core.md"
    disposition: KEEP_IN_PROFILE
    rationale: "跨 session stateless rule"

  - id: profile.global_core.fact_verification_gate
    current: ".asp/profiles/global_core.md lines 39-100"
    lines: 62
    disposition: CONVERT_TO_SKILL
    target_skill: "asp-fact-verify"
    rationale: "有明確觸發詞（涉及外部事實/API/版本）、一次性執行、可獨立運作"

  - id: profile.global_core.assumption_checkpoint
    current: ".asp/profiles/global_core.md"
    disposition: CONVERT_TO_SKILL
    target_skill: "asp-assumption-checkpoint"
    rationale: "非 trivial 任務前輸出表格——有觸發詞、capability 而非 constraint"

  - id: profile.global_core.classify_bug_severity
    current: ".asp/profiles/global_core.md"
    disposition: CONVERT_TO_SKILL
    target_skill: "asp-bug-classify"
    rationale: "bug 修復前的分類動作有觸發詞（bug fix, 修 bug）"

  - id: profile.global_core.change_cascade_protocol
    current: ".asp/profiles/global_core.md"
    disposition: CONVERT_TO_SKILL
    target_skill: "asp-change-cascade"
    rationale: "需求變更時有明確觸發詞（需求變更、change request）"

  - id: profile.task_orchestrator.on_task_received
    current: ".asp/profiles/task_orchestrator.md"
    disposition: KEEP_IN_PROFILE
    rationale: "任務路由是 cross-cutting，沒有觸發詞——AI 必須自動套用"

  - id: profile.task_orchestrator.project_health_audit
    current: ".asp/profiles/task_orchestrator.md"
    disposition: KEEP_IN_PROFILE
    rationale: "首次介入自動觸發——implicit rule"

  - id: profile.task_orchestrator.handoff_protocol
    current: ".asp/profiles/task_orchestrator.md + .asp/templates/handoff/"
    disposition: CONVERT_TO_SKILL
    target_skill: "asp-handoff"
    rationale: "交接是顯式 capability——使用者說「交接給下一個 agent」才觸發"

  - id: profile.task_orchestrator.team_recommendation
    current: ".asp/profiles/task_orchestrator.md + .asp/agents/team_compositions.yaml"
    disposition: CONVERT_TO_SKILL
    target_skill: "asp-team-pick"
    rationale: "團隊推薦是顯式 capability——使用者說「推薦 team」才觸發"

  - id: profile.escalation
    current: ".asp/profiles/escalation.md"
    lines: 115
    disposition: CONVERT_TO_SKILL
    target_skill: "asp-escalate"
    rationale: "整個 profile 是 capability——有觸發詞（escalate, P0, 緊急）"

  - id: profile.dev_qa_loop
    current: ".asp/profiles/dev_qa_loop.md"
    lines: 138
    disposition: CONVERT_TO_SKILL
    target_skill: "asp-dev-qa-loop"
    rationale: "Dev↔QA 迴路是顯式工作流——使用者啟動才執行，非 implicit"

  - id: profile.pipeline
    current: ".asp/profiles/pipeline.md"
    disposition: KEEP_IN_PROFILE
    rationale: "G1-G6 是 cross-cutting pipeline constraint，不能變成只有觸發詞才執行"

  - id: profile.system_dev
    current: ".asp/profiles/system_dev.md"
    disposition: KEEP_IN_PROFILE
    rationale: "TDD 規則、Pre-Implementation Gate 是 cross-cutting constraint；部分邏輯已抽出為 skills"

dispositions_summary:
  KEEP: 4
  COMPRESS: 6
  REFERENCE: 4
  ELIMINATE: 2
  CONVERT_TO_SKILL: 8
  KEEP_IN_PROFILE: 8
```

**Step 2: 驗證**

```bash
# 確認 YAML 可以解析
python3 -c "import yaml; d=yaml.safe_load(open('.asp-disposition-matrix.yaml')); print(d['dispositions_summary'])"
# Expected: {'KEEP': 4, 'COMPRESS': 6, 'REFERENCE': 4, 'ELIMINATE': 2, 'CONVERT_TO_SKILL': 8, 'KEEP_IN_PROFILE': 8}
```

---

### Task A4 — Disposition Matrix 紅隊質疑 Markdown

**Files:**
- Create: `.asp-disposition-matrix.md`

**Step 1: 寫入紅隊文件**

格式（必須包含以下 section）：
1. Summary 表格（所有 disposition）
2. 紅隊質疑（至少 10 條，每條：挑戰 + 回應 + 最終決策 ACCEPT/MODIFY）
3. 修正後的 disposition（標記哪些因紅隊改變）

重點紅隊問題（必須回答）：
- "把 Makefile 表從 CLAUDE.md 移除，第一次使用 ASP 的人還能找到指令嗎？" → 答案：make help 是標準入口，但要在 CLAUDE.md 補一行說明
- "fact_verification_gate 轉成 skill 後，使用者忘記觸發怎麼辦？" → 答案：gate G1 仍然在 pipeline.md 要求它，不會被跳過
- "assume checkpoint 轉成 skill 後，沒有 profile 的使用者（L0）能用嗎？" → 答案：skill 獨立運作，L0 可以直接調用
- "把 escalation.md 全轉成 skill，但 implicit 的 P0 觸發怎麼辦？" → 答案：P0 escalation 的 implicit 部分仍留在 autonomous_dev.md

**Step 2: 驗證**

```bash
grep "紅隊\|Red Team\|ACCEPT\|MODIFY" .asp-disposition-matrix.md | wc -l
# Expected: ≥ 8
```

---

### Task A5 — CLAUDE.md 重寫

**Files:**
- Modify: `CLAUDE.md` (309 行 → ≤ 100 行)

**IMPORTANT:** 先備份再改

**Step 1: 備份原始 CLAUDE.md**

```bash
cp CLAUDE.md CLAUDE.md.v3.7-backup
```

**Step 2: 寫入新 CLAUDE.md**

按照以下結構，100 行上限：

```
行 1-5:    標題 + 讀取順序（3 行）
行 6-16:   啟動程序（6 個 step 的精簡版，移除 pseudocode block）
行 17-27:  Profile 映射表（type/mode → profiles，精簡版）
行 28-36:  成熟度等級（L0-L5，每行一個，含 .asp/levels/ link）
行 37-47:  鐵則（4 條，每條 2 行：rule name + 1 行說明）
行 48-57:  強制 Skill 調用表（簡化版：G1/G4/G6 三個關鍵觸發點）
行 58-63:  強制力架構（4 行 table）
行 64-68:  標準工作流（ASCII diagram 壓縮版）
行 69-73:  技術執行層（3 行：allow-all + deny 黑名單 link + hook link）
行 74-79:  Bypass 警告（2 行：格式範例 link）
行 80-85:  預設行為（5 行：最重要的 5 條，link to global_core.md）
行 86-100: 快速指令（make help 一行 + 最重要的 6 個指令 + 索引）
```

新 CLAUDE.md 必須保留的鐵則文字（一字不改）：
- `ADR 未定案禁止實作`
- `外部事實驗證防護`
- `敏感資訊保護`
- `破壞性操作防護`

**Step 3: 驗證**

```bash
wc -l CLAUDE.md
# Expected: ≤ 100

grep -E "ADR 未定案|外部事實|敏感資訊|破壞性操作" CLAUDE.md | wc -l
# Expected: 4 (all iron rules present)

grep "make help" CLAUDE.md
# Expected: 行存在

grep "L0\|Spike" CLAUDE.md
# Expected: 行存在（L0 level entry）
```

**Step 4: Commit Task A**

```bash
git add CLAUDE.md .asp-baseline-v3.7.json .asp-baseline-v3.7.md .asp-disposition-matrix.yaml .asp-disposition-matrix.md CLAUDE.md.v3.7-backup
git commit -m "feat(v4/track-a): constitution compression — CLAUDE.md 309→≤100 lines + baseline + disposition matrix"
```

---

## Track B — Skill 抽取（Phase 1，與 Track A 平行）

*所有新 skill 必須符合「無需載入任何 .asp/profiles/ 也能獨立運作」的條件。*

### Task B1 — asp-handoff skill

**Files:**
- Create: `.claude/skills/asp/asp-handoff.md`

**Step 1: 閱讀來源材料**

```bash
cat .asp/templates/handoff/TASK_COMPLETE.yaml
cat .asp/templates/handoff/SESSION_BRIDGE.yaml
cat .asp/templates/handoff/ESCALATION.yaml
cat .asp/templates/handoff/REASSIGNMENT.yaml
cat .asp/templates/handoff/PHASE_GATE.yaml
```

**Step 2: 寫入 asp-handoff.md**

必須包含：
- YAML frontmatter：name, description（含觸發詞：handoff, 交接, agent handoff, 交給, task complete, session bridge, escalation, reassignment, phase gate）
- 5 種交接類型的選擇器（觸發條件描述）
- 每種類型的欄位填寫指引
- 輸出格式：YAML 存至 `.asp/handoffs/HANDOFF-{YYYYMMDD}-{type}.yaml`
- 「不要觸發」section（避免 false positive）
- 無 ASP profile 也能運作（所有邏輯直接嵌入 skill）

```bash
cat > .claude/skills/asp/asp-handoff.md << 'SKILL'
---
name: asp-handoff
description: |
  Agent 任務交接 / 工作交接。生成結構化 handoff YAML 並存檔。
  Triggers: handoff, agent handoff, 交接, 交給, 任務移交, task complete,
  session bridge, session handoff, escalation handoff, reassignment,
  phase gate, 跨 session, 換人接, 離開, 上下游交接, pass the baton
---
# asp-handoff — Agent 交接工作流

## 何時觸發
- 你需要把當前任務移交給另一個 agent 或下次 session
- Agent 完成自己的工作範圍，需要通知下游
- P0/P1 升級需要生成 escalation handoff
- Multi-agent 跨 track 的 phase gate 確認

## 不要觸發
- 一般程式碼 review（那是 asp-review）
- 任務開始，不是任務結束/移交

## 步驟 1：選擇交接類型

| 類型 | 觸發條件 |
|------|---------|
| TASK_COMPLETE | Worker agent 完成一個 task，通知 Orchestrator |
| SESSION_BRIDGE | 當前 session context 快滿，需要下次 session 接力 |
| ESCALATION | P0/P1 問題超出處理能力，需要人類介入 |
| REASSIGNMENT | 任務需要轉給不同 agent 角色 |
| PHASE_GATE | 一個 development phase 完成，進入下一 phase |

## 步驟 2：填寫交接 YAML

### TASK_COMPLETE 格式
```yaml
type: TASK_COMPLETE
task_id: "<task_id>"
completed_by: "<agent_role>"
timestamp: "<ISO8601>"
output_artifacts:
  - path: "<file_path>"
    description: "<what it is>"
done_when_verified:
  - "<binary check 1>"
next_task: "<next_task_id or null>"
notes: "<any context for the next agent>"
```

### SESSION_BRIDGE 格式
```yaml
type: SESSION_BRIDGE
session_id: "<current_session_id>"
timestamp: "<ISO8601>"
completed_tasks:
  - "<task description>"
in_progress_task:
  description: "<what was being done>"
  last_action: "<what was last done>"
  next_action: "<what to do first in new session>"
context_snapshot:
  key_decisions: []
  blockers: []
  working_files: []
resume_instructions: "<one paragraph for next session>"
```

### ESCALATION 格式
```yaml
type: ESCALATION
severity: P0 | P1
task_id: "<task_id>"
triggered_by: "<agent_role>"
timestamp: "<ISO8601>"
reason: "<why escalating>"
fix_history:
  - attempt: 1
    action: "<what was tried>"
    result: "<what happened>"
human_action_needed: "<specific ask>"
context_snapshot: "<relevant file paths and current state>"
```

### REASSIGNMENT 格式
```yaml
type: REASSIGNMENT
task_id: "<task_id>"
from_agent: "<current_agent_role>"
to_agent: "<target_agent_role>"
reason: "<why reassigning>"
handoff_context: "<what the new agent needs to know>"
artifacts_to_review: []
```

### PHASE_GATE 格式
```yaml
type: PHASE_GATE
phase_from: "<G1|G2|G3|G4|G5|G6>"
phase_to: "<G2|G3|G4|G5|G6|DONE>"
gate_passed: true | false
evidence:
  - "<binary check result>"
next_phase_instructions: "<what to do next>"
```

## 步驟 3：存檔

```bash
mkdir -p .asp/handoffs
# 存為 .asp/handoffs/HANDOFF-{YYYYMMDD}-{TYPE}.yaml
```

## 下一步
- TASK_COMPLETE → Orchestrator 處理後分派下個任務
- SESSION_BRIDGE → 在新 session 開頭讀取此 YAML 恢復進度
- ESCALATION → 立即通知人類，停止自動進行
SKILL
```

**Step 3: 驗證**

```bash
grep "TASK_COMPLETE\|SESSION_BRIDGE\|ESCALATION\|REASSIGNMENT\|PHASE_GATE" .claude/skills/asp/asp-handoff.md | wc -l
# Expected: ≥ 5

head -5 .claude/skills/asp/asp-handoff.md
# Expected: --- (YAML frontmatter start)
```

---

### Task B2 — asp-team-pick skill

**Files:**
- Create: `.claude/skills/asp/asp-team-pick.md`

**Step 1: 閱讀 team_compositions.yaml**

```bash
cat .asp/agents/team_compositions.yaml
```

**Step 2: 寫入 asp-team-pick.md**

Skill 必須把 team_compositions.yaml 的邏輯直接嵌入（不依賴 profile）。格式：
- 觸發詞：team pick, 組團隊, recommend team, 哪些 agent, 推薦 agent, 誰來做, who should work on
- 輸入：任務類型 + 複雜度
- 輸出：agent 清單 + 每個 agent 的職責
- 包含完整的 9 個 scenario（從 team_compositions.yaml 抽出）

**Step 3: 驗證**

```bash
grep "NEW_FEATURE\|BUGFIX\|MODIFICATION\|REMOVAL\|GENERAL" .claude/skills/asp/asp-team-pick.md | wc -l
# Expected: ≥ 5
```

---

### Task B3 — asp-escalate skill

**Files:**
- Create: `.claude/skills/asp/asp-escalate.md`

**Step 1: 閱讀 escalation.md**

```bash
cat .asp/profiles/escalation.md
```

**Step 2: 寫入 asp-escalate.md**

包含：
- 觸發詞：escalate, escalation, P0, P1, 緊急, 卡住了, stuck, blocked, critical issue
- P0-P3 決策樹（從 escalation.md 的 `escalate()` function 抽出）
- 各嚴重度對應的回應動作（P0: 暫停全部 + 通知人類，P1: 暫停當前 track + Orchestrator，P2: 重新分派，P3: tech debt backlog）
- 生成 ESCALATION handoff YAML 的步驟（引用 asp-handoff 的 ESCALATION 格式）

**Step 3: 驗證**

```bash
grep "P0\|P1\|P2\|P3\|severity" .claude/skills/asp/asp-escalate.md | wc -l
# Expected: ≥ 8
```

---

### Task B4 — asp-dev-qa-loop skill

**Files:**
- Create: `.claude/skills/asp/asp-dev-qa-loop.md`

**Step 1: 閱讀 dev_qa_loop.md**

```bash
cat .asp/profiles/dev_qa_loop.md
```

**Step 2: 寫入 asp-dev-qa-loop.md**

包含：
- 觸發詞：dev qa loop, dev-qa, qa loop, 開發品質迴路, impl 寫完讓 qa 看, 跑 dev qa
- 逐模組 Dev→QA→Fix 的步驟
- checksum smuggling detection 步驟
- QA_FAIL 3× 觸發 asp-escalate P2
- 整合驗證（所有模組 PASS 後）

**Step 3: 驗證**

```bash
grep "checksum\|smuggl\|QA_FAIL\|模組" .claude/skills/asp/asp-dev-qa-loop.md | wc -l
# Expected: ≥ 4
```

---

### Task B5 — asp-fact-verify skill

**Files:**
- Create: `.claude/skills/asp/asp-fact-verify.md`

**Step 1: 閱讀 global_core.md 的 Fact Verification Gate section**

```bash
sed -n '/外部事實驗證閘/,/---/p' .asp/profiles/global_core.md | head -80
```

**Step 2: 寫入 asp-fact-verify.md**

包含：
- 觸發詞：fact verify, 外部事實, API 版本, 查證, verify fact, check version, 確認 API
- Fact Verification Gate 的完整流程（從 global_core.md 抽出）
- `.asp-fact-check.md` 的寫入格式（table 格式）
- 5 元素驗證清單（人事時地物）
- 輸出：PASS / FAIL / UNVERIFIED verdict

**Step 3: 驗證**

```bash
grep "asp-fact-check\|UNVERIFIED\|WebSearch\|WebFetch" .claude/skills/asp/asp-fact-verify.md | wc -l
# Expected: ≥ 3
```

---

### Task B6 — asp-assumption-checkpoint skill

**Files:**
- Create: `.claude/skills/asp/asp-assumption-checkpoint.md`

**Step 1: 閱讀 global_core.md 的 Assumption Checkpoint 部分**

```bash
grep -n "Assumption\|假設" .asp/profiles/global_core.md | head -20
```

**Step 2: 寫入 asp-assumption-checkpoint.md**

包含：
- 觸發詞：assumption, checkpoint, 假設確認, 開始前先確認, pre-task check, 有沒有假設
- 輸出表格格式：假設 | 依據 | 若錯誤的風險 | 驗證方式
- 觸發條件（2+ 模組、ADR/SPEC 必要、架構影響）
- 等待使用者確認後才繼續

**Step 3: 驗證**

```bash
grep "假設\|Assumption\|依據\|風險\|驗證方式" .claude/skills/asp/asp-assumption-checkpoint.md | wc -l
# Expected: ≥ 4
```

---

### Task B7 — asp-bug-classify skill

**Files:**
- Create: `.claude/skills/asp/asp-bug-classify.md`

**Step 1: 閱讀 global_core.md 的 bug classification 部分**

```bash
grep -n "bug\|trivial\|non-trivial\|classify" .asp/profiles/global_core.md | head -20
```

**Step 2: 寫入 asp-bug-classify.md**

包含：
- 觸發詞：bug classify, bug severity, 分類 bug, 這是 trivial 嗎, 這個 bug 要 SPEC 嗎
- trivial vs non-trivial 的判斷標準（affected_files, changed_lines 等量化標準）
- bug 類型標籤：[bug:logic] [bug:boundary] [bug:concurrency] [bug:integration] [bug:config] [bug:security]
- 輸出：severity + 建議工作流（直接修 vs SPEC-first）

**Step 3: 驗證**

```bash
grep "trivial\|non-trivial\|\[bug:" .claude/skills/asp/asp-bug-classify.md | wc -l
# Expected: ≥ 4
```

---

### Task B8 — asp-change-cascade skill

**Files:**
- Create: `.claude/skills/asp/asp-change-cascade.md`

**Step 1: 閱讀 global_core.md 的需求變更回溯協議**

```bash
grep -n "需求變更\|change.*cascade\|L1\|L2\|L3\|L4" .asp/profiles/global_core.md | head -30
```

**Step 2: 寫入 asp-change-cascade.md**

包含：
- 觸發詞：change cascade, requirement change, 需求變更, scope change, 需求改了, change request
- 變更等級判定（L1 細節 / L2 SPEC override / L3 ADR override / L4 方向 pivot）
- 每個等級對應的 cascade 動作（L1: 更新 SPEC, L2: 新建 SPEC, L3: 新建 ADR, L4: 全面重新規劃）
- 影響範圍評估

**Step 3: 驗證**

```bash
grep "L1\|L2\|L3\|L4\|cascade" .claude/skills/asp/asp-change-cascade.md | wc -l
# Expected: ≥ 6
```

---

### Task B9 — 更新 SKILL.md Router

**Files:**
- Modify: `.claude/skills/asp/SKILL.md`

**Step 1: 閱讀現有 SKILL.md**

```bash
cat .claude/skills/asp/SKILL.md
```

**Step 2: 在 SKILL.md 加入 v4.0 新 skill section**

在「## 子 Skill 路由表」的現有區塊後，加入新區塊：

```markdown
### v4.0 新增 Skill（抽自 Profile）

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| 任務交接 / Agent handoff | handoff, 交接, 任務移交, session bridge | asp-handoff |
| 推薦執行團隊 | team pick, 組團隊, 推薦 agent, who should work | asp-team-pick |
| 升級處理 / 緊急問題 | escalate, P0, P1, 緊急, 卡住, critical | asp-escalate |
| Dev↔QA 品質迴路 | dev qa loop, qa loop, 開發品質迴路 | asp-dev-qa-loop |
| 外部事實查證 | fact verify, 外部事實, 查證 API, 確認版本 | asp-fact-verify |
| 任務假設確認 | assumption, checkpoint, 假設確認, 開始前確認 | asp-assumption-checkpoint |
| Bug 嚴重度分類 | bug classify, bug severity, 這是 trivial 嗎 | asp-bug-classify |
| 需求變更回溯 | change cascade, 需求變更, scope change | asp-change-cascade |
```

**Step 3: 驗證**

```bash
grep -c "asp-handoff\|asp-team-pick\|asp-escalate\|asp-dev-qa-loop\|asp-fact-verify\|asp-assumption-checkpoint\|asp-bug-classify\|asp-change-cascade" .claude/skills/asp/SKILL.md
# Expected: 8
```

**Step 4: Commit Track B**

```bash
git add .claude/skills/asp/asp-handoff.md .claude/skills/asp/asp-team-pick.md \
    .claude/skills/asp/asp-escalate.md .claude/skills/asp/asp-dev-qa-loop.md \
    .claude/skills/asp/asp-fact-verify.md .claude/skills/asp/asp-assumption-checkpoint.md \
    .claude/skills/asp/asp-bug-classify.md .claude/skills/asp/asp-change-cascade.md \
    .claude/skills/asp/SKILL.md
git commit -m "feat(v4/track-b): +8 new skills extracted from profiles (handoff, team-pick, escalate, dev-qa-loop, fact-verify, assumption-checkpoint, bug-classify, change-cascade)"
```

---

## Track C — 安全威脅模型（Phase 1，與 Track A/B 平行）

*CYBERSEC 2026 演講相關，最高優先。*

### Task C1 — STRIDE 威脅模型文件

**Files:**
- Create: `docs/security/threat-model-v4.0.md`

**Step 1: 寫入威脅模型**

結構（必須包含以下 section）：

1. **系統描述與信任邊界**
   - 信任邊界：Human operator ↔ Claude Code ↔ ASP hooks ↔ file system ↔ git
   - 資產：`.claude/settings.json`（控制 deny list）、`.asp/hooks/`（SessionStart 執行）、`.asp-bypass-log.json`（審計紀錄）、`.asp-session-briefing.json`（動態 deny 注入點）

2. **STRIDE 威脅分析表**（至少 12 條）

| 類別 | 威脅描述 | 受影響元件 | 嚴重度 | 現有防護 | 缺口 |
|------|---------|-----------|------|---------|------|
| Tampering | 攻擊者修改 `.asp/hooks/denied-commands.json` 移除 git-push deny | denied-commands.json | CRITICAL | 在 git，修改可見 | 無 hook 載入時的完整性驗證 |
| Tampering | 攻擊者修改 `.asp-session-briefing.json` 的動態 deny | session-audit.sh output | HIGH | 每次 session 重新產生 | 攻擊視窗存在於兩次 session 之間 |
| Repudiation | `.asp-bypass-log.json` 被靜默編輯 | bypass audit trail | MED | 無 | 可變更 JSON，無 append-only 機制 |
| Spoofing | 惡意 `.ai_profile` 把 level 設為 0 以繞過所有 gates | ai_profile parsing | MED | Bash grep，無 schema 驗證 | 無 YAML schema validation |
| Elevation of Privilege | 使用者在非緊急情況呼叫 `make asp-unlock-commit` | Dynamic deny removal | HIGH | 人類 HITL | 無 unlock 操作的 audit 記錄 |
| Prompt Injection | Web_fetch / rag_search 回傳含 imperative-mood 指令 | agent tool outputs | HIGH | 無 | ASP 沒有 tool output sanitization |
| Prompt Injection | `.asp-agent-memory.yaml` 被投毒，AI 信任 hint 執行 | agent memory hints | HIGH | 無 | 無 memory entry 可信度標記 |
| Supply Chain | `pip install / npm install` 過程無驗證 | 依賴安裝 | MED | 無 | 無 hash 驗證 |
| Confused Deputy | escalate(P0) 通知內容由 AI 撰寫，可被注入 | human notification | MED | 無 | 通知內容未做 sanity check |
| LOLBAS | `make <any target>` 可執行任意 shell | Makefile | MED | deny list 保護特定指令 | Makefile targets 未在 deny list |
| Sandbox Escape | autonomous_dev 的「精確邊界」由 AI 解讀，可 rationalize | SPEC scope | LOW-MED | SPEC 有 allow/forbid 清單 | AI 仍可 rationalize 邊界 |
| Information Disclosure | `.asp-session-briefing.json` 可能在 MCP context 中洩漏 | session briefing | LOW | 未 commit 到 git | MCP server 若存在可能暴露 |

3. **8 步攻擊鏈（攻擊者的視角）**
   - Step 1: Reconnaissance — GitHub public repo 已暴露 `.asp/profiles/` 的完整規則集
   - Step 2: Profile 逆向 — 攻擊者知道哪些 gate 存在，規劃繞過順序
   - Step 3: `.ai_profile` 投毒 — 提交一個把 `level: 0` 設定的 `.ai_profile`（L0 跳過所有 gates）
   - Step 4: Session briefing 竄改 — 在 PR review 期間修改 `.asp-session-briefing.json` 移除 BLOCKER
   - Step 5: Memory poisoning — 在 `.asp-agent-memory.yaml` 注入假 hint，下次 agent 執行時被信任
   - Step 6: Bypass log 清理 — 靜默刪除 `.asp-bypass-log.json` 中的記錄，繞過 bypass-3x-blocker
   - Step 7: 觸發 unlock — 引導使用者執行 `make asp-unlock-commit`（沒有 unlock 原因記錄）
   - Step 8: 直接 push — denied-commands.json 已被移除 git-push deny，直接 `git push main`

4. **v4.0 建議的 3 條對抗式鐵則（最低必要集）**
   - Iron Rule A: hook 完整性驗證 — session 啟動時驗證 denied-commands.json + session-audit.sh 的 git hash
   - Iron Rule B: append-only bypass log — `.asp-bypass-log.json` 只能 append，任何覆寫嘗試觸發 BLOCKER
   - Iron Rule C: tool output sanitization — agent 的 web_fetch / rag_search 輸出進入 context 前，標記為 UNTRUSTED，不得直接作為指令執行

5. **CYBERSEC 2026 演講重點（從 ASP 視角）**
   - AI dev framework 本身就是一個攻擊面（不只是它保護的 codebase）
   - ASP 的 governance framework 如何被對抗性 AI 利用（kill chain 整合）
   - 可 demo 的漏洞：Step 3（.ai_profile 投毒）+ Step 6（bypass log 清理）

**Step 2: 驗證**

```bash
grep -c "STRIDE\|Spoofing\|Tampering\|Repudiation\|Disclosure\|Denial\|Elevation\|Injection" docs/security/threat-model-v4.0.md
# Expected: ≥ 8
wc -l docs/security/threat-model-v4.0.md
# Expected: ≥ 80
```

---

### Task C2 — Security ADR

**Files:**
- Create: `docs/adr/ADR-002-asp-v4-security-threat-model.md`

**Step 1: 閱讀 ADR 範本**

```bash
cat .asp/templates/ADR_Template.md | head -40
```

**Step 2: 寫入 ADR-002**

```markdown
# ADR-002: ASP 採用 STRIDE 威脅模型進行自我安全審計

**Status:** Accepted
**Date:** 2026-04-29
**Deciders:** astroicers

## Context

ASP v3.7 的鐵則專注於 CI hygiene（ADR 先於實作、敏感資訊保護、破壞性操作防護、外部事實驗證）。
但 ASP **本身**作為一個 AI 治理 framework 沒有威脅模型——攻擊者可以針對 ASP 的規則引擎、hook 系統、
bypass log 等機制進行對抗性攻擊。尤其在 multi-agent 環境中，prompt injection via tool output 和
agent memory poisoning 是真實且未被覆蓋的攻擊向量。

CYBERSEC 2026 演講（astroicers，主題：From Foot Soldier to Commander）需要具體的 ASP 安全 case study。

## Decision

從 v4.0 開始，每個 major version 維護一份 STRIDE 威脅模型文件（`docs/security/threat-model-vX.Y.md`）。
威脅模型隨 release 更新，並成為 `make audit-health` 的 7 維度之一（新增 Dimension 8: Security Posture）。

v4.0 引入的最低必要對抗式防護（3 條 Iron Rules）：
1. Hook 完整性驗證（session-audit.sh 檢查 denied-commands.json 的 git hash）
2. Append-only bypass log（覆寫 .asp-bypass-log.json 觸發 BLOCKER）
3. Tool output UNTRUSTED 標記（web_fetch / rag_search 輸出不得直接作為指令）

## Consequences

**Positive:**
- ASP 有可驗證的安全態勢，不只是 governance hygiene
- CYBERSEC 2026 演講有具體的 framework case study
- Multi-agent 場景的 memory poisoning 和 prompt injection 有明確防護方向

**Negative:**
- 威脅模型需要隨每個 major version 更新（維護成本）
- 3 條新鐵則增加 session 啟動時的 check 數量

## Alternatives Considered

1. **不做威脅模型**：只依賴現有 4 條鐵則——拒絕，因為無法覆蓋 multi-agent 攻擊向量
2. **只做 CYBERSEC 演講素材，不納入 ASP 正式規則**：拒絕，因為安全 governance 應該是 first-class citizen
3. **完整的 formal threat model + 大量對抗式鐵則**：過重，先從最低必要集（3 條）開始，後續 v4.x 擴充
```

**Step 3: 驗證**

```bash
grep "Accepted\|ADR-002\|STRIDE" docs/adr/ADR-002-asp-v4-security-threat-model.md | wc -l
# Expected: ≥ 3
```

---

### Task C3 — Commit Track C

```bash
git add docs/security/threat-model-v4.0.md docs/adr/ADR-002-asp-v4-security-threat-model.md
git commit -m "feat(v4/track-c): STRIDE threat model + ADR-002 (adversarial rules for multi-agent ASP)"
```

---

## Track D — L0 Spike 等級（Phase 1，與其他 Track 平行）

### Task D1 — level-0.yaml

**Files:**
- Create: `.asp/levels/level-0.yaml`

**Step 1: 閱讀 level-1.yaml 的結構**

```bash
cat .asp/levels/level-1.yaml
```

**Step 2: 寫入 level-0.yaml**

```yaml
level: 0
name: Spike
tagline: 探索優先 — 快速驗證假設，零治理負擔，鐵則仍然適用
description: |
  L0 是 ASP 的探索等級。適合「我不知道這個技術能不能 work」的原型驗證階段。
  沒有 ADR 要求、沒有 SPEC 要求、沒有 TDD 要求、沒有 pipeline gate。
  唯一目標：用最快速度驗證技術假設，然後在進入正式開發前切換到 L1+。
  L0 是暫時狀態，不是永久豁免。

profiles:
  - global_core

auto_load:
  - spike_mode

ai_profile_hint: |
  type: system
  level: 0
  name: your-spike-project
  hitl: strict

hitl_override: strict

permissions_granted:
  - skip_adr_requirement
  - skip_spec_requirement
  - skip_tdd_requirement
  - skip_pipeline_gates
  - skip_changelog_update

permissions_denied:
  - production_deploy
  - skip_iron_rules
  - skip_credential_scan

graduation_checklist:
  - id: spike-question-answered
    description: "Spike 驗證問題已有明確答案（可行 / 不可行）"
    check: "test -f docs/spike-conclusion.md || find docs -name 'spike*.md' -o -name 'poc*.md' 2>/dev/null | grep -q ."
    manual: true
  - id: no-production-code-in-main
    description: "Spike 代碼未進入 main branch"
    check: "git branch --show-current | grep -E 'spike|poc|experiment'"
  - id: spike-timebox-not-exceeded
    description: "Spike 未超過 5 個工作天（可豁免，需說明）"
    check: "true"
    manual: true

exit_to:
  recommended: 1
  rationale: "Spike 驗證後，進入 L1 (Starter) 開始正式開發"

exit_triggers:
  - "使用者說「這個方向可行，我們繼續開發」"
  - "Spike 超過 3 天仍無結論"
  - "開始寫第一個非 spike 的正式功能"

warnings:
  - "L0 沒有品質保護。Spike 代碼不應直接進入生產。"
  - "如果 spike 持續超過 5 個工作天，考慮是否升級到 L1。"
  - "L0 強制 hitl: strict — 你在探索未知，每步都需確認。"

use_cases:
  - "nuclei template 命中率驗證（半天工作）"
  - "CYBERSEC 演講 PoC：示範 prompt injection 攻擊 multi-agent"
  - "評估新 MCP server 是否值得整合"
  - "新框架 / 第三方 API 可行性探索"

benefits_of_upgrading: |
  升到 L1 (Starter) 後，你會獲得：
  - ADR 記錄：確保 spike 決策有根據
  - SPEC 要求：把「感覺差不多」轉成可驗收的規格
  - TDD：沒有測試的代碼難以重構進入正式版

next_level: 1
```

**Step 3: 驗證**

```bash
python3 -c "import yaml; d=yaml.safe_load(open('.asp/levels/level-0.yaml')); print(d['level'], d['name'])"
# Expected: 0 Spike

ls .asp/levels/level-*.yaml | wc -l
# Expected: 6
```

---

### Task D2 — spike_mode.md profile

**Files:**
- Create: `.asp/profiles/spike_mode.md`

**Step 1: 寫入 spike_mode.md**

```markdown
# Spike Mode Profile — L0 探索模式

<!-- requires: global_core -->
<!-- optional: (none) -->
<!-- conflicts: autonomous_dev, autopilot, pipeline, multi_agent -->

適用：L0 (Spike) 等級。快速原型驗證，最小治理約束。
載入條件：`.ai_profile` 中 `level: 0`（由 level-0.yaml 自動載入）

---

## 核心原則

L0 是暫時狀態，不是豁免狀態。所有「跳過」都是**顯式豁免**，
必須在 commit message 中標記 `[spike]`，以便日後清理。

---

## 允許跳過的規則

| 規則 | 豁免條件 |
|------|---------|
| ADR 建立 | spike 可無 ADR 直接實作；進 L1+ 前必須補 ADR |
| SPEC 建立 | spike 可無 SPEC；spike 結束前必須寫 spike-conclusion.md |
| TDD | spike 可先實作後補（或不補）測試 |
| Pipeline gate G1-G6 | 全部跳過 |
| CHANGELOG 更新 | spike 期間可跳過 |

---

## 絕不可跳過（繼承自 global_core 鐵則）

- 破壞性操作防護（git push, rm -rf 等仍受 deny list 保護）
- 敏感資訊保護（API key, 密碼不可 hardcode）
- asp-ship Step 9（憑證掃描）— spike 代碼也不能有硬編碼密碼
- `git push` 前的人類確認

---

## 強制 HITL: strict

即使 `.ai_profile` 設定了 `hitl: minimal`，L0 覆蓋為 `hitl: strict`。
因為你在探索未知領域，每個決策都需要人類確認。

---

## Spike 分支紀律

- L0 代碼必須在 `spike/*` 或 `poc/*` 或 `experiment/*` branch
- **禁止從 L0 直接 commit 到 main**
- Spike 結論寫入 `docs/spike-conclusion.md`（或類似）

---

## L0 → L1 升級觸發

AI 在以下情況**必須**提示使用者考慮升級到 L1：

1. 使用者說「這個方向可行，我們繼續開發」
2. Spike 開始第 3 天仍無明確結論
3. 開始寫第一個非 spike 的正式功能
4. 使用者詢問「這個要加測試嗎」（L0 沒有測試，是時候升級了）
```

**Step 2: 驗證**

```bash
grep "conflicts: autonomous_dev\|hitl: strict\|spike/\|exit_triggers\|L0 → L1" .asp/profiles/spike_mode.md | wc -l
# Expected: ≥ 3
```

---

### Task D3 — Commit Track D

```bash
git add .asp/levels/level-0.yaml .asp/profiles/spike_mode.md
git commit -m "feat(v4/track-d): L0 Spike maturity level — pre-governance exploration mode with 3-day timebox and explicit graduation to L1"
```

---

## Track E — MCP Server & Telemetry（Phase 2）

### Task E1 — MCP Server ADR

**Files:**
- Create: `docs/adr/ADR-003-asp-mcp-server.md`

**Step 1: 閱讀 ADR 範本**

```bash
head -50 .asp/templates/ADR_Template.md
```

**Step 2: 寫入 ADR-003**

必須包含：
- Status: Accepted
- Context: ASP 目前無程式化 API 面，skill 和 hook 都是 Markdown/Bash
- 三個選項評估：
  - Option A: TypeScript (Node.js) — Anthropic reference implementation，但引入 Node.js 依賴
  - Option B: Python — 與 `.asp/scripts/rag/*.py` 相容，複用現有基礎
  - Option C: Bash — 無新依賴，但難以維護 stateful tool 響應
- Decision: Python (Option B)
- 初始 6 個 tool：asp_gate_evaluate, asp_audit_quick, asp_bypass_log, asp_telemetry_push, asp_handoff_create, asp_fact_check_log
- Consequences: 需要 `mcp` Python package；MCP server 為可選（skill 無 server 時仍可運作）

**Step 3: 驗證**

```bash
grep "Accepted\|ADR-003\|Python\|asp_gate_evaluate" docs/adr/ADR-003-asp-mcp-server.md | wc -l
# Expected: ≥ 3
```

---

### Task E2 — MCP Server SPEC

**Files:**
- Create: `docs/specs/SPEC-002-asp-mcp-server.md`

**Step 1: 閱讀 SPEC 範本**

```bash
head -60 .asp/templates/SPEC_Template.md
```

**Step 2: 寫入 SPEC-002**

必須包含：
- Goal: 提供 MCP server，讓 Claude Code 以結構化 tool 呼叫 ASP governance 操作
- Inputs: 6 個 tool 的完整 JSON schema（input/output/errors）
- Expected Outputs: `{"status": "...", "verdict": "...", "data": {...}}` 格式
- Side Effects: 寫入 .asp-bypass-log.json, .asp-fact-check.md, .asp-telemetry.jsonl
- Edge Cases: MCP server 未啟動時 skill 仍可運作（backward compatible）
- Done When（至少 4 條 binary checks）
- Rollback Plan
- Traceability: ADR-003

```markdown
Done When:
- [ ] `python3 .asp/mcp/server.py --check` 回傳 `{"status": "ok", "tools": 6}`
- [ ] `asp_gate_evaluate(gate_id="G4", context_json="{}") `回傳 JSON without crashing
- [ ] `.ai_profile` 不存在時回傳 `{"status": "no_profile", "verdict": "SKIP"}` 而不是 crash
- [ ] 所有 13 個現有 skill 在 MCP server 不存在時仍可正常運作
```

**Step 3: 驗證**

```bash
grep "Done When\|SPEC-002\|asp_gate_evaluate" docs/specs/SPEC-002-asp-mcp-server.md | wc -l
# Expected: ≥ 3
```

---

### Task E3 — Telemetry 腳本

**Files:**
- Create: `.asp/scripts/telemetry/collect.py`
- Create: `.asp/scripts/telemetry/report.py`
- Create: `.asp/scripts/telemetry/prune.py`
- Create: `.asp/scripts/telemetry/README.md`

**Step 1: 寫入 collect.py**

```python
#!/usr/bin/env python3
"""ASP telemetry event collector.
Reads .asp-session-briefing.json and .asp-bypass-log.json,
appends structured events to .asp-telemetry.jsonl.
Usage: python3 collect.py [--dry-run]
"""
import json, sys, os
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))
TELEMETRY_FILE = PROJECT_ROOT / ".asp-telemetry.jsonl"
BRIEFING_FILE = PROJECT_ROOT / ".asp-session-briefing.json"
BYPASS_LOG_FILE = PROJECT_ROOT / ".asp-bypass-log.json"

def collect_session_start_event():
    event = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "event_type": "session_start",
        "asp_version": "4.0.0",
        "data": {
            "blockers": 0,
            "warnings": 0,
            "profile_type": "unknown"
        }
    }
    if BRIEFING_FILE.exists():
        try:
            briefing = json.loads(BRIEFING_FILE.read_text())
            event["data"]["blockers"] = len(briefing.get("BLOCKERS", []))
            event["data"]["warnings"] = len(briefing.get("WARNINGS", []))
        except Exception:
            pass
    return event

def main():
    dry_run = "--dry-run" in sys.argv
    event = collect_session_start_event()
    if dry_run:
        print(json.dumps(event, ensure_ascii=False, indent=2))
        return
    with open(TELEMETRY_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(event, ensure_ascii=False) + "\n")
    print(f"[asp-telemetry] Event recorded: {event['event_type']}")

if __name__ == "__main__":
    main()
```

**Step 2: 寫入 report.py**

```python
#!/usr/bin/env python3
"""ASP telemetry weekly report generator.
Usage: python3 report.py [--days 7]
"""
import json, sys
from pathlib import Path
from collections import defaultdict
from datetime import datetime, timezone, timedelta

PROJECT_ROOT = Path(__file__).parent.parent.parent
TELEMETRY_FILE = PROJECT_ROOT / ".asp-telemetry.jsonl"

def main():
    days = 7
    for i, arg in enumerate(sys.argv):
        if arg == "--days" and i + 1 < len(sys.argv):
            days = int(sys.argv[i + 1])

    if not TELEMETRY_FILE.exists():
        print("No telemetry data found. Run collect.py first.")
        return

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    events = []
    for line in TELEMETRY_FILE.read_text().splitlines():
        if line.strip():
            try:
                e = json.loads(line)
                if datetime.fromisoformat(e["ts"]) > cutoff:
                    events.append(e)
            except Exception:
                pass

    event_counts = defaultdict(int)
    bypass_skills = defaultdict(int)
    gate_results = defaultdict(lambda: {"pass": 0, "fail": 0})

    for e in events:
        event_counts[e["event_type"]] += 1
        if e["event_type"] == "bypass":
            bypass_skills[e["data"].get("skill", "unknown")] += 1
        if e["event_type"] in ("gate_pass", "gate_fail"):
            gate_id = e["data"].get("gate_id", "unknown")
            result = "pass" if e["event_type"] == "gate_pass" else "fail"
            gate_results[gate_id][result] += 1

    print(f"\n=== ASP Telemetry Report (last {days} days) ===")
    print(f"Total events: {len(events)}")
    print("\nEvent breakdown:")
    for k, v in sorted(event_counts.items(), key=lambda x: -x[1]):
        print(f"  {k}: {v}")
    if bypass_skills:
        print("\nMost bypassed skills:")
        for k, v in sorted(bypass_skills.items(), key=lambda x: -x[1])[:5]:
            print(f"  {k}: {v} times")
    if gate_results:
        print("\nGate results:")
        for gate, results in sorted(gate_results.items()):
            total = results["pass"] + results["fail"]
            rate = f"{100*results['pass']//total}%" if total > 0 else "N/A"
            print(f"  {gate}: {results['pass']}/{total} passed ({rate})")

if __name__ == "__main__":
    main()
```

**Step 3: 寫入 prune.py**

```python
#!/usr/bin/env python3
"""ASP telemetry pruner. Archives events older than --days to .asp-telemetry-archive/
Usage: python3 prune.py [--days 90]
"""
import json, sys
from pathlib import Path
from datetime import datetime, timezone, timedelta

PROJECT_ROOT = Path(__file__).parent.parent.parent
TELEMETRY_FILE = PROJECT_ROOT / ".asp-telemetry.jsonl"
ARCHIVE_DIR = PROJECT_ROOT / ".asp-telemetry-archive"

def main():
    days = 90
    for i, arg in enumerate(sys.argv):
        if arg == "--days" and i + 1 < len(sys.argv):
            days = int(sys.argv[i + 1])

    if not TELEMETRY_FILE.exists():
        print("No telemetry data.")
        return

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    keep, archive = [], []
    for line in TELEMETRY_FILE.read_text().splitlines():
        if not line.strip():
            continue
        try:
            e = json.loads(line)
            if datetime.fromisoformat(e["ts"]) > cutoff:
                keep.append(line)
            else:
                archive.append((e["ts"][:7], line))  # (YYYY-MM, raw)
        except Exception:
            keep.append(line)

    if not archive:
        print("Nothing to prune.")
        return

    ARCHIVE_DIR.mkdir(exist_ok=True)
    by_month = {}
    for month, line in archive:
        by_month.setdefault(month, []).append(line)
    for month, lines in by_month.items():
        archive_file = ARCHIVE_DIR / f"{month}.jsonl"
        with open(archive_file, "a") as f:
            f.write("\n".join(lines) + "\n")

    TELEMETRY_FILE.write_text("\n".join(keep) + "\n" if keep else "")
    print(f"Pruned {len(archive)} events, kept {len(keep)} events.")

if __name__ == "__main__":
    main()
```

**Step 4: 寫入 .asp/scripts/telemetry/README.md**

簡短說明：
- collect.py 用途
- report.py 用途（--days 參數）
- prune.py 用途（--days 參數）
- 如何整合到 session-audit.sh（可選）
- 如何讀懂 weekly report

**Step 5: 驗證**

```bash
python3 .asp/scripts/telemetry/collect.py --dry-run
# Expected: valid JSON output (no crash)

python3 .asp/scripts/telemetry/report.py
# Expected: either "No telemetry data found" or report output (no crash)

python3 .asp/scripts/telemetry/prune.py
# Expected: "Nothing to prune." (no crash)
```

---

### Task E4 — Telemetry ADR & Makefile targets

**Files:**
- Create: `docs/adr/ADR-004-asp-telemetry.md`
- Modify: `.asp/Makefile.inc`（若存在）或在 `Makefile` 補充 target

**Step 1: 閱讀現有 Makefile.inc**

```bash
cat .asp/Makefile.inc | tail -30
```

**Step 2: 寫入 ADR-004**

Status: Accepted
Decision: JSONL append-only telemetry（非 SQLite）
理由：無 runtime 依賴、grep-able、git diff-able、失敗 silent 不影響主流程

**Step 3: 補充 Makefile targets（在 .asp/Makefile.inc 或 Makefile 末尾）**

```makefile
# ─── Telemetry ───────────────────────────────────────────────────────────────
asp-telemetry-collect:
	@python3 .asp/scripts/telemetry/collect.py
	@echo "[ASP] Telemetry event collected"

asp-telemetry-report:
	@python3 .asp/scripts/telemetry/report.py --days 7

asp-telemetry-prune:
	@python3 .asp/scripts/telemetry/prune.py --days 90
```

**Step 4: Commit Track E**

```bash
git add docs/adr/ADR-003-asp-mcp-server.md docs/specs/SPEC-002-asp-mcp-server.md \
    .asp/scripts/telemetry/ docs/adr/ADR-004-asp-telemetry.md
git commit -m "feat(v4/track-e): MCP server ADR-003 + SPEC-002 + telemetry system (JSONL append-only) + ADR-004"
```

---

## Track F — 整合 SDS（Phase 3，需等所有 Track 完成）

### Task F1 — v4.0 整合架構 SPEC

**Files:**
- Create: `docs/specs/SPEC-003-asp-v4-architecture-refactor.md`

**Depends on:** A1-A5, B1-B9, C1-C3, D1-D3, E1-E4 全部完成

**Step 1: 閱讀 SDS 範本**

```bash
head -80 .asp/templates/SDS_Template.md
```

**Step 2: 寫入 SPEC-003**

結構必須包含：

1. **Goal**（30 字內）
   "ASP v4.0 = 憲法壓縮 + Skill 增殖 + 可觀測性層：把 v3.7 的 token 負擔降低 40%，同時增加 8 個 capability 與 security posture。"

2. **Architecture Overview**（ASCII diagram）

3. **Migration Guide**（v3.7 → v4.0，5 步驟）

4. **Backward Compatibility Matrix**（5 行 table）

5. **Done When**（8 條 binary checks）
   - [ ] `wc -l CLAUDE.md` ≤ 100
   - [ ] `ls .claude/skills/asp/asp-*.md | wc -l` = 21
   - [ ] `ls .asp/levels/level-*.yaml | wc -l` = 6
   - [ ] `ls docs/adr/ADR-*.md | wc -l` = 4
   - [ ] `ls docs/specs/SPEC-*.md | wc -l` = 3
   - [ ] `python3 .asp/scripts/telemetry/collect.py --dry-run` exits 0
   - [ ] `grep -c 'asp-handoff\|asp-team-pick' .claude/skills/asp/SKILL.md` ≥ 2
   - [ ] `bash .asp/hooks/session-audit.sh` exits 0

6. **v4.0 不解決什麼**（至少 5 條）
   - 不取代 Superpowers skills（兩者互補）
   - 不為 enterprise 多人協作優化（仍是個人/小團隊定位）
   - MCP server 在 v4.0 是 ADR + SPEC（設計），實作留 v4.1+
   - 不解決 AI 幻覺問題（只有 fact-verify gate，不保證完全準確）
   - 不取代 test framework（只治理流程，不寫測試）

7. **Edge Cases（v4.0 可能比 v3.7 差的情境）**
   - CLAUDE.md 壓縮後，第一次使用 ASP 的人可能需要多看一層文件
   - 8 個新 skill 增加 router 決策複雜度（SKILL.md 觸發詞增加）
   - L0 可能被濫用，讓使用者永遠停在 Spike 模式

8. **Rollback Plan**
   - `cp CLAUDE.md.v3.7-backup CLAUDE.md`
   - 移除 `.claude/skills/asp/asp-{8-new-skills}.md`
   - `rm .asp/levels/level-0.yaml .asp/profiles/spike_mode.md`

**Step 3: 驗證**

```bash
grep "Done When\|SPEC-003\|v4.0 不解決" docs/specs/SPEC-003-asp-v4-architecture-refactor.md | wc -l
# Expected: ≥ 3
wc -l docs/specs/SPEC-003-asp-v4-architecture-refactor.md
# Expected: ≥ 80
```

---

### Task F2 — v4.0 決策日誌

**Files:**
- Create: `docs/v4-decision-log.md`

**Step 1: 寫入決策日誌**

格式：每個主要決策一節，包含：問題 | 被拒絕的方案 | 最終決策 | 理由

必須涵蓋：
1. 為什麼壓縮 CLAUDE.md（309 行問題）
2. 為什麼做 profile → skill 抽取
3. 為什麼選 Python for MCP server（非 TypeScript）
4. 為什麼選 JSONL for telemetry（非 SQLite）
5. 為什麼加 L0 Spike 等級
6. 我們決定不做什麼（被拒絕的想法清單）

**Step 2: Commit Track F**

```bash
git add docs/specs/SPEC-003-asp-v4-architecture-refactor.md docs/v4-decision-log.md
git commit -m "feat(v4/track-f): integration SDS SPEC-003 + v4 decision log"
```

---

## Phase 4 — 驗收檢查

### Task V1 — 全部 Done When 驗證

**Step 1: 執行全部驗收指令**

```bash
cd /home/ubuntu/AI-SOP-Protocol
echo "=== CLAUDE.md 行數 ==="
wc -l CLAUDE.md  # Expected: ≤ 100

echo "=== Skill 數量 ==="
ls .claude/skills/asp/asp-*.md | wc -l  # Expected: 21 (13 + 8)

echo "=== Level 數量 ==="
ls .asp/levels/level-*.yaml | wc -l  # Expected: 6 (L0-L5)

echo "=== ADR 數量 ==="
ls docs/adr/ADR-*.md | wc -l  # Expected: 4

echo "=== SPEC 數量 ==="
ls docs/specs/SPEC-*.md | wc -l  # Expected: 3

echo "=== 鐵則完整性 ==="
grep -E "ADR 未定案|外部事實|敏感資訊|破壞性操作" CLAUDE.md | wc -l  # Expected: 4

echo "=== Telemetry 腳本 ==="
python3 .asp/scripts/telemetry/collect.py --dry-run  # Expected: valid JSON

echo "=== Session audit hook ==="
bash .asp/hooks/session-audit.sh  # Expected: exits without error

echo "=== Skill router ==="
grep "asp-handoff\|asp-team-pick\|asp-escalate\|asp-dev-qa-loop\|asp-fact-verify\|asp-assumption-checkpoint\|asp-bug-classify\|asp-change-cascade" .claude/skills/asp/SKILL.md | wc -l  # Expected: 8
```

### Task V2 — 版本號更新與最終 commit

```bash
echo "4.0.0-alpha" > .asp/VERSION

# 確認 .asp/VERSION
cat .asp/VERSION  # Expected: 4.0.0-alpha

git add .asp/VERSION
git commit -m "chore(v4.0.0-alpha): bump version to 4.0.0-alpha

v4.0 refactor complete on feature/v4-refactor:
- CLAUDE.md: 309 → ≤100 lines
- Skills: 13 → 21 (+8 extracted from profiles)
- Levels: L1-L5 → L0-L5 (Spike mode)
- ADRs: 1 → 4 (security, MCP, telemetry)
- SPECs: 1 → 3 (MCP server, architecture SDS)
- Telemetry: JSONL append-only system
- Security: STRIDE threat model for ASP itself
- Decision log: docs/v4-decision-log.md"
```

---

## 依賴關係圖

```
Task 0.1 (branch + dirs)
    │
    ├── A1 (baseline json) → A2 (baseline md)
    │       │
    │       ├── A3 (disposition matrix yaml)
    │       │       │
    │       │       └── A4 (red team md) → A5 (CLAUDE.md rewrite)
    │       │
    │       ├── B1-B8 (8 new skills) → B9 (SKILL.md update)
    │       │
    │       ├── C1 (threat model) → C2 (ADR-002)
    │       │
    │       ├── D1 (level-0.yaml) → D2 (spike_mode.md)
    │       │       └── D3 (需要 A5 完成後更新 CLAUDE.md L0 row)
    │       │
    │       └── E1 (ADR-003) → E2 (SPEC-002) → E3 (telemetry scripts) → E4 (ADR-004)
    │
    └── F1 (SPEC-003) → F2 (decision log) → V1 → V2
            (等待 A/B/C/D/E 全部完成)
```

---

## 風險與緩解

| 風險 | 機率 | 影響 | 緩解 |
|------|------|------|------|
| CLAUDE.md 壓縮遺漏鐵則 | LOW | CRITICAL | 壓縮後立即 `grep -E "ADR 未定案\|外部事實\|敏感資訊\|破壞性操作" CLAUDE.md` |
| 新 skill 破壞現有 SKILL.md router | MED | HIGH | B9 專門做 router 更新；執行後測試所有觸發詞 |
| session-audit.sh 在加入 telemetry 後失敗 | MED | HIGH | hook 永遠 `exit 0`；加入 telemetry 前後各測 |
| L0 profile 與 pipeline.md 衝突 | LOW | MED | `<!-- conflicts: ... -->` 已在 spike_mode.md 聲明 |
| 平行執行 context 超限 | MED | LOW | Track A/B/C/D 各自獨立 commit；Track F 等全部落地後再執行 |
