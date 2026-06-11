# Spike Mode Profile — L0 探索模式

<!-- requires: global_core -->
<!-- optional: (none) -->
<!-- conflicts: autonomous_dev, autopilot, pipeline, multi_agent -->

適用：L0 (Spike) 等級。快速原型驗證，最小治理約束。
載入條件：`.ai_profile` 中 `level: 0`（由 level-0.yaml 自動載入）

---

## 核心原則

L0 是暫時狀態，不是豁免狀態。所有「跳過」都是**顯式豁免**，
必須在 commit message 中標記 `[spike]`，以便日後清理。

---

## 允許跳過的規則

| 規則 | 豁免條件 |
|------|---------|
| ADR 建立 | spike 可無 ADR 直接實作；進 L1+ 前必須補 ADR |
| SPEC 建立 | spike 可無 SPEC；spike 結束前必須寫 spike-conclusion.md |
| TDD | spike 可先實作後補（或不補）測試 |
| Pipeline gate G1-G6 | 全部跳過 |
| CHANGELOG 更新 | spike 期間可跳過 |

---

## 絕不可跳過（繼承自 global_core 鐵則）

- 破壞性操作防護（git push, rm -rf 等仍受 deny list 保護）
- 敏感資訊保護（API key, 密碼不可 hardcode）
- asp-ship Step 9（憑證掃描）— spike 代碼也不能有硬編碼密碼
- `git push` 前的人類確認（hitl: strict 強制執行）

---

## 強制 HITL: strict

即使 `.ai_profile` 設定了 `hitl: minimal`，L0 強制覆蓋為 `hitl: strict`。
因為你在探索未知領域，每個決策都需要人類確認。

---

## Spike 分支紀律

- L0 代碼必須在 `spike/*` 或 `poc/*` 或 `experiment/*` branch
- **禁止從 L0 直接 commit 到 main**
- Spike 結論寫入 `docs/spike-conclusion.md`（或命名含 spike/poc 的文件）

---

## L0 → L1 升級觸發

AI 在以下情況**必須**提示使用者考慮升級到 L1：

1. 使用者說「這個方向可行，我們繼續開發」
2. Spike 開始第 3 天仍無明確結論（time budget 耗盡）
3. 開始寫第一個非 spike 的正式功能
4. 使用者詢問「這個要加測試嗎」（L0 沒有測試，是時候升級了）

---

## 與其他 Profile 的衝突說明

| 衝突的 Profile | 原因 |
|---------------|------|
| `autonomous_dev` | L0 要求 hitl: strict；autonomous 是 hitl: minimal，兩者互斥 |
| `autopilot` | Autopilot 是跨 session 自動執行；Spike 是一次性探索 |
| `pipeline` | G1-G6 pipeline gate 在 L0 全部跳過；不能同時套用 pipeline |
| `multi_agent` | Multi-agent 有 SPEC + ADR 要求；L0 無這些前提 |

---

## Spike 結束清單

Spike 結束（成功或失敗）前必須完成：

- [ ] 寫入 `docs/spike-conclusion.md`（一段：驗證了什麼、結論、下一步）
- [ ] 標記所有 spike commit（`[spike]` 前綴）
- [ ] 決定：繼續開發（升 L1+）或放棄（關閉 spike branch）
- [ ] 若繼續：把 spike 代碼的 tech debt 記錄為 `tech-debt: spike-cleanup`
