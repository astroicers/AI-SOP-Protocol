# SPEC-002: ASP MCP Server 規格書

**Status:** Draft
**Date:** 2026-04-29
**ADR Reference:** ADR-003

## Goal

提供 Python MCP server，讓 Claude Code 以結構化 tool call 的方式操作 ASP governance，
替代依賴文字觸發詞的 skill Markdown 方式。

## Architecture

```
Claude Code Agent
      │ tool_call(asp_gate_evaluate, ...)
      ▼
ASP MCP Server (.asp/mcp/server.py)
      │
      ├── asp_gate_evaluate() → reads .asp-session-briefing.json + .ai_profile
      ├── asp_audit_quick() → calls make audit-quick internally
      ├── asp_bypass_log() → appends to .asp-bypass-log.json
      ├── asp_telemetry_push() → appends to .asp-telemetry.jsonl
      ├── asp_handoff_create() → writes to .asp/handoffs/
      └── asp_fact_check_log() → appends to .asp-fact-check.md
```

## Tool Specifications

### asp_gate_evaluate

Input:
```json
{
  "gate_id": "G1 | G2 | G3 | G4 | G5 | G6",
  "context_json": "{}"
}
```

Output:
```json
{
  "status": "ok",
  "verdict": "PASS | FAIL | SKIP",
  "gate_id": "G1",
  "checks": [
    {"name": "ADR exists", "result": "PASS"},
    {"name": "ADR status Accepted", "result": "FAIL", "reason": "ADR-001 is Draft"}
  ],
  "message": "Gate G1 FAIL: ADR-001 is not Accepted"
}
```

Error cases:
- `.ai_profile` 不存在 → `{"status": "no_profile", "verdict": "SKIP"}`
- 無效 gate_id → `{"status": "error", "message": "Invalid gate_id: G7"}`

### asp_audit_quick

Input: `{}`

Output:
```json
{
  "status": "ok",
  "blockers": [
    {"id": "ADR-001", "type": "draft_adr", "message": "ADR-001 is Draft — git commit blocked"}
  ],
  "warnings": [],
  "blocker_count": 1
}
```

### asp_bypass_log

Input:
```json
{
  "skill": "asp-ship",
  "step": "Step 9",
  "reason": "Emergency hotfix — credential scan deferred"
}
```

Output:
```json
{
  "status": "ok",
  "logged_at": "2026-04-29T10:00:00+08:00",
  "entry_id": "bypass-20260429-001"
}
```

### asp_telemetry_push

Input:
```json
{
  "event_type": "gate_pass | gate_fail | bypass | session_start | skill_invoke",
  "data_json": "{\"gate_id\": \"G4\", \"profile_type\": \"system\"}"
}
```

Output:
```json
{
  "status": "ok",
  "event_id": "tel-20260429-abc123"
}
```

### asp_handoff_create

Input:
```json
{
  "type": "TASK_COMPLETE | SESSION_BRIDGE | ESCALATION | REASSIGNMENT | PHASE_GATE",
  "context_json": "{\"task_id\": \"B1\", \"completed_by\": \"impl\"}"
}
```

Output:
```json
{
  "status": "ok",
  "file_path": ".asp/handoffs/HANDOFF-20260429-TASK_COMPLETE.yaml"
}
```

### asp_fact_check_log

Input:
```json
{
  "claim": "Nuclei v3.2.0 supports YAML template format",
  "source": "https://github.com/projectdiscovery/nuclei/releases",
  "verdict": "PASS | FAIL | UNVERIFIED"
}
```

Output:
```json
{
  "status": "ok",
  "logged_at": "2026-04-29T10:00:00+08:00"
}
```

## Done When

- [ ] `python3 .asp/mcp/server.py --check` 回傳 `{"status": "ok", "tools": 6}`
- [ ] `asp_gate_evaluate(gate_id="G4", context_json="{}")` 回傳 JSON without crashing
- [ ] `.ai_profile` 不存在時回傳 `{"status": "no_profile", "verdict": "SKIP"}` 而不是 crash
- [ ] 所有現有 skill 在 MCP server 不存在時仍可正常運作（backward compatible）

## Rollback Plan

MCP server 是可選元件。移除 `.asp/mcp/server.py` 不影響任何現有 skill 或 hook。

## Not In Scope (v4.0)

- MCP server 實際實作（留 v4.1+）
- Authentication / authorization for MCP server
- Multi-project MCP server
- Real-time event streaming
