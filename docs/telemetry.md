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

---

## 報告解讀（Reading the Report）

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