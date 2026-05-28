---
name: asp-handoff
description: |
  Use when creating structured agent handoff documents in ASP workflows,
  or when an issue requires escalation in multi-agent workflows.
  Handles: task completion handoffs, cross-session bridges, escalation handoffs (P0-P3),
  agent reassignments, and pipeline phase gate transitions.
  Triggers: handoff, 交接, 任務移交, session bridge, escalation handoff,
  reassignment, phase gate, agent handoff, 移交任務, 建立交接單, create handoff,
  escalate, escalation, P0, P1, P2, P3, 緊急, 卡住了, stuck, blocked,
  critical issue, 無法繼續, 升級, pause and report, 需要升級, cannot proceed,
  security vulnerability, production down, qa fail 3x.
---

# ASP Handoff Skill

建立結構化的 agent 交接文件。本 skill 自包含，不依賴任何 `.asp/profiles/`。

## 交接類型選擇器

根據情境選擇對應類型：

| 類型 | 使用時機 |
|------|---------|
| **TASK_COMPLETE** | Worker → Orchestrator，任務完成（成功或失敗） |
| **SESSION_BRIDGE** | 跨 session 交接，context budget 用盡或人類介入時 |
| **ESCALATION** | 任何 agent → Orchestrator/人類，需要升級處理時 |
| **REASSIGNMENT** | Orchestrator → 新 Worker，轉派任務給其他 agent |
| **PHASE_GATE** | Pipeline 階段邊界，記錄品質門結果 |

輸出路徑：`.asp/handoffs/HANDOFF-{YYYYMMDD}-{TYPE}.yaml`

---

## 類型 1：TASK_COMPLETE

Worker → Orchestrator，任務完成（pass 或 fail）。

```yaml
handoff_type: TASK_COMPLETE
task_id: "TASK-{NNN}"
timestamp: "YYYY-MM-DDTHH:MM:SSZ"
from_agent:
  role: "{agent_role_id}"       # e.g., impl, tdd, qa
  task_manifest: "{manifest_ref}"
status: "{success|failed|needs_review}"

# === Context: Full transfer, NO summarization ===
artifacts:
  files_modified: []            # git diff --stat full output
  files_created: []
  diff_summary: |
    # Full git diff content
  test_output: |
    # Full make test-filter output
  test_checksums:               # For smuggling detection
    # "path/to/test_file.go": "sha256:..."

# === On failure (status != success) ===
failure_context:
  root_cause_analysis: ""
  attempted_fixes:
    - attempt: 1
      description: ""
      result: ""                # "oscillation", "cascade", "pass", etc.
  guard_triggered: null         # null | oscillation | cascade | smuggling
  remaining_failures: []

# === On success ===
success_context:
  spec_done_when_status:
    - criterion: ""
      verified: false
```

---

## 類型 2：SESSION_BRIDGE

跨 session 交接，擴充 `.asp-autopilot-state.json`。

```yaml
handoff_type: SESSION_BRIDGE
timestamp: "YYYY-MM-DDTHH:MM:SSZ"
session_id: ""
next_session_hint: ""

# === Autopilot state reference ===
autopilot_state_file: ".asp-autopilot-state.json"

# === Agent coordination state ===
agent_state:
  active_tracks: []             # Currently running parallel tracks
  pending_handoffs: []          # Handoffs not yet processed
  team_composition:
    scenario: ""                # e.g., NEW_FEATURE_complex
    agents: []                  # Active agent roles

# === Work summary ===
completed_work:
  phases_done: []               # Pipeline phases completed
  last_gate_passed: ""          # e.g., G3
  files_modified: []

pending_work:
  current_phase: ""
  current_gate: ""
  blocked_tasks: []
  next_action: ""

# === Context budget ===
context_usage_percent: 0
exit_reason: ""                 # context_budget | human_intervention | all_done
```

---

## 類型 3：ESCALATION

任何 agent → Orchestrator/人類，含 P0-P3 嚴重度分類。

```yaml
handoff_type: ESCALATION
task_id: "TASK-{NNN}"
timestamp: "YYYY-MM-DDTHH:MM:SSZ"
from_agent:
  role: "{agent_role_id}"
severity: "P0"                  # P0 | P1 | P2 | P3

# === Severity guide ===
# P0: Security vulnerability, data loss, production down → pause ALL tracks
# P1: auto_fix + reassign exhausted, unresolvable parallel conflict → pause current track
# P2: Single module QA fail 3x, scope exceeded, unexpected dependency → reassign
# P3: Tech debt accumulation, doc staleness → backlog

reason: ""
attempted_fixes:
  - description: ""
    result: ""

# === Full context snapshot (NO summarization) ===
context_snapshot:
  test_output: |
    # Full test output
  files_affected: []
  current_state: |
    # Description of current codebase state
  spec_reference: ""            # SPEC-NNN

escalation_target: "{role_id|human}"
```

### ESCALATION 決策樹：判斷嚴重度

```
問題發生 → 先問：
  1. 是否涉及安全漏洞 / 資料遺失 / 生產環境中斷？
     YES → P0（立即暫停一切，等待人類指示）

  2. 是否已重試 2+ 次且仍無法解決？或存在跨軌道不可解衝突？
     YES → P1（暫停當前軌道，Orchestrator 接管）

  3. 是否為單一模組 QA fail 3x / scope 超出 / 意外依賴？
     YES → P2（重新分派或增援）

  4. 以上皆否（tech debt、文件過期、非阻斷警告）？
     → P3（記入 backlog）
```

### 觸發點對照表

| 觸發來源 | 嚴重度 |
|----------|--------|
| 安全審查發現漏洞 / 生產環境事故 | P0 |
| auto_fix_loop 偷渡偵測 | P1 |
| auto_fix_loop 重試耗盡 → Orchestrator 重派 2 次仍失敗 | P1 |
| 並行軌道不可解衝突 | P1 |
| auto_fix_loop 振盪 / 級聯偵測 | P2 |
| auto_fix_loop 重試耗盡（僅第一次）/ 品質門重試 2 次失敗 | P2 |
| Dev↔QA 迴路模組 3x 失敗 / scope 超出 / 意外依賴 | P2 |
| Tech debt 累積 / 文件過期 | P3 |

### ESCALATION 執行流程

**P0**：立即停止所有工作 → 生成 ESCALATION handoff → 通知人類 → 等待明確指示，不可自行繼續

**P1**：暫停當前軌道（其他可繼續）→ 生成 ESCALATION handoff → Orchestrator 嘗試解決 → 無法解決則升級通知人類

**P2**：生成 ESCALATION handoff → 嘗試 REASSIGNMENT → 無法重派則升級為 P1

**P3**：記錄 tech debt（格式：`tech-debt: [HIGH|MED|LOW] [CATEGORY] description (DUE: YYYY-MM-DD)`）→ 繼續原本工作，不中斷

### ESCALATION 標準回覆格式

```
🔴 P0 ESCALATION（或 🟡 P1 / 🟠 P2 / ⚪ P3）

問題：{一句話說明}
嚴重度判定依據：{為什麼是這個等級}
已嘗試：
  1. {嘗試 1} → {結果}
  2. {嘗試 2} → {結果}

行動：{根據 P0-P3 流程說明下一步}
交接單：{若已生成，說明路徑}
```

---

## 類型 4：REASSIGNMENT

Orchestrator → 新 Worker，轉派並傳遞前任 Worker 的完整診斷。

```yaml
handoff_type: REASSIGNMENT
task_id: "TASK-{NNN}"
reassignment_count: 0          # Orchestrator retry count (max 2)
timestamp: "YYYY-MM-DDTHH:MM:SSZ"
from_agent:
  role: "{previous_agent_role}"
  previous_handoff: "HANDOFF-{NNN}"  # Reference to TASK_COMPLETE
to_agent:
  role: "{new_agent_role}"     # Can be different role if needed

# === Previous Worker's full diagnosis (NO summarization) ===
previous_diagnosis:
  attempted_fixes: []           # Copied from previous TASK_COMPLETE
  guard_triggered: null         # oscillation | cascade | smuggling | null
  test_output: |
    # Full test output from previous Worker
  files_changed: []             # What previous Worker modified

# === Orchestrator guidance ===
orchestrator_hint: |
  # Orchestrator's analysis of why previous Worker failed
  # and suggested alternative approach

# === Agent memory reference ===
memory_ref:
  similar_patterns: []          # From .asp-agent-memory.yaml fix_strategies
  suggested_strategy: ""
```

---

## 類型 5：PHASE_GATE

Pipeline 階段邊界，記錄品質門評估結果。

```yaml
handoff_type: PHASE_GATE
task_id: "TASK-{NNN}"
timestamp: "YYYY-MM-DDTHH:MM:SSZ"

gate:
  id: "G1"                     # G1-G6
  name: ""                     # e.g., "Architecture Gate", "Verification Gate"
  phase_from: ""               # SPECIFY | PLAN | FOUNDATION | BUILD | HARDEN | DELIVER
  phase_to: ""

# === Agent verdicts ===
evaluations:
  - agent_role: ""
    verdict: "PASS"            # PASS | NEEDS_WORK
    evidence:
      - ""
  # Reality Checker (if participating) has veto power
  - agent_role: "reality"
    verdict: "NEEDS_WORK"
    evidence:
      - ""

# === Gate result ===
final_verdict: "FAIL"          # PASS | FAIL
blocking_agent: ""             # Which agent blocked (if FAIL)
next_action: ""                # What needs to happen before retry
```

---

## 執行步驟

1. **判斷類型**：根據上方選擇器確認要建立哪種交接單
2. **填入內容**：複製對應 YAML 模板，填入所有 `{}` 佔位符
3. **不可摘要**：`context_snapshot`、`test_output`、`diff_summary` 等欄位必須放完整內容，不可省略
4. **產生路徑**：確認輸出到 `.asp/handoffs/HANDOFF-{YYYYMMDD}-{TYPE}.yaml`
5. **通知接收方**：ESCALATION 和 REASSIGNMENT 必須明確告知接收 agent 或人類

---

## 不要觸發此 skill 的情況

- 簡單的任務狀態更新（口頭說明即可）
- trivial bug 修復（affected_files <= 2，changed_lines <= 10）
- 單純的檔案讀取或資訊查詢
- 使用者只是問問題，不需要正式的交接文件