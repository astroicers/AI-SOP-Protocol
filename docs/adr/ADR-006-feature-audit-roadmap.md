# [ADR-006]: ASP 全專案功能 Audit Roadmap (v4.2 → v5.0)

| 欄位 | 內容 |
|------|------|
| **狀態** | `Draft` |
| **日期** | 2026-05-10 |
| **決策者** | astroicers（待確認） |
| **觸發事件** | v4.1.1 cleanup wave 1+2+3 完成後，repo 進入「架構轉型中段」狀態，需要決定後續 feature 取捨方向 |
| **關聯 ADR** | ADR-005（GA 前 holistic review，本 audit 同樣由獨立 agent 執行） |

---

## 背景（Context）

ASP 在 2026-04-29 → 2026-05-10 經歷三次連續重構：

1. **v4.0**：profile→skill 抽離，CLAUDE.md 309→100 行
2. **v4.1.0**：SPEC-004 multi-agent worktree 硬性隔離 GA
3. **v4.1.1**：review-fix patch + cleanup wave 1+2+3（v3.7 leftover、archive、profile→skill 收尾、agent yaml 裁剪）

當前狀態（2026-05-10 cleanup wave 3 結束後）：
- 23 個 skill / 18 個 profile / 6 個 maturity level / 86 個 Makefile target / 17 個 template / 19 個 doc
- **真實使用訊號弱**：23 個 skill 中 17 個全 git history 只 commit 一次（建立後從未迭代）
- **過剩集中三處**：(A) ~5 個 skill 與 global_core.md 重複、(B) `task_orchestrator + multi_agent + pipeline` 三 profile 互引嚴重、(C) ~12 個 Makefile target 無人引用
- L0–L5 6 級**過度細分**：L0/L1、L4/L5 邊界模糊
- 預估瘦身潛力：**~4,800 行 / ~14 檔 / ~21 個 Makefile target = 整體維護面積 -30~35%**

但**現在不是急著動的時機**：
- v4.1.1 才 ship 一天，wave 1+2+3 cleanup 也才剛完成 7 個 commit 沒推
- 馬上又開 v4.2 改 profile/skill 會讓 release cadence 失序
- ADR-005（GA 前 holistic review）還是 Draft——應該先把「制度」立起來，下次大動作才不會像 v4.1.0 那樣 over-claim

本 ADR 的目的是**將 audit findings 制度化為 v4.2 → v5.0 的執行 roadmap**，並要求每個 v4.x release 前先實踐 ADR-005 的 holistic review。

---

## 評估選項（Options Considered）

### 選項 A：立刻執行 v4.2.0 高 ROI 項目（5 項）

- **優點**：trim down 速度快（~1 週）、馬上看到效果
- **缺點**：違反 ASP 自己的「ADR 未定案禁止實作」鐵則；wave 3 才 commit 還沒 push、再疊新 release 的 cadence 危險；ADR-005 還是 Draft，沒有制度化的 holistic review 把關，可能重蹈 v4.1.0 over-claim 覆轍
- **風險**：高 — 七天內第三次 release 會讓使用者 changelog fatigue

### 選項 B：把 audit 寫成 ADR (Draft)，等 review + Accept 後再動（本決策）

- **優點**：符合鐵則「ADR 未定案禁止實作」、給人類 review 時間、與 ADR-005 holistic review gate 同步立制度、release cadence 健康
- **缺點**：執行時間延後 1-2 週
- **風險**：低 — audit findings 的 evidence 都基於 grep + git log 客觀證據，不會因延後而失效

### 選項 C：分項逐個討論（不寫 roadmap）

- **優點**：可以針對單項深入辯論
- **缺點**：失去「整體視角」（部分項目互相關聯，例如 task_orchestrator + multi_agent + pipeline 必須一起整併才有意義）；缺乏優先級排序，容易做了低 ROI 高風險的項目
- **風險**：中 — 容易碎片化、缺乏全局最佳化

---

## 決策（Decision）

**選擇選項 B**：將 audit findings 寫成本 ADR 作為 v4.2 → v5.0 的執行 roadmap，狀態 Draft，等待人類 review。

### 執行原則

1. **每個 v4.x release 前必跑 ADR-005 holistic review**（GA gate）
2. **本 ADR Accept 後**才開始 v4.2 第一項實作；每完成一個 item 跑一次完整 audit_health + lint + test
3. **Item 之間有依賴的不可分開做**（例如 task_orchestrator + multi_agent + pipeline 三檔整併）
4. **每個 item 完成後 commit + push**，避免堆疊（v4.1.1 已踩過這個雷）

### Roadmap

#### v4.2.0（高 ROI、~1 週、低風險）

| # | 行動 | 對象 | 削減 | 風險 | Done When |
|---|------|------|-----|------|-----------|
| 1 | REMOVE 4 重複 skill | `asp-fact-verify` (155) + `asp-assumption-checkpoint` (128) + `asp-bug-classify` (161) + `asp-change-cascade` (208) | -652 行 + 4 個 SKILL.md router 入口 | 低 | grep 確認 global_core 內嵌版能取代「使用者主動 /skill 呼叫」入口；SKILL.md router 表移除 4 個項目 |
| 2 | REMOVE 3 dead template + 空目錄 | `architecture_spec.md` / `workflow-design.md` / `gate_report.md` / `handoff/` 空目錄 | -274 行 + 1 死引用 | 零 | 4 個 git rm + verify multi-agent-architecture.md 對 handoff 的引用改寫 |
| 3 | REMOVE 9 無引用 Makefile target | agent-status / agent-reset / agent-track-status / agent-team-recommend / task-* (3) / agent-memory-* (3 deprecated stub) | -80 行 + help message 清爽 | 低 | grep 全 repo + user-level 確認真零引用；help message 重排為 6 類 |
| 4 | CONSOLIDATE 4 doc-new → 1 | `srs-new` / `sds-new` / `uiux-spec-new` / `deploy-spec-new` → `doc-new TYPE=` | -3 個 target | 低 | autopilot.md 改 1 處引用；測試 4 種 TYPE 都 work |
| 5 | 修 README vs where-to-start 重疊 | 用對照表標清楚分工 | 重疊 30% → ~5% | 零 | 兩 doc 開頭加「這頁回答什麼問題」標頭 |

**v4.2.0 預估總瘦身：~1,000 行 / ~7 檔 / ~13 target**

#### v4.3.0（中 ROI、~2-3 週、中風險）

| # | 行動 | 對象 | 削減 | 風險 |
|---|------|------|-----|------|
| 6 | CONSOLIDATE 三大 profile | `task_orchestrator + multi_agent + pipeline` 按「載入時機」重切為 `orchestration_core / pipeline_gates / multi_agent_runtime` | 2,315 → ~1,000 行 | **中**（cross-ref 30+ 處要重做；建議「先寫新版 + 保留原檔 rollback」） |
| 7 | REMOVE autopilot.md profile | 邏輯收回 asp-autopilot skill | -566 行 | 低 |
| 8 | CONSOLIDATE asp-escalate → asp-handoff | P0-P3 表搬入 ESCALATION YAML schema 段 | -159 行 | 低 |
| 9 | CONSOLIDATE asp-qa → asp-dev-qa-loop | qa 變單模組分支 | -83 行 | 低 |
| 10 | REMOVE asp-security skill | 改路由到 `make security-scan`（Semgrep 才是真執行體） | -71 行 | 低 |
| 11 | REFACTOR validate-profile.sh | 219 行 bash → ~50 行 jsonschema | -170 行 | 中（要寫 schema） |
| 12 | CONSOLIDATE 3 concept docs | `task-orchestration.md` + `spec-driven-dev.md` + `development-modes.md` → `concepts.md` 或併入 README | -200 行 | 低 |

**v4.3.0 預估總瘦身：~2,500 行 / ~5 檔**

#### v5.0.0（重大重構、需子 ADR）

| # | 行動 | 對象 | 削減 | 為何 v5 |
|---|------|------|-----|--------|
| 13 | L0-L5 → L0-L3 4 級 | 砍 level-2 + level-5、合併內容到鄰近級 | -2 yaml + 心智負擔大降 | 影響 .ai_profile schema，需要 migration tool |
| 14 | autonomous_dev + vibe_coding → autonomy_boundaries.md | 兩 profile 都是「決策邊界宣言」、大量重複 | -200 行 | 影響 autopilot 等多個依賴 |
| 15 | architecture / multi-agent-arch / production-ops 三檔重整 | architecture（核心）+ ops-playbook（reference）兩檔 | -400 行 | 大幅改 outline，需要設計 review |

**v5.0.0 預估總瘦身：~600 行 / 4 檔 / 2 yaml**

#### 累積規模（v4.2 + v4.3 + v5.0 完成後）

| 維度 | Before (v4.1.1) | After (v5.0) | 削減 |
|---|---|---|---|
| Skill 數 | 23 | 14 | -9（39%） |
| Skill 行數 | 3,839 | ~2,400 | -1,400 |
| Profile 數 | 18 | 13 | -5 |
| Profile 行數 | 5,961 | ~3,500 | -2,460 |
| Template 數 | 17 + 空目錄 | 13 | -4 |
| Template 行數 | 2,790 | ~2,500 | -290 |
| Makefile target 數 | 86 | ~65 | -21 |
| Doc 行數（docs/） | 3,671 | ~3,000 | -670 |
| Maturity Levels | 6 | 4 | -2 yaml |
| **總行數削減** | — | — | **~4,800 行** |
| **總檔案削減** | — | — | **~14 檔** |
| **維護面積削減** | — | — | **~30-35%** |

---

## 明確不該動的（KEEP-AS-IS 清單）

audit 中明確列出**不該因為 cleanup 動到的核心**：

- 5 大核心 skill：`asp-plan` / `asp-ship` / `asp-gate` / `asp-audit` / `asp-review`（git 證據顯示真實使用入口）
- `session-audit.sh`（v4.x enforcement 支點）
- 3 個 runbook（user-facing onboarding，只升級內容不刪）
- SPEC-004 multi-agent worktree 整套（v4.1.0 GA、perf benchmark + rollback 已成熟）
- `level-0.yaml`（Spike，是 v4.0 辨識特色，timebox 概念對使用者價值高）
- RAG / telemetry / ai-performance 三子系統（條件啟用、不互依，分開反而簡單）
- Iron Rules A/B/C / `.asp-bypass-log.ndjson`（v4.0 安全主幹）
- Item 7 的 3 個 frontend/api/design profile（使用者已確認「為了設立前端與 API 的邊界與方向」必要）

---

## Audit 方法論（避免重蹈 v4.1.0 over-claim）

每個 v4.2/v4.3 release 必須遵循 ADR-005 的 holistic review gate：

1. **執行前**：跑獨立 reality-checker agent 對「將要動的範圍」做 evidence collection（grep + git log）
2. **執行中**：每完成一個 item 跑 `make test + lint + audit-health`
3. **執行後**：在打 release tag 前，獨立 reality-checker 對 SPEC vs 實作 vs 文件做三層級 holistic review
4. **CHANGELOG 誠實**：Done When 標 `[x]` 必須以「測試 cover 該場景」為準，不以「實作宣稱完成」為準

如果遺漏，下一輪 review-fix patch 會再次出現（v4.0 → v4.0.1、v4.1.0 → v4.1.1 已是慣例）。

---

## 後果（Consequences）

### 正面

- v4.1.1 之後的演進方向有明確 roadmap，不會臨時起意做大動作
- 每個 release 範圍可控（v4.2.0 只做 5 項、v4.3.0 只做 7 項），符合 ASP 自己的「小步前進」原則
- ADR-005 + ADR-006 兩個 process ADR 一起發 → 立起「audit + holistic review」的循環機制
- 整體瘦身 30-35% 的目標明確，可量化驗證

### 負面

- v4.2.0 第一個高 ROI commit 至少延後 3-5 天（等本 ADR Accept）
- 如果使用者半年後對某項目改變主意，需要修本 ADR 而不是直接動手
- audit 的 evidence 是 2026-05-10 snapshot，半年後可能部分過時 — 需在每個 v4.x release 前再 spot-check 一次

### 對既有流程的影響

- `docs/ROADMAP.md` 須擴充：把本 ADR 的 v4.2/v4.3/v5.0 三波列為正式 milestone
- `make help` 在 v4.2 #3 後會明顯減項，需要 release notes 提醒
- v4.3 #6 三大 profile 整併會影響 user-level `~/.claude/asp/profiles/` sync — install.sh 需要對舊 profile 名稱做 cleanup（rsync --delete 自動處理，但要 release notes 強調）

---

## 落實時程

| 階段 | 項目 | 排程 |
|------|------|------|
| ADR-006 接受 | 人類 review 本 ADR 並改 Accepted | TBD（人類決定） |
| ADR-005 同步 Accept | GA 前 holistic review 制度化 | 本 ADR Accept 同時 |
| ROADMAP.md 更新 | v4.2 / v4.3 / v5.0 milestone 寫入 | ADR Accept 後 |
| v4.2.0 執行 | 5 個高 ROI item，~1 週 | ADR Accept 後第 1-2 週 |
| v4.2.0 GA review | 獨立 reality-checker 三層 review | v4.2.0 release time |
| v4.3.0 執行 | 7 個中 ROI item，~2-3 週 | v4.2.0 ship 後 1 個月 |
| v5.0.0 執行 | 3 個重大重構，需子 ADR | v4.3 ship 後 ≥3 個月 |

---

## 關聯文件

- 觸發 audit 的 cleanup 序列：commits `5402535` (wave 1) / `8402e65` (wave 2) / `27488c7` (wave 3 group C) / `499ecc1` (wave 3 group A) / `80de27c` (wave 3 group B) / `efe7787` (wave 3 item 1)
- ADR-005：GA 前 holistic review gate（與本 ADR 互為對偶 process ADR）
- 完整 audit findings：本 ADR 的 evidence 由獨立 general-purpose agent 於 2026-05-10 跑出，agent ID `afd9f8b30c5449c7f`
- ROADMAP.md：將在本 ADR Accept 後更新，列入 v4.2/v4.3/v5.0 milestone

---

## 變更歷史

- 2026-05-10：初稿，狀態 Draft，等待人類 review

---

## 給人類 reviewer 的提示

審本 ADR 時請特別注意：

1. **roadmap 三波的優先級是否對齊你的時間預算**？v4.2 ~1 週、v4.3 ~2-3 週、v5.0 ≥3 個月——若你想加速或延後某波，請改 §落實時程
2. **「明確不該動」清單是否漏了什麼**？特別是 Item 7 的 frontend/api/design profile 已確認保留
3. **每個 item 的 risk 評估是否合理**？v4.3 #6 三大 profile 整併標 medium，是否該升 high？
4. **是否同意「ADR-005 + ADR-006 一起 Accept」的綁定關係**？process ADR 兩個一組才有意義
5. **是否要加 ADR-007「audit cadence」？** 例如「每 6 個月跑一次全專案 feature audit」制度化

審完後將狀態改為 `Accepted`（人類手動，AI 不可自改），並在 ROADMAP.md 補上 v4.2/v4.3/v5.0 milestone。
