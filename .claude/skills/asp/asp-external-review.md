---
name: asp-external-review
description: |
  Layer 3 external AI review — requests cross-vendor code review for high-stakes changes.
  Required for crypto/auth paths, L3+ projects, High-Stakes mode.
  Triggers: external review, Layer 3, cross-vendor review, 外部審查, 跨廠商審查
---

# asp-external-review — Layer 3 External AI Review

**Independence level:** 4/4 (cross-vendor, different training pipeline, different alignment)

---

## Three-Layer Review Architecture

| Layer | Who | Independence | When Required |
|-------|-----|-------------|---------------|
| **L1 Mechanical** | `asp-reality-check` (same-vendor Claude) | 0.5/4 | Always |
| **L2 Human** | You (architect review) | 4/4 | L3+ projects, ADR changes |
| **L3 External AI** | Cross-vendor AI (GitHub Copilot, Diamond) | 4/4 | High-Stakes, crypto/auth paths |

**For L0–L2 projects:** L1 + L2 is sufficient.
**For L3+ or any crypto/auth/payment path:** All three layers required (Iron Rule 7).

---

## When to Invoke

**Required (not optional):**
- Any change touching `/crypto/`, `/security/`, `/auth/` directories
- Functions named `Encrypt`, `Decrypt`, `Sign`, `Verify`, `Hash`, `Random`, `SecretShare`, `KeyDerivation`
- L3+ projects on security-sensitive paths
- Subsystem B/C in High-Stakes mode (§3.5 of Production Ops Playbook)

**Optional (recommended):**
- Any change where Sonnet/Opus same-vendor review feels insufficient
- ADR changes in L4+ projects

---

## Process

### Step 1: Confirm L1 (asp-reality-check) already passed

```bash
# asp-reality-check must pass BEFORE requesting Layer 3
# If not done: /asp-reality-check first
grep -r "PASS\|NEEDS_WORK" .asp-reality-check-log.md 2>/dev/null || \
  echo "Run /asp-reality-check first (Layer 1)"
```

### Step 2: Confirm PR exists

```bash
gh pr view --json number,url 2>/dev/null || \
  echo "No open PR — run /asp-ship first to create PR, then Layer 3"
```

### Step 3: Request external AI review

```bash
# Option A: GitHub Copilot (if enabled on the repo)
gh pr edit --add-reviewer "app/copilot-for-prs" 2>/dev/null && \
  echo "Copilot review requested" || \
  echo "Manual: go to the PR and request review from your external AI service"
```

If external AI is not configured:
- Go to the GitHub PR URL
- Click "Request review" → select your external AI reviewer
- Wait for review completion before proceeding

### Step 4: Record in calibration log (append-only)

After external review completes, record the outcome:

```bash
PR_NUM=$(gh pr view --json number -q .number 2>/dev/null || echo "unknown")
AGREED="true"   # Change to false if Layer 3 found issues Layer 1 missed

echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pr\":${PR_NUM},\"layer3_reviewer\":\"copilot\",\"agreed_with_layer1\":${AGREED},\"findings_count\":0}" \
  >> .asp-review-calibration.jsonl

echo "Calibration entry recorded in .asp-review-calibration.jsonl"
```

### Step 5: Resolution

If Layer 3 finds issues NOT caught by Layer 1 (`asp-reality-check`):
1. Address all Layer 3 findings
2. Re-run `/asp-reality-check` (Layer 1 re-check)
3. Record divergence in `.asp-review-calibration.jsonl` with `"agreed_with_layer1": false`
4. Proceed to `/asp-gate G5` → `/asp-ship` only when all layers agree

---

## Calibration & Trust

Track reviewer agreement in `.asp-review-calibration.jsonl`. Monthly review:

```bash
# Count Layer 3 divergences (issues Layer 1 missed)
grep '"agreed_with_layer1":false' .asp-review-calibration.jsonl | wc -l
```

High divergence rate → upgrade more changes to Layer 3 scope.
Low divergence rate → Layer 1 is well-calibrated for your codebase.

---

## Why Cross-Vendor Matters

Same-vendor models (Opus + Sonnet, both Anthropic) share:
- Same Constitutional AI training pipeline
- Same RLHF preference data
- Same alignment philosophy

Independence = **2.5/4** at best. For crypto/auth paths, silent failure is catastrophic
(backup encryption: data appears to work, fails at recovery time).

Cross-vendor review achieves **4/4 independence**: different training data, different
alignment objectives, different architectural biases. Catches what Anthropic models
systematically miss.

---

## Next Steps After This Skill

- Layer 3 PASS + Layer 1 PASS → 👉 `/asp-gate G5` → `/asp-ship`
- Layer 3 found issues → 👉 Fix → re-run `/asp-reality-check` → back to Step 4
