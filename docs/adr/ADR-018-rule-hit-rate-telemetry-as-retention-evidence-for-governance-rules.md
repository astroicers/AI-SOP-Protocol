# [ADR-018]: Rule hit-rate telemetry as retention evidence for governance rules

| 欄位 | 內容 |
|------|------|
| **狀態** | `FIRM` |
| **日期** | 2026-06-11 |
| **決策者** | astroicers（v5 簡報 Phase 5 + 方案 A 裁決）+ AI（registry/統計設計） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

v5 原則 5：「任何規則的存留以命中率數據為準，不憑感覺」。現況沒有任何機制記錄「哪條規則實際攔過什麼」——規則的增刪全憑直覺與個案記憶，正是散文治理層膨脹到 28,846 行的根因之一。本 ADR 給每條治理規則一個穩定 `rule_id`，在既有 hook 觸發點計數，並提供 `make rule-stats` 把「90 天零命中」規則列為待刪候選。

**範圍裁決（使用者 2026-06-11 定案 = 方案 A 極簡版）**：只在既有 session-audit.sh 評估點與動態 deny 注入點計數；**不加 PreToolUse 觀測 hook**。已查證（Claude Code 官方文件）：PreToolUse hook 先於權限規則執行、scoped deny 可被觀測——方案 B（觀測 hook）技術可行，但每個 Bash 呼叫 +1 hook 進程、settings 模板與升級遷移面擴大，與「極簡版」及反過度設計原則（ADR-010 教訓）相悖。代價：12 條靜態 deny pattern 無「實際阻擋」數據，於 registry 標 `observed_by: none`，**歸類「不可觀測」而非「待刪候選」**（防誤刪鐵則執行面）。

---

## 評估選項（Options Considered）

### 選項 A：session-audit 評估點計數（採用，使用者裁決）

- **優點**：零新 hook、零每呼叫延遲；寫入點全在 Iron Rule A 保護的檔案內；Done When（Draft ADR 阻擋有 JSONL 記錄）由 `AUDIT-A3.1` + `DENY-DYNAMIC` 兩事件滿足。
- **缺點**：靜態 deny 12 條永遠無命中數據（標不可觀測）。
- **風險**：審計時計數 ≠ 實際阻擋次數——已知語意差異，registry `observed_by` 欄位明示每條規則的觀測方式，rule-stats 報表分類呈現。

### 選項 B：A + PreToolUse 觀測 hook（deny-observer，只記錄不阻擋）

- **優點**：12 條靜態 deny 取得真實嘗試率。
- **缺點**：每個 Bash 呼叫 +1 進程（~10-30ms）；settings 模板 + 既有專案升級三處同步；新增 Iron Rule A 覆蓋決策。
- **風險**：為「也許有用的數據」加常駐運行面——使用者明確選 A。

### 選項 C：要求 LLM 在 skill 執行時自行 append 計數

- **優點**：覆蓋 G1-G6 等 skill 層規則。
- **缺點**：LLM 步驟可被略過、格式漂移——「遙測本身不確定」是自我矛盾。
- **風險**：數據可信度為零。G1-G6 改從 `.asp-gate-log/` 檔案**機械統計**（SPEC-006 既有產物）。

---

## 決策（Decision）

### 1. `rule_id` 註冊表：`.asp/config/rule-registry.yaml`

扁平 schema（awk/grep 可解析）：`id` / `desc` / `source` / `observed_by`（session-audit｜gate-log｜manual｜none）/ `exempt`（預設 false）。涵蓋：
- `CLAUDE-IR-1..4`（4 條 CLAUDE.md 鐵則）+ `IRON-A/B/C` —— **全部 `exempt: true`（紅線 1：鐵則語意不變，不適用 90 天刪除條款）**
- `GATE-G1..G6` —— `observed_by: gate-log`（機械掃 `.asp-gate-log/*.md` frontmatter）
- `DENY-01..12`（denied-commands.json 逐條，pattern 抄入 desc）—— `observed_by: none`（方案 A）；`DENY-DYNAMIC` —— `observed_by: session-audit`
- `AUDIT-*`（session-audit 規則點：IRON-A/B、A1.3/A1.4/A1.5、A3.1/A3.2、A4.7、A5.3/A5.4/A5.9、A8.3、A9.2、A14.1/A14.2、A15.1、A16.1/A16.2）

### 2. 寫入端：session-audit.sh 內建 `asp_metric()`（~14 行，不另立腳本）

`{ts, project, rule_id, action}` 單行 JSON（jq 組裝防注入）append 至 `~/.claude/asp/metrics/rule-hits.jsonl`（`ASP_METRICS_FILE` env 可覆寫供測試）。沿 audit-write.sh 的 POSIX O_APPEND pattern（<4096 bytes）。**所有失敗吞掉、恆 return 0**——遙測永不影響主流程（紅線：hook 恆 exit 0）。注入點 = 每個 `BLOCKERS+=/WARNINGS+=/INFOS+=` 旁一行 + 動態 deny 實際注入成功處（`DENY-DYNAMIC deny-inject`）。

### 3. 統計端：`.asp/scripts/rule-stats.sh` + `make rule-stats`

`[--days N(=90)] [--project NAME]`；從 registry **枚舉全部 rule_id（零命中必出現）**；輸出 `rule_id | hits | last_hit | disposition`，disposition ∈ `active`／`待刪候選`（零命中 ∧ 非 exempt ∧ observed_by ∉ {none, manual}）／`不可觀測`／`鐵則豁免`。G1-G6 計數 = 90 天窗內 `.asp-gate-log/*.md` 的 `gate:` frontmatter 機械統計。退出碼：0 正常（含有候選）｜2 registry 缺失。

### 4. 治理原則入憲（CLAUDE.md 鐵則章節加註）

「規則存留以命中率為準：`make rule-stats` 顯示 90 天零命中的規則，於下個 minor 版本移除。**鐵則（CLAUDE-IR-1..4、IRON-A/B/C，registry `exempt: true`）豁免此條**（紅線 1）；移除動作本身仍走 ADR。」

### 5. 配套：asp-gate.md 一行措辭——gate log 寫入（SPEC-006 schema）從 asp-plan auto-gate 專屬提升為**所有** `/asp-gate` 評估的要求（讓 G3-G6 也累積機械可統計的記錄）。

回滾方式：單 commit revert；registry/rule-stats 純新增；session-audit 注入行為 no-op 副作用（revert 即消失）；`~/.claude/asp/metrics/` 殘留無害（uninstall 整目錄移除涵蓋）。

---

## 後果（Consequences）

**正面影響：**
- 規則增刪首次有數據依據；「待刪候選」清單機械產出。
- 與 showcase telemetry 區隔明確：規則命中遙測屬 **Core**（治理證據），session 事件量測屬 Showcase。

**負面影響 / 技術債：**
- 審計時計數的語意限制（見選項 A 風險）；靜態 deny 無數據（方案 B 留檔可後補，屆時另開 ADR）。
- gate-log 統計初期主要覆蓋 G1/G2（auto-gate 穩定產出），G3-G6 隨措辭生效逐步累積——初期零命中屬資料累積期而非待刪訊號，rule-stats 註記。

**後續追蹤：**
- [ ] 90 天後（≈2026-09-09）首次正式 rule-stats 審視，產出第一批待刪候選
- [ ] 方案 B 評估（若靜態 deny 的存留爭議出現）

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| Draft ADR 阻擋有記錄 | fixture 觸發 → jsonl 含 `AUDIT-A3.1` 與 `DENY-DYNAMIC`，每行 jq 合法 | `tests/test_rule_metrics.sh` | 每次 make test |
| 遙測永不影響主流程 | 唯讀目錄模擬 → hook exit 0、briefing 仍生成、無 stderr 噪音 | 同上 | 每次 |
| 全 id 枚舉 | rule-stats 輸出含 registry 全部 id（零命中必列） | `tests/test_rule_stats.sh` | 每次 |
| registry ↔ 程式碼防漂移 | session-audit 內 `asp_metric` id 集合 ⊆ registry；DENY 條數 = denied-commands.json 長度 | `tests/test_rule_registry.sh` | 每次 |

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：方案 A/B 裁決（使用者 2026-06-11；PreToolUse 順序查證記錄於 v5 PR）、SPEC-006（gate-log schema = G 計數來源）、ADR-011（hook 寫入面隔離先例）、ADR-017（telemetry 的 Core/Showcase 分界）、**ADR-004**（session 事件量測 `.asp-telemetry.jsonl`——與本 ADR 的 rule-hits 為平行 pipeline、路徑與用途不同、互不覆蓋；G1 review F-8）
- 設計補註（G1 review F-2/F-9）：IRON-C 位於 global_core 散文層、無機械觀測點 → registry `observed_by: manual`（與 CLAUDE-IR-2/4 同類，rule-stats 歸「不可觀測」）；GATE-G3..G6 帶 `enabled_since: 2026-06-11`，rule-stats 在統計窗短於啟用期時標「資料累積期」而非待刪候選

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | branch `asp/v5-slimming`：test_rule_metrics / test_rule_stats / test_rule_registry 全綠；本 repo 實際 fire 記錄 |
| **驗證日期** | 2026-06-11 |
| **驗證者** | astroicers（2026-06-11 對話 blanket 授權 ADR-015~018；AI 代筆狀態變更） |
| **驗證摘要** | 規則命中遙測（方案 A）：穩定 rule_id 註冊表 + 評估點計數 + 90 天零命中待刪報表，失敗永不影響主流程 |
