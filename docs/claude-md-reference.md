# CLAUDE.md 機制參考（下沉細節）

> 本檔承接 [CLAUDE.md](../CLAUDE.md) 下沉的「機制細節」——為降低行為憲法首屏認知負荷而移出（P0 onboarding slimming）。
> CLAUDE.md 仍是行為憲法本體（鐵則 / 過程義務速查 / 啟動程序 / Profile 核心映射）；本檔是它的參考附錄，內容語意不變、僅換位置。

---

## 強制力架構（四層機制）

| Layer | 機制 | 強制力 |
|-------|------|--------|
| L1: SessionStart | `session-audit.sh` → `.asp-session-briefing.json` | 硬（啟動時輸出 BLOCKER） |
| L1.5: PreToolUse | `pretooluse-ship-gate.sh` 攔 `git commit`：無新鮮測試痕跡 → deny（ADR-020 遺忘威脅；escape hatch `ASP_SHIP_OK=1` + fail-open 防死鎖） | 硬（commit 前機械擋） |
| L2: Dynamic Deny | `Draft` ADR / 測試未過 → 動態阻擋 `git commit`；`FIRM` ADR → 允許但記錄 bypass log | 硬（VSCode deny dialog） |
| L3: Skill Gates | `asp-ship`(10步，含 Step 9.6 gate-log 後驗) + `asp-gate`(G1-G6) + `asp-plan` Step 5.5 auto-gate（ADR-009 + SPEC-006 已落地：staged ADR/SPEC 機械觸發 G1/G2 subagent，報告存 `.asp-gate-log/`） | 結構化軟性 |
| L4: Subagent QA | `asp-reality-check` 獨立驗證（on-demand） | 中等 |

> 對應的「AI 必須報告 BLOCKER」與「必須調用 Skill 的時機」屬行為義務，**不下沉**，仍留在 [CLAUDE.md 強制力架構段](../CLAUDE.md#強制力架構)。

---

## 常用指令

| 動作 | 指令 |
|------|------|
| 新增 ADR | `make adr-new TITLE="..."` |
| 新增 SPEC | `make spec-new TITLE="..."` |
| 執行測試 | `make test` |
| 健康審計 | `make audit-health` |
| 重新執行審計 | `make asp-refresh` |
| 解除 commit 阻擋 | `make asp-unlock-commit` |

完整指令：`make help` | 入門文件：`docs/where-to-start.md`、`docs/quickstart.md`

---

## ASP slash 指令三形式（命名慣例）

三種掛 "asp" 的指令機制不同，別混：

- **`/asp <意圖>`** — 路由 skill（`skills/asp/SKILL.md`，唯一註冊的 ASP skill）。依意圖分流到內部 worker（`skills/asp/asp-*.md`：plan/ship/gate/audit/level…）。docs 裡 `/asp-ship` 等連字號是舊寫法，實際走 `/asp ship`。
- **`/asp:approve-adr`、`/asp:review-work`、`/asp:merge`** — 獨立單步 command（`.claude/commands/asp/*.md`，子資料夾＝冒號前綴；user-global 經 `asp-sync` 同步，本環境實證呼叫名帶冒號，見 `.asp-fact-check.md` FC-003）。

**慣例**：`/asp <意圖>`＝治理工作流（plan/ship/gate/audit/level/review/release）；`/asp:<動作>`＝單步快捷（approve-adr/review-work/merge）。新增單步快捷 → 放 `.claude/commands/asp/`；新增工作流階段 → 放 `skills/asp/` 並更新路由表。
