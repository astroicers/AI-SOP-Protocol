# Runbook：Startup MVP 從零到上線

> **模式**：ASP L1-L2 | **週期**：4-6 週 | **團隊組成**：NEW_FEATURE_complex

---

## 場景說明

從一份需求文件出發，在 4-6 週內交付可上線的 MVP。速度重要，但品質門檻不得妥協。

---

## Agent 團隊

| 角色 | ASP Agent | 啟動時機 |
|------|-----------|---------|
| 架構師 | `arch` | Week 1 |
| SPEC 撰寫者 | `spec` | Week 1 |
| 依賴分析師 | `dep-analyst` | Week 1 末 |
| 測試作者 | `tdd` | Week 2 前 |
| 實作者 | `impl` | Week 2 |
| 安全審查員 | `sec` | Week 3 |
| QA 驗證者 | `qa` | 貫穿 Week 2-4 |
| Reality Checker | `reality` | Week 4 |
| 文件撰寫者 | `doc` | Week 4 |

---

## 週次執行計劃

### Week 1：探索與架構

```
Day 1-2：需求分析
├── /asp-gate G1 — 確認 ADR 是否必要（有架構影響則必須建立）
├── arch → 建立 ADR（如需要，等 Accepted 才能繼續）
└── arch → 輸出架構影響評估報告

Day 3-4：SPEC 與規劃
├── /asp-gate G2 — 確認 SPEC 七欄位完整、Done When 二元可測試
├── spec → 建立 SPEC 文件（docs/specs/）
├── dep-analyst → 建立任務依賴 DAG
└── 產出：sprint backlog（RICE 優先排序）

Day 5：基礎建設
├── impl → 專案鷹架、CI/CD 設定
└── 品質門檻：架構套件經 arch 審核通過
```

### Week 2-3：核心建置

```
Sprint 1（Week 2）：
├── /asp-gate G3 — 確認測試 FAIL（tdd 先於 impl）
├── tdd → 為每個 Done When 撰寫測試（必須 FAIL）
├── impl → 實作讓測試 PASS 的 production code
├── qa → 每個任務完成後獨立驗證（Dev↔QA loop）
└── Sprint Review：檢視 velocity 與 first-pass QA rate

Sprint 2（Week 3）：
├── 繼續 Dev↔QA loop（max 2 次重派，第 3 次升級）
├── sec → 完成安全審查（auth、API 端點、資料驗證）
└── /asp-gate G4 — make test 100%、make lint 清淨
```

### Week 4：強化與上線準備

```
Day 1-2：品質衝刺
├── qa → 完整 regression 驗證
├── reality → /asp-reality-check（預設 NEEDS_WORK，需壓倒性證據）
└── sec → 最終 credential 掃描

Day 3-4：上線準備
├── /asp-gate G5 — 獨立再驗證通過
├── /asp-gate G5.5 — 跨元件 parity 確認
└── doc → CHANGELOG、README、SPEC Traceability 同步

Day 5：交付決策
├── /asp-gate G6 — /asp-ship 10 步驟完成
├── reality 給出 READY 才能標記完成
└── 人工確認後 git push
```

### Week 5-6（選擇性）：上線後優化

```
├── 收集使用者回饋（首週目標 ≥ 10 名真實使用者）
├── 建立 bug fix 週期（使用 BUGFIX_non_trivial 場景）
└── 規劃下一個 sprint（升級至 ASP L3 的條件確認）
```

---

## 關鍵決策點

| 決策 | 時機 | 決策者 |
|------|------|--------|
| ADR 必要性 | Week 1 Day 1 | arch + 人類 |
| MVP scope 凍結 | Sprint 1 規劃 | 人類 |
| 上線 Go/No-Go | Week 4 Day 5 | reality + 人類 |

---

## 成功指標

| 指標 | 目標 |
|------|------|
| 交付時間 | ≤ 6 週 |
| Make test 通過率 | 100% |
| First-pass QA rate | ≥ 70% |
| 上線後 24h 系統穩定 | 0 P0 事故 |
| SPEC Done When 覆蓋 | 100% |

---

## 常見陷阱

| 陷阱 | 防範措施 |
|------|---------|
| ADR 未 Accepted 就開始實作 | `session-audit.sh` 動態 deny git commit |
| 為求速度跳過 QA | qa 獨立驗證是強制的，非選擇性 |
| 測試未 FAIL 就開始實作 | /asp-gate G3 硬性阻擋 |
| 上線前未跑 asp-ship | G6 阻擋，解除條件只有完成 10 步驟 |

---

## 相關指令

```bash
make spec-new TITLE="MVP 核心功能"   # 建立 SPEC
make adr-new TITLE="技術選型"         # 建立 ADR（如需）
make task-start DESC="Week 1 架構"   # 記錄任務
make asp-enforcement-status           # 確認當前阻擋狀態
```

> 參考：`.asp/agents/team_compositions.yaml` → `NEW_FEATURE_complex`
