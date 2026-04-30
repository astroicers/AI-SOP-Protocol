---
name: asp-escalate
description: |
  Use when an issue requires escalation in ASP multi-agent workflows.
  Handles: P0-P3 severity classification, escalation routing decisions,
  generating ESCALATION handoff YAMLs, handling critical issues and blockages.
  Triggers: escalate, escalation, P0, P1, P2, P3, 緊急, 卡住了, stuck, blocked,
  critical issue, 無法繼續, 升級, pause and report, 需要升級, cannot proceed,
  security vulnerability, production down, qa fail 3x.
---

# ASP Escalate Skill

處理 agent 無法繼續時的分級升級。本 skill 自包含，P0-P3 決策樹直接內嵌，不依賴外部 profile。

## P0-P3 嚴重度定義

| 等級 | 名稱 | 判定條件 | 回應行動 | 處理者 |
|------|------|----------|----------|--------|
| **P0** | 緊急 | 安全漏洞、資料遺失風險、生產環境中斷 | 立即暫停所有並行軌道 + 通知人類 | Orchestrator + 人類 |
| **P1** | 高 | auto_fix + Orchestrator 重派全耗盡；並行軌道不可解衝突 | 暫停當前軌道，其他軌道繼續 | Orchestrator（嘗試解決）或人類 |
| **P2** | 中 | 單一模組 QA fail 3x；scope 超出；意外依賴 | 重新分派或增援 | Orchestrator |
| **P3** | 低 | Tech debt 累積；文件過期；非阻斷警告 | 記入 backlog | 自動記錄 |

---

## 決策樹：判斷嚴重度

```
問題發生 → 先問：
  1. 是否涉及安全漏洞 / 資料遺失 / 生產環境中斷？
     YES → P0（最嚴重，立即暫停一切）

  2. 是否已重試 2+ 次且仍無法解決？或存在跨軌道不可解衝突？
     YES → P1（暫停當前軌道，Orchestrator 接管）

  3. 是否為單一模組 QA fail 3x / scope 超出 / 意外依賴？
     YES → P2（重新分派或增援）

  4. 以上皆否（tech debt、文件過期、非阻斷警告）？
     → P3（記入 backlog）
```

---

## 觸發點對照表

| 觸發來源 | 嚴重度 |
|----------|--------|
| 安全審查發現漏洞 | P0 |
| 生產環境事故 | P0 |
| auto_fix_loop 振盪偵測 | P2 |
| auto_fix_loop 級聯偵測 | P2 |
| auto_fix_loop 偷渡偵測 | P1（偷渡較嚴重） |
| auto_fix_loop 重試耗盡 → Orchestrator 重派 2 次仍失敗 | P1 |
| auto_fix_loop 重試耗盡（僅第一次） | P2 |
| 品質門重試 2 次失敗 | P2 |
| Dev↔QA 迴路模組 3x 失敗 | P2 |
| 並行軌道不可解衝突 | P1 |
| Tech debt 累積 | P3 |
| 文件過期 | P3 |

---

## 執行流程

### P0 流程

```
1. 立即停止所有工作（multi-agent 模式下暫停所有並行軌道）
2. 生成 ESCALATION handoff（見下方 YAML 模板）
3. 通知人類，說明：
   - 問題描述（一句話）
   - 已嘗試的修復（列表）
   - 當前系統狀態
4. 等待人類明確指示，不可自行繼續
5. 若 autopilot 模式：標記 task status=failed, exit_reason="P0_escalation"
```

### P1 流程

```
1. 暫停當前軌道（其他軌道可繼續）
2. 生成 ESCALATION handoff
3. Orchestrator 嘗試解決：
   - 若 Orchestrator 可解決 → 解決後 RESUME_TRACK
   - 若 Orchestrator 無法解決 → 升級通知人類
```

### P2 流程

```
1. 生成 ESCALATION handoff
2. 嘗試重新分派（REASSIGNMENT）：
   - 若可重派 → 建立 REASSIGNMENT handoff，選擇替代 agent
   - 若無法重派 → 升級為 P1
3. 使用 asp-handoff 建立 REASSIGNMENT 交接單
```

### P3 流程

```
1. 記錄 tech debt（格式：tech-debt: [HIGH|MED|LOW] [CATEGORY] description (DUE: YYYY-MM-DD)）
2. 繼續原本工作，不中斷
3. P3 不需要建立 ESCALATION handoff（除非追蹤用）
```

---

## 生成 ESCALATION Handoff YAML

使用 `asp-handoff` skill 的 ESCALATION 類型模板，填入以下欄位：

```yaml
handoff_type: ESCALATION
task_id: "TASK-{NNN}"
timestamp: "{現在時間 ISO 8601}"
from_agent:
  role: "{你的 agent 角色}"
severity: "{P0|P1|P2|P3}"

reason: |
  {一句話說明問題：什麼時機、什麼模組、什麼錯誤}

attempted_fixes:
  - description: "{第一次嘗試}"
    result: "{結果：oscillation/cascade/fail/pass}"
  - description: "{第二次嘗試（若有）}"
    result: "{結果}"

context_snapshot:
  test_output: |
    {完整的測試輸出，不可摘要}
  files_affected:
    - "{修改過的檔案路徑}"
  current_state: |
    {當前 codebase 狀態描述}
  spec_reference: "{SPEC-NNN（若有）}"

escalation_target: "{human|orchestrator|{agent_role}}"
```

輸出路徑：`.asp/handoffs/HANDOFF-{YYYYMMDD}-ESCALATION.yaml`

---

## 標準回覆格式（向使用者報告）

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