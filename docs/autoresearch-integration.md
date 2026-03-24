# autoresearch 搭配 ASP 使用指南

> [karpathy/autoresearch](https://github.com/karpathy/autoresearch) 是 ML 訓練實驗自動化工具。
> ASP 是軟體開發流程治理框架。兩者層級不同，不合併，但可搭配使用。

---

## 適用場景

| 場景 | 用 autoresearch | 用 ASP | 兩者搭配 |
|------|----------------|--------|---------|
| ML 模型訓練調優 | ✅ | — | — |
| 效能基準測試（固定指標） | ✅ | — | ✅ 結果回填 ADR |
| 演算法 A/B 比較 | ✅ | — | ✅ 決策寫 ADR |
| 新功能開發 | — | ✅ | — |
| Bug 修復 | — | ✅ | — |
| 架構決策 | — | ✅ | — |

---

## 搭配工作流

```
1. ASP: 建立 ADR-NNN "效能調優策略"（Draft）
2. ASP: 建立 SPEC-NNN "效能調優實驗"，Done When 包含目標指標
3. autoresearch: 在獨立分支跑 N 次實驗
4. 人類: 審查 results.tsv，選擇最佳結果
5. ASP: 將最佳 commit cherry-pick 進主分支
6. ASP: 更新 ADR 為 Accepted，記錄實驗數據
7. ASP: 驗證 SPEC Done When → 關閉
```

---

## 為什麼不合併

| 衝突點 | autoresearch | ASP |
|--------|-------------|-----|
| `git reset` | 每次失敗的實驗用 reset 丟棄 | 鐵則禁止 `git reset` |
| 測試 | 不寫測試，只看 `val_bpb` 指標 | TDD 先行，測試是閘門 |
| SPEC | 無，直接修改 `train.py` | 非 trivial 修改必須有 SPEC |
| 暫停機制 | 永不暫停（"The human might be asleep"） | HITL 機制控制暫停條件 |
| 操作範圍 | 單一檔案（`train.py`） | 整個 codebase |

---

## 注意事項

- autoresearch 必須在**獨立分支**操作（`autoresearch/<tag>`），不可在 ASP 管理的主分支上跑
- 最佳結果 cherry-pick 進主分支**前**，必須補齊測試
- 實驗結束後由 ASP 流程接管（走 SPEC gate、更新 ADR）
- autoresearch 的 `program.md` 等同 ASP 的 `.ai_profile` + profiles，概念相同但格式不同

---

## autoresearch 借鏡的設計模式

ASP 已吸收的核心精髓：

| 模式 | autoresearch 實作 | ASP 對應 |
|------|------------------|---------|
| 人類定義策略，agent 執行 | `program.md` | `.ai_profile` + profiles |
| 固定預算迴圈 | 5min 訓練 + keep/discard | autopilot task loop（ROADMAP 驅動） |
| 累積式實驗日誌 | `results.tsv` | SPEC Done When + CHANGELOG |
| Git 作為實驗記錄 | 每次嘗試一個 commit | 每個 task 一個 commit |
