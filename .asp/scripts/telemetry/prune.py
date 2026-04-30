#!/usr/bin/env python3
"""ASP telemetry pruner. Archives events older than --days to .asp-telemetry-archive/
Usage: python3 prune.py [--days 90]
"""
import json
import sys
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
    for line in TELEMETRY_FILE.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            e = json.loads(line)
            if datetime.fromisoformat(e["ts"]) > cutoff:
                keep.append(line)
            else:
                archive.append((e["ts"][:7], line))
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
        with open(archive_file, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

    content = "\n".join(keep) + "\n" if keep else ""
    TELEMETRY_FILE.write_text(content, encoding="utf-8")
    print(f"Pruned {len(archive)} events, kept {len(keep)} events.")


if __name__ == "__main__":
    main()
