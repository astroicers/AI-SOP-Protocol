# Autopilot 模式

`autopilot: enabled` 啟用 ROADMAP 驅動的持續自動執行。AI 讀取 `ROADMAP.yaml`，逐一完成所有任務，直到全部完成或 token 預算耗盡。

---

## 工作流

```
1. GitHub 開專案
2. 安裝 ASP（curl -sSL ... | bash）
3. 建立前置文件（make srs-new / sds-new / uiux-spec-new / deploy-spec-new，按需）→ 填寫內容
4. 建立 ROADMAP（make autopilot-init）→ 填寫任務清單
5. 驗證（make autopilot-validate）→ 自動產生 CLAUDE.md 專案描述
6. 設定 .ai_profile 的 autopilot: enabled → 啟動
7. AI 自動執行所有任務 → token 用盡 → 存 checkpoint → 新 session 自動續接
```

---

## 零確認執行

Autopilot 啟動後**不會提出任何確認問題**，所有決策由 AI 自主完成：

| 情境 | 自主處理策略 |
|------|------------|
| CLAUDE.md 專案描述過期 | 從 ROADMAP.yaml + .ai_profile + SRS 自動更新 |
| 前置文件缺失 | 自動執行 `make srs-new` 等建立模板 |
| ADR 未 Accepted | 標記 task 為 blocked，跳過繼續 |
| 依賴循環 | 標記涉及的 tasks 為 blocked，繼續其他 |
| git push | 僅 commit，不 push |
| 新增外部依賴 | stack 標準依賴自動允許；非標準記 tech-debt |
| task 失敗 | 標記 failed，跳過，繼續下一個獨立 task |
| context > 75% | 存 checkpoint，下次 session 自動續接 |

---

## ROADMAP.yaml

ROADMAP 頂層攜帶專案元資料，autopilot 據此自動載入對應 profile 並探測必要前置文件：

```yaml
version: "1.0"
project: my-app

stack:
  frontend: react        # → 自動載入 frontend_quality，探測 UIUX_SPEC
  backend: go            # → 探測 SDS
  database: postgres     # → 探測 SDS
  infra: kubernetes      # → 探測 DEPLOY_SPEC

requires:
  uiux: true             # → 載入 design_dev + 探測 UIUX_SPEC
  api: true              # → 載入 openapi + 探測 SDS API 段落

milestones:
  - id: M1
    title: "MVP"
    tasks:
      - id: T001
        title: "使用者認證"
        type: NEW_FEATURE
        adr: ADR-001
        depends_on: []
        status: pending
```

完整 ROADMAP 結構（含 conventions、architecture、quality、security、observability）請參考 `.asp/templates/ROADMAP_Template.yaml`。

---

## 前置文件體系

| 文件 | Make Target | 必要條件 |
|------|-------------|---------|
| `ROADMAP.yaml` | `make autopilot-init` | 永遠 |
| `docs/SRS.md` | `make srs-new` | 永遠 |
| `docs/SDS.md` | `make sds-new` | backend / database / api |
| `docs/UIUX_SPEC.md` | `make uiux-spec-new` | uiux / frontend |
| `docs/DEPLOY_SPEC.md` | `make deploy-spec-new` | infra != none |

---

## 跨 Session 續接

Autopilot 將執行狀態存入 `.asp-autopilot-state.json`（已加入 `.gitignore`）。新 session 偵測到 state 檔時自動續接，無需手動操作。

```bash
make autopilot-status  # 查看當前進度
make autopilot-reset   # 重置狀態（ROADMAP 不動）
```
