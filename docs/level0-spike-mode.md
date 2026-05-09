# L0 Spike Mode — User Guide

> **Use when:** Technical assumption validation, PoC, CYBERSEC demo prep, new framework/API feasibility.
> **Time-box:** ≤5 working days. If you need more, consider upgrading to L1.

---

## Quick Start

1. Copy `.asp/templates/example-profile-spike.yaml` → `.ai_profile` in project root
2. Work on a `spike/*` branch (L0 blocks direct commits to main)
3. Write `docs/spike-conclusion.md` before graduating to L1

```bash
cp .asp/templates/example-profile-spike.yaml .ai_profile
git checkout -b spike/my-spike-name
```

---

## What L0 Skips

| Skipped | Why | Must catch up before L1 |
|---------|-----|-------------------------|
| ADR requirement | Exploration decisions change constantly | Yes — create ADR for any architectural choices made |
| SPEC requirement | Spike questions evolve too fast for specs | Yes — write SPEC for anything being kept |
| TDD / G1-G6 gates | Too much friction for exploration | Yes — write tests before code goes to production |
| CHANGELOG entries | Spike branches are throwaway | Yes — summarize outcome in spike-conclusion.md |
| Pipeline gates | No CI/CD overhead during exploration | Yes — re-run all gates at L1+ |

---

## What L0 NEVER Skips (Iron Rules always apply)

| Rule | Behavior in L0 |
|------|----------------|
| `git push` → list changes first | Always — destructive op protection is non-negotiable |
| No API keys / credentials in output | Always — credential scan runs regardless of level |
| External fact verification (weak form) | Mark source; full verify required before L1 promotion |
| Destructive op confirmation (HITL strict) | Always — L0 **forces** `hitl: strict` regardless of profile setting |

---

## Graduation Checklist (L0 → L1)

Before merging your spike branch to main, confirm all items:

- [ ] `docs/spike-conclusion.md` written — what did you learn? go or no-go?
- [ ] Architecture choices documented in ADR(s)
- [ ] SPEC written for anything being kept in production
- [ ] Tests written for code being kept
- [ ] Code moved from `spike/*` branch via PR (not direct merge)
- [ ] `.ai_profile` updated to `level: 1` (or higher)

```bash
# Run level check before upgrading
make asp-level
```

---

## Three Real Usage Scenarios

### A — CVE / nuclei template validation (half-day spike)

```yaml
spike_question: "Does our nuclei template hit CVE-2025-XXXXX in the test environment?"
spike_deadline: "2026-05-09"
```

ASP interventions: ~1 (git push confirmation). No gates, no ADR required.
Outcome: either template works (→ commit to nuclei repo) or doesn't (→ discard).

### B — Prompt injection PoC for CYBERSEC demo (2-day spike)

```yaml
spike_question: "Can we demo multi-agent prompt injection live on stage?"
spike_deadline: "2026-05-11"
```

ASP interventions: ~3 (git push ×2, destructive op confirmation ×1).
Outcome: either demo harness works (→ L1 with ADR on attack scenario design) or pivot.

### C — MCP server feasibility assessment (3-day spike)

```yaml
spike_question: "Is fastmcp compatible with our hook architecture?"
spike_deadline: "2026-05-14"
```

ASP interventions: ~2.
Outcome: go → upgrade to L1, create ADR, write SPEC; no-go → document in spike-conclusion.md.

---

## L0 Lifecycle: Active vs Zombie Diagnosis

Run `make asp-l0-audit` monthly on L0 repos. Ask three questions:

1. **Active?** — Any commits in the last 30 days?
2. **Understandable?** — Can you change something in <30 min?
3. **Worth keeping?** — Would losing it cause pain?

| Answer | Diagnosis | Action |
|--------|-----------|--------|
| All yes | Active L0 | Continue as-is |
| No to Q1 only | Zombie | Archive or delete |
| No to Q2 | Zombie trap | Upgrade to L1 or refactor before it rots further |
| No to Q3 | Zombie | Delete without guilt |

```bash
# Run lifecycle audit on any L0 project
make asp-l0-audit
# Or from ASP repo:
bash .asp/scripts/l0-audit.sh /path/to/your-l0-project
```

---

## Promotion Gate Triggers (Mandatory L0 → L1 Evaluation)

These events **force** an L0 → L1 evaluation regardless of your preference:

| Trigger | Required action |
|---------|----------------|
| First external user (someone you don't know) | Evaluate upgrade to L1 — production governance required |
| Any real PII or payment data touches the system | Immediate L2+ required |
| Repo age > 60 days AND still in active development | Run audit: Active or Zombie? Upgrade or delete. |
| Going onto any app store / public deployment | L3 minimum required — start ADR + SPEC now |

`make asp-l0-audit` checks trigger 1 (external committer) and trigger 3 (60-day clock) automatically.

---

## Anti-patterns

- **"We'll just stay in L0 forever"** — L0 is time-boxed. If you need > 5 working days, escalate to L1. The graduation checklist ensures spike findings are captured before going further.
- **Starting without a spike question** — define *what you're validating* before writing any code. If you can't phrase the question, you're not ready to spike.
- **Committing spike code to main** — always use `spike/*` branches. `session-audit.sh` will BLOCKER you if you try to skip this.
- **Treating L0 as a shortcut to skip ADRs permanently** — L0 is an *explicit temporary exemption*, not a governance bypass. Spike code that goes to production needs all the governance applied retroactively.

---

## Reference

| Resource | Purpose |
|----------|---------|
| `.asp/levels/level-0.yaml` | Machine-readable L0 config, graduation checklist, exit triggers |
| `.asp/profiles/spike_mode.md` | Profile loaded automatically when `level: 0` is set |
| `.asp/templates/example-profile-spike.yaml` | Copy-paste `.ai_profile` template for spike projects |
| `make asp-level` | Check current maturity level and graduation status |
| `make asp-l0-audit` | Run L0 lifecycle audit (Active vs Zombie + Promotion Gate checks) |
| `docs/where-to-start.md` | General ASP onboarding guide |
