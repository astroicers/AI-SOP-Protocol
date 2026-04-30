---
name: asp-handoff
description: |
  Use when creating structured agent handoff documents in ASP workflows.
  Handles: task completion handoffs, cross-session bridges, escalation handoffs,
  agent reassignments, and pipeline phase gate transitions.
  Triggers: handoff, 交接, 任務移交, session bridge, escalation handoff,
  reassignment, phase gate, agent handoff, 移交任務, 建立交接單, create handoff.
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