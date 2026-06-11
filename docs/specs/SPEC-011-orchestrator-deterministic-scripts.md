# SPEC-011：orchestrator deterministic scripts

> 結構完整的規格書讓 AI 零確認直接執行。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-011 |
| **關聯 ADR** | ADR-015 |
| **估算複雜度** | 中 |
| **建議模型**（optional） | Sonnet |
| **HITL 等級**（optional） | （沿用 `.ai_profile`） |

---

## 🎯 目標（Goal）

把 `task_orchestrator.md` 中可確定性判斷的偽代碼（任務分類關鍵字表、bug 領域規則、audit 前置檢查、後置審計輪數、tech-debt 記錄）下沉為真實 bash 腳本（`.asp/scripts/orchestrator/`），讓 LLM 不再當千行控制流程的直譯器——v5 原則 1/2 的核心落地。

---

## 📥 輸入規格（Inputs）

| 腳本 | 參數 | 型別 | 來源 | 限制條件 |
|----------|------|------|------|----------|
| classify-task.sh | 任務描述 | string | argv 或 `--stdin` | 非空白；`--hitl minimal\|standard\|strict`（預設 standard）；`--domain` 切換 bug 領域模式；`--rules FILE` 覆寫規則檔 |
| audit-check.sh | `--project DIR`（預設 .）`--max-age-days N`（預設 7） | path/int | argv | DIR 須存在 |
| post-audit-round.sh | `--get\|--increment\|--reset`、`--cap N`（預設 2）、`--project DIR` | enum/int | argv | 三選一動作必填 |
| tech-debt-log.sh | `--category C --desc D [--severity HIGH\|MED\|LOW] [--due YYYY-MM-DD]` | string | argv | HIGH 必帶 `--due` |

---

## 📤 輸出規格（Expected Output）

**成功情境（單行 JSON 到 stdout）：**

```json
{"type":"BUGFIX","confidence":0.86,"matched":["修復"],"reason":"包含修復/錯誤意圖",
 "post_checks":[],"await_required":false,"hitl":"minimal","threshold":0.8}
```

- classify `--domain` 模式：`{"domain":"auth","add_agents":["sec"],"grep_hint":"...","force_full_test":false,"force_state_scan":false}`
- audit-check：`{"baseline_exists":true,"age_days":3,"stale":false,"missing_files":[],"audit_required":false}`
- post-audit-round：`{"round":2,"cap":2,"exceeded":true}`
- tech-debt-log：`{"recorded":true,"file":"docs/TECH_DEBT.md"}`

**失敗情境（退出碼）：**

| 錯誤類型 | exit code | 處理方式 |
|----------|-----------|----------|
| 空輸入/參數錯誤 | 2 | stderr 用法說明 |
| rules 檔缺失或非法 JSON | 3 | stderr 指出檔案 |
| jq 不存在 | 4 | stderr 安裝提示 |
| audit-check 需要審計（無/過期/損毀 baseline） | 2 | JSON 仍輸出，`audit_required: true` |
| post-audit-round increment 達 cap | 4 | JSON 仍輸出，`exceeded: true`（呼叫端轉記 tech-debt） |

**confidence 與 await_required（hitl:minimal 矛盾修正的機械側）：**
`confidence = top_type_hits / total_hits`（無命中 → GENERAL，confidence=0.3）；
`await_required = NOT (hitl == "minimal" AND confidence >= threshold)`，threshold 取自規則檔（預設 0.8）。

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| `.asp-orch-state.json` 寫入（audit_round） | post-audit-round `--increment/--reset` | task_orchestrator Step 3 | 測試矩陣 P3/B2；檔案為合法 JSON |
| `docs/TECH_DEBT.md` 追加 marker 行 | tech-debt-log 成功 | A8.3 掃描、`make tech-debt-list` | 測試矩陣 P4：追加行可被既有 `tech-debt:` 掃描命中 |
| install.sh 複製清單加 `scripts` 目錄 | user-level 安裝/升級 | `~/.claude/asp/scripts/`（Phase 3 asp-compile 也依賴） | 靜態契約斷言：`tests/test_orch_hitl_minimal.sh` §(c)（安裝契約，非執行期行為，故不列測試矩陣——G2 review F-8） |
| task_orchestrator.md 重寫 ≤300 行 | 本 SPEC 落地 | pipeline.md G1-G6 錨點、asp-dispatch/impact/autopilot 引用 | 錨點 grep：execute_* 函式名與 Part 編號保留 |

---

## ⚠️ 邊界條件（Edge Cases）

- 空字串/全空白輸入 → exit 2，不輸出半成品 JSON
- 任務描述同時命中多類關鍵字 → priority 序（REMOVAL > BUGFIX > MODIFICATION > NEW_FEATURE），competing 計數反映於 confidence
- 規則檔 JSON 損毀 → exit 3（不得 fallback 猜測）
- `.asp-orch-state.json` 損毀 → 視為 round=0 重建（記 WARNING 到 stderr）
- 任務描述含引號/反斜線 → jq 組裝保證輸出 JSON 合法
- MODIFICATION 命中 → `post_checks:["target_exists_in_codebase"]`（目標存在性屬語意判斷，留給 LLM：target 不存在 → 視為 NEW_FEATURE）

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | `git revert` Phase 2 單一 commit：腳本/規則檔/測試為純新增；task_orchestrator.md 原文在 `docs/archive/profiles/task_orchestrator-v4.3-1587L.md` 完整保存，revert 即還原 |
| **資料影響** | 無（`.asp-orch-state.json` gitignored，可安全刪除） |
| **回滾驗證** | `wc -l .asp/profiles/task_orchestrator.md` = 1587；`make test` 綠 |
| **回滾已測試** | ☑ 是（git mv/revert 機制與 Phase 1 同型，已驗證） |

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入條件 | 預期結果 | 對應場景 |
|---|------|---------|---------|---------|
| P1 | ✅ 正向 | 「修復登入 bug」 | type=BUGFIX、confidence>0.5 | S1 |
| P2 | ✅ 正向 | `--domain`「token 過期」 | domain=auth、add_agents=["sec"] | S4 |
| P3 | ✅ 正向 | increment ×2 | round=2、exceeded=true 邊界 | S5 |
| P4 | ✅ 正向 | tech-debt-log MED | TECH_DEBT.md 追加一行、格式可被 A8.3 掃描 | S6a |
| N1 | ❌ 負向 | 空輸入 | exit 2 | S2 |
| N2 | ❌ 負向 | rules 檔缺失 | exit 3 | S2 |
| N3 | ❌ 負向 | HIGH 無 --due | exit 2 | S6b |
| B1 | 🔶 邊界 | 「移除舊功能再新增新版」 | priority 序 → REMOVAL | S3 |
| B2 | 🔶 邊界 | 損毀 state json | round 視為 0、stderr WARNING | S5 |
| B3 | 🔶 邊界 | minimal+高信心 vs minimal+模糊 | await_required false / true | S7 |

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: Orchestrator 確定性腳本
  作為 task_orchestrator 的執行者（LLM）
  我想要以 make orch-* 取得分類/審計/輪數/tech-debt 的機械判斷
  以便不再在 Markdown 偽代碼裡當直譯器

  Background:
    Given repo 含 .asp/scripts/orchestrator/ 與 rules/classification.json

  Scenario: S1 - 關鍵字分類回傳 JSON 與 confidence
    When 執行 classify-task.sh "修復登入 bug"
    Then stdout 為單行合法 JSON 且 type 為 BUGFIX
    And confidence 介於 0 與 1

  Scenario: S2 - 錯誤輸入以退出碼回報
    When 執行 classify-task.sh ""
    Then exit code 為 2
    When 以 --rules /nonexistent.json 執行
    Then exit code 為 3

  Scenario: S3 - 多重命中依 priority 序
    When 執行 classify-task.sh "移除舊功能再新增新版"
    Then type 為 REMOVAL

  Scenario: S4 - bug 領域偵測
    When 執行 classify-task.sh --domain "JWT token 過期沒擋住"
    Then domain 為 auth 且 add_agents 含 sec

  Scenario: S5 - 後置審計輪數上限
    Given round 為 0
    When increment 兩次
    Then 第二次回傳 exceeded=true 且第三次 increment exit 4

  Scenario: S6a - tech-debt 記錄落檔
    When 以 --severity MED 記錄
    Then docs/TECH_DEBT.md 追加一行 tech-debt: marker

  Scenario: S6b - HIGH 缺 due 防護
    When 以 --severity HIGH 不帶 --due 記錄
    Then exit code 為 2

  Scenario: S7 - hitl minimal 信心門檻（雙重確認之腳本層）
    When 以 --hitl minimal 分類高信心輸入「修復 bug」
    Then await_required 為 false
    When 以 --hitl minimal 分類無關鍵字的模糊輸入
    Then await_required 為 true
    When 以 --hitl standard 分類任何輸入
    Then await_required 為 true
```

---

## ✅ 驗收標準（Done When）

- [ ] `bash tests/test_orch_classify.sh` 等 5 支測試全綠（涵蓋測試矩陣全部行）
- [ ] `wc -l .asp/profiles/task_orchestrator.md` ≤ 300
- [ ] 文本層雙重確認：新 task_orchestrator.md 無「即使 hitl: minimal 也確認」舊句；原檔 `:571` 的「L3 變更即使 minimal 也暫停」原句保留（紅線 2；此處 L3 = **需求變更等級**（global_core 需求變更回溯協議 L1-L4），非成熟度等級——G2 review F-5 消歧）
- [ ] 錨點完整：`grep -c 'execute_new_feature\|execute_bugfix\|execute_modification\|execute_removal\|execute_general' task_orchestrator.md` ≥ 5；Part A-J 標題保留
- [ ] 原文完整保存於 `docs/archive/profiles/task_orchestrator-v4.3-1587L.md`（1,587 行）
- [ ] Part G 逐字抽出為 `orchestrator_multi_agent.md`（與抽出前當前檔 **:891-1130** 內文 `diff -u` 退出碼 0——G2 review F-2 量化 + G1 review F-2 行號校正；與 v4.3 pristine 歸檔的已知唯一差異 = :1061 的 ADR-014 D5 修正行）
- [ ] `make lint` 無 error；`make audit-health` 無新 BLOCKER

---

## 🔗 追溯性（Traceability）

| 實作檔案 | 測試檔案 | 最後驗證日期 |
|----------|----------|-------------|
| .asp/scripts/orchestrator/classify-task.sh | tests/test_orch_classify.sh, tests/test_orch_hitl_minimal.sh | 2026-06-11 |
| .asp/scripts/orchestrator/rules/classification.json | tests/test_orch_classify.sh | 2026-06-11 |
| .asp/scripts/orchestrator/audit-check.sh | tests/test_orch_audit_check.sh | 2026-06-11 |
| .asp/scripts/orchestrator/post-audit-round.sh | tests/test_orch_round.sh | 2026-06-11 |
| .asp/scripts/orchestrator/tech-debt-log.sh | tests/test_orch_debt_log.sh | 2026-06-11 |
| .asp/profiles/task_orchestrator.md（重寫） | tests/test_orch_hitl_minimal.sh（文本層） | 2026-06-11 |

---

## 📊 非功能需求（Non-Functional Requirements, optional）

| 類別 | 需求 | 驗證方式 |
|------|------|----------|
| 相容性 | bash 4+/jq 即可，不引入 python/yq 依賴 | shellcheck + 測試於 CI 環境 |
| 確定性 | 同輸入同輸出（無時間戳於判斷欄位） | 測試重複執行斷言 |

---

## 📊 可觀測性（Observability）

| 面向 | 說明 |
|------|------|
| **關鍵指標** | N/A（本地 CLI 工具；分類結果由 LLM 在對話中 PRESENT 留痕） |
| **日誌** | 錯誤一律 stderr；stdout 保留給 JSON |
| **告警** | N/A |
| **如何偵測故障** | `make test`（5 支測試）；exit code 非 0 |

---

## 🚫 禁止事項（Out of Scope）

- 不要修改：pipeline.md 的 G1-G6 定義、asp-plan/asp-ship/asp-gate skills 本體（重複內容改為一行引用即可）
- 不要引入新依賴：python/yq/node 一律禁止（bash+jq only）
- 不處理 Part G 的內容變更（逐字搬移，Phase 4 凍結）

---

## 📎 參考資料（References）

- 相關 ADR：ADR-015（三分法決策）、ADR-014（hitl 上移 global_core）、ADR-013（profile-map）
- 現有類似實作：`.asp/scripts/level-resolve.sh`（中央映射 pattern）、`.asp/scripts/multi-agent/audit-write.sh`（JSON 輸出慣例）
- 外部文件：v5 簡報 Phase 2（偽代碼三分法）
