# [ADR-001]: Autopilot — Roadmap 驅動持續執行

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-03-12 |
| **決策者** | 專案維護者 |

---

## 背景（Context）

ASP 目前的自動化是「單任務」粒度：task_orchestrator 接收一個任務 → 分類 → 執行 → 完成報告。使用者必須手動餵入下一個任務。這導致兩個問題：

1. **缺少外層迴圈**：無法讀取結構化的 Roadmap 文件，自動逐一執行所有任務直到完成或 token 用盡
2. **缺少跨 session 續接**：`make session-checkpoint` 產出的是 narrative markdown，不是機器可解析的狀態，新 session 無法自動續接
3. **缺少前置文件體系**：ASP 僅有 ADR/SPEC/Postmortem 模板，缺少 SRS（需求規格）、SDS（設計規格）、UI/UX 規格、部署規格等高階文件模板，導致開發方向容易偏離

使用者期望的工作流：
```
撰寫前置文件（SRS + SDS + UI/UX Spec + Deploy Spec）
  → 產出 ROADMAP.yaml（結構化任務清單）
  → 設定 autopilot: enabled
  → AI 自動執行所有任務，token 用盡時存 checkpoint
  → 新 session 自動續接
```

---

## 評估選項（Options Considered）

### 選項 A：擴展現有 task_orchestrator

- **優點**：不引入新 profile，修改集中在一個檔案
- **缺點**：task_orchestrator 已有 ~900 行，職責過重（健康審計 + 任務分類 + 5 種工作流 + 文件管線）；加入 Roadmap 解析、任務佇列、跨 session 狀態管理會讓它更難維護
- **風險**：違反單一職責原則，未來修改牽連範圍過大

### 選項 B：外部 CI/CD 調度

- **優點**：利用 GitHub Actions / GitLab CI 等成熟工具管理任務排程
- **缺點**：脫離 Claude CLI 生態；需要額外的基礎設施配置；無法利用 ASP 的 profile 系統和安全邊界
- **風險**：增加使用門檻，與 ASP「一鍵啟用」的設計哲學矛盾

### 選項 C：新 profile + 前置文件體系 + 複用現有 orchestrator

- **優點**：
  - 職責分離：autopilot 負責外層迴圈（Roadmap 解析、任務佇列、跨 session 狀態），task_orchestrator 負責單任務執行
  - 前置文件模板確保開發方向不偏離
  - ROADMAP.yaml 頂層元資料（tech stack、requires）驅動 profile 動態載入和前置文件動態探測
  - 完全複用現有基礎設施：`on_task_received()`、`auto_fix_loop()`、健康審計、Makefile targets
- **缺點**：新增 6 個檔案、修改 4 個檔案
- **風險**：新 profile 與現有 profile 的邊界需明確定義

---

## 決策（Decision）

我們選擇 **選項 C：新 profile + 前置文件體系 + 複用現有 orchestrator**，因為：

1. **職責分離**：autopilot.md 只處理「什麼任務要做、按什麼順序、跨 session 怎麼續接」；task_orchestrator.md 繼續處理「單一任務怎麼執行」
2. **前置文件體系**：提供 SRS、SDS、UI/UX Spec、Deploy Spec 四種模板，根據 ROADMAP.yaml 的 stack/requires 動態探測哪些是必要的
3. **最大複用**：每個任務通過 `on_task_received()` 進入 task_orchestrator，所有鐵則、TDD、SPEC、ADR 驗證、文件管線保持不變
4. **Session Bridge**：`.asp-autopilot-state.json` 提供機器可解析的跨 session 狀態，與 ROADMAP.yaml 的 task status 雙軌追蹤（state 檔 gitignored，ROADMAP 變更 committed）

### 實作範圍

**新增 6 個檔案**：
- `.asp/profiles/autopilot.md` — 核心 profile
- `.asp/templates/ROADMAP_Template.yaml` — 含 stack/requires/conventions/architecture/quality/security/observability 元資料
- `.asp/templates/SRS_Template.md` — 含 FR/US/UC/資料模型/介面規格/追溯矩陣
- `.asp/templates/SDS_Template.md` — 含系統架構/模組設計/資料設計/API 合約/安全設計
- `.asp/templates/UIUX_SPEC_Template.md` — 含 Design System/頁面流程/元件規格/響應式/無障礙
- `.asp/templates/DEPLOY_SPEC_Template.md` — 含環境定義/Container/CI-CD/監控/災難復原

**修改 4 個檔案**：
- `.asp/Makefile.inc` — +7 targets
- `CLAUDE.md` — +autopilot 欄位、Profile 對應表、啟動程序、速查表
- `.asp/scripts/install.sh` — +autopilot 欄位處理
- `.asp/VERSION` — 2.5.0 → 2.6.0

---

## 後果（Consequences）

**正面影響：**
- 使用者只需提供前置文件和 ROADMAP.yaml，即可讓 AI 自動執行到完成
- 跨 session 自動續接，最大化利用 Claude CLI token 預算
- 前置文件體系確保開發方向不偏離（動態探測缺失文件）
- 完全向後相容：不啟用 autopilot 的專案不受任何影響

**負面影響 / 技術債：**
- 新增 6 個檔案增加維護面積
- ROADMAP.yaml 格式一旦發布，後續版本變更需考慮向後相容

**後續追蹤：**
- [ ] 實作完成後進行整合測試
- [ ] 收集第一批使用者回饋，評估前置文件模板的實用性
- [ ] 評估是否需要 `make autopilot-generate-roadmap`（從 SRS 自動產出 ROADMAP）

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| Makefile targets 全部正常 | 11/11 測試通過 | `tests/test_autopilot_targets.sh` | 實作完成時 |
| 既有 targets 無迴歸 | 0 個失敗 | 全量 `make test`（若存在） | 實作完成時 |
| 前置文件模板可正確建立 | 4/4 模板可用 | `make srs-new && make sds-new && make uiux-spec-new && make deploy-spec-new` | 實作完成時 |
| install.sh 支援 autopilot | `.ai_profile` 包含 autopilot 欄位 | install.sh 整合測試 | 實作完成時 |
| 跨 session 續接可用 | state 檔正確讀寫 | 手動模擬 checkpoint + resume | 實作完成時 |

> 重新評估時機：若使用者回饋前置文件模板過於繁瑣或不實用，應簡化模板結構。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - `task_orchestrator.md` — autopilot 複用其 `on_task_received()` 入口
  - `autonomous_dev.md` — autopilot 繼承其安全邊界
  - `vibe_coding.md` — autopilot 複用其 context 管理規則
