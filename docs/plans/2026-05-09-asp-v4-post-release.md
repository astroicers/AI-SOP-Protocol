# ASP v4.0 Post-Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 根據 `temp/` 四份文件的設計決策，完成 v4.0 發布後的三個主要工作：User-level Migration (D-004)、Track G Automation Subsystems、以及三個設計決策補完 (D-008 Reality Checker 三層、D-009 L0 Lifecycle、D-010 Implementer/Reviewer Pair)。

**Architecture:** 共 5 個 Track，Track 1 (User-level Migration) 最優先且風險最高；Track 2-5 可在 Track 1 完成驗證後並行。

**Tech Stack:** Bash, Python, YAML, Markdown, GitHub CLI (gh), Claude Code hooks

**Source documents:**
- `temp/asp-v4-improvement-prompts.md` — Prompt 10 執行步驟
- `temp/asp-production-ops-playbook.md` — Track G 子系統設計 + AI Performance Review
- `temp/asp-v4-design-notes.md` — D-004/D-008/D-009/D-010 決策紀錄

---

## Context: 現況與範圍

### 已完成（v4.0 正式發布，2026-05-09）

| 項目 | 狀態 | 證明 |
|-----|------|------|
| CLAUDE.md ≤ 100 行 | ✅ | 92 行（Agent skills 表格化後） |
| 22 個 asp-* skill | ✅ | `.claude/skills/asp/asp-*.md` |
| L0 Spike level + profile | ✅ | `level-0.yaml` + `spike_mode.md` |
| Iron Rules A/B/C | ✅ | `session-audit.sh` + `global_core.md` |
| Telemetry (collect/report/prune) | ✅ | `.asp/scripts/telemetry/` |
| STRIDE Threat Model | ✅ | `docs/security/threat-model-v4.0.md` |
| ROADMAP.md | ✅ | `docs/ROADMAP.md` |
| CONTEXT.md + bilingual table | ✅ | `CONTEXT.md` |
| docs/level0-spike-mode.md | ✅ | L0 user guide |

### 本計劃範圍（v4.0 之後）

| Track | 主題 | 對應設計決策 | 優先度 |
|-------|------|------------|-------|
| 1 | User-level Migration | D-004 | **P0（最先執行）** |
| 2 | AI Performance Review System | D-006 | P1 |
| 3 | L0 Lifecycle Mechanisms | D-009 | P1 |
| 4 | Reality Checker 三層架構 | D-008 | P2 |
| 5 | Semgrep Security Ruleset | D-002 | P2 |

**Track G 子系統 A/B/C/D 的完整自動化（需要專案進入 production）不在本計劃範圍**——這些在各專案自己的 CLAUDE.md 和 ops runbook 裡配置，不是 ASP framework 本身的工作。

---

## Track 1 — User-level Migration (Prompt 10)

**目標：** 把 ASP skills 部署到 `~/.claude/skills/asp/`，讓所有專案共享一份，不再各 repo 各裝。

**風險等級：高**（Migration 失敗 blast radius = 所有 ASP 專案同時失能）

**前置條件：**
- [ ] 確認 v4.0 已穩定（本計劃執行當天起算，已穩定 ≥ 2 週再做 migration）
- [ ] `git tag v3.7-final` 或 `git tag v4.0.0` 已建立（rollback 錨點）

### Step 1: 建立 user-level 目錄結構

```bash
mkdir -p ~/.claude/skills
mkdir -p ~/.claude/commands
mkdir -p ~/.claude/hooks
# 列出現有 ~/.claude/ 結構，確認無衝突
ls -la ~/.claude/
```
Expected: 無舊版 ASP skills 衝突

### Step 2: 複製 skills 到 user-level（保留 ASP repo 原件）

```bash
cp -r /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp ~/.claude/skills/
ls ~/.claude/skills/asp/ | wc -l
# Expected: 22（不是搬移，是複製）
```

### Step 3: 建立 user-level CLAUDE.md（≤ 60 行）

**File to create:** `~/.claude/CLAUDE.md`

內容原則（從現有 ASP CLAUDE.md 抽取通用鐵則，刪去 repo-specific 內容）：

```markdown
# ASP User-level Rules

> Applies to all projects. Project-specific rules go in each project's CLAUDE.md.

## 鐵則（不可覆蓋）

| 鐵則 | 說明 |
|------|------|
| 破壞性操作防護 | `git push / rebase / rm -rf / docker push` 必須先列出變更並等待人類確認 |
| 敏感資訊保護 | 禁止輸出 API Key、密碼、憑證 |
| ADR 未定案禁止實作 | Draft ADR 狀態下禁止寫生產代碼 |
| 外部事實驗證防護 | 涉及第三方 API/版本 → 必須執行 asp-fact-verify |

## 成熟度等級（L0-L5）

| Level | 名稱 | 適用場景 |
|-------|------|---------|
| L0 | Spike | 技術假設驗證、PoC |
| L1 | Starter | 個人/小型專案 |
| L2 | Disciplined | 自動化品質護欄 |
| L3 | Test-First | 測試文化成熟 |
| L4 | Collaborative | 中大型/跨模組 |
| L5 | Autonomous | ROADMAP 驅動 |

## 啟動程序

1. 讀取專案 `.ai_profile`，依欄位載入對應 profile
2. 無 `.ai_profile`：只套用鐵則，詢問使用者專案類型

## Agent skills

Invoke with `/skill-name`. All asp-* skills available via `~/.claude/skills/asp/`.
```

**Verify:**
```bash
wc -l ~/.claude/CLAUDE.md
# Must be ≤ 60
```

### Step 4: 在 temp 目錄驗證 user-level skills 可觸發

```bash
cd /tmp/asp-migration-test && mkdir -p . && cd /tmp/asp-migration-test
# 確認 claude code 讀得到 user-level skills（不需要實際 session，
# 檢查 skill 檔案路徑是否正確）
ls ~/.claude/skills/asp/asp-plan.md
ls ~/.claude/skills/asp/asp-gate.md
ls ~/.claude/skills/asp/asp-context.md
# Expected: 22 files accessible
```

### Step 5: 建立 sync 腳本

**File to create:** `~/.claude/scripts/asp-sync.sh`

```bash
#!/usr/bin/env bash
# Sync ASP skills from AI-SOP-Protocol repo to user-level
# Run after any ASP update

ASP_REPO="${HOME}/AI-SOP-Protocol"
USER_SKILLS="${HOME}/.claude/skills/asp"

if [ ! -d "$ASP_REPO" ]; then
    echo "ERROR: ASP repo not found at $ASP_REPO"
    exit 1
fi

echo "=== ASP Sync: $(date) ==="
diff -r "$USER_SKILLS" "$ASP_REPO/.claude/skills/asp" | head -20

echo ""
echo "Sync files? (y/N)"
read -r CONFIRM
if [ "$CONFIRM" = "y" ]; then
    cp -r "$ASP_REPO/.claude/skills/asp/." "$USER_SKILLS/"
    echo "Synced $(ls $USER_SKILLS | wc -l) skills"
else
    echo "Aborted"
fi
```

```bash
chmod +x ~/.claude/scripts/asp-sync.sh
mkdir -p ~/.claude/scripts
chmod +x ~/.claude/scripts/asp-sync.sh
```

### Step 6: 對最低風險專案做 migration（符石對決）

**只在確認 user-level 正常後才執行此 step。**

```bash
# 假設符石對決 repo 在 ~/符石對決 或類似路徑
# 先確認路徑
ls ~/projects/ 2>/dev/null || ls ~/ | grep -E "符石|chess|fuse"
```

Migration 步驟（對每個專案）：
1. `git checkout -b migrate-to-asp-v4-user-level`
2. 如果有 `.asp/` 目錄：備份 `cp -r .asp .asp.v4-backup`
3. 寫薄版 CLAUDE.md（≤ 30 行，只放 project-specific 規則）
4. 確認 `.ai_profile` 仍在（不需要刪）
5. `git commit -m "migrate: ASP user-level deployment (skills via ~/.claude/skills/asp)"`

**符石對決薄版 CLAUDE.md 範例：**
```markdown
# 符石對決

繼承 ~/.claude/CLAUDE.md 全部鐵則。

## 專案狀態
- Maturity Level: L0 (Spike)
- Tech stack: [填入]
- 部署環境: 個人使用，未對外

## L0 Promotion Criteria
- 第一個不認識的玩家 → 強制升 L1
- 第一筆金流 → 直接升 L2+
- 超過 60 天且仍 active → audit 是否升 L1
```

### Step 7: 驗收標準

```bash
# 1. user-level skills 存在且完整
ls ~/.claude/skills/asp/ | wc -l
# Expected: ≥ 22

# 2. user-level CLAUDE.md 在行數限制內
wc -l ~/.claude/CLAUDE.md
# Expected: ≤ 60

# 3. sync 腳本可執行
ls -la ~/.claude/scripts/asp-sync.sh
# Expected: -rwxr-xr-x (executable)

# 4. ASP repo 自身 skill 未被刪（只複製不搬移）
ls /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/ | wc -l
# Expected: ≥ 22
```

---

## Track 2 — AI Performance Review System (D-006)

**目標：** 建立 auto-merge 配套的 AI 事後反思機制，讓 AI 特權自動受限。

**Prerequisites:** 子系統 B (Trivial auto-merge) 需要先啟用。本 Track 先建立基礎設施，等 B 啟用後即可開始累積資料。

### Step 1: 建立目錄結構

```bash
mkdir -p ~/asp-ai-performance
```

### Step 2: 建立 auto-merged-prs.jsonl schema 文件

**File to create:** `~/asp-ai-performance/schema.md`

```markdown
# auto-merged-prs.jsonl Schema

每次 auto-merge 後手動或自動追加一筆：

{
  "ts": "ISO8601",
  "pr_number": 142,
  "repo": "Merak",
  "subsystem": "trivial-bug-fix",
  "files_changed": 3,
  "lines_changed": 12,
  "ai_classification": "trivial",
  "outcome_t30": null    ← 30 天後填入
}

30 天後 outcome_t30 填入：
  "reverted": bool
  "revert_pr": int | null
  "follow_up_bug_filed": bool
  "production_incident": bool
  "trust_score_delta": int (+1 存活, -5 revert, -20 incident)
```

### Step 3: 建立 trust-tier.yaml

**File to create:** `~/asp-ai-performance/trust-tier.yaml`

```yaml
trust_tier:
  current: TIER_2_STANDARD
  score: 100
  last_updated: "2026-05-09"

tiers:
  TIER_3_FULL_AUTO:
    min_score: 95
    auto_merge: true
    requires_label: false
    files_limit: 10

  TIER_2_STANDARD:
    min_score: 80
    auto_merge: true
    requires_label: "trivial-auto"
    files_limit: 5

  TIER_1_REVIEW:
    min_score: 60
    auto_merge: false
    auto_open_pr: true
    requires_human_approval: true

  TIER_0_REVOKED:
    min_score: 0
    auto_merge: false
    auto_open_pr: false
    you_must_invoke: true
```

### Step 4: 建立月度 review 腳本

**File to create:** `~/asp-ai-performance/monthly-review.py`

```python
#!/usr/bin/env python3
"""Monthly AI Performance Review — reads auto-merged-prs.jsonl, computes trust score."""
import json, sys
from pathlib import Path
from datetime import datetime, timedelta

LOG = Path.home() / "asp-ai-performance" / "auto-merged-prs.jsonl"
TIER = Path.home() / "asp-ai-performance" / "trust-tier.yaml"

def main():
    if not LOG.exists():
        print("No auto-merge log yet.")
        return

    entries = [json.loads(l) for l in LOG.read_text().splitlines() if l.strip()]
    thirty_days_ago = datetime.utcnow() - timedelta(days=30)

    total = len(entries)
    evaluated = [e for e in entries if e.get("outcome_t30") is not None]
    reverted = sum(1 for e in evaluated if e["outcome_t30"].get("reverted"))
    incidents = sum(1 for e in evaluated if e["outcome_t30"].get("production_incident"))
    survived = len(evaluated) - reverted - incidents

    score = 100 + survived - (reverted * 5) - (incidents * 20)
    score = max(0, min(100, score))

    print(f"=== AI Performance Review: {datetime.utcnow().date()} ===")
    print(f"Total auto-merged PRs: {total}")
    print(f"Evaluated (30d): {len(evaluated)}")
    print(f"  Survived: {survived}")
    print(f"  Reverted: {reverted}")
    print(f"  Incidents: {incidents}")
    print(f"Trust score: {score}/100")

    if score >= 95:
        tier = "TIER_3_FULL_AUTO"
    elif score >= 80:
        tier = "TIER_2_STANDARD"
    elif score >= 60:
        tier = "TIER_1_REVIEW"
    else:
        tier = "TIER_0_REVOKED"
    print(f"Current tier: {tier}")

if __name__ == "__main__":
    main()
```

```bash
chmod +x ~/asp-ai-performance/monthly-review.py
# Test run
python3 ~/asp-ai-performance/monthly-review.py
# Expected: "No auto-merge log yet."
```

### Step 5: 在 ASP repo 記錄此子系統

在 `docs/ROADMAP.md` 中的 v4.1 Planning 部分加入 AI Performance Review System 為 planned 項目（`make asp-refresh` 後可在 ROADMAP 中查看）。

---

## Track 3 — L0 Lifecycle Mechanisms (D-009)

**目標：** 補完 L0 的「出口」與「診斷」機制。入口已有（level-0.yaml + spike_mode.md + docs/level0-spike-mode.md）。

### Step 1: 讀現有 level-0.yaml 確認當前 graduation_checklist

```
Read /home/ubuntu/AI-SOP-Protocol/.asp/levels/level-0.yaml
```

### Step 2: 建立 l0-audit.sh（Active vs Zombie 診斷）

**File to create:** `/home/ubuntu/AI-SOP-Protocol/.asp/scripts/l0-audit.sh`

```bash
#!/usr/bin/env bash
# L0 Spike Lifecycle Audit
# Usage: bash .asp/scripts/l0-audit.sh
# Detects Zombie L0 vs Active L0 and checks Promotion Gate triggers.

PROJECT_DIR="${1:-.}"
AI_PROFILE="${PROJECT_DIR}/.ai_profile"

echo "=== L0 Lifecycle Audit: $(basename $(realpath $PROJECT_DIR)) ==="

# Check if L0
if [ ! -f "$AI_PROFILE" ]; then
    echo "No .ai_profile — skipping L0 audit"
    exit 0
fi

LEVEL=$(grep "^level:" "$AI_PROFILE" 2>/dev/null | awk '{print $2}')
if [ "$LEVEL" != "0" ]; then
    echo "Level: $LEVEL — not L0, audit not applicable"
    exit 0
fi

echo "Level: L0 (Spike)"
echo ""

# --- Promotion Gate Checks ---
echo "## Promotion Gate Triggers"

# Trigger 1: First external user
if git log --all --format='%ae' 2>/dev/null | sort -u | grep -v "$(git config user.email)" | grep -q "@"; then
    echo "  ⚠️  TRIGGER: External committer detected — must evaluate upgrade to L1"
else
    echo "  ✅ No external committers"
fi

# Trigger 2: 60-day clock
FIRST_COMMIT_DATE=$(git log --reverse --format='%ci' 2>/dev/null | head -1)
if [ -n "$FIRST_COMMIT_DATE" ]; then
    DAYS_SINCE=$(( ($(date +%s) - $(date -d "$FIRST_COMMIT_DATE" +%s 2>/dev/null || echo $(date +%s))) / 86400 ))
    if [ "$DAYS_SINCE" -gt 60 ]; then
        echo "  ⚠️  TRIGGER: Repo is ${DAYS_SINCE} days old (>60) — audit active vs zombie"
    else
        echo "  ✅ Repo age: ${DAYS_SINCE} days (≤60)"
    fi
fi

echo ""
echo "## Active vs Zombie Diagnosis"

# Q1: Recent commits?
RECENT_COMMITS=$(git log --since="30 days ago" --oneline 2>/dev/null | wc -l)
if [ "$RECENT_COMMITS" -gt 0 ]; then
    echo "  ✅ Active: $RECENT_COMMITS commits in last 30 days"
else
    echo "  ⚠️  Zombie signal: 0 commits in last 30 days"
fi

# Q2: File count growth (rough proxy for complexity)
TOTAL_FILES=$(git ls-files 2>/dev/null | wc -l)
if [ "$TOTAL_FILES" -gt 200 ]; then
    echo "  ⚠️  Complexity signal: $TOTAL_FILES tracked files (>200 for a spike?)"
else
    echo "  ✅ File count: $TOTAL_FILES (reasonable for L0)"
fi

echo ""
echo "## Recommendation"
if [ "$RECENT_COMMITS" -gt 0 ] && [ "${DAYS_SINCE:-0}" -le 60 ]; then
    echo "  Active L0 — no action required"
elif [ "$RECENT_COMMITS" -eq 0 ]; then
    echo "  Zombie L0 — decide: upgrade to L1 or archive/delete"
else
    echo "  Long-running L0 — review graduation checklist in docs/level0-spike-mode.md"
fi
```

```bash
chmod +x /home/ubuntu/AI-SOP-Protocol/.asp/scripts/l0-audit.sh
bash /home/ubuntu/AI-SOP-Protocol/.asp/scripts/l0-audit.sh /home/ubuntu/AI-SOP-Protocol
# Should output level check; ASP itself is L4, will exit early
```

### Step 3: 在 Makefile 加入 l0-audit target

```
Read /home/ubuntu/AI-SOP-Protocol/Makefile lines 1–30
# Find the right place to add l0-audit
```

在 Makefile 中加入：

```makefile
asp-l0-audit: ## Run L0 Lifecycle Audit (Active vs Zombie diagnosis)
	@bash .asp/scripts/l0-audit.sh .
.PHONY: asp-l0-audit
```

### Step 4: 更新 docs/level0-spike-mode.md 補「出口」機制

在現有文件的「Anti-patterns」之前插入：

```markdown
## L0 Lifecycle: Active vs Zombie Diagnosis

Run `make asp-l0-audit` monthly on L0 repos. Ask three questions:

1. **Active?** — Any commits in the last 30 days?
2. **Understandable?** — Can you change something in <30 min?
3. **Worth keeping?** — Would losing it cause pain?

| Answer | Diagnosis | Action |
|--------|-----------|--------|
| All yes | Active L0 | Continue as-is |
| No to Q1 | Zombie | Archive or delete |
| No to Q2 | Zombie trap | Upgrade to L1 or refactor |
| No to Q3 | Zombie | Delete |

## Promotion Gate Triggers (Mandatory L0 → L1 Evaluation)

These events FORCE an L0 → L1 evaluation regardless of your preference:

| Trigger | Why |
|---------|-----|
| First external user (someone you don't know) | Production signals require governance |
| Any real PII or payment data | Immediate L2+ required |
| Repo > 60 days old AND still in active dev | Prototype Trap risk |
| Going onto any app store / public deployment | L3 minimum required |
```

### Step 5: Verify

```bash
ls /home/ubuntu/AI-SOP-Protocol/.asp/scripts/l0-audit.sh
bash /home/ubuntu/AI-SOP-Protocol/.asp/scripts/l0-audit.sh .
grep -c "asp-l0-audit" /home/ubuntu/AI-SOP-Protocol/Makefile
# Expected: ≥ 1
```

---

## Track 4 — Reality Checker 三層架構 (D-008)

**目標：** 重新定位現有 Reality Checker 為 Layer 1，記錄三層架構設計，新增 asp-external-review skill 入口。

**注意：** Layer 3 (External AI via cross-vendor) 依賴外部服務（GitHub Copilot / Diamond），本 Track 只實作 skill 骨架和文件，不做完整整合。

### Step 1: 讀現有 reality-checker 相關文件

```
Read /home/ubuntu/AI-SOP-Protocol/.claude/agents/reality-checker.md
Read /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-reality-check.md lines 1–50
```

### Step 2: 建立 asp-external-review.md skill

**File to create:** `/home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-external-review.md`

```markdown
---
name: asp-external-review
description: Layer 3 external AI review — opens PR and waits for cross-vendor review (GitHub Copilot/Diamond)
---

# asp-external-review — Layer 3 External Review

**Independence level:** 4/4 (cross-vendor, different training pipeline)

## When to use

Required (not optional) for:
- auth / crypto / payment-related changes
- L3+ projects on any security-sensitive path
- High-Stakes mode (§3.5 of Production Ops Playbook)

Optional for:
- Any change where same-vendor Sonnet/Opus review is insufficient

## Process

### Step 1: Verify PR exists
```bash
gh pr view HEAD --json number,url 2>/dev/null || \
  echo "No PR yet — run asp-ship first to create PR"
```

### Step 2: Enable external AI review
```bash
# Enable GitHub Copilot code review (if available)
gh pr edit --add-reviewer "app/copilot-for-prs" 2>/dev/null || \
  echo "Manual: request review from your external AI service on this PR"
```

### Step 3: Wait and record
After external review completes, record in `.asp-review-calibration.jsonl`:

```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pr\":$(gh pr view --json number -q .number),\"layer3_reviewer\":\"copilot\",\"findings_count\":0,\"agreed_with_layer1\":true}" \
  >> .asp-review-calibration.jsonl
```

### Step 4: Resolution

If Layer 3 finds issues not caught by Layer 1 (asp-reality-check):
- Address all findings
- Re-run `/asp-gate G5`
- Record divergence in `.asp-review-calibration.jsonl`

## Three-Layer Review Architecture

| Layer | Who | Independence | When |
|-------|-----|-------------|------|
| L1 Mechanical | asp-reality-check (Claude, same session) | 0.5/4 | Always |
| L2 Human | You (architect review) | 4/4 | L3+ projects, ADR changes |
| L3 External AI | Cross-vendor AI (Copilot, Diamond) | 4/4 | High-Stakes, crypto, auth |

**For L1-L2 projects:** L1 + L2 is sufficient.
**For L3+ or crypto/auth paths:** All three layers required.
```

### Step 3: 在 SKILL.md router 加入 asp-external-review 路由

```
Read /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/SKILL.md lines 1–40
```

在 Multi-Agent 協作 section 加入 asp-external-review：

| 用戶意圖 | 觸發詞 | 載入的 Skill |
|---------|--------|------------|
| 外部 AI 跨廠商 review | external review, Layer 3, cross-vendor review, 外部審查 | asp-external-review |

### Step 4: Verify

```bash
ls /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-external-review.md
grep "asp-external-review" /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/SKILL.md | wc -l
# Expected: ≥ 1
```

---

## Track 5 — Semgrep Security Ruleset (D-002)

**目標：** 建立 `.semgrep/asp-security.yml` 並整合進 G4/G5 gate，把 ASP 的安全規則從 profile 中的 regex 搬到 deterministic enforcement。

**注意：** 這個 Track 需要 `semgrep` CLI 已安裝。若無，先跳過，記錄為 v4.1 backlog。

### Step 1: 確認 semgrep 是否可用

```bash
which semgrep 2>/dev/null && semgrep --version || echo "semgrep not installed"
# If not installed: pip install semgrep
```

### Step 2: 建立 .semgrep/asp-security.yml

**File to create:** `/home/ubuntu/AI-SOP-Protocol/.semgrep/asp-security.yml`

```yaml
rules:
  - id: asp-no-hardcoded-secret
    patterns:
      - pattern: $KEY = "..."
    message: "Potential hardcoded secret — use environment variables"
    languages: [python, go, javascript, typescript]
    severity: ERROR
    metadata:
      asp_rule: "Iron Rule: Sensitive Data Protection"

  - id: asp-no-raw-sql
    patterns:
      - pattern: db.Exec("SELECT..." + $USERINPUT)
      - pattern: db.Query("..." + $USERINPUT)
    message: "Potential SQL injection — use parameterized queries"
    languages: [go]
    severity: ERROR

  - id: asp-crypto-must-be-hitl
    patterns:
      - pattern: func Encrypt(...)
      - pattern: func Decrypt(...)
      - pattern: func Sign(...)
      - pattern: func Verify(...)
    message: "Crypto function detected — Iron Rule 7: HITL required, no auto-merge"
    languages: [go, python]
    severity: WARNING
    metadata:
      asp_rule: "Iron Rule 7: Crypto Auto-fix Prohibition"
```

### Step 3: 在 Makefile 加入 security-scan target

在現有 Makefile 中加入：

```makefile
security-scan: ## Run Semgrep ASP security rules (D-002)
	@semgrep --config=.semgrep/asp-security.yml . --quiet 2>/dev/null || \
	  echo "[ASP] semgrep not installed — skip security scan"
.PHONY: security-scan
```

### Step 4: Verify

```bash
ls /home/ubuntu/AI-SOP-Protocol/.semgrep/asp-security.yml
grep "security-scan" /home/ubuntu/AI-SOP-Protocol/Makefile | wc -l
# Expected: ≥ 1
semgrep --config=.semgrep/asp-security.yml /home/ubuntu/AI-SOP-Protocol --quiet 2>/dev/null || echo "OK (semgrep not installed)"
```

---

## Commit Strategy

| Track | Commit message |
|-------|---------------|
| 1 | `feat(deploy): user-level ASP skills + sync script (D-004)` |
| 2 | `feat(ops): AI Performance Review System infrastructure (D-006)` |
| 3 | `feat(l0): lifecycle audit script + promotion gate docs (D-009)` |
| 4 | `feat(review): asp-external-review skill + 3-layer architecture (D-008)` |
| 5 | `feat(security): Semgrep ASP ruleset + Makefile target (D-002)` |

After all tracks committed:
```bash
git tag v4.1.0-alpha -m "ASP v4.1.0-alpha — user-level migration + ops infrastructure"
```

---

## Explicitly Out of Scope (本計劃不做)

| Item | Reason |
|------|--------|
| Track G 子系統 A/B/C/D 完整自動化 | 各 project-specific，ASP framework 不直接實作 |
| aggregate.py / post-commit telemetry hook | v4.2 backlog，JSONL 格式已夠用 |
| MCP server | 已 cancelled (commit deleting ADR-003)，D-004 路徑已選 user-level |
| Merak / CyPulse / Backup encryption migration | 各專案自己的 migration PR，非 ASP repo 工作 |
| Monthly cron for Performance Review | 需要各 project 手動設定，不在 ASP repo 裡 |

---

## Execution Order

```
Track 1 (User-level Migration) ← 先跑，最高優先，驗證 2 週後才做各專案 migration
Track 2 (AI Performance Review) ← 基礎設施，等 Track 1 完成後同步進行
Track 3 (L0 Lifecycle) ← 獨立，可與 Track 2 並行
Track 4 (Reality Checker) ← 獨立，可任何時間做
Track 5 (Semgrep) ← 最低優先，取決於 semgrep 是否已安裝
```