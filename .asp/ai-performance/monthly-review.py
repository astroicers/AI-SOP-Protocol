#!/usr/bin/env python3
"""Monthly AI Performance Review — reads auto-merged-prs.jsonl, computes trust score.

Usage:
    python3 ~/.claude/asp/ai-performance/monthly-review.py
    python3 ~/.claude/asp/ai-performance/monthly-review.py --update-tier
    make asp-performance-review
"""
import json
import sys
import argparse
from pathlib import Path
from datetime import datetime, timedelta, timezone

BASE_DIR = Path.home() / ".claude" / "asp" / "ai-performance"
LOG = BASE_DIR / "auto-merged-prs.jsonl"
TIER_FILE = BASE_DIR / "trust-tier.yaml"


def load_entries():
    if not LOG.exists():
        return []
    lines = LOG.read_text().splitlines()
    return [json.loads(l) for l in lines if l.strip()]


def compute_score(entries):
    evaluated = [e for e in entries if e.get("outcome_t30") is not None]
    reverted = sum(1 for e in evaluated if e["outcome_t30"].get("reverted"))
    incidents = sum(1 for e in evaluated if e["outcome_t30"].get("production_incident"))
    survived = len(evaluated) - reverted - incidents

    score = 100 + survived - (reverted * 5) - (incidents * 20)
    return max(0, min(100, score)), evaluated, survived, reverted, incidents


def score_to_tier(score):
    if score >= 95:
        return "TIER_3_FULL_AUTO"
    elif score >= 80:
        return "TIER_2_STANDARD"
    elif score >= 60:
        return "TIER_1_REVIEW"
    return "TIER_0_REVOKED"


def main():
    parser = argparse.ArgumentParser(description="ASP AI Performance Monthly Review")
    parser.add_argument("--update-tier", action="store_true",
                        help="Update trust-tier.yaml with computed score")
    args = parser.parse_args()

    entries = load_entries()

    if not entries:
        print("No auto-merge log yet (auto-merged-prs.jsonl empty or missing).")
        print(f"Create entries at: {LOG}")
        return

    score, evaluated, survived, reverted, incidents = compute_score(entries)
    tier = score_to_tier(score)

    print(f"=== AI Performance Review: {datetime.now(timezone.utc).date()} ===")
    print(f"Total auto-merged PRs: {len(entries)}")
    print(f"Evaluated (outcome_t30 filled): {len(evaluated)}")
    print(f"  Survived 30 days: {survived}")
    print(f"  Reverted: {reverted}")
    print(f"  Production incidents: {incidents}")
    print(f"")
    print(f"Trust score: {score}/100")
    print(f"Current tier: {tier}")

    # Group failures by subsystem
    failed = [e for e in evaluated
              if e["outcome_t30"].get("reverted") or e["outcome_t30"].get("production_incident")]
    if failed:
        print(f"\nTop failure sources:")
        subsystems = {}
        for e in failed:
            s = e.get("subsystem", "unknown")
            subsystems[s] = subsystems.get(s, 0) + 1
        for s, count in sorted(subsystems.items(), key=lambda x: -x[1])[:3]:
            print(f"  {count}x  {s}")

    pending_outcome = [e for e in entries if e.get("outcome_t30") is None]
    if pending_outcome:
        print(f"\n{len(pending_outcome)} PR(s) awaiting T+30 outcome fill-in.")

    if args.update_tier:
        _update_tier_file(score, tier)


def _update_tier_file(score, tier):
    if not TIER_FILE.exists():
        print(f"WARNING: {TIER_FILE} not found, cannot update")
        return
    content = TIER_FILE.read_text()
    import re
    content = re.sub(r'(trust_tier:\s*\n\s*current:\s*)\S+', f'\\1{tier}', content)
    content = re.sub(r'(score:\s*)\d+', f'\\1{score}', content)
    today = datetime.now(timezone.utc).date().isoformat()
    content = re.sub(r'(last_updated:\s*")[^"]*"', f'\\1{today}"', content)
    TIER_FILE.write_text(content)
    print(f"\nUpdated {TIER_FILE}: score={score}, tier={tier}")


if __name__ == "__main__":
    main()
