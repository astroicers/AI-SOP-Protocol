# ASP Production Operations Playbook — 全自動維運手冊

> ⚠️ **本文件 Status: Reference (2026-05-10 起)**
>
> v4.0 ops 設計脈絡。Track G 的 ToDo 已部分實作（見 `.asp/ai-performance/`、`session-audit.sh`、SPEC-004 worktree），剩餘章節保留作為「ops 設計參考」。**不再主動更新**，新的 ops 變動請更新 `docs/architecture.md` 或開新 SPEC。

> **本檔案定位**：用 AI 自動維運個人專案的長期 playbook (操作手冊)。
>
> **使用方式**：每個專案進入 production 前/後查此檔案決定啟用哪些子系統。日常操作指引。
>
> **與其他三份檔案的分工**：
> - `~/docs/cs146s-study-notes.md` (personal notes, not in repo) — 學什麼、學會了什麼（學習過程）
> - `docs/archive/v4-refactor/v4-architecture-sds.md` — 為什麼這樣設計（v4.0 框架重構，已 archive）
> - `docs/archive/v4-refactor/v4-refactor-prompts.md` — 怎麼執行（v4.0 重構步驟，已 archive）
> - `docs/production-ops-playbook.md` ← **本檔案** — 框架完成後怎麼用 AI 維運

---

## Frontmatter

| 欄位 | 值 |
|-----|---|
| Version | v1.0 |
| Status | Reference（原為 Active，2026-05-10 改） |
| 起源 | CS146S W6/W7/W8 學習 + 與 astroicers 的設計對談 |
| Owner | astroicers |
| 起始日期 | 2026-05-04 |
| 最後更新 | 2026-05-10（Status frontmatter 與 archive 連結同步） |
| 適用 ASP 版本 | v4.0+（v4.1 部分內容已被取代） |

### 跨檔案索引

- 對應 ASP v4.0 設計憲章：`docs/archive/v4-refactor/v4-architecture-sds.md` §3.1 盲點 4 / §6.1 Track G / §10 D-005~D-007
- 對應 v4.0 執行 prompt：`docs/archive/v4-refactor/v4-refactor-prompts.md` (Track G 對應的 prompt 將另外擴充)
- 對應學習依據：`~/docs/cs146s-study-notes.md` (personal notes, not in repo) W6 (Closed-Loop Remediation) + W7 (Reviewer Trust Boundary) + W8 (Production Boundary)

---

## 1. Goal (目標)

> **30 字 essence**：用 AI 加速生產系統的開發、bug 修復、監控，但**保留人類在客戶可見邊界跟高風險決策上的最終決定權**。

### 核心原則

1. **Trust boundary 決定自動化等級**——不是 AI 不夠強，是不該把高 trust 任務交給單一 channel 控制
2. **客戶可見邊界 = 自動化禁區**——trust capital management 不可妥協
3. **AI 信任靠累積數據**——不是預設給，是經 30 天 outcome tracking 賺到
4. **每個自動化必須配套 accountability mechanism**——auto-merge 配 performance review 才能讓「事後反思」真的發生

### 與 ASP v4.0 的關係

| | ASP v4.0 | 本維運手冊 |
|---|---------|----------|
| 範圍 | 框架本身重構 | 用框架去做事 |
| 時程 | 30 天集中專案 | 永久 ongoing |
| 何時穩定 | 完成後就穩 | 持續演化 |
| 受影響人 | ASP 開發者 | 你的所有專案的營運 |
| 觸發更新 | 新一輪重構 | 新事件 / 新專案上線 / 新威脅 |

**v4.0 是基礎設施，本手冊是駕駛說明**。v4.0 完成才能完整啟用本手冊所有子系統。

---

## 2. Subsystem Overview (子系統總覽)

6 個自動化子系統，每個有獨立 trust boundary 跟自動化等級。**已決定啟用 4 個（A/B/C/D）跳過 2 個（E/F）**。

### Strategic Frame

| 子系統 | 範疇 | 自動化等級 | 啟用？ | 失敗代價 |
|-------|------|----------|-------|---------|
| **A. 開發 Pipeline** | SPEC → 實作 → PR | 60% | ✅ | 中 |
| **B. Bug 修復 (Trivial)** | typo / lint / format | 90% (auto-merge) | ✅ | 小 |
| **C. Bug 修復 (Standard)** | 功能 bug | 50% | ✅ | 中 |
| **D. Production Monitoring** | log / metrics / anomaly | 100% (read-only) | ✅ | 零 |
| **E. 架構設計** | ADR draft | — | ❌ 跳過 | 高 (HITL 必要) |
| **F. 客戶 Bug 處理** | 客戶 ticket → 修補 | — | ❌ 跳過 | 極高 (HITL 強制) |

### Trust Boundary 判定表

每個子系統的自動化等級由 4 維 trust boundary 決定：

| 子系統 | Customer-facing? | High blast radius? | Tribal knowledge required? | Critical security? |
|-------|-----------------|------------------|--------------------------|-------------------|
| A 開發 | ❌ (內部) | 中（可 rollback）| 部分 | 視專案 |
| B Trivial | ❌ | 小（單檔小改）| 否 | 否（不碰 crypto） |
| C Standard | ❌ | 中（功能改動）| 部分 | 視專案 |
| D Monitor | ❌ | 零（read-only） | 否 | 否 |
| E 架構 | ❌ | **極高（決策影響數年）**| **必要**| 視專案 |
| F 客戶 | **✅✅✅** | 極高（信任崩潰） | 必要 | 視專案 |

**E、F 跳過的關鍵原因**：
- E：tribal knowledge required + W7 教過 AI 在架構決策不可靠
- F：customer-facing 直接違反鐵則 6（客戶通訊隔離）

### Per-Project Applicability

不同專案啟用的子系統不同（詳見 §12 Per-Project Status Tracker）：

```
高敏感 production 專案 (Merak、Backup 加密)：
  ✅ A (開發)、D (Monitor)
  ⚠️ B、C 排除 crypto/ + security/ 目錄
  ❌ 永遠不碰 E、F

中敏感 production 專案 (CyPulse dogfood)：
  ✅ A、B、C、D 全部啟用
  ❌ E、F 跳過

Prototype 專案 (符石對決 L0)：
  ✅ A 簡化版（無強制 SPEC）
  ⚠️ B、C 視情況
  ❌ D、E、F 不需要
```

---

## 3. Subsystem A: Development Pipeline

### 屬性

| 屬性 | 值 |
|-----|---|
| 自動化等級 | 60% |
| 你的角色 | SPEC author + final approver |
| Blast radius | 中 |
| 客戶可見 | ❌ |
| 適用專案 | 所有 |

### 流程

```
[你] 寫 SPEC 進 docs/specs/SPEC-XXX.md
       ↓
[你] /asp-plan SPEC-XXX
       ↓
Claude Code:
  1. 讀 SPEC 的 Done When
  2. git worktree add ../{repo}-spec-XXX feature/SPEC-XXX
  3. 在 worktree 寫測試（讓所有測試 fail）
  4. 實作 code 直到測試通過 (Reflexion loop)
  5. 跑 pre-commit (lint / format / Semgrep)
  6. push branch, gh pr create
       ↓
[GitHub] Diamond/Copilot 自動 review
       ↓
[你] 看 Diamond review + 你自己 review
       ↓
[你] 同意 → merge / 不同意 → comment 回 Reflexion
```

### 安全限制

- worktree 必須使用 (W5: Filesystem isolation)
- SPEC 的「Done When」必須包含可二元測試的條件
- pre-commit Semgrep ruleset 必須通過 (W6: Hard mechanism)
- crypto/ 目錄修改觸發強制 HITL (鐵則 7)
- 任何 customer-facing 修改進入子系統 F 流程（即不啟用，HITL 強制）

### 關鍵設計

你**只動 SPEC 跟 final approve**，中間全自動。

**何時 SPEC 改寫成簡化版**：
- L0 專案（符石對決）：可省略 SPEC，直接給 task brief
- L1+ 專案：完整 SPEC + Done When + Edge Cases

### 3.5 — Implementer/Reviewer Pair Configuration (實作者/審查者配對配置)

> **此節 cross-applies to §4 子系統 B 跟 §5 子系統 C**。子系統 D (Monitor) 不適用（純 read-only，無 reviewer 階段）。

#### 設計依據：W7 4 維獨立性檢驗

回憶 W7 教過的真獨立 4 維（model / vendor / prompt lineage / context）。當 implementer 跟 reviewer 都是 Claude（同 vendor）時的獨立性檢驗：

| 獨立維度 | Opus implementer | Sonnet reviewer | 獨立？ |
|---------|------------------|-----------------|-------|
| Model independence | Opus 4.7 | Sonnet 4.6 | ⚠️ 半獨立（不同 size、不同 capability profile） |
| Vendor independence | Anthropic | Anthropic | ❌ 同廠商（共享 alignment 哲學 + 訓練資料 overlap） |
| Prompt lineage | implementer prompt | review prompt（不同設計） | ✅ |
| Context independence | 完整實作對話 | 可選擇給/不給 | ✅ 可控 |

**獨立度 2.5/4**——比同 session self-doubt (0.5/4) 好，比 cross-vendor (4/4) 差。

#### 三種 Pair Mode (配對模式)

| Mode | Implementer | Reviewer | 獨立度 | 適用任務 |
|------|-------------|----------|--------|---------|
| **Routine** | Sonnet 4.6 | Opus 4.7 | 2.5/4 | trivial bug 修補、template 生成、簡單 refactor |
| **Complex** | Opus 4.7 | Sonnet 4.6 | 2.5/4 | new feature、architectural change、複雜邏輯 |
| **High-Stakes** | Opus 4.7 | Sonnet 4.6 + External AI (Diamond/Copilot) + Human | 4/4 | auth、crypto、customer-facing、backup 加密 |

#### 不對稱方向（Asymmetric Direction）— 為什麼 Routine 跟 Complex 反向

**Routine task: Sonnet 寫 + Opus review**

理由：
- Sonnet 速度快，適合**量產**
- Opus 深度推理，適合**深 review**
- Routine baseline 較低，Sonnet 寫的品質夠用
- Opus review 補強——抓 Sonnet 容易漏的微妙 bug

**Complex task: Opus 寫 + Sonnet review**

理由：
- Complex 需要 Opus 的深度推理能力做架構決策
- Sonnet review 補強——抓 Opus「過度思考」漏掉的明顯問題
- 反向會讓 Sonnet 在 baseline 不足的情況下做架構決策，風險高

#### Calibration Log Schema

放在 `.asp-ai-performance/reviewer-agreement-log.jsonl`：

```jsonl
{
  "ts": "2026-05-04T...",
  "pr_number": 142,
  "task_type": "routine|complex|high_stakes",
  "implementer": "sonnet-4.6",
  "reviewer": "opus-4.7",
  "implementer_findings": [...],
  "reviewer_findings": [...],
  "agreement_rate": 0.85,
  "reviewer_caught_implementer_missed": [...],
  "implementer_caught_reviewer_missed": [...],
  "real_outcome_t30": {
    "real_bugs_in_pr": [...],
    "who_caught_each": ["implementer"|"reviewer"|"both"|"production"]
  }
}
```

跑 30 天後分析：
- 哪些 finding type Reviewer 抓到 Implementer 漏的（有效補強）
- 哪些 finding type 兩個都抓到（冗餘）
- 哪些 finding type 兩個都漏（**必須升級到 High-Stakes mode**）

#### Maturity Level 適用表

| Level | 預設 Pair Mode | 強制 Layer 3 (External AI)? | 強制 Human? |
|-------|---------------|---------------------------|-----------|
| L0 (Spike) | Routine | 否 | 否 |
| L1-L2 | Routine or Complex（by task） | 否 | 視情況 |
| L3 | Complex | 對 sensitive paths 強制 | 是 |
| L4-L5 | High-Stakes mandatory | 是 | 是 |
| crypto/auth paths (任何 level) | High-Stakes | 是 | 是 |

#### 警告與限制

1. **同廠商有結構性共同盲點**——Anthropic 對所有自家模型有統一的 Constitutional AI training pipeline、同一套 RLHF 偏好資料。Opus + Sonnet 在「什麼樣的 code 看起來 ok」這件事上判斷標準高度相關。
2. **不可跳過 Layer 3 (cross-vendor) 在 L3+ 場景**——同 vendor 的 2.5/4 獨立度對高 blast radius 任務不夠。
3. **必須跑 30 天 calibration log 才能信任這個 pair**——憑感覺信任 = W7 教過的 false confidence。
4. **發現「兩個都漏」的 finding type → 該類型必須升級到 High-Stakes mode**——這是 W6 Coverage Gap 的應用。

#### 對應 4 個 trust boundary 維度的覆蓋

回憶 W3 → W6 → W7 trust boundary 三部曲：

| Trust 層 | Routine pair | Complex pair | High-Stakes pair |
|---------|-------------|--------------|------------------|
| OAuth (W3) | 不相關 | 不相關 | 不相關 |
| Detector (W6) | ✅ pre-commit Semgrep | ✅ pre-commit Semgrep | ✅ multi-detector ensemble |
| Reviewer (W7) | ⚠️ 2.5/4 | ⚠️ 2.5/4 | ✅ 4/4 (cross-vendor + human) |
| Production boundary (W8) | L0-L2 | L1-L2 | L3+ |

**核心**：Reviewer pair 只解決 W7 layer 的部分問題，**不能取代 W3、W6、W8 的對應防禦**。

---

## 4. Subsystem B: Bug 修復 (Trivial)

### 屬性

| 屬性 | 值 |
|-----|---|
| 自動化等級 | 90% (auto-merge) |
| 你的角色 | 5 秒掃 PR |
| Blast radius | 小 |
| 配套機制 | **AI Performance Review System (§10) 必須啟用** |

### Trivial 的嚴格定義

**算 trivial**：
- typo（包括 docs、註解、log 訊息、變數名）
- import 順序、格式調整、lint warning
- dead code 清理（明確沒人引用的函式）
- 文件更新（已過期的 README 段落）

**不算 trivial（即使看起來簡單）**：
- 任何邏輯改動
- 任何 dependency 升級
- 任何 config 改動（.yaml / .json / .toml）
- 任何 test 改動
- 任何 crypto/ 或 security/ 目錄改動（鐵則 7）

### 流程

```
[Cron / GitHub Action] 每天跑 trivial-cleanup task
       ↓
Claude Code:
  1. 跑 codespell / ruff / golangci-lint 找 trivial issues
  2. classify_bug_severity 過濾，只挑 trivial
  3. 對每個 finding 開一個 worktree
  4. 修補
  5. 跑測試確認沒退化
  6. 開 PR with label "trivial-auto"
       ↓
[GitHub] CI 過 → 自動 merge (有 label "trivial-auto" 才允許)
       ↓
[你] 每天早上掃一眼 merged 列表
       ↓
[後台] auto-merged-prs.jsonl 紀錄此筆 (§10 Performance Review)
       ↓
[+30 天] cron job 填寫 outcome (revert? incident?)
```

### 安全限制（多層防護）

- 只在 has-label `trivial-auto` 的 PR auto-merge
- 任何 PR 改超過 5 個檔案 → 拿掉 label，回退人工 review
- 任何 PR 觸碰 `.yaml` / `.json` config → 拿掉 label
- 任何 PR 觸碰 `crypto/` / `security/` 目錄 → **絕對拿掉 label**（鐵則 7）
- 任何 PR 觸碰 customer-facing 文件 → 拿掉 label（鐵則 6）
- AI 信任分數低於閾值 → 自動降級 trust tier，停用 auto-merge（§10）

### Trust Tier 動態調整

詳見 §10 AI Performance Review System。簡述：
- TIER_3 信任分 ≥ 95：full auto-merge
- TIER_2 信任分 80-94：標準 auto-merge（有 label）
- TIER_1 信任分 60-79：auto-PR 但不 auto-merge
- TIER_0 信任分 < 60：完全停用

---

## 5. Subsystem C: Bug 修復 (Standard)

### 屬性

| 屬性 | 值 |
|-----|---|
| 自動化等級 | 50% |
| 你的角色 | approve fix proposal + final review |
| Blast radius | 中 |

### 流程

```
[客戶/同事/監控系統] 提 issue
       ↓
[你] 把 issue 轉成 SPEC（簡化版）：reproduce / expected / actual / scope
       ↓
[你] /asp-fix BUG-XXX
       ↓
Claude Code:
  1. git worktree add
  2. 寫 reproducing test (應該 fail)
  3. 確認 test 真的能 reproduce
  4. 修補直到 test pass
  5. 跑全 test suite 確認沒 regression
  6. push + gh pr create
       ↓
[GitHub] Diamond review
       ↓
[你] approve → merge
```

### 與 Trivial 的關鍵差別

**你必須把 issue 轉 SPEC（5 分鐘工作），AI 才動手**。沒有 SPEC 不修。

理由：
- standard bug 通常涉及邏輯變更，需要明確 reproduce step
- SPEC 強迫你想清楚「expected vs actual」邊界，避免修錯
- SPEC 是 Reflexion loop 的 ground truth signal (W6)

### 安全限制

- 無 reproducing test → 拒絕修補
- 修補引入新 finding（regression cascade，W6 失效模式 3）→ rollback 並 escalate
- 影響超過 3 個檔案 → 強制 HITL review，不只 final approve
- 任何 fix proposal 動到 auth、permission、access control 路徑 → 強制 HITL
- crypto/ 目錄改動 → 不得進子系統 C，必須走純 HITL（鐵則 7）

---

## 6. Subsystem D: Production Monitoring

### 屬性

| 屬性 | 值 |
|-----|---|
| 自動化等級 | 100% (read-only) |
| 你的角色 | 每天看 alert summary |
| Blast radius | 零（不寫只讀）|

### 流程

```
[Cron] 每 6 小時跑一次
       ↓
Claude Code (固定 prompt template，不用 agentic):
  1. 讀過去 6 小時的 production log
  2. 讀 metrics dashboard snapshot
  3. 對照「正常 baseline」找 anomaly (異常)
  4. 生成 summary 報告
       ↓
[Output] 寫入 ~/asp-alerts/{repo}/{date}.md：
  - Errors increased: X% (對比上週同時段)
  - Slow endpoints: 列表
  - Suspicious patterns: 列表
  - Recommended actions: 給你的待辦清單
       ↓
[你] 每天早上掃一眼，決定哪些要進子系統 C 處理
```

### Token 經濟性設計

**避免 always-on agent**：
- 不用 always-on agent
- 固定 prompt template + scheduled job
- 讀 log 時做 sampling 跟 aggregation，不全部進 context
- 預估每天 token 成本：< $1

### 安全限制（read-only 鐵則）

- Monitor agent 的 `allowed-tools` 只包含 read tools (read / grep / list)
- **絕對不能** edit / delete / API call to production
- 任何想要動的事 → 寫進 recommended actions 給你看
- Recommended actions 由你決定是否進子系統 C 處理

### Baseline 建立期

新專案啟用 D 子系統時：
- 第一週：純觀察，不發 alert（只記錄）
- 第二週起：開始對照 baseline 發 alert
- 每月 review baseline 是否需要更新（流量增長後正常 pattern 會變）

---

## 7. Skipped Subsystems (跳過的子系統)

### 子系統 E：架構設計 (Architectural Design)

**為什麼跳過**：
- W7 教過 AI 在 architectural fit + tribal knowledge 類別不可靠
- 架構決策影響數年，blast radius 極高
- 需要對 business context、團隊歷史、未來計畫的綜合判斷

**AI 在此可以做的事**：
- 輔助寫 ADR draft（你提供方向，AI 結構化）
- 列出已知架構選項的 trade-off 比較
- review 你的 ADR 找 logical gap

**AI 不可以做的事**：
- 主動產出 ADR
- 做架構決策
- commit 任何 architectural 變更

### 子系統 F：客戶 Bug 處理 (Customer Bug Handling)

**為什麼跳過**：
- 違反鐵則 6（Customer Communication Isolation）
- 客戶溝通需要理解 unspoken needs（客戶字面 bug report ≠ 真實需求）
- 信任崩潰代價極高

**AI 在此可以做的事**：
- 把 issue 分類找對應 code 段落
- 列出可能成因的內部分析報告
- 草擬待人類核准的回覆

**AI 絕對不可以做的事**：
- 直接回覆客戶
- 自動 close ticket
- 客戶可見的 PR comment 沒經過你核准就送出
- 任何 customer-facing artifact 沒有 human signature

---

## 8. Cross-cutting Rules (橫切規則)

### 8.1 鐵則 6: Customer Communication Isolation (客戶通訊隔離)

> 任何客戶可見的訊息（email、support ticket reply、客戶可看的 PR comment）必須由人類撰寫或核准後送出。
>
> AI 可以：
> - 產出**內部分析報告**給人類參考
> - 草擬**待人類核准的回覆**
> - 但**絕對不能直接送出客戶可見訊息**
>
> 違反此鐵則 = BLOCKER。

**範圍判定**：
- email 寄給客戶 email address
- ticket reply 在客戶可看到的 ticket system
- PR comment 在客戶可看到的 repo
- 任何 customer-facing 文件（手冊、release note、API doc）的對外發布

### 8.2 鐵則 7: Cryptographic Code Auto-fix Prohibition (加密碼自動修補禁止)

> 任何 cryptographic 相關 code（key 產生、加解密、簽章、雜湊、隨機數、KDF）**永遠 HITL**，AI 可以提建議但不可自動 merge。
>
> 違反此鐵則 = BLOCKER。

**範圍判定**：
- `/crypto/` 目錄全部
- `/security/` 目錄全部
- 含 `Encrypt/Decrypt/Sign/Verify/Hash/Random` 命名的 function
- 含 `SecretShare/KeyDerivation/MasterKey` 等高敏感概念

**理由**：cryptographic 失敗模式是 **silent corruption (沉默損毀)**——事後反思機制不適用，等發現時為時已晚。詳見 §11 High-Stakes Deployment Phasing。

### 8.3 Design Principle 11: AI Trust Requires Explicit Accountability Mechanism

> 員工有 performance review、法律責任、解雇威脅作為內建反思機制；AI 沒有，必須**主動建立**——auto-merge log + 30 天 outcome tracking + 動態 trust tier 降級才能讓「事後反思」真的會發生。

**實作**：詳見 §10 AI Performance Review System。

### 8.4 Design Principle 12: Customer-facing Artifacts Require Human Signature

> 任何客戶看得到的產物（報告、訊息、PR comment、support ticket reply），即使 AI 全程協助，**最終提交前必須由 human 重寫或核准**。這不只是技術限制，是 trust capital management（信任資本管理）。

**這條跟鐵則 6 的關係**：鐵則 6 是技術強制（違反 = BLOCKER），準則 12 是更廣義的指導（包含內部產物如果會被外部看到）。

---

## 9. Per-Subsystem Implementation Status

各子系統的目前實作狀態。這個 table 會隨 v4.0 ROADMAP Track G 進度更新。

| 子系統 | 設計 | 實作 | 部署 | 監控 |
|-------|-----|------|------|------|
| A 開發 | ✅ Done | ⬜ 等 v4.0 完成 | ⬜ | ⬜ |
| B Trivial | ✅ Done | ⬜ | ⬜ | ⬜ |
| C Standard | ✅ Done | ⬜ | ⬜ | ⬜ |
| D Monitor | ✅ Done | ⬜ | ⬜ | ⬜ |
| AI Performance Review | ✅ Done | ⬜ | ⬜ | ⬜ |
| 階段化部署規則 | ✅ Done | N/A | ⬜ | ⬜ |

對應 v4.0 ROADMAP Track G（見設計憲章 §6.1）。

---

## 10. AI Performance Review System

> **解決問題**：auto-merge (子系統 B) 需要「事後反思」機制，但 AI 不像員工有內建反思機制，必須**主動建立**。

### 10.1 設計

```
~/asp-ai-performance/
├── auto-merged-prs.jsonl          # 每筆 auto-merge 紀錄
├── monthly-review.md              # 月度績效檢討
└── trust-tier.yaml                # 當前 AI 信任等級
```

### 10.2 auto-merged-prs.jsonl Entry Schema

每次 auto-merge 寫一筆。30 天後 cron job 自動填 outcome：

```json
{
  "ts": "2026-05-04T10:30:00+08:00",
  "pr_number": 142,
  "repo": "Merak",
  "subsystem": "trivial-bug-fix",
  "files_changed": 3,
  "lines_changed": 12,
  "ai_classification": "trivial",
  "outcome_t30": {
    "reverted": false,
    "follow_up_bug_filed": false,
    "production_incident": false,
    "trust_score_delta": +1
  }
}
```

如果 PR 被 revert 或引發 incident：

```json
"outcome_t30": {
  "reverted": true,
  "revert_pr": 156,
  "revert_reason": "broke build on platform X",
  "production_incident": false,
  "trust_score_delta": -5
}
```

### 10.3 Trust Tier 動態降級機制

```yaml
trust_tier:
  current: TIER_2
  
tiers:
  TIER_3_FULL_AUTO:    # 信任分 ≥ 95
    auto_merge: true
    requires_label: false
    files_limit: 10
    
  TIER_2_STANDARD:     # 信任分 80-94
    auto_merge: true
    requires_label: trivial-auto
    files_limit: 5
    
  TIER_1_REVIEW:       # 信任分 60-79
    auto_merge: false
    auto_open_pr: true
    you_batch_approve: true
    
  TIER_0_REVOKED:      # 信任分 < 60
    auto_merge: false
    auto_open_pr: false
    you_must_invoke: true
```

**信任分數低於閾值自動降級**——AI 沒法主動反思，但**它的特權會自動受限**。比員工被解雇機制更直接。

### 10.4 月度 Performance Review

每月 1 號 cron job 跑：

```
本月 auto-merge 統計:
- 總 PR 數: 47
- 30 天後仍存活: 44 (93.6%)
- 被 revert: 2 (4.3%)
- 引發 incident: 1 (2.1%)

Trust score: 87/100 (上月 92)
Trust tier: TIER-2 (Standard auto-merge enabled)

Top 3 失敗類別:
1. golangci-lint 自動修補引入新 lint warning (1 次)
2. 跨檔案 typo 修正動到測試 fixtures (1 次)  
3. import 整理改變 init 順序導致初始化錯誤 (1 次)

建議:
- 第 3 類問題：暫停「import 順序整理」這個 trivial 類別
- 其他類別繼續觀察
```

### 10.5 Trust Score 計算邏輯

簡化版（v1）：
- 起始分數：100
- 每筆 auto-merge 30 天後仍存活 → +1
- 每筆被 revert（非 incident 級別）→ -5
- 每筆引發 production incident → -20
- Trust tier 邊界：每月 1 號評估，跨閾值即升降

進階版（v2，未來）：
- 不同失敗類別權重不同
- 失敗類別重複出現額外懲罰
- 引入 confidence interval（樣本太少先觀察）

---

## 11. High-Stakes Deployment Phasing

> **適用場景**：backup 加密分持系統（4 個專案，第一個進生產）。
>
> **核心觀察**：backup 系統失敗模式特別惡——**silent corruption (沉默損毀)**。平常完全沒徵兆，等真的需要 recovery 才發現所有歷史備份都是壞的。Backup 系統不適合做為 auto-fix 練習場。

### 11.1 Silent Corruption 概念

普通 production vs Backup 加密的不對稱性：

| 系統類型 | 失敗後果 | 時間性 |
|---------|---------|--------|
| 一般 production | 立即可見（用戶抱怨）| 即時發現 |
| **Backup 加密** | **沉默失敗** | 需要時才發現 = 為時已晚 |

對 backup 加密系統的具體失敗模式：
- 加密分片產生時數學錯誤 → 客戶以為備份成功 → 災難復原時才發現拼不回來
- 平常完全沒徵兆，monitor 看不出
- 等真的需要 recovery 時，**所有歷史備份可能都是壞的**

**這就是 silent corruption**——時間累積問題，traditional reflection mechanism 失效。

### 11.2 階段化部署規則

```
階段 0 (現在 — 進生產前)：
  ✅ 子系統 D (Monitor) 部署在 backup 加密所有環境
     → dev / staging / pre-prod 都裝
     → 目的：建立 baseline，學習正常 pattern
  ✅ 子系統 A (開發 pipeline) 用在新功能開發
  ❌ 子系統 B (Trivial) 不要碰 backup 加密 repo
     → 在 CyPulse / 符石對決等不敏感 repo 練
  ❌ 子系統 C (Standard) 不要碰 backup 加密
  
階段 1 (進生產後 30 天)：
  ✅ Monitor (D) 持續，建立 production baseline
  ✅ 任何 anomaly 進子系統 C 處理（半自動，不自動 merge）
  ❌ Trivial auto-merge 仍繞過 backup 加密 repo
  
階段 2 (進生產後 90 天，零事件)：
  ✅ 開始考慮 trivial auto-merge 在 backup 加密 repo 啟用
     但仍排除以下類別：
     ❌ 任何 .go/.rs 檔案（核心邏輯）
     ❌ 任何 crypto/ 目錄
     ❌ 任何 test/ 目錄
     ✅ 只允許 .md / docs / 註解 typo
    
階段 3 (進生產後 6 個月，零事件)：
  ✅ 考慮放寬 trivial 範圍
  ❌ 但 crypto 邏輯永遠 HITL（鐵則 7）
```

### 11.3 階段轉換條件

從階段 0 → 1：產品正式 GA (general available)
從階段 1 → 2：累積 30 天無事件 + 你 review 過所有 alert
從階段 2 → 3：累積 90 天無事件 + 你 review 過所有 trivial PR
從任何階段倒退：發生事件後降一階重新累積

### 11.4 鐵則 7 範圍判定（再強調一次）

任何觸及以下範圍的 PR：
- 不得 auto-merge
- 必須有 HITL approval
- 違反 = BLOCKER

範圍：
- `/crypto/` 目錄全部
- `/security/` 目錄全部
- 含 `Encrypt/Decrypt/Sign/Verify/Hash/Random` 命名的 function
- 含 `SecretShare/KeyDerivation/MasterKey` 等高敏感概念

---

## 12. Per-Project Status Tracker

> **這節是本檔案最常更新的部分**。每個專案目前在哪個 phase、啟用哪些 subsystem 都記在這。

### 12.1 Project: Backup 加密 (4 個專案)

| 屬性 | 值 |
|-----|---|
| 專案類型 | High-stakes Production |
| 部署狀態 | Pre-production（準備進生產）|
| Maturity Level | L4 |
| 階段（§11） | 階段 0 |
| **Pair Mode (§3.5)** | **High-Stakes mandatory**（cross-vendor + human）|

**啟用的子系統**：
- ✅ A 開發（無限制）
- ⬜ D Monitor（**進生產時啟用**，預先在 staging 跑建 baseline）
- ❌ B Trivial（階段 0 完全排除）
- ❌ C Standard（階段 0 完全排除）

**Promotion 條件**：
- 階段 0 → 1：產品正式 GA
- 階段 1 → 2：30 天無事件
- 階段 2 → 3：90 天無事件
- crypto/ 目錄永久 HITL（鐵則 7）

**特別注意**：silent corruption 風險，紀律最嚴格。

### 12.2 Project: Merak

| 屬性 | 值 |
|-----|---|
| 專案類型 | Production (政府/軍方)|
| 部署狀態 | Production |
| Maturity Level | L4 |
| 階段（§11） | N/A（非 backup 系統）|
| **Pair Mode (§3.5)** | **High-Stakes for auth/crypto paths**，**Complex for 一般功能** |

**啟用的子系統**：
- ✅ A 開發
- ✅ D Monitor
- ⚠️ B Trivial（排除 crypto/ + auth/ + customer-facing 文件）
- ⚠️ C Standard（排除 auth-related 變更，需 HITL）

**Promotion 條件**：保持現狀，每季 audit。

### 12.3 Project: CyPulse

| 屬性 | 值 |
|-----|---|
| 專案類型 | Dogfood Production |
| 部署狀態 | 自家使用，未對外 |
| Maturity Level | L2 |
| 階段（§11） | N/A |
| **Pair Mode (§3.5)** | **Routine for trivial bug**，**Complex for new feature** |

**啟用的子系統**：
- ✅ A 開發
- ✅ B Trivial（最寬鬆，dogfood 階段）
- ✅ C Standard
- ✅ D Monitor（自家用）

**Promotion 條件**：
- 第一個外部 user → 升 L3 並啟用更嚴格的 customer-facing 限制
- 商業化 → 啟用完整 production 限制

### 12.4 Project: 符石對決

| 屬性 | 值 |
|-----|---|
| 專案類型 | Prototype |
| 部署狀態 | 個人使用 |
| Maturity Level | L0 |
| 階段（§11） | N/A |
| **Pair Mode (§3.5)** | **Routine**（cost-effective，L0 不需 cross-vendor）|

**啟用的子系統**：
- ✅ A 開發（簡化版，無強制 SPEC）
- ⬜ B Trivial（暫不需要，等規模大了再啟用）
- ⬜ C Standard
- ⬜ D Monitor（無 production，不需要）

**Promotion 條件（W8 教的 trigger-driven）**：
- 第一個我不認識的玩家出現 → 強制升 L1
- 第一筆金流發生 → 直接升 L2+
- 上架商店（Switch / App Store）→ 升 L3
- 跑超過 60 天且還在 active 開發 → audit 是否該升 L1

### 12.5 Project: ASP (Self-hosting)

| 屬性 | 值 |
|-----|---|
| 專案類型 | Meta（用 ASP 開發 ASP）|
| 部署狀態 | Active development |
| Maturity Level | L4 |
| 階段（§11） | N/A |
| **Pair Mode (§3.5)** | **Complex**（dogfood 整套配對機制）|

**啟用的子系統**：
- ✅ A 開發（dogfood 整套 v4.0）
- ✅ B Trivial（test ground for B subsystem 本身）
- ✅ C Standard
- ⬜ D Monitor（不適用，無 production runtime）

**特別注意**：v4.0 重構期間，ASP 本身既是被改的對象也是改的工具——dogfood 純粹度極高。

### 12.6 Status 更新節奏

每月 1 號 review 一次此 §12，更新：
- Maturity Level 變動
- 階段變動
- 啟用/停用的子系統
- 新加入的專案

---

## 13. Cross-references (跨檔案索引)

### 13.1 對應 ASP v4.0 設計憲章

| 本檔案章節 | 設計憲章對應段落 |
|----------|----------------|
| §2 Subsystem Overview | §3.1 盲點 4（對抗式威脅鐵則 7 條） |
| §3-7 子系統 A-F | §6.1 ROADMAP Track G |
| §8 Cross-cutting Rules | §3.1 盲點 4 + §4.2 Design Principle 11/12 |
| §10 AI Performance Review | §10 Decision Log D-006 |
| §11 High-Stakes Phasing | §10 Decision Log D-007 |
| §12 Per-Project Tracker | (新內容，設計憲章中無對應) |

### 13.2 對應學習筆記

| 本檔案概念 | 學習筆記對應週次 |
|----------|----------------|
| Trust Boundary 4 維 | W7 Reviewer Trust Boundary |
| Closed-Loop Remediation | W6 W6 Frame |
| Coverage Gap | W6 重要 mental model |
| Dogfooding / Blast Radius / Trust Earned | W6 三個工程哲學 |
| Self-doubt ≠ Second opinion | W7 最濃縮 insight |
| Prototype Trap / Silent Corruption | W8 Production Boundary |
| Trigger-driven 升級 | W8 核心 mental model |

### 13.3 對應 Decision Log

設計憲章 §10 中與本手冊直接相關的 decisions：

- **D-005**: 4 個自動化子系統優先序 → 對應 §2 Subsystem Overview
- **D-006**: Auto-merge 配套 AI Performance Review → 對應 §10 整章
- **D-007**: Crypto Code Auto-fix 全面禁止 → 對應 §8.2 鐵則 7 + §11

---

## 14. How to Use This File (使用說明)

### 14.1 工作流

**日常使用**：
- 每天早上：看 §12 Per-Project Status，掃 D Monitor 的 alert summary
- 每天早上：掃 B Trivial 隔夜 merged PR
- 每月 1 號：review §10 Performance Review、更新 §12 Status
- 新事件發生：先確認對應子系統，按子系統 §3-7 的流程處理

**新專案啟動時**：
1. 評估專案類型（production / dogfood / prototype）
2. 決定 maturity level
3. 在 §12 加新一節記錄狀態
4. 啟用對應子系統

**遇到「該不該自動化」的決策時**：
- 查 §2.2 Trust Boundary 判定表
- 查 §8 是否觸發橫切規則（鐵則 6 / 7）
- 不確定時 → 不自動化

### 14.2 給 Claude Code 的使用方式

開新 session 處理維運任務時：
- 處理 §3-7 任一子系統的工作 → paste 該子系統章節（單章節 50-150 行，不超過）
- 處理跨子系統的決策 → paste §2 Overview + §8 Cross-cutting Rules
- 處理 backup 加密相關 → 必須 paste §11 High-Stakes Phasing
- 不要全 paste（違反 W4 concise 原則）

### 14.3 更新節奏

| 章節 | 更新頻率 |
|-----|---------|
| §1 Goal | 不變（除非範圍重大調整）|
| §2 Subsystem Overview | 偶爾調整（如新增子系統）|
| §3-7 子系統設計 | 設計穩定後不變 |
| §8 Cross-cutting Rules | 新威脅出現時補 |
| §9 Implementation Status | v4.0 Track G 推進時更新 |
| §10 AI Performance Review | 每月評估邏輯是否需調整 |
| §11 High-Stakes Phasing | 階段轉換時更新 |
| §12 Per-Project Status | **每月 1 號 review，新事件即時更新** |
| §13 Cross-references | 新增交付物時補 |

### 14.4 警告與提醒

- **不要**讓 §12 Per-Project Status 過時——這是本檔案的活躍章節
- **不要**忽略月度 Performance Review——AI 信任管理是 ongoing 的
- **不要**鬆綁鐵則 6 或 7——這兩條沒有「漸進放寬」選項
- **不要**在 backup 加密系統跳階段——silent corruption 不可逆
- **不要**把本檔案當設計憲章用——本檔案是 operational playbook，設計依據在設計憲章
