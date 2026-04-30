---
name: asp-team-pick
description: |
  Use when selecting the optimal agent team composition for a task.
  Handles: recommending agents based on task type and complexity, mapping scenarios
  to team configurations, explaining each agent's responsibilities.
  Triggers: team pick, 組團隊, recommend team, 哪些 agent, 推薦 agent,
  who should work on, 需要哪些 agent, 組什麼隊, 誰來做, which agents,
  team composition, 團隊組成.
---

# ASP Team Pick Skill

根據任務類型與複雜度推薦最佳 agent 團隊。本 skill 自包含，所有 scenario 直接內嵌，不依賴外部檔案。

## 使用方式

輸入：任務類型 + 複雜度描述
輸出：agent 清單 + 每個 agent 的職責說明 + pipeline 階段

---

## 場景對照表（完整內嵌自 team_compositions.yaml）

### NEW_FEATURE_simple
**適用**：無架構影響，< 5 個檔案，`assess_architecture_impact()` 回傳 `requires_adr: false`

| Agent | 職責 |
|-------|------|
| `spec` | 撰寫 SPEC 七欄位（Goal / Background / Inputs / Outputs / Edge Cases / Side Effects / Done-When） |
| `tdd` | 先寫測試（測試先 FAIL 後 PASS） |
| `impl` | 實作 production code，內部跑 auto_fix_loop |
| `qa` | 獨立驗證（不信任 impl 的自我回報） |
| `doc` | 文件同步、CHANGELOG 更新 |

**Pipeline 階段**：PLAN → FOUNDATION → BUILD → HARDEN → DELIVER
**並行**：否（循序執行）

---

### NEW_FEATURE_complex
**適用**：架構影響，> 15 個檔案，`requires_adr: true`

| Agent | 職責 |
|-------|------|
| `arch` | 建立 ADR，評估架構影響，設計決策文件 |
| `spec` | SPEC 撰寫（需引用 ADR） |
| `dep-analyst` | 依賴圖分析，識別並行邊界，防止循環依賴 |
| `tdd` | 跨模組測試策略，整合測試設計 |
| `impl` | 實作（可並行，依 dep-analyst 的模組邊界切割） |
| `integ` | 並行軌道匯流，解決 track 間衝突 |
| `qa` | 模組級 + 整合級獨立驗證 |
| `sec` | OWASP 掃描，憑證/敏感資訊審查 |
| `reality` | 懷疑主義驗收，反面測試（有 veto 權） |
| `doc` | 架構文件 + 使用文件同步 |

**Pipeline 階段**：SPECIFY → PLAN → FOUNDATION → BUILD → HARDEN → DELIVER
**並行**：是（依 dep-analyst 的模組邊界切割並行軌道）
**並行策略**：Split by module boundary from dep-analyst

---

### BUGFIX_trivial
**適用**：`classify_bug_severity()` 回傳 `severity == TRIVIAL`（affected_files <= 2，changed_lines <= 10，無條件邏輯變更）

| Agent | 職責 |
|-------|------|
| `impl` | 直接修復，說明豁免理由 |
| `qa` | 快速驗證修復正確性 |

**Pipeline 階段**：BUILD → HARDEN
**並行**：否

---

### BUGFIX_non_trivial
**適用**：`severity >= NON_TRIVIAL`，需要 SPEC + 重現測試

| Agent | 職責 |
|-------|------|
| `spec` | 建立 Bug SPEC（含根因、重現步驟、修復方案） |
| `tdd` | 先撰寫能重現 Bug 的測試（修復前必須 FAIL） |
| `impl` | 修復 + 全專案 grep 掃描相似位置 |
| `qa` | 獨立驗證，確認重現測試修復後 PASS |
| `doc` | Postmortem（若 Bug 影響 production 或重試 3+ 次） |

**Pipeline 階段**：PLAN → FOUNDATION → BUILD → HARDEN → DELIVER
**並行**：否

---

### BUGFIX_hotfix
**適用**：`request.is_production_incident == true`（生產事故快速通道）

| Agent | 職責 |
|-------|------|
| `impl` | 緊急修復，最小範圍變更 |
| `qa` | 快速驗證（聚焦問題點） |
| `sec` | 確認修復不引入新漏洞 |
| `doc` | 事後 Postmortem 必建 |

**Pipeline 階段**：BUILD → HARDEN → DELIVER
**並行**：否
**自動升級**：P0（自動觸發 asp-escalate）

---

### MODIFICATION_L1_L2
**適用**：`determine_change_level()` 回傳 L1（細節修改）或 L2（SPEC 推翻）

| Agent | 職責 |
|-------|------|
| `spec` | 修改或重建 SPEC，處理 L2 的半成品清理 |
| `tdd` | 更新測試（L2 可能需要刪除舊測試） |
| `impl` | 實作修改，評估已寫程式碼受影響範圍 |
| `qa` | 驗證修改後行為符合更新的 SPEC |
| `doc` | CHANGELOG 記錄變更原因 |

**Pipeline 階段**：PLAN → FOUNDATION → BUILD → HARDEN → DELIVER
**並行**：否

---

### MODIFICATION_L3_L4
**適用**：L3（ADR 推翻）或 L4（方向 pivot）— 需要完整 pipeline

| Agent | 職責 |
|-------|------|
| `arch` | 新 ADR 建立，舊 ADR 標記 Superseded |
| `spec` | 受影響 SPEC 逐個處理（更新或 Cancelled） |
| `dep-analyst` | 反向掃描所有引用舊 ADR/SPEC 的程式碼 |
| `tdd` | 新方向的測試策略 |
| `impl` | 雙軌道：舊系統清理 + 新系統實作 |
| `integ` | 新舊系統轉換期的整合處理 |
| `qa` | 全量驗證（不可用 test-filter） |
| `sec` | 新方向的安全影響評估 |
| `reality` | 確認 pivot 決策合理性，有 veto 權 |
| `doc` | Pivot ADR 文件 + session-checkpoint |

**Pipeline 階段**：SPECIFY → PLAN → FOUNDATION → BUILD → HARDEN → DELIVER
**並行**：是（舊系統清理 + 新系統建立雙軌道）
**並行策略**：Old system + new system dual tracks

---

### REMOVAL
**適用**：`execute_removal()` 完整依賴分析流程

| Agent | 職責 |
|-------|------|
| `dep-analyst` | 依賴清理順序分析（循序執行，不可並行） |
| `impl` | 依序移除，每步確認無遺留引用 |
| `qa` | 驗證移除後整體系統仍正常運作 |
| `reality` | 確認無殘留引用、無孤兒資料 |
| `doc` | 記錄移除原因，更新架構圖 |

**Pipeline 階段**：PLAN → BUILD → HARDEN → DELIVER
**並行**：否（依賴清理順序必須循序）
**注意**：Dependency cleanup order matters — cannot parallelize

---

### GENERAL
**適用**：任務複雜度不明，先 `decompose()` 分解後再個別匹配場景

| Agent | 職責 |
|-------|------|
| （動態決定） | 先執行 decompose()，每個子任務依自身情境匹配上方場景 |

**Pipeline 階段**：動態決定（依子任務場景）
**並行**：動態決定（依子任務依賴圖）

---

## 動態調整規則

執行過程中，以下情況會自動追加 agent：

| 觸發情況 | 追加 Agent | 原因 |
|----------|-----------|------|
| auto_fix_loop 耗盡 | `sec` | 可能是安全相關根因 |
| scope 超出預期 | `arch` | 需要架構重新評估 |
| 發現安全問題 | `sec`（若未在隊中） | 安全疑慮發現 |
| 並行軌道衝突 | `integ` | Track 匯流需要協調 |
| context budget > 60% | — | 建立 SESSION_BRIDGE 準備交接 |

---

## 領域驅動角色追加

偵測到 bug 根因領域時，追加對應 agent：

| 領域 | 追加 | 原因 |
|------|------|------|
| `auth` | `sec` | 認證問題需要安全審查 |
| `concurrency` | `dep-analyst` | 需要跨模組影響分析 |
| `api_contract` | `sec` + `dep-analyst` | 攻擊面 + 下游影響 |
| `data_integrity` | — （force_full_test） | 必須全量測試 |
| `state_machine` | — （force_state_scan） | 強制狀態依賴掃描 |
| `boundary` | — | 擴大 grep 到同模組所有比較運算 |
| `null_safety` | — | 掃描同模組所有未檢查 nullable 存取 |

---

## 輸出格式

回覆使用者時，輸出：

```
場景：{SCENARIO_NAME}
判定依據：{為什麼選這個場景}

推薦團隊：
- {agent}: {職責}
- {agent}: {職責}
...

Pipeline 階段：{階段列表}
並行策略：{並行/循序，若並行說明切割策略}

動態調整注意：{列出可能觸發額外追加的條件}
```