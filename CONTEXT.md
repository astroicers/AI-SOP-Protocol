# CONTEXT.md — ASP 領域詞彙表

> 由 `/asp-context` skill 維護。所有 ADR、SPEC、commit message 使用的術語必須與此表一致。
> 最後更新：2026-05-05

---

## 中英術語對照（Bilingual Term Index）

| 中文術語 | English Term | 縮寫 / Alias |
|---------|-------------|-------------|
| ASP（AI-SOP-Protocol） | AI Standard Operating Protocol | ASP |
| Profile | Behavioral Specification File | — |
| Skill | Structured Command Workflow | — |
| Gate（品質門） | Quality Gate | G1-G6 |
| HITL | Human-in-the-Loop | HITL |
| Session Briefing（session 簡報） | Session Briefing | — |
| Bypass Log（繞過記錄） | Bypass Log | — |
| Dynamic Deny List（動態拒絕清單） | Dynamic Deny List | — |
| Reality Checker（懷疑論者 subagent） | Reality Checker | — |
| Smuggling（偷渡） | Smuggling (Unauthorized Logic Injection) | — |
| CONTEXT.md（領域詞彙表） | Domain Vocabulary File | — |
| Maturity Level（成熟度等級） | Maturity Level | L0-L5 |
| Autopilot（自動駕駛） | Autopilot (ROADMAP-driven execution) | — |
| Provenance（來源出處） | Task Provenance | — |
| Task Inbox（任務收件匣） | Task Inbox (External Task Queue) | inbox |
| Held（待授權暫置） | Held (Awaiting Human Authorization) | held |
| Triage-accept（人類分診核准） | Triage-accept | triage |
| Pipeline（開發流程） | ASP Development Pipeline | G1→G6 |
| SPEC | Software Design Specification | SPEC |
| ADR | Architecture Decision Record | ADR |
| Telemetry（遙測） | Telemetry Event Log | — |
| Claude Code | Claude Code (Anthropic CLI) | claude |
| gh | GitHub CLI | gh |

---

## 核心概念

### ASP（AI-SOP-Protocol）
**English:** AI Standard Operating Protocol
**定義：** 一套以 Claude Code 為執行環境的 AI 治理框架，透過 Profile、Skill、Hook 和 Gate 的組合，強制 AI 遵守品質紀律與安全邊界。
**避免使用：** [SOP框架, Claude治理, AI規則集]（這些詞語過於模糊，無法與其他框架區別）
**相關 ADR：** ADR-002

### Profile
**English:** Behavioral Specification File
**定義：** 載入至 Claude context 的 Markdown 行為規格檔案，定義 AI 在特定場景下的預設行為、限制與工作流程；位於 `.asp/profiles/`。
**避免使用：** [設定, config, 規則檔]（Profile 是行為規格，不只是設定）
**相關 ADR：** ADR-001

### Skill
**English:** Structured Command Workflow
**定義：** Claude Code 原生可調用的結構化指令集（`.claude/skills/asp/asp-*.md`），使用者以 `/skill-name` 觸發，Skill Router（SKILL.md）負責路由。
**避免使用：** [命令, 指令, command]（Skill 是結構化工作流，不只是單一指令）

### Gate（G1-G6）
**English:** Quality Gate (G1-G6)
**定義：** ASP pipeline 的六個品質門檻檢查點，由 `asp-gate` skill 執行；G1=ADR、G2=SPEC 完整性、G3=測試先行、G4=實作通過、G5=安全審查、G6=部署就緒。
**避免使用：** [Checkpoint, 關卡, 審查點]（Gate 特指 G1-G6 這六個固定門檻）

### HITL（Human-in-the-Loop）
**English:** Human-in-the-Loop
**定義：** ASP 鐵則之一：破壞性操作（`git push`、`rm -rf` 等）必須先列出變更並等待人類確認才能執行。
**避免使用：** [人工確認, manual approval]（HITL 是 ASP 的固定術語，包含明確的觸發場景清單）

---

## 系統元件

### Session Briefing（.asp-session-briefing.json）
**English:** Session Briefing
**定義：** `session-audit.sh` 在 SessionStart 時自動產生的 JSON 報告，包含 BLOCKER、WARNING、INFO 三個等級的專案狀態；AI 必須在 session 開始時讀取並向使用者報告 BLOCKER。
**避免使用：** [session report, 啟動報告]（Session Briefing 是固定檔案名稱與固定機制）

### Bypass Log（.asp-bypass-log.ndjson）
**English:** Bypass Log (Append-Only Skip Record)
**定義：** Append-only NDJSON 格式的 skip 事件紀錄，由 `asp-gate` 自動寫入；同一步驟累計 3 次 bypass 觸發 BLOCKER。
**避免使用：** [跳過記錄, skip log]（Bypass Log 強調「不可縮短」的 append-only 語義）
**相關 ADR：** ADR-002（Iron Rule B）

### Dynamic Deny List
**English:** Dynamic Deny List
**定義：** `session-audit.sh` 根據專案當前狀態（Draft ADR 存在、測試未通過）動態注入至 `.claude/settings.json` 的 `deny` 陣列，使危險指令在 VSCode 跳出阻擋對話框。
**避免使用：** [黑名單, 禁令清單]（Dynamic Deny List 強調「根據狀態動態生成」的行為）

### Reality Checker
**English:** Reality Checker (Skeptic Subagent)
**定義：** 獨立 context 的懷疑論者 subagent（`.claude/agents/reality-checker.md`），預設回覆 NEEDS_WORK，用於 G5 交叉驗證；不可被主 agent 的 context 影響。
**避免使用：** [reviewer, QA agent]（Reality Checker 特指獨立 context + 預設否定 這個組合）

### Smuggling（偷渡）
**English:** Smuggling (Unauthorized Logic Injection)
**定義：** ASP 特有的安全威脅類別：AI 在已批准的實作工作中夾帶未經授權的邏輯變更；由測試 checksum 比對與 spec 對照偵測。
**避免使用：** [scope creep, 超出範圍]（Smuggling 特指惡意或非預期的隱性夾帶行為，不只是範圍擴張）
**相關 ADR：** ADR-002

### CONTEXT.md
**English:** Domain Vocabulary File
**定義：** repo root 的領域詞彙表檔案，由 `/asp-context` skill 維護；session 啟動時若存在則自動讀取，確保 ADR/SPEC/commit 的術語一致性。
**避免使用：** [詞彙表, glossary, 術語檔]（CONTEXT.md 是 ASP 的固定檔案路徑與機制名稱）

---

## 流程與狀態

### Maturity Level（成熟度等級）
**English:** Maturity Level (loose / standard / autonomous)
**定義：** ASP v5 的三個成熟度等級（loose → standard → autonomous，ADR-014 由 v4 的 L0-L5 六級收斂），定義啟用哪些 Profile 組合與 graduation_checklist；透過 `asp-level` skill 評估與升級。遺留數字值 0-5 由 `level-resolve.sh` 自動映射（0,1→loose｜2,3→standard｜4,5→autonomous），v6 移除。
**避免使用：** [等級, 版本, tier, L0-L5（歷史文件外）]（loose/standard/autonomous 是 v5 固定用語）
**相關 ADR：** ADR-014

### Loose Mode（鬆治理模式）
**English:** Loose Mode
**定義：** v5 的鬆治理 profile（`loose_mode.md`，ADR-014 併自 vibe coding + spike mode）：角色分工 + 探索豁免（`[spike]` commit 標記、豁免期間 hitl 強制 strict）+ Context 管理。載入條件：`level: loose` 或 `workflow: vibe-coding`。
**避免使用：** [vibe coding profile, spike mode profile]（兩者已歸檔，v5 起統稱 Loose Mode）
**相關 ADR：** ADR-014

### Autopilot
**English:** Autopilot (ROADMAP-driven Continuous Execution)
**定義：** ROADMAP.yaml 驅動的連續執行模式（`autopilot: enabled`），自動逐一執行 Roadmap 任務直到 token 用盡，跨 session 透過 `.asp-autopilot-state.json` 續接。
**避免使用：** [自動模式, 自動執行]（Autopilot 特指 ROADMAP.yaml 驅動 + 跨 session 續接 這個完整機制）
**相關 ADR：** ADR-001

### Provenance（來源出處）
**English:** Task Provenance
**定義：** 任務的來源屬性標記——**人類手寫** vs **外部來源**（帶 `source_type`/`triggered_by` 等 inbox schema 欄位）。ADR-012 信任模型以 provenance 決定授權強度：外部來源任務須人類放行，人類手寫任務維持既有機制。
**避免使用：** [來源, source, origin]（Provenance 特指「決定授權路徑的信任屬性」，不是一般的資料出處）
**相關 ADR：** ADR-012

### Task Inbox（任務收件匣）
**English:** Task Inbox (External Task Queue)
**定義：** `.asp-task-inbox.json`——asp-operator 將外部 GitHub issue 翻譯後投遞的**惰性佇列**。SPEC-007 起 inbox 內容不再自動進入 ROADMAP（見 Held），僅作為待人類授權的暫存。
**避免使用：** [佇列, queue, 任務池]（Task Inbox 是固定檔名與固定機制，且自 SPEC-007 起為「惰性」——寫入不產生執行效果）
**相關 ADR：** ADR-012

### Held（待授權暫置）
**English:** Held (Awaiting Human Authorization)
**定義：** 外部來源任務在 inbox 中的暫置狀態：SessionStart 只**回報**不注入（`status: pending` 保持不變），直到人類透過 Triage-accept 或 Accepted ADR 放行。SPEC-007 的核心語意。
**避免使用：** [擱置, 凍結, pending 中]（Held 特指「等待人類授權」的安全暫置，不是任意的延遲）
**相關 ADR：** ADR-012

### Triage-accept（人類分診核准）
**English:** Triage-accept (Human Authorization for Non-architectural External Tasks)
**定義：** 外部**非架構**任務的人類放行通道：人類執行 `make inbox-triage` 逐件核准，任務寫入 ROADMAP（帶 `triage_accepted_by`）並由人類自行 commit——**該 commit 的作者即機械可驗證的授權記號**（autopilot 閘以 `git log -S` 驗證、bot 樣式拒絕）。SPEC-009 落地。
**避免使用：** [審核, approve, 人工確認]（Triage-accept 特指「人類 commit 即授權」這個可驗證機制，不是一般的口頭核可）
**相關 ADR：** ADR-012

### Pipeline（G1→G6）
**English:** ASP Development Pipeline (G1→G6)
**定義：** ASP 的六階段開發流程：ADR → SPEC → 測試先行 → 實作 → 安全審查 → 部署就緒，每個階段由對應的 Gate 把關。
**避免使用：** [流程, workflow, CI/CD pipeline]（ASP Pipeline 特指 G1-G6 這個有序門檻序列，與 CI/CD 基礎設施不同）

### SPEC（Software Design Specification for a task）
**English:** Software Design Specification (7-field task spec)
**定義：** ASP 中每個任務必須先有的設計文件（七欄位：Why / What / How / Done When / Risk / Test Plan / Rollback），是 G2 Gate 的核心產物。
**避免使用：** [規格, spec文件, 設計文件]（SPEC 在 ASP 語境中特指七欄位的任務級設計文件）

### ADR（Architecture Decision Record）
**English:** Architecture Decision Record
**定義：** 架構決策記錄，存放於 `docs/adr/`；Draft 狀態下 Dynamic Deny List 自動阻擋 `git commit`，須等 ADR 狀態改為 Accepted 才能開始實作。
**避免使用：** [架構文件, 設計決策]（ADR 是 ASP 鐵則的核心觸發器，不只是文件分類）

### Telemetry（.asp-telemetry.jsonl）
**English:** Telemetry Event Log
**定義：** JSONL append-only 格式的 ASP 行為事件紀錄，記錄 gate_fail、bypass、session_start 等事件；由 `make asp-telemetry-collect` 收集，`make asp-telemetry-report` 分析。
**避免使用：** [log, 日誌, metrics]（Telemetry 在 ASP 語境中特指 `.asp-telemetry.jsonl` 的格式與管線）
**相關 ADR：** ADR-004

---

## 外部依賴

### Claude Code（claude）
**English:** Claude Code (Anthropic CLI)
**定義：** Anthropic 的 CLI 工具，ASP 的執行環境；ASP 的 Hook、Skill、Agent 等機制均依賴 Claude Code 的 SessionStart hook 與 settings.json permission model。
**避免使用：** [Claude CLI, claude-code]（正式名稱是 Claude Code）

### gh（GitHub CLI）
**English:** GitHub CLI
**定義：** ASP issue tracker 的操作工具；GitHub Issues（`astroicers/AI-SOP-Protocol`）是 ASP 的官方 issue tracker，所有操作透過 `gh` CLI 執行。
**避免使用：** [GitHub API, 手動建立 issue]（ASP 規定使用 `gh` CLI，不使用 web UI 或直接 API 呼叫）

---

## 縮寫對照

| 縮寫 | 全稱 | 說明 |
|------|------|------|
| ASP | AI-SOP-Protocol | 框架本體 |
| HITL | Human-in-the-Loop | 人類確認機制 |
| ADR | Architecture Decision Record | 架構決策記錄 |
| SPEC | Software Design Specification | 任務級設計文件（七欄位） |
| G1-G6 | Gate 1-6 | ASP pipeline 六個品質門檻 |
| SRS | Software Requirements Specification | 需求規格文件（Autopilot 前置文件體系） |
| SDS | Software Design Specification | 系統設計文件（Autopilot 前置文件體系） |
| SIT | System Integration Test | G6.5 Post-Deploy 整合測試 |
| STRIDE | Spoofing/Tampering/Repudiation/Info Disclosure/Denial/Elevation | 威脅建模方法論（ADR-002） |
| NDJSON | Newline Delimited JSON | Bypass Log 格式（Iron Rule B） |
| L0-L5 | Level 0-5 | ASP Maturity Level 縮寫 |
