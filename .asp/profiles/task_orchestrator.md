# Task Orchestrator — 任務協調與專案健康審計（v5 語意核心版）

<!-- requires: global_core, system_dev -->
<!-- optional: autonomous_dev, multi_agent, loose_mode, design_dev, openapi, rag_context, frontend_quality -->
<!-- conflicts: (none) -->

適用：統一任務入口，自動分類與路由任何任務類型；首次介入專案時自動審計並強制補齊缺失。
載入條件：`orchestrator: enabled` 或 `autonomous: enabled`（自動載入）

> **v5 重構**（ADR-015/SPEC-011）：確定性判斷已下沉至 `.asp/scripts/orchestrator/`（make orch-*），
> 本檔只留語意判斷與協調框架；原 1,587 行版在 `docs/archive/profiles/task_orchestrator-v4.3-1587L.md`，
> Part G 逐字抽出至 `orchestrator_multi_agent.md`。

---

## 統一入口

所有任務（需求、Bug、功能修改、功能移除）從這裡開始：

```
FUNCTION on_task_received(request):

  // ─── Step 0: 專案健康審計（機械判斷下沉）───
  EXECUTE("make orch-audit-check")   // exit 2 = 需審計（無/過期 baseline 或缺檔）
  IF exit_code == 2:
    health = EXECUTE("make audit-health")   // 審計本體（唯一實作，不重寫）
    IF health.has_blockers:
      remediate_gaps(health)   // 見 Part A「強制補齊」

  // ─── Step 1: 任務分類（機械分類 + 信心門檻）───
  result = EXECUTE("make orch-classify TASK=\"{request}\" HITL={hitl_level}")
  PRESENT("任務分類：[{result.type}] {request.summary}")
  PRESENT("  理由：{result.reason}（confidence={result.confidence}）")
  IF result.await_required:
    AWAIT human_confirm        // 低信心、或 hitl ≠ minimal
  ELSE:
    PRESENT("hitl: minimal 且 confidence ≥ {result.threshold} → 自主續行（分類已留痕）")
  // MODIFICATION 帶 post_checks: target 不存在於 codebase → 改走 NEW_FEATURE（語意判斷）

  // ─── Step 2: 路由執行 ───
  MATCH result.type:
    NEW_FEATURE  → execute_new_feature(request)
    BUGFIX       → execute_bugfix(request)
    MODIFICATION → execute_modification(request)
    REMOVAL      → execute_removal(request)
    GENERAL      → execute_general(request)

  // ─── Step 3: 後置審計（輪數上限下沉）───
  IF quick_audit().new_gaps:
    EXECUTE("make orch-round ACTION=increment")   // exit 4 = 已達 2 輪上限
    IF exit_code == 4:
      FOR gap IN new_gaps: EXECUTE("make orch-debt-log CATEGORY=post-audit-overflow DESC=\"{gap}\"")
    ELSE:
      remediate_gaps(new_gaps)

  // ─── Step 4: 任務完成 → reset 輪數、更新基線 ───
  EXECUTE("make orch-round ACTION=reset")
  EXECUTE("make audit-health")   // 末尾自動更新 .asp-audit-baseline.json
```

---

## Part A: 專案健康審計

| 觸發時機 | 動作 |
|------|------|
| 首次介入 / baseline 過期（`make orch-audit-check` exit 2） | 自動觸發 `make audit-health` |
| `make audit-health` | 手動隨時可用 |
| 任務完成後 | 快速審計（只檢查本次修改相關） |

審計本體 = `make audit-health`（9 維度掃描，Makefile 為唯一實作）；session 級結果讀
`.asp-session-briefing.json`。分級標準：🔴 Blocker（ADR Draft 有實作、核心模組無測試）
必須先修復；🟡 Warning 主任務後處理；🟢 Info 建議改善。

### 強制補齊（remediation SPEC 撰寫指引——語意判斷，保留）

發現 blocker 時：
1. 逐項向人類列出 blocker 與影響。
2. autonomous 啟用 → 為每個 blocker 建 `make spec-new TITLE="AUDIT-NNN: {gap}"`，
   SPEC 的 Goal 寫「補齊 {gap.description}」、Done When 寫 gap 的可二元驗證消除條件
   （例：「`make audit-health` 不再列出此項」），**然後 PAUSE 等人類確認執行順序**。
3. standard → 列出 blocker 與建議 SPEC 標題，由人類決定。
4. Warning 排入佇列，主任務完成後處理；無法處理者 `make orch-debt-log` 留痕。

---

## Part B: 任務分類

分類執行 `make orch-classify TASK="..." HITL=...`（關鍵字表與信心門檻在
`.asp/scripts/orchestrator/rules/classification.json`，回傳 type/confidence/await_required）。

### 模糊案例裁決原則（語意判斷，腳本不裁決）

- **MODIFICATION 的 post_check**：腳本回傳 `target_exists_in_codebase` 時，由 AI grep
  確認目標存在；不存在 → 改走 NEW_FEATURE 並說明。
- **複合需求**（GENERAL）：永遠人類確認拆解，不論 hitl 等級（拆解錯誤代價跨任務放大）。
- **分類與使用者明示意圖矛盾**：使用者說「這是 bug」但腳本判 MODIFICATION → 以使用者
  意圖為準，PRESENT 兩者差異後採用使用者分類。
- **confidence 介於 0.5-0.8 的灰帶**：即使 standard 模式也補一句分類依據（matched 關鍵字），
  讓人類確認時有判斷材料。

### 人類確認話術格式（保留）

```
任務分類：[BUGFIX] 修復登入逾時
  理由：包含修復/錯誤意圖（confidence=0.86，matched: 修復）
  → 確認分類正確？（回覆「對」繼續；或直接給正確分類）
```

**繞過藉口與反駁（分類執行）：**
| 藉口 | 反駁 |
|------|------|
| 「分類很明顯，不用跑腳本」 | 「明顯」是主觀判斷。腳本 1 秒回傳含 confidence 的可審計結果，跳過 = 留痕斷裂 |
| 「confidence 低但我覺得分類對」 | 你的「覺得」無法被 audit。低信心 → AWAIT 是機械規則，覺得對就讓人類花 3 秒確認 |
| 「使用者趕時間，跳過確認」 | 錯誤分類走錯工作流的代價 >> 3 秒確認。趕時間更要確認方向 |
| 「上次同類任務確認過了」 | 分類確認是 per-task 的。上次的確認不延續（同 Assumption Checkpoint 豁免規則） |

---

## Part C: 架構影響評估

依 `/asp-plan` Step 2 的五問清單判斷是否需要 ADR（跨模組／新依賴／schema 或 API 合約／
3+ 檔案或跨團隊／安全效能合規）。保留啟發式：`assess_architecture_impact()` ——
影響 > 15 個檔案（grep 計數）→ 需要 ADR。

---

## Part D: 五種任務工作流

> 各工作流只保留協調骨架與 Phase 編號（pipeline.md G1-G6 映射錨點）；ADR/SPEC/TDD/
> 提交細節一律引用對應 skill：建立規劃 → `/asp-plan`；品質門 → `/asp-gate`；
> 提交前 → `/asp-ship`。

### D1. TASK_NEW_FEATURE — `execute_new_feature(request)`

| Phase | 動作 |
|-------|------|
| 1 | 架構影響評估（Part C）；需 ADR → `/asp-plan` Step 3，**等人類升 Accepted/FIRM**（FIRM 🟡 留 bypass log；Draft 超時 30 分鐘 → 人類三選一：等待／暫存終止／跳過記 `adr-pending` tech-debt） |
| 2 | SPEC 建立（`/asp-plan` Step 4，七欄位 + 場景） |
| 3 | 條件 Gates：design/openapi enabled 且 profile 已載入 → 各自 Gate；rag enabled → `make rag-search` 查歷史教訓；enabled 但未載入 → WARN + `make orch-debt-log` |
| 4 | 變更影響評估（`assess_change_impact()`，system_dev.md） |
| 5 | TDD：有 Gherkin 場景 → 場景驅動產測試骨架並填 assertion；無 → 從 Done When 推測試。先確認 FAIL（`/asp-gate G3`） |
| 6 | 實作 |
| 7 | 驗證：autonomous → `auto_fix_loop`（防護觸發 = PAUSE）；否則 `make test`；`verify_stable_state()` |
| 8 | 提交前自審（`/asp-ship`） |
| 9 | 文件管線（Part E） |
| 10 | 完成報告（Part F） |

### D2. TASK_BUGFIX — `execute_bugfix(request)`

| Phase | 動作 |
|-------|------|
| 1 | production 事故 → 轉 `execute_hotfix()`（system_dev.md Hotfix 流程），結束 |
| 2 | 嚴重度判斷（`classify_bug_severity()`，global_core）；2.5 領域偵測 `make orch-classify --domain`（追加角色/grep_hint/force_full_test） |
| 3 | TRIVIAL → 快速路徑：修復 → `make test` → **全專案 grep（鐵則，無豁免）** → CHANGELOG → 結束 |
| 4 | non-trivial：SPEC（`BUG-` 前綴，Done When 含重現條件）+ 場景矩陣（P1 修復後正確行為、N1 重現條件 + 領域典型負向案例，從 rules/classification.json 的 domain 對應） |
| 4.7 | 回歸基線捕獲：`make test` 結果快照（total/passed/failed/test_names） |
| 5 | 重現測試（必須先 FAIL） |
| 6 | 修復 |
| 7 | 驗證：重現測試 PASS + 全量測試；`force_full_test` 域（data_integrity）強制全量；7.5 回歸比對——快照中 PASS→FAIL 的測試 = 回歸，PAUSE；測試消失 = WARN 可能誤刪 |
| 8 | **全專案掃描（global_core 鐵則）**：grep 指令本身必須輸出在回覆中；領域 grep_hint 加掃；STATE_DEPENDENCY 型 → `scan_state_dependencies()` |
| 9 | 共用模組 → 全量測試 + 列下游消費者 |
| 10 | Postmortem 評估（`meets_postmortem_criteria()`，global_core 觸發表） |
| 11 | 文件管線；commit 帶 `[bug:logic|boundary|concurrency|integration|config]` 分類標籤 |

### D3. TASK_MODIFICATION — `execute_modification(request)`

| Phase | 動作 |
|-------|------|
| 1 | 找既有 artifacts（SPEC/ADR） |
| 2 | 影響分析（grep affected files） |
| 3 | 變更等級判定（Part H `determine_change_level()`，L1-L4 = 需求變更等級） |
| 4 | 路由：L1 → 更新既有 SPEC（追加變更記錄）；L2 → 舊 SPEC 標 Cancelled + 新 SPEC，PAUSE 確認；L3 → 新 ADR + `PAUSE("L3 變更：需要新 ADR（即使 hitl: minimal 也暫停）")` + 舊 ADR 標 Superseded + `reverse_scan_adr()`；L4 → 暫停所有進行中 SPEC，PRESENT 全量影響，AWAIT 人類方向 |
| 4.5 | 場景同步（語意判斷）：既有場景與新行為矛盾 → AI 自動更新並 PRESENT；新行為 → 產新場景；同步測試矩陣 |
| 4.7 | 回歸基線捕獲（同 D2） |
| 5 | 更新測試（場景變更 → 重生測試骨架）；確認 FAIL |
| 6 | 實作 |
| 7 | 驗證 + 回歸比對（同 D2 Phase 7/7.5） |
| 8 | 文件管線 |

### D4. TASK_REMOVAL — `execute_removal(request)`

> 移除比新增更危險——殘留比缺少更有害。

| Phase | 動作 |
|-------|------|
| 1 | 識別移除範圍 |
| 2 | 依賴分析（六類 grep：code/test/doc/config/spec/adr 引用計數，PRESENT 影響表）；code 引用 > 0 → PAUSE 確認策略 |
| 3 | 外部消費者/public API → 建議分階段：先 DEPRECATED + 清理期限，到期再移除；PAUSE 決定 |
| 4 | 模組/服務/API endpoint 級 → ADR（`REMOVE-` 前綴），PAUSE 審核 |
| 5 | SPEC：Done When 含「grep 0 結果（排除 docs/adr/、CHANGELOG）+ make test 過 + 無孤立 imports/configs」 |
| 6 | 執行順序（重要）：6a 先更新依賴方 → 6b 清理測試 → 6c 移除目標（**檔案刪除在 autonomous 仍 PAUSE——鐵則**）→ 6d 清理設定/環境變數 |
| 7 | 驗證：全量測試 + 殘留 grep（過濾合理殘留：CHANGELOG/ADR 歷史） |
| 8 | 文件管線（ADR 標 Deprecated + 反向掃描） |

### D5. TASK_GENERAL — `execute_general(request)`

| Phase | 動作 |
|-------|------|
| 1-2 | 深度分析 + 拆解為低耦合子任務，逐個 `make orch-classify` |
| 3 | **PAUSE 確認拆解**（複合需求永遠人類確認，見 Part B 裁決原則） |
| 4 | multi-agent 且子任務 >1 → `orchestrator_multi_agent.md` 分派；否則依類型逐個執行 D1-D4 |
| 5 | 跨任務整合驗證（全量測試） |
| 6 | 統一文件管線 |

---

## Part E: 文件產出管線

`documentation_pipeline(spec, task_type)` = `/asp-ship` Step 3-5（CHANGELOG 分類
Added/Fixed/Changed/Removed、README、SPEC Traceability 回填）之外的 delta：

- 架構異動 / REMOVAL → 更新 `docs/architecture.md`
- REMOVAL → 關聯 ADR 標 Deprecated + `grep -r "ADR-{id}"` 反向掃描
- 結束 → `make session-checkpoint NEXT="{next_task_or_done}"`

---

## Part F: 完成報告

`completion_report(spec)` 欄位（PRESENT 為表格）：

| 欄位 | 內容 |
|------|------|
| 任務 | type / SPEC-id / 關聯 ADR |
| 變更 | 修改/新增/刪除檔案數；新增測試數；`make test` 結果 |
| 文件 | 已更新文件清單；CHANGELOG 條目；commit 標籤 |
| 健康 | blockers/warnings before → after |
| 後續 | 殘餘 TODO 或 None |

trivial 路徑用 `completion_report_lite()`（變更 + 測試結果兩行）。

---

## Part G: Multi-Agent 整合（stub）

全文已抽出至 **`orchestrator_multi_agent.md`**（ADR-015；Phase 4 隨 multi-agent 凍結至
experimental/）。`mode: multi-agent` 時**必須一併載入**該檔（profile-map.yaml 已綁定）。
本節保留標題作為外部引用錨點（pipeline.md、asp-dispatch、asp-autopilot）。

---

## Part H: 裁決原則（語意判斷函數）

`determine_change_level(request, existing_spec, existing_adr)` —— L1-L4 = **需求變更等級**
（global_core「需求變更回溯協議」，非成熟度等級）：

| 判定 | 等級 | 範例 |
|------|------|------|
| 多個 SPEC（>2）或 ADR（>1）失效 | L4 | B2C → B2B 轉型 |
| 與既有 ADR 決策矛盾 | L3 | REST 改 GraphQL |
| SPEC Goal 改變，或影響 >10 檔且超出 SPEC 範圍 | L2 | 新增 OAuth Provider（已有 auth SPEC） |
| Goal 不變的內部調整 | L1 | 新增 optional API 欄位 |

不確定時 → 視為高一級（保守原則）。

`meets_postmortem_criteria()` → global_core「Postmortem 觸發條件」表（severity ≥ HIGH、
retry ≥ 3、影響 production、需 rollback）。

`is_core_module()` / 場景衝突判定 / 測試骨架產生為語意判斷——原則：核心模組 =
auth/payment/data 類（無測試 = BLOCKER）；場景與新行為矛盾 → AI 自動更新不需人類手動；
詳細 pseudocode 見 archive 版 Part H。

---

## Part I: 團隊推薦（v5 移除）

`recommend_team()` 由 `/asp-team-pick` skill 提供（`team_compositions.yaml`）；Phase 4 隨 multi-agent 凍結。

---

## Part J: 管線整合

```
FUNCTION execute_with_pipeline(task_type, request, team):
  IF pipeline_loaded:
    RETURN execute_pipeline(request, team, team.pipeline_phases)  // from pipeline.md
  ELSE:
    MATCH task_type:  // fallback：直接呼叫 Part D 對應 execute_*()
      NEW_FEATURE → execute_new_feature(request)   | BUGFIX   → execute_bugfix(request)
      MODIFICATION → execute_modification(request) | REMOVAL  → execute_removal(request)
      GENERAL → execute_general(request)
```

---

## 與其他 Profile 的關係

```
task_orchestrator.md
  ├── 依賴 global_core.md（鐵則 + HITL 等級 + 三層回應 + 升級路徑 + 文件同步 + 迴歸預防）
  ├── 依賴 system_dev.md（ADR/SPEC/TDD 流程 + Gates + Hotfix）
  ├── 確定性腳本 .asp/scripts/orchestrator/（make orch-classify / orch-audit-check / orch-round / orch-debt-log）
  ├── 可選 autonomous_dev.md（auto_fix_loop + 自主決策邊界）
  ├── Part G → orchestrator_multi_agent.md（mode: multi-agent 時一併載入）
  ├── 可選 loose_mode.md（spike 豁免 + context 管理）
  ├── 可選 design_dev.md（Design Gate）／openapi.md（OpenAPI Gate）／rag_context.md（歷史教訓）
  └── 健康審計本體 = make audit-health（Makefile 唯一實作）
```

