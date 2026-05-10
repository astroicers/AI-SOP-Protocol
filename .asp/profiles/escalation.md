# Escalation Profile — P0-P3 嚴重度路由（v4.x 縮版）

<!-- requires: global_core -->
<!-- optional: multi_agent, autonomous_dev, pipeline -->
<!-- conflicts: (none) -->

適用：agent 無法繼續時的分級升級。提供「載入時的條件分支標記」+「觸發點映射表」。
**P0-P3 詳細決策樹與處理流程已 100% 內嵌於 `/asp-escalate` skill**（self-contained）。

載入條件：`mode: multi-agent` 或 `autonomous: enabled` 時自動載入

> **v4.x 設計原則**（profile vs skill 分工）：
> - **Profile（本檔）**：靜態定義 — 嚴重度表、觸發點映射、其他 profile 的 `IF escalation_loaded` 條件分支
> - **Skill（`/asp-escalate`）**：動態執行 — P0-P3 流程、PAUSE_ALL_TRACKS / NOTIFY_HUMAN / 重派決策樹、escalation log YAML schema
> - **取代歷史**：v3.x 的 escalation.md 含 84 行 P0-P3 pseudocode，與 skill 重複；v4.1.x cleanup 移除（commit 2026-05-10），保留路由表 + 觸發點映射 + 跨 profile 關係

---

## 嚴重度定義

| 等級 | 名稱 | 判定條件 | 回應行動 | 處理者 |
|------|------|----------|----------|--------|
| **P0** | 緊急 | 安全漏洞、資料遺失風險、生產環境中斷 | 立即暫停所有並行軌道 + 通知人類 | Orchestrator + 人類 |
| **P1** | 高 | auto_fix + Orchestrator 重派全耗盡；並行軌道不可解衝突 | 暫停當前軌道，其他軌道繼續 | Orchestrator（嘗試解決）或人類 |
| **P2** | 中 | 單一模組 QA fail 3x；scope 超出；意外依賴 | 重新分派或增援 | Orchestrator |
| **P3** | 低 | Tech debt 累積；文件過期；非阻斷警告 | 記入 backlog | 自動記錄 |

詳細決策樹（PAUSE_ALL_TRACKS / NOTIFY_HUMAN / 升級規則）：見 `/asp-escalate` skill。

---

## 觸發點映射

下游 profile / skill / hook 觸發 escalation 時的標準路由：

| 觸發來源 | 原有機制 | 新的升級路由 |
|----------|---------|------------|
| `auto_fix_loop` 振盪偵測 | `PAUSE_AND_REPORT(oscillation)` | `escalate(P2)` |
| `auto_fix_loop` 級聯偵測 | `PAUSE_AND_REPORT(cascade)` | `escalate(P2)` |
| `auto_fix_loop` 偷渡偵測 | `PAUSE_AND_REPORT(smuggling)` | `escalate(P1)` — 偷渡較嚴重 |
| `auto_fix_loop` 重試耗盡 | `on_worker_auto_fix_exhausted()` | `escalate(P2)` → Orchestrator 重派 |
| Orchestrator 重派 2 次仍失敗 | `escalate_to_human()` | `escalate(P1)` |
| 安全審查發現漏洞 | （無） | `escalate(P0)` |
| 生產環境事故 | `execute_hotfix()` | `escalate(P0)` |
| 品質門重試 2 次失敗 | （無） | `escalate(P2)` |
| Dev↔QA 迴路模組 3x 失敗 | （無） | `escalate(P2)` |
| 並行軌道不可解衝突 | （無） | `escalate(P1)` |
| Tech debt 累積 | `LOG_TECH_DEBT()` | `escalate(P3)` |
| SPEC-004 worktree 衝突無法 rebase | （v4.1 新增） | `escalate(P1)` — converge.sh 自動寫 escalation log |

---

## 升級函數（→ skill）

profile 不再內嵌 `FUNCTION escalate(severity, reason, task_id, context)` 完整 pseudocode。
AI 收到「需要 escalation」訊號時，請呼叫 `/asp-escalate` skill，傳入相同參數，由 skill 的決策樹處理：
- P0 → PAUSE_ALL_TRACKS + NOTIFY_HUMAN + autopilot state 更新
- P1 → PAUSE_TRACK + Orchestrator 嘗試解決 → 失敗則 NOTIFY_HUMAN
- P2 → 嘗試 reassign → 不可則升 P1
- P3 → LOG_TECH_DEBT

---

## 與其他 Profile 的關係

```
escalation.md（本檔，靜態路由表）
  ├── 取代 autonomous_dev.md 中的 PAUSE_AND_REPORT()
  ├── 取代 multi_agent.md 中的 escalate_to_human()
  ├── 整合 pipeline.md（品質門失敗的升級路由）
  ├── 整合 /asp-dev-qa-loop skill（模組級失敗的升級路由；v4.x 取代 dev_qa_loop.md profile）
  ├── 整合 autopilot.md（P0 時更新 autopilot state）
  └── 整合 SPEC-004 converge.sh（worktree merge / rebase 衝突自動寫 escalation log）

/asp-escalate skill（動態執行）
  ├── 讀取本 profile 的觸發點映射表決定 severity
  ├── 執行 P0-P3 決策樹
  └── 寫入 .asp-escalation.ndjson（v4.1 SPEC-004 引入；audit-write.sh wrapper）
```

`IF escalation_loaded` 條件分支（其他 profile 內）：
- `autonomous_dev.md:143` — 若本 profile 已載入則用 `escalate()`，否則 fallback `PAUSE_AND_REPORT()`
- `multi_agent.md:289-295` — 同上
- 這些 fallback 永遠不會觸發（escalation 是 multi-agent / autonomous 的 auto-load 條件之一），但保留條件分支讓 profile 可以單獨在 L2 / L3 啟用

---

## 變更歷史

- **2026-05-10 (v4.1.1 cleanup wave 3 group A)**：profile 從 115 行縮為 ~75 行。刪除 P0-P3 詳細 pseudocode（與 `/asp-escalate` skill 100% 重複），保留嚴重度表 + 觸發點映射 + 跨 profile 關係。新增 SPEC-004 converge 衝突的觸發點對應。
- **2026-04-28 (v3.7.0)**：原 profile 引入 escalation 機制，含完整 P0-P3 pseudocode。
