#!/usr/bin/env python3
"""ASP telemetry weekly report generator.
Usage: python3 report.py [--days 7]
"""
import json
import sys
from pathlib import Path
from collections import defaultdict
from datetime import datetime, timezone, timedelta

PROJECT_ROOT = Path(__file__).parent.parent.parent
TELEMETRY_FILE = PROJECT_ROOT / ".asp-telemetry.jsonl"


def main():
    days = 7
    for i, arg in enumerate(sys.argv):
        if arg == "--days" and i + 1 < len(sys.argv):
            try:
                days = int(sys.argv[i + 1])
            except ValueError:
                print(f"⚠️  --days 需為整數，收到 '{sys.argv[i + 1]}'，改用預設 {days}", file=sys.stderr)

    if not TELEMETRY_FILE.exists():
        print("No telemetry data found. Run collect.py first.")
        return

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    events = []
    for line in TELEMETRY_FILE.read_text(encoding="utf-8").splitlines():
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
