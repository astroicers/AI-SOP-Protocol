# ADR-003: ASP MCP Server 採用 Python 實作

**Status:** Accepted
**Date:** 2026-04-29
**Deciders:** astroicers

## Context

ASP 目前的操作介面是 Markdown skill 文件（Claude Code skill）和 Bash hook（session-audit.sh）。
隨著 v4.0 的 telemetry 系統和更複雜的 gate 評估需求，我們需要一個結構化的程式化 API 面：
讓 Claude Code agent 能以 structured tool call 的方式操作 ASP governance，
而非依賴文字觸發詞和 skill Markdown 文件。

MCP（Model Context Protocol）是 Anthropic 支援的標準工具介面，適合做 ASP 的程式化 API 層。

## Options Considered

### Option A: TypeScript (Node.js)
- **Pro:** Anthropic 官方 reference implementation，社群資源豐富
- **Con:** 引入 Node.js/npm 依賴，與 ASP 現有 Python 腳本生態不一致

### Option B: Python
- **Pro:** 與 `.asp/scripts/rag/*.py` 相容，複用現有 Python 基礎設施；`mcp` Python package 已有官方支援
- **Con:** Python MCP 生態相對 TypeScript 較新

### Option C: Bash + JSON
- **Pro:** 無新依賴
- **Con:** 難以維護 stateful tool 響應；JSON schema validation 困難；長期維護成本高

## Decision

採用 **Python (Option B)**。

理由：
1. ASP 現有 RAG 腳本（`.asp/scripts/rag/*.py`）已建立 Python 基礎設施，同語言降低維護負擔
2. Anthropic 官方 `mcp` Python package（`pip install mcp`）已提供穩定 SDK
3. Telemetry 腳本（Track E）也用 Python，集中在同一生態

初始工具集（6 個 tool）：
1. `asp_gate_evaluate(gate_id, context_json)` — 評估 G1-G6 gate 是否通過
2. `asp_audit_quick()` — 快速審計（只看 blocker）
3. `asp_bypass_log(skill, step, reason)` — 記錄 bypass 事件到 .asp-bypass-log.json
4. `asp_telemetry_push(event_type, data_json)` — 推送 telemetry 事件
5. `asp_handoff_create(type, context_json)` — 建立交接 YAML 文件
6. `asp_fact_check_log(claim, source, verdict)` — 記錄事實查證結果

MCP server 在 v4.0 是 ADR + SPEC（設計），實作留 v4.1+。

## Consequences

**Positive:**
- ASP 有結構化 API 面，不再依賴文字觸發詞
- Telemetry 事件可程式化推送（不只是 script 呼叫）
- 未來可整合到 multi-agent orchestration 的 tool use 流程

**Negative:**
- 需要 `mcp` Python package（`pip install mcp`）
- MCP server 為**可選**：skill 無 server 時仍可運作（backward compatible）
- v4.0 只有設計，實作在 v4.1+（短期內無法使用）

## Related Documents
- `docs/specs/SPEC-002-asp-mcp-server.md` — 詳細規格
- `docs/adr/ADR-004-asp-telemetry.md` — Telemetry 決策
