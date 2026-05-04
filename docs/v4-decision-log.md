# ASP v4.0 決策日誌

> 記錄 v4.0 重構過程中的主要決策、被拒絕的方案、和最終選擇的理由。

---

## D1: 為什麼壓縮 CLAUDE.md（從 309 行到 92 行）

**問題：** CLAUDE.md 是 ASP 的「憲法」，每個 session 都會完整載入。309 行 (~4500 tokens) 消耗了 L1 session 的大量 context 窗口，而其中大量內容是「速查表」性質（Makefile 全表 65 行、validate_profile_config() pseudocode 32 行），session 中幾乎不需要即時存取。

**被拒絕的方案：**
- 維持 309 行不動：被拒絕。Token 浪費是可量測的問題，baseline 已記錄在 `.asp-baseline-v3.7.json`。
- 壓縮到 50 行以內：被拒絕。太激進，鐵則、profile 映射表、工作流 diagram 必須保留。

**最終決策：** 壓縮到 92 行（≤100 行目標），遵循 disposition matrix 的 COMPRESS/REFERENCE/ELIMINATE 分類。

**理由：** Makefile 速查全表（65 行）改為 `make help` 一行；pseudocode（32 行）改為一行指向 global_core.md；legacy 等級推斷規則（17 行）完全移除（session-audit.sh 已有 fallback）。鐵則、工作流 diagram、profile 映射表全部保留。

---

## D2: 為什麼從 profile 抽取 8 個 skill

**問題：** 部分 profile 邏輯屬於「capability」（使用者主動要求時執行），不應作為 implicit 規則在每個 session 全量載入。例如 handoff protocol 只在任務交接時才需要；dev-qa-loop 只在使用者明確啟動品質迴路時才執行。

**被拒絕的方案：**
- 不抽取，保持現有 profile 結構：被拒絕。profile 過胖（task_orchestrator.md 1379 行）嚴重影響 L4/L5 的 context 效率。
- 把整個 profile 都轉成 skill：被拒絕。pipeline.md 的 G1-G6 是 cross-cutting rule，必須 implicit 套用，不能只在觸發時才執行。

**最終決策：** 只把「有明確觸發詞 + 一次性執行 + 無跨 session 狀態需求」的 capability 轉成 skill。8 個邏輯符合條件：handoff, team-pick, escalate, dev-qa-loop, fact-verify, assumption-checkpoint, bug-classify, change-cascade。

**理由：** Disposition matrix 的 CONVERT_TO_SKILL 標準：明確觸發詞 + capability（非 constraint）+ 無 implicit 需求。

---

## D3: 為什麼 Telemetry 用 JSONL（非 SQLite）

**問題：** 需要一種可以持久記錄 ASP 事件的方式，以便做 evidence-based 的規則調整。

**被拒絕的方案：**
- SQLite：需要 schema migration；binary format 不 grep-able；concurrent write 複雜。
- JSON array file：append 需要讀全檔重寫；大文件慢。
- Prometheus/OpenTelemetry：對個人/小團隊工具過重。

**最終決策：** JSONL append-only（每行一個 JSON event）。

**理由：** 無額外依賴（純 stdlib）；grep-able；append-only 天然支援未來完整性 audit；prune.py 按月歸檔避免無限成長。

---

## D4: 為什麼加 L0 Spike 等級

**問題：** ASP 從 L1 開始，沒有「探索性原型」等級。PoC 驗證、CYBERSEC 演講 demo、新技術可行性評估等場景，使用者被迫在 L1 的治理負擔（ADR、SPEC、TDD、pipeline gates）下做探索性工作，摩擦感高。

**被拒絕的方案：**
- 讓使用者手動關閉各個規則：被拒絕。每次都要記住要關什麼很麻煩，也容易出錯。
- 在 L1 加入「spike 模式」flag：被拒絕。level 系統應該是正交的；spike 是等級而非 flag。

**最終決策：** 新增 L0 (Spike)，完全豁免 ADR/SPEC/TDD/pipeline gates，但保留所有鐵則（破壞性操作、敏感資訊、credential scan）。強制 hitl: strict。

**理由：** 探索模式需要最低治理，但不能是零安全保護。hitl: strict 是必要的，因為 Spike 是在探索未知領域。

---

## D5: 我們決定不做的事（被拒絕的想法清單）

| 被拒絕的想法 | 拒絕理由 |
|------------|---------|
| 把 session-audit.sh 重寫為 Python | 現有 Bash 實作穩定，重寫風險高、收益低 |
| 移除 Makefile 全部速查表 | 保留 6 個最常用指令 + `make help` 一行；完全移除影響新手 |
| 把 escalation.md 整個刪除 | 轉為 skill 後，profile 可以標記為 deprecated 但不立即刪除 |
| 為 v4.0 寫完整 test suite | ASP 是 AI governance framework，測試 AI 行為比測試 code 複雜；留 v5.0 |
| 把 STRIDE 威脅模型轉為正式 security policy | 威脅模型是分析工具，執行層面的 policy 在 v4.1 的 Iron Rule 實作 |
