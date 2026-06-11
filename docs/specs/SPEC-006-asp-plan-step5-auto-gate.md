# SPEC-006：asp-plan Step 5 auto-gate 觸發機制與實作規格

> 本 SPEC 為 ADR-009 落地的硬依賴。涵蓋觸發 glob、edge cases、G2 PENDING 例外規則、rationalization 初始集、bypass 整合、`asp-ship` Step 9.6 文字、`asp-plan` Step 5 文字。

> **用詞約定**：本 SPEC 之「流程」均指通用程序（generic procedure / process），**非** ASP G1-G6 Pipeline。CONTEXT.md 將「流程」列為 Pipeline 的避免同義詞，本 SPEC 在使用「流程」一字時不指涉 G1-G6 Pipeline，特此釐清以避免 G2 reviewer 誤判。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-006 |
| **關聯 ADR** | ADR-009 |
| **估算複雜度** | 中 |
| **建議模型** | Sonnet（prompt engineering + 文件編輯，無重 IO） |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

把 ADR-009 的 P2「AI 自律 spawn G1/G2 subagent」從**設計**落到**可執行規格**：定義觸發條件的機械化 glob 命令、邊界 case 處理、`.asp-gate-log/` 寫入規範、`asp-plan` Step 5 與 `asp-ship` Step 9.6 的具體文字補丁、bypass 流程整合，使 AI 在 plan 結尾**無判斷空間**地執行 review automation。

---

## 📥 輸入規格（Inputs）

| 參數 | 型別 | 來源 | 限制條件 |
|------|------|------|----------|
| `staged_diff` | shell output | `git diff --cached --name-only` | 由 AI 在 Step 5 結尾必須執行；命令固定，不可改寫 |
| `current_commit_sha` | string | `git rev-parse --short HEAD` | 用於 gate log 檔名 timestamp |
| `iso_timestamp` | string | `date -u +%Y%m%dT%H%M%SZ` | 用於 gate log 檔名 |
| `bypass_log_path` | path | constant `.asp-bypass-log.ndjson` | 遷移後正式路徑；遷移前若仍為 `.json`，依 session-audit 流程提示遷移 |

**AI 行為輸入**：本 SPEC 落地後，AI 在 `asp-plan` Step 5 完成 ADR/SPEC 寫入後**必須**：
1. 執行 `git diff --cached --name-only`
2. 應用下方「觸發 glob 表」做機械匹配
3. 命中 → 並行 spawn G1/G2 subagent；未命中 → 跳過並在 Step 5 結尾陳述「無 ADR/SPEC 變更，跳過 auto-gate」（這句話必填，作為決策痕跡）

---

## 📤 輸出規格（Expected Output）

### 觸發 glob 表（**ground truth**，AI 不得偏離）

| Glob pattern | 觸發 Gate | 範例命中 | 範例不命中 |
|--------------|-----------|----------|------------|
| `^docs/adr/ADR-[0-9]+.*\.md$` | G1 | `docs/adr/ADR-009-foo.md` | `docs/adr/README.md`、`docs/adr/ADR-template.md` |
| `^docs/specs/SPEC-[0-9]+.*\.md$` | G2 | `docs/specs/SPEC-006-bar.md` | `docs/specs/README.md`、`docs/specs/notes.md` |

**判斷邏輯**（精確；G2 review 後自抓 F-5 修正——原版用 `--name-only` 會把**刪除**的 ADR/SPEC 也計入觸發，牴觸 E3/B3「刪除不觸發」。改用 `--name-status` 排除 `D`，rename `R` 取新檔名計入 = E1）：
```bash
staged=$(git diff --cached --name-status)
hits_adr=$(echo "$staged" | grep -v '^D' | awk '{print $NF}' | grep -cE '^docs/adr/ADR-[0-9]+.*\.md$' || true)
hits_spec=$(echo "$staged" | grep -v '^D' | awk '{print $NF}' | grep -cE '^docs/specs/SPEC-[0-9]+.*\.md$' || true)
deleted_gov=$(echo "$staged" | grep '^D' | awk '{print $NF}' | grep -cE '^docs/(adr|specs)/(ADR|SPEC)-[0-9]+.*\.md$' || true)
[[ $hits_adr -gt 0 ]] && spawn_g1
[[ $hits_spec -gt 0 ]] && spawn_g2
[[ $deleted_gov -gt 0 ]] && echo "⚠️ ADR/SPEC 刪除偵測 — 請確認是 supersede 流程而非誤刪"
```

### Gate log 寫入格式

**檔名**：`.asp-gate-log/{iso_timestamp}-G{n}-{adr_or_spec_id}.md`
例：`.asp-gate-log/20260513T143022Z-G1-ADR-009.md`

**內容** = subagent 完整 markdown 報告（含 PASS/WARN/FAIL、findings、notes）+ 開頭 frontmatter：

```yaml
---
gate: G1
target_id: ADR-009
target_path: docs/adr/ADR-009-asp-plan-step5-auto-subagent-gate.md
trigger_commit: <sha-short>
trigger_diff_command: "git diff --cached --name-only"
spawn_timestamp_utc: 20260513T143022Z
subagent_type: general-purpose
subagent_model: sonnet
result: PASS_WITH_WARN  # PASS | PASS_WITH_WARN | FAIL
findings_count: 4
---
```

### 主對話摘要區塊（**必填**，無 frontmatter，AI 直接 echo）

```
## asp-gate auto-review 結果

| Gate | Status | WARN/BLOCKER |
|------|--------|--------------|
| G1   | PASS_WITH_WARN | 4 WARN（W1 N=1 evidence、W2 Step 9.x 衝突、W3 CLAUDE.md 表未同步、W4 trigger 非機械化）|
| G2   | (skipped — no SPEC in staged diff) | — |

完整報告：.asp-gate-log/20260513T143022Z-G1-ADR-009.md
```

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | 驗證方式 |
|--------|---------|----------------|---------|
| 新建 `.asp-gate-log/{timestamp}-G{n}-*.md` | glob 命中 + subagent 完成 | doc-audit、`asp-ship` Step 9.6 | `tests/test_auto_gate_log_write.sh` 檢查檔名 pattern + frontmatter schema |
| 主對話 echo「asp-gate auto-review 結果」摘要 | 同上 | 使用者可見輸出 | `tests/test_auto_gate_summary.sh` 用 fixture 對照 |
| 跳過時 echo「無 ADR/SPEC 變更，跳過 auto-gate」 | glob 未命中 | 使用者可見輸出（決策痕跡） | `tests/test_auto_gate_skip_message.sh` |
| 寫入 `.asp-bypass-log.ndjson`（一行 NDJSON） | 使用者或 AI 主動 bypass auto-gate | 既有 bypass 機制 | `tests/test_auto_gate_bypass_log.sh` 檢查 ndjson schema |
| `asp-ship` Step 9.6 偵測 commit 含 ADR/SPEC 但缺對應 gate log → WARN | 每次 `/asp-ship` | 提交流程 | `tests/test_ship_step96.sh` |
| `asp-plan` Step 5 多一個結尾陳述 | 每次 plan 結束 | plan 流程 | 手動 review `.claude/skills/asp/asp-plan.md` 差異 |

---

## ⚠️ 邊界條件（Edge Cases）

### Edge Case 表

| Case | 觸發 | 預期行為 |
|------|------|---------|
| **E1: ADR 檔案 rename（git mv）** | `git diff --cached --name-status` 顯示 `R` | 視同**新增** — 觸發 G1。理由：rename 通常代表 ID 變更或結構性重整，需重審 |
| **E2: ADR 只改 Status（Draft → Accepted）** | diff 內容只有 frontmatter 表格 status 列 | **仍觸發** G1（保守選擇 — Accept transition 是高價值節點，剛好對應 ADR-009 後續追蹤的 sync-CLAUDE.md commitment） |
| **E3: ADR 刪除（git rm）** | `--name-status` 顯示 `D` | **不**觸發 G1，但在主對話 echo「⚠️ ADR 刪除偵測 — 請確認是 supersede 流程而非誤刪」（提示，非阻擋） |
| **E4: 同一 plan 修改 ≥ 2 個 ADR** | hits_adr ≥ 2 | 各自並行 spawn G1（每個 ADR 一個 subagent），各自獨立 gate log |
| **E5: 修改 ADR + SPEC 同 plan** | hits_adr ≥ 1 且 hits_spec ≥ 1 | G1 + G2 並行 spawn |
| **E6: 純粹 typo 修改既有 ADR**（例如改錯字）| hits_adr ≥ 1 | **仍觸發** — 保守選擇，trial 期觀察噪音率，若過高再考慮加 hash-based content threshold |
| **E7: `docs/adr/README.md` 修改** | glob 不匹配（非 `ADR-NNN` 命名）| 不觸發。README 是索引文件，非 ADR 本體 |
| **E8: AI context budget 接近上限** | AI 主觀判斷 | **不可作為跳過理由**（見 rationalization #5）。若真的爆 context → 走 bypass 流程顯式記錄 |
| **E9: subagent spawn 失敗（API error / timeout）** | Agent tool 回錯 | 主對話 echo「⚠️ auto-gate spawn 失敗：<error>」+ 寫 bypass log step=auto-gate reason=spawn-failure。**不**阻擋 plan 完成 |
| **E10: `.asp-gate-log/` 目錄不存在** | 首次執行 | AI 必須先 `mkdir -p .asp-gate-log` 再寫入。`.gitignore` 範例見「Out of Scope」 |

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | `git revert` 本 SPEC 落地 commit；revert 後 `asp-plan.md` Step 5 / `asp-ship.md` Step 9.6 / Common Rationalizations 表全部還原；`.asp-gate-log/` 內容保留（純文件，無破壞）；ADR-009 從 Accepted 退回 Draft |
| **資料影響** | 零；所有 gate log 為純 markdown 檔，移除規格後仍可手動產出/不產出 |
| **回滾驗證** | `make test` 全綠；`/asp-plan` 跑完 ADR 不再自動 spawn subagent；`grep -c "auto-gate" .claude/skills/asp/asp-plan.md` = 0 |
| **回滾已測試** | ☐ 未測（落地時補一輪 rollback drill） |

---

## 📐 G2 PENDING 註解例外規則（補 ADR-009 open question #2）

> ADR-009 v3 N=1 trial 顯示：G2 對 SPEC 內合法 `PENDING (Stage N)` 註解誤判為 WARN（如 SPEC-005 Stage 1 的 6 條 PENDING automated_checks）。本節定義 G2 subagent prompt 必須採用的例外規則，避免重現該噪音。

### 規則內容（G2 subagent prompt 必須 verbatim 包含）

```
## G2 PENDING 例外規則（reviewer 必讀）

當 SPEC 內出現 `PENDING` 註解時，**不可**立即判定為 Done When 不完整。先做下列三項判斷：

1. **PENDING 是否有 Stage 標籤**：例如 `PENDING (Stage 2)` 或註解「Stage 1 active check 1 條，6 條 PENDING 將於 Stage 2 補上」。若有，**視為合法 staged-rollout 標記，不 WARN**。
2. **PENDING 是否出現在 automated_checks 的 cmd 欄位內**：若 PENDING 是實際 shell command（如 `cmd: "PENDING tests/foo.sh"`），則 **WARN**（這是真實的缺漏，不是聲明性 placeholder）。
3. **PENDING 是否伴隨明確的 trigger 條件**：例如「等 Stage 2 PR 補上」「ADR-NNN Accept 後啟用」。若有，**視為合法**；若無 trigger、純粹「之後再說」→ **WARN**。

裁判表：

| PENDING 出現位置 | 帶 Stage 標籤 | 帶 trigger 條件 | 判定 |
|------------------|--------------|----------------|------|
| automated_checks cmd 欄內（shell 命令位置） | 任何 | 任何 | **WARN**（真實缺漏） |
| automated_checks description 欄內 | 是 | 任何 | PASS（合法 staged） |
| automated_checks description 欄內 | 否 | 是 | PASS（合法 deferred） |
| automated_checks description 欄內 | 否 | 否 | **WARN**（純粹拖延） |
| manual_checks checkbox 內 | 任何 | 任何 | PASS（checkbox 本來就是人類驗證） |
| SPEC 正文其他段落（如 Edge Cases） | 任何 | 任何 | PASS（非 Done When 範圍） |

**簡記**：「Stage 標籤 + trigger 條件 至少一項，且不在 shell command 位置」→ PASS。
```

### 為何這條規則放在 SPEC-006 而非 asp-gate.md 本體

G2 prompt 模板現存於 `.claude/skills/asp/asp-gate.md`，但本 SPEC 落地時**必須**把上述規則文字 verbatim 插入 G2 prompt 區段。本 SPEC 是規則的權威來源，asp-gate.md 是其消費端。Stage 2 實作步驟見「附錄 A：實作落地藍圖」。

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入 | 預期 | 場景 |
|---|------|------|------|------|
| P1 | ✅ 正向 | `git add docs/adr/ADR-010-foo.md` 後跑 mock asp-plan Step 5 | 觸發 G1，產生 `.asp-gate-log/...-G1-ADR-010.md`，主對話有摘要 | S1 |
| P2 | ✅ 正向 | `git add docs/adr/ADR-010-foo.md docs/specs/SPEC-007-bar.md` | G1+G2 並行 spawn，各一個 log | S2 |
| P3 | ✅ 正向 | `git add .claude/skills/asp/asp-plan.md`（只動 skill） | 不觸發任何 gate，主對話 echo skip message | S3 |
| N1 | ❌ 負向 | `git add docs/adr/README.md` | 不觸發 G1（glob 不命中） | S4 |
| N2 | ❌ 負向 | subagent API timeout | 寫 bypass log reason=spawn-failure，plan 仍完成 | S5 |
| N3 | ❌ 負向 | AI 試圖跳過（context budget 藉口） | 必須走 bypass 流程或被 Step 9.6 抓出 | S6 |
| B1 | 🔶 邊界 | ADR rename (git mv) | 觸發 G1（視同新增） | S7 |
| B2 | 🔶 邊界 | ADR Status only 修改 | 仍觸發 G1 | S8 |
| B3 | 🔶 邊界 | ADR 刪除 (git rm) | 不觸發，echo supersede 提示 | S9 |
| B4 | 🔶 邊界 | `.asp-gate-log/` 目錄不存在 | 自動 mkdir，不報錯 | S10 |
| B5 | 🔶 邊界 | 同一 plan 修改 2 個 ADR | 2 個獨立 G1 log | S11 |

---

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: asp-plan Step 5 auto-gate 觸發機制
  作為 ASP 框架使用者
  我想要 AI 寫完 ADR/SPEC 後自動執行 G1/G2 subagent review
  以便設計問題在 plan 階段攔截、不沉澱進實作 commit

  Background:
    Given ADR-009 已 Accepted
    And SPEC-006 已落地（asp-plan.md / asp-ship.md 已更新）
    And `.asp-gate-log/` 目錄存在或可建立

  # --- 正向場景 ---

  Scenario: S1 — 修改 ADR 自動觸發 G1
    Given `git diff --cached --name-only` 含 "docs/adr/ADR-010-foo.md"
    When AI 完成 asp-plan Step 5 寫入 ADR-010
    Then AI 必須 spawn G1 subagent（不問使用者）
    And `.asp-gate-log/{timestamp}-G1-ADR-010.md` 被建立
    And 主對話包含「asp-gate auto-review 結果」表格
    And gate log frontmatter 含 trigger_commit + subagent_type + result

  Scenario: S2 — 同時修改 ADR + SPEC
    Given staged diff 同時命中 ADR + SPEC glob
    When asp-plan Step 5 完成
    Then G1 + G2 並行 spawn
    And 兩個 gate log 各自獨立建立

  Scenario: S3 — 純 skill 修改不觸發
    Given staged diff 只含 ".claude/skills/asp/*.md"
    When asp-plan Step 5 完成
    Then 不 spawn 任何 subagent
    And 主對話 echo「無 ADR/SPEC 變更，跳過 auto-gate」（決策痕跡）

  # --- 負向場景 ---

  Scenario: S4 — docs/adr/README.md 不算 ADR
    Given staged diff 含 "docs/adr/README.md"
    When asp-plan Step 5 完成
    Then 不 spawn G1（glob 不命中 ADR-NNN pattern）

  Scenario: S5 — subagent spawn 失敗
    Given subagent API 回 500 / timeout
    When AI spawn G1
    Then 寫 .asp-bypass-log.ndjson 一行 step=auto-gate reason=spawn-failure
    And 主對話 echo「⚠️ auto-gate spawn 失敗」
    And plan 流程仍完成（不阻擋）

  Scenario: S6 — AI 試圖以 context budget 為由跳過
    Given staged diff 命中 ADR glob
    And AI context 用量 > 80%
    When AI 處理 Step 5 結尾
    Then AI 必須 spawn G1 或顯式 bypass（寫 ndjson）
    And 不可只 echo「context 緊張，略過 gate」而不留痕

  # --- 邊界場景 ---

  Scenario Outline: S7-S11 — rename / status-only / delete / mkdir / 多 ADR
    Given staged diff 場景 "<scenario>"
    When asp-plan Step 5 完成
    Then 行為符合 "<expected>"

    Examples:
      | scenario               | expected                              |
      | git mv ADR-009 ADR-010 | 觸發 G1（視同新增）                    |
      | ADR Status only 修改   | 觸發 G1                               |
      | git rm ADR-007         | 不觸發 + echo supersede 提示          |
      | .asp-gate-log/ 不存在  | 自動 mkdir 後寫入                     |
      | 2 個 ADR 同 plan       | 2 個獨立 G1 log，並行                 |
```

---

## ✅ 驗收標準（Done When）

### 🤖 automated_checks（必填）

```yaml
# 註（G2 review F-4）：下列 test_*.sh / grep 檢查為 G4（實作）驗收標準，非 G2（規格）標準。
# G2 驗證的是欄位完整性 / 二元可測性 / Gherkin 覆蓋 / 追溯性；
# 下列 shell 命令於實作完成後（G4）對 artifacts 執行。
automated_checks:
  - cmd: "tests/test_auto_gate_glob_matcher.sh"
    description: "Glob 表 P1/P3/N1/B1-B3 case 全綠（純函式測試，無 spawn）"
  - cmd: "tests/test_auto_gate_log_write.sh"
    description: "Gate log 檔名 pattern + frontmatter schema 符合 SPEC"
  - cmd: "tests/test_auto_gate_summary.sh"
    description: "主對話摘要文字格式符合 fixture"
  - cmd: "tests/test_auto_gate_skip_message.sh"
    description: "Glob 未命中時 echo 跳過訊息"
  - cmd: "tests/test_auto_gate_bypass_log.sh"
    description: "Spawn 失敗 / 顯式 bypass 時 .asp-bypass-log.ndjson 寫入正確 schema"
  - cmd: "tests/test_ship_step96.sh"
    description: "asp-ship Step 9.6 偵測 commit 含 ADR/SPEC 但缺 gate log → WARN"
  - cmd: "tests/test_asp_plan_step5_rationalization.sh"
    description: "asp-plan.md 含 Common Rationalizations 段落且涵蓋 R1-R7 七條初始集（每條 grep 對應反駁關鍵字）"
  - cmd: "grep -q '## Step 5\\.[0-9]\\+ — auto-gate' .claude/skills/asp/asp-plan.md"
    description: "asp-plan.md 含 Step 5.X auto-gate 子步驟標題（非單一關鍵字匹配，必須是 markdown header）"
  - cmd: "grep -q 'git diff --cached --name-only' .claude/skills/asp/asp-plan.md && grep -q 'docs/adr/ADR-\\[0-9\\]\\+' .claude/skills/asp/asp-plan.md"
    description: "asp-plan.md 確實使用機械 glob trigger（git diff 命令 + glob pattern）"
  - cmd: "grep -q '### Step 9\\.6' .claude/skills/asp/asp-ship.md"
    description: "asp-ship.md 含 Step 9.6 auto-gate log 後驗段落"
  - cmd: "grep -q 'auto-gate' CLAUDE.md && grep -q 'on-demand' CLAUDE.md"
    description: "CLAUDE.md 強制力架構表已依 ADR-009 選項 (c) 更新：L3 行含 auto-gate（SPEC-006 落地註記）、L4 行維持 on-demand（G2 review F-1 修正：原檢查為選項 (b) 撰寫，對已採用的選項 (c) 為 false-fail）"
```

### 👤 manual_checks

- [x] `.claude/skills/asp/asp-plan.md` Step 5 文字含 mandatory sub-step（Step 5.5）+ 「Common Rationalizations」段落（R1-R7）（2026-06-11）
- [x] `.claude/skills/asp/asp-ship.md` Step 9.6 加 gate-log 後驗（2026-06-11）
- [x] `CLAUDE.md` 強制力架構表同步（ADR-009 開放問題 #1 選項 (c)：L3 含 auto-gate 落地註記、L4 維持 on-demand）（2026-06-11）
- [x] CHANGELOG.md 加 Unreleased 條目（2026-06-11）
- [x] `docs/where-to-start.md` 提到 auto-gate 機制（2026-06-11）

---

## 🔗 追溯性（Traceability v2）

```yaml
traceability:
  candidate_files:
    - path: ".claude/skills/asp/asp-plan.md"
      role: implementation
    - path: ".claude/skills/asp/asp-ship.md"
      role: implementation
    - path: "CLAUDE.md"
      role: documentation
    - path: ".asp-gate-log/.gitkeep"
      role: scaffold
    - path: "tests/test_auto_gate_glob_matcher.sh"
      role: test
    - path: "tests/test_auto_gate_log_write.sh"
      role: test
    - path: "tests/test_auto_gate_summary.sh"
      role: test
    - path: "tests/test_auto_gate_skip_message.sh"
      role: test
    - path: "tests/test_auto_gate_bypass_log.sh"
      role: test
    - path: "tests/test_ship_step96.sh"
      role: test
    - path: "tests/test_asp_plan_step5_rationalization.sh"
      role: test
    - path: "tests/fixtures/auto-gate/"
      role: test-fixture
    - path: ".claude/skills/asp/asp-gate.md"
      role: implementation  # G2 PENDING 例外規則（A.3）
    - path: "docs/where-to-start.md"
      role: documentation
    - path: ".asp-gate-log/20260611T061000Z-G2-SPEC-006.md"
      role: audit-trail  # 本 SPEC 自身的 G2 review，機制第一筆記錄
  last_verified: "2026-06-11"
```

---

## 📋 Common Rationalizations 初始集（要被 asp-plan.md 採用）

> 任何下列 AI / 使用者藉口都**不可**作為跳過 auto-gate 的理由。若真要跳過，**必須**走 bypass 流程寫 `.asp-bypass-log.ndjson`。

| # | 藉口 | 反駁 |
|---|------|------|
| **R1** | 「這個 ADR 太小，不值得 spawn subagent」 | 「太小」是主觀判斷，正是 P2 要關閉的 rationalization 面。Trial 期觀察噪音率，若真的低價值會在 metric 上反映 |
| **R2** | 「我（AI）腦中已驗證一致性，沒問題」 | 獨立 context 才是 review 的本質。AI 自我驗證 = 同一 context 內的判斷，已被 N=1 trial 證實會漏（WARN 2.6 workflow 用詞就是 AI 自己沒抓到） |
| **R3** | 「使用者趕時間，跳過 gate 比較快」 | Plan 階段 catch 比 ship 後 catch 便宜 10x。短期省 2-3 分鐘 = 長期欠技術債 |
| **R4** | 「這只是 Draft ADR，內容會再改」 | Draft 本身就是要 review 的對象 — review 的價值是在 Draft 階段抓設計問題。等 Accepted 才 review 為時已晚 |
| **R5** | 「Context budget 緊張，沒 quota spawn subagent」 | Subagent 在獨立 context，不佔主對話 budget。若真的是 API quota 問題 → 走 bypass 顯式寫 ndjson，不可隱式跳過 |
| **R6** | 「我已經跑過 G1 了，這次只是修錯字」 | typo 修改不命中 N3 rationalization — 但 glob 仍命中，仍觸發。Trial 期觀察是否噪音過高再決定是否加 content-hash threshold（不在本 SPEC 範圍） |
| **R7** | 「subagent 之前抓的 WARN 都是噪音，這次八成也是」 | 訊噪比由 metric 機械統計，不可由 AI 預判。預判即為自我偏見 |

---

## 📊 可觀測性

| 面向 | 說明 |
|------|------|
| **關鍵指標** | (1) auto-gate 觸發率（分母 = git log 中的 ADR/SPEC commits，分子 = `.asp-gate-log/` 對應 entries）；(2) auto-gate 訊噪比（真實 catch ÷ 噪音 WARN，需人工標註）；(3) bypass 比例（step=auto-gate 的 ndjson 條目數 / 觸發次數） |
| **日誌** | `.asp-gate-log/*.md`（每次 spawn 一個）+ `.asp-bypass-log.ndjson`（每次 bypass 一行） |
| **告警** | Trial 期內任一 plan 跳過 auto-gate 而未寫 bypass → 視為 ADR-009 機制失效，立即 reality-check |
| **如何偵測故障** | `make audit-health` 加項：(a) `.asp-gate-log/` 目錄存在；(b) 最近 30 天 git log 內 ADR/SPEC commits 與 gate log entries 數量比 ≥ 90% |

---

## 🚫 禁止事項（Out of Scope）

- **不**設計 G3/G4/G5/G6 自動化（本 SPEC 只覆蓋 G1+G2，其他 gate 待 trial 結果決定）
- **不**設計專職 subagent 路由（reality-checker / test-engineer 與本 SPEC 無關，由未來 ADR 決定）
- **不**修改既有 `/asp-gate` skill — 它仍是手動入口，本 SPEC 只新增自動入口
- **不**做 content-hash threshold（typo 偵測）— 留給 trial 後評估
- **不**做 `.asp-gate-log/` 的 retention / archive — 暫時保留全部
- **不**搬遷 `.asp-bypass-log.json` → `.ndjson`（那是 ADR-006/008 的工作；本 SPEC 假設遷移已完成或進行中）
- **不**修改 hook（`.claude/settings.json`、`.asp/hooks/*`）— 純文件層 prompt engineering
- **`.asp-gate-log/` 加入 `.gitignore` 還是 commit？**：**Commit**（審計痕跡需要 version control）。但 `.asp-gate-log/.gitignore` 排除暫存檔（例：`.tmp`、`.in-progress`）

---

## 📎 參考資料

- ADR-009（本 SPEC 對應）
- ADR-008（Step 9.5 reserver — 與本 SPEC Step 9.6 並列）
- ADR-006（`.asp-bypass-log.ndjson` 為正式格式）
- ADR-004（telemetry — 本 SPEC `.asp-gate-log/` 為未來對接點）
- CLAUDE.md「強制力架構」表 L4 行（Accept ADR-009 時必須同步更新）
- 既有 `.claude/skills/asp/asp-ship.md` 「Common Rationalizations」段落（line ~234）為本 SPEC R1-R7 結構之模板
- 既有 `.claude/skills/asp/asp-gate.md` G1/G2 prompt body — 直接複用為 subagent prompt 模板，不重寫

---

## 附錄 A：實作落地藍圖（Stage 2 implementer 使用）

### A.1 asp-plan.md Step 5 補丁（literal prose，verbatim 採用）

在 `.claude/skills/asp/asp-plan.md` 既有 Step 5 的**呈現模板（``` 圍欄）結束之後、「等待用戶明確確認…」句之前**插入下列段落（G2 review F-2 修正：原錨點「下一步清單之前」位於 code fence 內，會產生三種解讀；本錨點唯一。執行語意：呈現摘要 → 跑 auto-gate → 等使用者確認）：

```markdown
---

## Step 5.5 — auto-gate（ADR-009 強制機制）

> **本步驟不可跳過**。跳過必須走既有 `⚠️ ASP BYPASS` 流程寫 `.asp-bypass-log.ndjson`。

### 5.5.1 機械觸發判斷

於 Step 5 寫完 ADR / SPEC 後，**必須**執行下列命令並依結果動作。**禁止以 AI 啟發式判斷取代**（「這次 plan 算不算 ADR 等級」由 glob 決定，不由 AI 決定）：

\```bash
staged=$(git diff --cached --name-status)
hits_adr=$(echo "$staged" | grep -v '^D' | awk '{print $NF}' | grep -cE '^docs/adr/ADR-[0-9]+.*\.md$' || true)
hits_spec=$(echo "$staged" | grep -v '^D' | awk '{print $NF}' | grep -cE '^docs/specs/SPEC-[0-9]+.*\.md$' || true)
deleted_gov=$(echo "$staged" | grep '^D' | awk '{print $NF}' | grep -cE '^docs/(adr|specs)/(ADR|SPEC)-[0-9]+.*\.md$' || true)
\```

- `hits_adr > 0` → **必須** spawn G1 subagent（每個命中的 ADR 一個 subagent，並行）
- `hits_spec > 0` → **必須** spawn G2 subagent（同上）
- `deleted_gov > 0` → echo「⚠️ ADR/SPEC 刪除偵測 — 請確認是 supersede 流程而非誤刪」（提示，非阻擋；E3）
- 兩者皆 0 → 在 Step 5 結尾陳述「無 ADR/SPEC 變更，跳過 auto-gate」（這句話必填，作為決策痕跡）

### 5.5.2 Subagent 呼叫（使用 Agent tool）

- `subagent_type`: `general-purpose`（trial 期；ADR-009 trial 完可路由到 reality-checker / test-engineer）
- `model`: `sonnet`
- Prompt body：直接引用 `.claude/skills/asp/asp-gate.md` 內 G1 / G2 prompt 模板，填入 target 路徑

### 5.5.3 結果處理

- 報告寫入 `.asp-gate-log/{ISO_TIMESTAMP_UTC}-G{n}-{TARGET_ID}.md`（檔名+frontmatter schema 見 SPEC-006「Gate log 寫入格式」）
- 主對話**必須** echo「asp-gate auto-review 結果」摘要表（格式見 SPEC-006）
- BLOCKER（FAIL）→ 暫停 plan 流程，等使用者裁決
- WARN → 列入摘要，不阻擋繼續

### 5.5.4 Common Rationalizations（禁止藉口）

> 執行本 step 時，AI **必須**先檢視此表。下列任何藉口都不可作為跳過理由。

| # | 藉口 | 反駁 |
|---|------|------|
| R1 | 「這個 ADR 太小，不值得 spawn subagent」 | 「太小」是主觀判斷，正是 ADR-009 P2 要關閉的 rationalization 面 |
| R2 | 「我（AI）腦中已驗證一致性，沒問題」 | 獨立 context 才是 review 的本質，自我驗證已被 N=1 證實會漏 |
| R3 | 「使用者趕時間，跳過 gate 比較快」 | Plan 階段 catch 比 ship 後 catch 便宜 10x |
| R4 | 「這只是 Draft ADR，內容會再改」 | Draft 本身就是 review 的對象 |
| R5 | 「Context budget 緊張，沒 quota spawn subagent」 | Subagent 在獨立 context，不佔主對話 budget |
| R6 | 「我已經跑過 G1 了，這次只是修錯字」 | typo 仍命中 glob，仍觸發；trial 期觀察噪音率再決定 |
| R7 | 「subagent 之前抓的 WARN 都是噪音，這次八成也是」 | 訊噪比由 metric 機械統計，不可由 AI 預判 |

任何跳過都必須執行 `make asp-bypass-record SKILL=asp-plan STEP=Step5.5 REASON="..."`，寫入 `.asp-bypass-log.ndjson`。
```

### A.2 asp-ship.md Step 9.6 補丁（literal prose，verbatim 採用）

在 `.claude/skills/asp/asp-ship.md` 既有 Step 9 與 Step 10 之間插入下列段落：

```markdown
---

### Step 9.6 — auto-gate log 後驗（ADR-009 強制機制）

> **目的**：偵測「commit 含新 ADR/SPEC 但無對應 `.asp-gate-log/` 紀錄」— 代表 plan 階段 auto-gate（ADR-009 Step 5.5）失效（AI 跳過、API 失敗、或忘記）。

**檢查命令**：

\```bash
# 注意（G2 review F-3）：本片段設計為獨立執行（standalone script / AI 執行的 bash 區塊），
# 不可被 source —— exit 0 會結束呼叫端 shell。
adr_specs=$(git diff --cached --name-only | grep -E '^docs/(adr|specs)/(ADR|SPEC)-[0-9]+.*\.md$' || true)
[[ -z "$adr_specs" ]] && exit 0  # 無 ADR/SPEC 變更，跳過

missing=0
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    id=$(basename "$f" | grep -oE '(ADR|SPEC)-[0-9]+')
    if ! ls .asp-gate-log/*-G[12]-"${id}"*.md >/dev/null 2>&1; then
        echo "⚠️  Step 9.6 WARN：$f staged 但無 .asp-gate-log/*-${id}*.md"
        echo "    → 補跑 /asp-gate G1 或 G2，或走 bypass 流程記錄理由"
        missing=$((missing+1))
    fi
done <<< "$adr_specs"
\```

| 條件 | 嚴重度 |
|------|--------|
| `missing == 0` | ✅ PASS（commit 繼續） |
| `missing > 0` 且非 bypass | 🟡 **WARN**（不阻擋 commit；記入 evidence） |
| 同一 ADR/SPEC 連續 3 次 commit 都 WARN | 🔴 **BLOCK**（下次 `asp-audit` 強制 reality-check） |

**處置**：WARN-GO 走既有 Step 10b bypass 流程（`make asp-bypass-record SKILL=asp-ship STEP=Step9.6 REASON="..."`）。
```

### A.3 G2 prompt 模板擴充（asp-gate.md 修改）

在 `.claude/skills/asp/asp-gate.md` 既有 G2 prompt body 結尾**之前**插入「G2 PENDING 例外規則」段落 verbatim — 內容見本 SPEC「G2 PENDING 註解例外規則」section 中的程式碼區塊。

### A.4 CLAUDE.md 強制力架構表更新（ADR-009 open question #1 落地）

依 ADR-009 開放問題 #1，CLAUDE.md 強制力架構表 L4 行的更新有三種擇法。**Accept ADR-009 的 reviewer 必須擇一**並在同一 commit 改表：

- **選項 (a) 合併 L3+L4**：把 L4 行刪除，併入 L3 行（敘述改為「Skill Gates + auto-spawn subagent」）
- **選項 (b) 新增 L3.5 行**：保留 L3 / L4，中間插入 L3.5「Auto-spawn Subagent QA | asp-plan Step 5.5 + asp-ship Step 9.6 | 結構化軟性（強制觸發、可 bypass）」
- **選項 (c) 改寫 L4 既有行**：L4 改為「on-demand reality-check（人工觸發）」+ 新增註腳「auto-spawn 部分歸入 L3」

**建議**：選項 (b)，理由是保留 L3/L4 原本語義（Skill Gates / Subagent QA 是兩種不同強度），auto-spawn 是橋接案例，自然屬於中間層。但最終由 reviewer 決定。

### A.5 `.asp-gate-log/` 目錄初始化

- 建立 `.asp-gate-log/` 目錄與 `.asp-gate-log/.gitkeep`
- 建立 `.asp-gate-log/.gitignore` 內容為 `*.tmp` 與 `*.in-progress`（排除暫存檔）
- `.asp-gate-log/*.md` 本身**進** version control（審計痕跡）

### A.6 測試骨架

`tests/test_auto_gate_glob_matcher.sh` 範例（其他測試類推）：

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh" 2>/dev/null || true

# P1: ADR glob 應命中
echo "docs/adr/ADR-010-foo.md" | grep -qE '^docs/adr/ADR-[0-9]+.*\.md$' \
    && echo "P1 PASS" || { echo "P1 FAIL"; exit 1; }

# N1: docs/adr/README.md 不應命中
! (echo "docs/adr/README.md" | grep -qE '^docs/adr/ADR-[0-9]+.*\.md$') \
    && echo "N1 PASS" || { echo "N1 FAIL"; exit 1; }

# B1: rename (git mv 後 --name-only 給的還是新檔名) 應命中
echo "docs/adr/ADR-010-renamed.md" | grep -qE '^docs/adr/ADR-[0-9]+.*\.md$' \
    && echo "B1 PASS" || { echo "B1 FAIL"; exit 1; }

echo "All glob tests passed"
```
