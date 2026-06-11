#!/usr/bin/env bash
# test_converge_crypto_gate.sh — ADR-010 Pattern 3-C0: converge.sh crypto gate.
#
# converge must, BEFORE rebase/merge, detect whether a task's diff touches a
# crypto/secrets path. If so it MUST NOT merge that task — it emits a
# crypto_path_touched escalation, skips the task (continue), and the run exits 9
# (crypto_hitl_pending). analyze-only: it never modifies bytes. Other (non-crypto)
# tasks in the same run still merge (partial success). git-diff failure is
# fail-closed (treated as "can't confirm → block").
# Run: bash tests/test_converge_crypto_gate.sh

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-c0-XXXXXX)
PASS=0; FAIL=0; TOTAL=0
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
DISPATCH="$ASP_ROOT/.asp/scripts/multi-agent/dispatch.sh"
CONVERGE="$ASP_ROOT/.asp/scripts/multi-agent/converge.sh"

aeq() { TOTAL=$((TOTAL+1)); if [ "$2" = "$3" ]; then echo "  ✅ $1"; PASS=$((PASS+1)); else echo "  ❌ $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi; }
acontains() { TOTAL=$((TOTAL+1)); if printf '%s' "$2" | grep -qF "$3"; then echo "  ✅ $1"; PASS=$((PASS+1)); else echo "  ❌ $1 (missing '$3')"; FAIL=$((FAIL+1)); fi; }

run_converge() {
  local ef="$TEST_DIR/.stderr.$$"; set +e
  bash "$CONVERGE" "$@" 2>"$ef"; CONVERGE_RC=$?; set -e
  rm -f "$ef"
}

setup_repo() {
  rm -rf "${TEST_DIR:?}"/*
  unset ASP_AUDIT_ROOT 2>/dev/null || true
  git init -q -b main "$TEST_DIR/main-repo"
  cd "$TEST_DIR/main-repo"
  git config user.email "t@test"; git config user.name "t"
  mkdir -p src/api src/crypto
  echo "package api" > src/api/file.go
  echo "package crypto" > src/crypto/keys.go
  echo "root" > README.md
  git add -A; git commit -q -m init
  cd "$ASP_ROOT"
}

write_manifest() {
  cat > "$1" <<EOF
task_id: $2
agent: worker-a
agent_role: impl
scope:
  allow: [$3]
  forbid: []
worktree_branch: feat/c0-$(echo "$2" | tr '[:upper:]' '[:lower:]')
EOF
}

worker_commit() {  # $1=worktree $2=relpath $3=content $4=msg
  cd "$1"; mkdir -p "$(dirname "$2")"; printf '%s\n' "$3" > "$2"; git add "$2"; git commit -q -m "$4"; cd "$ASP_ROOT"
}

merged_on_main() {  # $1=grep needle in main log → echo count
  ( cd "$TEST_DIR/main-repo" && git log main --oneline | grep -c "$1" || true )
}

# ── T1: a task touching src/crypto/ → skipped, escalated, exit 9 ──
echo ""
echo "T1: crypto-path task → NOT merged, crypto_path_touched escalation, exit 9"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/crypto/"
cd "$TEST_DIR/main-repo"; ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$DISPATCH" --manifests "$TEST_DIR/manifests" >/dev/null; cd "$ASP_ROOT"
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-001" "src/crypto/keys.go" "package crypto // rotated" "touch crypto"
cd "$TEST_DIR/main-repo"; ASP_HITL_MODE=mock ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_converge --task TASK-001; cd "$ASP_ROOT"
aeq "exit 9 (crypto_hitl_pending)" "$CONVERGE_RC" "9"
aeq "crypto task NOT merged onto main" "$(merged_on_main 'touch crypto')" "0"
ESC=$(cat "$TEST_DIR/main-repo/.asp-escalation.ndjson" 2>/dev/null || echo "")
acontains "escalation reason=crypto_path_touched" "$ESC" "crypto_path_touched"

# ── T2: a non-crypto task → merges normally, exit 0 ──
echo ""
echo "T2: non-crypto task → merges, exit 0 (gate does not add everyday friction)"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-002.yaml" "TASK-002" "src/api/"
cd "$TEST_DIR/main-repo"; ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$DISPATCH" --manifests "$TEST_DIR/manifests" >/dev/null; cd "$ASP_ROOT"
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-002" "src/api/file.go" "package api // v2" "api change"
cd "$TEST_DIR/main-repo"; ASP_HITL_MODE=mock ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_converge --task TASK-002; cd "$ASP_ROOT"
aeq "exit 0 on non-crypto task" "$CONVERGE_RC" "0"
aeq "non-crypto task merged onto main" "$(merged_on_main 'api change')" "1"

# ── T3: root-level crypto filename (aes.go) is detected (regex boundary fix) ──
echo ""
echo "T3: root-level crypto file (aes.go) detected → exit 9"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-003.yaml" "TASK-003" "."
cd "$TEST_DIR/main-repo"; ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$DISPATCH" --manifests "$TEST_DIR/manifests" >/dev/null; cd "$ASP_ROOT"
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-003" "aes.go" "package main // aes" "add aes"
cd "$TEST_DIR/main-repo"; ASP_HITL_MODE=mock ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_converge --task TASK-003; cd "$ASP_ROOT"
aeq "root-level aes.go → exit 9" "$CONVERGE_RC" "9"

# ── T4: mixed run — non-crypto merges, crypto skipped, exit 9 ──
echo ""
echo "T4: mixed — non-crypto merges, crypto skipped (partial success), exit 9"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-010.yaml" "TASK-010" "src/api/"
write_manifest "$TEST_DIR/manifests/TASK-011.yaml" "TASK-011" "src/crypto/"
cd "$TEST_DIR/main-repo"; ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$DISPATCH" --manifests "$TEST_DIR/manifests" >/dev/null; cd "$ASP_ROOT"
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-010" "src/api/file.go" "package api // ok" "safe api"
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-011" "src/crypto/keys.go" "package crypto // danger" "touch crypto2"
cd "$TEST_DIR/main-repo"; ASP_HITL_MODE=mock ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_converge --task TASK-010 --task TASK-011; cd "$ASP_ROOT"
aeq "mixed run → exit 9" "$CONVERGE_RC" "9"
aeq "non-crypto TASK-010 merged" "$(merged_on_main 'safe api')" "1"
aeq "crypto TASK-011 NOT merged" "$(merged_on_main 'touch crypto2')" "0"

# ── T5: fail-closed — if the gate can't compute the diff, BLOCK (no fail-open) ──
echo ""
echo "T5: base unreachable → crypto gate fail-closed (not merged, exit 9)"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-020.yaml" "TASK-020" "src/api/"
cd "$TEST_DIR/main-repo"; ASP_AUDIT_ROOT="$TEST_DIR/main-repo" bash "$DISPATCH" --manifests "$TEST_DIR/manifests" >/dev/null; cd "$ASP_ROOT"
worker_commit "$TEST_DIR/main-repo/.asp-worktrees/task-020" "src/api/file.go" "package api // x" "api x"
# --base points at a nonexistent ref → `git diff <missing>...<task>` fails → must fail-closed
cd "$TEST_DIR/main-repo"; ASP_HITL_MODE=mock ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_converge --base no-such-base --task TASK-020; cd "$ASP_ROOT"
aeq "unreachable base → exit 9 (fail-closed, not fail-open)" "$CONVERGE_RC" "9"
aeq "task NOT merged when gate can't verify" "$(merged_on_main 'api x')" "0"
ESC=$(cat "$TEST_DIR/main-repo/.asp-escalation.ndjson" 2>/dev/null || echo "")
acontains "escalation reason=crypto_gate_diff_failed" "$ESC" "crypto_gate_diff_failed"

# ── Summary ──
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
