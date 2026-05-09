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

## v4.1 — Planned: Adversarial Hardening

**Theme:** Move from documented threats to enforced mitigations.

| Feature | ADR | Status |
|---------|-----|--------|
| Iron Rule A: Hook file GPG signing | ADR-002 | Planned |
| Iron Rule B: `.asp-bypass-log.ndjson` + `chattr +a` enforcement | ADR-002 | Planned |
| Iron Rule C: UNTRUSTED_EXTERNAL parsing in tool output layer | ADR-002 | Doc-only in v4.0 |
| Multi-agent memory isolation (worker A cannot read worker B memory) | TBD | Planned |
| RAG poisoning detection (semantic drift alerts in `rag_search`) | TBD | Planned |
| `audit-health` Dimension 8: Security Posture score (0–5) | TBD | Planned |

---

## v4.2 — Vision: Observability & Demo Harness

| Feature | Notes |
|---------|-------|
| CYBERSEC demo harness | Reproducible attack scenario scripts for live demo |
| Telemetry dashboard | Local HTML report from `.asp-telemetry.jsonl` |
| `asp-gate` G5.5 / G6.5 gates | Adversarial content scanning, memory poisoning check |
| Bypass rate alerting | Auto-escalate when bypass rate > 30% in 7 days |

---

## v5.0 — Future: Enterprise & Multi-Tenant

| Feature | Notes |
|---------|-------|
| Multi-project RBAC | One ASP instance governing multiple repos |
| Full behavioral test suite | Automated tests that verify AI governance behavior |
| Enterprise multi-agent orchestration | Horizontal scaling of multi-agent pipelines |

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
