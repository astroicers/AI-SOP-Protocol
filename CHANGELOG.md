# Changelog

All notable changes to AI-SOP-Protocol will be documented in this file.

## [Unreleased]

### Security

- **SPEC-007 — 封 inbox-ingest 無授權旁路（ADR-012 INV-2/DP8，關閉 T-14）**：`inbox-ingest.sh` 自此為 held-mode——SessionStart 只回報 pending 外部任務（held、保持 `pending`），**不再自動注入 ROADMAP.yaml、不再標 `ingested`**（取代 v4.3.0 P1 的自動注入行為）。直推 `.asp-task-inbox.json` 到 main 不再能繞過信任模型進入 autopilot 執行佇列；外部任務的人類授權路徑由 SPEC-009（triage-accept）/ asp-op pivot 提供。`session-audit.sh` A15.1 由 INFO 升為 WARNING 並改 held 語意。順帶消除 inbox-ingest 對 ROADMAP 的無鎖寫入競態。測試：`test_inbox_ingest_no_bypass.sh`（14 斷言，含 T-14 攻擊模擬）；`test_task_inbox.sh` 由舊注入契約改寫為 held 契約（8 斷言）。

### Security (continued)

- **SPEC-008 — autopilot 外部來源 provenance 閘（ADR-012 INV-2/DP2）**：`autopilot.md` Phase 2 於既有 ADR 閘前新增 provenance 檢查——帶外部來源標記（`source_type` ≠ manual 或 `triggered_by` ∉ human/maintainer）的 ROADMAP 任務，須有人類 **Accepted** ADR 才可執行（外部任務不適用 FIRM 🟡 豁免、不自動建 Draft ADR）；DP8 過渡期外部非架構任務一律 blocked（待 SPEC-009 triage-accept）。人類手寫任務的既有機制逐字不變（DP3）。這是 SPEC-007（producer 側）之後的 consumer 側第二層防線。`asp-autopilot` skill 前置檢查表同步。測試：`test_autopilot_provenance_gate.sh`（15 斷言文字契約，TDD 先紅後綠）。

- **SPEC-009 — 人類 inbox-triage 授權通道（ADR-012 DP2/DP4；DP8 過渡期終止）**：新增 `make inbox-triage`——人類逐件核准/駁回 held 外部任務；核准寫入 ROADMAP（帶 `triage_accepted_by/at` + provenance 標記）並由**人類自行 commit**（該 commit 作者即機械可驗證的授權記號）。autopilot provenance 閘擴充 triage 分支：以 `git log -S` 驗證 entry 引入 commit 作者，撞 bot 樣式（`[bot]`/asp-op/autopilot）→ blocked（DP4 bot 不可自核）；人類 triage → 放行、管線深度仍依既有 severity 分類（DP2）。**外部非架構路徑自此啟用（DP8 過渡期結束）**。測試：`test_inbox_triage.sh`（20 斷言）；SPEC-008 契約 15/15 不回退。

### Fixed

- **A8.3 逾期 tech-debt 假陽性**：session-audit 的 tech-debt 掃描把 `global_core.md` 等框架文件內的「格式範例」標記（範例日期已過期）誤報為 3 筆逾期 HIGH。掃描改排除框架文件路徑（`.asp/profiles/`、`.asp/templates/`、`.claude/skills/`、`docs/runbooks/`）；修復後實際可動作逾期債為 0。回歸測試：`test_tech_debt_scan_exclusions.sh`（7 斷言，含管線重演與「測試檔自身不得成為新假陽性」防護）。
- **lint 既有債清零**：移除 `test_converge_crypto_gate.sh` / `test_spec_004_scope_guard.sh` 中未使用的輸出擷取變數（SC2034）；`make lint` 全綠（RC=0）。

### Changed

- **CONTEXT.md 補錄 ADR-012 詞彙**：新增 Provenance（來源出處）、Task Inbox（任務收件匣）、Held（待授權暫置）、Triage-accept（人類分診核准）四詞條（含避免使用同義詞），同步詞彙速查表。

### Added

- **ADR-012 — operator↔autopilot 互動信任模型（Accepted）**：provenance-scoped、授權隨架構影響縮放（外部架構級→Accepted ADR；外部非架構→人類 triage-accept；人類手寫 ROADMAP 任務機制完全不變）。新增 INV-1（autopilot 僅人類啟動）/ INV-2（外部工作須人類放行）兩不變量與 DP1–DP8 決策點；威脅模型新增 **T-14**（external-artifact → autopilot poisoning）併入 `threat-model-v4.0.md`；ADR-001 Relations 補記 C2 profile/skill 漂移。

## [4.3.0] - 2026-05-28

### Added

- **v4.3 Profile/Skill 整併**（ADR-007）：消除三角循環依賴，降低 Cognitive Load。`multi_agent.md`（436 行）合入 `task_orchestrator.md` Part G，成為唯一 multi-agent 協調 canonical source；`asp-escalate`（159 行）合入 `asp-handoff`（新增 ESCALATION 決策樹與 P0-P3 執行流程）；`asp-qa`（83 行）合入 `asp-dev-qa-loop`（新增 Mode B 獨立 QA 驗證）；`asp-security`（71 行）合入 `asp-ship` Step 9（新增 OWASP Top 10 快速掃描）。淨變更：4 個檔案刪除，-814 行，Skill 數量從 20 降至 17。
- **scope-guard PreToolUse hook（N2）**：`.asp/hooks/scope-guard.sh` 在每次工具呼叫前驗證 `ASP_AUDIT_ROOT`，防止 worktree 跑到錯誤目錄。
- **dispatch disk precheck（B4）**：`dispatch.sh` 啟動時檢查磁碟空間，不足時以 exit 4 fail-closed（原 exit 4 重新定義）。
- **完整產品生命週期自動化（P0-P4）**：五個里程碑打通從開發到發布的全自動化路徑。
- **P0 — auto-PR**：autopilot 完成任務後自動建立 `asp/TASK-{id}-{slug}` feature branch、`git push origin asp/*`、`gh pr create --draft`；鐵則更新：`git push origin feature/* 或 asp/*` 明確允許，push to main 仍禁止。
- **P1 — Task Inbox**：`.asp-task-inbox.json` append-only 佇列機制。`inbox-ingest.sh` 在 SessionStart 自動注入 pending 任務至 ROADMAP.yaml（`source.ref` 去重、`sla_hours→priority` 映射 0/24/72/>72→P0-P3）。`task-inbox-schema.json` 定義 inbox JSON Schema，`test_task_inbox.sh` 涵蓋 8 個測試案例。
- **P2 — GitHub Actions CI 模板**：`.asp/templates/github-actions-ci.yml` 含三個 job（unit test / audit-quick / gitleaks 秘密掃描），`make ci-install` 一鍵複製至 `.github/workflows/asp-ci.yml`。
- **P3 — 每日健康審計**：`daily-audit.sh` 生成結構化 `.asp-daily-report.md`（ROADMAP 進度、ADR 狀態、audit blockers、inbox 狀態、24h git 活動）；`cron-setup.md` 提供 cron + GitHub Actions schedule 設定指南；`make daily-audit` 指令。
- **P4 — asp-release Skill**：四步驟 HITL 發布流程——Conventional Commits 版本 bump 判斷（major/minor/patch）、CHANGELOG.md 自動更新、`release/vX.Y.Z` branch 與 Draft PR 建立；AI 禁止 push tag 或自行 merge。
- **ADR FIRM 中間態完整落實**：Draft → FIRM → Accepted 三態機制傳播至 13 個執行路徑檔案（7 個 profiles、3 個 skills、2 個 scripts、2 個 CLAUDE.md）。FIRM ADR 可合法 commit（需 Verification Evidence），audit 輸出 🟡 YELLOW FLAG；Draft 鐵則（禁止生產代碼）維持不變。新增 `asp-review-checklist.md`（6 面向審查清單 + 結構化 finding 格式），`asp-review.md` 精簡為流程控制器（91 行）。
- **Windows 原生安裝支援**：新增 `.asp/scripts/install.ps1` 與 `uninstall.ps1`（PowerShell 5.1+），對應 `install.sh` 的兩階段安裝流程。Hook command 透過 Git for Windows 的 `bash.exe` 執行 `.sh` 腳本。
- **Windows 安裝文件**：`docs/install-windows.md` 涵蓋 WSL2 推薦路線、PowerShell + Git Bash 原生路線、驗證、移除、FAQ。
- **N2 — PreToolUse scope-guard**：新增 `.asp/scripts/multi-agent/scope-guard.sh`，在 Worker 執行 Write/Edit/NotebookEdit 前攔截，比對 TASK manifest 的 `scope.allow` / `scope.forbid`；違規 exit 2 + 自動寫入 bypass log；無 manifest 時 fail-open（不影響非 multi-agent session）。`.claude/settings.json` 加入 PreToolUse hook 完成 SPEC-004 N2 整合。
- **B4 — dispatch 磁碟空間動態預檢**：`dispatch.sh` Stage 4 實作 `df -BM` + `repo_size × max_parallel × 1.2/1.5` 動態門檻；空間不足 exit 4，警告區 stderr 警告繼續執行；支援 `ASP_MOCK_DISK_AVAIL_MB` / `ASP_MOCK_REPO_SIZE_MB` 測試環境覆蓋。SPEC-004 Done When #1、#8 標記為 `[x]`（21/21）。

### Changed

- **`task_orchestrator.md` 擴充為唯一 multi-agent 協調 source**：Part G 從 ~35 行 stub 擴充為 ~370 行，包含 Orchestrator 職責、角色分派、Task Manifest、worktree 隔離入口、並行軌道規劃、MCP 安全邊界、Worker 完成流程。
- **`asp-handoff` 新增 ESCALATION 決策樹**：Type 3 ESCALATION 新增完整 P0-P3 觸發點對照表、執行流程、標準回覆格式；description 新增 escalation 觸發詞。
- **`asp-dev-qa-loop` 新增 Mode B**：新增獨立 QA 驗證模式（單 agent 或手動觸發），6 步驟流程含 checksum 比對與覆蓋率檢查。
- **`asp-ship` Step 9 補強 OWASP**：Step 9 分為 9a（敏感資訊掃描）和 9b（OWASP Top 10 A01/A02/A03/A05/A07/A09 快速掃描，僅針對安全相關模組）。
- **`make diagram` 改為 HTML 輸出**：移除 `mmdc`（mermaid-cli）依賴，改為純 bash 生成 HTML，透過 mermaid.js CDN 渲染。同時支援 `docs/architecture.md`（4 個圖）與 `docs/multi-agent-architecture.md`（6 個圖），輸出至 `docs/architecture.html`（gitignore，不追蹤）。修復原 awk 實作將多個 mermaid 區塊拼接成單一檔案的 bug。
- **README 大幅精簡**：從 438 行縮至 ~120 行，聚焦安裝、三步啟動、預設行為、鐵則四項精華；深入內容指引至 `docs/`。原內容（強制力四層、Iron Rules 7 條、23 個 skill 分類、worktree 元件表、profile 分層樹、設計哲學）改以連結指向既有文件。
- **鐵則更新**：`git push origin feature/* 或 asp/*` 由 autopilot auto-PR 流程允許；`denied-commands.json` 改為細粒度規則（`push origin main`、`push --force`、`rebase`、`pr merge`、`rm -rf` 分開列出）。

### Removed

- **`multi_agent.md` profile 刪除**：內容完整移入 `task_orchestrator.md` Part G（v4.3 起為唯一 canonical source）。
- **`asp-escalate` skill 刪除**：邏輯合入 `asp-handoff` ESCALATION 類型。
- **`asp-qa` skill 刪除**：邏輯合入 `asp-dev-qa-loop` Mode B。
- **`asp-security` skill 刪除**：OWASP 掃描邏輯合入 `asp-ship` Step 9b。

## [4.1.1] - 2026-05-10

獨立 reality-checker 對 v4.1.0 GA 做 holistic review，抓出 4 個真實問題 + v3.7 殘留 + SPEC Done When 虛報。本版誠實修正。

### Fixed

- **`make agent-worktree-list / gc / gc-dry-run` 缺少 ASP_AUDIT_ROOT 注入** (Makefile.inc 第 744-754 行)：使用者直接 `make agent-worktree-list` 會 exit 7。已對齊 `agent-rollback` 的 `ASP_AUDIT_ROOT="$$(git rev-parse --show-toplevel)"` 注入模式。功能首次真正可用。
- **`asp-dispatch.md` Step 6 仍指示「鎖定 .agent-lock.yaml」** (`.claude/skills/asp/asp-dispatch.md` 第 71 行)：v3.7 廢止機制的殘留指示，會誤導 AI 跑 `/asp-dispatch` skill 時做廢止行為。改寫為 dispatch.sh 的呼叫範例 + ASP_AUDIT_ROOT 設定 + 廢止警告。
- **退出碼 4 三處定義不一致**：SPEC §📤「Worktree 殘留 > max_parallel」/ dispatch.sh「磁碟不足」/ multi_agent.md 漏寫 4 與 8。已校對：SPEC §📤 改為 dispatch 階段語意（磁碟空間不足，v4.2 實作）、dispatch.sh 註解標明 RESERVED for v4.2、multi_agent.md 退出碼速覽含完整 1/2/3/4/5/6/7/8/13。
- **telemetry.md 主表格漏 `multi_agent.dispatch_rejected` 和 `multi_agent.rollback`**：兩個事件都已實作但只在 schema 範例出現、主表沒列。補上完整對應。

### Deprecated

- **v3.7 file-lock Makefile targets** (`agent-unlock` / `agent-lock-gc` / `agent-locks`)：改寫為 deprecation stub，印警告 + 指向 v4.1+ worktree 機制 + 提示 `rm .agent-lock.yaml` 安全清理。**不直接刪除**，避免破壞既有 user 升級路徑。v5.0 移除。
- **`docs/runbooks/enterprise-feature.md` 並行軌道協議**：原本用 `.agent-lock.yaml` YAML 範例 + `make agent-lock-gc`，改寫為 SPEC-004 worktree 工作流（dispatch.sh + converge.sh）。

### Documentation Honesty Fix

- **SPEC-004 Done When #1 與 #8 從 `[x]` 改為 `[⚠️] partial`**：v4.1.0 GA commit message 自稱「18/18 = 100%」是虛高計數。Reality-checker 正確指出：
  - **N2 (S7) Worker runtime scope 違規攔截**：實作只有「audit-write.sh 手動 write」smoke test，缺 end-to-end runtime 攔截（需要 PreToolUse hook 整合）。
  - **B4 (S13) 磁碟空間動態預檢**：dispatch.sh Stage 4 是「Skipped here」placeholder，連 `df` 呼叫都沒有；測試 comment 宣稱有但沒對應 Test body。
  - 真實完成度：**16 完整 + 2 partial = 16/18 (89%)**，不是 100%。N2 + B4 排程 v4.2。
- **SPEC-004 Done When #1 assertion 計數從 96 修正為 113**（spec-004 測試檔，6 檔；含 install_precheck 22 共 135）。

### Tests

無新測試（v4.1.1 是 review-fix release）；既有 173 bash + 50 pytest = 223 全綠。
shellcheck `-S warning` 通過。
audit-health 0/0/0。

### v4.2 規劃（review 確認）

- **B4 dispatch 階段磁碟空間動態預檢**：實作 `df -BM` + `repo_size × max_parallel × 1.2/1.5` 動態門檻，emit exit 4
- **N2 PreToolUse hook 整合**：Worker 修改 forbid 路徑時 runtime 攔截、自動寫 bypass log
- **`make agent-rollback` 確認提示**：不帶 `--dry-run` 時先預覽 + `ASP_ROLLBACK_CONFIRM=1` escape hatch
- **Telemetry schema 統一**（已在 v4.1.0-alpha entry 提過）

### Process Lesson

v4.1.0 GA 是 AI 在 7 batch 連續實作後自評「18/18」並打 tag。獨立 reality-checker review **抓到 4 個 documentation drift / scope 偷渡**。

教訓：**SPEC Done When 勾選必須以「測試實際 cover 該場景」為標準**，不能以「實作宣稱完成」為標準。本次校對機制已用 v4.1.1 落實。下次：在打 GA tag 前，由獨立 agent 對 SPEC-vs-實作做 holistic review，是 release gate。

## [4.1.0] - 2026-05-10

SPEC-004 Done When 18/18 = 100% — v4.1.0 正式版。在 4.1.0-alpha 基礎上補完三條收尾項。

### Added — 收尾交付

- **`install.sh` 兩階段 runtime precheck（Done When #13）**：新增 `precheck_runtime()` 函式於 Phase 0，檢查 git ≥ 2.20 / bash ≥ 4.4 / jq ≥ 1.6 / python3 ≥ 3.10，缺任一者 exit 13。提供 `ASP_SKIP_PRECHECK=1` escape hatch（仍會印警告）。`version_at_least()` 用 GNU `sort -V`，POSIX 安全。
- **`.asp/scripts/multi-agent/rollback.sh`（Done When #9）**：依 SPEC §🔄 Rollback Plan 實作。force-remove 所有 in-flight worktree、刪除 `feat/spec-004-*` branches、驗證 base HEAD 未動、保留 task manifests 作為 forensic record、emit `multi_agent.rollback` telemetry。支援 `--dry-run`。
- **`make agent-rollback / agent-rollback-dry-run / spec-004-rollback-test`** Makefile targets
- **`make lint` 含 shellcheck（Done When #2）**：`lint` target 擴展為「先語言原生 linter（go/python/npm），最後 shellcheck 對 `.asp/scripts/multi-agent/*.sh` 與 `tests/*.sh`」；shellcheck 不在時 fallback `bash -n` syntax check
- **3 個新 bash 測試檔**：
  - `test_install_precheck.sh`（22 assertions）：cover version_at_least 邊界 + 缺/過舊 binary 偵測
  - `test_spec_004_rollback.sh`（15 assertions）：cover full rollback、dry-run、partial converge 後 base 不 regress
- **`.asp/VERSION`** → 4.1.0

### Fixed

- **shellcheck SC2115 警告**（11 個 test 檔的 `rm -rf "$TEST_DIR"/*` → `rm -rf "${TEST_DIR:?}"/*`）：理論上 `mktemp -d` + `set -euo pipefail` 不會出空 var，但加 `:?` 是更安全的防呆
- **`audit-write.sh` 接受 escalation log type** 已在 4.1.0-alpha 完成；在 rollback.sh 中新增 `multi_agent.rollback` event 證明擴展性 OK
- **`test_spec_004_audit_write.sh` Test 12 的 ASP_AUDIT_ROOT 加 export**：避免 shellcheck SC2034「unused var」誤判（var 是給 source 進來的 function 用）

### Tests

新增 2 個 bash 測試檔，37 新 assertions：
- `test_install_precheck.sh`：22 項
- `test_spec_004_rollback.sh`：15 項

專案總測試：bash 173 + pytest 50 = **223 passing**。
Audit：🔴 0 / 🟡 0 / 🟢 0。
Lint：✅ shellcheck -S warning 通過。

### Done When（SPEC-004 共 18 條）

✅ **18 / 18 = 100%**

### v4.2 規劃預告

- Telemetry schema 統一（`multi_agent.*` 平鋪 vs `session_start/bypass/gate_*` nested 二選一）
- N2: PreToolUse hook 整合，runtime 強制 scope.forbid
- v3.7 殘留機制（`agent_memory.md` 等）正式 deprecation 流程

## [4.1.0-alpha] - 2026-05-10

SPEC-004 Multi-Agent Worktree 硬性隔離正式交付。Multi-agent 並行從 v4.0 過渡期的「單軌序列執行」升級為真正的檔案系統層級隔離，取代 v3.7 已廢止的 `.agent-lock.yaml` soft lock。

### Added — SPEC-004 實作（D-001 / v4-decision-log D6）

- **`.asp/scripts/multi-agent/audit-write.sh`**：fail-closed wrapper，所有 Worker 寫 bypass / telemetry / escalation log 的單一入口。POSIX `O_APPEND` atomicity 保證（< 4KB），ASP_AUDIT_ROOT 兩階段驗證（unset / 相對路徑 / 不存在 / 非 git repo 全部 exit 7）
- **`.asp/scripts/multi-agent/_validate_audit_root.sh`**：可被 source 的共享驗證函式，dispatch / converge / GC / list 全部共用
- **`.asp/scripts/multi-agent/dispatch.sh`**：Orchestrator 進入點。讀 task manifests、scope.allow 重疊偵測、為每個 task 建獨立 git worktree + branch、寫 telemetry `multi_agent.dispatch`。退出碼語意完全對齊 SPEC §📤
- **`.asp/scripts/multi-agent/converge.sh`**：Orchestrator merge 階段。per-task rebase + merge --no-ff，衝突分類為 `task_merge_conflict`（本次 converge 已 merge 過某 task）vs `base_branch_rebase_conflict`（base 在 dispatch 後變動）。partial success 為 SPEC-mandated（已 merge 的 task 留在 base，後續失敗不 revert）。worktree 自動 cleanup，branch 保留供 PR review
- **`.asp/scripts/multi-agent/worktree-list.sh` + `worktree-gc.sh`**：運維工具。list 顯示 TASK_ID / AGE / BRANCH / PATH / STATUS；GC 移除 stale worktree（HEAD commit > `ASP_WORKTREE_IDLE_HOURS` 前，預設 2h），annotate manifest `abandoned: true`，保留 branch，emit `multi_agent.gc` telemetry。支援 `--dry-run`
- **Makefile targets**：`make agent-worktree-list / agent-worktree-gc / agent-worktree-gc-dry-run`
- **Telemetry events**：新增 `multi_agent.dispatch / converge / fail / gc / dispatch_rejected` 五種事件型別（schema 見 `docs/telemetry.md`）

### Changed

- **`.asp/profiles/multi_agent.md`**：「衝突隔離」章節從「v4.1 將實作」改為實作後文件（三個入口腳本、強制要求、退出碼語意）
- **`docs/architecture.md`**：§7 已知限制中 worktree 項標記為「✅ v4.1 已實作」；新增多代理執行架構 mermaid 序列圖
- **`docs/telemetry.md`**：事件類型表加入 4 個 multi_agent.* 事件；schema 章節說明平鋪 vs nested 的格式差異

### Fixed

- **`audit-write.sh` 接受 escalation log type**（B3 整合需求）：原本只支援 bypass / telemetry，加入 escalation 後 converge 衝突可以記錄結構化 reason 而不靠 telemetry 重載

### Tests

新增 4 個 bash 測試檔案，共 75 個 assertions：
- `test_spec_004_audit_write.sh`（B1 fail-safe wrapper）：23 項
- `test_spec_004_dispatch.sh`（B2 dispatch + scope 驗證 + max_parallel 邊界）：20 項
- `test_spec_004_audit_integration.sh`（B5 Iron Rule A 掛載 + 並行壓測 5×200）：13 項
- `test_spec_004_converge.sh`（B3 衝突分類 + cleanup）：21 項
- `test_spec_004_worktree_gc.sh`（B4 GC 閾值 + manifest annotation）：21 項

專案總測試：bash 136 + pytest 50 = **186 passing**。

### Done When 進度（SPEC-004 共 18 條）

- ✅ #5 `agent-worktree-gc` / #6 `agent-worktree-list` / #7 dispatch + converge 實作 / #12 telemetry events / #16 ASP_AUDIT_ROOT 機制 / #17 fail-safe 兩階段驗證
- ⏳ 剩 #1 spec-004 全測試套（依賴 #15 benchmarks 提供基準環境量測） / #4 multi_agent.md 章節（本版完成）/ #10 architecture.md（本版完成） / #11 CHANGELOG（本版即是）/ #13 install.sh 預檢 / #15 benchmarks.md / #18 D6 entry
- 餘下項目排程於 v4.1.0 正式版

### Known Limitations

- 並行壓測在測試中縮為 5 worker × 200 entry（1000 行）以兼顧 CI 速度。SPEC §S18 全量 10×1000 留給 `SPEC-004-multi-agent-worktree-isolation-benchmarks.md`
- N2（Worker 修改 forbid 路徑）需要 PreToolUse hook 整合，本版未實作；scope 違規目前在 dispatch 階段透過 scope.allow/forbid 宣告擋下，runtime 強制留待 v4.1.x
- Telemetry schema 在 `multi_agent.*`（平鋪）與既有事件（nested data）不一致，v4.2 統一

## [4.0.1] - 2026-05-09

對照 v4.0 四份核心設計文件（`docs/v4-architecture-sds.md`、`docs/production-ops-playbook.md`、`docs/v4-refactor-prompts.md`、`~/docs/cs146s-study-notes.md`）執行 review，補齊 v4.0 ship 後遺留的 gap。

### Fixed
- **`make test` exit 5**: pytest 找不到 Python 測試時直接失敗，bash 測試（`tests/*.sh`）被忽略。新增 bash test fallback 與 `autopilot-validate` 的 script-not-found graceful skip，27/27 測試通過
- **`CLAUDE.md` 過時路徑**: 6 處引用 `.asp/profiles/`、`.asp/hooks/`、`.asp/levels/`、`.asp/templates/` 已失效（v4.0 改為 user-level 架構），全數更新為 `~/.claude/asp/`，檔案維持 100 行內
- **audit-health 測試掃描盲點**: 第 723 行只認 `go/ts/tsx/js/jsx/py/java/rb` 副檔名，bash 測試完全被忽略，導致純 bash 測試專案被誤報為 BLOCKER。新增 `sh` 副檔名與 `tests/*` 路徑排除
- **audit-health tech-debt false positive**: 第 811 行掃描沒有 `--include` 過濾，撈到 markdown 文件中的字面範例（`asp-ship.md`、`asp-review.md`、runbooks 等），誤報 14 個 ghost debts。已限定 source code 副檔名並排除 `.asp/profiles/`、`.asp/templates/`、`.asp/hooks/`、`.asp/scripts/` 工具內部

### Added
- **ADR-003: MCP Server 取消決策**: 正式記錄 v4.0 取消 MCP server 的選項評估與決策理由（user-level skill 架構已涵蓋原定 5 個 tool 功能），並列出 v4.1 重新評估條件
- **`.asp/ai-performance/` (移入 repo)**: 將 `~/asp-ai-performance/` 的 `schema.md`、`trust-tier.yaml`、`monthly-review.py` 移入版控；新增 `make asp-performance-review` 與 `make asp-performance-review-update` Makefile targets；路徑同步至 `~/.claude/asp/ai-performance/`

### Changed
- **`docs/v4-architecture-sds.md` §9 進度追蹤**: 從 all-⬜-Not-started 改寫為「v4.0 交付狀態」，11 個 prompt 對應實際產出檔案；Track C（MCP）標記 CANCELLED，其餘 5 個 track 標記 DONE
- **`multi_agent.md` 廢止 v3.7 機制**: 砍掉「Context 全量傳遞」（line 21）與「文件鎖定」+「Lock GC 自動化」（line 82-126，共 51 行）兩個與 D-001 決策矛盾的段落，加上指向 v4.1 worktree 架構的廢止警告

### Rationale
v4.0 ship 時為了發布，幾個 P1-P2 等級的不一致先暫時擱置：（1）測試與 audit 腳本對 bash-first 專案的覆蓋率盲點；（2）profile 中與 SDS 決策矛盾的舊 v3.7 機制描述；（3）SDS §9 進度追蹤滯後於實際交付。本次 review 一次補齊，使 audit baseline 反映真實狀態，profile 與 SDS 不再對 AI 下達矛盾指令。

## [4.1.0] - 2026-05-05

### Added
- **Domain Vocabulary Mechanism（CONTEXT.md）**: ASP v4.1 核心補強。完整的術語一致性執行鏈：
  - **`CONTEXT.md`（repo root）**: ASP 自身的領域詞彙表，覆蓋 15+ 核心術語（ASP、Profile、Skill、Gate G1-G6、SPEC、ADR、HITL、Session Briefing、Bypass Log、Dynamic Deny、Reality Checker、Smuggling、Maturity Level、Autopilot、Pipeline、Telemetry）；含定義、避免使用詞、相關 ADR
  - **`asp-context` skill（Mode A/B/C）**: Mode A 從現有 ADR/SPEC 初始化詞彙表，Mode B 增量更新術語，Mode C 審計術語一致性（掃描 ADR/SPEC/commit message 是否使用已棄用同義詞）；所有寫入操作前設置 STOP gate 等待人類確認
  - **`.asp/templates/CONTEXT_Template.md`**: CONTEXT.md 標準模板，含五個必要 section
  - **`global_core.md` session 啟動讀取**: 若 `CONTEXT.md` 存在，session 開始前必須讀取；後續所有輸出術語必須與 CONTEXT.md 一致
  - **`asp-plan.md` 術語預檢**: SPEC 撰寫 Step 4 後，強制以 `grep` 交叉比對 CONTEXT.md「避免使用」詞清單
  - **`asp-gate.md` G2 術語一致性**: G2 checklist 新增第 6 項：SPEC 術語對照 CONTEXT.md，「避免使用」詞一律 FAIL
  - **`SKILL.md` router 新增 asp-context 路由**: 觸發詞 `context, vocabulary, 術語, 詞彙, domain vocab`；執行後提示下一步為 `/asp-gate G2` 術語驗證
- **mattpocock/skills 整合**: 全局安裝 12 個 engineering skills（`diagnose`、`tdd`、`grill-with-docs`、`to-prd`、`to-issues`、`triage`、`improve-codebase-architecture`、`zoom-out`、`grill-me`、`caveman`、`write-a-skill`、`setup-matt-pocock-skills`）至 `~/.agents/skills/`，symlink 至 `~/.claude/skills/`
- **`docs/agents/` 設定目錄**: 新增 `issue-tracker.md`（GitHub Issues + `gh` CLI）、`triage-labels.md`（5 個 canonical triage 狀態）、`domain.md`（single-context，`CONTEXT.md` + `docs/adr/`）
- **`CLAUDE.md` Agent skills 區塊**: 新增 `## Agent skills` section，讓 mattpocock skills 能讀取 issue tracker、triage labels、domain docs 設定

### Fixed
- **`.asp/scripts/install.sh` 升級 Bug #1（cp -r 嵌套）**: `cp -r src/dir dst/dir` 在目標目錄已存在時產生 `dst/dir/dir` 嵌套，導致 skill/profile 重複安裝；修復為 `rm -rf dst && mkdir dst && cp -r src/. dst/`
- **`.asp/scripts/install.sh` 升級 Bug #2（Makefile 自訂 targets 被清空）**: 升級時完整替換 Makefile，使用者寫在「專案自訂 targets」區塊的內容被覆蓋；修復為升級前用 awk 提取自訂區塊，替換後以 sed 重新注入
- **`.claude/settings.json` deny 重複注入**: `npx skills@latest add` installer 將 `ask` 陣列複製為 `deny`，造成危險指令從「跳彈窗確認」變為「靜默拒絕」，與 ASP 鐵則設計不符；已移除多餘 `deny` 區塊，還原為 `ask` 行為

### Rationale
競品分析（mattpocock/skills、addyosmani/agent-skills、slavingia/skills）發現 ASP 在「跨 session 術語一致性執行」維度有明顯差距：其他框架以 CONTEXT.md 為核心解決「AI 自創術語」問題，ASP 雖在 `docs/adr/` 有架構記錄，但缺少 session 啟動時的強制讀取機制與 Gate 整合。Domain Vocabulary Mechanism 補上此差距，同時借助 ASP 現有的 Gate 體系（G2 術語一致性 checklist）實現比競品更強的執行強制力。

## [3.6.0] - 2026-04-22

### Added
- **G5.5 Cross-Component Parity Gate**: 新 gate 在 G5 與 G6 之間，驗證跨 module / 跨 service 契約對齊。檢查 SPEC 是否含 Cross-Component Invariants section、grep 全 repo callsite、mock 對稱檢查、round-trip test 是否存在。
- **G6.5 Post-Deploy SIT Gate**: 新 gate 在 G6 之後，要求 deploy 完 + ArgoCD synced 後跑 SIT round-trip 才算「完成」；FAIL 時 AI 提議 rollback infra image tag PR。請求使用者 UI 驗證**之前**必過此 gate。
- **`docs/spec-driven-dev.md` Cross-Component Invariants section**: SPEC 模板必填欄位（涉及跨 module 契約時），明示 invariant、SSOT、consumer、現有格式的 grep 證據。

### Rationale
2026-04-21/22 PoC 出現連續 21 小時、6+ deploy 才穩住的 incident（PM-002）：兩個 cross-component invariant violation（shard key padding asymmetry + envelope decrypt asymmetry）存活 ≥ 3.5 月。原因是 ASP G1-G6 流程每層自洽通過，但**沒有任何一道 gate 檢查「跨 module 真的能合作」**。G5.5 + G6.5 補上這層。詳見 `backup-infrastructure/docs/postmortems/PM-002-shard-key-and-decrypt-cross-component-asymmetries.md`。

## [3.5.1] - 2026-04-10

### Added
- **`global_core.md` 工作目錄紀律**: 新增「工作目錄紀律」段落，要求 AI 在多 root / subagent 接手 / 相對路徑情境下明確確認 cwd，存取專案外路徑必須等待使用者確認
- **`global_core.md` 外部資料校對**: 新增「外部資料校對」段落，要求 API / 函式簽章等資訊必須透過 RAG / context7 / WebFetch 查證，以「人事時地物 5 元素」對齊
- 兩個段落皆含 Common Rationalizations 藉口反駁表

### Rationale
差距分析發現使用者個人全域 CLAUDE.md 有 2 條通用紀律 ASP 尚未涵蓋（工作目錄確認、外部資料校對）。這兩條是語言/技術棧中立的通用紀律，適合納入 `global_core.md`。其他個人偏好（繁體中文、套件管理工具、硬體環境）刻意保留在使用者個人全域，不進入框架層。

## [3.5.0] - 2026-04-10

### Added
- **Maturity Levels 系統（L1-L5）**: 借鑒 addyosmani/agent-skills 與 slavingia/skills 的 journey-based 設計。取代 20 個 profile 的扁平組合，使用者從 L1 Starter 開始逐級升級（L1→L2 Disciplined→L3 Test-First→L4 Collaborative→L5 Autonomous）
  - 新增 `.asp/levels/level-1.yaml` ~ `level-5.yaml`（含 profile 組合、graduation_checklist、prerequisites）
  - 新增 `asp-level` skill（評估 / 升級 / 降級）
  - 新增 Makefile targets: `asp-level-check`、`asp-level-upgrade`、`asp-level-list`
  - `.ai_profile` 新增 `level:` 欄位；legacy 專案支援 level 推斷規則
  - `install.sh` 新增 L1-L5 選單（替代扁平 preset，保留 P 選項作向後相容）
- **Anti-Rationalization Tables**: 借鑒 agent-skills 的反合理化設計。在 asp-ship、asp-plan、asp-gate、asp-reality-check、asp-level 五個 skill 新增 `## Common Rationalizations` 段落，系統性封堵 AI 常見繞過藉口
- **Evidence-Based Gate Output**: Gate 與 Ship 輸出升級為結構化證據模式
  - 每個檢查項目必須附 `command` + `exit_code` + `evidence_excerpt`
  - Skip 事件必須寫入 `.asp-bypass-log.json`（append-only）
  - 預設摘要模式 + verbose 詳情模式
- **Bypass Log 系統**
  - 新增 `.asp-bypass-log.json`（append-only 紀錄所有 skip 事件）
  - 新增 Makefile targets: `asp-bypass-review`、`asp-bypass-record`
  - `asp-enforcement-status` 顯示近 7 天 bypass 統計
- **Specialist Subagent Personas**: 擴充 `reality-checker` 模式
  - `.claude/agents/security-auditor.md`（OWASP Top 10 獨立審查，read-only）
  - `.claude/agents/test-engineer.md`（測試品質與 TDD 紀律審查，read-only）
  - 可透過 Agent tool 直接召喚，不需啟用 `multi_agent` profile
- **Router Next-Step Suggestions**: SKILL.md router 新增「執行後主動提示下一步」規則，每個 skill 完成後提示 workflow 下一階段（只建議、不自動執行）

### Changed
- **CLAUDE.md**: 新增 `.ai_profile` `level:` 欄位、Maturity Levels 章節、新 Makefile targets 速查
- **install.sh**: 互動式安裝新增 L1-L5 等級選單；`.ai_profile` 欄位補充 loop 納入 `level`
- **asp-ship**: Step 10 分為 10a（測試結果）/ 10b（bypass 記錄）；新增 Evidence-Based Output 說明
- **asp-gate**: 新增 Evidence-Based Output JSON 格式範例、skip 自動記錄規則

### Design Origin
本版本的演化方向來自分析兩個外部框架：
- addyosmani/agent-skills — Anti-rationalization tables + evidence-based verification
- slavingia/skills — Journey-based skill sequencing

ASP 保留 4 層強制力架構（Hook + Dynamic Deny + Gate + Subagent）作為核心差異化，在此之上吸收兩者的新手友善設計。

## [3.4.0] - 2026-03-26

### Added
- **4-layer enforcement architecture**: 借鏡 sd0x-dev-flow 的 hook 強制力設計，在 VSCode 插件限制下實現最大規則覆蓋
- **Smart SessionStart audit** (`session-audit.sh`): Session 啟動時自動執行 7 維度專案審計，產生 `.asp-session-briefing.json`
- **Dynamic deny list**: 根據專案狀態（Draft ADR、測試未通過）動態注入 `git commit` deny pattern，VSCode 彈出阻擋對話框
- **`asp-gate` skill**: Pipeline G1-G6 品質門檻評估器，結果寫入 `.asp-gate-state.json`
- **`reality-checker` subagent** (`.claude/agents/reality-checker.md`): 獨立 context 的懷疑論者，預設 NEEDS_WORK，用於 G5 交叉驗證
- **`asp-verify.sh` script**: 獨立驗證腳本（test + lint + credential scan + debug scan）
- **Mandatory skill invocation table**: CLAUDE.md 新增強制 skill 調用點表，含繞過警告格式
- **`asp-ship` v3.4**: 從 7 步驟擴展為 10 步驟（+Session briefing +Lint +Security scan +記錄結果）
- **Makefile targets**: `asp-unlock-commit`、`asp-refresh`、`asp-enforcement-status`

### Changed
- **`clean-allow-list.sh`**: 新增動態 deny 清理邏輯（每次 session 先清理再重新評估）
- **`settings.json`**: 註冊 `session-audit.sh` 為第二個 SessionStart hook
- **CLAUDE.md 鐵則**: ADR 禁止實作規則標記為「v3.4 硬性執行」
- **SKILL.md router**: 新增 asp-gate 路由

### Technical Notes
- VSCode Claude Code 插件不支援 PreToolUse/PostToolUse/Stop hooks（GitHub #21736, #13744, #13339）
- 強制力設計繞過此限制：使用 SessionStart + deny list（硬性）+ skill（結構化軟性）+ subagent（中等）
- 規則覆蓋：78 條可強制規則中，18 條硬性阻擋 + 53 條結構化軟性 + 7 條 subagent 驗證

## [2.15.0] - 2026-03-22

### Added
- **E2E Test Gate**: 全端專案（同時具有 frontend/ + backend/）強制 Playwright E2E 測試
- **Pre-Implementation Gate Step 5c**: Playwright 設定檔 + e2e/ 目錄不存在 → BLOCK
- **Testing Pyramid enforcement**: E2E 從「建議」升級為「有前後端時必須」
- **Health audit dimension 1c**: E2E 測試審計，缺少設定/目錄/測試檔 → BLOCKER
- **Pre-commit checklist**: 使用者流程修改需驗證 E2E 覆蓋

## [2.14.0] - 2026-03-19

### Added
- **Security BLOCK**: coding_style 安全違規（SQL injection、hardcoded secrets、raw HTML）從 SUGGEST 升級為 BLOCK，無豁免
- **Pre-commit report**: 提交前自審必須輸出 5 維度通過/失敗結論報告
- **Bug grep evidence**: Bug 修復後 grep 全專案必須輸出 grep 指令本身作為證據
- **Bug classification function**: `classify_bug_severity()` 以客觀指標取代主觀判斷
- **Frontend verification triggers**: 4 個驗證函數加入明確觸發時機表
- **Breaking change BLOCK**: OpenAPI breaking change 偵測到即 BLOCK，強制版本遞增
- **Profile conflict detection**: `validate_profile_config()` 啟動時自動驗證依賴/衝突
- **Autopilot script safety**: script 呼叫加入存在性檢查，不存在時 WARN 而非報錯

## [2.13.0] - 2026-03-19

### Added
- **Design system BLOCK**: `design: enabled` 時若 `design-system/` 不存在 → BLOCK
- **Design token WARN**: `design-system/` 存在但缺 `tokens.yaml` → WARN
- **Design Gate integration**: `system_dev.md` Step 4a 強制呼叫 `before_ui_work()`
- **API Test Gate**: 通用 Step 5b，後端 API 修改時強制整合測試
- **verify_token_sync alignment**: pre-commit 與 SPEC Done When 參數對齊
- **Pencil MCP section**: design_dev 新增已知問題速查表與標準流程
- **Frontend quality responsibility table**: 明確劃分 design_dev 與 frontend_quality 職責
- **Vibe coding Design Gate pause**: `hitl: minimal` 暫停條件新增 Design Gate

## [2.12.0] - 2026-03-18

### Added
- **Skill Layer**: 5 個 Claude Code 原生 skill（asp-plan/ship/audit/review/autopilot）
- **SKILL.md router**: 根據使用者意圖自動路由到對應子 skill
- Reduced onboarding friction with skill-based entry points

## [2.11.0] - 2026-03-18

### Changed
- Autopilot Phase 2 auto-generates SPEC for all tasks (mandatory)
- Autopilot Phase 2 smart assessment for ADR necessity

## [2.10.0] - 2026-03-17

### Added
- Autopilot auto-generates/revises README.md on completion

## [2.9.0] - 2026-03-17

### Changed
- **Deny-list permission model**: Allow Bash(*) + deny dangerous commands
- SessionStart hook ensures deny rules are correctly applied

## [2.8.0] - 2026-03-16

### Changed
- Restructured README and autopilot docs into SOP format

## [2.7.0] - 2026-03-15

### Added
- Auto-generate CLAUDE.md project description from ROADMAP.yaml

## [2.6.0] - 2026-03-12

### Added
- **Autopilot Profile** (`.asp/profiles/autopilot.md`): Roadmap-driven continuous execution with cross-session resume, dynamic prerequisite detection, and automatic profile loading
- **ROADMAP Template** (`.asp/templates/ROADMAP_Template.yaml`): Structured project metadata including tech stack, requirements, conventions, architecture, quality, security, and observability
- **SRS Template** (`.asp/templates/SRS_Template.md`): Software Requirements Specification with FR/US/UC, data model, interface spec, and traceability matrix
- **SDS Template** (`.asp/templates/SDS_Template.md`): Software Design Specification with system architecture, module design, data design, API contracts, and security design
- **UI/UX Spec Template** (`.asp/templates/UIUX_SPEC_Template.md`): Design system, page flow, component spec, responsive rules, accessibility, and animation
- **Deploy Spec Template** (`.asp/templates/DEPLOY_SPEC_Template.md`): Environment definition, container spec, CI/CD pipeline, monitoring, and disaster recovery
- **Makefile targets**: `autopilot-init`, `autopilot-validate`, `autopilot-status`, `autopilot-reset`, `srs-new`, `sds-new`, `uiux-spec-new`, `deploy-spec-new`
- **install.sh**: `autopilot` field support in `.ai_profile`
- **CLAUDE.md**: Autopilot field, Profile mapping, startup procedure step 4b, Makefile quickref

### Changed
- **Zero-confirmation autopilot**: All 13 pause points removed; autopilot runs continuously to token exhaustion with auto-handling strategies (skip + record)
- `.asp/VERSION`: 2.5.0 → 2.6.0
- `.gitignore`: Added `.asp-autopilot-state.json`

## [2.5.0] - 2026-03-12

### Changed
- Non-destructive Makefile installation via include-based architecture

## [2.4.1] - 2026-03-12

### Fixed
- install.sh Makefile upgrade detection and jq type guard

## [2.4.0] - 2026-03-12

### Added
- Task orchestrator and health audit
- Framework robustness improvements

## [2.3.0] - 2026-03-12

### Added
- Task orchestrator profile

## [2.2.0] - 2026-03-12

### Added
- Frontend quality profile

## [2.1.0] - 2026-03-12

### Added
- Autonomous + multi-agent composability via layered authorization

---

> **v3.7.0 (2026-04-28) 之前的完整 ASP 框架升級紀錄**：見 [`docs/archive/asp-changelog-pre-v4.0.md`](docs/archive/asp-changelog-pre-v4.0.md)。
> 該檔案是 v4.0 重構前的 `.asp/CHANGELOG.md`（ASP 框架自身升級風格），與本 root CHANGELOG.md 早期條目重疊但格式不同，2026-05-10 cleanup 時 archive。
