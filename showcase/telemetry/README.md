# ASP Telemetry System

JSONL-based append-only telemetry for evidence-based ASP governance improvement.

## Scripts

### collect.py
Appends a `session_start` event to `.asp-telemetry.jsonl`.

```bash
python3 .asp/scripts/telemetry/collect.py          # append event
python3 .asp/scripts/telemetry/collect.py --dry-run # preview event (no write)
```

### report.py
Generates a weekly (or custom window) report from telemetry events.

```bash
python3 .asp/scripts/telemetry/report.py           # last 7 days
python3 .asp/scripts/telemetry/report.py --days 30 # last 30 days
```

### prune.py
Archives events older than 90 days to `.asp-telemetry-archive/{YYYY-MM}.jsonl`.

```bash
python3 .asp/scripts/telemetry/prune.py            # archive events > 90 days old
python3 .asp/scripts/telemetry/prune.py --days 30  # archive events > 30 days old
```

## Event Format

```jsonl
{"ts": "2026-04-29T00:00:00+00:00", "event_type": "session_start", "asp_version": "4.0.0", "data": {"blockers": 0, "warnings": 2, "profile_type": "system"}}
{"ts": "2026-04-29T01:00:00+00:00", "event_type": "gate_pass", "asp_version": "4.0.0", "data": {"gate_id": "G4"}}
```

## Makefile Integration

```makefile
asp-telemetry-collect:
	@python3 .asp/scripts/telemetry/collect.py

asp-telemetry-report:
	@python3 .asp/scripts/telemetry/report.py --days 7

asp-telemetry-prune:
	@python3 .asp/scripts/telemetry/prune.py --days 90
```

## Design Principles

- **Append-only**: `.asp-telemetry.jsonl` is never overwritten, only appended
- **Silent failure**: telemetry errors do not block the main ASP workflow
- **No runtime dependency**: pure stdlib Python, no pip packages required
- **Git-ignored**: `.asp-telemetry.jsonl` should be in `.gitignore` (project-local data)
