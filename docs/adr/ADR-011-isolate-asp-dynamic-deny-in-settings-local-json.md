<!-- Last Updated: 2026-06-08 | Status: Accepted | Audience: ASP framework maintainers -->
# [ADR-011]: 將 ASP 動態 deny 隔離至 settings.local.json

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-08 |
| **決策者** | astroicers（**已核准 2026-06-08**） |
| **觸發事件** | TD-005 修復後，對抗式驗證 workflow 揭露 sidecar 方案的架構性殘留（換機卡死 / 同字串碰撞 / 暫態 deny 混入 tracked 設定） |
| **關聯** | TD-005（`docs/tech-debt-2026-06-08.md`）；ADR-002（強制力架構 / L2 Dynamic Deny）；`session-audit.sh` Section 10；外部事實查證 `.asp-fact-check.md`（FC-001） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

L2「Dynamic Deny」強制力層讓 `session-audit.sh` 在偵測到 Draft ADR 時，動態把 `Bash(git commit *)` / `Bash(git commit)` 注入 `.claude/settings.json` 的 `permissions.deny`，並在 Draft 解除後自我清除。

2026-06-08 TD-005 修復把「移除全部 hardcoded 集合」改為 sidecar（`.asp-managed-deny.json`，gitignored）只記錄並移除「ASP 實際注入」的條目，解決了「使用者手動 deny 被靜默移除」的主要 bug。但**對抗式驗證 workflow（4 個獨立 skeptic agent）揪出架構性殘留**：

1. **狀態分裂導致換機永久卡死（HIGH）**：deny 寫在 **git-tracked** 的 `settings.json`，但 ownership 紀錄在 **gitignored** 的 sidecar。若 ASP 在 Draft 期間注入 deny 且 `settings.json` 被 commit，換機 / `git clean` 後 sidecar 遺失 → `PREV_MANAGED` 退回 `[]` → 無 Draft 時無法自清 → `git commit` 被神祕阻擋，需手動 `make asp-unlock-commit`。
2. **同字串碰撞（MEDIUM）**：使用者在 ASP 擁有期間自行加入相同字串，事後無法辨識歸屬，Draft 解除時被連帶移除。
3. **暫態狀態污染 tracked 設定**：ASP 的 session 暫態 deny 與使用者共享的 `settings.json` 混用，產生使用者非預期的 diff，且有被誤 commit 之虞。

根因是**單一字串無法承載 ownership 資訊**，且**暫態狀態與共享設定混存於同一 tracked 檔**。本 session 已加 orphan WARNING 緩解 #1、效驗閘防止 settings 損毀，但未根治。

**已驗證的外部事實（`.asp-fact-check.md` FC-001，官方 Claude Code 文件）：** `.claude/settings.local.json` 是 Claude Code 自動載入、**預設 gitignored** 的本地 scope；`permissions.deny` 跨 scope **合併**且採 **deny-first**——任一 scope 的 deny 即生效，與檔案優先序無關；hook 寫入 settings.local.json 的 deny 同 session reload 即生效。

---

## 評估選項（Options Considered）

### 選項 A：ASP 動態 deny 改寫到 `.claude/settings.local.json`（建議）

ASP 只管理 gitignored 的 `settings.local.json`，把動態 deny 全部寫在那；tracked 的 `settings.json` 永不被 ASP 觸碰（使用者 deny 的家）。

- **優點**：根治三個殘留。(a) ASP 完整擁有 settings.local.json 的 deny → 可用最單純的 hardcoded 命名空間 reconcile，**無需 sidecar、無 ownership 歧義、無換機 desync**（兩者皆本地、皆不進 git）。(b) 使用者 `settings.json` 零 ASP-induced diff，暫態 deny 永不被 commit。(c) 同字串碰撞消失——使用者的在 settings.json、ASP 的在 settings.local.json，deny 為 union 兩者皆生效，ASP 只清自己的檔。
- **缺點**：須改 `session-audit.sh` Section 10 的寫入目標 + 處理「遷移前已注入 tracked settings.json 的殘留 deny」一次性清理；既有測試（檢查 settings.json deny）須移到 settings.local.json；settings.local.json 不存在時須建立。
- **風險**：動到 L2 強制力關鍵路徑——deny 生效性已由 FC-001 確認（deny-first、scope-agnostic），但須 POC 實測「Draft 期間 commit 確實被擋」。

### 選項 B：維持現狀（sidecar + orphan WARNING，本 session 已實作）

- **優點**：零額外改動；主要 bug（使用者 deny 被刪）已解；換機卡死有 WARNING 可見。
- **缺點**：殘留 #1 只被「surface」非「resolve」（仍需人工 `make asp-unlock-commit`）；#2 同字串碰撞未解；暫態 deny 仍在 tracked 檔。
- **風險**：團隊協作 / 多機情境下換機卡死會反覆發生，磨損對框架的信賴。

### 選項 C：在 settings.json deny 內嵌自我識別標記

- **優點**：不改寫入位置。
- **缺點 / 風險**：**不可行**——deny 字串必須精確匹配命令樣式，無法 namespace；JSON 無註解。技術上做不到。**已排除。**

---

## 決策（Decision）

提議 **選項 A**：把 ASP 動態 deny 的寫入與自清目標從 `.claude/settings.json` 改為 **gitignored 的 `.claude/settings.local.json`**，tracked 的 `settings.json` 由使用者全權擁有、ASP 不再觸碰。FC-001 已確認 deny-first / scope-merge 行為使此方案在強制力上與現狀等價。

**本 ADR 維持 `Draft`，依鐵則「Draft 禁止實作」——人類核准升 `Accepted` 前，不得動 `session-audit.sh` 寫入邏輯。** 落地細節（一次性清理既有 tracked deny、測試遷移、sidecar/orphan-warning 退役）defer 到對應 SPEC，通過 G2 後實作。

---

## 後果（Consequences）

**正面影響：**
- 根治 TD-005 三個殘留（換機卡死、同字串碰撞、暫態污染 tracked 設定）。
- `.asp-managed-deny.json` sidecar 與 8.5 節 orphan WARNING 可**退役**（ASP 全權擁有 local 檔，reconcile 邏輯反而更單純）。
- 使用者 `settings.json` 從此零 ASP-induced diff。

**負面影響 / 技術債：**
- 一次性遷移：偵測並清掉「遷移前已寫進 tracked settings.json」的 ASP 殘留 deny（否則它會留在 tracked 檔變孤兒）。
- 既有測試 `test_managed_deny_reconcile.sh` 須改為驗 settings.local.json；新增「settings.json 永不被 ASP 改」的回歸測試。
- 須處理 settings.local.json 不存在 / 非法 JSON 的建立與防護（沿用本 session 的效驗閘）。

**後續追蹤：**
- [x] 人類審核本 ADR → **astroicers 於 2026-06-08 核准升 `Accepted`**。
- [x] 實作 settings.local.json 遷移（TDD）：session-audit Section 10 改寫 `settings.local.json`、永不觸碰 tracked `settings.json`；`make asp-unlock-commit` 同步清兩檔。
- [x] 退役 Section 8.5 orphan WARNING（tracked/gitignored 分裂的根因已消除——deny 不再進 tracked 檔）。
- [ ] POC：實機確認「Draft 期間注入 settings.local.json 的 deny 確實擋下 git commit」（FC-001 已查證 deny-first/scope-merge 行為）。

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 使用者 settings.json 被 ASP 改動 | 0 次（任何 Draft/解除循環後 tracked settings.json 不變） | 回歸測試：注入→解除後 `git diff .claude/settings.json` 為空 | 實作完成時 |
| Draft 期間 commit 仍被擋 | deny 生效（commit 被阻擋） | POC：settings.local.json 注入 deny 後實測 `git commit` 被擋 | 實作完成時 |
| 換機自清（無 sidecar 依賴） | Draft 解除後 ASP deny 自動消失，不殘留 | 模擬「clean local state」後跑 audit | 實作完成時 |
| 同字串碰撞 | 使用者 settings.json 的同字串 deny 不受 ASP 清除影響 | 負向測試 | 實作完成時 |

> 重新評估條件：若未來 Claude Code 改變 settings.local.json 的載入 / deny-merge 行為（FC-001 失效），須重審本決策。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：TD-005（`docs/tech-debt-2026-06-08.md` 殘留清單 #1）；ADR-002（強制力架構 L2 Dynamic Deny）；`.asp/hooks/session-audit.sh` Section 8.5 + Section 10；外部事實查證 `.asp-fact-check.md` FC-001（Claude Code settings.local.json deny-merge 行為）。

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | （待 POC：settings.local.json 注入 deny → 實測 git commit 被擋 + 換機自清） |
| **驗證日期** | （待填） |
| **驗證者** | astroicers（待人類覆核） |
| **驗證摘要** | 外部事實 FC-001 已驗證（deny-first / scope-merge / gitignored）；落地行為待 POC。 |
