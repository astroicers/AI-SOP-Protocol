# ASP v4.0 Disposition Matrix — 元件分類與紅隊質疑

> 機器可讀版本：`.asp-disposition-matrix.yaml`
> 目的：決定 v3.7 每個元件在 v4.0 的去向，並以紅隊視角質疑每個決策

---

## 分類摘要

| Disposition | 數量 | 說明 |
|-------------|------|------|
| KEEP | 4 | 留在 CLAUDE.md，不動 |
| COMPRESS | 6 | 留 CLAUDE.md，大幅縮短 |
| REFERENCE | 4 | CLAUDE.md 改為單行指向 |
| ELIMINATE | 2 | 完全刪除 |
| CONVERT_TO_SKILL | 8 | 轉為 Claude Code skill |
| KEEP_IN_PROFILE | 9 | 留在 .asp/profiles/ |
| **合計** | **33** | |

---

## CLAUDE.md 元件分類

| Section | 原行數 | Disposition | 目標 |
|---------|--------|-------------|------|
| 標頭 + 讀取順序 | 5 | KEEP | 保留 3 行 |
| 啟動程序 (步驟 1-6) | 11 | COMPRESS | ≤6 行 |
| validate_profile_config() pseudocode | 32 | REFERENCE | 指向 global_core.md |
| .ai_profile schema | 14 | COMPRESS | ≤8 行 (5 關鍵欄位) |
| Profile 對應表 | 29 | COMPRESS | ≤10 行 (type/mode 主映射) |
| Maturity Levels 詳細描述 | 32 | COMPRESS | ≤8 行 (L0-L5 各一行) |
| 等級管理指令 | 16 | REFERENCE | 指向 make asp-level-* |
| Legacy 等級推斷規則 | 17 | ELIMINATE | 完全刪除 |
| 4 條鐵則 | 13 | KEEP | 精簡到每條 2 行 |
| 強制力架構 | 13 | COMPRESS | 4 行 table |
| 強制 Skill 調用表 | 24 | COMPRESS | ≤8 行 (G1/G4/G6) |
| Bypass 警告格式 | 11 | REFERENCE | 指向 asp-ship Step 10 |
| 預設行為表 | 23 | REFERENCE | 移到 global_core.md |
| 標準工作流 diagram | 7 | KEEP | 保留 diagram + 1 行說明 |
| Makefile 速查全表 | 65 | ELIMINATE | `make help` 一行 |
| 技術執行層說明 | 17 | COMPRESS | ≤4 行 |

---

## Profile 元件分類

| Profile / Section | Disposition | 去向 |
|------------------|-------------|------|
| global_core — 溝通規範 | KEEP_IN_PROFILE | 不動 |
| global_core — 工作目錄紀律 | KEEP_IN_PROFILE | 不動 |
| global_core — Fact Verification Gate | CONVERT_TO_SKILL | asp-fact-verify |
| global_core — Assumption Checkpoint | CONVERT_TO_SKILL | asp-assumption-checkpoint |
| global_core — Bug Severity Classify | CONVERT_TO_SKILL | asp-bug-classify |
| global_core — Change Cascade L1-L4 | CONVERT_TO_SKILL | asp-change-cascade |
| task_orchestrator — on_task_received | KEEP_IN_PROFILE | 不動 |
| task_orchestrator — project_health_audit | KEEP_IN_PROFILE | 不動 |
| task_orchestrator — Handoff Protocol | CONVERT_TO_SKILL | asp-handoff |
| task_orchestrator — Team Recommendation | CONVERT_TO_SKILL | asp-team-pick |
| escalation.md (整體) | CONVERT_TO_SKILL | asp-escalate |
| dev_qa_loop.md (整體) | CONVERT_TO_SKILL | asp-dev-qa-loop |
| pipeline.md | KEEP_IN_PROFILE | 不動 |
| system_dev.md | KEEP_IN_PROFILE | 不動 |
| autonomous_dev.md | KEEP_IN_PROFILE | 不動 |
| agent_memory.md | KEEP_IN_PROFILE | 不動 (v4.1 可轉 MCP) |
| autopilot.md | KEEP_IN_PROFILE | 不動 |

---

## 紅隊質疑（15 條）

以下質疑遵循格式：**挑戰 → 回應 → 最終決策 ACCEPT/MODIFY**

---

### RT-01：Makefile 表 ELIMINATE 後，新使用者還找得到指令嗎？

**挑戰：** 65 行的 Makefile 速查表對第一次使用 ASP 的人是快速入門的關鍵材料。刪掉後他們需要先知道 `make help` 才能找到任何指令，但他們怎麼知道有 `make help`？

**回應：** 在 CLAUDE.md 的快速指令 section 保留 6 個最常用的指令（adr-new, spec-new, test, audit-health, asp-refresh, asp-level-check），並加一行「完整指令：`make help`」。這給新使用者足夠的入口，同時去除 65 行的 token 負擔。

**決策：** MODIFY — ELIMINATE 改為「留 6 個最常用 + make help 一行」，不是完全刪除

---

### RT-02：validate_profile_config() 從 CLAUDE.md 移除後，AI 還會驗證 profile 依賴嗎？

**挑戰：** pseudocode 30 行是 AI 在 session 啟動時的「程式化行動指引」。移除後 AI 的行為可能退化為不驗證 profile 依賴。

**回應：** session-audit.sh 的 A1 check 在 SessionStart hook 層已執行 profile 驗證，並把結果注入 .asp-session-briefing.json。AI 讀取 briefing 而非執行 pseudocode。如果 briefing 顯示依賴警告，AI 應處理。REFERENCE 是正確的：AI 不需要在 runtime 跑 pseudocode。

**決策：** ACCEPT — REFERENCE 維持

---

### RT-03：Fact Verification Gate 轉成 skill，但 implicit 觸發怎麼辦？

**挑戰：** 目前 global_core.md 把 Fact Verification Gate 定義為「任何任務涉及外部事實時必須先執行」——這是 implicit rule，不是有觸發詞的 capability。轉成 skill 後，如果使用者不主動呼叫，整個 gate 就被繞過。

**回應：** 這是真正的張力。解法：
1. global_core.md 保留一行 implicit 規則：「涉及第三方 API/版本/法規 → 在 G1 前執行 asp-fact-verify」
2. asp-gate G1 的評估步驟明確要求 fact-verify 已執行（檢查 .asp-fact-check.md 是否存在）
3. skill 本身包含完整執行邏輯

這樣同時保留 implicit 觸發（通過 G1 強制）和 capability 靈活性（可單獨呼叫）。

**決策：** MODIFY — global_core.md 保留一行 fact-verify 觸發規則 + G1 gate 要求；但完整邏輯轉 skill

---

### RT-04：Escalation 整體轉 skill，autonomous_dev 的 P0 implicit 觸發斷鏈？

**挑戰：** autonomous_dev.md 的 `must_pause` 條件包含「auto_fix 3× 失敗 → 停止並通知人類」，這是 P0 escalation 的一種。如果 escalation.md 整體轉 skill，autonomous_dev 的 P0 路徑就沒有邏輯支撐。

**回應：** autonomous_dev.md 的 must_pause 和 escalation.md 的 `escalate(P0)` 是不同的事情：
- must_pause：AI 自主停下等待確認（不需要 escalation skill）
- escalate(P0)：AI 在需要「通知機制」時調用（需要 escalation skill）

解法：autonomous_dev.md 保留其 must_pause 邏輯（這是 implicit constraint），escalation.md 只轉移「P0-P3 路由決策」和「ESCALATION handoff 產生」邏輯到 asp-escalate skill。

**決策：** MODIFY — escalation.md 轉 skill，但 autonomous_dev.md 的 must_pause 邏輯不移動

---

### RT-05：CLAUDE.md 壓縮到 100 行後，第一次使用 ASP 的工程師 5 分鐘看完能啟動嗎？

**挑戰：** v3.7 的 CLAUDE.md 雖然長（309 行），但資訊很密集。100 行的版本如果只剩指向其他文件的連結，新使用者可能需要看 10 個文件才能開始工作。

**回應：** v4.0 CLAUDE.md 的 100 行必須讓新使用者能回答 3 個問題：
1. 「我應該設定什麼 .ai_profile？」→ 型別/等級表 + 範例
2. 「哪些事情我不能做？」→ 4 條鐵則
3. 「怎麼開始工作？」→ 標準工作流 diagram + make help

這 3 個問題在 100 行內可以完整回答。其餘的探索性需求（全部指令、完整 profile 說明）交給 make help 和 .asp/profiles/。

**決策：** ACCEPT — 100 行目標可行，需確保上述 3 個問題能在 CLAUDE.md 內被回答

---

### RT-06：Disposition 分類為「KEEP_IN_PROFILE」的 implicit rule，在不載入 profile 的場景下會失效嗎？

**挑戰：** 若使用者設定了一個非常精簡的 .ai_profile（例如只有 type: system），很多 optional profile 就不會被載入，裡面的 implicit rule（溝通規範、工作目錄紀律）就消失了。

**回應：** global_core 是所有 type 的強制載入（CLAUDE.md 的啟動程序明確列出 `type: system → global_core + system_dev`）。溝通規範和工作目錄紀律在 global_core，無論什麼 type 都會載入。其他 profile 的 implicit rule 只在該 profile 啟用時才需要，這是正確的設計。

**決策：** ACCEPT — KEEP_IN_PROFILE 是正確的，因為 global_core 是保底

---

### RT-07：8 個新 skill 增加 SKILL.md router 的觸發詞密度，會增加 false positive 嗎？

**挑戰：** SKILL.md 從 13 個 skill 增加到 21 個，觸發詞數量翻倍。當使用者說「開始前先想一下假設」，AI 可能同時觸發 asp-assumption-checkpoint 和 asp-plan（兩個都有類似觸發詞）。

**回應：** skill router 的觸發詞設計應保持互斥性。解法：
- asp-assumption-checkpoint 觸發詞：「假設確認、開始前確認、有沒有假設、assumption」
- asp-plan 觸發詞：「計劃新功能、建立 ADR、寫 SPEC、新功能」

如果確實模糊，在 SKILL.md 加一個「優先級規則」：plan > assumption-checkpoint（planning 包含 assumption）。

**決策：** ACCEPT + 在 SKILL.md 加觸發詞優先級說明

---

### RT-08：agent_memory.md 暫時留 profile，但它其實是 Stateful + Lazy 的完美 MCP 候選，這個決策是否太保守？

**挑戰：** 根據 disposition matrix 的判讀規則，Stateful + Lazy → 應該是 CONVERT_TO_MCP。agent_memory.md 明顯是 stateful（記憶跨 session）且 lazy（被呼叫才需要），但我們選擇了 KEEP_IN_PROFILE。

**回應：** 這個決策確實保守，但是刻意的：v4.0 的 MCP server 是 ADR + SPEC（設計文件），實作留到 v4.1。如果現在把 agent_memory.md 設計為 CONVERT_TO_MCP，但 MCP server 還不存在，使用者就會有一個功能完全消失的空窗期。暫時 KEEP_IN_PROFILE 是過渡決策，不是最終決策。

**決策：** MODIFY — 在 YAML 中標記 `target_future: v4.1+ 可考慮轉為 MCP`，讓意圖明確

---

### RT-09：fact_verification_gate 的 5 元素驗證（人事時地物）embedded 在 skill，但 skill 沒有 WebSearch/WebFetch 的強制能力，只能「建議」使用者去查，這算真正的驗證嗎？

**挑戰：** skill 只是 Markdown 指令，它說「請 WebSearch 這個 API 版本」，但 AI 可以選擇不執行。原本在 profile 裡作為 implicit rule 的強制力，轉成 skill 後變成了建議。

**回應：** 這是真正的降級。緩解方案：asp-gate G1 在評估時檢查 `.asp-fact-check.md` 是否存在且非空。如果不存在，G1 自動 FAIL（有明確的 gate 強制力）。asp-fact-verify skill 的存在讓「如何執行 fact check」有標準流程，但強制力由 G1 gate 提供。

**決策：** ACCEPT（降級是可接受的）— 前提是 G1 gate 補上「.asp-fact-check.md 存在」的驗證步驟

---

### RT-10：Makefile 速查表 ELIMINATE，但 telemetry 系統引入了 3 個新 `make` target（asp-telemetry-*）——這些新指令怎麼傳達給使用者？

**挑戰：** v4.0 新增 3 個 telemetry make target，但 CLAUDE.md 的 Makefile 表已經刪除。使用者怎麼知道這些新指令的存在？

**回應：** 所有 make target 都應該在 `make help` 輸出中列出（這是 Makefile 的慣例）。`.asp/Makefile.inc` 的新 target 只要加了 `## comment`，就會自動出現在 `make help` 輸出。CLAUDE.md 不需要列出每個 target。

**決策：** ACCEPT — make help 是正確的單一入口

---

### RT-11：Assumption Checkpoint 轉成 skill 後，L0 使用者（沒有 profile）能用嗎？

**挑戰：** L0 Spike mode 只載入 global_core 和 spike_mode，不載入包含 Assumption Checkpoint Protocol 的完整 global_core 邏輯。但如果 Assumption Checkpoint 轉成 skill，L0 使用者反而可以獨立呼叫它。

**回應：** 這實際上是一個正向的 side effect。Skill 的設計原則是「無需 ASP profile 也能獨立運作」，所以 L0 使用者確實可以在需要時呼叫 asp-assumption-checkpoint。這比在 global_core.md 埋著（L0 不完整載入）更好。

**決策：** ACCEPT — skill 化後 L0 反而受益，這是正確的設計

---

### RT-12：Change Cascade L1-L4 轉成 skill，但「需求變更回溯」是否真的只在使用者明確說「需求變更」時才需要？還是每次 SPEC 修改時都應該 implicit 觸發？

**挑戰：** 如果開發者悄悄修改了 SPEC 而沒有說「需求變更」，change cascade 就永遠不會被觸發，造成 ADR 和 SPEC 之間的不一致。

**回應：** asp-ship (pre-commit) 的 Step 5 檢查 SPEC 變更是否有對應的 ADR 引用更新。這提供了一個 implicit 的 catch-all 機制，不依賴使用者說「需求變更」。Change Cascade skill 提供的是「主動變更管理」工作流，而不是 commit 時的被動檢查。兩者互補。

**決策：** ACCEPT — change cascade 適合 skill，asp-ship 提供 implicit fallback

---

### RT-13：team_recommendation 轉成 skill，但 task_orchestrator 的 on_task_received 在路由任務時仍然需要推薦 team——兩者解耦會造成 task_orchestrator 邏輯殘缺嗎？

**挑戰：** task_orchestrator.md 的 on_task_received 包含「自動推薦 team 並等待確認」，這個自動推薦邏輯如果移到 asp-team-pick skill，task_orchestrator 就沒有這個能力了。

**回應：** task_orchestrator.md 的 on_task_received 保留一行：「team 推薦：呼叫 asp-team-pick」，讓 skill 作為 task_orchestrator 的外部能力被呼叫。這是良好的模塊化，不是殘缺。相當於 task_orchestrator 知道「有這個能力」，但邏輯詳情在 skill。

**決策：** ACCEPT — task_orchestrator 引用 asp-team-pick，邏輯不殘缺

---

### RT-14：3 條「修正後的判讀」——至少找出 3 個之前判讀錯的地方

**（說明：按照 v4.0 prompt pack 的要求，必須找出 3 個需要修正的判讀）**

**修正 1：Makefile 速查表 ELIMINATE → MODIFY**
- 原判讀：完全刪除（只留 `make help`）
- 修正後：留 6 個最常用指令 + `make help` 一行
- 理由：完全 ELIMINATE 對新使用者太粗暴，6 個指令的 token 成本（~8 行）換來的 UX 改善值得

**修正 2：fact_verification_gate CONVERT_TO_SKILL（純 skill）→ CONVERT_TO_SKILL + 保留 G1 implicit check**
- 原判讀：整個邏輯轉 skill，profile 只留一行觸發規則
- 修正後：G1 gate 補上 `.asp-fact-check.md exists` 的驗證步驟，確保 fact-verify 不能被跳過
- 理由：skill 是正確的，但 gate 層必須提供強制力，否則 implicit 觸發退化為建議

**修正 3：escalation.md CONVERT_TO_SKILL（整體）→ CONVERT_TO_SKILL（部分）+ autonomous_dev 保留 must_pause**
- 原判讀：escalation.md 整體轉成 asp-escalate skill
- 修正後：只轉移「P0-P3 路由決策和 ESCALATION handoff 產生」；autonomous_dev.md 的 must_pause 邏輯不移動
- 理由：must_pause 是 autonomous mode 的 implicit constraint，不是顯式的 escalation capability

---

### RT-15：security — 如果攻擊者知道 fact_verification_gate 轉成了 skill（不是 rule），會怎麼利用？

**挑戰：** 攻擊者知道 fact check 只在「明確觸發 asp-fact-verify」時執行後，可以通過 PR 注入一個包含錯誤 API 資訊的 SPEC，讓 AI 在沒有 fact check 的情況下實作一個錯誤的接口。

**回應：** 這是真實的攻擊向量。緩解：
1. G1 gate 強制要求 `.asp-fact-check.md` 存在（見 RT-09 修正）
2. G1 gate 也應該檢查 SPEC 中的外部 API reference 是否有對應的 fact check 記錄
3. asp-ship Step 5（SPEC traceability）可以加一個 fact-check 的交叉驗證

這是 CYBERSEC 2026 演講可以直接 demo 的攻擊鏈：PR 注入假 API 版本 → AI 實作 → fact check 被跳過 → 整合時 runtime error。

**決策：** ACCEPT（已在威脅模型中納入）+ G1 gate 需要補強

---

## 修正後的 Disposition 清單（受紅隊影響）

| ID | 原 Disposition | 修正後 |
|----|---------------|--------|
| claude_md.makefile_full_table | ELIMINATE | MODIFY：留 6 個最常用 + `make help` |
| profile.global_core.fact_verification_gate | CONVERT_TO_SKILL | CONVERT_TO_SKILL + G1 gate 補強 `.asp-fact-check.md exists` 檢查 |
| profile.escalation | CONVERT_TO_SKILL (整體) | CONVERT_TO_SKILL (部分) — autonomous_dev.md 的 must_pause 留原位 |
