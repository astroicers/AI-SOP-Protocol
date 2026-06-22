<!-- Last Updated: 2026-06-22 | Status: Draft | Audience: Maintainers -->
# 借鏡反思報告：ASP 對照 buildwithclaude 與 nuwa-skill

> 本報告為**評估交付物**，非實作。借鏡兩個外部 Claude/Agent 生態專案，對 ASP 現況做一次誠實、批判性的反思，給出改善與重構方向。所有「建議」皆為提案，需經 ADR 流程核准後方可落地。
> 參照標的：[`davepoon/buildwithclaude`](https://github.com/davepoon/buildwithclaude)（分發/catalog 典範，3.1k★）、[`alchaincyf/nuwa-skill`](https://github.com/alchaincyf/nuwa-skill)（極簡單一價值 + examples-first + 跨 runtime）。

---

## 0. 摘要（TL;DR）

ASP 的核心問題**不是「治理不夠」，而是三件事疊加**：

1. **治理過載**——~85:1 的文件:功能碼比、20 個高度交叉引用的 ADR、為繞過 LLM 不穩而生的 2083 行編譯產物、帶 escape hatch 的機械閘、甚至有「量測自己有沒有過胖」的基礎建設。每遇一個 LLM 可靠性問題，反射動作是**加一層機械強制**，而非簡化需求。
2. **沒接上生態**——用 29KB 自製 `install.sh` + 全域 sync，而 Claude Code 早有官方 `/plugin marketplace add` 機制。零可發現性，且 sync 漂移本身已成測試負擔。
3. **沒拆層**——單一 repo 同時扛憲法、強制力 hooks、skills、installer、實驗性多代理、showcase、templates、48 個測試；可攜的「行為憲法」與不可攜的「Claude Code 專屬強制力」糾纏在一起。

對應三個方向：**精簡（cut）／拆層（split）／接軌（adopt 官方 plugin 機制）**。

借鏡關係一覽：

| 借鏡來源 | 它做對什麼 | ASP 對應缺口 |
|---|---|---|
| buildwithclaude | 官方 marketplace 分發、分類 catalog、一致命名、多安裝路徑 | 自製 installer + sync 漂移、零生態可發現性 |
| nuwa-skill | 一句話價值、examples-first、誠實邊界、標準協定跨 runtime | 術語牆上手、無範例情境庫、深綁 Claude Code |
| 兩者共同 | skill 短小、單一職責、好組合 | 巨型 skill（autopilot 829 行）+ 單體 router |

---

## 1. 定位與上手（借鏡 nuwa-skill 的「一句話價值 + examples-first」）

- **借鏡點**：nuwa 用一句 tagline 把價值講完（「你想萃取的下一個人，不必是你的同事」）；`examples/` 放 13 個可直接跑的人物 skill；方法論透明（`extraction-framework.md`）、附「誠实边界」誠實說明侷限。新人 5 分鐘內知道「這是什麼、怎麼用、能不能用在我身上」。
- **ASP 現況**：價值主張埋在術語牆下。要讀懂 ASP 在幹嘛，得串接 README → `CLAUDE.md` → `CONTEXT.md`（40+ 條術語表）→ `docs/where-to-start.md` 四份文件。首屏即出現 ADR / SPEC / HITL / G1–G6 / L1–L4 / Draft–FIRM–Accepted / profile / hook 等約 22 個縮寫，README 前 5KB 約**每 300 字一個縮寫**。`CLAUDE.md` 第二行就是巢狀術語「鐵則（不可覆蓋）」，且把「啟動程序」「強制力架構」「過程義務速查」這些**機制細節**放在新人最先讀到的位置。
- **落差**：
  - 沒有一句話定位句。
  - 沒有 5 分鐘 quickstart（裝完馬上看到一個有感的行為）。
  - 沒有 examples-first 的「跑一個真實情境」入口——`showcase/` 是進階 opt-in，不是入門範例。
  - 術語沒有前置 glossary，新人邊讀邊查。
- **建議**：
  1. README 首屏一行定位句（例：「ASP 是給 AI coding agent 的行為憲法 + 機械護欄，讓它在沒人盯著時也守紀律」）。
  2. 5 分鐘 quickstart：裝 → 開一個 `loose` 專案 → 故意製造一次該被擋的 commit → 看 gate 擋下來。讓「護欄真的會動」可被親眼看到。
  3. `examples/` 情境庫（對齊 nuwa）：3–5 個最小可跑情境（loose spike、standard TDD、一次 ADR 流程）。
  4. 術語表前置或獨立 `GLOSSARY.md`，README/CLAUDE.md 首次出現時連結過去。
  5. `CLAUDE.md` 瘦身：鐵則 4 條留首屏，啟動程序/強制力架構等機制細節下沉到 `docs/`。

---

## 2. Skill 粒度：是否「簡短且單一功能」（使用者明確問題）

- **借鏡點**：buildwithclaude 與 nuwa 的 skill 都**短小、單一職責、好組合**——buildwithclaude 把能力切成 117 agents / 175 commands / 26 skills，命名即職責（`commands-version-control-git`）；nuwa 一個 skill 做一件事（萃取一個人）。
- **ASP 現況**：skill 走「巨型化 + 單體 router」：
  - `asp-autopilot.md` **829 行**、`asp-gate.md` **419 行**、`asp-ship.md` **306 行**——單一檔塞進整條工作流。
  - `SKILL.md`（117 行）是唯一註冊的 ASP skill，依「意圖」分流到 `asp-*` worker。這是**單一巨型 router**，不是市集式「多個小 skill 各自可被發現/取用」。
- **落差**：
  - 巨型 skill 難測（一個檔涵蓋 10 步，無法單測一步）、難重用（想只要 G3 測試閘，得載入整個 gate skill）、難跨 runtime（見 §5）。
  - 新人/外部使用者無法「只取用其中一塊」——要嘛全要，要嘛不要。
  - 對 LLM 而言，長 skill 在長對話壓縮後容易蒸發（這也是 ADR-020「遺忘威脅」要對治的問題之一，等於 skill 過長反過來放大了它要解的問題）。
- **建議**：
  - 把 mega-skill 拆成單一職責小 skill：G1–G6 各自獨立可呼叫；autopilot 的 step 3/4 拆成可組合單元。
  - `SKILL.md` router 保持薄，只做意圖→skill 名的對應，不內含工作流邏輯。
  - 命名向 buildwithclaude 慣例靠攏（職責即名），提升可發現性。

---

## 3. 「完整思維路線」與是否該拆成多專案 / 多 skill（使用者明確問題）

### 3.1 思維路線是否完整？——完整，但**過度完整**

ASP 的思維路線清楚：`需求 → ADR → SDD 設計 → TDD 測試 → 實作 → 文件同步 → 確認後部署`，再疊上 G1–G6 品質閘與 L1–L4 強制力層次。問題不在缺失，而在：

- **連接邏輯散落在 20 個高度交叉引用的 ADR**。ADR-009 串接 9 個前序 ADR（佔總數 45%）；要懂一個決策得回溯 3–7 個前序。這條「思維路線」存在，但**讀者得自己在 20 份文件間拼湊**，沒有一份「定案設計總覽」把它串成一條線。
- 結果是**思維路線存在於作者腦中與 ADR 鏈裡，但沒有以新人可線性閱讀的形式存在**。

### 3.2 是否該拆成多專案 / 多 skill？——應該拆

目前單一 monorepo 同時扛：行為憲法 + hooks 強制力 + 15 skills + 29KB 自製 installer + `experimental/` 多代理（35 檔）+ `showcase/`（RAG/telemetry/perf）+ 18 個 templates + 48 個測試。職責邊界模糊，改一處牽動整片。

**建議分層拆解**（對齊既有 loose/standard/autonomous 三級，但目前**封裝完全沒反映分層**）：

| 層 | 內容 | 可攜性 | 現況 |
|---|---|---|---|
| `asp-core` | 最小行為憲法（4 鐵則 + global_core 精簡版） | 高（標準協定） | 與其他層混在 root |
| `asp-skills` | skills pack（拆小後的單一職責 skill） | 中高 | 巨型化、綁 CC |
| `asp-enforce` | Claude Code 專屬 hooks / 動態 deny / session-audit | 不可攜（CC-only） | 與憲法混雜 |
| `asp-experimental` | 多代理 orchestration | — | 已在 `experimental/`，建議獨立 repo |
| `asp-showcase` | RAG / telemetry / perf 範例 | — | 已 opt-in，建議獨立 repo/examples |

拆層的副效益：複雜度預算可分層管理；可攜層能上 nuwa 式的多 runtime；強制力層的鎖定範圍變得誠實可見（見 §5）。

---

## 4. 分發與生態整合（借鏡 buildwithclaude）

- **借鏡點**：buildwithclaude 用 Claude Code **官方機制** `/plugin marketplace add davepoon/buildwithclaude` 一鍵安裝；內容分類成 Agents/Commands/Hooks/Skills/Plugins；命名一致（`agents-python-expert`）；web UI 可瀏覽/搜尋/複製；多種安裝路徑並存。可發現性與低安裝摩擦是它 3.1k★ 的關鍵。
- **ASP 現況**：
  - `install.sh` **29KB** + `install.ps1` PowerShell 版 + 全域 `~/.claude/asp/` sync，分 Phase 1（user-level）/ Phase 2（project-level）。
  - 沒掛上任何官方 plugin marketplace，零生態可發現性。
  - 存在 `test_asp_sync_downgrade`、`test_managed_deny_reconcile`、`test_asp_commands_sync` 等測試——**這些測試的存在本身就是 sync 機制容易漂移的症狀**：自製分發機制把「保持同步」變成了持續的工程負擔。
- **落差**：高安裝複雜度、版本/路徑漂移風險、零可發現性。
- **建議**：
  1. 重新封裝為標準 Claude Code plugin，上架 marketplace，以官方機制取代 29KB 自製 installer 與一整批 sync 漂移測試。
  2. 命名向 buildwithclaude 慣例對齊（職責前綴），降低外部認知成本。
  3. 保留自製 installer 作為「進階/離線」路徑即可，不再是唯一/主要路徑。

---

## 5. 跨 runtime 可攜性（借鏡 nuwa-skill 的標準協定）

- **借鏡點**：nuwa 走標準 Agent Skills 協定，宣稱可在 Claude Code / Cursor / Codex / 50+ runtime 跑。skill 是純粹的「思維/方法」描述，不綁特定 harness。
- **ASP 現況**：深度綁定 Claude Code：
  - 強制力靠 hooks（`session-audit.sh` 27KB、`pretooluse-ship-gate.sh`）。
  - 動態 deny 注入 `.claude/settings.local.json`。
  - L1 / L1.5 / L2 強制力層**全是 CC 專屬**，換到別的 runtime 立刻失效。
- **落差**：本可攜的「行為憲法 / 方法論」與不可攜的「CC 專屬強制力」混在一起，導致**整體都不可攜**，連憲法層都被綁死。
- **建議**：
  1. 明確分層（接 §3.2）：憲法 / skills 層走標準 Agent Skills 協定，盡量可攜；hooks / 強制力層標示為 **CC-only tier**。
  2. 在 docs 誠實記錄鎖定範圍（呼應 nuwa 的「誠实边界」）：哪些能力換 runtime 還在、哪些會失效。讓使用者在採用前知道自己買的是什麼。
  3. 不必硬追 50+ runtime；重點是**讓可攜的部分不被不可攜的部分拖下水**。

---

## 6. 複雜度 / 過度工程（核心病徵）

- **數據**：
  - ~**85:1** 文件:功能碼比（治理文件 vs 實際 shell/功能碼）。
  - **20 個交叉耦合 ADR**，平均 2.4 個互引，ADR-009 串 9 個。
  - `.asp-compiled-profile.md` **2083 行**編譯產物——**為繞過 LLM runtime 解析 profile 依賴不穩**而加的 build-time 編譯器（ADR-016）。
  - `pretooluse-ship-gate.sh` commit 閘帶 **fail-open**（hook 自身異常就放行）+ `ASP_SHIP_OK=1` **escape hatch**（ADR-020）。
  - `asp-metrics.sh` / `rule-stats.sh` / `.asp-metrics-baseline.json`：**用來量測 ASP 自己有沒有過胖**的基礎建設（ADR-013/018）。
- **共同病徵**：每遇一個 LLM 可靠性問題，反射動作是**加一層機械強制**，而非簡化需求——
  - LLM 解析 profile 不穩 → 加編譯器（ADR-016）。
  - LLM 會忘記跑測試 → 加 PreToolUse 閘 + escape hatch（ADR-020）。
  - 不確定規則有沒有用 → 加遙測量測規則命中率（ADR-018）。

  治理層因此**自我增生**（ADR 13→14→…→20），且系統已**自承**有「語意型、hook 無法機械化」的義務殘留（`CLAUDE.md` 過程義務速查），只能靠「希望它在長對話壓縮後存活」——這已逼近**治理劇場**（governance theater）：寫了規則但無法強制，靠祈禱。
- **建議**：
  1. 設**複雜度預算**：每新增一層強制，先問「能不能用簡化需求取代」。
  2. 把 ADR 鏈合併為少數幾份「已定案設計總覽」，ADR 退化為索引/變更記錄（接 §3.1）。
  3. 若 profile 集合縮小（接 §3.2 拆層），重新評估 compiled-profile 編譯步驟是否還需要——它是為解決「profile 太多太散」而生，把根因解掉，這層可能整個消失。
  4. 對「無法機械化」的義務**誠實降級**為文件約定，別偽裝成強制；與其用 metrics 量自己肥不肥，不如直接砍。

---

## 7. 反向平衡（避免一面倒）

批判之外，誠實列出 ASP 做得好、**不該砍**的部分——重構是「精簡 + 拆層 + 接軌」，不是推倒重來：

- **鐵則安全模型**：破壞性操作防護、敏感資訊保護、ADR 未定案禁止實作、外部事實驗證——這四條是真正的價值核心，邊界清楚、值得保留。
- **bypass log hash chain**（ADR-019）：tamper-evident 的設計是紮實的工程，不是過度。
- **敏感資訊掃描**（`asp-ship` Step 9）：實用的防護。
- **測試文化**：48 個 bash 測試覆蓋 hooks/gates/profiles/install，且已抽 `tests/lib/common.sh` 去重——紀律值得肯定。
- **三級成熟度模型**（loose/standard/autonomous）**的設計意圖**是對的（漸進式採用）；問題只在「封裝沒反映分層」，模型本身應留。

換言之，ASP 的**安全/品質核心是資產**；負債在它外圍的**分發、上手、可攜、複雜度**包裝層。

---

## 8. 行動優先序（給決策用，不在本次執行）

| 優先 | 行動 | 投入 | 風險 | 收益 |
|---|---|---|---|---|
| **P0** | 上手/定位瘦身：一行定位句 + 5 分鐘 quickstart + GLOSSARY + CLAUDE.md 機制細節下沉 | 低 | 低 | 立即降低新人/外部採用門檻 |
| **P1** | skill 拆小（§2）+ 接 Claude Code plugin marketplace（§4） | 中 | 中（需驗證官方機制涵蓋 hooks 場景） | 可發現性 + 重用性 + 砍掉 sync 漂移測試 |
| **P2** | 分層拆 repo（§3.2）：core / skills / enforce / experimental / showcase | 高 | 中高（跨 repo 協調） | 職責清晰、複雜度可分層管理、解鎖可攜層 |
| **P3** | 複雜度預算 + ADR 鏈整併為設計總覽（§6） | 中 | 低 | 思維路線可線性閱讀、治理層止血 |
| **P4** | 可攜層分離 + 誠實記錄 CC 鎖定範圍（§5） | 中 | 中 | 憲法/skills 不再被 CC 綁死 |

建議路徑：先做 P0（低投入高回報、不動架構），驗證採用反饋後再評估 P1–P4 是否值得投入。每個 Px 落地前各自走 ADR 流程。

---

## 附錄：證據索引

- **結構/數據**：`.asp-compiled-profile.md`(2083 行)、`.claude/skills/asp/asp-autopilot.md`(829)/`asp-gate.md`(419)/`asp-ship.md`(306)、`docs/adr/`(ADR-001..020)、`docs/specs/`(SPEC-001..013)、`.asp/scripts/install.sh`(29KB)、`tests/`(48 檔)、`tests/lib/common.sh`。
- **治理自省**：`CHANGELOG.md` ADR-013/016/017/018/020 段落；`CLAUDE.md`「過程義務速查」自承「語意型、hook 無法機械化（ADR-020 已知殘留）」。
- **外部對照**：buildwithclaude README（`/plugin marketplace add`、Agents/Commands/Hooks/Skills/Plugins 分類、命名慣例、web UI）；nuwa-skill README（`SKILL.md` + `references/` + `examples/` 13 範例、標準 Agent Skills 協定 50+ runtime、「誠实边界」）。
