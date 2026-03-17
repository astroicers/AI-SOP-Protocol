# 我該從哪裡開始？

> 一頁式快速決策指南。不確定用哪個指令時，從這裡找答案。

---

## 我想做一個新功能

```
1. 評估是否需要 ADR（架構決策）
   └─ 會跨模組？引入新依賴？改 DB Schema？影響 >3 個檔案？
      ├─ YES → make adr-new TITLE="Use XXX for YYY"
      │         等人類將 ADR 狀態改為 Accepted
      └─ NO  → 跳過 ADR，直接建 SPEC

2. 建立 SPEC
   └─ make spec-new TITLE="功能名稱"
      填寫：Goal / Inputs / Outputs / Side Effects /
            Edge Cases / Done When / Rollback Plan

3. 寫測試（先讓測試 FAIL）
   └─ make test-filter FILTER=你的功能名

4. 實作直到測試全 PASS
   └─ make test

5. 提交前檢查
   └─ 使用 /asp-ship 或 make tech-debt-list
```

---

## 我發現了一個 Bug

```
1. 判斷是否 trivial（全部滿足才算 trivial）
   • 影響檔案 ≤ 2
   • 修改行數 ≤ 10
   • 不涉及商業邏輯或架構決策
   不確定 → 視為 non-trivial

2. Non-trivial bug
   └─ make spec-new TITLE="BUG-XXX: 問題描述"
      根因記錄格式：「根因：{module} 的 {function} 未處理 {edge_case}」

3. 先寫能重現 bug 的測試（必須先 FAIL）

4. 修復，確認測試 PASS

5. grep 全專案找相同模式（鐵則，無豁免）
   └─ grep -r "相似 pattern" .

6. 提交前：make test（全量）
```

---

## 我要跑 Autopilot（ROADMAP 驅動）

```
前提：
• 專案根目錄有 ROADMAP.yaml
• 無 → make autopilot-init 建立範本

流程：
1. make autopilot-validate   ← 驗證 SPEC/ADR，更新 CLAUDE.md
2. 告訴 Claude：「開始 autopilot」或 /asp-autopilot
3. Claude 自動執行任務佇列
4. Context 到 75% 時自動暫停 → 開新 session → 自動續接

查看狀態：make autopilot-status
重置狀態：make autopilot-reset
```

---

## 我不知道專案現在的健康狀態

```
快速掃描（僅 blocker）：
└─ make audit-quick

完整審計（7 個維度）：
└─ make audit-health
   維度：測試覆蓋 / SPEC覆蓋 / ADR合規 /
         文件完整 / 程式碼衛生 / 依賴健康 / 文件新鮮度

文件新鮮度：
└─ make doc-audit

Tech Debt 彙總：
└─ make tech-debt-list
```

---

## 我要記錄一個架構決策（ADR）

```
1. make adr-list           ← 查看現有決策，確認下一個編號
2. make adr-new TITLE="..."

填寫：
• Context（為什麼做這個決定）
• Decision（決定了什麼）
• Consequences（trade-off）
• Alternatives Considered（至少 2 個替代方案）

重要：ADR 保持 Draft 直到人類明確改為 Accepted
      AI 不可自行更改 ADR 狀態
```

---

## 我要提交代碼

```
使用 /asp-ship 或手動執行：

1. make test              ← 全量測試必須通過
2. git status             ← 確認變更範圍
3. 檢查 CHANGELOG.md 是否更新
4. 檢查 README.md（用戶可見行為是否改變）
5. make tech-debt-list    ← 確認新增的 tech-debt 有記錄
6. make adr-list          ← 確認無 ADR 被違反

全部通過 → git commit
```

---

## 我要驗證 .ai_profile 設定

```
make profile-validate

會檢查：
• type 欄位是否存在（必填）
• design: enabled 時 frontend_quality 是否也啟用（自動補全）
• hitl / workflow 值是否合法
• 列出將載入的所有 profile 清單
```

---

## 需求在開發中改變了

| 變更等級 | 觸發條件 | 處理方式 |
|---------|---------|---------|
| L1 細節修改 | SPEC 局部調整，Goal 不變 | 直接修改 SPEC，記錄變更 |
| L2 SPEC 推翻 | 功能方向改變 | 標記 SPEC 為 Cancelled，清理半成品 |
| L3 ADR 推翻 | 技術方向要換 | 建新 ADR（Draft），舊 ADR 標 Superseded |
| L4 方向 Pivot | 多個 SPEC/ADR 廢棄 | 暫停開發，建立 Pivot ADR，人類確認 |

---

## 常用指令速查

| 目的 | 指令 |
|------|------|
| 新增 ADR | `make adr-new TITLE="..."` |
| 列出 ADR | `make adr-list` |
| 新增 SPEC | `make spec-new TITLE="..."` |
| 列出 SPEC | `make spec-list` |
| 執行測試 | `make test` |
| 局部測試 | `make test-filter FILTER=xxx` |
| 健康審計 | `make audit-health` |
| 快速審計 | `make audit-quick` |
| Tech Debt | `make tech-debt-list` |
| Profile 驗證 | `make profile-validate` |
| Autopilot 初始化 | `make autopilot-init` |
| Autopilot 驗證 | `make autopilot-validate` |
| Autopilot 狀態 | `make autopilot-status` |
| Session 儲存 | `make session-checkpoint NEXT="..."` |
| 所有指令 | `make help` |

---

> 有疑問？執行 `make help` 查看完整指令列表。
> 想了解 ASP 架構？閱讀 `docs/development-modes.md` 和 `.asp/profiles/`。
