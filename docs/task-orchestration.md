# 任務協調與專案健康審計

`orchestrator: enabled`（或 `autonomous: enabled` 自動載入）時，ASP 提供兩個核心能力。

---

## 專案健康審計

任何時候介入一個專案，ASP 會自動掃描 7 個維度，偵測缺失並強制補齊：

| 維度 | 掃描內容 |
|------|----------|
| 測試覆蓋 | source files vs test files 比對 |
| SPEC 覆蓋 | 主要模組是否有對應 SPEC |
| ADR 覆蓋 | Draft ADR 是否已有實作代碼（鐵則違反） |
| 文件完整性 | README / CHANGELOG / architecture.md 存在與更新時間 |
| 程式碼衛生 | DEPRECATED / TODO 無 owner / tech-debt 標記 |
| 依賴健康 | lock file / loose version / .env.example |
| 文件新鮮度 | SPEC Traceability 的實作檔案 vs SPEC 修改時間 |

```bash
make audit-health    # 完整 7 維度掃描
make audit-quick     # 只檢查 blocker
make doc-audit       # 文件新鮮度掃描
make tech-debt-list  # tech-debt/TODO/FIXME/DEPRECATED 彙總
```

審計結果分為 🔴 Blocker / 🟡 Warning / 🟢 Info。Blocker 必須先修復才能開始主任務。

---

## 任務自動分類與路由

收到任何任務描述時，自動分類為 5 種類型並路由到對應工作流：

| 任務類型 | 工作流摘要 |
|----------|-----------|
| **新增功能** | 架構評估 → ADR(需要時) → SPEC → TDD → 實作 → 驗證 → 文件管線 |
| **修復 Bug** | 嚴重度判斷 → SPEC → 重現測試 → 修復 → grep 全專案 → 文件管線 |
| **修改功能** | 變更等級(L1-L4) → 對應流程 → 測試更新 → 文件管線 |
| **移除功能** | 依賴分析 → deprecation 評估 → 安全移除 → 零殘留驗證 → 文件管線 |
| **複合需求** | 分解子任務 → 分類 → 並行/串行執行 → 整合測試 → 統一文件管線 |

每個工作流結束都經過共用的**文件產出管線**，自動更新 CHANGELOG / README / architecture / SPEC Traceability。
