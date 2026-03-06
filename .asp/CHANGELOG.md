# ASP Changelog

本檔案記錄 AI-SOP-Protocol 框架本身的版本變更，供升級時參考。

---

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
