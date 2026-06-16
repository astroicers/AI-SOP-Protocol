#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"
# test_doc_numbering.sh — TDD tests for adr-new / spec-new / postmortem-new
#
# Bug: original logic uses (count + 1) which collides when there's a gap in
# numbering (e.g. existing 001 + 003 → count=2 → next=003 → overwrites!).
#
# Correct behavior: pick (max existing num + 1), independent of count.
#
# Run: bash tests/test_doc_numbering.sh

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mk_test_dir


setup_project() {
  rm -rf "${TEST_DIR:?}"/*
  mkdir -p "$TEST_DIR/.asp/templates"
  cp "$ASP_ROOT/.asp/Makefile.inc" "$TEST_DIR/.asp/Makefile.inc"

  # Copy real templates if they exist, otherwise stub
  for tmpl in ADR_Template.md SPEC_Template.md Postmortem_Template.md; do
    if [ -f "$ASP_ROOT/.asp/templates/$tmpl" ]; then
      cp "$ASP_ROOT/.asp/templates/$tmpl" "$TEST_DIR/.asp/templates/"
    else
      # Postmortem template doesn't exist by default; stub it
      cat > "$TEST_DIR/.asp/templates/$tmpl" <<EOF
# ${tmpl%_Template.md}-000：功能名稱
| **規格 ID** | ${tmpl%_Template.md}-000 |
EOF
    fi
  done

  cat > "$TEST_DIR/Makefile" <<'MK'
include .asp/Makefile.inc
MK
}

assert() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local actual="$2"; local expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ -f "$path" ]; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc"
    echo "     missing file: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_overwritten() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"; local sentinel="$3"
  if grep -q "$sentinel" "$path" 2>/dev/null; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc (file was overwritten — sentinel string lost)"
    FAIL=$((FAIL + 1))
  fi
}

# ── Test 1: spec-new with gap (001 + 003) → next must be 004, not 003 ──
echo "── Test 1: spec-new with numbering gap (regression for SPEC-004 collision) ──"
setup_project
mkdir -p "$TEST_DIR/docs/specs"
echo "# SPEC-001 sentinel-existing-001" > "$TEST_DIR/docs/specs/SPEC-001-existing.md"
echo "# SPEC-003 sentinel-existing-003" > "$TEST_DIR/docs/specs/SPEC-003-existing.md"

cd "$TEST_DIR"
make spec-new TITLE="new feature" >/dev/null 2>&1 || true
cd "$ASP_ROOT"

assert_file_not_overwritten "SPEC-001 not overwritten" \
  "$TEST_DIR/docs/specs/SPEC-001-existing.md" "sentinel-existing-001"
assert_file_not_overwritten "SPEC-003 not overwritten" \
  "$TEST_DIR/docs/specs/SPEC-003-existing.md" "sentinel-existing-003"
assert_file_exists "SPEC-004 created (next num after max)" \
  "$TEST_DIR/docs/specs/SPEC-004-new-feature.md"

# ── Test 2: adr-new with gap ──
echo "── Test 2: adr-new with numbering gap ──"
setup_project
mkdir -p "$TEST_DIR/docs/adr"
echo "# ADR-001 sentinel-adr-001" > "$TEST_DIR/docs/adr/ADR-001-old.md"
echo "# ADR-005 sentinel-adr-005" > "$TEST_DIR/docs/adr/ADR-005-old.md"

cd "$TEST_DIR"
make adr-new TITLE="new decision" >/dev/null 2>&1 || true
cd "$ASP_ROOT"

assert_file_not_overwritten "ADR-001 not overwritten" \
  "$TEST_DIR/docs/adr/ADR-001-old.md" "sentinel-adr-001"
assert_file_not_overwritten "ADR-005 not overwritten" \
  "$TEST_DIR/docs/adr/ADR-005-old.md" "sentinel-adr-005"
assert_file_exists "ADR-006 created (next num after max=5)" \
  "$TEST_DIR/docs/adr/ADR-006-new-decision.md"

# ── Test 3: postmortem-new with gap ──
echo "── Test 3: postmortem-new with numbering gap ──"
setup_project
mkdir -p "$TEST_DIR/docs/postmortems"
echo "# PM-002 sentinel-pm-002" > "$TEST_DIR/docs/postmortems/PM-002-incident.md"

cd "$TEST_DIR"
make postmortem-new TITLE="outage analysis" >/dev/null 2>&1 || true
cd "$ASP_ROOT"

assert_file_not_overwritten "PM-002 not overwritten" \
  "$TEST_DIR/docs/postmortems/PM-002-incident.md" "sentinel-pm-002"
assert_file_exists "PM-003 created (next num after max=2)" \
  "$TEST_DIR/docs/postmortems/PM-003-outage-analysis.md"

# ── Test 4: empty directory edge case ──
echo "── Test 4: empty directory → first num is 001 ──"
setup_project
mkdir -p "$TEST_DIR/docs/specs"
cd "$TEST_DIR"
make spec-new TITLE="first spec" >/dev/null 2>&1 || true
cd "$ASP_ROOT"
assert_file_exists "SPEC-001 created from empty dir" \
  "$TEST_DIR/docs/specs/SPEC-001-first-spec.md"

# ── Test 5: contiguous numbering (no gap) still works ──
echo "── Test 5: contiguous numbering (no gap) ──"
setup_project
mkdir -p "$TEST_DIR/docs/specs"
echo "# SPEC-001 c1" > "$TEST_DIR/docs/specs/SPEC-001-a.md"
echo "# SPEC-002 c2" > "$TEST_DIR/docs/specs/SPEC-002-b.md"
cd "$TEST_DIR"
make spec-new TITLE="third" >/dev/null 2>&1 || true
cd "$ASP_ROOT"
assert_file_exists "SPEC-003 created (contiguous)" \
  "$TEST_DIR/docs/specs/SPEC-003-third.md"

# ── Test 6: triple-digit boundary ──
echo "── Test 6: 099 → 100 boundary ──"
setup_project
mkdir -p "$TEST_DIR/docs/specs"
echo "# SPEC-099" > "$TEST_DIR/docs/specs/SPEC-099-x.md"
cd "$TEST_DIR"
make spec-new TITLE="hundred" >/dev/null 2>&1 || true
cd "$ASP_ROOT"
assert_file_exists "SPEC-100 created (3-digit boundary)" \
  "$TEST_DIR/docs/specs/SPEC-100-hundred.md"

# ── Summary ──
echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ $FAIL -eq 0 ]
