# ASP Changelog

本檔案記錄 AI-SOP-Protocol 框架本身的版本變更，供升級時參考。

---

## v2.5.0

- **Makefile 非破壞性安裝（Breaking Change）**：
  - **Include-based 架構**：ASP targets 移至 `.asp/Makefile.inc`（ASP 完全擁有），專案 Makefile 改為 stub + `-include .asp/Makefile.inc`
  - **非 ASP 專案保護**：目標專案有自己的 Makefile 時，僅追加 include 指令，不覆蓋原有內容
  - **升級相容**：舊版 ASP Makefile（含 `AI-SOP-Protocol` 標記）自動轉換為 stub + include 模式
  - **install.sh 重構**：移除 4 層覆蓋式 Makefile 偵測邏輯，改為 3 分支 include-based 邏輯

---

## v2.4.1

- **install.sh Bug 修復**：
  - **Makefile 升級偵測**：修復舊版 Makefile（有 `guardrail-log` 但無 `ASP_MAKEFILE_VERSION`）不會被升級的問題。改用 `audit-health` 作為最新版本標記
  - **settings.local.json jq 錯誤**：修復 JSON 檔案非 object 類型時 jq 報錯。新增 type guard 跳過非 object 檔案
- **clean-allow-list.sh**：同步修復相同的 jq type guard 問題

---

## v2.4.0

- **框架穩健性優化**：提升 task_orchestrator 的可執行性與錯誤恢復能力
  - **Helper Function 定義**：新增 Part H，定義 ~12 個先前未規格化的函數（`is_core_module`、`determine_change_level`、`analyze_requirement`、`decompose` 等），含 pseudocode 與判定範例
  - **L1-L4 量化**：`determine_change_level()` 加入量化門檻與判定範例表，消除分類模糊性
  - **後置審計 Circuit Breaker**：最多 2 輪，超過記入 tech-debt，防止 infinite loop
  - **ADR Pre-flight Timeout**：30 分鐘逾時機制，提供繼續等待/暫存/跳過三個選項
  - **Gate 防護**：Design/OpenAPI Gate 呼叫前檢查 profile 是否載入，未載入時 WARN + tech-debt 而非靜默失敗
  - **auto_fix_loop 失敗處理**：D1/D2/D3 工作流加入 guard_triggered 檢查，三重防護觸發時 PAUSE 不繼續
  - **新鮮度維度修復**：SPEC 存在但無 Traceability 時發出 WARNING（不再靜默跳過）
  - **交叉引用表**：Part H 結尾新增 helper function → 來源 profile 對照表
- **Makefile 修復**：
  - `make test` / `make test-filter`：偵測框架後才執行，測試失敗正確傳播 exit code，無框架時 exit 1（不再靜默成功）
  - `audit-health` 維度 7：SPEC 存在但無 Traceability 時輸出 WARNING
- **CLAUDE.md 更新**：Makefile 速查表補齊所有 target（coverage、lint、diagram、agent-locks、rag-stats、guardrail、task-report 等），Profile 對應表去除冗餘列
- **跨 Profile 交叉引用**：
  - `multi_agent.md`「Autonomous 模式整合」加 canonical source 註記
  - `autonomous_dev.md`「Multi-Agent 整合」加擴展來源註記
  - `task_orchestrator.md` Part G 加 routing-only 註記
- **Trivial 統一定義**：`global_core.md` 新增量化標準（檔案 ≤ 2、行數 ≤ 10、不涉及商業邏輯），不確定時視為 non-trivial
- **SPEC Template**：Traceability 區塊加 HTML 註解標註「實作完成後回填」

---

## v2.3.0

- **Task Orchestrator Profile**：新增 `task_orchestrator.md`，統一任務入口與協調層
  - 任務分類：自動識別 5 種任務類型（新增/修復/修改/移除/複合）並路由到對應工作流
  - 架構影響評估：自動判斷是否需要 ADR
  - REMOVAL 工作流：全新的功能移除流程（依賴分析→deprecation 評估→安全移除→零殘留驗證）
  - 文件產出管線：所有任務類型共用，自動更新 CHANGELOG/README/architecture/SPEC
  - 完成報告：結構化報告含健康改善指標
  - Multi-Agent 整合：TASK_GENERAL 可分解為並行子任務
  - 載入：`orchestrator: enabled` 或 `autonomous: enabled` 時自動載入
- **專案健康審計**：`task_orchestrator.md` 內建 7 維度掃描 + 強制補齊機制
  - 測試覆蓋、SPEC 覆蓋、ADR 覆蓋、文件完整性、程式碼衛生、依賴健康、文件新鮮度
  - 分級報告：Blocker / Warning / Info
  - 觸發時機：首次介入專案自動觸發、距上次審計 > 7 天、`make audit-health`
  - 審計基線追蹤：`.asp-audit-baseline.json`
- **軟工缺陷修復**：
  - **雙向可追溯性**：SPEC Template 新增 Traceability 區塊（實作檔案、測試檔案、最後驗證日期）
  - **文件新鮮度追蹤**：`global_core.md` 新增技術強制機制，不再純靠 AI 自律
  - **非功能需求（NFR）**：SPEC Template 新增 optional 的效能/安全/可用性/相容性區塊
  - **測試金字塔**：`system_dev.md` 新增單元→整合→契約→E2E 指引
  - **Hotfix 流程**：`system_dev.md` 新增生產環境緊急修復流程（簡化 Gate + 24h 回填義務）
  - **分支與合併**：`system_dev.md` 新增輕量分支策略指引
  - **Tech Debt 彙總**：`global_core.md` 新增規則，`make tech-debt-list` 掃描全專案
- **Makefile 新增 targets**：
  - `audit-health`：完整專案健康掃描（7 維度）
  - `audit-quick`：快速 blocker 檢查
  - `doc-audit`：文件新鮮度掃描
  - `tech-debt-list`：tech-debt/TODO/FIXME/DEPRECATED 彙總
  - `task-start`/`task-status`/`task-report`：任務記錄與統計
- **install.sh**：支援 `orchestrator` 欄位，模式 2/4 自動啟用，安裝完成提示 `make audit-health`

## v2.2.0

- **Frontend Quality Profile**：新增 `frontend_quality.md`，獨立的前端工程品質驗證
  - i18n 硬編碼偵測 + 語系一致性驗證 pseudocode
  - 顏色值驗證（禁止硬編碼 hex/rgb）
  - 元件三態驗證 pseudocode
  - Error/Loading/Empty 標準化規範
  - Accessibility 自動化驗證 pseudocode
  - 載入：`frontend_quality: enabled` 或 `design: enabled` 時自動載入
- **Design Token 同步**：`design_dev.md` 新增 Token ↔ CSS 雙向驗證 pseudocode
- **design: disabled UI 兜底**：`system_dev.md` 新增 `ui_baseline_rules`
- **DEPRECATED 程式碼追蹤**：`global_core.md` 新增清理計畫規範
- **提交前自審擴充**：清潔度 +3 項、新增「前端元件完整性」區塊
- **TDD 場景擴充**：前端互動元件建議基本測試
- **設計 Review 擴充**：a11y checklist 新增 4 項
- **Makefile**：新增 `i18n-check` target
- **install.sh**：支援 `frontend_quality` 欄位

## v2.1.0

- **Autonomous + Multi-Agent 可組合**：分層授權（Worker scope 內自主、Orchestrator 全專案協調）
- **Profile 衝突驗證**：新增 `<!-- conflicts: -->` 標籤
- **安裝簡化**：從多題 y/N 精簡為 2 題（專案類型 + 開發風格）
- **專案偵測擴充**：Rust/Java/C#/C++/Ruby/Elixir/PHP + 架構偵測

## v2.0.0

- **Autonomous 開發模式**：新增 `autonomous_dev.md` profile，支援 AI 全自動開發
  - auto_fix_loop 含振盪偵測、串聯失敗偵測、測試篡改偵測
  - 批次 ADR 預審流程
- **Hook 架構重構**：移除 PreToolUse hooks（enforce-workflow.sh、enforce-side-effects.sh），改用 Claude Code 內建權限系統
  - 僅保留 SessionStart hook（clean-allow-list.sh）
  - install.sh 自動清理舊版 hooks
- **SPEC 模板增強**：
  - 新增「副作用與連動（Side Effects）」區塊
  - 新增「回退方案（Rollback Plan）」子區塊
  - Done When 增加副作用驗證 checkbox
  - 「建議模型」和「HITL 等級」標記為 optional
- **迴歸預防協議擴充**：6 步驟（根因→重現→全專案掃描→狀態依賴掃描→下游驗證→分類標記）
- **Postmortem 流程**：新增模板（5 Whys）、Makefile targets、觸發條件定義
- **穩定度導向**：
  - coding_style.md 新增穩定度導向編碼規則 + 安全編碼基線
  - system_dev.md 新增變更影響評估、穩定狀態驗證、Schema 變更治理、提交前自審、依賴管理規範
  - TDD 場景新增 UI/樣式調整豁免、文件/配置變更豁免
- **Context 管理**：主動預防措施（定期壓縮、品質自驗、不可繼承資訊清單）
- **Profile 交叉引用**：所有 profile 加入 `<!-- requires: -->` / `<!-- optional: -->` 標頭
- **RAG 增量索引**：build_index.py 支援 `--incremental`，SHA-256 manifest 追蹤
- **連動性補強**：
  - 文件原子化拆為正向 + 反向規則（ADR 廢止→掃 SPEC、設計變更→標記 drift、OpenAPI 變更→掃前後端）
  - ADR 執行規則加入 Deprecated/Superseded 反向掃描
  - Pre-Implementation Gate 新增步驟 6「歷史教訓查詢」（RAG 啟用時查 Postmortem）
  - 新增「需求變更回溯協議」：4 級（細節修改 / SPEC 推翻 / ADR 推翻 / 方向 Pivot）
- **Makefile 條件載入**：讀取 `.ai_profile` 的 `type`，content 專案隱藏 Docker/Test/Diagram targets

## v1.6.0

- 新增 `coding_style.md` profile（程式碼風格治理）
- 新增 `openapi.md` profile（API-First 工作流）
- 擴充 `design_dev.md`（UI/UX 設計治理）

## v1.4.0

- 吸收 context engineering 最佳實踐（壓縮觸發、衰退模式、token 經濟學）
- install.sh 顯示 commit hash

## v1.3.0

- 遷移至 SessionStart hook + 內建權限系統
- 移除 PreToolUse hook 中的 deny 策略

## v1.2.0

- Profile 決策流程改為偽代碼格式
- Hook 策略改為 hybrid（git push 使用內建權限）

## v1.1.0

- 新增 SPEC 存在性檢查
- 支援升級安裝

## v1.0.0

- 初始版本
- Profile 系統：global_core、system_dev、content_creative、vibe_coding、multi_agent、committee、guardrail、rag_context
- Makefile 封裝、ADR/SPEC 模板、install.sh
