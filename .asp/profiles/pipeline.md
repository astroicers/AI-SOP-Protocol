# Pipeline Profile — 6 階段品質管線

<!-- requires: global_core, system_dev, task_orchestrator -->
<!-- optional: multi_agent, autonomous_dev, reality_checker -->
<!-- conflicts: (none) -->

適用：所有任務類型。將 task_orchestrator.md 的隱式工作流轉為顯式管線 + 品質門。
載入條件：`mode: multi-agent` 時自動載入，`mode: auto` 時按需動態載入

> **設計原則**：
> - 不重新發明流程——在既有 execute_*() Phase 之間加上品質門
> - `mode: single` 時管線邏輯由 task_orchestrator.md 的 execute_*() 內建處理，無需本 profile
> - `mode: auto` 時由 auto_select_mode() 動態判斷是否載入
> - `mode: multi-agent` 時各階段由專精角色負責

---

## 管線階段定義

```
SPECIFY ──G1──▶ PLAN ──G2──▶ FOUNDATION ──G3──▶ BUILD ──G4──▶ HARDEN ──G5──▶ DELIVER ──G6──▶ DONE
```

### 階段 ↔ Agent ↔ Gate 映射

| 階段 | 對應 execute_new_feature() Phase | 主要 Agent | 支援 Agent | 品質門 |
|------|--------------------------------|-----------|-----------|--------|
| **SPECIFY** | Phase 1: 架構影響評估 | arch, dep-analyst | — | G1 |
| **PLAN** | Phase 2: SPEC 建立 + Phase 3: Gates | spec | reality | G2 |
| **FOUNDATION** | Phase 5: TDD 測試撰寫 | tdd | qa | G3 |
| **BUILD** | Phase 6: 實作 | impl | integ | G4 |
| **HARDEN** | Phase 7: 驗證 + Phase 8: 提交前自審 | qa, sec | reality | G5 |
| **DELIVER** | Phase 9: 文件管線 + Phase 10: 完成報告 | doc | reality | G6 |

### 階段可跳過規則

非所有任務都需要完整 6 階段。根據 team_compositions.yaml 的 pipeline_phases 決定：

| 場景 | 跳過的階段 | 原因 |
|------|----------|------|
| BUGFIX_trivial | SPECIFY, PLAN, FOUNDATION, DELIVER | 快速路徑：直接 BUILD → HARDEN |
| BUGFIX_hotfix | SPECIFY, PLAN, FOUNDATION | 快速路徑：BUILD → HARDEN → DELIVER |
| MODIFICATION_L1_L2 | SPECIFY | 無架構影響 |

---

## 品質門定義

> **⟦四層標記⟧**(ADR-034)——底下每個檢查點旁都標了它**實際上是什麼**。
> 形式(`FUNCTION`/`IF`/`RETURN`)讓四種性質不同的東西長得一樣,執行者因此期待精確,
> 並把「本來就要靠判斷」與「沒實作」一律回報為缺陷(**六道 gate 各派一次不知情執行者,共 50 條**)。
>
> | 標記 | 意思 | 執行者該怎麼做 |
> |---|---|---|
> | `⟦mechanical⟧` | **無需語意理解即可判定**。分兩種,標記會註明是哪種 | (a) **有指令**:真的去跑,**目標專案沒有該 target 時標 not-applicable,不是 passed**;(b) **無指令、可自行機械判定**(檔案存在性、欄位存在性、字串計數、表格解析):自己判,但**在證據裡註明結論來自你自己寫的 grep/腳本,不是 ASP 的儀器** |
> | `⟦judgment⟧` | 需要語意理解,**且不預期會機械化** | 自行裁量,但**必須寫依據**。這不是缺陷 |
> | `⟦debt⟧` | 被呼叫、**零實作**,但可機械化 | 依註解描述自行判斷;**回報它未實作是正確的** |
> | `⟦intent⟧` | config 定義了門檻但**沒有任何一行讀它** | **非生效門檻**,不要當成會被檢查的東西 |
>
> 標記**不改變任何 gate 的通過與否**。`debt` / `intent` 兩層是待辦清單,不是現況描述。
>
> **標記不會讓缺口消失。** 標了 `debt` 的東西仍然沒實作,標了 `intent` 的門檻仍然沒接線
> —— 回報它們是**正確的**,那不是誤報。標記只解決一件事:讓你不必猜哪些是裁量、哪些是欠債。
> (2026-08-18 後測實證:標記後回報數 50 → 60,**沒有下降**。詳見 ADR-034 Verification Evidence。)

### G1: Architecture Gate（SPECIFY → PLAN）

```
FUNCTION evaluate_G1(artifacts):
  checks = []

  // ⟦judgment⟧ `artifacts.requires_adr` **全 repo 只出現在本檔**,沒有任何欄位或腳本產生它。
  //   實務上它問的是「這個任務有沒有架構影響」——語意問題,不預期機械化。
  //   判斷時看:是否新增/更換外部依賴、是否改變模組邊界或資料流、是否影響其他 profile 的錨點。
  IF artifacts.requires_adr:
    // ⟦mechanical⟧ 檔案存在性。
    IF NOT exists(artifacts.adr):
      RETURN GATE_FAIL("ADR 不存在（鐵則）")
    // ⚠️ 2026-08-18 G1 前測發現兩個問題，一併修：
    //   (1) 原本的 ELSE 綁在 FIRM 那個 IF 上，於是 Proposed / Superseded / Rejected /
    //       空字串 / 拼錯**全部**落進 `checks.append("ADR Accepted ✅")` ——
    //       這段**從來沒有真的斷言 status == "Accepted"**。它蓋章的是 ASP 最硬的那條鐵則。
    //   (2) 精確比對讓小寫 `draft` 繞過鐵則 FAIL 再被蓋成 Accepted。
    //       機械後手 `.asp/checks/adr-draft.sh` 用的是 `grep -qiE`（大小寫不敏感、抓得到），
    //       **兩層的比對規則不一致**；此處對齊之。
    // ⟦mechanical⟧(有指令)機械後手已存在且今天就能跑:`.asp/checks/adr-draft.sh [專案根]`
    //   (狀態錨定「狀態/Status」label、正文 legend 不誤判、無 ADR 目錄 → exit 200 skip)。
    //   本 gate 不呼叫它;**若你要跑它當佐證可以,但兩層衝突時以 gate 的判定為準**。
    //
    // ⚠️ **2026-08-18 更正我自己的錯誤宣稱(由 G1 後測抓到)**:#112 在此寫「兩層的判定規則
    //   已對齊(皆大小寫不敏感)」——**那只對齊了大小寫,沒對齊比對模式,所以宣稱是假的**。
    //   後手是**在 label cell 值段內做 `\bDraft\b` 詞界子字串搜尋**(adr-draft.sh L39 的
    //   `grep -qiE "${TABLE_RE}\bDraft\b"`);pseudocode 原本做**整串精確相等**。
    //   拿該腳本自己 L13 文件化的合法格式當反例:`| 狀態 | Draft(待確認) |`
    //     → 後手命中 → exit 1 blocker;pseudocode 得 "draft(待確認)" ≠ "draft" → **不 FAIL**。
    //   **#112 自陳修掉的鐵則 fail-open,在「子字串 vs 精確相等」這個維度上仍然開著。**
    //   本次改為詞界比對,與後手同一條規則——這是**完成 #112 宣稱過但沒做完的事**,
    //   不是新決策;方向上只是讓 gate 不再比已上線的機械後手更寬鬆。
    adr_status = lowercase(trim(artifacts.adr.status))     // 值段可能帶包裝/後綴,故下方用詞界比對
    IF adr_status CONTAINS_WORD "draft":
      RETURN GATE_FAIL("ADR 為 Draft 狀態，禁止實作（鐵則）")
    ELIF adr_status CONTAINS_WORD "firm":
      checks.append("ADR FIRM 🟡（POC 驗證中，允許繼續，記錄 bypass log）")
      YELLOW_FLAG("ADR 尚未正式 Accepted，請盡快升級")
    ELIF adr_status CONTAINS_WORD "accepted":
      checks.append("ADR Accepted ✅")
    ELSE:
      // 不擋（A18 寧漏報不誤報），但**不得宣稱 Accepted**
      checks.append("ADR 狀態未辨識：{artifacts.adr.status} —— 未驗證")
      YELLOW_FLAG("ADR 狀態「{artifacts.adr.status}」不在 Draft/FIRM/Accepted 之列，請人工確認")

  IF artifacts.dependency_graph:
    // ⟦debt⟧ `has_cycle()` 未實作。標準有向圖環偵測(DFS + 三色標記),估 ~30 行。
    //   屬 ADR-034 D4 那份 ~150 行清單。**注意 `artifacts.dependency_graph` 同樣無產生來源**,
    //   所以現況等同這整段從不執行。
    IF has_cycle(artifacts.dependency_graph):
      RETURN GATE_FAIL("依賴圖存在循環")
    checks.append("依賴圖無環 ✅")

  IF NOT artifacts.requires_adr AND NOT artifacts.dependency_graph:
    checks.append("無架構影響，G1 自動通過 ✅")

  // ⟦intent⟧ `G1_architecture` 的 2 個鍵(`max_draft_adrs_blocking`、`dependency_cycle_allowed`)
  //   **沒有任何一行讀取**。G1 從不 load thresholds。兩者的語意目前由上方條件式硬編
  //   (Draft → FAIL、有環 → FAIL),數值改動不會生效。

  RETURN GATE_PASS(evidence=checks)
```

### G2: Specification Gate（PLAN → FOUNDATION）

```
FUNCTION evaluate_G2(artifacts):
  checks = []
  issues = []

  // ⟦mechanical⟧ 七欄位存在性 = 對 SPEC 抓標題。
  // ⟦intent⟧ 但 `G2_specification.required_spec_sections: 7` **沒被讀**——下面是硬編清單。
  //   改 config 的 7 不會改變這裡檢查幾個欄位。
  required_fields = ["Goal", "Inputs", "Expected Output", "Side Effects",
                     "Edge Cases", "Done When", "Traceability"]
  FOR field IN required_fields:
    IF NOT artifacts.spec.has(field):
      issues.append("SPEC 缺少欄位：{field}")

  // ⟦judgment⟧ `is_binary_testable()` 判一句散文條件能不能二元測試——語意的,不預期機械化。
  //   判斷時看:有沒有可觀測的受詞與明確的成功值(「回傳 200」可測;「效能良好」不可測)。
  FOR criterion IN artifacts.spec.done_when:
    IF NOT is_binary_testable(criterion):
      issues.append("Done When '{criterion}' 無法二元測試")

  IF issues:
    RETURN GATE_FAIL(issues)

  // L99 刻意保持 ✅：它真的被守住——上面的 FOR 對任何缺欄位都會 append issue，
  // 走到這裡就代表七欄位齊全。不是每個綠勾都要改，只有空轉得出來的才要。
  checks.append("SPEC 七欄位完整 ✅")
  // 但這條是空轉的：done_when 為空時 FOR 跑 0 次、無 issue，卻宣告「全部可二元測試」。
  dw_state = "passed" IF LEN(artifacts.spec.done_when) > 0 \
             ELSE "not-applicable（Done When 為空，無可判定對象）"
  checks.append("Done When 可二元測試：{dw_state}")

  // Reality Checker 參與（如果 team 包含 reality）
  // ⟦judgment⟧ `reality_check()` 是 reality_checker.md 的 agent 判定,無機械判準。
  IF "reality" IN current_team:
    reality_verdict = reality_check(artifacts, "G2")
    IF reality_verdict.status == "NEEDS_WORK":
      RETURN GATE_FAIL(reality_verdict.evidence)
    checks.append("Reality Checker：passed")
  ELSE:
    // 證據誠實原則:原本整段靜默跳過,evidence 一字不提,
    // 讀者無法分辨「Reality 審過了」與「Reality 從沒進場」。
    // 本檔 L634 明寫「Reality Checker 參與 G2, G5, G6」,所以缺席本身是值得記錄的事實。
    checks.append("Reality Checker：skipped（\"reality\" 不在 current_team）")

  // v3.2: Gherkin 場景強制驗證
  IF severity != TRIVIAL:
    // 測試矩陣必須存在
    // ⟦mechanical⟧ 矩陣存在 + 正/負向列計數 = 解析 SPEC 的表格。
    // ⟦intent⟧ `min_test_matrix_positive/negative`(各 1)未被讀取;下方硬編 `== 0`。
    //   兩者目前語意等價,但把 config 調成 2 不會生效。
    IF NOT spec.has_test_matrix:
      issues.append("🔴 缺少測試矩陣（非 trivial 任務必須填寫）")
    ELSE:
      positive_count = count(row FOR row IN spec.test_matrix IF row.type == "正向")
      negative_count = count(row FOR row IN spec.test_matrix IF row.type == "負向")
      IF positive_count == 0:
        issues.append("🔴 測試矩陣缺少正向案例（至少 1 個）")
      IF negative_count == 0:
        issues.append("🔴 測試矩陣缺少負向案例（至少 1 個）")

    // ⟦judgment⟧ `config_only` **全 repo 只出現在本檔**,無資料來源——執行者自行認定。
    //   判斷時看:變更是否只動 config/資料檔而無邏輯分支變化。
    // ⟦intent⟧ `min_gherkin_scenarios: 2` 未被讀取——這裡只檢查「有沒有」,不檢查數量。
    IF NOT config_only AND NOT spec.has_scenarios:
      issues.append("🔴 缺少 Gherkin 驗收場景（非 trivial 任務必須撰寫）")

    // ⚠️ 守衛修正(2026-08-18,G2 實測):本段迭代 spec.test_matrix,原本卻掛在
    // `IF spec.has_scenarios` 底下。SPEC「有場景但無矩陣」時,上面的 has_test_matrix
    // 分支只 append issue、**不 return**,於是這裡會去迭代一個不存在的 test_matrix。
    // 兩個條件都要成立才做這個交叉比對。
    IF spec.has_scenarios AND spec.has_test_matrix:
      // ⟦mechanical⟧ 以下三段(引用一致性、重現場景、場景品質)全是字串/計數比對,
      //   對已解析的 SPEC 可直接判定,無裁量成分。
      FOR row IN spec.test_matrix:
        IF row.scenario_ref AND row.scenario_ref NOT IN spec.scenario_ids:
          issues.append("矩陣 {row.id} 引用場景 {row.scenario_ref} 不存在")

      // Bug 修復必須有重現場景
      IF task_type == "BUGFIX":
        has_repro = any(s.name CONTAINS "重現" OR s.name CONTAINS "reproduce" OR s.name CONTAINS "N1" FOR s IN spec.scenarios)
        IF NOT has_repro:
          issues.append("🔴 Bug 修復缺少重現場景")

      // 場景品質檢查（攔截敷衍場景）
      FOR scenario IN spec.scenarios:
        IF LEN(scenario.then_clauses) < 1:
          issues.append("場景 {scenario.id} 沒有 Then 斷言（敷衍場景）")
        IF scenario.given_clauses IS EMPTY AND scenario.background IS EMPTY:
          issues.append("場景 {scenario.id} 缺少 Given 前置條件")
        IF scenario.name MATCHES "it works|正常運作|成功|OK|works fine":
          issues.append("場景 {scenario.id} 名稱過於模糊：'{scenario.name}'")

  // v3.3: Observability 驗證
  // ⚠️ 2026-08-18(#105 Q4):原本寫
  //     `IF spec.is_user_facing OR spec.is_backend_api OR spec.is_data_processing:`
  //   那三個旗標**沒有任何資料來源**——SPEC 模板沒有這些欄位、`.ai_profile` 也不對應,
  //   執行者只能讀內文自行宣稱。實測 7/18 份真實 SPEC 缺 Observability,
  //   所以這個旗標在 39% 的案例上決定 🔴 BLOCKER 與 pass。
  //
  //   更根本的是:**適用性判準已經寫在 SPEC_Template.md L187**——
  //   「使用者面向功能必填(backend API、資料處理、排程任務)。純 UI 或 config 變更可標注 N/A。」
  //   pipeline 這三個旗標是那條規則的**複本,而且複本沒接上電**(ADR-031:同一意義兩處編碼會 drift)。
  //
  //   改為:**適用性由 SPEC 作者依模板判準表態,pipeline 不重新編碼**,只檢查作者有沒有表態。
  //   模板已允許標 N/A —— 與 Side Effects 的「若無跨模組影響,填『無』並說明理由」同慣例。
  //   ADR-034 分類上這是升級:judgment(執行者猜隱藏旗標)→ mechanical(區塊存在且非空)。
  // ⟦mechanical⟧ 只檢查「作者有沒有表態」(區塊存在且非空),適用性判準在 SPEC_Template L187。
  // ⟦intent⟧ `observability_required: true` 未被讀取;此處硬編為必要。
  IF NOT spec.has_observability:
    // 嚴重度:**擋 gate**。人類 2026-08-18 於 PR #108 明確裁決「維持擋」。
    //   理由:模板本來就寫「必填」;逃生門只是一行字(`N/A — <理由>`);
    //   改成 YELLOW_FLAG 會讓模板那條「必填」永遠是虛構的(ADR-023 治理劇場)。
    //   ⚠️ 這是**嚴格方向**的行為變更——改動前,執行者判 is_user_facing=false 時
    //   檢查根本不觸發;現在一律評估。若日後要放寬,換成 YELLOW_FLAG(...) 即可,
    //   但那會推翻一次已裁決的取捨,**應附新的實測資料**(例如逃生門造成的假擋率)。
    issues.append("🔴 缺少 Observability 區塊——不適用時請依 SPEC_Template L187 標 N/A 並說明理由")
  ELSE:
    checks.append("Observability 已定義 ✅")

  // v3.7: Done When 數量下限（quality-thresholds.yaml G2_specification.min_acceptance_criteria）
  IF severity != TRIVIAL:
    // ⟦mechanical⟧ **這是全檔僅有的兩處真的 load thresholds 之一**(另一處是 G5)。
    //   `min_acceptance_criteria` 是 23 個 gate threshold 鍵中 5 個生效鍵的第 1 個。
    thresholds = load(".asp/config/quality-thresholds.yaml")
    min_ac = thresholds.gates.G2_specification.min_acceptance_criteria  // 預設 3
    IF LEN(artifacts.spec.done_when) < min_ac:
      issues.append("🔴 Done When 數量不足：{LEN(artifacts.spec.done_when)} 條 < 最低要求 {min_ac} 條")
    ELSE:
      checks.append("Done When 數量 {LEN(artifacts.spec.done_when)} ≥ {min_ac} ✅")

  // v3.7: [UNVERIFIED] 標注檢查（quality-thresholds.yaml fact_verification.max_unverified_facts_in_spec）
  // ⟦mechanical⟧ 字串計數,grep 即可。
  // ⟦intent⟧ 但 `fact_verification.max_unverified_facts_in_spec`(值 0)**未被讀取**——
  //   下面硬編 `> 0`。目前與 config 值等價,把它調成 1 不會放寬。
  unverified_count = count_pattern("[UNVERIFIED]", artifacts.spec.content)
  IF unverified_count > 0:
    issues.append("🔴 SPEC 含 {unverified_count} 個 [UNVERIFIED] 標注——必須先完成 Fact Verification Gate 再提交 G2")
  ELSE:
    checks.append("無 [UNVERIFIED] 未驗證事實 ✅")

  IF issues:
    RETURN GATE_FAIL(issues)

  // ⟦intent⟧ G2 尚未被讀取的鍵:`required_spec_sections`、`max_open_questions`、
  //   `min_gherkin_scenarios`、`min_test_matrix_positive`、`min_test_matrix_negative`、
  //   `observability_required`(7 個中的 6 個)。其中 `max_open_questions: 0`
  //   **完全沒有對應的檢查邏輯**,不只是沒讀——SPEC 的 Open Questions 從未被計數。
  RETURN GATE_PASS(evidence=checks)
```

### G3: Test Readiness Gate（FOUNDATION → BUILD）

```
FUNCTION evaluate_G3(artifacts):
  checks = []
  issues = []

  // ⟦judgment⟧ `has_test_for()` 判一句散文條件與一堆測試檔的對應關係——語意的,不預期機械化。
  //   判斷時看:測試名稱/斷言是否針對該條件的受詞與成功值,而非只是檔案存在。
  FOR criterion IN artifacts.spec.done_when:
    IF NOT has_test_for(criterion, artifacts.test_files):
      issues.append("Done When '{criterion}' 無對應測試")

  // 測試全部 FAIL（證明它們在測試東西）
  // ⟦mechanical⟧(有指令)**目標專案須提供 `test-filter` target**。
  // ⚠️ 但這一行**無守衛**(G3 後測):真的沒有 target 時 `make` 以 "No rule to make target"
  //   非零退出,`all_passed` 與 `compilation_error` **雙雙為 false**,下面兩個 IF 靜靜地
  //   什麼都不 append —— 那不是「空轉」,是**產生一段沉默並繼續往下走**,而後續還會對一個
  //   語意上未定義的 `test_result` 取值。三態守衛遲至下方 `test_state` 才出現。
  //   (對照 L371 的 lint 有 `IF make_target_exists` 守衛,兩個 mechanical 檢查寫法不對稱。)
  test_result = EXECUTE("make test-filter FILTER={artifacts.spec.filter}")
  IF test_result.all_passed:
    issues.append("測試在實作前就全部通過——測試可能沒有在測東西")
  ELIF test_result.compilation_error:
    issues.append("測試編譯失敗：{test_result.error}")

  // v3.3: 測試品質檢查（防止空測試）
  FOR test_file IN artifacts.test_files:
    // ⟦debt⟧ `count_assertions()` 未實作,但**可機械化且很便宜**——regex 下一行就給了。
    //   估 ~20 行 shell。屬 ADR-034 D4 那份 ~150 行清單。
    assertion_count = count_assertions(test_file)
    // count_assertions 依語言：
    //   Go: count("assert", "require.")  Python: count("assert")  TS/JS: count("expect(")
    IF assertion_count == 0:
      issues.append("測試檔案 {test_file} 沒有任何 assertion（空測試）")

  IF spec.has_scenarios:
    total_assertions = sum(count_assertions(f) FOR f IN artifacts.test_files)
    IF total_assertions < LEN(spec.scenarios):
      issues.append("assertion 總數（{total_assertions}）少於場景數（{LEN(spec.scenarios)}）")

  // ⚠️ 這原本是 G3 唯一的失敗出口，而它**在下方 v3.2 場景區塊之前** ——
  //   那個區塊還會繼續 append issues，卻永遠不會被檢查，結尾又是無條件 RETURN GATE_PASS。
  //   等於「場景無對應測試」與「測試數量少於場景數量」兩條**是死碼**（2026-08-18 G3 前測發現）。
  //   本 guard 保留為早退；尾端另補一道。
  IF issues:
    RETURN GATE_FAIL(issues)

  // 兩條都會空轉：done_when 為空 → 上面的 FOR 跑 0 次；
  // 無測試檔或無 make test-filter target → all_passed/compilation_error 皆不成立。
  // 後者尤其嚴重：G3 是 Test Readiness Gate，
  // 「一個零測試的專案拿到『測試全部 FAIL(預期行為)✅』」正好否定這道 gate 的意義。
  dw_state   = "passed" IF LEN(artifacts.spec.done_when) > 0 \
               ELSE "not-applicable（Done When 為空）"
  // ⚠️ 2026-08-18 二次修正：初版（#106）只判「有沒有測試檔／target」，**從不讀 test_result**
  //   —— 於是「4 failed 1 passed」照樣被標成 passed，而這行字寫的是「測試**全部** FAIL」。
  //   G3 前測的執行者當場拒簽這行證據。partially-green 是假紅燈的主要形態：
  //   零 assertion 的測試對著 no-op 骨架自然會綠，它不會在 BUILD 期間為了正確的理由轉綠。
  test_state = "not-applicable（無測試檔或無 test-filter target——**不等於測試正確地失敗中**）"
  IF artifacts.test_files AND make_target_exists("test-filter"):
    IF test_result.failed_count == test_result.total_count:
      test_state = "passed（{test_result.total_count} 個全部 FAIL）"
    ELSE:
      // 不擋 gate（維持 #106 的取捨：標示誠實，不新增阻斷），但必須說實話
      test_state = "partial（{test_result.failed_count}/{test_result.total_count} FAIL —— 未達 must_fail_before_impl）"
      YELLOW_FLAG("G3 紅燈不完整：有測試在實作前已通過，可能沒在測東西")
  checks.append("Done When 有對應測試：{dw_state}")
  checks.append("測試全部 FAIL（預期行為）：{test_state}")

  // v3.2: 場景 ↔ 測試映射驗證
  IF spec.has_scenarios:
    // ⟦debt⟧ `has_test_for_scenario()` / `count_test_cases_for_spec()` 皆未實作。
    //   與上面的 `has_test_for()` 不同:這兩個比對的是**字面 ID**,不需要語意理解 → 歸 debt。估 ~25 行。
    // ⚠️ **但那 ~25 行寫出來也還不能用**(2026-08-18 G3 後測):`scenario.id` 與 `spec.id`
    //   **在整個 artifact 契約裡沒有產生來源**——grep 需要一個字串,而沒有東西提供那個字串。
    //   這與 L68 對 `artifacts.requires_adr` 的註記同類(「全 repo 只出現在本檔」),
    //   標記 pass 初版漏標。**先補輸入契約,再談實作。**
    //   實測後果:該次 gate 的 PASS/FAIL 完全懸在這個未定義欄位上。
    FOR scenario IN spec.scenarios:
      IF NOT has_test_for_scenario(scenario.id, artifacts.test_files):
        issues.append("場景 {scenario.id}（{scenario.name}）無對應測試")

    scenario_count = LEN(spec.scenarios)
    test_count = count_test_cases_for_spec(spec.id, artifacts.test_files)
    IF test_count < scenario_count:
      issues.append("測試數量（{test_count}）少於場景數量（{scenario_count}）")

  // 第二道 guard：上方 v3.2 區塊新增的 issues 原本無人檢查（死碼）。
  IF issues:
    RETURN GATE_FAIL(issues)

  // ⟦intent⟧ `G3_tdd_red` 的 2 個鍵(`must_fail_before_impl`、`compilation_error_allowed`)
  //   **未被讀取**——G3 從不 load thresholds。前者的名字出現在上面的訊息字串裡,
  //   那是文字引用不是取值。

  RETURN GATE_PASS(evidence=checks)
```

### G4: Implementation Gate（BUILD → HARDEN）

```
FUNCTION evaluate_G4(artifacts):
  checks = []
  issues = []

  // ⟦mechanical⟧ ×2:`make test` / `make lint`。條件成立——目標專案須提供該 target。
  test_result = EXECUTE("make test")
  IF NOT test_result.all_passed:
    issues.append("make test 失敗：{test_result.failures}")

  // Lint clean
  IF make_target_exists("lint"):
    lint_result = EXECUTE("make lint")
    IF lint_result.has_errors:
      issues.append("make lint 有 error")

  // ⟦debt⟧ ×2:`git_diff_files()`(一行 git,估 ~5 行)與 `matches_scope()`(glob 比對,估 ~20 行)
  //   皆未實作。兩者都屬 ADR-034 D4 那份 ~150 行清單,是其中最便宜的。
  //   ⚠️ 另注意 `git_diff_files()` 在「gate 執行前已 commit」時回空集合,檢查恆真空過。
  modified_files = git_diff_files()
  allowed_files = artifacts.task_manifest.scope.allow
  out_of_scope = [f FOR f IN modified_files IF NOT matches_scope(f, allowed_files)]
  IF out_of_scope:
    issues.append("修改了 scope 外的檔案：{out_of_scope}")

  // v3.3: TODO/FIXME/HACK 標記檢查
  // ⚠️ 空清單防護(2026-08-18,G4 實測):modified_files 為空時,
  // `grep -rn ... --include=...` 沒有 path operand 會**讀 stdin 而卡住**。
  // 字面執行者會 hang。必須先判空。
  IF NOT modified_files:
    checks.append("TODO/FIXME 標記掃描：not-applicable（無變更檔案可掃）")
  ELSE:
    // ⟦mechanical⟧ grep 本體可跑。
    // ⟦debt⟧ 但 `{ext}` **沒有定義**——沒有任何一處說它從哪來(專案語言?變更檔副檔名集合?)。
    //   逐字執行者會把它原樣帶進 shell,`--include="*.{ext}"` 匹配不到任何檔案而靜默回空。
    //   估 ~10 行(取 modified_files 的副檔名集合)。屬 D4 清單。同樣的 `{ext}` 在 G5 的
    //   全專案 grep 也出現一次。
    marker_result = EXECUTE("grep -rn \"TODO\\|FIXME\\|HACK\\|XXX\" --include=\"*.{ext}\" {modified_files}")
    IF marker_result.has_matches:
      FOR match IN marker_result.matches:
        LOG_TECH_DEBT("code-marker: {match.file}:{match.line} — {match.content}")
      // 訊息用「標記」涵蓋四種 pattern——grep 找的是 TODO|FIXME|HACK|XXX,
      // 原本的字串只寫 TODO/FIXME,命中 HACK/XXX 會被歸在沒提到它的標籤下。
      checks.append("⚠️ 發現 {marker_result.count} 個 TODO/FIXME/HACK/XXX 標記（已記錄為 tech-debt）")
    ELSE:
      checks.append("無新增 TODO/FIXME/HACK/XXX 標記 ✅")

  IF issues:
    RETURN GATE_FAIL(issues)

  // 三條都可能空轉：
  //   - make test / make lint：target 不存在時整段沒跑，卻宣告通過
  //   - scope：git_diff_files() 在「gate 執行前已 commit」時回空集合，檢查恆真空過
  test_state  = "passed" IF make_target_exists("test") \
                ELSE "not-applicable（無 test target）"
  lint_state  = "passed" IF make_target_exists("lint") \
                ELSE "not-applicable（無 lint target）"
  scope_state = "passed" IF (modified_files AND allowed_files) \
                ELSE "not-applicable（無變更清單或無 task_manifest.scope）"
  checks.append("make test：{test_state}")
  checks.append("make lint：{lint_state}")
  checks.append("修改範圍在 scope 內：{scope_state}")

  // ⟦intent⟧ `G4_implementation` 的 4 個鍵**全部未被讀取**:
  //   `min_unit_coverage_pct: 80` 與 `max_cognitive_complexity: 10` **完全沒有對應檢查**
  //   (2026-08-18 已從快速參考表移除那兩條不實承諾);
  //   `lint_errors_allowed: 0` 與 `all_done_when_tested: true` 的語意由上方條件式硬編。
  RETURN GATE_PASS(evidence=checks)
```

### G5: Verification Gate（HARDEN → DELIVER）

```
FUNCTION evaluate_G5(artifacts):
  checks = []
  issues = []

  // G5_integration 閾值(#101 ③)。quality-thresholds.yaml 的 G5_integration 四條
  // 原本從未被任何 pseudocode 讀到，只出現在文末的快速參考表裡。
  //
  // ⚠️ 更正(2026-08-18，由一次不知情執行者的 G4 實測抓到)：本註解初版寫
  // 「六道 gate 中原本只有 G5 不 load thresholds」——**那是錯的**。
  // 全檔只有 G2(L156)與本處會 load；**G1 / G3 / G4 / G6 同樣不 load**，
  // 而 quality-thresholds.yaml 為它們定義的區塊也就同樣從未被讀到。
  // 那不是本次修好的東西，是同一個 bug 尚未處理的其餘部分。
  //
  // **適用性由專案型別推導，不由執行者宣稱。** 這很重要：若 N/A 可以被宣稱，
  // 真正的 web 專案也能宣稱，量化要求就變裝飾品。依據是 quality-thresholds.yaml
  // 自己的註解——`min_e2e_scenarios` 那行原本就寫著「（全端專案）」。
  //
  // ⚠️ 本段**不改變任何 gate 的通過與否**：非 web 專案標 not-applicable（原本就沒跑），
  // web 專案的未達標走 YELLOW_FLAG 不擋（見下）。純粹讓證據停止沉默。
  thresholds  = load(".asp/config/quality-thresholds.yaml")
  ai_profile  = load(".ai_profile")                       // 專案根的型別宣告
  g5_int = thresholds.gates.G5_integration
  has_web_surface = (ai_profile.type IN ["web", "fullstack"]) OR artifacts.has_ui_changes
  IF has_web_surface:
    FOR name, limit IN g5_int:
      // ⟦debt⟧ `measure()` / `violates()` 未實作。`violates()` 是數值比較(估 ~10 行);
      //   `measure()` **不屬** D4 那份 ~150 行清單——量 e2e 場景數/頁面載入 ms/a11y critical
      //   需要 e2e + lighthouse + axe 工具鏈,那是獨立專案等級,不是一個下午。
      //   現況:回 null 即 skipped(A18 寧漏報不誤報),所以這四條實務上從未擋過任何東西。
      actual = measure(name, artifacts)                    // 量不到就是 null
      IF actual == null:
        checks.append("{name}：skipped（無法量測）")       // 不擋——A18 寧漏報不誤報
      ELSE IF violates(name, actual, limit):
        // **不擋 gate**——比照 ADR-033 D1 的先例：新檢查一律先 YELLOW_FLAG。
        // 這四條從未被任何 pseudocode 執行過，直接改成擋 gate 等於對所有 web 專案
        // 一次啟用四道未經驗證的阻斷條件。要升為 blocking 是**獨立決策，需 ADR**
        // （屆時應附「實際擋下的案例 / 假阻率」證據，比照 ADR-033 的做法）。
        YELLOW_FLAG("G5_integration 未達標：{name} = {actual}（門檻 {limit}）")
      ELSE:
        checks.append("{name}：passed（{actual} vs {limit}）")
  ELSE:
    checks.append("G5_integration：not-applicable（.ai_profile type={ai_profile.type}，無 web surface）")

  // QA 獨立驗證。**三態**：passed / not-applicable / skipped —— 見本節末「證據誠實原則」。
  // 有 SPEC 時逐條驗 Done When;無 SPEC 時(CLAUDE.md 明列的輕量改動路徑,
  // 「可跳 G1-G6 重 gate 但獨立審查不可省」)驗「變更是否符合其自述意圖 + 無 scope 外殘留」。
  // ⚠️ 不得因「無 SPEC」而 FAIL——那會打斷框架自己文件化的輕量路徑。
  // ⟦judgment⟧ `qa_agent.independent_verify()` 無機械判準——它就是「另一個人重看一遍」。
  //   判斷時看:每條 Done When 是否有可指認的證據(測試/輸出/截圖),而非只有實作者自述。
  qa_verdict = qa_agent.independent_verify(artifacts)
  IF qa_verdict.status == "QA_FAIL":
    issues.append("QA 獨立驗證失敗：{qa_verdict.evidence}")
  qa_state = "passed" IF artifacts.spec ELSE "not-applicable（無 SPEC，退化為意圖一致性檢查）"

  // Security 審查
  // ⟦judgment⟧ `sec_agent.review()` 同上,語意審查,不預期機械化。
  IF "sec" IN current_team:
    sec_verdict = sec_agent.review(artifacts)
    IF sec_verdict.has_findings:
      issues.append("安全審查發現：{sec_verdict.findings}")

  // v3.3: 新增 warning 檢查
  IF make_target_exists("lint"):
    lint_result = EXECUTE("make lint")
    IF lint_result.warning_count > 0:
      checks.append("⚠️ lint 產生 {lint_result.warning_count} 個 warning")
      IF artifacts.baseline AND lint_result.warning_count > artifacts.baseline.get("lint_warning_count", 0):
        new_warnings = lint_result.warning_count - artifacts.baseline.lint_warning_count
        issues.append("新增 {new_warnings} 個 lint warning")

  // 偷渡偵測。**三態**：無 checksum 或 repo 內無測試檔時是 not-applicable，不是 passed。
  // ⟦debt⟧ `test_checksums_changed()` 未實作。sha256 比對,估 ~15 行。屬 D4 清單。
  //   (`.asp/checks/test-fresh.sh` 做的是**測試痕跡新鮮度**,不是 checksum 比對,不能替代。)
  IF test_checksums_changed(artifacts.original_checksums, artifacts.current_checksums):
    issues.append("測試檔案 checksum 已變更（偷渡風險）")
  smuggle_state = "passed" IF (artifacts.original_checksums AND artifacts.current_checksums) \
                  ELSE "not-applicable（無 checksum 可比對）"

  // 全專案 grep（global_core.md 鐵則：Bug 修復後無豁免）
  // ⟦mechanical⟧ grep 本體可跑。
  // ⟦judgment⟧ 但 `artifacts.bug_pattern` **全 repo 只出現在本檔**,無來源——
  //   「這個 bug 的模式是什麼」本來就要人判(是函式名?錯誤的比較運算?缺的 null check?)。
  // ⟦debt⟧ `{ext}` 同 G4,未定義。
  IF artifacts.task_type == "BUGFIX":
    grep_result = EXECUTE("grep -r \"{artifacts.bug_pattern}\" --include=\"*.{ext}\" .")
    IF grep_result.has_matches:
      issues.append("全專案 grep 發現 {grep_result.count} 處相同模式")

  // v3.3: Side Effects 驗證
  IF spec.side_effects AND LEN(spec.side_effects) > 0:
    FOR effect IN spec.side_effects:
      // ⟦judgment⟧ `has_verification_for()` 判「這個副作用有沒有被某條 Done When 或某列矩陣涵蓋」
      //   ——語意對應,不預期機械化。判斷時看:副作用的受詞是否出現在某條驗收的可觀測結果裡。
      IF NOT has_verification_for(effect, spec.done_when, spec.test_matrix):
        issues.append("副作用 '{effect.description}' 缺少驗證（Done When 或測試矩陣無對應）")
    IF NOT issues:
      checks.append("Side Effects 全部有驗證 ✅")

  // v3.3: Rollback 測試驗證
  // ⟦judgment⟧ `task_involves_architecture_change` / `task_involves_schema_change` 無資料來源,
  //   由執行者判定;`spec.rollback_plan.tested` 本身是 SPEC 欄位(mechanical)。
  IF spec.rollback_plan:
    IF task_involves_architecture_change OR task_involves_schema_change:
      IF NOT spec.rollback_plan.tested:
        issues.append("🔴 架構/Schema 變更的 Rollback Plan 未經測試")
    ELSE:
      IF NOT spec.rollback_plan.tested:
        checks.append("⚠️ Rollback Plan 未經測試（建議但不強制）")

  // skill-reviewer：僅當變更觸及 SKILL.md（ADR-033；來源 skill-quality-research）
  // 設計取捨（尤其「安全紅旗不擋 gate」是刻意的）見 docs/adr/ADR-033-skill-quality-gate-in-g5.md
  IF artifacts.changed_files MATCHES "**/SKILL.md":
    // 傳入變更集 → lint 切換為 change-scoped 判定，severity 由它一次決定。
    // 本 profile 不重新編碼「什麼該擋」的政策——canonical 是 skill-reviewer 的
    // references/rubric-manual-dimensions.yaml（ADR-031：同一意義兩處編碼會 drift）。
    // ⟦mechanical⟧ **六道 gate 中唯一指向真實可執行檔的檢查**(ADR-033)。
    //   `--selftest` 可自我驗證;未安裝時走下方 YELLOW_FLAG 不擋。
    lint = EXECUTE("python3 ~/.claude/skills/skill-reviewer/scripts/lint_skill.py {repo_root} \
                    --changed-files {join(artifacts.changed_files, ',')} --json")

    IF lint.exit_code != 0 OR NOT is_valid_json(lint.stdout):
      YELLOW_FLAG("skill-reviewer 未安裝或執行失敗，跳過 skill 檢查（不擋 gate）")
    ELSE:
      // 擋 gate：hygiene error 級。H-005（逐檔合規）在 change-scoped 下，若本次變更改壞了
      // SKILL.md，lint 已標為 error，故此一條即涵蓋——不需在此重算交集。
      FOR h IN lint.hygiene WHERE h.severity == "error" AND h.pass == false:
        issues.append("Skill hygiene 未過：{h.id} {h.detail}")

      // 既有不合規檔（非本次變更）lint 標 warning，落此分支 → 提醒但不擋
      FOR h IN lint.hygiene WHERE h.severity == "warning" AND h.pass == false:
        YELLOW_FLAG("Skill hygiene 提醒：{h.id} {h.detail}")

      // 豁免項（severity == "info"、pass == null）兩個迴圈都不進，會靜默消失。
      // 記進 checks 而非 flag——豁免本就不該吵，但不該看不見（#101 第 ⑤ 項）。
      FOR h IN lint.hygiene WHERE h.severity == "info":
        checks.append("Skill hygiene {h.id}：not-applicable（豁免條款成立）")

      // 不擋：安全紅旗靜態偵測有假陽性，降 YELLOW_FLAG 交人複核
      // 排除 polarity==positive（防禦樣態，無 confidence 欄位）；medium 假陽性率最低，措辭加重
      FOR s IN lint.security WHERE s.polarity != "positive":
        IF s.confidence == "medium":
          YELLOW_FLAG("Skill 安全紅旗（較高信心，優先複核）：{s.id}/{s.flag}")
        ELSE:
          YELLOW_FLAG("Skill 安全紅旗待複核（靜態偵測，假陽性率高）：{s.id}/{s.flag}")

      // craft：由 Gate Checker 的 LLM 判讀層處理（見 CONTEXT.md「Gate Checker」）。
      // 注意：skill-reviewer 是 Gate Checker 不是 team role——**無 team 守衛**，
      // 不要比照 sec_agent 加 IF "..." IN current_team，那會讓它永遠不執行。
      // 執行者：載入 ~/.claude/skills/skill-reviewer/SKILL.md，照其步驟 3–5
      //（判 skill 形狀 → craft 四維度 → 安全複核）對 changed_skills 判讀。
      // artifacts.changed_skills = 本次變更觸及的 **SKILL.md 檔路徑**（與 changed_files 同粒度），
      // 不是 skill 目錄。質化審讀以那些檔案為準；同目錄下的 references/ 只在該 SKILL.md
      // 明確引用時才一併讀（#101 第 ⑥ 項）。
      // ⟦judgment⟧ `INVOKE_SKILL` **是 pseudocode 不是程式**(全 repo 零實作,ADR-033 已補登)。
    //   它的意思是:執行者請去載入 skill-reviewer 的 SKILL.md 並照步驟做。
    //   craft 判讀無機械判準——這正是 skill-quality-research 的核心結論
    //   (星數關聯打包面不是工藝,craft 只能靠 LLM 維度)。**不預期會機械化。**
      skill_verdict = INVOKE_SKILL("skill-reviewer", scope=artifacts.changed_skills)
      IF skill_verdict.craft == "needs-revision":
        YELLOW_FLAG("Skill craft 待修：{skill_verdict.gap_list}")   // 判斷不是事實，不擋 gate

      checks.append("Skill packaging 剖面：{lint.tier_benchmark_packaging}（僅 packaging 面，非總評）")

  IF issues:
    RETURN GATE_FAIL(issues)

  // 證據誠實原則(2026-08-18,issue #101):**「檢查通過」與「無物可檢」不得長得一樣。**
  // 實測:一個零測試的 repo 拿到跟「測試齊全且未被竄改」一模一樣的綠勾。
  // gate evidence 是人類用來判斷該不該信任這道 gate 的紀錄——兩者混同會讓紀錄說謊。
  // 本改動**不改變任何 gate 的通過與否**,只改標示。與 A18「寧漏報不誤報」的 fail-open
  // 家規一致:誠實標示,不是加擋。
  checks.append("QA 獨立驗證：{qa_state}")
  IF "sec" IN current_team:
    checks.append("安全審查 clear ✅")
  ELSE:
    checks.append("安全審查：skipped（\"sec\" 不在 current_team）")
  checks.append("偷渡偵測：{smuggle_state}")

  // ⟦mechanical⟧ G5 的 4 個 threshold 鍵是**唯一一組真的被讀取**的 gate 門檻
  //   (`min_e2e_scenarios` / `performance_budget_ms` / `a11y_violations_critical` /
  //    `security_scan_critical`)——連同 G2 的 `min_acceptance_criteria` 共 5 個生效鍵。
  //   ⚠️ 但「被讀取」不等於「會擋」:`measure()` 未實作 → 一律 null → skipped。

  // Reality Checker 否決權
  IF "reality" IN current_team:
    reality_verdict = reality_check(artifacts, "G5")
    IF reality_verdict.status == "NEEDS_WORK":
      RETURN GATE_FAIL(reality_verdict.evidence)
    checks.append("Reality Checker：passed")
  ELSE:
    // 證據誠實原則:原本整段靜默跳過,evidence 一字不提,
    // 讀者無法分辨「Reality 審過了」與「Reality 從沒進場」。
    // 本檔 L634 明寫「Reality Checker 參與 G2, G5, G6」,所以缺席本身是值得記錄的事實。
    checks.append("Reality Checker：skipped（\"reality\" 不在 current_team）")

  RETURN GATE_PASS(evidence=checks)
```

### G6: Delivery Gate（DELIVER → DONE）

```
FUNCTION evaluate_G6(artifacts):
  checks = []
  issues = []

  // asp-ship 7 步清單
  // ⟦judgment⟧ `pre_commit_checklist()` 是 system_dev.md 的 7 步清單,其中多步是語意判斷
  //   (「變更有沒有對應的 CHANGELOG 條目」「這是不是該拆成兩個 commit」)。不預期機械化。
  ship_result = pre_commit_checklist()  // from system_dev.md
  IF ship_result.has_blockers:
    issues.append("asp-ship 有 BLOCKER：{ship_result.blockers}")

  // 健康分數不退步
  // ✅ 已修(2026-08-18,#112)：#106 的 null-check 曾放在 dereference 之後 9 行，baseline 為
  //   null 時逐字執行者會先炸。**守衛現已與使用點同行(下方 `IF artifacts.baseline AND ...`)，
  //   短路求值下不會炸。此處無待修問題。**
  //   ⚠️ 措辭教訓(G6 後測抓到):原註解用現在式描述**已修好的** bug，逐字執行者會去找一個
  //   找不到的東西並回報為缺陷。修正紀錄一律寫完成式。
  // ⟦mechanical⟧ `make audit-quick` 是 ASP 自己提供的 target,可跑。
  // ⟦debt⟧ 但 `load_audit_baseline()`(在下方 execute_pipeline 中)**全 repo 只出現在本檔、
  //   零實作**——沒有它 `artifacts.baseline` 恆為 null,整段降級為 not-applicable。
  //   估 ~15 行(讀上一次 audit 輸出取 blockers 數)。屬 D4 清單。
  current_audit = EXECUTE("make audit-quick")
  IF artifacts.baseline AND current_audit.blockers > artifacts.baseline.blockers:
    issues.append("健康審計引入新 blocker（before: {artifacts.baseline.blockers}, after: {current_audit.blockers}）")

  IF issues:
    RETURN GATE_FAIL(issues)

  // 兩條都可能空轉:pre_commit_checklist() 不可用、或無 artifacts.baseline 可比對時，
  // 條件式不成立 → 無 issue → 仍宣告通過。
  ship_state   = "passed" IF ship_result ELSE "not-applicable（pre_commit_checklist 未回傳結果）"
  health_state = "passed" IF artifacts.baseline ELSE "not-applicable（無 baseline 可比對）"
  checks.append("asp-ship 7 步：{ship_state}")
  checks.append("健康分數未退步：{health_state}")

  // v3.3: Traceability 檔案存在驗證
  // ⟦mechanical⟧ 檔案存在性,逐條可判。
  IF spec.traceability:
    FOR impl_file IN spec.traceability.impl_files:
      IF NOT exists(impl_file):
        issues.append("Traceability 引用的實作檔案不存在：{impl_file}")
    FOR test_file IN spec.traceability.test_files:
      IF NOT exists(test_file):
        issues.append("Traceability 引用的測試檔案不存在：{test_file}")
    IF NOT issues:
      checks.append("Traceability 檔案全部存在 ✅")

  // ✅ 已修(2026-08-18,#112)：Traceability 的 issues.append 曾位於**唯一**那道
  //   `IF issues: RETURN GATE_FAIL` 之後、結尾又是無條件 GATE_PASS，於是那些 issue
  //   既不擋 gate 也不進 evidence，徹底蒸發(與 G3 同型)。**下面這道就是補上的第二道 guard。**
  //   ⚠️ 但**尚未修**的同族問題(G6 後測):`spec.traceability` 存在而兩個 list 解析為空時,
  //   兩個 FOR 跑空集合 → `IF NOT issues` 成立 → append「Traceability 檔案全部存在 ✅」,
  //   **零個檔案被驗證卻蓋一個 ✅**。三態化需另案處理(會動到判定字串,不在標記 pass 範圍)。
  IF issues:
    RETURN GATE_FAIL(issues)

  // ⟦intent⟧ `G6_delivery` 的 4 個鍵**全部未被讀取**:`doc_freshness_days: 7` 與
  //   `tech_debt_p0_allowed: 0` 與 `postmortem_required_if_p0: true` **完全沒有對應檢查**;
  //   `health_score_regression: false` 的語意由上方 blockers 比較硬編。
  //   快速參考表的 G6 列(「文件新鮮度 ≤ 7 天;P0 tech debt = 0」)因此是**意圖不是實作**。

  // Reality Checker 否決權
  // ⟦judgment⟧ `reality_check()` 同 G2/G5。
  IF "reality" IN current_team:
    reality_verdict = reality_check(artifacts, "G6")
    IF reality_verdict.status == "NEEDS_WORK":
      RETURN GATE_FAIL(reality_verdict.evidence)
    checks.append("Reality Checker：passed")
  ELSE:
    // 證據誠實原則:原本整段靜默跳過,evidence 一字不提,
    // 讀者無法分辨「Reality 審過了」與「Reality 從沒進場」。
    // 本檔 L634 明寫「Reality Checker 參與 G2, G5, G6」,所以缺席本身是值得記錄的事實。
    checks.append("Reality Checker：skipped（\"reality\" 不在 current_team）")

  RETURN GATE_PASS(evidence=checks)
```

---

## 品質門評估邏輯

```
FUNCTION evaluate_gate(gate_id, artifacts, evaluating_agents):

  // ⟦judgment⟧ `agent.evaluate()` 是各 agent 的裁定。
  // ⟦debt⟧ `create_handoff()` / `collect_evidence()` 的實際定義在 task_orchestrator.md,
  //   本檔只引用(ADR-015 保護的外部錨點,不得改名)。
  verdicts = {}
  FOR agent IN evaluating_agents:
    verdicts[agent.role] = agent.evaluate(gate_id, artifacts)

  // Reality Checker 有否決權（參與 G2, G5, G6）
  IF "reality" IN evaluating_agents:
    IF verdicts["reality"].status == "NEEDS_WORK":
      handoff = create_handoff(PHASE_GATE,
        gate_id = gate_id,
        final_verdict = "FAIL",
        blocking_agent = "reality",
        evidence = verdicts["reality"].evidence)
      RETURN GATE_FAIL(handoff)

  // 其他 agent 全部 PASS 才通過
  failures = [agent FOR agent, v IN verdicts IF v.status != "PASS"]
  IF failures:
    handoff = create_handoff(PHASE_GATE,
      gate_id = gate_id,
      final_verdict = "FAIL",
      blocking_agents = failures,
      evidence = collect_evidence(verdicts))
    RETURN GATE_FAIL(handoff)

  handoff = create_handoff(PHASE_GATE,
    gate_id = gate_id,
    final_verdict = "PASS",
    evidence = collect_evidence(verdicts))
  RETURN GATE_PASS(handoff)
```

---

## 管線執行包裝

```
FUNCTION execute_pipeline(task, team, phases):
  // ⟦debt⟧ `load_audit_baseline()` 零實作 —— 見 G6 的 ⟦debt⟧ 註。
  artifacts = { spec: task.spec, baseline: load_audit_baseline() }

  FOR phase IN phases:
    // 執行階段
    MATCH phase:
      SPECIFY:    artifacts.update(run_specify(task, team))
      PLAN:       artifacts.update(run_plan(task, team))
      FOUNDATION: artifacts.update(run_foundation(task, team))
      BUILD:      artifacts.update(run_build(task, team))
      HARDEN:     artifacts.update(run_harden(task, team))
      DELIVER:    artifacts.update(run_deliver(task, team))

    // 評估品質門（除最後一個階段外）
    // ⟦debt⟧ `get_gate_for_phase()` / `get_gate_agents()` 皆零實作、全 repo 只出現在此
    //   (標記 pass 初版漏標,G3 後測抓到)。前者是階段→gate 的固定對照(見 L24 映射表,估 ~10 行);
    //   後者需 `team_compositions.yaml`,而**該檔不存在**——先補檔再談實作。
    gate = get_gate_for_phase(phase)
    IF gate:
      gate_agents = get_gate_agents(gate, team)
      result = evaluate_gate(gate, artifacts, gate_agents)

      IF result == GATE_FAIL:
        LOG("品質門 {gate.id} 未通過：{result.evidence}")
        // 品質門失敗不直接升級——回到當前階段的 agent 修正
        // 最多重試 2 次，超過走升級協議
        IF gate.retry_count >= 2:
          escalate(severity="P2", reason="品質門 {gate.id} 重試 2 次仍未通過", task_id=task.id)
        ELSE:
          gate.retry_count += 1
          RETRY current phase

  RETURN artifacts
```

---

## 量化閾值（v3.7）

>   **⟦mechanical⟧ 檢查**必須對照具體數字，不得使用「基本達標」等主觀描述。
>   **⟦judgment⟧ 檢查**不填「實際值」，填**判斷 + 依據**，狀態欄標 `judgment`。
>   **⟦debt⟧ / ⟦intent⟧ 檢查照列但標明未生效**，不得以空白或 `N/A` 混過。
>
> (ADR-034 D5 收窄。原文是「Gate 評分必須對照具體數字」——保留它禁止空話的原意
>  [裁量也要寫依據]，只否定「一切皆可量化」的隱含前提。實測:同一條規則兩個執行者兩種應對,
>  G2 的產出 13 列混著可數的與它自己判的,G4 的則填了四個 `⏭ 不適用`。)

完整閾值定義在 `.asp/config/quality-thresholds.yaml`。Gate 評分時必須輸出以下格式：

```
GATE G[N] 量化摘要
指標              | 閾值             | 實際值    | 狀態
------------------|------------------|-----------|------
SPEC 欄位數       | = 7              | 7         | ✅ PASS
Done When 數量    | ≥ 3              | 2         | ❌ FAIL
Gherkin 場景      | ≥ 2              | 3         | ✅ PASS
Draft ADR 數      | = 0              | 0         | ✅ PASS（FIRM 不計入）
[UNVERIFIED] 標注 | = 0              | 1         | ❌ BLOCKER
Done When 可二元測試| 全部             | 4/4 判斷  | judgment（依據：每條均有可觀測受詞與成功值）
count_assertions   | > 0             | 未實作    | debt（⟦debt⟧，本次未生效）
覆蓋率             | ≥ 80%            | 未接線    | intent（config 有值，evaluate_G4 不讀）
------------------|------------------|-----------|------
本 gate 分布       | mechanical N / judgment N / debt N / intent N
```

>   **計數單位:標記項,不是檢查點。** 一個檢查點可能帶多個標記
>   (例:G4 的 TODO 掃描同時是 ⟦mechanical⟧ 的 grep 與 ⟦debt⟧ 的 `{ext}`),`×2` 的標記算 2。
>   範圍:**這道 gate 的全部標記項**,不是「本次實際評估到的」——否則同一道 gate 每次分母都不同。
>
> **最後一列是必填的。** 一道 gate 的四層分布**就是它有多硬的量測**——
> 全部 `mechanical` 表示這道門真的擋得住;`intent` 佔多數表示它主要是意圖聲明。
> 目前這個比例完全看不到,而它是讀者判斷該不該信任這道 gate 的第一個數字。

**核心閾值快速參考（詳見 quality-thresholds.yaml）：**

> ⚠️ **本表列的是「意圖」,不等於「pseudocode 實際會檢查的東西」**(2026-08-18 實測)。
> `quality-thresholds.yaml` 共 **23** 個 threshold 鍵(G1:2 G2:7 G3:2 G4:4 G5:4 G6:4),
> 而 `evaluate_G*` 實際解參考的只有 `min_acceptance_criteria` 與 `G5_integration` 的 4 個
> = **5 個** —— **其餘 18 個從未被讀取**。
> (2026-08-18 更正:初版寫「19 鍵、約 16 個未讀」,那是計數腳本的錯——
>  它把 `gates.G2_specification` 出現一次就當整段被讀。手動列印 config 後才得到正確數字。)
> 下表已把 G2 / G4 兩列改成與實作一致(原本承諾了不存在的檢查);
> **其餘各列尚未逐條核對**,引用前請對照對應的 `### G{n}` pseudocode。

| Gate | 關鍵閾值 |
|------|---------|
| G1 | Draft ADR = 0；FIRM ADR = 🟡（允許但記錄）；依賴圖無環 |
| G2 | SPEC 7 欄位；≥3 Done When；Gherkin 場景**存在**（`min_gherkin_scenarios: 2` 未被讀取，實作只檢查有無）；測試矩陣正/負向各 ≥1；[UNVERIFIED] = 0 |
| G3 | 所有測試實作前 FAIL；無編譯錯誤 |
| G4 | `make test` 通過；`make lint` 無 error（**有 target 時**）；變更在 scope 內；TODO/FIXME/HACK/XXX 記為 tech-debt<br>⚠️ **覆蓋率與認知複雜度雖在 config 有值，`evaluate_G4` 從未檢查** —— 原本列在此處是不實承諾，已移除 |
| G5 | **（僅全端／web 專案適用，其餘標 not-applicable）** ≥1 E2E 場景；頁面載入 ≤ 3000ms；a11y critical = 0 |
| G6 | 文件新鮮度 ≤ 7 天；P0 tech debt = 0；健康分數不退步 |

---

## 與其他 Profile 的關係

```
pipeline.md
  ├── 依賴 task_orchestrator.md（execute_*() 是管線階段的實際邏輯）
  ├── 依賴 system_dev.md（pre_commit_checklist 用於 G6）
  ├── 可選 reality_checker.md（Reality Checker 參與 G2, G5, G6）
  ├── 可選 task_orchestrator.md Part G（multi-agent 時各階段由不同 agent 負責；v4.3 起 multi_agent.md 已合入）
  ├── 可選 /asp-dev-qa-loop skill（BUILD + HARDEN 階段的 Dev↔QA 迴路；v4.x 取代 dev_qa_loop.md profile）
  └── 升級路由：global_core「升級路徑」節（ADR-014 D4；品質門重試耗盡時走 P2）
```
