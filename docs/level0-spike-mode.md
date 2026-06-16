# Spike Mode (loose level) — User Guide

> **v5 terminology note (ADR-014):** What v4 called *L0 Spike* + *L1 Starter* is now the single **`loose`** level. This guide documents the **spike exemption** available at `loose`. Canonical profile: [`.asp/profiles/loose_mode.md`](../.asp/profiles/loose_mode.md) → "探索豁免（Spike Exemption）" section. (Filename kept as-is to avoid breaking inbound links.)

> **Use when:** Technical assumption validation, PoC, CYBERSEC demo prep, new framework/API feasibility.
> **Time-box:** ≤5 working days. If you need longer, conclude the spike and continue as normal `loose` development — or upgrade to `standard` once you need pipeline gates.

---

## Quick Start

1. Copy `.asp/templates/example-profile-loose.yaml` → `.ai_profile` in project root
2. Work on a `spike/*` (or `poc/*` / `experiment/*`) branch — `loose` blocks `[spike]` commits to main
3. Write `docs/spike-conclusion.md` before concluding the spike

```bash
cp .asp/templates/example-profile-loose.yaml .ai_profile
git checkout -b spike/my-spike-name
```

---

## What the spike exemption skips

| Skipped | Why | Must catch up before production / `standard` |
|---------|-----|----------------------------------------------|
| ADR requirement | Exploration decisions change constantly | Yes — create ADR for any architectural choices kept |
| SPEC requirement | Spike questions evolve too fast for specs | Yes — write SPEC for anything being kept |
| TDD / G1-G6 gates | Too much friction for exploration | Yes — write tests before code goes to production |
| CHANGELOG entries | Spike branches are throwaway | Yes — summarize outcome in spike-conclusion.md |
| Pipeline gates | No CI/CD overhead during exploration | Yes — re-run all gates after upgrading to `standard` |

---

## What the spike exemption NEVER skips (Iron Rules always apply)

| Rule | Behavior during a spike |
|------|-------------------------|
| `git push` → list changes first | Always — destructive op protection is non-negotiable |
| No API keys / credentials in output | Always — credential scan runs regardless of level |
| External fact verification (weak form) | Mark source; full verify required before going to production |
| Destructive op confirmation (HITL strict) | Always — spike-exemption activity **forces** `hitl: strict` regardless of profile setting (ADR-014 D1) |

---

## Spike Conclusion Checklist

Before merging your spike branch to main, confirm all items:

- [ ] `docs/spike-conclusion.md` written — what did you learn? go or no-go?
- [ ] Architecture choices documented in ADR(s)
- [ ] SPEC written for anything being kept in production
- [ ] Tests written for code being kept
- [ ] All spike commits marked with `[spike]` prefix
- [ ] Code moved from `spike/*` branch via PR (not direct merge); main has no `[spike]` commits
- [ ] `.ai_profile` `level:` stays `loose` for continued small-project work — or set `standard` once you need pipeline gates

```bash
# Check current level and graduation status before upgrading
make asp-level-check
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
Outcome: either demo harness works (→ continue dev, add ADR on attack scenario design) or pivot.

### C — MCP server feasibility assessment (3-day spike)

```yaml
spike_question: "Is fastmcp compatible with our hook architecture?"
spike_deadline: "2026-05-14"
```

ASP interventions: ~2.
Outcome: go → conclude spike, create ADR, write SPEC (upgrade to `standard` if gates needed); no-go → document in spike-conclusion.md.

---

## Loose-Spike Lifecycle: Active vs Zombie Diagnosis

Run `make asp-l0-audit` monthly on loose-level spike repos. Ask three questions:

1. **Active?** — Any commits in the last 30 days?
2. **Understandable?** — Can you change something in <30 min?
3. **Worth keeping?** — Would losing it cause pain?

| Answer | Diagnosis | Action |
|--------|-----------|--------|
| All yes | Active spike | Continue as-is |
| No to Q1 only | Zombie | Archive or delete |
| No to Q2 | Zombie trap | Conclude the spike or refactor before it rots further |
| No to Q3 | Zombie | Delete without guilt |

```bash
# Run lifecycle audit on any loose-level spike project
make asp-l0-audit
# Or from ASP repo:
bash .asp/scripts/l0-audit.sh /path/to/your-spike-project
```

---

## Promotion Gate Triggers (Mandatory Upgrade Evaluation)

These events **force** an upgrade evaluation regardless of your preference:

| Trigger | Required action |
|---------|----------------|
| First external user (someone you don't know) | Evaluate upgrade to `standard` — production governance required |
| Any real PII or payment data touches the system | Immediate `standard`+ required |
| Repo age > 60 days AND still in active development | Run audit: Active or Zombie? Upgrade or delete. |
| Going onto any app store / public deployment | `standard` minimum required — start ADR + SPEC now |

`make asp-l0-audit` checks trigger 1 (external committer) and trigger 3 (60-day clock) automatically.

---

## Anti-patterns

- **"We'll just stay in spike mode forever"** — the spike exemption is time-boxed. If you need > 5 working days, conclude the spike. The conclusion checklist ensures spike findings are captured before going further.
- **Starting without a spike question** — define *what you're validating* before writing any code. If you can't phrase the question, you're not ready to spike.
- **Committing spike code to main** — always use `spike/*` branches. `session-audit.sh` will BLOCKER you if you try to skip this.
- **Treating the spike exemption as a way to skip ADRs permanently** — it is an *explicit temporary exemption*, not a governance bypass. Spike code that goes to production needs all the governance applied retroactively.

---

## Reference

| Resource | Purpose |
|----------|---------|
| `.asp/levels/loose.yaml` | Machine-readable `loose` config, graduation checklist, exit triggers |
| `.asp/profiles/loose_mode.md` | Profile auto-loaded when `level: loose` is set (contains the "探索豁免" section) |
| `.asp/templates/example-profile-loose.yaml` | Copy-paste `.ai_profile` template for loose / spike projects |
| `make asp-level-check` | Check current maturity level and graduation status |
| `make asp-l0-audit` | Run spike lifecycle audit (Active vs Zombie + Promotion Gate checks) |
| `docs/where-to-start.md` | General ASP onboarding guide |
