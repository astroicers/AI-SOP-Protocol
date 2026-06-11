"""Unit tests for .asp/scripts/rag/build_index.py.

Covers the pure helper functions (file_hash, chunk_text, detect_adr_status,
collect_files, load_manifest, save_manifest). Skips build_index() itself
because it requires chromadb + sentence-transformers, which are heavy ML
dependencies and gated by an ImportError fallback in the source.
"""
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / ".asp" / "scripts" / "rag" / "build_index.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("build_index", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["build_index"] = module
    spec.loader.exec_module(module)
    return module


bi = _load_module()


# ─── file_hash: deterministic SHA-256 of file bytes ─────────────────────

def test_file_hash_matches_manual_sha256(tmp_path):
    f = tmp_path / "sample.md"
    f.write_text("# Hello\n")
    expected = hashlib.sha256(b"# Hello\n").hexdigest()
    assert bi.file_hash(str(f)) == expected


def test_file_hash_changes_when_content_changes(tmp_path):
    f = tmp_path / "sample.md"
    f.write_text("v1")
    h1 = bi.file_hash(str(f))
    f.write_text("v2")
    h2 = bi.file_hash(str(f))
    assert h1 != h2


def test_file_hash_handles_binary_safely(tmp_path):
    f = tmp_path / "blob.bin"
    f.write_bytes(b"\x00\xff\x10\x20")
    # Should not raise even on bytes that aren't valid UTF-8
    assert len(bi.file_hash(str(f))) == 64


# ─── chunk_text: word-based windowing with overlap ──────────────────────

def test_chunk_text_short_input_single_chunk():
    chunks = bi.chunk_text("one two three", chunk_size=500, overlap=100)
    assert chunks == ["one two three"]


def test_chunk_text_respects_chunk_size():
    text = " ".join(str(i) for i in range(1000))  # 1000 words
    chunks = bi.chunk_text(text, chunk_size=500, overlap=100)
    # Each chunk must contain at most chunk_size words
    for c in chunks:
        assert len(c.split()) <= 500


def test_chunk_text_overlap_repeats_words():
    text = " ".join(f"w{i}" for i in range(150))
    chunks = bi.chunk_text(text, chunk_size=100, overlap=20)
    # First chunk ends at word 99 (w0..w99); next chunk starts at 100-20=80
    # so chunks[1] must start with w80
    assert chunks[0].split()[0] == "w0"
    assert chunks[1].split()[0] == "w80"


def test_chunk_text_empty_input():
    assert bi.chunk_text("", chunk_size=100, overlap=10) == []


# ─── detect_adr_status: extract status from markdown ────────────────────

def test_detect_adr_status_returns_none_for_non_adr(tmp_path):
    f = tmp_path / "random.md"
    f.write_text("# 狀態 `Active`\n")
    # File is not in /adr/ path nor named ADR-*, so should return None
    assert bi.detect_adr_status(str(f)) is None


def test_detect_adr_status_finds_status_in_adr_path(tmp_path):
    adr_dir = tmp_path / "adr"
    adr_dir.mkdir()
    f = adr_dir / "decision.md"
    f.write_text("# Title\n\n| 狀態 | `Accepted` |\n")
    assert bi.detect_adr_status(str(f)) == "Accepted"


def test_detect_adr_status_finds_status_in_adr_filename(tmp_path):
    f = tmp_path / "ADR-007-something.md"
    f.write_text("狀態 `Draft`\n")
    assert bi.detect_adr_status(str(f)) == "Draft"


def test_detect_adr_status_handles_missing_status_field(tmp_path):
    f = tmp_path / "ADR-008.md"
    f.write_text("# 沒有狀態欄位的 ADR\n\n內容…\n")
    assert bi.detect_adr_status(str(f)) is None


# ─── collect_files: walk source dirs and hash ───────────────────────────

def test_collect_files_picks_up_md_recursively(tmp_path):
    (tmp_path / "a.md").write_text("a")
    sub = tmp_path / "sub"
    sub.mkdir()
    (sub / "b.md").write_text("b")
    (tmp_path / "c.txt").write_text("c")  # not .md, must be skipped

    result = bi.collect_files([str(tmp_path)])
    assert len(result) == 2
    assert all(p.endswith(".md") for p in result)
    assert all(len(h) == 64 for h in result.values())


def test_collect_files_empty_source_returns_empty(tmp_path):
    assert bi.collect_files([str(tmp_path)]) == {}


# ─── load_manifest / save_manifest: round-trip ──────────────────────────

def test_save_then_load_manifest_roundtrip(tmp_path):
    output_dir = tmp_path / "index"
    payload = {"a.md": "abc123", "b.md": "def456"}
    bi.save_manifest(str(output_dir), payload)
    assert bi.load_manifest(str(output_dir)) == payload


def test_load_manifest_missing_returns_empty(tmp_path):
    # No file written → must return empty dict, not raise
    assert bi.load_manifest(str(tmp_path)) == {}


def test_save_manifest_creates_output_dir_if_missing(tmp_path):
    target = tmp_path / "newly-created"
    assert not target.exists()
    bi.save_manifest(str(target), {"x.md": "h"})
    assert target.exists()
    assert (target / "index_manifest.json").exists()
