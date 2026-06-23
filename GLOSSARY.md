# GLOSSARY — ASP 術語快查

> 一頁速查：縮寫 / 術語 → 一句話。**完整定義、避免使用詞、相關 ADR 見 [CONTEXT.md](CONTEXT.md)**——深度定義唯一來源，本表不重複。
> 新術語請加到 CONTEXT.md（由 `/asp-context` skill 維護）；本表只摘一句話，與 CONTEXT 同步時以 CONTEXT 為準。

---

## 縮寫速查

| 縮寫 | 全稱 | 一句話 |
|------|------|--------|
| ASP | AI-SOP-Protocol | 給 AI coding agent 的行為憲法 + 機械護欄框架 |
| ADR | Architecture Decision Record | 架構決策記錄；`Draft` 狀態下 `git commit` 被動態阻擋 |
| SPEC | Software Design Specification | 任務級七欄位設計文件，G2 核心產物 |
| G1-G6 | Quality Gate 1-6 | ADR→SPEC→測試先行→實作→安全→部署 六道品質門 |
| HITL | Human-in-the-Loop | 破壞性操作必須人類確認的鐵則 |
| L0-L5 | Maturity Level 0-5 | 舊六級成熟度，v5 收斂為 loose / standard / autonomous |
| SRS / SDS | Software Requirements / Design Spec | Autopilot 前置文件體系 |
| SIT | System Integration Test | G6.5 Post-Deploy 整合測試 |
| STRIDE | Spoofing / Tampering / … | 威脅建模方法論（ADR-002） |
| NDJSON | Newline Delimited JSON | Bypass Log 格式（Iron Rule B） |

## 術語速查

| 中文 | English | 一句話 |
|------|---------|--------|
| Profile | Behavioral Specification File | 載入 context 的行為規格 `.md`，定義 AI 在某場景的預設行為 |
| Skill | Structured Command Workflow | `/skill-name` 觸發的結構化指令集 |
| Gate | Quality Gate | G1-G6 的品質門檻檢查 |
| Session Briefing | Session Briefing | SessionStart 自動產生的 BLOCKER / WARNING JSON |
| Bypass Log | Bypass Log | append-only skip 記錄；同步驟累計 3 次觸發 BLOCKER |
| Dynamic Deny List | Dynamic Deny List | 依專案狀態動態注入 settings 的 `deny` 清單 |
| Reality Checker | Reality Checker | 預設否定的獨立懷疑論 subagent，G5 交叉驗證 |
| Smuggling | Unauthorized Logic Injection | 在已批准工作中夾帶未授權的邏輯變更 |
| Maturity Level | Maturity Level | loose / standard / autonomous 三級成熟度 |
| Loose Mode | Loose Mode | 鬆治理 profile（含 `[spike]` 探索豁免） |
| Autopilot | ROADMAP-driven Execution | ROADMAP.yaml 驅動、跨 session 續接的連續執行 |
| Provenance | Task Provenance | 任務來源信任屬性（人類手寫 vs 外部），決定授權強度 |
| Task Inbox | External Task Queue | asp-operator 投遞外部 issue 的惰性佇列 |
| Held | Awaiting Human Authorization | 外部任務只回報不注入的安全暫置狀態 |
| Triage-accept | Human Authorization | 人類 commit 即授權的可驗證放行通道 |
| Pipeline | ASP Development Pipeline | G1→G6 六階段開發流程 |
| Telemetry | Telemetry Event Log | `.asp-telemetry.jsonl` 行為事件記錄 |
| Claude Code | Anthropic CLI | ASP 的執行環境 |
| gh | GitHub CLI | ASP 官方 issue tracker 操作工具 |

---

> 看到沒列在這裡的術語？→ [CONTEXT.md](CONTEXT.md) 有完整深度定義（含「避免使用」詞與相關 ADR）。
