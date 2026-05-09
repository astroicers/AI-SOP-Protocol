# ASP v4.0 改進 Prompt Pack

> 給 astroicers 用，配合 AI-SOP-Protocol v3.7 → v4.0 重構。
> 全部 prompt 設計為**直接貼進你 ASP repo 的 Claude Code session** 使用。
> 順序執行、每個 prompt 輸出都餵給下一個 prompt 當輸入。

---

## 使用方式

1. 在你 ASP repo 根目錄開新 Claude Code session
2. **第一步永遠是 Prompt 0**（基線量測），不要跳過
3. Prompt 1-7 可以平行或依序，但 Prompt 8 必須等前面全部完成
4. 每個 prompt 之間建議 `/clear` 一次，避免 context 污染
5. 所有產物建議 commit 到 `feature/v4-refactor` 分支，不要直接動 master

**Anti-patterns（這些動作會讓 prompt 失效）：**
- 不要在 prompt 裡加「請」「謝謝」這種客套——你要的是工程產出，不是對話
- 不要省略 `.ai_profile` 設定的描述，Claude Code 會根據它推斷邊界
- 不要相信第一次的 disposition 決策，每個關鍵 prompt 後面都接「紅隊質疑」prompt

---

## Prompt 0 — 基線量測（先跑，不要跳）

```
你正在我的 AI-SOP-Protocol (ASP) v3.7.0 專案根目錄。

任務：產出 v4.0 重構前的量化基線，輸出到 .asp-baseline-v3.7.json。

需要量測的維度：

1. 規模指標
   - CLAUDE.md 行數與 token 估算（用 1 token ≈ 1.3 char for zh）
   - .asp/profiles/ 每個 .md 的行數與 token
   - .claude/skills/asp/ 每個 skill 的行數與 token
   - .asp/agents/ 每個 yaml 的行數
   - .asp/templates/ 與 .asp/levels/ 的數量
   - L5 完整載入（global_core + system_dev + 所有選配 + multi_agent + autopilot 全套）的累計 token

2. 結構指標
   - 每個 profile 在 CLAUDE.md「Profile 對應表」中的觸發條件
   - 每個 profile 的 requires/optional/conflicts（從 yaml 註解抽）
   - 每個 skill 的 description trigger 詞數量
   - hook 腳本數量與 SLOC

3. 規則密度
   - CLAUDE.md 中「必須」「禁止」「不可」「鐵則」「BLOCKER」字樣出現次數
   - global_core.md 同上
   - 全 profile 中 PSEUDO-CODE FUNCTION 定義的數量

4. 重複性偵測（這個最重要）
   - 在所有 profiles 中，找出語義相同但寫在不同檔案的規則
     範例：「修改前必須確認 SPEC 存在」可能同時出現在 global_core / system_dev / autonomous_dev
   - 用 grep + 人工判讀，不要用 LLM 模糊匹配
   - 至少列出 10 條疑似重複，附完整檔名:行號

5. Bypass log 與 gate state
   - .asp-bypass-log（如果存在）的內容統計：哪個 skill 被 bypass 最多次
   - .asp-gate-state.json（如果存在）每個 gate 通過/失敗次數

輸出格式：JSON，根節點包含 measured_at（ISO8601）、metrics、findings 三個 section。
findings 用人話寫 5-10 條觀察，例如「task_orchestrator.md 是最大檔（1379 行），佔總 profile token 的 X%」。

不要做任何優化建議，只測量。建議在最後另外輸出一份 .asp-baseline-v3.7.md 摘要供我閱讀。
```

---

## Prompt 1 — Disposition Matrix 全盤點

```
基於 .asp-baseline-v3.7.json，對 ASP 每個元件套用 4 維度 disposition matrix。

維度定義：

| 維度 | 推 eager（rule） | 拉 lazy（skill）|
|------|----------------|-----------------|
| 性質 | Constraint（必須無條件適用，沒有觸發詞） | Capability（被呼叫才需要） |
| 狀態 | Stateful（跨 session 持久） | Stateless（一次性執行） |
| 觸發 | Implicit（無觸發詞，AI 必須主動套用） | Explicit（有自然語言觸發詞） |
| 覆蓋 | Cross-cutting（影響所有任務類型） | Domain-specific（特定情境） |

判讀規則：
- 4 維 ≥3 個落 eager → KEEP_AS_RULE（留 profile 或 hook）
- 4 維 ≥3 個落 lazy → CONVERT_TO_SKILL
- 4 維 ≥3 個 lazy 但其中「狀態」是 Stateful → CONVERT_TO_MCP（不是 skill，因為 skill 沒有持久狀態）
- 2:2 → SPLIT（拆出 rule 殘餘 + skill capability）

要分類的元件清單（逐個處理，不要省）：

A. CLAUDE.md 內每個 section（不只是檔案層級，要切到 section）：
   - 鐵則表（4 條）
   - 強制力架構（4 層）
   - 預設行為表（黃色項）
   - Maturity Levels 描述
   - Makefile 速查
   - 技術執行層 hooks 說明

B. .asp/profiles/ 全部 19 個：
   global_core, system_dev, content_creative, multi_agent, committee,
   vibe_coding, rag_context, guardrail, design_dev, coding_style, openapi,
   frontend_quality, autonomous_dev, autopilot, task_orchestrator,
   escalation, reality_checker, agent_memory, dev_qa_loop, pipeline

C. global_core.md 內每個 section（這個最重要，必須切細）：
   - 溝通規範
   - 工作目錄紀律
   - Fact Verification Gate
   - 破壞性操作防護
   - 迴歸預防協議
   - Postmortem 觸發條件
   - 需求變更回溯協議（L1-L4）
   - 文件原子化（正向/反向/雙向追溯）
   - Tech Debt 標準格式
   - DEPRECATED 追蹤
   - Token 節約
   - Assumption Checkpoint Protocol

D. .claude/skills/asp/ 已是 skill 的 13 個（驗證它們是否真的該是 skill）

E. .asp/hooks/ 全部 hook

輸出：
1. .asp-disposition-matrix.yaml — 結構化資料
2. .asp-disposition-matrix.md — 給人類看的表格 + 每筆理由（一句話）

每筆紀錄格式：
```yaml
- id: global_core.fact_verification_gate
  current_location: .asp/profiles/global_core.md (lines X-Y)
  size: { lines: N, tokens: ~M }
  dimensions:
    nature: Constraint  # Constraint | Capability
    state: Stateless     # Stateful | Stateless
    trigger: Implicit    # Implicit | Explicit
    coverage: Cross      # Cross | Domain
  disposition: KEEP_AS_RULE  # KEEP_AS_RULE | CONVERT_TO_SKILL | CONVERT_TO_MCP | SPLIT | DROP
  rationale: "外部事實查證沒有自然語言觸發詞，必須在 G1 前無條件執行"
  v4_destination: .asp/profiles/global_core_minimal.md
  estimated_token_savings: 0
```

特別要小心的判讀陷阱：
- 「看起來是 capability」但實際是 rule：例如 classify_bug_severity() 看起來是函數，但它必須在每次 bug 修復時自動套用，沒有觸發詞 → KEEP_AS_RULE
- 「看起來是 rule」但實際是 capability：例如 documentation_pipeline 內的 README 自動產生邏輯，它需要明確被呼叫 → CONVERT_TO_SKILL
- Stateful + Lazy 一定走 MCP，不要勉強塞 skill：agent_memory、autopilot_state、bypass_log 都是這類

對每個 disposition 決策，加一條 「red_team_question」：「這個分類錯了會發生什麼？」並回答。
```

---

## Prompt 1.5 — Disposition 紅隊質疑（強制要跑）

```
你剛才產出的 .asp-disposition-matrix.yaml，現在用紅隊視角質疑你自己。

對每筆 disposition，回答 3 個問題：

1. 反證問題：如果我把 disposition 反過來（rule ↔ skill），會在什麼具體場景下出問題？
   - 給出最壞情況的 attack scenario 或 user friction scenario
   - 不能只說「會增加 token」，要給具體 workflow

2. 邊界問題：這條規則/能力在哪個 maturity level 應該存在、哪個不該？
   - L0/L1 該不該有？L5 才有意義？
   - 是否應該按 level 漸進啟用？

3. 安全問題（你 OSCP 視角必問）：
   - 如果攻擊者知道這條規則的存在/不存在，能怎麼利用？
   - 例：「fact verification gate 是 rule」→ 攻擊者可以污染 fact-check.md 來繞過
   - 例：「agent_memory 是 MCP」→ 攻擊者可以投毒 memory entries 影響後續 agent 決策

把這份質疑追加到 .asp-disposition-matrix.md 末尾的「紅隊質疑」section，至少 15 條。
然後標出 3 條「我之前的判讀其實錯了」並提出修正後的 disposition。

不允許說「全部判讀都是對的」，不論你多有信心，至少要找出 3 個值得重新考慮的。
```

---

## Prompt 2 — CLAUDE.md 瘦身重寫

```
基於 .asp-disposition-matrix.yaml，重寫 CLAUDE.md 為 v4.0 版本。

硬性目標：
- 總行數 ≤ 100 行（含註解與空行）
- token 估算 ≤ 2500
- 鐵則 + 強制力 + 啟動程序 + .ai_profile schema + Maturity level 入口 + Makefile 速查連結

必須砍掉/搬走的內容：
- Profile 對應表 → 搬到 .asp/levels/ 與 .ai_profile_schema.yaml
- Makefile 速查全表 → 改為「執行 make help」一行
- 預設行為黃色項 → 拆到 global_core.md
- Maturity Levels 詳細描述 → .asp/levels/README.md
- 技術執行層詳細說明 → .asp/hooks/README.md

必須保留的內容：
- 4 條鐵則（一條一行，不要展開描述）
- 啟動程序（≤ 6 個 step）
- 4 層強制力架構表（4 行 markdown table）
- 「無 .ai_profile 時的行為」一條
- 連結到其他文件的索引

輸出：
1. CLAUDE.md.v4 — 新版本
2. CLAUDE.md.diff — 跟現在 v3.7 的 diff，並標註每段話搬到哪裡（target_file: ...）
3. CLAUDE.md.coverage_check.md — 證明你沒漏掉任何 v3.7 的功能：列出原版每個 section 的去處

驗證標準：
- 我把 v4.0 CLAUDE.md 給一個從沒看過 ASP 的工程師，他應該能在 5 分鐘內看完並啟動專案
- v3.7 的所有功能都還能運作（即使搬到別的檔案）
- 沒有「為了砍而砍」——保留的東西必須證明 token cost 值得

特別注意：
- 「外部事實驗證閘」「Assumption Checkpoint」這兩個我之前認為應該留 rule，但你應該獨立判斷它們是不是其實該抽成 skill 觸發
- 不要刪掉「無 .ai_profile 時詢問使用者專案類型」這條 fallback
```

---

## Prompt 3 — Profile → Skill 拆解器

```
對 .asp-disposition-matrix.yaml 中所有 disposition == CONVERT_TO_SKILL 的元件，
產出對應的 Claude Code skill。

每個 skill 必須包含：

1. YAML frontmatter（嚴格遵循 Claude Code skill 規範）：
   - name: kebab-case，前綴 asp-
   - description: 前 80 字必須包含中英雙語觸發詞
   - 列出 trigger 詞至少 8 個，繁中 + 英文 + 同義詞

2. 第一層 H1：skill 名稱
3. 「何時觸發」section：明確列出觸發場景
4. 「執行步驟」section：操作邏輯，可以引用 .asp/templates/ 或 .asp/agents/
5. 「不要觸發」section：避免 false positive 的條件
6. 「下一步建議」section（接 SKILL.md 的下一步路由表規範）

對於從 multi-page profile 拆出的 skill：
- 必須將原 profile 中的 PSEUDO-CODE FUNCTION 完整保留（不要簡化）
- 但移除「設計原則」「與其他 Profile 的關係」這類 meta-commentary
- 將「繞過藉口與反駁」表格搬到 skill 末尾的「常見反例」section

要產出的 skill 清單（基於我之前討論的方向，但你要根據 disposition matrix 自己決定最終列表）：
- asp-handoff（從 multi_agent.md 抽）
- asp-team-pick（從 task_orchestrator.md 的 recommend_team 抽）
- asp-escalate（從 escalation.md 抽）
- asp-dev-qa-loop（從 dev_qa_loop.md 抽）
- asp-fact-verify（從 global_core.md 的 Fact Verification Gate 抽）
- asp-assumption-checkpoint（從 global_core.md 抽）
- asp-bug-classify（從 global_core.md 的 classify_bug_severity 抽）
- asp-change-cascade（從 global_core.md 的 L1-L4 需求變更回溯協議抽）
- 其他 disposition matrix 認定該轉的

每個新 skill 輸出到 .claude/skills/asp/asp-XXX.md，並更新 .claude/skills/asp/SKILL.md 的路由表。

關鍵驗證：每個 skill 必須通過「沒有 ASP profile 也能獨立運作」測試。
也就是說，把 skill 給一個沒裝 ASP 的專案用，它仍然可以執行（即使部分 reference 失效）。
這是判斷是否真的成功從 rule 解耦的標準。

對於做不到獨立運作的 skill，標記 requires_asp_context: true 並列出依賴的 profile/template。
這些是 v4.0 還沒拆乾淨的部分，要在最後輸出 .asp-skill-coupling.md 列出。
```

---

## Prompt 4 — ASP-as-MCP-Server SDS

```
為 ASP v4.0 設計一個 MCP server，把所有 stateful + lazy 的能力轉成結構化 tool。

設計要求參考 modelcontextprotocol.io 規範與 CS146S Week 3 的 MCP server 最佳實踐。

要暴露的 tool（基於 disposition matrix 中所有 CONVERT_TO_MCP 元件）：

1. 知識查詢類
   - asp_rag_search(query: str, scope: str) — 取代 make rag-search
   - asp_team_history(scenario: str) — 查 team_compositions 過去成功率
   - asp_memory_get_hint(task_pattern: str, domain: str) — 從 .asp-agent-memory.yaml 取出修復策略

2. 狀態查詢類
   - asp_gate_status() — 回傳當前 G1-G6 狀態
   - asp_autopilot_state() — 取代 make autopilot-status
   - asp_bypass_log(since: ISO8601) — 取代 make asp-bypass-review
   - asp_health_audit(quick: bool) — 取代 make audit-health / audit-quick

3. 寫入類（受嚴格權限控制）
   - asp_memory_record_outcome(strategy_id, outcome, evidence)
   - asp_bypass_record(skill, reason)
   - asp_handoff_create(type, from_agent, to_agent, payload)

不要做的：
- 不要把 SPEC/ADR 撰寫做成 MCP tool — 這些是 capability，留 skill
- 不要做 git/test/build 的 wrapper — 這些是 hook 或 Makefile 該做的事
- 不要把鐵則做成 tool — rule 必須是 push 模型

輸出規格（一份完整 SDS）：

1. 架構圖：MCP server 在 ASP 中的位置（與 hook、profile、skill 的分工）
2. Tool schema：每個 tool 的完整 JSON schema（input/output/errors）
3. 部署模式：local STDIO（給 Claude Code 用）+ optional remote HTTP（給 CI 用）
4. 認證模型：
   - local：信任 process boundary
   - remote：API key from .asp/secrets.env，記得 audience 驗證
5. 速率限制：定義每個 tool 的 timeout 與 max calls per minute
6. 錯誤模型：HTTP failure / timeout / empty result / permission denied 的標準回應格式
7. 觀測性：每個 tool call 必須寫入 .asp-mcp-trace.jsonl（用於 telemetry）
8. 測試策略：每個 tool 至少 1 個 happy path + 1 個 error path 的單元測試

實作技術選擇：請評估以下三個方案並給結論：
A. Python + fastmcp（與現有 .asp/scripts/rag/ 相容性最高）
B. Rust + 自製 STDIO loop（呼應你 ZRust 的技術棧偏好）
C. Node.js + @modelcontextprotocol/sdk（生態最成熟）

加分項：
- 設計 `.asp/mcp/` 目錄結構
- 列出與「ASP 鐵則」的衝突點：例如 asp_bypass_record 寫入時會不會繞過動態 deny list
- 列出 prompt injection 攻擊面：如果攻擊者污染 .asp-agent-memory.yaml，asp_memory_get_hint 回傳的 hint 會不會直接被 worker agent 信任執行

輸出檔案：docs/specs/SPEC-XXX-asp-mcp-server.md（用你的 SPEC_Template.md 格式）
與 ADR-XXX-asp-mcp-server-tech-stack.md（記錄 A/B/C 選擇理由）。
```

---

## Prompt 5 — Telemetry 埋設與量測腳本

```
為 ASP v4.0 設計 30 天 telemetry 採集系統，用於驗證 v3.7 → v4.0 的實際效益。

採集點：

1. session_start：
   - timestamp
   - .ai_profile 內容快照
   - 載入的 profile/skill 列表
   - 估算載入 token
   - 觸發的 hook 列表

2. skill_invocation：
   - skill name
   - 觸發詞（trigger 字串）
   - 觸發來源：使用者輸入 / 主動建議 / 強制 gate
   - 執行 token 消耗
   - 執行結果：success / failure / bypassed
   - 完成後是否被使用者 reject / undo

3. rule_application：
   - rule id（例如 global_core.fact_verification_gate）
   - 觸發場景（implicit 觸發）
   - 是否 caught 真實問題（需要 AI 自我標記，並在 follow-up 確認）
   - 是否被 bypass

4. gate_evaluation（G1-G6 + G5.5 + G6.5）：
   - gate id
   - status: PASS / FAIL / BLOCKED
   - 抓到的 finding 數量與類型
   - 重試次數

5. mcp_tool_call：
   - tool name
   - latency
   - input/output size
   - error code if any

6. handoff_event（multi-agent）：
   - handoff type
   - from_agent / to_agent
   - context size

輸出格式：JSONL，每行一個事件，寫入 .asp-telemetry/{YYYY-MM-DD}.jsonl

實作：

1. 修改 .asp/hooks/session-audit.sh：start 時寫一筆 session_start 事件
2. 為每個 .claude/skills/asp/asp-*.md 加入 telemetry preamble（在 「執行步驟」section 之前），要求 AI 在執行前/後各寫一筆事件
3. 建立 .asp/scripts/telemetry/aggregate.py：
   - 讀取所有 telemetry/*.jsonl
   - 產出 weekly report：
     - 哪些 skill 從未被觸發（候選砍掉）
     - 哪些 skill 觸發但成功率 < 50%（候選改進）
     - 哪些 rule 從未抓到真問題（候選降級）
     - 哪些 gate 從未失敗（候選簡化）
     - token 消耗趨勢
4. 建立 make telemetry-report — 一鍵產 weekly summary

關鍵設計：
- AI 要怎麼判斷「rule 是否 caught 真實問題」？
  → 不要讓 AI 自己判斷。在使用者 commit 後，跑 post-commit hook 比對：
    這次 commit 修了什麼 → ASP 在過程中提示了什麼 → 對應上即為 "rule_helped"
  → 沒對應上的 rule application 都標 "rule_unverified"
- telemetry 本身不能影響 ASP 正常運作 — 全部寫操作都在 background，失敗 silent
- 隱私：telemetry 是 local-only，不上傳，加入 .gitignore

輸出檔案：
- .asp/scripts/telemetry/aggregate.py
- .asp/scripts/telemetry/post-commit-hook.sh
- .asp/scripts/telemetry/README.md（解釋怎麼讀 weekly report）
- 修改 .asp/hooks/session-audit.sh 的 patch
- 修改 13 個 asp-* skill 的 patch（加 telemetry preamble）
- 對 Makefile 的 patch（新增 telemetry-* targets）

驗證標準：
- 跑 1 週後，aggregate.py 產出的報告至少包含 30 個事件
- 我能從報告看出「哪 3 個 rule 是廢的」這類具體可行動的結論
```

---

## Prompt 6 — 對抗式 AI 系統 Gap Analysis

```
背景：我是 OSCP + ASP 框架開發者，需要把對抗式 AI 系統威脅模型納入 v4.0 鐵則。

ASP v3.7 的鐵則是 4 條 CI hygiene + 敏感資訊保護 + ADR + 外部事實驗證。
這對 zero-trust 政府/軍方場景的「軟體工程紀律」夠用，但對「對抗式 AI 系統」威脅模型完全空白。

任務：產出一份完整的 Gap Analysis，並提出 v4.0 的「對抗式威脅鐵則」候選清單。

威脅維度：

A. Prompt Injection via Tool Output
   - Agent 跑 web_fetch / rag_search / 第三方 MCP，回傳內容含 imperative-mood 指令
   - Agent 從 .asp-agent-memory.yaml 取 hint，hint 被人投毒
   - Agent 讀 SPEC.md / ADR.md，內容被污染（攻擊者透過 PR 注入）
   - Multi-agent handoff payload 被污染，下游 agent 信任上游輸出

B. Tool Authority Creep / LOLBAS
   - ASP 是 allow-all-bash + deny-list 模型 → 攻擊者天堂
   - curl | bash / python -c / git config core.fsmonitor / make 任意 target
   - 子進程逃逸：agent 起 subprocess，subprocess 不受 ASP 約束
   - MCP tool 的 permission scope creep

C. Supply Chain Integrity
   - pip install / npm install / cargo install 過程零防護
   - pre-commit hook 來源驗證
   - .asp/scripts/install.sh curl bash 安裝 ASP 本身就是反例（自己違反原則）
   - .claude/settings.json 被污染

D. Multi-Agent Cross-Contamination
   - Worker A 被攻擊後產出污染的 handoff，Worker B 信任 handoff 執行
   - Reality Checker 跟 impl 共享 CLAUDE.md → 不是真的獨立
   - Agent memory 跨 session 污染累積
   - Committee mode 的「多角色辯論」實際是同一個模型在自言自語

E. Confused Deputy
   - ASP 的 escalate(P0) 通知人類，但通知內容由 AI 撰寫
   - 動態 deny list 由 session-audit.sh 注入，攻擊者修改 .asp-session-briefing.json
   - asp_memory_record_outcome 寫入 hint，下次 AI 信任這個 hint

F. Sandbox Escape
   - autonomous_dev 的「精確邊界」邊界本身由 AI 解讀，AI 可以放寬解讀
   - SPEC scope 外的修改被 rationalize 成 scope 內

G. Customer Communication Compromise (客戶通訊妥協)
   - AI 直接送出客戶可見訊息但內容被 prompt injection 污染
   - 客戶 ticket 系統的 reply 被 AI 自動生成，未經人類核准
   - PR comment 上 AI 對外回應引發信任崩潰
   - 客戶看到 hallucinated 的「我們已經修好了」但實際未修

H. Cryptographic Silent Corruption (加密沉默損毀)
   - AI 自動修補 crypto code 引入數學錯誤（key 產生、簽章、KDF）
   - Backup 加密分片產生時錯誤，平常無徵兆
   - 災難復原時才發現所有歷史備份壞掉
   - Auto-fix 的 reflexion loop 對 silent corruption 失效（沒有立即 feedback signal）

對每個維度：

1. 列出 ASP v3.7 對應的現有規則（如果有）
2. 評估該規則的有效性（從攻擊者視角）
3. 提出 v4.0 應該補的鐵則或機制
4. 標記 cost：人類 friction、token 消耗、實作難度
5. 標記 priority：P0 (must) / P1 (should) / P2 (nice)

輸出：

1. docs/security/ASP-Threat-Model-v1.md
2. docs/security/ASP-v4-Adversarial-Rules-Candidates.md
   - 至少 12 條候選新鐵則或機制
   - 每條附 attack scenario + mitigation + 與 v3.7 規則的關係
3. docs/security/ASP-Adversarial-Case-Studies.md
   - 把 ASP 作為「AI dev framework 的安全 case study」
   - 至少 5 個內部教學/分享素材的 ASP 攻擊面案例

最後一個 section：「如果我是攻擊者，我會怎麼攻擊 ASP 本身？」
不要客氣。寫一份至少 8 步的 attack chain，從 reconnaissance（公開 GitHub repo 已經洩漏 .asp/profiles/）到完全控制使用者的 git push。

寫完後問自己：v4.0 應該預設啟用幾條對抗式威脅鐵則？

**已知方向**（基於 CS146S W3/W6/W7/W8 學習 + 設計筆記 §3.1 盲點 4 已固化）：v4.0 必須包含至少這 7 條：
1. Tool output sanitization (輸出消毒)
2. Tool authority allowlist (允許清單)
3. Supply chain verification (供應鏈驗證)
4. Inter-agent handoff payload signing (跨代理簽章)
5. MCP token audience validation (受眾驗證)
6. **Customer Communication Isolation (客戶通訊隔離)** — 對應 G
7. **Cryptographic Code Auto-fix Prohibition (加密自動修補禁止)** — 對應 H

請對這 7 條提出補強建議或新增其他候選。預設每一條都被質疑「真的需要嗎？」要說服自己。
```

---

## Prompt 7 — ASP-Lite (L0) 草擬

```
為 ASP 設計一個 L0 (Spike) maturity level，目標：

讓 PoC、紅隊工具、安全研究、demo、一次性實驗等 探索性開發 能用 ASP 但不被 ASP 拖累。

硬性目標：
- CLAUDE.md 加 L0 後仍 ≤ 100 行
- L0 啟用時的總載入 token < 1500
- 鐵則只剩 3 條（從 v3.7 的 4 條再砍）
- 沒有 ADR / SPEC 強制要求
- 沒有 G1-G6 gate
- 但保留 4 層強制力架構的 L1（session_audit briefing）與基本敏感資訊保護

要保留的：
- 「git push 前列出變更摘要」（這是 anti-data-loss，無條件必須）
- 「敏感資訊保護」（API key 不可洩漏）
- 「外部事實驗證」（這個你要決定 L0 還要不要 — 我的初判是「弱化版：明確標注訓練資料來源即可，不強制查證」）

要砍掉的：
- ADR 鐵則（L0 沒有架構決策概念）
- 文件原子化要求
- TDD 預設行為
- Assumption Checkpoint（探索性開發本來就是試錯）
- Multi-agent / autopilot / committee
- 大部分 profile

要新增的（L0 特有）：
- 「實驗銷毀紀律」：L0 開發產物如果要進 production，必須先升級到 L1 並補 SPEC + ADR
- 「Spike timebox」：L0 預設工作時段是有限的（建議 3 天），超過必須評估升 L1 還是丟棄
- 「不可從 L0 直接 commit 到 master」：強制 commit 到 spike/* branch

**W8 補強的 3 個 lifecycle 機制（必須納入設計）**：

1. **Promotion Gate (晉升閘)** — 明確 trigger 條件強制升 L1+：
   - 第一個非你之外的使用者出現 → 強制評估升 L1
   - 處理任何真實 PII / 金流 → 強制升 L2 以上
   - 跑超過 60 天 → 強制 audit 是否該升級

2. **Throwaway Expiration (用完即丟期限)** — L0 code 應有保鮮期：
   - 超過 timebox 還沒升級 → force decision (升級或刪除)
   - 不准放著腐爛變 zombie code

3. **Active L0 vs Zombie L0 區分** — 長期 L0 不一定是 trap：
   - Active：還在用 / 改起來容易 / 失去會難過 → 健康，繼續 L0
   - Zombie：忘了怎麼運作 / 改一處 30 分鐘 / 偶爾出 bug 浪費半天 → 升級或刪除
   - 自我診斷 3 問：5 分鐘讀完能講清楚？/ 過去 30 天因它浪費 >1 小時？/ 失去它會難過？

設計這 3 個機制要有：
- 偵測機制（Promotion Gate 怎麼自動觸發？telemetry 抓 user 數變化）
- Force decision UI（Throwaway expiration 到了怎麼跳出選項給使用者）
- 月度 audit job（對所有 L0 專案跑診斷三問）

輸出：

1. .asp/levels/level-0.yaml（用既有 level-1.yaml 結構，含 lifecycle 機制配置）
2. .asp/profiles/level0_minimal.md（單一 profile，含上述精簡規則）
3. CLAUDE.md 的 patch：在 Maturity Levels 表格加一行 L0
4. docs/level0-spike-mode.md：使用情境 + 從 L0 升 L1 的流程 + lifecycle 3 機制詳述
5. .asp/templates/example-profile-spike.yaml：典型 .ai_profile 配置範例
6. .asp/scripts/l0-audit.sh：月度 L0 audit job（自我診斷 3 問）

驗證情境：

設想以下三個你的真實使用案例，驗證 L0 是否真的好用：

A. 你要快速驗證 nuclei template 在新 CVE 上的命中率（半天工作）
B. 你要為內部教學做一個 PoC：示範 prompt injection 攻擊 multi-agent
C. 你要評估某個新的 MCP server 是否值得整合進 Merak
D. **你的符石對決卡牌遊戲**（W8 教過：唯一還在 prototype zone 的專案）— L0 何時自動觸發 promotion 評估？

每個案例：
- 描述 .ai_profile 該怎麼設
- 描述 ASP 在過程中該介入幾次
- 對比 L4 / L5 設定下會多出多少 friction
- 描述 Promotion Gate 在這個案例會怎麼觸發

如果發現 L0 還是太重 → 提出 L0-Lite 子變體。
如果發現 L0 跟 L1 差異不夠大 → 重新評估邊界。
```

---

## Prompt 8 — v4.0 整合 SDS

```
基於前 7 個 prompt 的全部輸出（baseline + matrix + redteam + CLAUDE.md.v4 + skill 包 + MCP SDS + telemetry + threat model + L0），
產出 ASP v4.0 的完整 SDS。

輸出檔案：docs/specs/SPEC-v4.0-asp-architecture-refactor.md
用你既有 SPEC_Template.md 格式，加上以下強制 section：

1. Goal — 用 30 字以內描述 v4.0 跟 v3.7 的本質差別
2. Inputs — 7 份前置交付物的引用清單
3. Architecture — 三層架構圖（Constitution / Hooks / Skills+MCP）
4. Migration Plan — 從 v3.7 到 v4.0 的 phase gate（至少 4 個 phase）
5. Cross-Component Invariants — v4.0 各層之間的契約（這是你 G5.5 自己加的，現在輪到你自己遵守）
6. Done When — 至少 8 條可二元測試的驗收標準
7. Edge Cases — 至少 5 個 v4.0 可能反而比 v3.7 差的情境
8. Rollback Plan — 如果 v4.0 上線後發現嚴重問題，怎麼回退

Done When 的範例（你必須產出比這更具體的）：
- [ ] make test 全部通過
- [ ] L1 完整啟動的 token < 8000（v3.7 估約 15k）
- [ ] L5 完整啟動的 token < 18000（v3.7 估約 30k+）
- [ ] CLAUDE.md ≤ 100 行
- [ ] 至少 6 個 profile section 成功轉成 skill
- [ ] MCP server 實作至少 5 個 tool 並通過單元測試
- [ ] L0 maturity level 可運作且 PoC 案例 A/B/C 都通過驗證
- [ ] v3.7 既有 13 個 asp-* skill 全部與 v4.0 相容（向後相容）
- [ ] 至少 3 條對抗式威脅鐵則被納入 v4.0
- [ ] telemetry 系統運作 1 週後產出可行動報告

Migration Plan 的 phase 範例（你要決定最終 phase 切分）：
- Phase 0: feature/v4-refactor branch + telemetry 雙跑
- Phase 1: CLAUDE.md.v4 + L0/L1 minimal profile（給內部測試）
- Phase 2: profile → skill 拆解上線
- Phase 3: MCP server 上線
- Phase 4: 對抗式威脅鐵則納入 + 公開發佈

每個 phase 必須有 entry criteria + exit criteria + rollback trigger。

最重要的一節：「v4.0 不解決什麼」
- 列出至少 5 個刻意不在 v4.0 範圍內的問題
- 例如「v4.0 不取代 Superpowers — 兩者互補」
- 例如「v4.0 不為 enterprise 多人協作優化 — 仍是個人/小團隊定位」
- 這個 section 用來防止 scope creep
```

---

## Prompt 9 — Migration Plan 與 ROADMAP.yaml 更新

```
基於 SPEC-v4.0-asp-architecture-refactor.md，產出可執行的 ROADMAP.yaml 與時程估算。

輸出：

1. 更新 docs/ROADMAP.md（如不存在則 make autopilot-init 後填入）
2. 產出 .asp/levels/migration-v3.7-to-v4.0.yaml — 升級腳本邏輯

ROADMAP.yaml 任務切分原則：
- 每個任務 ≤ 1 個工作天
- 每個任務必須對應一個 SPEC（v4.0 自己的 dogfooding）
- 並行任務必須標記 track A/B/...
- 依賴關係用 depends_on 明確列出

預估的任務群（你要根據 SDS 自己決定最終）：

Track A: Constitution & Profile 重構
  - A1: CLAUDE.md.v4 撰寫
  - A2: global_core_minimal.md 拆解
  - A3: L0 level + profile
  - A4: maturity level 文件更新

Track B: Skill 化
  - B1-B8: 拆 8 個新 skill（asp-handoff, asp-team-pick, ...）
  - B9: 整合測試 — 13 + 8 個 skill 在同一 session 不衝突

Track C: MCP server
  - C1: 技術選型決策（ADR）
  - C2: tool schema 定義
  - C3: 實作 + 單元測試
  - C4: 整合測試
  - C5: 部署文件

Track D: Telemetry
  - D1: hook patch
  - D2: skill preamble patch
  - D3: aggregate.py
  - D4: 1 週試跑與驗證

Track E: 對抗式威脅鐵則
  - E1: threat model
  - E2: 候選鐵則辯論（committee mode 用 ASP 自己決策）
  - E3: 實作至少 3 條 L1 鐵則
  - E4: 對抗式 AI 案例研究素材整理

Track F: 整合與發佈
  - F1: 全 track 整合測試
  - F2: v3.7 → v4.0 升級腳本
  - F3: docs/migration-v3.7-to-v4.0.md
  - F4: CHANGELOG + GitHub release

時程估算原則：
- 給樂觀 / 預期 / 悲觀三個時間（用 PERT 公式：(O + 4M + P) / 6）
- 標注哪些可以用 autopilot 跑、哪些必須人類介入
- 估算 token 預算（v4.0 重構過程的 Claude Code Max 用量）

最後一個 section：Go/No-Go 決策點

每個 phase 結束時，列出 3 個問題：
1. 量化指標達標？（token 降幅、bypass rate 改善、telemetry 有真實 finding）
2. 我自己（astroicers）使用體驗是否真的更好？
3. 對外推廣有沒有變容易？

任一答案是「否」就要評估是否該停止往下走。
v4.0 不是宗教，是工具。發現走錯了就回退，不要一意孤行。
```

---

## Prompt 10 — User-level Migration Execution

```
基於設計憲章 §5.5 Multi-repo Deployment Pattern，執行 ASP 從 in-project 部署到 user-level 部署的 migration。

這個 prompt 跟前 9 個不同：前 9 個是 v4.0 framework 重構，這個是 framework 完成後的部署層 migration。

前置條件（必須完成才能跑）：
- v4.0 alpha 已 release（CLAUDE.md 已砍到 < 80 行、skills 已拆解、MCP 已實作）
- 你已備份所有現有 ASP 安裝
- 你 git tag v3.7-final 已建立

執行步驟：

階段 1: 抽 ASP 為 user-level template

1. 從 ASP repo 抽出 user-level 內容：
   ```bash
   # 確保 ~/.claude/ 結構
   mkdir -p ~/.claude/skills
   mkdir -p ~/.claude/commands
   mkdir -p ~/.claude/hooks
   
   # 複製（注意：是複製不是搬移，原 ASP repo 仍保留）
   cp -r AI-SOP-Protocol/.claude/skills/asp ~/.claude/skills/
   cp -r AI-SOP-Protocol/.claude/commands/asp ~/.claude/commands/
   cp AI-SOP-Protocol/.asp/hooks/session-audit.sh ~/.claude/hooks/
   ```

2. 建立 user-level CLAUDE.md：
   ```bash
   cp AI-SOP-Protocol/CLAUDE.md ~/.claude/CLAUDE.md.draft
   # 砍到 60 行以內，保留鐵則 + .ai_profile schema + maturity level 入口
   ```
   產出 `~/.claude/CLAUDE.md` 最終版（必須 ≤ 60 行）

3. 驗證 Claude Code 在新 session 能讀到 user-level skills：
   ```bash
   cd /tmp && claude-code
   /asp-plan  # 應該能觸發
   ```

階段 2: 對每個現有專案做 migration

對清單上每個專案重複以下步驟：

(專案清單 — 順序按敏感度由低到高)
□ 符石對決 (L0)
□ ASP 自身 (L4，特殊：dogfood)
□ CyPulse (L2)
□ Merak (L4)
□ Backup 加密 4 個專案 (L4，**最後做，最謹慎**)

每個專案的 migration 步驟：

```bash
cd ~/projects/{project}
git checkout -b migrate-to-asp-v4

# 1. 備份 — 雖有 v3.7-final tag 但本地再備份
cp -r .asp .asp.backup
cp CLAUDE.md CLAUDE.md.backup

# 2. 刪除 v3.7 in-project 安裝
git rm -rf .asp/
git rm CLAUDE.md

# 3. 寫薄版 CLAUDE.md
cat > CLAUDE.md << 'EOF'
# {Project Name}

繼承 ~/.claude/CLAUDE.md 全部規則。

## 額外規則（專案特定）
{僅列此專案不同於通用的部分}

## 專案狀態
- Tech stack: {...}
- 預設 maturity level: L?
- 部署環境: {...}
EOF

# 4. 確認 .ai_profile 對應 user-level 配置（不是 in-project profile）

# 5. commit
git add -A
git commit -m "migrate: ASP v3.7 in-project → v4.0 user-level"

# 6. 驗證
# 在這個 repo 開 Claude Code，確認 ASP rules 仍生效
# /asp-gate 應該能跑
# 鐵則應該被識別

# 7. 觀察 7 天無 regression 才 push 並刪 .asp.backup
```

階段 3: 驗證 cross-project consistency

跑驗證腳本：

```bash
# 比對 ~/.claude/skills/asp/ 跟 AI-SOP-Protocol/.claude/skills/asp/ 是否同步
# 如果 ASP repo 有更新，user-level 必須 sync
diff -r ~/.claude/skills/asp/ AI-SOP-Protocol/.claude/skills/asp/
```

設計 sync 機制（避免 drift）：

```bash
# 建立 ~/.asp-sync 腳本：
#   1. 進 AI-SOP-Protocol repo pull latest
#   2. 對比 ~/.claude/skills/asp/ 看版本
#   3. 列出差異要不要 sync
# 加入 weekly cron
```

階段 4: ASP repo 自身角色轉變

ASP repo 從「**被裝進其他專案的 framework**」變成「**ASP 自身開發跟發布的工作目錄**」：

- ASP repo 不再有 .asp/profile/ 「裝在這裡讓別人複製」的角色
- ASP repo 變成 「ASP 開發者改 ASP 的地方」
- 對外發布的方式：tag release，使用者 git clone + 跑 install script 把內容裝到 ~/.claude/

更新 ASP repo README：
- 移除「複製整個 .asp/ 目錄到你專案」這種指引
- 改成「跑 install script 安裝 user-level」

驗收標準：

- [ ] ~/.claude/CLAUDE.md ≤ 60 行
- [ ] ~/.claude/skills/asp/ 至少 21 個 skill（13 既有 + 8 新拆）
- [ ] 每個專案 CLAUDE.md ≤ 30 行
- [ ] 開 Claude Code 在任一專案 session，asp-* skill 能正常觸發
- [ ] 在 ASP repo 改 ~/.claude/skills/asp/asp-plan.md，其他專案立即享受新版（不用各 repo 改一次）
- [ ] 驗證鐵則 6 (Customer Communication Isolation) 跨專案統一適用
- [ ] 驗證鐵則 7 (Crypto Auto-fix Prohibition) 跨專案統一適用
- [ ] Backup 加密 4 個專案的階段化部署規則（維運手冊 §11）正常運作

Rollback 機制：

如果 migration 後發現問題：
```bash
cd ~/projects/{project}
git revert {migration-commit-sha}
# 或
git checkout v3.7-final -- .asp CLAUDE.md
git commit -m "rollback: restore ASP v3.7 in-project deployment"
# 並從 ~/.claude/ 移除衝突的 skill
```

特別注意：

- **Backup 加密 4 個專案要最後做**——因為這是高風險系統，等其他專案 migration 穩定後再動
- Migration 過程中每個專案保持 v3.7 跟 v4.0 並存 1 週，無 regression 才完全切換
- 如果發現 user-level + 專案薄 CLAUDE.md 組合對某類任務 friction 增加 > 20%，回頭看是 user-level 規則寫得太抽象還是專案薄版漏寫關鍵
```

---

## Bonus Prompt — 元 Prompt：用 ASP 自己決策 v4.0

```
這是給 v4.0 開發過程用的「元 prompt」。

每當你（Claude Code）對 v4.0 的某個設計決策猶豫時，套用以下流程：

1. 把問題寫成一個 ADR Draft（用 .asp/templates/ADR_Template.md）
2. 列出至少 3 個方案（不可只有 2 個 — 強迫思考第三方向）
3. 啟用 mode: committee 跑 5 次 self-consistency 採樣
   - 每次採樣使用不同隨機種子的論點順序
   - 看 5 次採樣是否收斂到同一方案
4. 收斂 → 該方案有信心
   不收斂 → 真的需要人類介入，pause 並輸出 escalation P1
5. 決策後寫 ADR Accepted + 對應 SPEC

這條元 prompt 的目的：v4.0 重構過程是 ASP dogfooding 自己。
如果連 ASP 重構自己都需要繞過 ASP 的流程，那 ASP 就是個錯的設計。

特別需要套用此流程的決策點：
- MCP server 要實作哪些 tool（範圍邊界）
- 哪些 v3.7 規則該砍而不只是搬位置
- L0 跟 L1 的邊界畫在哪
- 對抗式威脅鐵則要納入幾條（過度安全 vs 不足安全）
- 是否要破壞 v3.7 向後相容

紀錄產出：
- docs/adr/ADR-v4-XXX.md（每個決策一份）
- docs/specs/SPEC-v4-XXX.md（對應實作 SPEC）
- docs/v4-decision-log.md（彙總所有 v4 重構期間的關鍵決策時間線）
```

---

## 執行檢查清單

跑完所有 prompt 後，你應該擁有：

- [ ] `.asp-baseline-v3.7.json` + `.asp-baseline-v3.7.md`
- [ ] `.asp-disposition-matrix.yaml` + `.asp-disposition-matrix.md`（含紅隊質疑）
- [ ] `CLAUDE.md.v4` + diff + coverage check
- [ ] 至少 6-8 個新的 `.claude/skills/asp/asp-*.md`
- [ ] `docs/specs/SPEC-XXX-asp-mcp-server.md` + ADR
- [ ] `.asp/scripts/telemetry/` 完整目錄
- [ ] `docs/security/ASP-Threat-Model-v1.md` + Adversarial Rules + Case Studies
- [ ] `.asp/levels/level-0.yaml` + L0 profile + spike mode 文件 + L0 audit script
- [ ] `docs/specs/SPEC-v4.0-asp-architecture-refactor.md`（整合 SDS）
- [ ] `docs/ROADMAP.md` v4.0 全部任務
- [ ] `docs/v4-decision-log.md`
- [ ] **Prompt 10 額外**：`~/.claude/CLAUDE.md` user-level + 各專案薄 CLAUDE.md + sync 腳本

**重要關聯**：

- 設計依據參考：`docs/v4-architecture-sds.md` 對應章節
- 學習依據參考：`~/docs/cs146s-study-notes.md` (personal notes, not in repo) 各週內容
- Production 維運後續工作：跑完 v4.0 重構後對應 `docs/production-ops-playbook.md` Track G

**最關鍵的兩條檢查：**

1. 跑完前 7 個 prompt 後，**先暫停**。不要直接進 Prompt 8。花一個下午自己用新的 ASP-Lite (L0) 寫一個小工具（不是 ASP 本身），看真的好用嗎。如果不好用，回去改 prompt 1-7 的決策。

2. **Prompt 10 (user-level migration) 不要急著跑**——v4.0 alpha 至少穩定 2 週才開始 migration。Migration 失敗的 blast radius 是「你所有 ASP 專案同時失能」，要慎重。
v4.0 不能只在文件上漂亮。

---

## 給 astroicers 個人化備註

1. 你 CyPulse 跟符石對決也用 ASP 嗎？如果有，把它們當作 v4.0 的 dogfooding target — 在這兩個專案先試 v4.0 而不是直接動 ASP repo 本身。

2. 你之前做的 6-role Claude Code multi-agent 系統跟 ASP 的 10-role 重疊度高。Prompt 1 的 disposition matrix 跑完後，順便評估你那 6-role 是不是該整併進 ASP 的 team_compositions.yaml，避免維護兩套。

3. 中文 prompt 在 Claude Code 上偶爾會有路由問題。如果某個 skill 觸發失敗，先檢查 description 的英文同義詞是否完整。

4. 不要一次跑完所有 prompt。建議節奏：每週 2-3 個 prompt，邊做邊用新版 ASP 開發其他專案，邊收集真實反饋。30 天內出 v4.0 alpha 是合理的。
