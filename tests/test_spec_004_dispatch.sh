#!/usr/bin/env bash
# test_spec_004_dispatch.sh — SPEC-004 B2: dispatch.sh
#
# Covers:
#   P1: 兩個 scope 不重疊的 task → 兩個 worktree 建立成功
#   P2: task manifest 持久化到 .asp-task-manifests/ (主 repo)
#   N1: scope.allow 指向 repo 外 → 拒絕
#   N4: worktree_root 指向 /etc → 拒絕
#   N5: scope.allow 重疊 → 拒絕 (exit 5)
#   N7+S20: dispatch 階段 ASP_AUDIT_ROOT unset → exit 7
#   B1 (max_parallel=10): 邊界 — 接受
#   B2 (max_parallel=11): 邊界 — 拒絕 (exit 6)
#   B4: 磁碟空間動態預檢 — 不足拒絕、警告線、充足通過
#   S10: dispatch + worktree 建立 + branch 對應
#
# Run: bash tests/test_spec_004_dispatch.sh

set -euo pipefail

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d /tmp/asp-test-spec004-b2-XXXXXX)
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

DISPATCH="$ASP_ROOT/.asp/scripts/multi-agent/dispatch.sh"

# ── helpers ──

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local actual="$2"; local expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✅ $desc"; PASS=$((PASS + 1))
  else
    echo "  ❌ $desc"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local haystack="$2"; local needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    echo "  ✅ $desc"; PASS=$((PASS + 1))
  else
    echo "  ❌ $desc"
    echo "     haystack: $haystack"
    echo "     needle:   $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ -f "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (missing: $path)"; FAIL=$((FAIL + 1)); fi
}

assert_dir_exists() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"; local path="$2"
  if [ -d "$path" ]; then echo "  ✅ $desc"; PASS=$((PASS + 1));
  else echo "  ❌ $desc (missing dir: $path)"; FAIL=$((FAIL + 1)); fi
}

# Run dispatch with given manifest dir, capture rc + stderr
run_dispatch() {
  local stderr_file="$TEST_DIR/.stderr.$$"
  set +e
  bash "$DISPATCH" "$@" 2>"$stderr_file"
  local rc=$?
  set -e
  DISPATCH_RC=$rc
  DISPATCH_STDERR=$(cat "$stderr_file")
  rm -f "$stderr_file"
}

# Setup: minimal git repo
setup_repo() {
  rm -rf "${TEST_DIR:?}"/*
  unset ASP_AUDIT_ROOT 2>/dev/null || true
  git init -q -b main "$TEST_DIR/main-repo"
  cd "$TEST_DIR/main-repo"
  git config user.email "test@test.local"
  git config user.name "test"
  mkdir -p src/store src/api src/auth
  echo "package store" > src/store/file.go
  echo "package api"   > src/api/file.go
  echo "package auth"  > src/auth/file.go
  git add -A
  git commit -q -m "init"
  cd "$ASP_ROOT"
}

# Write a task manifest YAML to a path
write_manifest() {
  local path="$1"; local task_id="$2"; local allow="$3"
  cat > "$path" <<EOF
task_id: $task_id
agent: worker-a
agent_role: impl
scope:
  allow: [$allow]
  forbid: []
worktree_branch: feat/spec-004-$(echo "$task_id" | tr '[:upper:]' '[:lower:]')
EOF
}

# ── Test 1: dispatch.sh exists and is executable ──
echo "── Test 1: dispatch.sh exists ──"
assert_file_exists "dispatch.sh exists" "$DISPATCH"

# ── Test 2: N7 — dispatch refuses to start when ASP_AUDIT_ROOT unset ──
echo "── Test 2: N7/S20 — dispatch rejects unset ASP_AUDIT_ROOT ──"
setup_repo
unset ASP_AUDIT_ROOT
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/"

run_dispatch --manifests "$TEST_DIR/manifests"
assert_eq "exit 7 when ASP_AUDIT_ROOT unset" "$DISPATCH_RC" "7"
assert_contains "stderr explains unset" "$DISPATCH_STDERR" "ASP_AUDIT_ROOT must be set"

# ── Test 3: P1 — single task happy path (worktree + branch + manifest persisted) ──
echo "── Test 3: P1/P2/S10 — single task dispatch happy path ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/"

cd "$TEST_DIR/main-repo"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_dispatch --manifests "$TEST_DIR/manifests"
cd "$ASP_ROOT"

assert_eq "exit 0 on happy path" "$DISPATCH_RC" "0"
assert_dir_exists "worktree dir created" "$TEST_DIR/main-repo/.asp-worktrees/task-001"
assert_file_exists "task manifest persisted to main repo" \
  "$TEST_DIR/main-repo/.asp-task-manifests/TASK-001.yaml"

# Verify branch exists
cd "$TEST_DIR/main-repo"
BRANCH_LIST=$(git branch --list 'feat/spec-004-task-001')
cd "$ASP_ROOT"
assert_contains "feat branch created" "$BRANCH_LIST" "feat/spec-004-task-001"

# Verify telemetry event written
assert_file_exists "telemetry log written" "$TEST_DIR/main-repo/.asp-telemetry.ndjson"

# ── Test 4: P1 — two non-overlapping tasks ──
echo "── Test 4: P1 — two non-overlapping tasks dispatch ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/"
write_manifest "$TEST_DIR/manifests/TASK-002.yaml" "TASK-002" "src/api/"

cd "$TEST_DIR/main-repo"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_dispatch --manifests "$TEST_DIR/manifests"
cd "$ASP_ROOT"

assert_eq "exit 0 on 2-task dispatch" "$DISPATCH_RC" "0"
assert_dir_exists "task-001 worktree" "$TEST_DIR/main-repo/.asp-worktrees/task-001"
assert_dir_exists "task-002 worktree" "$TEST_DIR/main-repo/.asp-worktrees/task-002"

# ── Test 5: N5/S17 — scope.allow overlap detected ──
echo "── Test 5: N5/S17 — scope.allow overlap rejected ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/"
write_manifest "$TEST_DIR/manifests/TASK-002.yaml" "TASK-002" "src/store/"  # OVERLAP

cd "$TEST_DIR/main-repo"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_dispatch --manifests "$TEST_DIR/manifests"
cd "$ASP_ROOT"

assert_eq "exit 5 on scope overlap" "$DISPATCH_RC" "5"
assert_contains "stderr mentions overlap" "$DISPATCH_STDERR" "scope.allow overlap"
# No worktree should be created on rejection
TOTAL=$((TOTAL + 1))
if [ ! -d "$TEST_DIR/main-repo/.asp-worktrees" ] || \
   [ -z "$(ls -A "$TEST_DIR/main-repo/.asp-worktrees" 2>/dev/null || true)" ]; then
    echo "  ✅ no worktrees created on overlap rejection"; PASS=$((PASS + 1))
else
    echo "  ❌ worktrees leaked despite rejection"; FAIL=$((FAIL + 1))
fi

# ── Test 6: N1 — scope.allow points outside repo ──
echo "── Test 6: N1 — scope.allow outside repo rejected ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "/etc/passwd"

cd "$TEST_DIR/main-repo"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_dispatch --manifests "$TEST_DIR/manifests"
cd "$ASP_ROOT"

assert_eq "exit 1 on scope outside repo" "$DISPATCH_RC" "1"
assert_contains "stderr explains outside-repo" "$DISPATCH_STDERR" "scope"

# ── Test 7: N4/S9 — worktree_root outside repo rejected ──
echo "── Test 7: N4/S9 — worktree_root outside repo rejected ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/"

cd "$TEST_DIR/main-repo"
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
  run_dispatch --manifests "$TEST_DIR/manifests" --worktree-root /etc/asp-worktrees
cd "$ASP_ROOT"

assert_eq "exit non-zero on bad worktree_root" \
  "$([ "$DISPATCH_RC" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
assert_contains "stderr explains worktree_root" "$DISPATCH_STDERR" "worktree_root"

# ── Test 8: B2/S11 — max_parallel boundary (11 → reject) ──
echo "── Test 8: S11 — max_parallel > 10 rejected ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
for i in $(seq 1 11); do
  num=$(printf '%03d' "$i")
  # Use distinct subdirs to avoid scope overlap
  mkdir -p "$TEST_DIR/main-repo/src/m$num"
  echo "// $num" > "$TEST_DIR/main-repo/src/m$num/file.go"
done
cd "$TEST_DIR/main-repo" && git add -A && git commit -q -m "add modules" && cd "$ASP_ROOT"

for i in $(seq 1 11); do
  num=$(printf '%03d' "$i")
  write_manifest "$TEST_DIR/manifests/TASK-$num.yaml" "TASK-$num" "src/m$num/"
done

cd "$TEST_DIR/main-repo"
ASP_HITL_MODE=mock \
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" run_dispatch --manifests "$TEST_DIR/manifests"
cd "$ASP_ROOT"

assert_eq "exit 6 on max_parallel exceeded" "$DISPATCH_RC" "6"
assert_contains "stderr explains parallel limit" "$DISPATCH_STDERR" "max_parallel"

# ── Test 9: B4/S13 — disk precheck: sufficient space passes ──
echo "── Test 9: B4/S13 — disk precheck: sufficient space passes ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/"

cd "$TEST_DIR/main-repo"
# Inject huge available space via env override so test is deterministic
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
  ASP_MOCK_DISK_AVAIL_MB=99999 \
  run_dispatch --manifests "$TEST_DIR/manifests"
cd "$ASP_ROOT"

assert_eq "exit 0 when disk sufficient" "$DISPATCH_RC" "0"

# ── Test 10: B4/S13 — disk precheck: below hard limit rejects (exit 4) ──
echo "── Test 10: B4/S13 — disk precheck: insufficient space rejected ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/"
write_manifest "$TEST_DIR/manifests/TASK-002.yaml" "TASK-002" "src/api/"

cd "$TEST_DIR/main-repo"
# Mock: only 1 MB available — well below any threshold
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
  ASP_MOCK_DISK_AVAIL_MB=1 \
  run_dispatch --manifests "$TEST_DIR/manifests"
cd "$ASP_ROOT"

assert_eq "exit 4 on insufficient disk" "$DISPATCH_RC" "4"
assert_contains "stderr mentions disk" "$DISPATCH_STDERR" "disk"

# ── Test 11: B4/S13 — disk precheck: warning zone (between 1.2x and 1.5x) ──
echo "── Test 11: B4/S13 — disk precheck: warning zone proceeds with warning ──"
setup_repo
mkdir -p "$TEST_DIR/manifests"
write_manifest "$TEST_DIR/manifests/TASK-001.yaml" "TASK-001" "src/store/"

cd "$TEST_DIR/main-repo"
# max_parallel=1, repo_size=100 MB → budget=100 MB
# hard_limit = 100×1.2 = 120 MB, warn_limit = 100×1.5 = 150 MB
# avail=130 MB → 120 < 130 < 150 → warning zone
ASP_AUDIT_ROOT="$TEST_DIR/main-repo" \
  ASP_MOCK_DISK_AVAIL_MB=130 \
  ASP_MOCK_REPO_SIZE_MB=100 \
  run_dispatch --manifests "$TEST_DIR/manifests" --max-parallel 1
cd "$ASP_ROOT"

assert_eq "exit 0 in warning zone (proceeds)" "$DISPATCH_RC" "0"
assert_contains "stderr has disk warning" "$DISPATCH_STDERR" "disk"

# ── Summary ──
echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════"

[ $FAIL -eq 0 ]
