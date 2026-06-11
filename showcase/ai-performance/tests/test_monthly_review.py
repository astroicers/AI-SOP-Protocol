"""Unit tests for .asp/ai-performance/monthly-review.py.

Tests the trust-score computation and tier-mapping logic, which is the
critical path of the AI Performance Review system. The score determines
whether AI gets TIER_3_FULL_AUTO (auto-merge without label) or
TIER_0_REVOKED (all automation disabled), so getting the math wrong
silently degrades the safety boundary.
"""
import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / ".asp" / "ai-performance" / "monthly-review.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("monthly_review", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["monthly_review"] = module
    spec.loader.exec_module(module)
    return module


mr = _load_module()


# ─── score_to_tier: tier-boundary mapping ───────────────────────────────

@pytest.mark.parametrize("score,expected_tier", [
    (100, "TIER_3_FULL_AUTO"),
    (95, "TIER_3_FULL_AUTO"),
    (94, "TIER_2_STANDARD"),
    (80, "TIER_2_STANDARD"),
    (79, "TIER_1_REVIEW"),
    (60, "TIER_1_REVIEW"),
    (59, "TIER_0_REVOKED"),
    (0, "TIER_0_REVOKED"),
])
def test_score_to_tier_boundaries(score, expected_tier):
    assert mr.score_to_tier(score) == expected_tier


# ─── compute_score: pure scoring logic ──────────────────────────────────

def _entry(reverted=False, incident=False, evaluated=True):
    """Build a single auto-merged-prs.jsonl-shaped entry."""
    if not evaluated:
        return {"outcome_t30": None}
    return {
        "outcome_t30": {
            "reverted": reverted,
            "production_incident": incident,
        }
    }


def test_compute_score_empty_returns_max():
    score, evaluated, survived, reverted, incidents = mr.compute_score([])
    assert score == 100
    assert evaluated == [] and survived == reverted == incidents == 0


def test_compute_score_unevaluated_entries_ignored():
    entries = [_entry(evaluated=False) for _ in range(5)]
    score, evaluated, *_ = mr.compute_score(entries)
    # Unevaluated entries don't move the score
    assert score == 100
    assert evaluated == []


def test_compute_score_survived_increments_by_one():
    score, _, survived, _, _ = mr.compute_score([_entry() for _ in range(3)])
    # 100 + 3 survived = 103, clamped to 100
    assert score == 100
    assert survived == 3


def test_compute_score_revert_costs_five():
    score, _, survived, reverted, _ = mr.compute_score([
        _entry(reverted=True),
        _entry(),
        _entry(),
    ])
    # 100 + 2 survived - 1*5 = 97
    assert score == 97
    assert survived == 2 and reverted == 1


def test_compute_score_incident_costs_twenty():
    score, *_, incidents = mr.compute_score([
        _entry(incident=True),
        _entry(),
    ])
    # 100 + 1 survived - 1*20 = 81
    assert score == 81
    assert incidents == 1


def test_compute_score_clamps_at_zero():
    # 6 incidents = -120, must clamp to 0 not go negative
    entries = [_entry(incident=True) for _ in range(6)]
    score, *_ = mr.compute_score(entries)
    assert score == 0


def test_compute_score_clamps_at_hundred():
    # Many survivals shouldn't push score above 100
    entries = [_entry() for _ in range(50)]
    score, *_ = mr.compute_score(entries)
    assert score == 100


def test_compute_score_revert_and_incident_both_count():
    """An entry with both reverted=True AND incident=True is double-penalized.

    This mirrors current source behavior: each flag is counted independently.
    If business logic ever decides incidents should subsume reverts, this
    test will catch the unannounced change.
    """
    entries = [_entry(reverted=True, incident=True)]
    score, _, survived, reverted, incidents = mr.compute_score(entries)
    # survived = 1 - 1 - 1 = -1 (one entry counted in both reverted and incidents)
    # score = 100 + (-1) - 5 - 20 = 74
    assert reverted == 1 and incidents == 1
    assert survived == -1
    assert score == 74


# ─── _update_tier_file: regex-based YAML rewrite ────────────────────────

def test_update_tier_file_rewrites_score_and_tier(tmp_path, monkeypatch):
    tier_yaml = tmp_path / "trust-tier.yaml"
    tier_yaml.write_text(
        'trust_tier:\n'
        '  current: TIER_2_STANDARD\n'
        '  score: 100\n'
        '  last_updated: "2026-01-01"\n'
    )
    monkeypatch.setattr(mr, "TIER_FILE", tier_yaml)

    mr._update_tier_file(75, "TIER_1_REVIEW")

    content = tier_yaml.read_text()
    assert "current: TIER_1_REVIEW" in content
    assert "score: 75" in content
    # last_updated should be a date string in YYYY-MM-DD form
    assert 'last_updated: "20' in content


def test_update_tier_file_missing_target_does_not_crash(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(mr, "TIER_FILE", tmp_path / "does-not-exist.yaml")
    mr._update_tier_file(50, "TIER_0_REVOKED")
    captured = capsys.readouterr()
    assert "WARNING" in captured.out
