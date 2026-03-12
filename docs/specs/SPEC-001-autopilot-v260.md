# SPEC-001：Autopilot v2.6.0

> 結構完整的規格書讓 AI 零確認直接執行。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-001 |
| **關聯 ADR** | ADR-001 |
| **估算複雜度** | 高 |
| **建議模型** | 依階段（見計畫 ASP 設定速查表） |
| **HITL 等級** | 依階段（見計畫 ASP 設定速查表） |

---

## 🎯 目標（Goal）

> 新增 autopilot profile 及前置文件體系，讓使用者提供 ROADMAP.yaml + 前置文件後，AI 能自動持續執行所有任務直到完成或 token 用盡，並支援跨 session 自動續接。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| ROADMAP.yaml | YAML | 專案根目錄 | 必須包含 version, project, milestones |
| docs/SRS.md | Markdown | docs/ | 永遠必要 |
| docs/SDS.md | Markdown | docs/ | stack.backend/database != none 時必要 |
| docs/UIUX_SPEC.md | Markdown | docs/ | requires.uiux 或 stack.frontend != none 時必要 |
| docs/DEPLOY_SPEC.md | Markdown | docs/ | stack.infra != none 時必要 |

---

## 📤 輸出規格（Expected Output）

**成功情境：**
- 所有 ROADMAP tasks 狀態為 completed
- `.asp-autopilot-state.json` 狀態為 completed
- 每個 task 都有對應 SPEC 和通過的測試

**中斷情境：**
- Context > 75% 時存 checkpoint，ROADMAP.yaml 更新至當前進度
- `.asp-autopilot-state.json` 包含 current_task、completed 列表、exit_reason

---

## 🔗 副作用與連動（Side Effects）

| 本功能的狀態變動 | 受影響的既有功能 | 預期行為 |
|-----------------|----------------|---------|
| 新增 autopilot 欄位到 .ai_profile | install.sh 欄位處理 | install.sh 需支援新欄位 |
| 新增 CLAUDE.md Profile 對應表行 | 啟動程序 profile 載入 | autopilot: enabled 時載入 autopilot.md |
| 新增 Makefile targets | make help | 新 targets 出現在幫助中 |

---

## ⚠️ 邊界條件（Edge Cases）

- Case 1：ROADMAP.yaml 不存在時 → 自動執行 `make autopilot-init` 建立（零確認）
- Case 2：依賴圖有循環 → 標記涉及的 tasks 為 blocked，繼續執行其他獨立 task（零確認）
- Case 3：所有 tasks 已 completed → 直接報告完成，不執行
- Case 4：context > 75% 剛好在 task 執行中間 → 等當前 task 完成後再 checkpoint
- Case 5：task 失敗 → 標記 failed，跳過依賴此 task 的後續任務，繼續獨立任務
- Case 6：前置文件缺失 → 自動執行對應 make target 建立模板（零確認）
- Case 7：ADR 未 Accepted → 標記相關 task 為 blocked 並跳過（不違反鐵則，零確認）
- Case 8：autonomous_dev 暫停項（git push/刪檔/新增依賴等）→ 由 autopilot 自主處理策略覆寫（見 autopilot.md「零確認」段落）

### 回退方案（Rollback Plan）

- **回退方式**：revert commit（所有變更為新增檔案或追加內容，不影響既有功能）
- **不可逆評估**：無不可逆部分。所有新增都是 additive。
- **資料影響**：無。autopilot 不動使用者資料。

---

## ✅ 驗收標準（Done When）

**自動化驗證**（Makefile targets）：
- [ ] `make autopilot-init` 能從模板建立 ROADMAP.yaml
- [ ] `make autopilot-init`（重複）不覆蓋、顯示警告
- [ ] `make autopilot-validate`（合法 ROADMAP）exit 0
- [ ] `make autopilot-validate`（不合法依賴）exit 1
- [ ] `make autopilot-validate`（缺失 ADR 引用）exit 1
- [ ] `make autopilot-status`（無 state）顯示 "not started"
- [ ] `make autopilot-status`（有 state）顯示正確統計
- [ ] `make autopilot-reset` 刪除 state 檔、ROADMAP 不動
- [ ] `make srs-new` / `sds-new` / `uiux-spec-new` / `deploy-spec-new` 各自建立且不覆蓋

**人工審核**（純文件）：
- [ ] `.asp/profiles/autopilot.md` 包含完整偽代碼（Phase 0-6）+ 動態探測邏輯 + 安全邊界
- [ ] `.asp/templates/ROADMAP_Template.yaml` 包含 stack/requires/conventions/architecture/quality/security/observability
- [ ] `.asp/templates/SRS_Template.md` 包含 FR/US/UC/資料模型/介面規格/追溯矩陣
- [ ] `.asp/templates/SDS_Template.md` 包含系統架構/模組設計/資料設計/API 合約/安全設計
- [ ] `.asp/templates/UIUX_SPEC_Template.md` 包含 Design System/頁面流程/元件規格/響應式/無障礙
- [ ] `.asp/templates/DEPLOY_SPEC_Template.md` 包含環境定義/Container/CI-CD/監控/災難復原
- [ ] `CLAUDE.md` 包含 autopilot 欄位 + Profile 對應表 + 啟動程序 step 4b + Makefile 速查
- [ ] `install.sh` 支援 autopilot 欄位
- [ ] `.asp/VERSION` 為 2.6.0

**迴歸檢查**：
- [ ] 所有既有 `make` targets 無影響
- [ ] 不啟用 autopilot 的專案行為完全不變

---

## 🔗 追溯性（Traceability）

<!-- 此區塊於實作完成後回填 -->

| 實作檔案 | 測試檔案 | 最後驗證日期 |
|----------|----------|-------------|
| `.asp/profiles/autopilot.md` | `tests/test_autopilot_targets.sh` | 2026-03-12 |
| `.asp/templates/ROADMAP_Template.yaml` | （人工審核） | 2026-03-12 |
| `.asp/templates/SRS_Template.md` | （人工審核） | 2026-03-12 |
| `.asp/templates/SDS_Template.md` | （人工審核） | 2026-03-12 |
| `.asp/templates/UIUX_SPEC_Template.md` | （人工審核） | 2026-03-12 |
| `.asp/templates/DEPLOY_SPEC_Template.md` | （人工審核） | 2026-03-12 |
| `.asp/Makefile.inc` | `tests/test_autopilot_targets.sh` (27/27) | 2026-03-12 |
| `CLAUDE.md` | （人工審核） | 2026-03-12 |
| `.asp/scripts/install.sh` | （人工審核） | 2026-03-12 |

---

## 🚫 禁止事項（Out of Scope）

- 不要修改：既有 profile 的行為邏輯（autopilot 只在上層調度；autonomous_dev 的暫停覆寫規則放在 autopilot.md 內，不修改 autonomous_dev.md 本體）
- 不要修改：task_orchestrator.md 或 autonomous_dev.md
- 不要引入新依賴：所有 Makefile targets 只用 python3 + pyyaml（已有 fallback）

---

## 📎 參考資料（References）

- 相關 ADR：ADR-001
- 現有類似實作：task_orchestrator.md（autopilot 複用其 `on_task_received()` 入口）
- 計畫檔案：`.claude/plans/sunny-popping-dongarra.md`
