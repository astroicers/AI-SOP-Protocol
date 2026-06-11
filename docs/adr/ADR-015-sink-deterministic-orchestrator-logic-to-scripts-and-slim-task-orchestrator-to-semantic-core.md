# [ADR-015]: Sink deterministic orchestrator logic to scripts and slim task orchestrator to semantic core

| 欄位 | 內容 |
|------|------|
| **狀態** | `FIRM` |
| **日期** | 2026-06-11 |
| **決策者** | astroicers（v5 簡報 Phase 2——本次重構核心）+ AI（三分法切割設計） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

`task_orchestrator.md` 是 ASP 散文治理層過度設計的最大單點：**1,587 行**，佔 profiles 總行數（5,177）的 31%。其中大量內容是 LLM 被要求「在腦中執行」的偽代碼——任務分類關鍵字表（:247-264）、bug 領域規則表（:1209-1266）、變更等級判定（:1286-1307）、審計過期檢查、後置審計輪數上限。這些都是**可確定性判斷的邏輯**，由 LLM 當直譯器執行既不可靠（每次「執行」結果可能不同）也昂貴（1,587 行 context 稅）。

附帶的設計矛盾：行 36 的「`AWAIT human_confirm` — 即使 hitl: minimal 也確認」與 global_core（v5）HITL 定義「minimal 在 SPEC 範圍內自主」直接衝突，v4 一直未解。

---

## 評估選項（Options Considered）

### 選項 A：只刪重複內容，不下沉腳本

- **優點**：工作量最小，無新腳本維護成本。
- **缺點**：只能砍到約 800-900 行；分類/領域偵測仍由 LLM 直譯，hitl:minimal 矛盾無機械解法（「信心」無從計算）。
- **風險**：v5 原則 1（確定性邏輯下沉）完全未落實於最大標的。

### 選項 B：偽代碼三分法——下沉腳本 / 保留語意 / 刪除重複（採用，簡報定案）

- **優點**：(1) 確定性判斷變成可測試的 bash+jq 腳本（與 repo 既有慣例一致）；(2) 分類腳本回傳 `confidence` 欄位，hitl:minimal 矛盾獲得機械解（`await_required = NOT(minimal AND confidence≥0.8)`）；(3) Markdown 縮到 ≤300 行純語意內容。
- **缺點**：4 支腳本 + 規則資料檔的維護面；關鍵字表從散文搬進 JSON 後，調整規則需改資料檔（這其實是優點：規則變更可 diff、可測試）。
- **風險**：外部錨點斷裂（pipeline.md G1-G6 映射引用 `execute_*()` 與 Phase 編號；asp-dispatch/asp-impact/asp-autopilot 引用內部符號）→ 緩解：函式名與 Part 編號全部保留。

### 選項 C：整檔轉為 skill（仿 autopilot SPEC-010）

- **優點**：profile 層直接消失一個大檔。
- **缺點**：orchestrator 是「常駐行為」（統一任務入口）而非「按需調用」，搬 skill 會讓入口邏輯失去 always-on 性質；且 skill 化不解決偽代碼直譯問題，只是換位置。
- **風險**：與 v4.4 SPEC-010 的「skill = 按需執行規格」分類學矛盾。

---

## 決策（Decision）

選擇 **選項 B**，切割如下：

### 1. 下沉為腳本（`.asp/scripts/orchestrator/`，介面詳見 SPEC-011）

| 腳本 | 來源（原檔行號） | 取代的偽代碼 |
|------|------|------|
| `classify-task.sh` + `rules/classification.json` | :242-268（分類決策樹）、:1199-1281（bug 領域規則 7 域） | `classify_task()`、`detect_bug_domain()`；新增 `confidence` 與 `await_required` 欄位 |
| `audit-check.sh` | :25-26、:73-80（baseline 過期/缺檔前置判斷） | 統一入口 Step 0 的觸發判斷；審計本體仍是 `make audit-health`（不寫第二套） |
| `post-audit-round.sh` | :54-63（後置審計 2 輪上限） | Step 3 輪數狀態機（`.asp-orch-state.json`，gitignored） |
| `tech-debt-log.sh` | `LOG_TECH_DEBT()` 散落呼叫 | 落檔 `docs/TECH_DEBT.md`，格式與 A8.3 掃描相容 |

Makefile 薄包裝：`orch-classify` / `orch-audit-check` / `orch-round` / `orch-debt-log`。
Markdown 只留一行「執行 `make orch-classify` 取得分類結果」。

### 2. 保留為 Markdown（語意判斷）

統一入口協調框架、五工作流的**流程骨架**（Phase 編號 + 條件分支，細節改引用 skill）、模糊案例裁決原則、remediation SPEC 撰寫指引、人類確認話術格式、`determine_change_level` 判定範例表（L1-L4 路由）、**新增**分類「繞過藉口與反駁」表（G1 review F-3 措辭校正：task_orchestrator 原無此表，本 ADR 仿 global_core / asp-plan 紅線 4 慣例新增 4 條——「分類很明顯不用跑腳本」「confidence 低但我覺得對」「使用者趕時間跳過確認」「上次同類任務確認過了」，不觸碰既有表）。

### 3. 直接刪除（與 skills 重複）

- Part D 中 ADR/SPEC 建立細節 → 一行引用 `/asp-plan`；gates 細節 → `/asp-gate`；文件管線細節 → `/asp-ship` Step 3-5
- Part H 場景同步/測試骨架四函式（:1339-1473，v3.2）→ 壓縮為原則三行 + archive 指引
- Part I 團隊推薦（:1499-1545）→ 刪除（隨 Phase 4 凍結；team_compositions.yaml 與 asp-team-pick skill 屆時移入 experimental）

### 4. Part G 逐字抽出

**:891-1130**（G1 review F-2 校正：Part H 始於 :1131，原估 :1127 少 3 行）**逐字**搬至 `.asp/profiles/orchestrator_multi_agent.md`（檔頭標注凍結中；**不可命名 multi_agent.md**——避免與歷史幽靈 token 撞名改變消費端容錯語意）。抽出來源為**當前檔**（含 Phase 1 對 :1061 的 ADR-014 D5 修正——該行與 v4.3 pristine 歸檔的已知唯一差異）。原處留 Part G stub 錨點 +「mode: multi-agent 時必須一併載入」。profile-map `mode=multi-agent` 規則加載此檔；Phase 4 隨 multi-agent 整體移入 experimental/。

### 5. hitl:minimal 矛盾修正（雙重確認）

- 腳本層：`classify-task.sh` 回傳 `await_required`（minimal + confidence≥0.8 → false）
- 文本層：統一入口改為 `IF result.await_required: AWAIT human_confirm ELSE: PRESENT 分類後續行`（取代 :36 無條件 AWAIT；**即使不 AWAIT 也強制 PRESENT 分類結果**，透明留痕）
- **:571「L3 變更即使 hitl: minimal 也暫停」原句保留**——紅線 2，L2 以上需求變更暫停是 global_core 共通規則

回滾方式：單 commit revert；原文完整保存 `docs/archive/profiles/task_orchestrator-v4.3-1587L.md`。

---

## 後果（Consequences）

**正面影響：**
- profiles 最大單點 1,587 → ~300 行（-81%）；L3+ 組態 context 稅預估 -30% 以上（Phase 3 驗收）。
- 分類/領域偵測變為可測試、可 diff 的確定性邏輯；hitl:minimal 行為由門檻機械決定。

**負面影響 / 技術債：**
- profiles 暫時 +1（orchestrator_multi_agent.md，13→14），Phase 4 移入 experimental 後回到目標數。
- install.sh 複製清單需加 `scripts` 目錄（user-level 部署 orchestrator 腳本；Phase 3 asp-compile 同樣依賴此改動）。
- 規則調整的入口從「改散文」變「改 JSON + 跑測試」——對非工程使用者門檻略升（接受：這正是「規則越少越鐵」）。

**後續追蹤：**
- [ ] Phase 3：asp-compile 驗收 L3/L5 組態 ≥30% 下降（本 ADR 提供主要降幅）
- [ ] Phase 4：orchestrator_multi_agent.md + team_compositions.yaml 移入 experimental/

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| Markdown 行數 | `wc -l task_orchestrator.md` ≤ 300 | test_orch_hitl_minimal.sh 文本層 | Phase 2 結束 |
| 腳本測試 | 5 支測試檔全綠（矩陣 P1-P4/N1-N3/B1-B3） | `make test` | 每次 |
| 錨點完整 | execute_* ×5 + Part A-J 標題保留；pipeline.md :27 映射逐項可對應 | grep + 人工 diff | Phase 2 結束 |
| Part G 保真 | 抽出檔與原文 :891-1127 diff 一致 | `sed -n '891,1127p' archive 對 diff` | Phase 2 結束 |
| hitl 雙重確認 | 腳本層 await_required 行為 + 文本層無舊句、:571 原句在 | test_orch_hitl_minimal.sh | 每次 |

---

## 關聯（Relations）

- 取代：（無——supersede task_orchestrator.md v4.3 版內容組織，原文歸檔）
- 被取代：（無）
- 參考：SPEC-011（腳本介面）、ADR-014（HITL 上移 global_core、D5 fallback 刪除）、ADR-013（簡報路徑偏差記錄）、ADR-007（v4.3 Part G 合併來源——本 ADR 抽出屬其「2000 行警戒線」的執行，演進非矛盾）
- **量測基準宣告（G1 review F-6）**：本 ADR 的「-81% 行數 / L3+ 組態 -30% context 稅」一律以 ADR-013 產出並 commit 的 `.asp-metrics-baseline.json`（main@eb07438 量測）為對照組；Phase 3 `--assert-reduction 30` 用同一檔案。

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | branch `asp/v5-slimming`：5 支 orch 測試全綠；task_orchestrator.md ≤300 行；Part G diff 保真；`make test` 全綠 |
| **驗證日期** | 2026-06-11 |
| **驗證者** | astroicers（2026-06-11 對話 blanket 授權 ADR-015~018；AI 代筆狀態變更） |
| **驗證摘要** | 確定性邏輯下沉為 4 支可測試腳本，orchestrator 縮至語意核心，hitl:minimal 矛盾以 confidence 門檻機械解 |
