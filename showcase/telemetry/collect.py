#!/usr/bin/env python3
"""ASP telemetry event collector.
Reads .asp-session-briefing.json and appends structured events to .asp-telemetry.jsonl.
Usage: python3 collect.py [--dry-run]
"""
import json
import sys
import os
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))
TELEMETRY_FILE = PROJECT_ROOT / ".asp-telemetry.jsonl"
BRIEFING_FILE = PROJECT_ROOT / ".asp-session-briefing.json"


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
            briefing = json.loads(BRIEFING_FILE.read_text(encoding="utf-8"))
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
