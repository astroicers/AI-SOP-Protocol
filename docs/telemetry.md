<!-- Last Updated: 2026-05-09 | Status: Active | Audience: L2+ users -->
# ASP Telemetry 使用指南

> Telemetry 系統以 JSONL append-only 格式記錄 session 事件，供後期分析使用。
> 詳細技術決策：[ADR-004](adr/ADR-004-asp-telemetry.md)

---

## 快速開始

```bash
# 記錄一次 session_start 事件
python3 .asp/scripts/telemetry/collect.py

# 查看統計報告
python3 .asp/scripts/telemetry/report.py

# 清理 90 天前的舊記錄
python3 .asp/scripts/telemetry/prune.py

# Makefile 捷徑
make asp-telemetry-collect
make asp-telemetry-report
make asp-telemetry-prune
```

---

## 事件類型（Event Types）

| event_type | 說明 | 記錄時機 |
|-----------|------|---------|
| `session_start` | Session 啟動事件，由 `collect.py` 寫入 | SessionStart hook 執行時 |
| `bypass` | Skill 繞過記錄；`data.skill` 欄位記錄被繞過的 skill | `asp-ship` Step 10 繞過時 |
| `gate_pass` | 品質門通過；`data.gate_id` 記錄門號（G1–G6） | `asp-gate` PASS 時 |
| `gate_fail` | 品質門未通過；`data.gate_id` 記錄門號（G1–G6） | `asp-gate` FAIL 時 |
| `multi_agent.dispatch` | SPEC-004 dispatch 建立 worktree | `dispatch.sh` 每個 task 建 worktree 後 |
| `multi_agent.converge` | SPEC-004 task merge 成功並 cleanup worktree | `converge.sh` per-task 成功 merge 後 |
| `multi_agent.fail` | SPEC-004 task 失敗（衝突 / scope_violation 等） | `converge.sh` 衝突；scope 違規時 |
| `multi_agent.gc` | SPEC-004 stale worktree 被 GC 清理 | `worktree-gc.sh` 移除 stale worktree 時 |

---

## JSONL Schema

每一行是一個獨立的 JSON 物件（`session_start` 範例）：

```json
{
  "ts": "2026-05-09T10:00:00+00:00",
  "event_type": "session_start",
  "asp_version": "4.0.0",
  "data": {
    "blockers": 0,
    "warnings": 0,
    "profile_type": "unknown"
  }
}
```

| 欄位 | 型別 | 說明 |
|------|------|------|
| `ts` | ISO 8601 string | 事件時間（UTC+offset） |
| `event_type` | string | 事件分類（見上表） |
| `asp_version` | string | 記錄時的 ASP 版本 |
| `data` | object | 事件詳細資料（依 event_type 不同） |
| `data.blockers` | int | session_start：BLOCKER 數量 |
| `data.warnings` | int | session_start：WARNING 數量 |
| `data.profile_type` | string | session_start：`.ai_profile` 的 type 值 |
| `data.skill` | string | bypass：被繞過的 skill 名稱 |
| `data.gate_id` | string | gate_pass/gate_fail：門號（"G1"–"G6"） |

### SPEC-004 multi_agent.* 事件 schema

`multi_agent.*` 事件使用平鋪結構（`event` 取代 `event_type`，無 `data` 包裝、無 `asp_version` 欄位）由 `audit-write.sh` wrapper 寫入主 repo `.asp-telemetry.ndjson`：

```jsonc
// dispatch
{"event": "multi_agent.dispatch", "task_id": "TASK-001",
 "worktree": ".asp-worktrees/task-001", "branch": "feat/spec-004-task-001"}

// converge success
{"event": "multi_agent.converge", "task_id": "TASK-001", "status": "success"}

// fail (per-task conflict or scope_violation)
{"event": "multi_agent.fail", "task_id": "TASK-002", "status": "task_merge_conflict",
 "conflict_files": "src/shared/util.go"}
// status 取值：task_merge_conflict | base_branch_rebase_conflict |
//             worktree_missing | branch_missing | scope_violation

// gc
{"event": "multi_agent.gc", "task_id": "TASK-001", "age_seconds": 18000}

// dispatch_rejected (mock HITL mode only)
{"event": "multi_agent.dispatch_rejected", "reason": "max_parallel_exceeded",
 "count": 11}
```

> **Schema note (v4.1)**：`multi_agent.*` 事件刻意使用平鋪結構是 SPEC-004 的選擇，與 `session_start / bypass / gate_*` 的 nested-data 結構不同。`report.py` 在 v4.1 階段 best-effort 顯示這些事件的計數，不解讀內部欄位。v4.2 規劃統一 schema（要嘛全部平鋪、要嘛全部 nested），屆時會發 ADR 記錄取捨。

`python3 .asp/scripts/telemetry/report.py` 輸出五個區塊：

| 區塊 | 說明 |
|------|------|
| **總事件數** | JSONL 中所有事件的總計 |
| **事件類型分布** | 各 event_type 的計數 |
| **最常被繞過的 skill（Top 5）** | `bypass` 事件中 `data.skill` 的頻次排名 |
| **Gate 通過率（G1–G6）** | 每個門的 pass/fail 計數與通過率 % |
| **Session 數** | `session_start` 事件總計（= 啟動次數） |

---

## 資料位置與保留政策

| 項目 | 說明 |
|------|------|
| 資料檔案 | `.asp-telemetry.jsonl`（專案根目錄） |
| 格式 | JSONL（每行一個 JSON 事件，append-only） |
| 保留期限 | 90 天（`prune.py` 依 `ts` 欄位清理） |
| 可見性 | 本機只讀，不上傳任何遠端服務 |
| Git 追蹤 | `.asp-telemetry.jsonl` 已列入 `.gitignore`（含個人 session 資料） |

---

## 進階：手動寫入自訂事件

`collect.py` 目前只寫入 `session_start`。若需記錄 `bypass` 或 `gate_pass/gate_fail` 事件，可直接 append JSONL：

```bash
echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","event_type":"bypass","asp_version":"4.0.0","data":{"skill":"asp-ship"}}' \
  >> .asp-telemetry.jsonl
```

或使用 `make asp-bypass-record`（透過 `.asp/Makefile.inc` 的 `asp-bypass-record` target）。