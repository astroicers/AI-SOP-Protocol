<!-- Last Updated: 2026-07-22 | Status: Accepted | Audience: ASP framework maintainers -->
# [ADR-027]: GitHub-native 多 session 並行開發 — per-session worktree 隔離 + issue/PR 協調基座

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-07-22 |
| **決策者** | ASP framework maintainers（astroicers 已核准 2026-07-22） |
| **觸發事件** | issue #56 — eks-infra 單日 3 起多 session 共用工作樹競態事故 |
| **關聯** | #56；SPEC-004（multi-agent worktree isolation，experimental 凍結）；ADR-017（core / experimental / showcase 分離）；使用者方向：開發環境全 GitHub-centric、大量沿用 issue/PR |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）
>
> ⬆️ 由 `Draft` 升 `Accepted`：使用者 2026-07-22 透過 `/asp:approve-adr ADR-027` 呼叫、看完本指令摘要的決策與 Verification Evidence（全空、POC 待補）後明確同意 **Draft 直升**（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。**直升取捨**：本 ADR 本輪只落地 **L1 advisory 純文件約定**（風險極低、不需 POC）；POC 綁定的 **L2 `session-audit` 偵測**另立 follow-up、待實作時補 Verification Evidence。**DP 拍板**：DP1＝落 `global_core.md` 預設行為 + `CLAUDE.md` 速查一行；DP2＝advisory-only（暫不做 L2 WARNING）；DP3＝僅偵測到多 session 時建議；DP4＝維持凍結 SPEC-004。

---

## 背景（Context）

### 事故實錄（issue #56）

2026-07-21 於 eks-infra 專案，同一工作樹（`/home/ubuntu/eks-infra`）單日有 **3+ 個 Claude Code session 並行**，實錄 **3 起競態事故**：

1. **commit 落到別人的分支**：session A 依協定開了自己的隔離分支，但在它 commit 前的空檔，HEAD 被 session B 切走 → session A 的 commit 落到 session B 的分支上，A 的分支停在舊 commit。需手動 `git branch -f` + `git reset --hard` 搶救（一步失誤即弄丟工作或污染他人 PR）。
2. **HEAD 在操作中途被切到 `main`**：若此時 commit＝直接踩「push main 由人類做」鐵則的前置防線。
3. **HEAD 被切到另一 feature 分支**：靠「commit 前 git status」抓到，但這是機率性防禦。

### 根因

git 的 **HEAD / index / working-tree 是 per-worktree 的單一共享資源**。現行協定「從最新 origin/main 開隔離分支 + commit 前 git status」：

- 「開隔離分支」隔離的是 **ref**，不是 HEAD/index/working-tree 這三樣共享狀態；
- 「commit 前檢查」只覆蓋**提交瞬間**，覆蓋不了 session 生命週期內任意時刻的互踩（checkout / add / stash / reset 全部互相干擾）。

並行 session 數 ≥2 時，協定的正確性依賴「兩個 AI 恰好不在同一時窗操作 git」——**這不是工程保證**。

### 前提更正（重要）

issue #56 假設要「修改現行 handoff『工作樹多 session 共用』協定段落」。**經查 ASP repo（grep `CLAUDE.md` / `global_core.md` / `.asp/templates/`）並無此段落**——它是下游 eks-infra 的專案慣例，不在 ASP core。故本 ADR 定位為**在 ASP core 新增規則**，而非修改既有；連帶須先定案「規則落在哪裡」（見 DP1）。

### 使用者方向

開發環境全部圍繞 GitHub → git worktree 設計要**格外重視**；目標是**完美解決多 session 並行開發問題**；且**大量沿用 GitHub 既有的 issue / PR 功能**做協調。本 ADR 據此把 worktree 隔離設為一等公民，issue/branch/PR 三元組為協調基座。

---

## 評估選項（Options Considered）

### 選項 A：GitHub-native per-session worktree 隔離規則進 core（建議）

**核心模型**：每個並行 session ＝ 認領一個 GitHub **issue** → 在**專屬 git worktree**（`git worktree add ../<repo>-wt-<topic> origin/main`；Claude Code 由使用者指示 **EnterWorktree**）開**專屬 branch** → 收尾開**專屬 PR**。**主工作樹保留給人類**。

- **優點**：
  - worktree 間 HEAD / index / working-tree **完全獨立** → 事故 1-3 **結構性不可能發生**（非機率性防禦）。
  - GitHub **issue/PR 天然承載跨 session 狀態與交接**——認領＝assign issue、進度＝PR draft、交接＝PR review，取代脆弱的「共用工作樹 + git status」協定，且完全落在使用者既有的 GitHub 工作流內。
  - 分層乾淨：core 只加「規則 + 紀律」（可攜、標準協定）；偵測 enforcement 為 CC-only tier（接 P4 可攜層分離）。
- **缺點**：磁碟成本 + 首次 checkout 數秒；需 worktree 生命週期紀律（合併後 `git worktree remove` + 刪分支，避免殭屍 worktree）；cwd-based hooks/skills 在 worktree 路徑下的行為須驗。
- **風險**：觸及行為憲法（規則落點 DP1）與 Iron-Rule-A 保護的 `session-audit.sh`（L2 偵測 DP2）；須人類拍板落點與強制程度後方可實作。

### 選項 B：維持現狀（共用工作樹 + 開隔離分支 + commit 前 git status）

- **優點**：零改動。
- **缺點**：機率性防禦，**issue #56 單日 3 起事故已證其結構性不足**（連遵守協定的對方 session 也照樣出事）。
- **風險**：並行 session 成常態後事故反覆，磨損對框架信賴、且有踩「push main」鐵則之虞。

### 選項 C：全套解凍 SPEC-004（orchestrator 多 agent 隔離）

- **優點**：SPEC-004 已有完整 worktree 隔離設計（驗收 21/21）。
- **缺點 / 風險**：**場景不符**。SPEC-004 是「一個 orchestrator 派多 agent」（需要 dispatch / converge 編排）；本案是「使用者手動開多個互動 session」（**只需要隔離、不需要編排**）。全套解凍＝過度工程，且不符 ADR-017 的解凍條件（「出現單一 session 無法完成的實際案例」——本案每個 session 各自完成一個 issue，符合單 session 能力範圍）。**已排除**：改為抽最小隔離規則進 core。

---

## 決策（Decision）

提議 **選項 A**：把「GitHub-native per-session worktree 隔離」納入 ASP core，以 **issue → worktree → branch → PR** 三元組為並行開發的協調基座。

因觸及行為憲法與 Iron-Rule-A 保護檔，**本 ADR 維持 `Draft`**，並把落地細節切成三層 + 一份相容性清單，待人類拍板下列**設計決策點**後，由對應 SPEC（通過 G2）實作：

| DP | 決策點 | 選項 | 初步建議 |
|----|--------|------|---------|
| **DP1** | 規則落點 | (a) root `CLAUDE.md` 憲法　(b) `global_core.md` 預設行為　(c) 新增 shipped CLAUDE.md 模板 | **(b) 預設行為為主 + (a) 一行摘要**。ASP 目前**不 ship 下游 CLAUDE.md 模板**，故不走 (c)。 |
| **DP2** | 強制程度 | (a) 純文件約定（advisory）　(b) + L2 `session-audit` WARNING 偵測　(c) 硬 gate（deny） | **(b) advisory + WARNING**。worktree 是使用者環境選擇，硬 gate 會誤傷單一 session／不支援 worktree 的環境。 |
| **DP3** | 觸發範圍 | (a) 僅偵測到多 session 時建議　(b) 一律建議 per-session worktree | **(a)**：單 session 無競態、不必付 worktree 成本。 |
| **DP4** | SPEC-004 立場 | (a) 維持凍結　(b) 部分解凍　(c) 全套解凍 | **(a) 維持凍結**：本案只需隔離，登錄為「已知使用案例但不解凍」。 |

### 三層落地藍圖（供 SPEC 展開，非本 ADR 實作）

- **L1（core 模型，可攜）**：定義 issue→worktree→branch→PR 三元組與 worktree 生命週期紀律。
- **L2（偵測，CC-only tier）**：`session-audit` A 系列偵測「本 session 不在專屬 worktree」或「主工作樹近期 reflog 有其他 session 的 checkout 活動」→ 印 WARNING 建議改用 worktree（**須人類核准後才動 Iron-Rule-A 保護的 `session-audit.sh`**）。
- **L3（SPEC-004 立場）**：於文件明確記錄「維持凍結、不套用 ADR-017 解凍條件」及理由。

### 須一併驗證的相容性清單

- 專案內**絕對路徑配置**（`.mcp.json`、`KUBECONFIG`、憑證路徑等）在 worktree 路徑下是否可用（多為指向主 repo 的絕對路徑，應無礙，但落點文件須寫明）。
- ASP hooks / skills 以 **cwd 解析**的部分在 worktree 內的行為。
- **worktree 清理紀律**：合併後 `git worktree remove` + 刪分支，避免殭屍 worktree 累積（呼應 memory「堆疊 PR 中途 merge → 孤兒分支」的相鄰風險）。

---

## 後果（Consequences）

**正面影響：**
- 多 session 並行下的 commit 落錯分支 / HEAD 被切走事故**結構性根治**。
- 協調層完全落在使用者既有的 GitHub issue/PR 工作流；每個並行任務有獨立、可稽核的 issue+branch+PR。
- core（規則）與 enforce（偵測）分層乾淨，可攜層不被 CC-only 偵測拖累（接 P4）。

**負面影響 / 技術債：**
- 磁碟 + 首次 checkout 秒級成本；worktree 生命週期紀律（未清理 → 殭屍 worktree）。
- cwd-based hooks/skills 相容性須逐項驗；EnterWorktree 與 handoff 文件須更新。
- L2 偵測須動 Iron-Rule-A 保護的 `session-audit.sh`（核准後 + hash 更新流程）。

**後續追蹤：**
- [ ] 人類核准本 ADR + 拍板 DP1–DP4（`/asp:approve-adr ADR-027`）。
- [ ] 撰寫 SPEC（L1 規則落點 + L2 偵測 spec + 相容性清單），通過 G2。
- [ ] POC：多 session 並行、各自 worktree，實測事故 1-3 不再發生；相容性清單全綠。

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 多 session 並行下 commit 落錯分支 / HEAD 被切走事故 | 0 起 | POC：≥2 session 各自 worktree 並行操作 git，稽核 reflog | POC 完成時 |
| 每個並行任務的可稽核性 | 100% 有獨立 issue + branch + PR | 抽查並行任務 | 上線後 1 個迭代 |
| worktree 相容性 | 清單全綠（絕對路徑配置 / cwd hooks / 清理紀律） | 相容性驗證腳本 | 實作完成時 |

> 重新評估條件：若 Claude Code 的 EnterWorktree / 多 session 模型改變，或 worktree 隔離成本高於協調收益（例如絕對路徑配置大量失效），須重審本決策。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：issue #56（事故實錄 + 分層建議）；`docs/specs/SPEC-004-multi-agent-worktree-isolation.md`（凍結中，DP4 維持凍結）；ADR-017（core / experimental / showcase 分離，DP1 落點的上位約束）；使用者方向（GitHub-centric、issue/PR 協調）。

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | （待 POC：≥2 session 各自 worktree 並行，實測事故 1-3 不再發生 + 相容性清單） |
| **驗證日期** | （待填） |
| **驗證者** | （待人類覆核） |
| **驗證摘要** | 待 POC；外部行為（`git worktree` HEAD/index 獨立性）為 git 既有保證，落地相容性待驗。 |
