# ASP Framework Roadmap

> This is the ASP *framework-level* roadmap — not a project task list.
> For project autopilot task tracking, use `.asp/templates/ROADMAP_Template.yaml`.

---

## v4.0 — Current Release (2026-04-29)

### Shipped ✅

- CLAUDE.md compressed from 309 → ≤100 lines (disposition matrix driven)
- 9 new skills extracted from profiles: `asp-handoff`, `asp-team-pick`, `asp-escalate`,
  `asp-dev-qa-loop`, `asp-fact-verify`, `asp-assumption-checkpoint`, `asp-bug-classify`,
  `asp-change-cascade`, `asp-context`
- L0 Spike maturity level added (`level-0.yaml` + `spike_mode.md`)
- Telemetry system: `collect.py` / `report.py` / `prune.py` + ADR-004
- STRIDE threat model: 13 threats, 8-step attack chain (`docs/security/threat-model-v4.0.md`)
- CONTEXT.md domain vocabulary mechanism (`asp-context` skill)
- Disposition matrix: 33 elements classified, 15 red-team questions answered

### v4.0 Gap-Fill Sprint (2026-05-09) ✅

- CLAUDE.md trimmed to exactly 100 lines
- Iron Rules A/B/C implemented in `session-audit.sh` + `global_core.md`
- L0 user-facing documentation: `docs/level0-spike-mode.md` + `example-profile-spike.yaml`
- This `docs/ROADMAP.md`
- SPEC-003 Done-When table corrected to reflect MCP removal

---

## v4.1 — Shipped: Multi-Agent Worktree Isolation (2026-05-10)

**Theme:** Move from documented threats to enforced mitigations + multi-agent hard isolation.

| Feature | ADR | Status |
|---------|-----|--------|
| Iron Rule A/B/C 機制與文件 | ADR-002 | ✅ Shipped (v4.0) |
| **Multi-agent worktree hard isolation** | D6 / SPEC-004 | ✅ Shipped (v4.1.0 GA, 2026-05-10) |
| ASP_AUDIT_ROOT fail-safe (Iron Rule B 強化) | SPEC-004 | ✅ Shipped (v4.1.0) |
| AI Performance Review System | D-006 | ✅ Shipped (v4.0 + ~/.claude/asp/ai-performance/) |
| Reality Checker Layer 3 (cross-vendor) | D-008 | ✅ Shipped (asp-external-review skill, v4.0) |
| Semgrep Security Ruleset | D-002 | ✅ Shipped (.semgrep/asp-security.yml, v4.0) |
| L0 Lifecycle Audit | D-009 | ✅ Shipped (make asp-l0-audit, v4.0) |
| GA holistic review gate | ADR-005 | ✅ Accepted (2026-05-10), 第一次套用於 v4.2.0 |

### v4.1.x patches
- v4.1.0-alpha (2026-05-10): SPEC-004 7 batches B1-B7
- v4.1.0 (2026-05-10): SPEC-004 GA, Done When 18/18 (later corrected to 16+2 partial in v4.1.1)
- v4.1.1 (2026-05-10): post-GA review-fix patch + cleanup wave 1+2+3

### v4.1.x deferred to later versions
- Iron Rule A 強化（GPG hook signing）→ v4.3 評估
- Iron Rule B 強化（chattr +a enforcement）→ v4.3 評估
- Iron Rule C runtime parsing（v4.0 仍是 doc-only）→ v4.3 評估
- N2 Worker runtime scope.forbid 攔截（PreToolUse hook 整合）→ v4.2.x patch
- B4 dispatch 階段磁碟空間動態預檢 → v4.2.x patch
- Multi-agent memory isolation → v4.3 評估
- RAG poisoning detection → v4.3 評估
- audit-health Dimension 8 (Security Posture score) → v4.3 評估

---

## v4.2 — Planned: Cleanup wave 4 (high-ROI feature audit, ~1 week)

**Theme:** Trim ~1,000 lines / ~7 files / ~13 Makefile targets per ADR-006 §Roadmap §v4.2.0.

詳細 5 個 item 與 Done When 見 [ADR-006](adr/ADR-006-feature-audit-roadmap.md) §v4.2.0 表格：

| # | Item | 削減 | Status |
|---|------|-----|--------|
| 1 | REMOVE 4 重複 skill (asp-fact-verify, -assumption-checkpoint, -bug-classify, -change-cascade) | -652 行 | Planned (ADR-006 Accepted 後啟動) |
| 2 | REMOVE 3 dead template + handoff/ 空目錄 | -274 行 | Planned |
| 3 | REMOVE 9 無引用 Makefile target | -80 行 | Planned |
| 4 | CONSOLIDATE 4 doc-new target → 1 | -3 個 target | Planned |
| 5 | 修 README vs where-to-start 重疊 | 重疊 30%→5% | Planned |

加上前一段列出的 v4.1.x deferred items（N2 / B4）作為 v4.2.x patches。

---

## v4.3 — Planned: Cleanup wave 5 (mid-ROI consolidation, ~2-3 weeks)

**Theme:** Trim ~2,500 lines / ~5 files per ADR-006 §v4.3.0.

| # | Item | 削減 | Risk |
|---|------|-----|------|
| 6 | CONSOLIDATE task_orchestrator + multi_agent + pipeline (3 大 profile 整併) | 2,315 → ~1,000 行 | Medium |
| 7 | REMOVE autopilot.md profile (邏輯收回 asp-autopilot skill) | -566 行 | Low |
| 8 | CONSOLIDATE asp-escalate → asp-handoff | -159 行 | Low |
| 9 | CONSOLIDATE asp-qa → asp-dev-qa-loop | -83 行 | Low |
| 10 | REMOVE asp-security skill (路由到 make security-scan) | -71 行 | Low |
| 11 | REFACTOR validate-profile.sh (bash → jsonschema) | -170 行 | Medium |
| 12 | CONSOLIDATE 3 concept docs → concepts.md or README | -200 行 | Low |

加上 v4.1.x deferred 的 Iron Rule A/B/C 強化評估、memory isolation、RAG poisoning、Security Posture score。

---

## v5.0 — Future: Major refactors (≥ 3 months out)

詳見 [ADR-006](adr/ADR-006-feature-audit-roadmap.md) §v5.0.0：

| # | Item | 削減 | 為何 v5 |
|---|------|-----|--------|
| 13 | L0-L5 → L0-L3 4 級 (砍 level-2, level-5) | -2 yaml + 心智負擔大降 | 影響 .ai_profile schema，需 migration tool |
| 14 | autonomous_dev + vibe_coding → autonomy_boundaries.md | -200 行 | 影響 autopilot 等多依賴 |
| 15 | architecture / multi-agent-arch / production-ops 三檔重整 | -400 行 | 大幅改 outline，需設計 review |

加上原 v5.0 既定 vision：
- Multi-project RBAC: One ASP instance governing multiple repos
- Full behavioral test suite: Automated tests that verify AI governance behavior
- Enterprise multi-agent orchestration: Horizontal scaling of multi-agent pipelines

---

## 累積目標（v4.2 + v4.3 + v5.0 完成後）

per ADR-006 §累積規模：

| 維度 | v4.1.1 (current) | v5.0 (target) | 削減 |
|---|---|---|---|
| Skill 數 | 23 | 14 | -9 (39%) |
| Skill 行數 | 3,839 | ~2,400 | -1,400 |
| Profile 數 | 18 | 13 | -5 |
| Profile 行數 | 5,961 | ~3,500 | -2,460 |
| Template 數 | 17 | 13 | -4 |
| Makefile target 數 | 86 | ~65 | -21 |
| Doc 行數 | 3,671 | ~3,000 | -670 |
| Maturity Levels | 6 | 4 | -2 yaml |
| **總行數削減** | — | — | **~4,800 行** |
| **總檔案削減** | — | — | **~14 檔** |
| **維護面積削減** | — | — | **~30-35%** |

---

## Migration Guide: v3.7 → v4.0

### Step 1 — Update CLAUDE.md
```bash
# Check your current CLAUDE.md is the v4.0 version (≤100 lines)
wc -l CLAUDE.md
# If > 100: pull latest from ASP repo
```

### Step 2 — Verify new skills present
```bash
ls .claude/skills/asp/asp-*.md | wc -l
# Expected: ≥ 20 (was 13 in v3.7)
```

### Step 3 — Add L0 level file (if missing)
```bash
ls .asp/levels/level-0.yaml || echo "Missing — copy from ASP repo"
```

### Step 4 — Initialize telemetry
```bash
make asp-telemetry-collect   # first run creates .asp-telemetry.jsonl
```

### Step 5 — Run full health audit
```bash
make audit-health
# Resolve any BLOCKERs before treating upgrade as complete
```

---

## Deprecation Notices

| Deprecated | Replacement | Timeline |
|-----------|-------------|----------|
| `.asp-bypass-log.json` (mutable JSON array) | `.asp-bypass-log.ndjson` (append-only NDJSON) | v4.1 — run `make asp-bypass-migrate` to convert |
| `agent_memory.md` profile (session-only, no persistence) | Stateful MCP tool — will re-evaluate in v4.1 if architectural decision revisited | TBD |
| `pipeline.md` direct profile loading | Prefer `asp-gate` skill invocation + `level-3.yaml` | Soft deprecation v4.0; formal v4.1 |

---

## What ASP Will Not Do

| Out of scope | Reason |
|-------------|--------|
| Replace Superpowers plugin | Complementary frameworks — ASP = governance, Superpowers = dev workflow |
| Fix AI hallucination | Governance framework, not model alignment |
| Enterprise RBAC | Personal/small-team tool; scope creep risk |
| Real-time telemetry dashboard | JSONL is grep-able; dashboard adds infra complexity without clear ROI |
| MCP server implementation | Deliberately removed in v4.0; stateful needs will be re-evaluated in v4.1 |
| User-base / cross-repo governance | Currently repo-scoped by design; v5.0 vision item |
