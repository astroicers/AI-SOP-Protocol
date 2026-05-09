"""Unit tests for .asp/scripts/update-project-description.py.

Focuses on the YAML/profile parsers and safe-getter helper. Skips
generate_description() and main() because they assemble large markdown
blocks whose exact format is fluid and would create churn in tests.
The fragile, security-sensitive bit is the fallback YAML parser, which
runs whenever PyYAML isn't installed (default install.sh path).
"""
import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / ".asp" / "scripts" / "update-project-description.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("update_project_description", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["update_project_description"] = module
    spec.loader.exec_module(module)
    return module


upd = _load_module()


# ─── parse_ai_profile: simple key:value parser ──────────────────────────

def test_parse_ai_profile_basic(tmp_path):
    f = tmp_path / ".ai_profile"
    f.write_text(
        "type: system\n"
        "level: 2\n"
        "mode: auto\n"
    )
    profile = upd.parse_ai_profile(str(f))
    assert profile == {"type": "system", "level": "2", "mode": "auto"}


def test_parse_ai_profile_skips_comments_and_blanks(tmp_path):
    f = tmp_path / ".ai_profile"
    f.write_text(
        "# this is a comment\n"
        "\n"
        "type: content\n"
        "  \n"
        "# another comment\n"
        "name: foo\n"
    )
    profile = upd.parse_ai_profile(str(f))
    assert profile == {"type": "content", "name": "foo"}


def test_parse_ai_profile_missing_file_returns_empty(tmp_path):
    assert upd.parse_ai_profile(str(tmp_path / "absent")) == {}


def test_parse_ai_profile_lines_without_colon_ignored(tmp_path):
    f = tmp_path / ".ai_profile"
    f.write_text(
        "type: system\n"
        "this line has no colon\n"
        "name: bar\n"
    )
    profile = upd.parse_ai_profile(str(f))
    assert profile == {"type": "system", "name": "bar"}


# ─── get_val: safe nested lookup with defaults ──────────────────────────

def test_get_val_returns_value_when_present():
    data = {"stack": {"frontend": "React", "backend": "Go"}}
    assert upd.get_val(data, "stack", "frontend") == "React"


def test_get_val_returns_default_when_section_missing():
    assert upd.get_val({}, "stack", "frontend", default="?") == "?"


def test_get_val_returns_default_when_key_missing():
    data = {"stack": {"frontend": "React"}}
    assert upd.get_val(data, "stack", "backend", default="none") == "none"


def test_get_val_returns_default_when_section_not_dict():
    """If a section is unexpectedly a string (malformed YAML), fall back safely."""
    data = {"stack": "this should have been a dict"}
    assert upd.get_val(data, "stack", "frontend", default="N/A") == "N/A"


def test_get_val_treats_falsy_values_as_default():
    """Behavior under test: empty string / None falls through to default.

    This is current source semantics — if downstream callers want to
    preserve explicit empty strings, they'd need to change get_val.
    """
    data = {"stack": {"frontend": ""}}
    assert upd.get_val(data, "stack", "frontend", default="none") == "none"


# ─── load_yaml_simple fallback parser (when PyYAML absent) ──────────────
# We can't easily force-disable PyYAML in the test process, but we can at
# least exercise the function with a real file and verify round-trip
# accuracy regardless of which path it took.

def test_load_yaml_simple_flat_keys(tmp_path):
    f = tmp_path / "roadmap.yaml"
    f.write_text(
        "project: my-app\n"
        "version: 1.0\n"
    )
    data = upd.load_yaml_simple(str(f))
    assert data["project"] == "my-app"
    # Version may parse as float (PyYAML) or string (fallback) — accept both
    assert str(data["version"]).startswith("1")


def test_load_yaml_simple_one_level_nesting(tmp_path):
    f = tmp_path / "roadmap.yaml"
    f.write_text(
        "stack:\n"
        "  frontend: React\n"
        "  backend: Go\n"
        "project: x\n"
    )
    data = upd.load_yaml_simple(str(f))
    assert data["project"] == "x"
    assert isinstance(data["stack"], dict)
    assert data["stack"]["frontend"] == "React"
    assert data["stack"]["backend"] == "Go"


def test_load_yaml_simple_strips_inline_comments(tmp_path):
    """The fallback parser strips '#' comments from values; PyYAML does too."""
    f = tmp_path / "roadmap.yaml"
    f.write_text(
        "project: foo  # inline comment\n"
    )
    data = upd.load_yaml_simple(str(f))
    assert data["project"] == "foo"


def test_load_yaml_simple_handles_blanks_and_comments(tmp_path):
    f = tmp_path / "roadmap.yaml"
    f.write_text(
        "# top comment\n"
        "\n"
        "project: x\n"
        "\n"
        "# another\n"
        "version: 2\n"
    )
    data = upd.load_yaml_simple(str(f))
    assert data["project"] == "x"
    assert str(data["version"]) == "2"


# ─── extract_srs_summary: first non-frontmatter, non-heading line ───────

def test_extract_srs_summary_finds_first_paragraph(tmp_path):
    srs = tmp_path / "SRS.md"
    srs.write_text(
        "---\n"
        "title: foo\n"
        "---\n"
        "\n"
        "# Heading\n"
        "\n"
        "> a quote\n"
        "\n"
        "<!-- comment -->\n"
        "\n"
        "This is the actual summary line.\n"
    )
    roadmap = {"documents": {"srs": str(srs)}}
    assert upd.extract_srs_summary(roadmap) == "This is the actual summary line."


def test_extract_srs_summary_missing_srs_returns_none(tmp_path):
    roadmap = {"documents": {"srs": str(tmp_path / "absent.md")}}
    assert upd.extract_srs_summary(roadmap) is None


def test_extract_srs_summary_only_headings_returns_none(tmp_path):
    srs = tmp_path / "SRS.md"
    srs.write_text("# A\n## B\n### C\n")
    roadmap = {"documents": {"srs": str(srs)}}
    assert upd.extract_srs_summary(roadmap) is None
