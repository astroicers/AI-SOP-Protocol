#!/usr/bin/env bash
# test_separation.sh — v5 Phase 4 Core/Experimental/Showcase 分離驗收（ADR-017）。
# 靜態斷言：.asp/ 無凍結/showcase 殘留、SKILL.md 無凍結 skill 路由、installer
# 契約、-include 機制、asp-sync marker、settings 無 scope-guard、levels 無幽靈。
# Run: bash tests/test_separation.sh

set -uo pipefail

source "$(dirname "$0")/lib/common.sh"

ASP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ASP_ROOT" || exit 1

echo ""
echo "T1: .asp/ 內無凍結/showcase 殘留"
for p in .asp/scripts/multi-agent .asp/agents .asp/scripts/telemetry .asp/scripts/rag .asp/ai-performance; do
  [ ! -d "$p" ] && pass "$p 不存在" || fail "$p 仍在 .asp/"
done
for f in .asp/hooks/rag-auto-index.sh .asp/profiles/rag_context.md .asp/profiles/orchestrator_multi_agent.md; do
  [ ! -f "$f" ] && pass "$f 不存在" || fail "$f 仍在 .asp/"
done
[ "$(ls .asp/profiles/*.md | wc -l | tr -d ' ')" = "12" ] && pass "profiles = 12（v5 最終目標）" || fail "profiles = $(ls .asp/profiles/*.md | wc -l)"

echo ""
echo "T2: 凍結 skills 已移出，SKILL.md 路由收斂"
for s in asp-dispatch asp-team-pick asp-handoff; do
  [ ! -f ".claude/skills/asp/$s.md" ] && pass "$s.md 移出 skills/" || fail "$s.md 仍在 .claude/skills/asp/"
  [ -f "experimental/multi-agent/skills/$s.md" ] && pass "$s.md 在 experimental" || fail "$s.md 不在 experimental"
done
ROUTES=$(grep -cE '\|\s*(asp-dispatch|asp-team-pick|asp-handoff)\s*\|' .claude/skills/asp/SKILL.md || true)
[ "$ROUTES" = "0" ] && pass "SKILL.md 無凍結 skill 路由條目" || fail "SKILL.md 仍有 $ROUTES 條凍結路由"
grep -q '升級路徑' .claude/skills/asp/SKILL.md && pass "escalate 改指 global_core 升級路徑" || fail "escalate 路由缺失"
grep -q '升級路徑' .asp/profiles/global_core.md && pass "global_core 升級路徑節存在（無斷鏈）" || fail "global_core 升級路徑缺失"

echo ""
echo "T3: installer 契約"
INS=.asp/scripts/install.sh
grep -q -- '--with-showcase' "$INS" && pass "install.sh 有 --with-showcase" || fail "缺 --with-showcase"
grep -q 'ASP_WITH_SHOWCASE' "$INS" && pass "install.sh 有 ASP_WITH_SHOWCASE env" || fail "缺 env"
grep -q '.showcase-installed' "$INS" && pass "install.sh 有 marker" || fail "缺 marker"
grep -qE 'for dir in [^;]*agents' "$INS" && fail "dir 迴圈仍含 agents" || pass "dir 迴圈不含 agents"
grep -q 'scripts/multi-agent' "$INS" && grep -q 'rm -rf.*multi-agent' "$INS" \
  && pass "升級路徑清理 stale multi-agent" || fail "缺升級清理"
bash -n "$INS" && pass "install.sh 語法 ok" || fail "install.sh 語法錯"
grep -qE "for dir in [^;]*agents" .asp/scripts/install.ps1 2>/dev/null \
  && fail "install.ps1 dirs 仍含 agents" || pass "install.ps1 dirs 同步（無 agents）"

echo ""
echo "T4: Makefile -include 機制"
grep -q -- '-include experimental/multi-agent/Makefile.inc' .asp/Makefile.inc && pass "core 含 experimental -include" || fail "缺 experimental -include"
grep -q -- '-include showcase/Makefile.inc' .asp/Makefile.inc && pass "core 含 showcase -include" || fail "缺 showcase -include"
grep -qE '^rag-index:|^agent-worktree-list:|^asp-telemetry-collect:|^agent-unlock:' .asp/Makefile.inc \
  && fail "core 仍有已移走/deprecated targets" || pass "core 無已移走 targets 定義"
[ -f experimental/multi-agent/Makefile.inc ] && [ -f showcase/Makefile.inc ] && pass "兩個分區 Makefile.inc 存在" || fail "分區 Makefile.inc 缺失"

echo ""
echo "T5: asp-sync marker 機制"
grep -q '.showcase-installed' .claude/scripts/asp-sync.sh && pass "asp-sync 有 marker 處理" || fail "asp-sync 缺 marker"
grep -q 'showcase/telemetry' .claude/scripts/asp-sync.sh && pass "asp-sync 有補同步邏輯" || fail "asp-sync 缺補同步"
bash -n .claude/scripts/asp-sync.sh && pass "asp-sync 語法 ok" || fail "asp-sync 語法錯"

echo ""
echo "T6: repo settings 無 scope-guard；levels 無幽靈"
grep -q 'scope-guard' .claude/settings.json && fail "settings.json 仍有 scope-guard" || pass "settings.json 無 scope-guard"
grep -qE '^  - rag_context' .asp/levels/autonomous.yaml && fail "autonomous.yaml 仍列 rag_context" || pass "autonomous.yaml 無 rag_context"
grep -q 'orchestrator_multi_agent' .asp/config/profile-map.yaml | grep -v '#' \
  && fail "profile-map 仍載 orchestrator_multi_agent" || pass "profile-map 已收走凍結 profile（註解除外）"

echo ""
echo "T7: 移入檔案完整性（bash -n 全過）"
SYNTAX_OK=1
for f in experimental/multi-agent/scripts/*.sh showcase/rag/hooks/*.sh; do
  bash -n "$f" 2>/dev/null || { SYNTAX_OK=0; fail "syntax: $f"; }
done
[ "$SYNTAX_OK" = "1" ] && pass "experimental/showcase 腳本語法全過" || true
[ -f experimental/multi-agent/README.md ] && grep -q 'FROZEN' experimental/multi-agent/README.md \
  && pass "experimental README 標 FROZEN" || fail "FROZEN 標注缺失"
[ -f showcase/README.md ] && pass "showcase README 存在" || fail "showcase README 缺失"

echo ""
echo "════════════════════════════════"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
