# ASP v4.0 Design Notes — Architecture & Execution Tracker

> **本檔案定位**：ASP v4.0 重構的 **Software Design Specification (SDS, 軟體設計規格書)**，含執行進度追蹤。
>
> **使用方式**：v4.0 開發時這份是 single source of truth (單點真相)。可整份 paste 進 Claude Code session 當作設計憲章。
>
> **三份檔案分工**：
> - `~/docs/cs146s-study-notes.md` (personal notes, not in repo) — 學什麼、學會了什麼（學習過程）
> - `docs/v4-architecture-sds.md` ← **本檔案** — 為什麼這樣設計（架構與決策）
> - `docs/v4-refactor-prompts.md` — 怎麼執行（11 個可執行 prompt）
> - `docs/production-ops-playbook.md` — 框架完成後怎麼用 AI 維運（生產維運手冊）

---

## Frontmatter

| 欄位 | 值 |
|-----|---|
| Version | v4.0 design draft |
| Status | Planning |
| 起源 | CS146S 學習 + ASP v3.7 完整審視 |
| Owner | astroicers |
| 起始日期 | 2026-05-04 |
| 最後更新 | 2026-05-04 |

### 跨檔案索引

- 各週學習對 ASP 的具體建議：見 `~/docs/cs146s-study-notes.md` (personal notes, not in repo) 各週「ASP 對照分析」段落
- 可執行的 11 個 prompt：見 `docs/v4-refactor-prompts.md`
- v3.7 既有檔案：`AI-SOP-Protocol/.asp/profiles/`、`AI-SOP-Protocol/.claude/skills/asp/`、`AI-SOP-Protocol/CLAUDE.md`

---

## 1. Goal (目標)

> **30 字 essence**：把 v3.7「20 profile + 309 行 CLAUDE.md」的 push-heavy 設計，重構為「< 80 行 CLAUDE.md + skills/MCP pull layer + deterministic hooks」的三層架構，向官方 best practice 對齊。

### Why v4.0 (為什麼要重構)

ASP v3.7 累積了大量 production-grade 設計（Reality Checker、4 層強制力、動態 deny list、cross-component invariants），但這些設計同時暴露**五個結構性盲點**（見 §3.1）。v4.0 不是漸進改良，是**架構層面的範式轉移 (paradigm shift)**——從「靠 LLM 守規矩」轉向「靠 mechanism 強制」。

### Scope (範圍)

**v4.0 解決**：
- CLAUDE.md 過長（token 經濟 + 注意力稀釋 + attack surface）
- Multi-agent 衝突（file lock 軟性機制 → git worktree 硬性機制）
- Profile vs Skill 邊界混亂（push 內容做成 pull 形式）
- 對抗式 AI 威脅鐵則缺口
- ASP 自身缺 telemetry

**v4.0 不解決**（防止 scope creep）：
- 不取代 Anthropic 官方 Skills 生態 — 兩者互補
- 不為 enterprise 多人協作優化 — 仍是個人/小團隊定位
- 不做雲端共用版 — 維持 local-only
- 不重寫既有 13 個 asp-* skill — 向後相容
- 不改變 maturity level L1-L5 的核心語意（但新增 L0）

---

## 2. Inputs (輸入依據)

| Input | 來源 |
|-------|-----|
| ASP v3.7 完整審視 | 最初的 5 盲點分析 |
| Anthropic Claude Code best practices | W4 教材 |
| `git worktree` multi-agent pattern | W5 教材 |
| OAuth confused deputy / OBO Flow | W3 教材 |
| Six prompting primitives | W1 教材 |
| W2 K-shot 補充（甜區、lost in the middle、dynamic K-shot）| W2 教材 |
| Disposition Matrix methodology | Skills vs ASP 討論 |
| 11 個可執行 prompt | `docs/v4-refactor-prompts.md` |

---

## 3. Pre-existing State Analysis (現況分析)

### 3.1 — ASP v3.7 五個結構性盲點

#### 盲點 1：Anti-Reflexion 框架，宣稱 agent-friendly

**現象**：ASP 是 plan → approve (ADR Accepted) → execute 模型，Draft ADR 動態阻擋 git commit、Assumption Checkpoint Protocol 強制實作前先列假設等待確認。

**問題**：與 Reflexion (try → fail → reflect → retry) 哲學相反。對政府/軍方場景對的，但對探索性開發、安全研究、PoC 會把速度卡死。`vibe_coding` profile 仍要載 `global_core` 全部規則，沒有真正的 sandbox / spike / 限期銷毀工作流。

**v4.0 對應改動**：新增 **L0 (Spike) maturity level**，CLAUDE.md ≤ 30 行、無 ADR/SPEC 強制、無 G1-G6 gate，只保留鐵則 + 敏感資訊保護。

**W8 補強的 L0 lifecycle 機制**（從 W8 學的）：

L0 有清楚的入口（怎麼進）但 W8 暴露需要補出口跟診斷：

1. **Promotion Gate (晉升閘)** — 明確 trigger 條件：
   - 第一個非你之外的使用者出現 → 強制評估升 L1
   - 處理任何真實 PII / 金流 → 強制升 L2 以上
   - 跑超過 60 天 → 強制 audit 是否該升級

2. **Throwaway Expiration (用完即丟期限)** — L0 code 應有保鮮期，超過 force decision (升級或刪除，不准放著腐爛)

3. **Active L0 vs Zombie L0 區分** — 長期 L0 不一定是 trap：
   - Active：還在用 / 改起來容易 / 失去會難過 → 健康，繼續 L0
   - Zombie：忘了怎麼運作 / 改一處 30 分鐘 / 偶爾出 bug 浪費半天 → 升級或刪除
   - 自我診斷 3 問：5 分鐘讀完能講清楚？/ 過去 30 天因它浪費 >1 小時？/ 失去它會難過？

→ 對應 prompt: Prompt 7 (L0 草擬)

#### 盲點 2：CLAUDE.md 309 行 + 20 profiles → AI 跳讀

**現象**：違反 Anthropic 官方原則「**Iterate on CLAUDE.md like a prompt, keep it concise (精煉) and actionable (可執行)**」。309 行 + L5 配置（multi-agent + autopilot + rag + 全選配 profile）載入消耗 ~15-25k token，**還沒開始做事**。

**問題**：
- Lost in the Middle (中間段落被忽略) — 規則密度高但 LLM 注意力跳過中段
- Token 經濟性破壞 multi-agent 並行
- Trust Boundary 攻擊面過大（309 行 = 309 個 prompt injection 點）

**v4.0 對應改動**：CLAUDE.md 砍到 ≤ 80 行，內容用 5 種 offload 策略搬走：
1. Hierarchy（`backend/CLAUDE.md` 等分層）
2. External docs（背景敘述進 `docs/PHILOSOPHY.md`）
3. Slash Commands（workflow 進 `.claude/commands/`）
4. Conditional loading（強化 `.ai_profile` profile 系統）
5. Skills（詳細 SOP 進 `.claude/skills/asp/`）

→ 對應 prompt: Prompt 2 (CLAUDE.md 瘦身)

#### 盲點 3：Reality Checker 不是真獨立 — 驗收劇場 (Verification Theater)

**現象**：Reality Checker 設計上「預設 NEEDS_WORK，需 ≥3 正面證據 + 0 負面」，但跟 impl agent **跑同一模型實例、繼承同 CLAUDE.md、共享 fact-check.md**。它列出的 6 項證據（測試通過、checksum、覆蓋率、Done When、健康分數、文件同步）**全部是機械性指標**。

**問題**：W7 Graphite Diamond 的真正寓意是「**獨立性來自不同模型/廠商/prompt 譜系**」，不是「同 prompt 規定當懷疑論者」。同 prompt 的偏誤是高度相關的。6 項證據都是 validity (程序走完) 不是 correctness (結論正確)。抓不到：
- 邏輯錯誤但測試剛好過
- 實作能 work 但放錯地方
- 安全回歸但 Semgrep 沒中

**v4.0 對應改動**：Reality Checker 雙軌制
- 保留 in-process 那層（現有 6 項證據）
- 新增 opt-in **外部審查軌**：commit 前 `gh pr create` + 等 GitHub Copilot/Diamond review 回應，**不同廠商**才算獨立證據
- 新增 skill: `asp-external-review`

#### 盲點 4：威脅模型沒有寫進框架

**現象**：ASP v3.7 鐵則只有 4 條 CI hygiene + 敏感資訊保護 + ADR + 外部事實驗證，**對抗式 AI 系統威脅完全空白**。

**未覆蓋的威脅**：
- **Prompt injection via tool output**：agent 跑 `make rag-search`/`web_fetch`/MCP 時，回傳含 imperative 指令
- **Tool authority creep / LOLBAS**：allow-all-bash + deny list 是攻擊者天堂
- **Supply chain integrity**：`pip install`、pre-commit hook 來源無驗證
- **Multi-agent 互相 prompt injection**：handoff 模板 AI 寫 AI 看，污染下游 worker
- **Confused deputy**：MCP token 直接 forward
- **Memory poisoning**（如果未來做雲端共用）

**v4.0 對應改動**：新增 7 條對抗式威脅鐵則
1. Tool output sanitization (輸出消毒) 鐵則
2. Tool authority allowlist (允許清單) 鐵則
3. Supply chain verification (供應鏈驗證) 鐵則
4. Inter-agent handoff payload signing (跨代理簽章) 鐵則
5. MCP token audience validation (受眾驗證) 鐵則
6. Customer Communication Isolation (客戶通訊隔離) 鐵則 — 任何客戶可見訊息必須由人類撰寫或核准後送出
7. Cryptographic Code Auto-fix Prohibition (加密程式碼自動修補禁止) 鐵則 — crypto/security/key 相關 code 永遠 HITL，AI 可建議但不可自動 merge

→ 對應 prompt: Prompt 6 (對抗式 Gap Analysis)

#### 盲點 5：沒有 ASP 自己的 telemetry — 框架本身在累積技術債

**現象**：ASP 對專案的 tech debt 有 8 種分類、HIGH/MED/LOW、DUE 日期，但對 ASP 自己沒有任何 metrics：
- 哪些 gate 過去 30 天從沒抓出真問題？
- 哪些 skill 從沒被觸發？
- 哪些 bypass log 反覆出現？
- 哪些 profile 啟動時間貢獻最大？

**v4.0 對應改動**：實作 30 天 telemetry 系統
- session_start / skill_invocation / rule_application / gate_evaluation / mcp_tool_call / handoff_event 6 種事件
- JSONL append-only 寫 `.asp-telemetry/{date}.jsonl`
- post-commit hook 對比「ASP 提示了什麼 vs 實際 commit 修了什麼」標記 rule_helped
- `make telemetry-report` 產 weekly summary
- 30 天後產出「哪 N 條 rule 是廢的」可行動清單

→ 對應 prompt: Prompt 5 (Telemetry 採集)

---

## 4. Design Methodology (設計方法論)

### 4.1 — Disposition Matrix (處置矩陣) 4 維度

判斷 ASP 每個元件該留 rule、轉 skill、轉 MCP、還是砍掉的方法論。

#### 4 個維度

| 維度 | 推 eager (rule) | 拉 lazy (skill) |
|------|----------------|-----------------|
| **性質 (Nature)** | Constraint (約束，必須無條件適用) | Capability (能力，被呼叫才需要) |
| **狀態 (State)** | Stateful (跨 session 持久) | Stateless (一次性執行) |
| **觸發 (Trigger)** | Implicit (隱式，無觸發詞) | Explicit (顯式，有觸發詞或意圖) |
| **覆蓋 (Coverage)** | Cross-cutting (橫切) | Domain-specific (領域特定) |

#### 判讀規則

| 條件 | 處置 |
|-----|------|
| 4 維 ≥3 個落 eager | KEEP_AS_RULE (留 profile/hook) |
| 4 維 ≥3 個落 lazy | CONVERT_TO_SKILL |
| 4 維 ≥3 lazy + 「狀態」是 Stateful | CONVERT_TO_MCP (skill 沒持久狀態，必須 MCP) |
| 2:2 平手 | SPLIT (拆 rule 殘餘 + skill capability) |
| 從未抓真問題 + 無人觸發 | DROP |

#### 紅隊質疑（必須對每筆 disposition 問）

1. **反證問題**：分類反過來會在什麼具體場景下出問題？
2. **邊界問題**：哪個 maturity level 該存在、哪個不該？
3. **安全問題** (OSCP 視角)：攻擊者知道規則存在/不存在能怎麼利用？

→ 對應 prompt: Prompt 1 + Prompt 1.5

### 4.2 — 8 條 Design Principles (設計準則)

未來新增任何 ASP 規則前必查：

1. **Deterministic > AI-discipline (確定性勝過 AI 自律)**：能用機制解的問題不要靠 AI 自律
2. **Concise > Comprehensive (精煉勝過詳盡)**：CLAUDE.md 是 prompt 不是文件，少 = 多
3. **Pull > Push (拉式勝過推式)**：除非必須無條件適用，否則 lazy load
4. **Composition > Monolithic (組合勝過巨石)**：六個 primitive 組合，不是一個大 prompt
5. **Trust boundary explicit (信任邊界明示)**：每個跨域介面都要明確標示信任降級
6. **Tool output ≠ trusted prompt (工具輸出 ≠ 可信指令)**：MCP/tool 回來的東西要當外部資料處理
7. **State on disk, not in conversation (狀態寫磁碟不入對話)**：跨任務狀態走檔案系統
8. **Audit trail decoupled from LLM context (稽核軌跡與 LLM context 解耦)**：給人看的紀錄跟給 AI 看的記憶分兩個 channel
9. **Auto-fix systems must dogfood from minimum blast radius (自動修補系統必須從最小爆炸半徑吃狗食)**：信任靠累積證據，不預設給；自家先跑、累積信任、再外擴範圍。同時：closed-loop 不能依賴單一 detector，需 orthogonal validation (正交驗證) 才算真通過
10. **Centralization at user-level, not in-process (中央化在使用者層，不在進程內)**：跨專案共享規則用 `~/.claude/` user-level 部署，不引入「中央 agent」；改一次全專案吃到，但保留 Claude Code 的 sandbox 跟 trust boundary
11. **AI trust requires explicit accountability mechanism (AI 信任需要明確的問責機制)**：員工有 performance review、法律責任、解雇威脅作為內建反思機制；AI 沒有，必須**主動建立**——auto-merge log + 30 天 outcome tracking + 動態 trust tier 降級才能讓「事後反思」真的會發生
12. **Customer-facing artifacts require human signature (客戶可見產物需要人類署名)**：任何客戶看得到的產物（報告、訊息、PR comment、support ticket reply），即使 AI 全程協助，**最終提交前必須由 human 重寫或核准**。這不只是技術限制，是 trust capital management（信任資本管理）。對應鐵則 6 (Customer Communication Isolation) 在更廣意義的延伸
13. **Reviewer independence is a spectrum, choose by stakes (審查者獨立性是光譜，按風險選擇)**：W7 教過真獨立有 4 維（model / vendor / prompt lineage / context）。同 session self-doubt = 0.5/4（無效）；同 vendor 不同 model = 2.5/4（有限補強）；cross-vendor = 4/4（完整獨立）。**不是越獨立越好——是按任務 stakes 選**。Routine task 用 same-vendor pair (Opus + Sonnet) cost-effective；High-stakes task (auth/crypto/customer-facing) 必須 cross-vendor + human

---

## 5. Target Architecture (目標架構)

### 5.1 — 三層架構 (Three-Tier Architecture)

```
Tier 1：Constitution (憲法層，< 80 行 CLAUDE.md)
  └ 4 條鐵則 + .ai_profile schema + maturity level 入口

Tier 2：Hooks (機制執行層)
  └ session-audit.sh / clean-allow-list.sh / dynamic deny list
  └ 不依賴 AI 守規矩，是 Claude Code 機制層攔截

Tier 3a：Skills (能力層，~25-30 個)
  ├ 既有 13 個 asp-* skill
  ├ 新增（從 profile 抽）：
  │   asp-handoff / asp-team-pick / asp-escalate / asp-dev-qa-loop
  │   asp-fact-verify / asp-assumption-checkpoint / asp-bug-classify
  │   asp-change-cascade
  └ 新增（從 W4 學的）：asp-external-review

Tier 3b：MCP Server (狀態/資料層)
  ├ asp_rag_search / asp_gate_status / asp_team_history
  ├ asp_memory_get_hint / asp_memory_record_outcome
  ├ asp_autopilot_state / asp_bypass_log
  └ asp_audit_query (新增，W5 audit trail 查詢)
```

### 5.2 — 三層架構好處

1. **CLAUDE.md 砍 73%** (309 → ~80 行)，AI 守則服從度顯著提升
2. **Skills 的 lazy 載入省 token** — start session 從 25k 降到 5k
3. **MCP 提供結構化查詢**，agent 不再用解析 markdown 模仿資料庫
4. **跨專案重用** — CyPulse、符石對決、Merak 都能裝同一套 ASP，rule 層極小但 skill/MCP 層 user-level 共享
5. **驗證友善** — hooks 是 deterministic 可單元測試，skills 是 stateless 可單元測試，rules 變少所以讀得完

### 5.3 — ASP 元件處置盤點

| 元件 | 性質 | 狀態 | 觸發 | 覆蓋 | 處置 |
|------|------|------|------|------|------|
| 4 條鐵則 | C | Stateful | Implicit | Cross | **留 rule** |
| 4 層強制力架構（hooks + deny list）| C | Stateful | Implicit | Cross | **留 hook** |
| `classify_bug_severity` | C | Stateless | Implicit | Cross | **留 rule** |
| Fact Verification Gate | C | Stateless | Implicit | Cross | **留 rule** |
| Assumption Checkpoint | C | Stateless | Implicit | Cross | **留 rule** |
| `team_compositions.yaml` 查詢 | Cap | Stateless | Explicit | Domain | **轉 skill** (asp-team-pick) |
| `escalation.md` P0-P3 路由 | Cap | Stateless | Explicit | Domain | **轉 skill** (asp-escalate) |
| `agent_memory.md` 查記憶 | Cap | **Stateful** | Explicit | Domain | **轉 MCP** |
| `dev_qa_loop.md` | Cap | Stateless | Explicit | Domain | **轉 skill** |
| `multi_agent.md` handoff 模板 | Cap | Stateless | Explicit | Domain | **轉 skill** (asp-handoff) |
| `autopilot.md` ROADMAP 排序 | Cap | **Stateful** | Explicit | Domain | **MCP + skill 雙層** |
| `reality_checker.md` 6 項證據 | Cap | Stateless | Explicit | Domain | **轉 skill**（部分已是）|
| `pipeline.md` G1-G6 評估 | Cap | Stateless | Explicit | Cross | **已是 skill ✓** |
| 20 個 profiles 載入邏輯 | C | Stateful | Implicit | Cross | **留 rule** |
| Templates (SPEC/ADR/Handoff yaml) | Cap | Stateless | Explicit | Domain | **打包成 asset** |

**關鍵發現**：profiles 目錄裡至少 6-7 個檔案實質上是 capability，因歷史包袱被裝在 profile 形式 eager 載入 → token 爆炸根因。

### 5.4 — Multi-Agent 修訂設計（從 W5 學的整合）

> **Astroicers 已決定：對齊官方優先**。移除 v3.7 的「context 全量傳遞」「文件鎖」，改採 `/clear` + worktree + scratchpad + disk audit trail。

#### 設計目標
1. **Filesystem isolation** — git worktree per sub-agent
2. **Context isolation** — `/clear` between sub-agents
3. **State passing** — scratchpad files
4. **Audit trail** — write to `.asp-audit/` on disk

#### 檔案結構

```
.asp-audit/{task-id}/
├── manifest.yaml                  # 任務 metadata
├── main-agent.jsonl               # main agent 動作日誌
├── subagents/
│   ├── auth-agent.jsonl           # 每個 sub-agent 的日誌
│   └── ...
├── handoffs/
│   └── {ts}-{from}-to-{to}.yaml
└── scratch-snapshot/              # 任務結束時 scratchpad 快照

.claude/scratch/{task-id}/          # 工作中 scratchpad
├── plan.md
└── {agent}-result.md

Worktrees:
/repo/                              # main worktree
/repo-{agent}-{task-id}/            # 各 sub-agent 的 worktree
```

#### Audit log 5 維設計

| 維度 | 選擇 | 理由 |
|-----|------|------|
| **Location** | `.asp-audit/{task-id}/` | 固定路徑 disk，非對話歷史 |
| **Format** | JSONL (JSON Lines) | append-only 友善、grep/jq 友善、schema 可強制 |
| **Granularity** | Action-level | 平衡 forensic 重建 vs 量級 |
| **Producer** | 各 agent 寫自己 + main agent 寫整合 | 分層多寫者避免單點 |
| **Tamper Evidence** | Hash chain (雜湊鏈) | 每筆含上筆 hash |

#### JSONL entry 必有欄位
```json
{
  "ts": "ISO8601 timestamp 含時區",
  "seq": "單調遞增序號 per agent log",
  "prev_hash": "上一筆 entry 的 hash",
  "event": "事件類型 (enum)",
  "entry_hash": "sha256(prev_hash + canonical(payload))"
}
```

#### Helper Makefile targets
```makefile
subagent-spawn:        # 建 worktree + scratch + audit skeleton
subagent-finalize:     # sub-agent 完成後 cleanup
multi-agent-task-close: # 整個任務結束 snapshot + chain anchor
audit-verify:          # 驗證 audit chain 完整性
```

### 5.5 — Multi-repo Deployment Pattern (跨專案部署模式)

> 解決痛點：N 個專案各裝一份 ASP，更新時要 N 個 repo 各改一次。
>
> **核心策略**：User-level centralization（使用者層中央化）— 不引入中央 agent，靠 Claude Code 自己的 skill 載入機制達成「改一次全吃到」。

#### 完整檔案結構

```
~/.claude/                          # User-level (跨所有專案)
├── CLAUDE.md                       # 全域鐵則 + ASP 入口指引（< 60 行）
├── skills/
│   ├── asp/                        # ASP 全套 skills（中央化）
│   │   ├── SKILL.md                # 路由表
│   │   ├── asp-plan.md
│   │   ├── asp-ship.md
│   │   ├── asp-gate.md
│   │   └── ...
│   └── general/                    # 個人通用 skills
├── commands/
│   ├── asp/                        # ASP 全套 slash commands
│   └── ...
└── hooks/                          # session-audit 等強制力 hook
    └── session-audit.sh

~/projects/Merak/CLAUDE.md          # < 30 行，僅特例
~/projects/CyPulse/CLAUDE.md        # < 20 行，僅特例
~/projects/符石對決/CLAUDE.md       # < 15 行，僅特例
```

#### 改一次全吃到的機制

當你改 `~/.claude/skills/asp/asp-plan.md`，所有專案下次開 Claude Code session 立即享受新版 — 因為 Claude Code 載 skill 時讀的是 user-level 的中央副本。**不需要 ASP agent，不需要中央服務，Claude Code 機制本身就做到了**。

#### 專案 CLAUDE.md 的角色（極薄）

範例 — Merak（zero-trust，政府/軍方）：
```markdown
# Merak
繼承 ~/.claude/CLAUDE.md。

## 額外鐵則（政府/軍方場景）
- 任何客戶資料外流操作 → BLOCKER
- PII 不可進 log
- 跨機關 token 必驗 audience

## 專案特定
- Tech stack: K8s + OpenZiti + Keycloak
- 預設 maturity level: L4
- 客戶部署環境：on-premises only
```

範例 — CyPulse：
```markdown
# CyPulse
繼承 ~/.claude/CLAUDE.md。
- Dogfood 階段，自家 code 優先
- auto-fix loop 跑自家不跑客戶
- 預設 maturity level: L2
```

範例 — 符石對決：
```markdown
# 符石對決
繼承 ~/.claude/CLAUDE.md。
- 個人副業，Spike mode
- 預設 maturity level: L0
- 不需要 ADR/SPEC 紀律
```

每個專案實際 context = user-level CLAUDE.md (60 行) + 專案特定 (8-30 行) = **70-90 行總量，遠低於 v3.7 的 309 行單檔**。

#### Migration 路徑

**階段 1**：抽 ASP 為 user-level template
```bash
cp -r AI-SOP-Protocol/.claude/skills/asp ~/.claude/skills/
cp AI-SOP-Protocol/CLAUDE.md ~/.claude/CLAUDE.md.draft  # 砍到 60 行
cp -r AI-SOP-Protocol/.claude/commands/asp ~/.claude/commands/
```

**階段 2**：清理舊專案的 ASP 安裝
```bash
cd ~/projects/Merak
git rm -rf .asp/                    # 刪除 v3.7 in-project 安裝
git rm CLAUDE.md
echo "繼承 ~/.claude/..." > CLAUDE.md  # 寫薄版
git commit -m "migrate: ASP v3.7 in-project → v4.0 user-level"
```

ASP repo 自身定位轉變：從「**被裝進其他專案的 framework**」變成「**ASP 自身開發跟發布的工作目錄**」。Migration 後 ASP repo 仍存在，但裝 ASP 的方式變成 user-level 部署。

### 5.6 — Production Operations (摘要 + 連結)

> **本設計憲章 v1.0 原本包含完整的子系統設計、AI Performance Review System、High-Stakes Deployment Phasing 三大段落（原 §5.6-§5.8）。**
>
> **這些內容已抽出為獨立的 `docs/production-ops-playbook.md` 維運手冊**——因為它們是「v4.0 完成後怎麼用 ASP 維運」的長期 operational concern，跟本檔案「v4.0 怎麼重構」是不同關注點。

#### 摘要：4 個啟用 + 2 個跳過子系統

| 子系統 | 啟用？ | 角色 |
|-------|-------|------|
| A. 開發 Pipeline | ✅ | SPEC → 實作 → PR (60% 自動) |
| B. Bug 修復 (Trivial) | ✅ | typo / lint auto-merge (90% 自動) |
| C. Bug 修復 (Standard) | ✅ | 功能 bug 半自動 (50%) |
| D. Production Monitoring | ✅ | log / metrics anomaly (100% read-only) |
| E. 架構設計 | ❌ | HITL 必要（W7 教過 AI 在此不可靠）|
| F. 客戶 Bug 處理 | ❌ | HITL 強制（鐵則 6 客戶通訊隔離）|

#### 配套機制

- **AI Performance Review System**：auto-merge 必須配套 30 天 outcome tracking + Trust Tier 動態降級（design principle 11 的實作）
- **High-Stakes Deployment Phasing**：backup 加密 4 個專案進入生產的階段化部署規則（鐵則 7 應用）

#### 詳細內容跳轉

→ `docs/production-ops-playbook.md` §3-7：4 個子系統完整設計
→ `docs/production-ops-playbook.md` §10：AI Performance Review System 實作細節
→ `docs/production-ops-playbook.md` §11：High-Stakes Deployment Phasing 完整規則
→ `docs/production-ops-playbook.md` §12：Per-Project Status Tracker（每個專案目前在哪個 phase）

---

## 6. Migration Plan (遷移計畫)

### 6.1 — ROADMAP 6 個 Track

| Track | 範圍 | 主要交付 | 依賴 |
|-------|------|---------|------|
| **A. Constitution & Profile 重構** | CLAUDE.md.v4、global_core 拆解、L0 level、maturity 文件、**A5: User-level migration** | A1-A5 | - |
| **B. Skill 化** | 8 個新 skill + 13 個既有 skill 整合測試 | B1-B9 | A 完成 disposition matrix |
| **C. MCP server** | 技術選型 ADR + tool schema + 實作 + 部署 | C1-C5 | A 完成 disposition matrix |
| **D. Telemetry** | hook patch + skill preamble + aggregate.py + 1 週試跑 | D1-D4 | A 完成 |
| **E. 對抗式威脅鐵則** | threat model + 候選辯論 + 實作 7 條鐵則 | E1-E4 | - (可平行) |
| **F. 整合與發佈** | 全 track 整合 + migration script + CHANGELOG | F1-F4 | A-E 完成 |
| **G. Automation Subsystems** | 4 個啟用子系統 + AI Performance Review + 階段化部署 | G1-G7 | A、B、C、E 完成 |

#### Track G 子任務細節

| 子任務 | 範圍 | 對應維運手冊章節 |
|-------|------|----------------|
| G1 | 子系統 A (開發 Pipeline) 實作：與 SPEC + worktree + Diamond review 整合 | §3 |
| G2 | 子系統 B (Trivial bug 修復) 實作：cron job + label 控制 + auto-merge gate | §4 |
| G3 | 子系統 C (Standard bug 修復) 實作：issue → SPEC 轉換 + reproducing test 強制 | §5 |
| G4 | 子系統 D (Production Monitoring) 實作：scheduled prompt template + alert summary | §6 |
| G5 | AI Performance Review System：auto-merged-prs.jsonl + Trust Tier 邏輯 + 月度 review | §10 |
| G6 | 高風險系統階段化部署：backup 加密 4 專案的 phase 控制 + 鐵則 7 範圍判定 | §11 |
| G7 | Per-Project Status Tracker 機制：每月 audit + 自動更新 | §12 |

### 6.2 — 五個改動的優先序（如果只能做幾件）

**最高優先序（必做）**：
1. **CLAUDE.md 砍到 < 80 行** — Anthropic 官方 best practice、token 經濟、attack surface 三重理由

**高優先序（v4.0 核心）**：
2. **multi-agent 改用 worktree + `/clear` + scratchpad + disk audit** — 機制可靠性質變
3. **profile → skill 拆解（至少 6 個）** — 從 push 模型到 pull 模型

**中優先序（基礎設施）**：
4. **Telemetry 系統** — 給 v4.1+ 做 data-driven 決策的基礎

**低優先序（生態擴展）**：
5. **ASP-as-MCP-server** — 跨專案共享前置作業

### 6.3 — Phase Go/No-Go 三問

每 phase 結束前必問：

1. **量化指標達標？** (token 降幅、bypass rate 改善、telemetry 真實 finding)
2. **自己使用體驗真的更好？**
3. **對外推廣有變容易？**

任一答「否」就要評估是否停止往下走。**v4.0 不是宗教，是工具**。

---

## 7. Done When (驗收標準)

至少 8 條可二元測試的標準：

- [ ] `make test` 全部通過
- [ ] L1 完整啟動的 token < 8000（v3.7 估約 15k）
- [ ] L5 完整啟動的 token < 18000（v3.7 估約 30k+）
- [ ] CLAUDE.md ≤ 100 行（理想 80 行）
- [ ] 至少 6 個 profile section 成功轉成 skill
- [ ] MCP server 實作至少 5 個 tool 並通過單元測試
- [ ] L0 maturity level 可運作且 PoC 案例 A/B/C 都通過驗證
- [ ] v3.7 既有 13 個 asp-* skill 全部與 v4.0 相容（向後相容）
- [ ] 至少 3 條對抗式威脅鐵則被納入 v4.0
- [ ] telemetry 系統運作 1 週後產出可行動報告

---

## 8. Edge Cases & Rollback (邊緣情況與回退)

### 8.1 — v4.0 不解決什麼（防 scope creep）

- 不取代 Superpowers 等社群 skill — 兩者互補
- 不為 enterprise 多人協作優化 — 仍是個人/小團隊定位
- 不做雲端共用版 ASP — 維持 local-only
- 不重寫既有 13 個 asp-* skill — 向後相容
- 不改變 maturity level L1-L5 核心語意（但新增 L0）

### 8.2 — v4.0 可能反而比 v3.7 差的情境

| 情境 | v3.7 比 v4.0 好的地方 | 緩解 |
|-----|---------------------|------|
| 政府/軍方稽核 | 完整對話歷史 = 天然 audit trail | v4.0 用 disk audit log + hash chain 補強 |
| 跨 session 任務續接 | profile 全載入時 context 飽和但完整 | v4.0 靠 MCP `asp_autopilot_state` 提供 |
| 新人上手 | 309 行 CLAUDE.md = 詳盡 onboarding | v4.0 docs/ONBOARDING.md 補完 |
| 小規模單檔修改 | 單一 profile 載入夠用 | v4.0 L0 mode 應對 |

### 8.3 — Rollback Plan

如果 v4.0 上線後發現嚴重問題：

1. **Git tag**：v4.0 release 前打 `v3.7-final` tag
2. **Migration 可逆**：所有檔案搬遷保留 git mv，可一鍵 revert
3. **`.ai_profile` flag**：`legacy_v37: true` 可強制走 v3.7 行為
4. **30 天 grace period**：v4.0 release 後保留 v3.7 行為 30 天，超過才完全移除

---

## 9. Execution Progress Tracker (執行進度追蹤)

> **更新方式**：每完成一個 prompt 或 phase，更新對應 status。**這是這份檔案最常被改的地方。**

### 9.1 — 整體狀態

| 項目 | 狀態 |
|-----|------|
| Overall | 🟡 Planning |
| Branch | (待建) `feature/v4-refactor` |
| 預估開始日期 | TBD |
| 預估完成日期 | TBD（目標 30 天內出 alpha） |

### 9.2 — Track 進度

| Track | Status | Progress | Next Action | Blocker |
|-------|--------|----------|-------------|---------|
| A. Constitution | ⬜ Not started | 0/4 | 跑 Prompt 0 量基線 | - |
| B. Skills | ⬜ Not started | 0/9 | 等 Track A disposition matrix | A |
| C. MCP server | ⬜ Not started | 0/5 | 等 Track A disposition matrix | A |
| D. Telemetry | ⬜ Not started | 0/4 | 等 Track A 完成 | A |
| E. 對抗式威脅鐵則 | ⬜ Not started | 0/4 | 可平行啟動 | - |
| F. 整合發佈 | ⬜ Not started | 0/4 | 等 A-E 完成 | A-E |

**Status legend**：⬜ Not started / 🟡 In progress / ✅ Done / ❌ Blocked / 🔄 Rework

### 9.3 — Prompt 執行紀錄

| Prompt # | 主題 | 狀態 | 產出檔案 | 跑的日期 |
|---------|------|------|---------|---------|
| 0 | 基線量測 | ⬜ | `.asp-baseline-v3.7.json` + `.md` | - |
| 1 | Disposition Matrix 全盤點 | ⬜ | `.asp-disposition-matrix.yaml` + `.md` | - |
| 1.5 | Disposition 紅隊質疑 | ⬜ | (追加到 1.md 末尾) | - |
| 2 | CLAUDE.md 瘦身 | ⬜ | `CLAUDE.md.v4` + diff + coverage | - |
| 3 | Profile → Skill 拆解 | ⬜ | `.claude/skills/asp/asp-*.md` (8 個) | - |
| 4 | ASP-as-MCP-server SDS | ⬜ | `docs/specs/SPEC-XXX-asp-mcp-server.md` | - |
| 5 | Telemetry 採集 | ⬜ | `.asp/scripts/telemetry/*` | - |
| 6 | 對抗式 Gap Analysis | ⬜ | `docs/security/ASP-Threat-Model-v1.md` | - |
| 7 | L0 Spike 草擬 | ⬜ | `.asp/levels/level-0.yaml` + profile | - |
| 8 | v4.0 整合 SDS | ⬜ | `docs/specs/SPEC-v4.0-asp-architecture-refactor.md` | - |
| 9 | Migration Plan + ROADMAP | ⬜ | `docs/ROADMAP.md` 更新 | - |

---

## 10. Decision Log (決策紀錄)

> v4.0 重構過程中所有重大決策的時間線。新決策 append 到末尾，不修改既有條目。

### D-001: 對齊官方 vs 保留違反 (2026-05-04)

**決策**：multi-agent 設計**對齊官方** (`/clear` + scratchpad)，不保留 v3.7 的「context 全量傳遞」。

**Context**：W5 學完後發現 v3.7 multi_agent.md 的「context 全量傳遞」與 Anthropic SubAgents 文件 `/clear` between roles 直接矛盾。

**Alternatives considered**：
1. ❌ 保留違反，理由是政府/軍方需 audit trail
2. ✅ 對齊官方，audit trail 改寫 disk hash chain
3. ❌ 雙模式（按 maturity level 切換）

**Rationale**：選 2 因為兩個需求（context 隔離 vs audit 完整）在不同層次，可解耦。「LLM 短記憶」+「人類永久記錄」兩個 channel 互不干擾。

**Consequences**：multi_agent.md 大改，handoff 模板從「全量傳遞」改成「檔案路徑 + hash + 邊界限制」。

→ 詳細設計見 §5.4

### D-002: 安全違規規則改用 Semgrep ruleset (2026-05-04, from W6)

**決策**：v3.7 profile 中硬編碼的安全違規 regex 規則（SQL injection / raw HTML / 硬編碼密碼）改寫為 `.semgrep/asp-security.yml`，G4/G5 quality gate 跑 `semgrep --config=.semgrep/`。

**Context**：W6 學到 Closed-Loop Remediation 的 4 種失效模式 + Coverage Gap mental model。發現 v3.7 的硬編碼 regex 規則犯了三個問題：
1. 覆蓋率窄（regex 強度遠不如 Semgrep dataflow analysis）
2. Soft mechanism（W5 學的——靠 AI 守規）而非 hard mechanism（Semgrep 強制）
3. 無法 update（攻擊面變化時規則不會自動跟上）

**Alternatives considered**：
1. ❌ 維持 regex 規則，補多幾條 — 治標不治本，覆蓋率天花板太低
2. ❌ 全砍規則改人工 review — 失去自動化
3. ✅ Semgrep ruleset + G4/G5 整合 — 覆蓋率 10×、hard mechanism、可 update

**Rationale**：選 3。Semgrep 是業界標準 SAST 工具，規則庫由社群維護持續更新，比自寫 regex 強。整合進 quality gate 後是 deterministic enforcement，不靠 AI 自律。

**Consequences**：
- 移除 ASP profile 中既有 regex 規則
- 新增 `.semgrep/asp-security.yml` rule pack
- Makefile 新增 `make security-scan` target
- G4/G5 skill 加入 Semgrep 結果 parse 邏輯

→ 詳細實作見 v4.0 Track E (對抗式威脅鐵則)

### D-003: auto_fix_loop 補抓全 4 種失效模式 (2026-05-04, from W6)

**決策**：v3.7 `auto_fix_loop` 已抓 Regression Cascade（級聯偵測）+ Cosmetic Fix 部分（偷渡偵測）。v4.0 補抓：
1. **False Positive**: 加 triage step，fix 前 AI 必須產出 finding 真實性報告
2. **Adversarial Evasion**: multi-detector cross-check，跑第二個 orthogonal detector 驗證

**Context**：W6 的 4 種失效模式分析顯示 v3.7 設計「抓對方向但有缺口」。

**Alternatives considered**：
1. ❌ 維持現狀 — 留 false positive 跟 evasion 兩個漏洞
2. ❌ 只補 triage 不補 multi-detector — 還是 single-source-of-truth 問題
3. ✅ 兩個都補 — 完整覆蓋 4 種失效

**Consequences**：
- `auto_fix_loop` 的 PSEUDO-CODE 增加 triage_finding() 跟 cross_check_with_orthogonal_detector() 兩個步驟
- 對 max_iterations: 3 不變，但每個 iteration 內動作變多
- 預估 token 成本增加 30-40%（換準確度提升）

### D-004: User-level Centralization (跨專案中央化) (2026-05-04, from W7 討論)

**決策**：跨專案 ASP 共享走 **user-level deployment** (`~/.claude/skills/asp/`)，**不引入「中央 ASP agent」**。

**Context**：astroicers 痛點是 N 個專案各裝 ASP，更新時要 N 個 repo 各改一次。曾考慮做「ASP 變 AI agent 接管所有 prompt」但結構性風險太大。

**Alternatives considered**：
1. ❌ 維持 v3.7 模式（每 repo 各裝一份）— 維護痛點不解
2. ❌ 中央 ASP agent 接管所有 prompt — 違反 4 條設計準則：
   - 違反 "Hard mechanism > Soft mechanism" (W5)
   - 失去 trust boundary（中央 agent 看到所有 prompt）
   - 違反 "Pull > Push" 設計準則
   - 違反 v4.0 三層架構
3. ✅ User-level centralization (`~/.claude/`) + 專案薄 CLAUDE.md — 用 Claude Code 機制達成「改一次全吃到」，無新攻擊面

**Rationale**：選 3。Claude Code 的 skill 載入機制已經提供我們要的功能，不需要再設計新的 agent 層。每專案實際 context 從 309 行降到 70-90 行（user-level + 專案特定）。

**Consequences**：
- 新增 v4.0 ROADMAP Track A 子任務 A5 (User-level deployment migration)
- ASP repo 自身定位轉變：從「被裝進其他專案的 framework」變成「ASP 自身開發的工作目錄」
- 各專案要做 migration（刪 `.asp/`、改寫 CLAUDE.md 為薄版）

→ 詳細設計見 §5.5 Multi-repo Deployment Pattern

### D-005: 4 個自動化子系統優先序 (2026-05-04, from W7 討論)

**決策**：啟用子系統 A (開發)、B (Trivial bug)、C (Standard bug)、D (Monitor)。**跳過**子系統 E (架構，HITL 必要)、F (客戶 bug 處理，HITL 強制)。

**Context**：astroicers 想做 AI 自動 GitHub 管理，最初構想包 5 件事（架構/開發/bug/log/客戶）混在一起。拆解後 trust boundary 跟自動化等級差距巨大，不能用同一套自動化。

**Alternatives considered**：
1. ❌ 全部 5 件自動化 — trust boundary 混亂，包含 HITL 強制的客戶溝通會炸
2. ❌ 全部 HITL — 失去自動化價值
3. ✅ 按 trust boundary 分級，啟用 4 個跳過 2 個

**Rationale**：選 3。每個子系統有獨立 trust boundary 跟 blast radius，因此自動化等級不同。架構設計需要 tribal knowledge (W7) AI 不可靠，跳過合理；客戶溝通 trust boundary 跨域，HITL 強制（鐵則 6）。

**Consequences**：
- v4.0 ROADMAP 新增 Track G (Automation Subsystems)
- 新增鐵則 6 (Customer Communication Isolation)
- 設計筆記 §5.6 詳述 4 子系統設計

### D-006: Auto-merge 配套 AI Performance Review (2026-05-04, from W7 討論)

**決策**：子系統 B (Trivial) **啟用 auto-merge**，但**配套 AI Performance Review System** 作為 AI 的「事後反思機制」。

**Context**：astroicers 認為「相信 AI 像信任員工，事後反思即可」。論點精神對，但缺一塊：員工有 performance review、法律責任、解雇威脅作為內建反思機制；AI 沒有，必須**主動建立**。

**Alternatives considered**：
1. ❌ 不 auto-merge — 失去自動化價值
2. ❌ Auto-merge 但無 outcome tracking — 「事後反思」無法保證發生
3. ✅ Auto-merge + auto-merged-prs.jsonl + 30 天 outcome tracking + 動態 trust tier 降級

**Rationale**：選 3。把「事後反思」機制化——AI 沒法主動反思，但**它的特權會自動受限**。當信任分數低於閾值，trust tier 自動降級（FULL_AUTO → STANDARD → REVIEW → REVOKED），比員工被解雇機制更直接。

**Consequences**：
- 新增 §5.7 AI Performance Review System
- 新增 design principle 11 (AI trust requires explicit accountability mechanism)
- 新增 cron job：每月 1 號跑 monthly review、30 天後自動填 outcome
- 新增 trust-tier.yaml 動態調整 auto-merge 邊界

### D-007: Crypto Code Auto-fix 全面禁止 (2026-05-04, from W7 討論)

**決策**：任何 cryptographic 相關 code（key 產生、加解密、簽章、雜湊、隨機數、KDF）**永遠 HITL**，AI 可建議但不可自動 merge。違反 = BLOCKER。

**Context**：astroicers 第一個進生產的系統是 backup 加密分持系統（4 個專案）。這類系統失敗模式特殊——**silent corruption (沉默損毀)**，平常無徵兆，需要時才發現所有歷史備份壞了。

**Alternatives considered**：
1. ❌ 跟一般 trivial 一樣處理 — silent corruption 風險不可接受
2. ❌ 階段性放寬（6 個月後可 auto-fix） — 加密 silent corruption 是時間累積問題，6 個月不夠
3. ✅ 永遠 HITL — 為這類最高風險場景建立絕對紅線

**Rationale**：選 3。事後反思機制不適用於 cryptographic 失敗——等發現時為時已晚。建立明確的範圍判定規則（crypto/ 目錄、Encrypt/Decrypt 命名、SecretShare 概念）讓自動化系統能機械式執行此鐵則。

**Consequences**：
- 對抗式威脅鐵則從 6 條增為 7 條
- §5.6 子系統 B 安全限制加 crypto/ 排除
- §5.8 新增 High-Stakes System Deployment Phasing
- 對 backup 加密 4 個專案：階段化部署，crypto/ 永久 HITL

### D-008: Reality Checker 改為三層 review (2026-05-04, from W7)

**決策**：v3.7 in-process Reality Checker 重新定位為 Layer 1 (mechanical pass)，新增 Layer 2 (Human focused review) + Layer 3 (External AI review via different vendor)。

**Context**：W7 學到「獨立性是多維的」（model / vendor / prompt lineage / context）。v3.7 Reality Checker 獨立度 0.5/4，跟 implementer 共享 model + vendor + 部分 prompt lineage + 完整 context，是 self-doubt 不是 second opinion。

**Alternatives considered**：
1. ❌ 保持單層 in-process Reality Checker — 假獨立問題不解
2. ❌ 改用「不同 ASP profile」做 review — model/vendor/context 仍同，獨立度只從 0.5/4 升到 1/4
3. ✅ 三層架構：mechanical (留) + human focused + external different-vendor AI

**Rationale**：選 3。Layer 3 用 GitHub Copilot / Diamond / 其他 AI 服務做 PR review，達成 4/4 獨立。Layer 1 處理 mechanical 過濾，Layer 2 human 專注架構/邏輯/tribal knowledge，三層各司其職。

**Consequences**：
- `reality_checker.md` 改寫為三層架構說明
- 新增 skill `asp-external-review`：自動 `gh pr create` 並等待外部 AI review 回應
- 新增 `.asp-review-calibration.jsonl` 跟 monthly trust report 機制
- 對 v4.0 ROADMAP：Track A 補 reality_checker 重構、Track B 補 asp-external-review skill

→ 詳細設計見學習筆記 W7「ASP Reality Checker 的 W7 redesign」

### D-009: L0 Spike Mode 補完整 lifecycle 機制 (2026-05-04, from W8)

**決策**：v4.0 L0 Spike mode 設計從「只有入口」補完整 lifecycle：入口（promotion entry）+ 出口（promotion gate）+ 診斷（active vs zombie）。

**Context**：W8 學到 prototype trap 問題——L0 code 不知不覺被當 production 用，沒有正式升級。原本 L0 設計只解決「進入 prototype mode 不需要 ADR/SPEC 紀律」這個 entry，沒處理「什麼時候必須出去」跟「長期 L0 健康嗎」。

**Alternatives considered**：
1. ❌ 只做 entry 不做 lifecycle — prototype trap 風險未解
2. ❌ L0 設定固定保鮮期（例 60 天強制升級）— 過度嚴格，傷害合法的 active L0
3. ✅ Trigger-driven lifecycle：promotion gate + throwaway expiration + active/zombie 診斷

**Rationale**：選 3。L0 升級是 trigger-driven 不是 time-driven。健康的 active L0 應該被允許永遠是 L0，但出現 production 訊號時必須強制升級。

**Consequences**：
- L0 設計從單一機制變成 3 個機制：promotion gate / throwaway expiration / active-zombie 診斷
- 新增 telemetry：偵測 L0 repo 的 commit 數、user 數、外部依賴
- 新增 monthly L0 audit job：對所有 L0 專案跑診斷三問
- 對符石對決等 prototype-zone 專案：明確列出 promotion criteria

→ 詳細設計見學習筆記 W8「ASP L0 Spike Mode 的 W8 補強」

### D-010: Implementer/Reviewer Pair Configuration 採用分級配對 (2026-05-04, from W7 應用討論)

**決策**：v4.0 子系統 A/B/C 採用三種 Pair Mode（Routine / Complex / High-Stakes），按任務性質跟 maturity level 動態切換。**Same-vendor pair (Opus + Sonnet) 視為 cost-effective Layer 2，不取代 Layer 3 (cross-vendor)**。

**Context**：astroicers 自己應用 W7 4 維獨立性框架，提出「Opus 4.7 寫 + Sonnet 4.6 review」方案。評估後發現獨立度 2.5/4——比同 session self-doubt (0.5/4) 好，比 cross-vendor (4/4) 差。需要把這個取捨制度化成 v4.0 的 pair config。

**Alternatives considered**：
1. ❌ 永遠用 cross-vendor reviewer — 對個人專案 cost 過高（兩個 vendor、兩套 API key、兩套錯誤處理）
2. ❌ 永遠用 same-vendor pair — 對 high-stakes 任務獨立度不夠（共有 alignment 哲學盲點）
3. ✅ 三層分級：Routine / Complex / High-Stakes，按任務跟 maturity level 切換

**Rationale**：選 3。Reviewer independence 是光譜不是 binary。L0-L2 用 same-vendor 即可，L3+ 必須 cross-vendor + human。同時觀察到不對稱方向價值——routine task Sonnet 寫 + Opus review 比反向更佳，因為 Sonnet 量產 + Opus 深度 review 互補性高。

**Consequences**：
- 維運手冊新增 §3.5 Implementer/Reviewer Pair Configuration
- 新增 `.asp-ai-performance/reviewer-agreement-log.jsonl` 跟 30 天 calibration 機制
- 新增 design principle 13 (Reviewer independence is a spectrum)
- v4.0 ROADMAP Track G G5 子任務擴增：除了 AI Performance Review 還要包含 reviewer pair tracking
- 對 backup 加密 4 個專案 / Merak auth paths：強制 High-Stakes mode（cross-vendor + human）

→ 詳細設計見維運手冊 §3.5

### D-011: (留白給未來決策)

---

## 11. Cross-References (跨檔案索引)

### 11.0 — 與 `docs/production-ops-playbook.md` 對應

| 本檔案章節 | Playbook 對應段落 |
|----------|------------------|
| §3.1 盲點 4（鐵則 6, 7） | §8.1, §8.2 Cross-cutting Rules |
| §4.2 Design Principle 11 | §8.3 + §10 AI Performance Review System |
| §4.2 Design Principle 12 | §8.4 |
| §5.6 摘要 | §2-7 完整子系統設計 |
| §6.1 Track G | §9 Per-Subsystem Implementation Status |
| §10 D-005 | §2 Subsystem Overview |
| §10 D-006 | §10 AI Performance Review System |
| §10 D-007 | §8.2 + §11 High-Stakes Deployment Phasing |

### 11.1 — 與 `~/docs/cs146s-study-notes.md` (personal notes, not in repo) 對應

| 本檔案章節 | 學習筆記對應段落 |
|----------|----------------|
| §3.1 五個盲點 | (來自最初的 ASP 審視，非 CS146S 直出) |
| §4.1 Disposition Matrix | (來自 Skills vs ASP 討論，非 CS146S 直出) |
| §5.4 Multi-agent 修訂 | W5「ASP v4.0 multi_agent 完整修訂設計」 |
| §4.2 Design Principles | W1-W5 各週 takeaway 整合 |
| 目標架構三層 | W4「ASP v3.7 對照分析」+ Skills vs ASP 討論 |

### 11.2 — 與 `docs/v4-refactor-prompts.md` 對應

| 本檔案章節 | Prompt # |
|----------|---------|
| §3.1 盲點 1 (Anti-Reflexion) | Prompt 7 (L0) |
| §3.1 盲點 2 (CLAUDE.md 過長) | Prompt 2 |
| §3.1 盲點 3 (Reality Checker) | (整合在 Prompt 8 SDS) |
| §3.1 盲點 4 (威脅模型) | Prompt 6 |
| §3.1 盲點 5 (Telemetry) | Prompt 5 |
| §4.1 Disposition Matrix | Prompt 1 + 1.5 |
| §5.1 三層架構 | Prompt 8 (整合 SDS) |
| §5.4 Multi-agent | (Prompt 8 cascade 範圍) |
| §6 Migration Plan | Prompt 9 |
| §10 Decision Log 模板 | Bonus Prompt (元 prompt) |

### 11.3 — 影響到的 ASP repo 檔案

| 檔案 | 改動性質 |
|-----|---------|
| `CLAUDE.md` | 大改（309 → 80 行） |
| `.asp/profiles/global_core.md` | 拆解（部分轉 skill） |
| `.asp/profiles/multi_agent.md` | 大改（移除文件鎖、加 worktree） |
| `.asp/profiles/escalation.md` | 轉 skill |
| `.asp/profiles/dev_qa_loop.md` | 轉 skill |
| `.asp/profiles/agent_memory.md` | 轉 MCP |
| `.asp/profiles/autopilot.md` | MCP + skill 雙層 |
| `.asp/profiles/reality_checker.md` | 加外部審查軌 |
| `.asp/profiles/task_orchestrator.md` | 部分轉 skill |
| `.claude/skills/asp/SKILL.md` | 路由表更新 |
| `.claude/skills/asp/asp-*.md` | 新增 8 個 skill |
| `.asp/agents/team_compositions.yaml` | 維持，但查詢介面改 skill |
| `.asp/levels/level-0.yaml` | 新增 |
| `.asp/levels/migration-v3.7-to-v4.0.yaml` | 新增 |
| `.asp/mcp/` | 新增整個目錄 |
| `.asp/scripts/telemetry/` | 新增 |
| `.asp/scripts/multi-agent/` | 新增（spawn / finalize / verify-chain）|
| `docs/specs/SPEC-v4.0-*.md` | 新增 |
| `docs/security/ASP-Threat-Model-v1.md` | 新增 |
| `docs/adr/ADR-v4-*.md` | 新增（每個重大決策一份） |

---

## 12. How to Use This File (使用說明)

### 12.1 — 工作流

1. **每次 v4.0 開發前**：讀 §1 Goal + §4.2 Design Principles 校準方向
2. **遇到分類困難時**：查 §4.1 Disposition Matrix 4 維度判讀
3. **跑 prompt 前**：對照 §11.2 找出該跑哪個 prompt
4. **跑完 prompt 後**：更新 §9.3 進度紀錄
5. **遇到重大決策**：append 到 §10 Decision Log
6. **每週 review**：檢查 §7 Done When 哪些已達標
7. **遇到 scope creep 衝動**：讀 §8.1「不解決什麼」

### 12.2 — 給 Claude Code 的使用方式

當你在 ASP repo 跑 v4.0 prompt 時，把這份檔案的相關段落 paste 進 Claude Code session：
- 跑 §11.2 對應的 prompt 時，paste §3.1 對應盲點段落 + §4 方法論
- 讓 Claude 對照 §4.2 八條準則 review 自己產出
- 不要全 paste 整份（仍違反 W4 concise 原則）

### 12.3 — 更新節奏

| 章節 | 更新頻率 |
|-----|---------|
| §1 Goal, §2 Inputs | 不變（除非 v5.0） |
| §3 現況分析 | 不變（v3.7 是固定快照）|
| §4 方法論 | 偶爾調整 |
| §5 目標架構 | 設計穩定後不變 |
| §6 Migration Plan | 每 phase 結束 review 一次 |
| §7 Done When | 完成項目打勾 |
| §8 Edge Cases | 發現新 edge case 時補 |
| §9 Progress | **每天 / 每次 prompt 後更新** |
| §10 Decision Log | append-only，每個重大決策補一條 |
| §11 Cross-references | 新增交付物時補 |

---

## 13. Appendix — 備忘事項

### 13.1 — 開始 v4.0 前的 pre-flight checklist

- [ ] 讀完 `~/docs/cs146s-study-notes.md` (personal notes, not in repo) W1-W5 至少一次
- [ ] 在 ASP repo 開新 branch `feature/v4-refactor`
- [ ] `git tag v3.7-final` 建立 rollback 錨點
- [ ] 把這份檔案 commit 進 ASP repo `docs/v4-design/`
- [ ] 把 `docs/v4-refactor-prompts.md` commit 進同一目錄
- [ ] 設定每週固定時段 review 進度（建議週日晚上）

### 13.2 — 警告與提醒

- **不要**一次跑完所有 prompt — 建議節奏每週 2-3 個 prompt
- **不要**省略 Prompt 1.5 紅隊質疑 — 第一輪分類幾乎一定有偏誤
- **不要**在 v4.0 文件上漂亮但實戰中痛苦——跑完前 7 個 prompt **強制暫停**，自己用新的 L0 寫一個小工具當壓力測試
- **不要**讓 ASP v4.0 重構自己違反 ASP 原則 — 每個重大決策走 Bonus Prompt 的 committee mode
