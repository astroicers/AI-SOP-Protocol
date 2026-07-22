# [ADR-028]: Compatibility assessment — pi coding agent as an alternative ASP enforcement harness

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-07-22 |
| **決策者** | ASP framework maintainers（待人類核准） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

> ⬆️ 由 `Draft` 升 `Accepted`：使用者 2026-07-22 透過 `/asp:approve-adr 028` 呼叫、看完本指令摘要的決策（選項 B：pi 作為受支援替代 harness、經薄 adapter、Claude Code 維持 primary、實作延至 `asp-pi-adapter` SPEC）與 Verification Evidence（四欄留白、POC 明確延後）後明確同意直升（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。⚠️ 本 ADR 為評估型：直升＝接受「無 POC 佐證即定案方向」；Accepted 的是**方向**，實作仍待 `asp-pi-adapter` SPEC（Draft→Accepted 不解除「無 SPEC 前禁止實作」）。

---

## 背景（Context）

使用者評估以 **pi**（`earendil-works/pi-mono`，開源多供應商 BYOK CLI coding agent，即 pi.dev；npm `@earendil-works/pi-coding-agent`）取代 Claude Code 作為 ASP 的執行 harness，並問及能否沿用 Claude Code Max 訂閱。

釐清：使用者提供的 `agegr/pi-web` 只是 pi 的本地網頁 UI（讀 `~/.pi/agent/sessions`），**非 agent 本體**；本評估針對 pi 本體。

ASP 的治理內容（憲法、成熟度等級、ADR/SPEC/TDD 工作流、SOP skills）是工具中立的；但其**強制力**目前 100% 建在 Claude Code 專屬 primitive 上（四層強制力 L1 SessionStart / L1.5 PreToolUse / L2 Dynamic Deny / L3 Skill Gates / L4 Subagent QA；註：習稱「四層」但實為 **5 個 primitive**——L1.5 PreToolUse 與 L2 Dynamic Deny 同屬「攔截 + deny」機制、合計一層，故層數=4、primitive 數=5）。本 ADR 評估：把這套強制力搬到 pi 需要什麼、哪些做得到、哪些做不到、工作量多大，並在合規前提（不使用 Claude 訂閱 OAuth，見 FC-008）下給出建議。

外部事實依鐵則「外部事實驗證防護」查證並記錄於 `.asp-fact-check.md`：**FC-007**（pi 能力逐層對應，本 session Workflow fan-out + 對抗式驗證）、**FC-008**（Anthropic 訂閱 OAuth 用於第三方 harness 的條款）。

### 逐層對應（已驗證，本評估載重內容）

強制力接線錨點：repo `.claude/settings.json` 的 `hooks`（`SessionStart → clean-allow-list.sh, session-audit.sh`；`PreToolUse matcher:"Bash" → pretooluse-ship-gate.sh`）。

| ASP 層（實作檔） | Claude Code primitive | pi 支援 | pi 機制 / 移植做法 |
|---|---|---|---|
| **L1 SessionStart**（`.asp/hooks/session-audit.sh` → `.asp-session-briefing.json` + stdout 注入 context） | SessionStart hook（每 session 一次）；stdout 餵入 model context；`$CLAUDE_PROJECT_DIR` | **native 事件、須手寫首輪 gate** | ⚠️ 無「每 session 一次且可注入」的單一事件：`session_start` 每 session 觸發但**只重建 in-memory state、不注入**；`before_agent_start` 可注入 system-prompt/message 但**每 turn 觸發**（官方 one-time 建議 async factory）。→ 用 `before_agent_start` + 首輪去重 gate（或 async factory 算 briefing）注入；bash 分析主體可留用、由擴充呼叫 |
| **L1.5 PreToolUse**（`.asp/hooks/pretooluse-ship-gate.sh` 回 `permissionDecision:"deny"`）+ **L2 Dynamic Deny**（`.asp/hooks/denied-commands.json` + session-audit 注入 `settings.local.json`，ADR-011） | PreToolUse `hookSpecificOutput.permissionDecision`；`permissions.allow/deny` 的 `Bash(...)` 模型；gitignored local scope | **native**（機制）／但**無宣告式 deny-list config** | `pi.on("tool_call")` 回 `{block:true, reason}`（官方 `examples/extensions/permission-gate.ts` 已示範擋 `rm -rf`）；deny 邏輯改寫為 TS handler（可讀外部檔/shell out 模擬動態注入）；須裝為 global/CLI 擴充避開 project-trust 才恆生效；headless 無 confirm UI → 命中預設 block |
| **L3 Skill Gates**（`.claude/skills/asp/` 16 檔；`.claude/commands/asp/` 3 檔 → `/asp:*`） | Skill 工具依 description 自動載入；`commands/<ns>/*.md` → `/ns:name`；`$ARGUMENTS` | **native** | 同一套 Agent Skills `SKILL.md` 規格（name≤64／description≤1024／progressive disclosure；pi 為 lenient 相容實作）→ `~/.pi/agent/skills/` 或共用 `~/.agents/skills/`；命令 → prompt templates（`.pi/prompts/`）。摩擦：叫用變 `/skill:asp-plan`；prompt 目錄**非遞迴**（`/asp:*` 命名空間需壓平）；ASP 用 `$ARGUMENTS` 可原樣（pi `$N` 為 1-based） |
| **L4 Subagent QA**（`.claude/agents/` reality-checker／security-auditor／test-engineer，唯讀；Agent/Task tool `subagent_type`） | 原生 subagent + Task tool；in-process 唯讀隔離 | **partial** | pi 明列「No sub-agents」為**非目標**；但有**官方範例擴充** `examples/extensions/subagent/`（markdown+YAML frontmatter、`~/.pi/agent/agents/*.md`、子行程隔離、parallel max 8／4-concurrent、`tools` frontmatter + SDK `createReadOnlyTools()` 做唯讀），或裝現成套件（`@vigolium/piolium` = security-auditor 對應、`@tintinweb/pi-subagents`）。差異：無 first-class Task API（須組裝/安裝）、隔離為**子行程級**非 in-process |
| **Profile/編譯**（`.asp/scripts/asp-compile.sh` → `.asp-compiled-profile.md`，mtime 重編，ADR-016） | SessionStart 觸發重編；CLAUDE.md 映射載入 artifact | **native**（config）＋一處非原生 | 憲法/profile → `SYSTEM.md`／`APPEND_SYSTEM.md`／`AGENTS.md`（**pi 本就讀 `CLAUDE.md`**，現有 ASP CLAUDE.md 可原樣載入）；~30 生命週期事件。**非原生**：compiled-artifact + mtime 重編（改由擴充在 `session_start` 重算/自管 cache——影響小） |
| **合規 auth** | API key 或訂閱 OAuth | **native** | `ANTHROPIC_API_KEY`／`auth.json`／`--api-key`，與 `/login` OAuth 獨立；多供應商（OpenAI/Gemini/Bedrock/Vertex/Ollama via `models.json`）原生。**須營運上釘死 API-key、禁 `/login`** 以守住合規前提（見 FC-008） |

**判定**：技術可行、屬「中等 adapter 工作量」，**非 drop-in**。SOP 內容（16 skill 本體、`asp-compile.sh`、`denied-commands.json` 資料、profile/level `.yaml`/`.md`、QA 檢查清單）幾乎原樣可攜；真正需重建的 enforcement = ~2–3 個 pi 擴充（briefing 注入[`before_agent_start`+首輪去重] + tool_call deny gate + L4 dispatch）+ 採用 subagent 範例擴充補 L4 + 壓平 slash 命名空間 + 憲法進 SYSTEM.md。需寫新程式碼的層分兩類：**(a) 完全無 native primitive、須另建的＝L4**（pi 明列 sub-agents 為非目標，須靠官方範例擴充/社群套件另建）；**(b) 有 native primitive、但須手寫 handler 邏輯＝L1、L1.5、L2**——L1 SessionStart 因無「每 session 一次且可注入」的單一事件，須 `before_agent_start`(per-turn) + 首輪去重 gate（`session_start` 只重建 state、不注入）；L1.5/L2 的 deny 須手寫 TS handler（無宣告式 deny-list 可原樣搬）；其餘（L3 Skill/Command、Profile-config、auth）為近原生的**薄綁定**。pi 的擴充 API（型別化 TS 事件、~30 生命週期事件、可改 system prompt / 註冊 tool/command / 擋 tool call）在表達力上其實**比 Claude Code shell hook 更豐富**。

---

## 評估選項（Options Considered）

### 選項 A：完全遷移（pi 取代 Claude Code）

- **優點**：解鎖多供應商／自架模型（Ollama/vLLM）；擴充 API 型別化、表達力強；擺脫對單一 harness 的鎖定。
- **缺點**：一次性重建整個 enforcement 層；L4 唯讀隔離改為子行程級（邊界不弱，但無 first-class Task API、須經範例擴充組裝）；失去 Claude 訂閱計費（僅能走 API-key 按量付費）；pi 生態較年輕、部分關鍵能力（L4）依賴社群/範例擴充。
- **風險**：把成熟、正在 dogfood 的 Claude Code 強制力換成未驗證的移植；enforcement 退化為 in-process advisory（可藉「不載入擴充」繞過）而無明確補償；過早 all-in。

### 選項 B（建議）：雙 harness——pi 作為受支援的替代 harness（經薄 adapter），Claude Code 維持 primary/reference

- **優點**：SOP 內容本就可攜、零損失即可讓 pi 使用者跑 ASP 治理；enforcement 缺口以一層小 `asp-pi` adapter（~2 擴充 + L4 範例擴充）補；Claude Code 仍為 canonical 強制力參考，風險隔離；實作延到未來 SPEC，有實需再投入。
- **缺點**：需維護兩套 harness 綁定（雖然內容共用）；adapter 的 enforcement 等價性需 POC 驗證。
- **風險**：adapter 若無人投入則 pi 使用者只得「內容可攜、強制力較弱」；須明確標註此差距、不宣稱等價。

### 選項 C：維持現狀（只支援 Claude Code，不支援 pi）

- **優點**：零工作量；enforcement 維持最強。
- **缺點**：放棄 pi 獨有的多供應商／自架／合規多路線能力；把 ASP 永久鎖在單一 harness。
- **風險**：若 Claude Code 條款/計費/可用性變動（參 FC-008 條款波動），ASP 無退路。

---

## 決策（Decision）

建議採 **選項 B**：**將 pi 定位為受支援的替代 enforcement harness，經一層薄 `asp-pi` adapter；Claude Code 維持 primary/reference。實作不在本 ADR，延至未來 `asp-pi-adapter` SPEC（有實需再啟動）。**

本 ADR 狀態為 `Draft`——**僅為評估與建議，待人類核准；核准前不寫任何生產代碼**（符合鐵則「ADR 未定案禁止實作」）。

合規前提（不可協商，見 FC-008）：任何 pi 落地一律走 **`ANTHROPIC_API_KEY`（或他供應商）按量付費路線，禁用 `/login` 訂閱 OAuth**。Claude Code **Max 訂閱額度無法合規地用於 pi**——載重理由是 Anthropic 2026-02 起明訂訂閱 OAuth 憑證僅限官方客戶端，`pi-claude-auth` 讀取該憑證雖技術可行但違反條款、有封號風險。（另註：曾於 2026-06-15 宣布、可讓訂閱涵蓋第三方用量的「Agent SDK 額度」**已於生效前暫停、目前不可用**，且該機制僅涉及**建於 Claude Agent SDK 的工具**——pi 非其一；故此路亦不通。詳 FC-008。）

---

## 後果（Consequences）

**正面影響：**
- 明確記錄「ASP 內容可攜、強制力綁 harness」的邊界，未來換 harness 有藍圖。
- 為多供應商／自架模型／合規多路線鋪路（pi 能力，Claude Code 無）。
- 兩筆 fact-check（FC-007/FC-008）沉澱 pi 與 Anthropic 條款的一手查證，供後續複用。

**負面影響 / 技術債：**
- 選 B 需維護兩套 harness 綁定（內容共用、綁定分歧）。
- pi 上 enforcement 為 in-process advisory（可藉不載入擴充繞過）——但 Claude Code hook 本質亦同；須誠實標註、不宣稱 OS 級強制。
- L4 唯讀隔離的**實作方式不同**（非資安退步）：Claude Code 為 in-process（Task tool + 唯讀工具限制），pi 為子行程級（`tools` frontmatter + `createReadOnlyTools`）——子行程隔離邊界不弱、甚至更硬，但代價是**無 first-class Task API**（須經官方範例/社群擴充組裝）與失去緊密 context 共享；且依賴社群/範例擴充，需選一個標準化並當作依賴審查。
- 放棄 compiled-profile 的 mtime 快取最佳化（改由擴充重算，影響小）。

**後續追蹤：**
- [ ] 若核准 → 開 `asp-pi-adapter` SPEC：定義 ~2–3 擴充（briefing 注入[`before_agent_start`+首輪去重]、tool_call deny gate、L4 dispatch）+ L4 範例擴充選型 + slash 命名空間壓平方案。
- [ ] POC：pi tool_call deny 擋下等同 `denied-commands.json` 的 12 條破壞性操作。
- [ ] 釘死 API-key 路線的營運護欄（provision `ANTHROPIC_API_KEY`、禁 `/login`）。

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 可原樣移植的 SOP 內容 | 多數工具中立（skills/profiles/compiler/checklists/deny 資料） | 逐項清點檔案（skill 16 + command 3 + profile/level/config + compiler 腳本） | 待 `asp-pi-adapter` SPEC 實測百分比（本 ADR 僅質性判定，未加總比例） |
| 完全無 native primitive、須另建的層數 | 1（僅 L4；pi 明列 sub-agents 為非目標） | 對應表 | 本 ADR（已達） |
| 有 native primitive 但須手寫 handler 邏輯的層數 | 3（L1 的 `before_agent_start`+首輪 gate；L1.5/L2 的 deny handler；Profile mtime 快取為次要） | 對應表 | 本 ADR（已達） |
| adapter 所需新增 pi 擴充檔數 | ≤3（briefing 注入[含首輪去重] + tool_call deny + L4 dispatch） | adapter SPEC POC 計數 | `asp-pi-adapter` SPEC |
| enforcement 等價性（破壞性操作阻擋） | pi tool_call deny 擋下 `denied-commands.json` 全 12 條 | POC 實測 | `asp-pi-adapter` SPEC POC |

**重新評估條件**：pi 擴充事件模型／skill/agent 規格／auth 路線變更（FC-007 失效），或 Anthropic 條款/Agent SDK 額度政策變更（FC-008 失效）時，須重審本 ADR。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - **FC-007**（pi 能力逐層對應）、**FC-008**（Anthropic 訂閱 OAuth 條款）——本 ADR 事實依據。
  - **ADR-011**（動態 deny 隔離至 settings.local.json）——L2 對應 pi tool_call handler 的來源。
  - **ADR-016**（compiled-profile）——Profile/編譯層的移植對象。
  - **ADR-020**（把 AI 遺忘當一級威脅、機械化強制；偽硬 gate 之忌）——「enforcement 綁 harness、內容可攜」的張力來源；提醒 pi 上勿宣稱過強強制。
  - **ADR-021**（Claude Code plugin/marketplace 分發）——pi「packages」（npm/git 散發 skills+prompts+extensions）為對應散發模型。
  - **ADR-027**（多 session worktree 隔離）——pi 亦內建 worktree sidebar，跨 harness 的並行治理主題相關。

---

## Verification Evidence（升級至 FIRM 時必填）

| 欄位 | 內容 |
|------|------|
| POC 分支／測試結果 | （待人類核准後，於 `asp-pi-adapter` SPEC 補：pi tool_call deny 擋 12 條 POC、briefing 注入[`before_agent_start`+首輪 gate] POC） |
| 驗證日期 | — |
| 驗證者 | — |
| 驗證摘要 | — |
