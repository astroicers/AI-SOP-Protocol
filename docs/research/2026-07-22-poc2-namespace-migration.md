<!-- Last Updated: 2026-07-22 | Status: POC (inventory) | Audience: ASP framework maintainers -->
# ADR-021 POC-2 — 命名空間遷移盤點

## 問題

ADR-021 把 ASP 改封裝為 plugin。Claude Code plugin 的 **skill 一律 namespaced 為 `plugin:skill`、command 為 `/plugin:command`**。ASP 現有呼叫名遷入 plugin `asp` 後會變，需盤點受影響呼叫名 + docs，並給遷移/相容方案（ADR-021 後續追蹤 POC-2）。

## 盤點

### A. Slash commands（3 支）— **零/極小變動** ✅
現於 `.claude/commands/asp/`，已 `/asp:<name>` 呼叫。plugin `asp` 的 command 同樣 `/asp:<name>`。

| 現呼叫名 | plugin 後 | 變動 |
|---|---|---|
| `/asp:approve-adr` | `/asp:approve-adr` | 無 |
| `/asp:merge` | `/asp:merge` | 無 |
| `/asp:review-work` | `/asp:review-work` | 無 |

### B. Skills（15 支）— **命名空間碰撞** ⚠️
現於 `.claude/skills/asp/asp-*.md`，名為 `asp-gate` 等（Skill tool / `/asp-gate`）。plugin `asp` 下變 **`asp:asp-<name>`**（雙 `asp`，plugin 前綴 + 檔名前綴重複）。

| 現 skill | plugin 後（保留前綴） | 若去前綴 |
|---|---|---|
| `asp-gate` | `asp:asp-gate` | `asp:gate` |
| `asp-ship` | `asp:asp-ship` | `asp:ship` |
| `asp-plan` | `asp:asp-plan` | `asp:plan` |
| …（共 15：audit/autopilot/context/dev-qa-loop/external-review/impact/level/reality-check/release/review/review-checklist/skill-author） | `asp:asp-*` | `asp:*` |

**路由**：`SKILL.md` 是意圖路由器（依用戶意圖載入子 skill），plugin 後為 `asp:SKILL`（或 `/asp <意圖>` 慣例）——同樣沾雙 `asp`。

### C. 受影響 docs / 肌肉記憶
- `/asp:` / `/asp <intent>` 引用：**15 份 live docs**（CLAUDE.md、README、docs/quickstart、docs/claude-md-reference、CHANGELOG、ADR-021~027 等）。
- skill 名引用footprint（含 cross-skill / tests / memory，grep 粗估）：asp-ship≈74、asp-gate≈60、asp-plan≈56 檔… → **去前綴重命名的波及面極大**。
- 使用者 global memory（`~/.claude/.../memory/`）多處記 `/asp:*`、`asp-*`（見 [[feedback_slash_commands_repeat_prompts]]、[[reference_asp_sync_no_self_update]]）。

## 遷移 / 相容方案

### 方案選擇：**保留 `asp-` 前綴（接受 `asp:asp-gate`）** — 建議
- **理由**：commands 零變動；skills 僅多一層 plugin 前綴、**零重命名、零 doc 改寫、零 memory 失效**；footprint 74/60/56 檔的波及被完全避免（遵守 ADR-022 複雜度預算「先問能不能用簡化需求取代」）。
- **代價**：`asp:asp-gate` 視覺冗餘。可接受——功能正確、可發現性由 marketplace 提供。

### 次選：去前綴（`asp:gate`）——不建議本階段做
- **好處**：呼叫名乾淨、對齊 addyosmani（`/spec /plan /build…`）。
- **代價**：15 skill 檔改名 + SKILL.md 路由表 + 15+ docs + 使用者 memory + `.claude/commands/asp/*` 內引用全改 → 高破壞、高回歸風險。若要做，須**獨立 ADR + 漸進**（比照 ADR-024 機會式，不 big-bang），並提供過渡別名。

### 相容策略（採建議案時）
- 過渡期 **marketplace + installer 雙路徑並存**（ADR-021 已定）：installer 使用者的 `~/.claude/skills/asp/asp-*` 與 plugin 的 `asp:asp-*` 名稱一致，肌肉記憶不斷。
- 文件契約：README/quickstart 標「plugin 安裝後 skill 呼叫為 `asp:asp-<name>`（或直接用 `/asp <意圖>` 路由）」。
- 不需別名層——因未重命名。

### 與 ADR-017 分層對齊（封裝邊界）
- **core plugin `asp`**：daily-driver 強制力（`.asp/hooks/` 的 session-audit + ship-gate + clean-allow-list）+ 15 skills + 3 commands + profiles/levels/templates。
- **不入 core plugin**（維持獨立，呼應 ADR-017）：experimental 多代理、showcase（telemetry / RAG / ai-performance）。
- installer 的「進階/離線」路徑承載 plugin 未涵蓋部分（如 profile 編譯、showcase）。

## 結論（POC-2）

- **commands 遷移零成本**；**skills 建議保留前綴**（`asp:asp-*`）以零重命名遷入 plugin，避開 56–74 檔的波及面。
- 去前綴為未來獨立 ADR 的可選優化，非 marketplace 遷移的前置。
- 封裝邊界依 ADR-017：core plugin 只含 daily-driver + skills + commands，experimental/showcase 不入包。
- **POC-2 = 完成**（盤點 + 方案已定，供實作輪據以遷移）。
