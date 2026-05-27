# ADR FIRM State Propagation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 讓所有 ASP 執行路徑（profiles、skills、scripts、CLAUDE.md）都認識 FIRM 中間態，使 FIRM ADR 能合法通過原本只接受 Accepted 的閘門。

**Architecture:** FIRM 的語義已在 ADR_Template、session-audit、Makefile、asp-gate G1、asp-plan 定義完畢。本計劃把這個語義向下傳播到 13 個還用二態邏輯（Draft/Accepted）的檔案。每個 Task 改一個檔案，變更局部且可獨立驗證。

**Tech Stack:** Bash (audit-fallback.sh)、Markdown（profiles/*.md, skills/*.md, CLAUDE.md）、無測試框架（用 grep 驗證）

**FIRM 語義定義（所有 Task 的共同依據）：**
- `Draft` → 禁止生產代碼；git commit 動態阻擋
- `FIRM` → 允許 commit；視同「有條件的 Accepted」；audit 輸出 🟡 YELLOW FLAG；需有 Verification Evidence
- `Accepted` → 完全放行

---

## Task 1：audit-fallback.sh — 加入 FIRM YELLOW FLAG

**背景：** 沒有安裝 Makefile 的專案跑 `/asp-audit` 時走這支腳本。目前只偵測 Draft BLOCKER，FIRM 被忽略。

**Files:**
- Modify: `.asp/scripts/audit-fallback.sh:89-93`

**Step 1: 讀取現有邏輯**

```bash
grep -n "Draft\|STATUS\|FIRM" /home/ubuntu/AI-SOP-Protocol/.asp/scripts/audit-fallback.sh
```

預期看到約第 89 行：`if [ "$STATUS" = "Draft" ]; then`

**Step 2: 修改**

找到這個區塊：
```bash
  if [ "$STATUS" = "Draft" ]; then
      ADR_ID=$(basename "$f" .md | grep -o 'ADR-[0-9]*')
      if grep -r "$ADR_ID" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" . >/dev/null 2>&1; then
          echo "  🔴 BLOCKER: $ADR_ID 狀態為 Draft 但已有實作代碼（鐵則違反）"
```

改為（在 `if` 之前加入 ADR_ID 提取，並加入 `elif FIRM`）：
```bash
      ADR_ID=$(basename "$f" .md | grep -o 'ADR-[0-9]*')
      if [ "$STATUS" = "Draft" ]; then
          if grep -r "$ADR_ID" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" . >/dev/null 2>&1; then
              echo "  🔴 BLOCKER: $ADR_ID 狀態為 Draft 但已有實作代碼（鐵則違反）"
              BLOCKERS=$((BLOCKERS + 1))
          fi
      elif [ "$STATUS" = "FIRM" ]; then
          if grep -r "$ADR_ID" --include="*.go" --include="*.ts" --include="*.py" --include="*.java" . >/dev/null 2>&1; then
              echo "  🟡 WARNING: $ADR_ID 狀態為 FIRM（POC 驗證中）— 允許 commit，待人類升級至 Accepted"
              WARNINGS=$((WARNINGS + 1))
          fi
```

**Step 3: 驗證**

```bash
grep -n "FIRM\|YELLOW\|elif" /home/ubuntu/AI-SOP-Protocol/.asp/scripts/audit-fallback.sh
```

預期：看到 `elif [ "$STATUS" = "FIRM" ]` 和 YELLOW WARNING 字串

**Step 4: Commit**

```bash
git add .asp/scripts/audit-fallback.sh
git commit -m "fix(audit-fallback): add FIRM YELLOW FLAG alongside Draft BLOCKER"
```

---

## Task 2：pipeline.md — G1 gate 接受 FIRM

**背景：** `pipeline.md` 第 57-59 行的 G1 邏輯只接受 `Accepted`，FIRM 會觸發 GATE_FAIL。

**Files:**
- Modify: `.asp/profiles/pipeline.md:57-59`

**Step 1: 讀取現有邏輯**

```bash
sed -n '53,65p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/pipeline.md
```

**Step 2: 修改**

找到：
```
    IF NOT exists(artifacts.adr) OR artifacts.adr.status != "Accepted":
      RETURN GATE_FAIL("ADR 不存在或非 Accepted 狀態（鐵則）")
    checks.append("ADR Accepted ✅")
```

改為：
```
    IF NOT exists(artifacts.adr):
      RETURN GATE_FAIL("ADR 不存在（鐵則）")
    IF artifacts.adr.status == "Draft":
      RETURN GATE_FAIL("ADR 為 Draft 狀態，禁止實作（鐵則）")
    IF artifacts.adr.status == "FIRM":
      checks.append("ADR FIRM 🟡（POC 驗證中，允許繼續，記錄 bypass log）")
      YELLOW_FLAG("ADR 尚未正式 Accepted，請盡快升級")
    ELSE:
      checks.append("ADR Accepted ✅")
```

也更新第 473 行的 metric 表格，把 `Draft ADR 數 = 0` 改為 `Draft ADR 數 = 0（FIRM 不計入）`

**Step 3: 驗證**

```bash
grep -n "FIRM\|Draft\|GATE_FAIL" /home/ubuntu/AI-SOP-Protocol/.asp/profiles/pipeline.md | head -10
```

預期：看到 FIRM 的條件分支

**Step 4: Commit**

```bash
git add .asp/profiles/pipeline.md
git commit -m "fix(pipeline): G1 gate accepts FIRM ADR as conditional pass"
```

---

## Task 3：autonomous_dev.md — FIRM 視為有條件的 Accepted

**背景：** 第 20、33、195、247 行都要求 `Accepted` 才放行。FIRM 應被允許但標記。

**Files:**
- Modify: `.asp/profiles/autonomous_dev.md:20,33,57,195,247`

**Step 1: 讀取**

```bash
sed -n '18,22p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/autonomous_dev.md
sed -n '31,35p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/autonomous_dev.md
sed -n '193,197p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/autonomous_dev.md
```

**Step 2: 修改四處**

**第 20 行**，`ADR 已為 Accepted 狀態` → `ADR 已為 Accepted 或 FIRM 狀態`

**第 33 行**，表格中 `對應 ADR 已 Accepted` → `對應 ADR 已 Accepted 或 FIRM（🟡）`

**第 57 行**，`AI 不可自行將 ADR 從 Draft 改為 Accepted` → `AI 不可自行將 ADR 從 Draft 改為 FIRM 或 Accepted`

**第 195 行**：
```
  VERIFY adr_status(stage.adr) == "Accepted"
```
改為：
```
  VERIFY adr_status(stage.adr) IN ["Accepted", "FIRM"]
  IF adr_status(stage.adr) == "FIRM": YELLOW_FLAG("ADR 為 FIRM，待升級至 Accepted")
```

**第 247 行**，`建立/修改 SPEC（ADR 已 Accepted）` → `建立/修改 SPEC（ADR 已 Accepted 或 FIRM）`

**Step 3: 驗證**

```bash
grep -n "FIRM\|Accepted" /home/ubuntu/AI-SOP-Protocol/.asp/profiles/autonomous_dev.md | head -15
```

**Step 4: Commit**

```bash
git add .asp/profiles/autonomous_dev.md
git commit -m "fix(autonomous_dev): accept FIRM ADR as conditional pass for implementation"
```

---

## Task 4：autopilot.md — FIRM 不等同 blocked

**背景：** 第 258 行 `adr.status != "Accepted"` 把 FIRM 歸類為 blocked，導致 autopilot 永遠跳過 FIRM ADR 的任務。

**Files:**
- Modify: `.asp/profiles/autopilot.md:252-270,511-512`

**Step 1: 讀取**

```bash
sed -n '250,275p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/autopilot.md
sed -n '509,514p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/autopilot.md
```

**Step 2: 修改**

**第 255-258 行區塊**：
```
        blocked_by_adr.append(task.id)  // Draft ADR → 無法實作，標記 blocked
      ELIF adr.status != "Accepted":
```
改為：
```
        blocked_by_adr.append(task.id)  // Draft ADR → 無法實作，標記 blocked
      ELIF adr.status == "FIRM":
        LOG("Task {task.id}: ADR {task.adr} 為 FIRM（POC 驗證中）→ 允許執行，標記 🟡")
        yellow_flag_tasks.append(task.id)
      ELIF adr.status != "Accepted":
```

**第 511-512 行表格**加入新行：
```
| **ADR 為 FIRM** | 允許執行，任務標記 🟡，輸出 bypass log |
```

**Step 3: 驗證**

```bash
grep -n "FIRM\|yellow_flag\|blocked_by_adr" /home/ubuntu/AI-SOP-Protocol/.asp/profiles/autopilot.md | head -10
```

**Step 4: Commit**

```bash
git add .asp/profiles/autopilot.md
git commit -m "fix(autopilot): FIRM ADR tasks execute with yellow flag, not blocked"
```

---

## Task 5：task_orchestrator.md — WAIT_UNTIL 接受 FIRM

**背景：** 第 327 行 `WAIT_UNTIL adr.status == "Accepted"` 對 FIRM ADR 會一直等到逾時（30 分鐘）。

**Files:**
- Modify: `.asp/profiles/task_orchestrator.md:125-126,327-329`

**Step 1: 讀取**

```bash
sed -n '123,130p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/task_orchestrator.md
sed -n '325,332p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/task_orchestrator.md
```

**Step 2: 修改**

**第 125-126 行**（Draft 有實作代碼 → BLOCKER）：這條邏輯正確，**不動**。
只需在下方補：
```
    IF adr.status == "FIRM" AND has_implementation_code(adr):
      report.add(WARNING, "ADR-{adr.id} 狀態為 FIRM（🟡）— 允許，待升級至 Accepted")
```

**第 327-329 行**：
```
    WAIT_UNTIL adr.status == "Accepted" OR timeout(30_minutes):
```
改為：
```
    WAIT_UNTIL adr.status IN ["Accepted", "FIRM"] OR timeout(30_minutes):
      IF adr.status == "FIRM":
        PRESENT("🟡 ADR-{adr.id} 為 FIRM 狀態，允許繼續執行（建議盡快升至 Accepted）")
```

**Step 3: 驗證**

```bash
grep -n "FIRM\|WAIT_UNTIL\|yellow\|WARNING" /home/ubuntu/AI-SOP-Protocol/.asp/profiles/task_orchestrator.md | head -10
```

**Step 4: Commit**

```bash
git add .asp/profiles/task_orchestrator.md
git commit -m "fix(task_orchestrator): WAIT_UNTIL accepts FIRM, FIRM+code is WARNING not BLOCKER"
```

---

## Task 6：system_dev.md — 狀態機加入 FIRM

**背景：** 第 27 行的狀態機定義沒有 FIRM；第 33、199、203、205、271、482 行的「Accepted 才可」說法需更新。

**Files:**
- Modify: `.asp/profiles/system_dev.md:27,33,199,203,205,271,482`

**Step 1: 讀取**

```bash
sed -n '25,35p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/system_dev.md
sed -n '197,207p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/system_dev.md
```

**Step 2: 修改**

**第 27 行**狀態機：
```
Draft → Proposed → Accepted → Deprecated / Superseded by ADR-XXX
```
改為：
```
Draft → FIRM（人類填 Verification Evidence）→ Accepted → Deprecated / Superseded by ADR-XXX
```

**第 33 行**：`ADR 狀態為 Draft 時，禁止撰寫對應的生產代碼（鐵則）` — **不動**（正確）

**第 199、203 行**：`Accepted → 繼續` 改為 `Accepted 或 FIRM（🟡）→ 繼續`

**第 205 行**：`ADR 為 Draft → 先完成 ADR 審議，不建 SPEC、不寫生產代碼` — **不動**（正確）

**第 271 行**：`前提是對應 ADR 已 Accepted` → `前提是對應 ADR 已 Accepted 或 FIRM`

**第 482 行** checklist：`□ ADR 已標記 Accepted` → `□ ADR 已標記 Accepted 或 FIRM（🟡 需後續升級）`

**Step 3: 驗證**

```bash
grep -n "FIRM\|Draft\|Accepted" /home/ubuntu/AI-SOP-Protocol/.asp/profiles/system_dev.md | head -15
```

**Step 4: Commit**

```bash
git add .asp/profiles/system_dev.md
git commit -m "fix(system_dev): add FIRM to ADR state machine and allow-list"
```

---

## Task 7：reality_checker.md — FIRM 不觸發 BLOCKER

**背景：** 第 126、134 行把 Draft ADR 計入 BLOCKER。FIRM ADR 不應被計入。

**Files:**
- Modify: `.asp/profiles/reality_checker.md:126,134`

**Step 1: 讀取**

```bash
sed -n '123,137p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/reality_checker.md
```

**Step 2: 修改**

**第 126 行** metric 表格：
```
Draft ADR 數          | = 0              | 1         | ❌ BLOCKER
```
改為：
```
Draft ADR 數          | = 0              | 1         | ❌ BLOCKER
FIRM ADR 數           | ≥ 0（監控）      | —         | 🟡 YELLOW（非 BLOCKER）
```

**第 134 行**敘述：
```
  2. Draft ADR 存在（ADR-007 尚未 Accept）→ BLOCKER
```
改為：
```
  2. Draft ADR 存在（ADR-007 尚未 Accept）→ BLOCKER（FIRM 狀態不計入此項）
```

**Step 3: 驗證**

```bash
grep -n "FIRM\|Draft\|BLOCKER" /home/ubuntu/AI-SOP-Protocol/.asp/profiles/reality_checker.md | head -10
```

**Step 4: Commit**

```bash
git add .asp/profiles/reality_checker.md
git commit -m "fix(reality_checker): FIRM ADR is YELLOW not BLOCKER"
```

---

## Task 8：vibe_coding.md — SPEC 建立允許 FIRM

**背景：** 第 87 行要求 `ADR 已 Accepted` 才能建 SPEC，FIRM 應同樣允許（有條件）。

**Files:**
- Modify: `.asp/profiles/vibe_coding.md:87`

**Step 1: 讀取**

```bash
sed -n '85,90p' /home/ubuntu/AI-SOP-Protocol/.asp/profiles/vibe_coding.md
```

**Step 2: 修改**

```
| 建立新 SPEC（前提：ADR 已 Accepted） | 發現需求超出 SPEC/版本範圍 |
```
改為：
```
| 建立新 SPEC（前提：ADR 已 Accepted 或 FIRM） | 發現需求超出 SPEC/版本範圍 |
```

**Step 3: 驗證**

```bash
grep -n "FIRM\|Accepted\|SPEC" /home/ubuntu/AI-SOP-Protocol/.asp/profiles/vibe_coding.md | head -5
```

**Step 4: Commit**

```bash
git add .asp/profiles/vibe_coding.md
git commit -m "fix(vibe_coding): allow SPEC creation when ADR is FIRM"
```

---

## Task 9：asp-ship.md — FIRM 有豁免路徑

**背景：** 第 122 行 `Draft ADR → BLOCK`；第 242、254 行的 rationalization/bypass 表沒有 FIRM 路徑。

**Files:**
- Modify: `.claude/skills/asp/asp-ship.md:121-122,242,254`

**Step 1: 讀取**

```bash
sed -n '119,125p' /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-ship.md
sed -n '240,245p' /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-ship.md
sed -n '252,256p' /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-ship.md
```

**Step 2: 修改**

**第 121-122 行** ADR 檢查：
```
- 所有 `Accepted` ADR 的決策是否在此次變更中被遵守
- 是否有 `Draft` ADR 對應的生產代碼被加入 → 🔴 **BLOCK**（鐵則）
```
改為：
```
- 所有 `Accepted` ADR 的決策是否在此次變更中被遵守
- 是否有 `Draft` ADR 對應的生產代碼被加入 → 🔴 **BLOCK**（鐵則）
- 是否有 `FIRM` ADR 對應的生產代碼被加入 → 🟡 **YELLOW**（允許，需記錄 bypass log）
```

**第 242 行** rationalization 表，在 Draft 那行下方新增：
```
| 「ADR 是 FIRM，可以合法 commit」 | ✅ 正確。FIRM + Verification Evidence = 允許 commit，但需在 bypass log 記錄，並在下次 session 前升級至 Accepted。 |
```

**第 254 行** bypass 表，新增：
```
| FIRM ADR 對應生產代碼 | 允許，記錄至 bypass log，盡快升至 Accepted |
```

**Step 3: 驗證**

```bash
grep -n "FIRM\|YELLOW\|bypass" /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-ship.md | head -10
```

**Step 4: Commit**

```bash
git add .claude/skills/asp/asp-ship.md
git commit -m "fix(asp-ship): FIRM ADR is YELLOW not BLOCK, add bypass log guidance"
```

---

## Task 10：asp-autopilot.md — FIRM 任務不 blocked

**背景：** 第 102 行把 `Draft` ADR 對應任務標為 blocked；需讓 FIRM 走不同路徑。

**Files:**
- Modify: `.claude/skills/asp/asp-autopilot.md:69,102,208`

**Step 1: 讀取**

```bash
sed -n '67,72p' /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-autopilot.md
sed -n '100,105p' /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-autopilot.md
sed -n '206,210p' /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-autopilot.md
```

**Step 2: 修改**

**第 69 行**：`Draft ADR 不阻擋非依賴任務` — 語意正確，補充：
`Draft ADR 不阻擋非依賴任務；FIRM ADR 不阻擋任何任務（標記 🟡）`

**第 102 行** 表格：
```
| 對應 ADR 為 Draft | 標記 `blocked`，跳過，繼續下一任務 |
```
下方新增：
```
| 對應 ADR 為 FIRM  | 標記 `🟡 yellow`，允許執行，輸出警告 |
```

**第 208 行** 表格：
```
| Draft ADR 阻擋 | 自動標記 blocked，跳至下一任務 |
```
下方新增：
```
| FIRM ADR       | 自動標記 🟡，允許執行，記錄至 session briefing |
```

**Step 3: 驗證**

```bash
grep -n "FIRM\|yellow\|blocked" /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-autopilot.md | head -10
```

**Step 4: Commit**

```bash
git add .claude/skills/asp/asp-autopilot.md
git commit -m "fix(asp-autopilot): FIRM ADR tasks run with yellow flag, not blocked"
```

---

## Task 11：asp-change-cascade.md — 新方向允許 FIRM

**背景：** 第 102、121、123 行要求新 ADR 進入 `Accepted` 才能實作。FIRM 應是合法的中間點。

**Files:**
- Modify: `.claude/skills/asp/asp-change-cascade.md:102,121,123`

**Step 1: 讀取**

```bash
sed -n '100,125p' /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-change-cascade.md
```

**Step 2: 修改**

**第 102 行**：
```
**必須暫停，等待人類確認後才執行。新 ADR Accepted 後才能開始新方向的實作。**
```
改為：
```
**必須暫停，等待人類確認後才執行。新 ADR 升至 FIRM 或 Accepted 後才能開始新方向的實作。**
```

**第 121、123 行**（兩處 `Accepted 後`）：
各自改為 `FIRM 或 Accepted 後`

**Step 3: 驗證**

```bash
grep -n "FIRM\|Accepted" /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/asp-change-cascade.md | head -10
```

**Step 4: Commit**

```bash
git add .claude/skills/asp/asp-change-cascade.md
git commit -m "fix(asp-change-cascade): allow implementation after FIRM, not only Accepted"
```

---

## Task 12：CLAUDE.md（專案）— 鐵則說明補 FIRM

**背景：** 第 42、52 行只提 Draft，使用者看不到 FIRM 的存在。

**Files:**
- Modify: `CLAUDE.md:42,52`

**Step 1: 讀取**

```bash
sed -n '40,55p' /home/ubuntu/AI-SOP-Protocol/CLAUDE.md
```

**Step 2: 修改**

**第 42 行**：
```
| **ADR 未定案禁止實作** | Draft ADR 狀態下禁止寫生產代碼；`session-audit.sh` 動態注入 `git commit` deny |
```
改為：
```
| **ADR 未定案禁止實作** | `Draft` ADR 禁止生產代碼；`FIRM` ADR 允許 commit（需 Verification Evidence，audit 輸出 🟡）；`session-audit.sh` 動態注入 deny |
```

**第 52 行**：
```
| L2: Dynamic Deny | Draft ADR / 測試未過 → 動態阻擋 `git commit` | 硬（VSCode deny dialog） |
```
改為：
```
| L2: Dynamic Deny | `Draft` ADR / 測試未過 → 動態阻擋 `git commit`；`FIRM` ADR → 允許但記錄 bypass log | 硬（VSCode deny dialog） |
```

**Step 3: 驗證**

```bash
grep -n "FIRM\|Draft" /home/ubuntu/AI-SOP-Protocol/CLAUDE.md | head -10
```

**Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE.md): clarify FIRM state in ADR iron rule and L2 dynamic deny"
```

---

## Task 13：~/.claude/CLAUDE.md（user-level）— 同步鐵則說明

**背景：** User-level CLAUDE.md 第 11 行只寫 Draft，需與專案層對齊。

**Files:**
- Modify: `~/.claude/CLAUDE.md:11`

**Step 1: 讀取**

```bash
sed -n '9,13p' ~/.claude/CLAUDE.md
```

**Step 2: 修改**

```
| ADR 未定案禁止實作 | Draft ADR 狀態下禁止寫生產代碼 |
```
改為：
```
| ADR 未定案禁止實作 | `Draft` ADR 禁止生產代碼；`FIRM`（含 Verification Evidence）允許 commit，audit 輸出 🟡 |
```

**Step 3: 驗證**

```bash
grep -n "FIRM\|Draft" ~/.claude/CLAUDE.md
```

**Step 4: Commit**

```bash
git add ~/.claude/CLAUDE.md
# 注意：~/.claude/CLAUDE.md 不在本 repo，此 commit 不適用
# 改為透過 asp-sync.sh 同步後，確認內容已更新
bash ~/.claude/scripts/asp-sync.sh --yes
```

---

## Task 14：asp-sync + 最終驗證

**Step 1: 同步所有變更到 user-level**

```bash
bash ~/.claude/scripts/asp-sync.sh --yes
```

**Step 2: 全域驗證 FIRM 覆蓋率**

```bash
# 確認所有執行路徑都認識 FIRM
grep -rn "FIRM" \
  /home/ubuntu/AI-SOP-Protocol/.asp/profiles/ \
  /home/ubuntu/AI-SOP-Protocol/.asp/scripts/ \
  /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/ \
  /home/ubuntu/AI-SOP-Protocol/CLAUDE.md \
  | grep -v ".bak" | wc -l
```

預期：> 30 處（覆蓋所有 13 個檔案）

**Step 3: 確認 Draft 鐵則未被削弱**

```bash
# Draft 的 BLOCKER 邏輯應仍然存在
grep -rn "Draft.*BLOCK\|BLOCK.*Draft\|Draft.*禁止\|禁止.*Draft" \
  /home/ubuntu/AI-SOP-Protocol/.asp/ \
  /home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/ \
  | grep -v ".bak"
```

預期：仍有多處 Draft BLOCKER，未被移除

**Step 4: 最終 commit**

```bash
git add CHANGELOG.md
git commit -m "docs(CHANGELOG): record FIRM state propagation to all execution paths"
```

---

## 執行順序

Tasks 1-11 互相獨立，可任意順序。  
Task 12（CLAUDE.md）在 Tasks 1-11 之後，確保措辭一致。  
Task 13-14（sync + 驗證）最後執行。

建議批次：
- **批次 A**（scripts）：Task 1
- **批次 B**（profiles）：Tasks 2-8（可並行）
- **批次 C**（skills）：Tasks 9-11（可並行）
- **批次 D**（收尾）：Tasks 12-14
