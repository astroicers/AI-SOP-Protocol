# auto-merged-prs.jsonl Schema

Each auto-merge appends one line. After 30 days a cron job (or manual run) fills in `outcome_t30`.

## Entry format

```jsonc
{
  "ts": "2026-05-09T10:30:00+08:00",   // ISO 8601
  "pr_number": 142,
  "repo": "Merak",                       // short repo name
  "subsystem": "trivial-bug-fix",        // subsystem A/B/C
  "files_changed": 3,
  "lines_changed": 12,
  "ai_classification": "trivial",        // trivial | standard | high_stakes
  "outcome_t30": null                    // filled in 30 days after merge
}
```

## outcome_t30 (filled at T+30)

```jsonc
{
  "reverted": false,
  "revert_pr": null,            // PR number if reverted
  "follow_up_bug_filed": false,
  "production_incident": false,
  "trust_score_delta": 1        // +1 survived, -5 revert, -20 incident
}
```

## Trust score rules

| Event | Score delta |
|-------|-------------|
| PR survived 30 days | +1 |
| PR reverted (non-incident) | -5 |
| PR caused production incident | -20 |

Starting score: 100. Clamped to [0, 100].

## File location

`~/.claude/asp/ai-performance/auto-merged-prs.jsonl` — append-only JSONL, one entry per line.

## Tier boundaries (see trust-tier.yaml)

| Score | Tier |
|-------|------|
| ≥ 95 | TIER_3_FULL_AUTO |
| 80–94 | TIER_2_STANDARD |
| 60–79 | TIER_1_REVIEW |
| < 60 | TIER_0_REVOKED |
