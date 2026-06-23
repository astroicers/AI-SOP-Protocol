# [ADR-021]: Adopt official Claude Code plugin marketplace as primary distribution channel

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-23 |
| **決策者** | ASP framework maintainers（待人類核准） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）
>
> ⬆️ 由 `Draft` 升 `Accepted`：使用者 2026-06-23 透過 `/asp:approve-adr ADR-021` 呼叫、看完本指令摘要的決策（選項 C）與 Verification Evidence（POC-1/POC-2 待填、外部事實已於 FC-004 查證）後明確同意直升（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。直升取捨：外部 plugin 機制事實已查證，ASP 動態 deny 端到端 POC（POC-1）留待 P1 實作時補。

---

## 背景（Context）

外部評估（借鏡 `davepoon/buildwithclaude` 3.1k★ 分發典範；來源見 ADR-020 記錄之外部評估、及反思報告 P1）指出 ASP 的分發層是負債：

- **自製 installer 過重**：`.asp/scripts/install.sh`（~29KB）+ `install.ps1` + 全域 `~/.claude/asp/` sync，分 Phase 1（user-level）/ Phase 2（project-level）。
- **sync 漂移已成工程稅**：`test_asp_sync_downgrade`、`test_managed_deny_reconcile`、`test_asp_commands_sync` 等測試的**存在本身**就是自製分發機制易漂移的症狀——把「保持同步」變成持續維護負擔。
- **零生態可發現性**：未掛任何官方 plugin marketplace，外部使用者無從 discover/一鍵安裝。

同期 Claude Code 已提供**官方 plugin + marketplace 機制**。ASP 賴以為生的強制力（SessionStart 審計、PreToolUse commit 閘）是否能由官方機制承載，是本決策的關鍵風險——**已於 FC-004 查證官方文件確認**（見 `.asp-fact-check.md`）：

- `hooks/hooks.json` 支援 **SessionStart**、**PreToolUse（可 block tool call）** 事件；`${CLAUDE_PLUGIN_ROOT}` 可引用 bundled 腳本；plugin 可打包 skills/agents/commands/hooks/MCP。
- `.claude-plugin/marketplace.json` + `/plugin marketplace add <owner/repo>`（GitHub 直接 host，含 private repo）一鍵安裝；省略 `version` 走 git 時 **commit SHA = 版本**（自動更新）。

故「以官方機制承載 ASP」屬**低風險、高信心**，而非探索性賭注。

---

## 評估選項（Options Considered）

### 選項 A：維持現狀（自製 installer + 持續修 sync 測試）

- **優點**：不動現有使用者；完全控制安裝行為（含離線）。
- **缺點**：29KB installer 維護成本高；sync 漂移稅持續；零生態可發現性，外部採用門檻不降。
- **風險**：分發層複雜度只增不減，與報告「治理過載」病徵同源。

### 選項 B：完全改用 marketplace（移除自製 installer）

- **優點**：最大化可發現性與自動更新；徹底砍掉 sync 漂移測試。
- **缺點**：失去離線/進階安裝路徑；既有使用者遷移斷裂；遷移風險一次性集中。
- **風險**：兩個 FC-004 殘留（hook 寫 `settings.local.json`、命名空間遷移）若 POC 不過，無退路。

### 選項 C：marketplace 為主 + installer 降為進階/離線次要路徑（**採用**）

- **優點**：取得可發現性與自動更新；自製 installer 保留為「進階/離線」備援，遷移可漸進；命名向 buildwithclaude 慣例對齊。
- **缺點**：過渡期雙路徑並存，短期維護面變大。
- **風險**：雙路徑語意需清楚劃分，避免使用者混淆——以「marketplace = 預設、installer = 進階」文件契約收斂。

---

## 決策（Decision）

採用 **選項 C**：把 ASP 重新封裝為標準 Claude Code plugin、以 **`.claude-plugin/marketplace.json` + `/plugin marketplace add` 作為主要分發機制**，自製 `install.sh` 降為「進階/離線」次要路徑，並隨之退役一整批 sync 漂移測試。命名向職責前綴慣例對齊以降低外部認知成本。

> 本決策為 `Draft` 提案——**禁止對應生產代碼**，待人類核准（並完成下方兩項 POC 驗收）後方可實作。封裝拆解須與 **ADR-017**（core / experimental / showcase 分離）對齊：plugin 應反映分層，而非把所有元件糊成一包。

---

## 後果（Consequences）

**正面影響：**
- 一鍵安裝 + 自動更新（commit/version），外部採用門檻大降、可發現性從零到有。
- 退役自製 installer 主路徑與 `test_asp_sync_downgrade` / `test_managed_deny_reconcile` / `test_asp_commands_sync` 等漂移測試，砍掉持續維護稅。

**負面影響 / 技術債：**
- **動態 deny 必須留在 hook 端**：FC-004 確認 plugin `settings.json` 目前僅支援 `agent`/`subagentStatusLine` 兩鍵，ASP L2 動態 deny（寫 `settings.local.json`）不能改走 plugin settings.json，須維持 hook 寫檔（與下方 POC-1 同一驗收，呼應 ADR-011）。
- **命名空間遷移**：plugin skill 一律 namespaced（`/plugin-name:skill`），現 `/asp <意圖>` router 改 plugin 後呼叫名會變（如 `/asp:...`），需處理既有 docs 與使用者肌肉記憶（與報告 §2 mono-router 議題相連）。
- 過渡期 marketplace + installer 雙路徑並存，維護面短期變大。

**後續追蹤：**
- [ ] **POC-1**：證實 plugin hook 能動態寫 `settings.local.json`（FC-004 殘留 1，承載 ASP L2）。
- [ ] **POC-2**：命名空間遷移盤點——列出所有受影響的呼叫名與 docs，給遷移/相容方案。
- [ ] 與 ADR-017 對齊 plugin 封裝邊界。**初步框（待 POC 確認，非定案）**：core plugin 含 daily-driver 強制力（`.asp/hooks/` 的 session-audit + ship-gate）+ skills + commands；experimental 多代理與 showcase（telemetry / RAG / ai-performance）維持獨立、**不入** core plugin（呼應 ADR-017 分層）；自製 installer 的「進階/離線」路徑承載 plugin 機制未涵蓋的部分。
- [ ] 過渡期文件契約：「marketplace = 預設、installer = 進階/離線」。

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 安裝步驟數（新使用者） | 由「clone + 跑 29KB script」降到 `/plugin marketplace add` 一步 | 人工走查 quickstart | 實作完成時 |
| 強制力等價 | SessionStart 審計 + PreToolUse commit 閘在 plugin 安裝下行為等同現狀 | `tests/test_pretooluse_ship_gate.sh` + session-audit 實測 | POC-1 完成時 |
| sync 漂移測試淨減 | ≥ 3 個 sync-drift 測試退役且無回歸 | `make test` 綠 + 測試清單 diff | 實作完成時 |

> **重新評估條件**：若 POC-1（hook 寫 settings.local.json）不可行，或官方變更 plugin hook 事件集合 / marketplace schema（FC-004 再驗證條件觸發）→ 退回選項 A 或重議。

---

## 關聯（Relations）

- 取代：（無——新增分發機制，非取代既有 ADR）
- 被取代：（無）
- 參考：
  - **ADR-017**（core / experimental / showcase 分離）——plugin 封裝須反映此分層
  - **ADR-003**（MCP server 取消 → user-level skill 架構）——分發策略歷史脈絡；skill 使用者端路徑（現由 installer 複製 `~/.claude/skills/asp/`）改由 plugin 承載或仍留 installer，待 POC-2 封裝盤點確認
  - **ADR-011**（動態 deny 隔離於 settings.local.json）——本案動態 deny 留 hook 端的依據
  - **ADR-013 / ADR-016**（v5 slimming / profile 編譯）——install 與 profile 載入現況
  - 反思報告 P1（`docs/research/2026-06-22-external-benchmark-reflection.md`，PR #39）
  - **FC-004**（`.asp-fact-check.md`）——官方 plugin 機制查證證據

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由**人類**將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。AI 不可自行升級狀態。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | （待 POC-1：plugin hook 寫 settings.local.json 實證；POC-2：命名空間遷移盤點） |
| **驗證日期** | （待填） |
| **驗證者** | （待填，人類） |
| **驗證摘要** | （待填）外部 plugin 機制事實已於 FC-004 查證；尚缺 ASP 動態 deny 在 plugin hook 下的端到端 POC |
