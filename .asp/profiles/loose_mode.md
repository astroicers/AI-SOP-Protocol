# Loose Mode — 鬆治理模式（探索 + 規格驅動入門）

<!-- requires: global_core -->
<!-- optional: (none) -->
<!-- conflicts: autonomous_dev, autopilot, pipeline, multi_agent -->

適用：`loose` 等級（吸收 v4 的 L0 Spike + L1 Starter）與 vibe-coding 工作流。
載入條件：`level: loose`（legacy `0`/`1` 自動映射）或 `workflow: vibe-coding`

> **v5 合併來源**（ADR-014）：原 vibe coding + spike mode 兩個 profile 併為本檔。
> HITL 等級定義（`should_pause()` + minimal 行為規範）已上移 `global_core.md`（全域概念）。
> 原檔完整保存於 `docs/archive/profiles/`。

---

## 角色分工

```
人類（決策者）              AI（實作者）
─────────────────────────────────────
撰寫 SPEC-002 ────────→  執行 SPEC-001 中
確認設計方案  ←────────  規格複述 + 計畫
驗收成果      ←────────  Done Checklist
撰寫 SPEC-003 ────────→  執行 SPEC-002 中
```

核心原則：人類決策與 AI 實作的節奏**不互相等待**。

---

## AI 執行規則

拿到 SPEC 後：

1. **複述理解**：一段話說明 Goal 和 Done When 的理解
2. **列出計畫**：修改的檔案清單與修改理由
3. **等待確認**（HITL: standard / strict 時；等級定義見 global_core「HITL 等級與暫停決策」）
4. **自我驗收**：執行 Done When 清單並回報結果

**無 SPEC 時的處理：**
- 人類直接描述需求（非提供 SPEC）→ AI 主動建議 `make spec-new TITLE="..."` 並協助填寫
- 至少確認 Goal 和 Done When 後再開始實作
- 對話中可簡化為「口頭 SPEC」：AI 複述 Goal + Done When，人類確認後視為等效

---

## 探索豁免（Spike Exemption）

探索/原型驗證是暫時狀態，不是豁免狀態。所有「跳過」都是**顯式豁免**，
必須在 commit message 中標記 `[spike]`，以便日後清理。

| 規則 | 豁免條件 |
|------|---------|
| ADR 建立 | spike 可無 ADR 直接實作；轉正式開發前必須補 ADR |
| SPEC 建立 | spike 可無 SPEC；spike 結束前必須寫 spike-conclusion.md |
| TDD | spike 可先實作後補（或不補）測試 |
| Pipeline gate G1-G6 | 全部跳過（loose 等級本就不載入 pipeline） |
| CHANGELOG 更新 | spike 期間可跳過 |

**豁免期間 HITL 強制 strict**（ADR-014 D1，保留較嚴格者）：
即使 `.ai_profile` 設定 `hitl: minimal`，使用 spike 豁免的活動一律以 `hitl: strict` 執行——
你在探索未知領域，每個決策都需要人類確認。spike 範疇外的一般開發依設定的 HITL 等級。

### Spike 分支紀律

- Spike 代碼必須在 `spike/*` 或 `poc/*` 或 `experiment/*` branch
- **禁止從 spike branch 直接 commit 到 main**
- Spike 結論寫入 `docs/spike-conclusion.md`（或命名含 spike/poc 的文件）

### Spike 結束清單

Spike 結束（成功或失敗）前必須完成：

- [ ] 寫入 `docs/spike-conclusion.md`（一段：驗證了什麼、結論、下一步）
- [ ] 標記所有 spike commit（`[spike]` 前綴）
- [ ] 決定：繼續開發（轉正式流程）或放棄（關閉 spike branch）
- [ ] 若繼續：把 spike 代碼的 tech debt 記錄為 `tech-debt: spike-cleanup`

---

## 絕不可跳過（繼承自 global_core 鐵則）

- 破壞性操作防護（git push, rm -rf 等仍受 deny list 保護）
- 敏感資訊保護（API key, 密碼不可 hardcode）
- asp-ship Step 9（憑證掃描）— spike 代碼也不能有硬編碼密碼
- `git push` 前的人類確認

---

## 升級觸發（loose → standard）

AI 在以下情況**必須**提示使用者考慮升級到 `standard`：

1. 使用者說「這個方向可行，我們繼續開發」
2. Spike 開始第 3 天仍無明確結論（time budget 耗盡）
3. 開始寫第一個非 spike 的正式功能
4. 使用者詢問「這個要加測試嗎」（是時候啟用 pipeline gates 了）
5. 出現外部協作者 commit（個人專案變多人專案）

---

## Context 管理

長 session 的 context 會衰退，優化原則：**tokens-per-task（完成任務的總消耗）比 tokens-per-request 更重要**。

**壓縮觸發**：context 使用率 > 70% 或對話超過 50 回合時，執行 `make session-checkpoint` 並產出結構化摘要（Session Intent / Files Modified / Decisions Made / Current State / Next Steps）。

**衰退信號辨識**（任一出現 → 立即壓縮）：

| 模式 | 信號 |
|------|------|
| 中段遺忘（lost-in-middle） | AI 忽略對話中段的指令或決策 |
| 資訊汙染（poisoning） | AI 依據錯誤/過時的 context 行動 |
| 干擾（distraction） | AI 被無關資訊帶偏，偏離任務目標 |
| 矛盾（clash） | AI 在矛盾指令間擺盪，輸出不一致 |

**主動預防**：每 30 回合主動 `make session-checkpoint`；Stage 完成時 AI 重述當前 SPEC 的 Goal 和 Done When（重述偏差 → 從檔案系統重讀 SPEC；無法重述 → checkpoint + 新 session）。

**不可跨 session 繼承的資訊**（新 session 必須從檔案系統重新讀取）：
ADR 狀態、測試基線、架構圖、依賴版本、其他人的 commit。

---

## 模型選擇與 Rate Limit

| 任務類型 | 建議層級 | 理由 |
|----------|---------|------|
| 架構設計、ADR 撰寫 | 強 | 需要深度推理 |
| 樣板代碼、重複性生成 | 輕 | 省 Token |
| 單元測試 | 中 | 結構化但需理解上下文 |
| 文件整理 | 輕 | 格式化工作 |

觸發 Rate Limit 時 → 切換至文件工作（寫 SPEC、更新 ADR、整理文件），並行準備原則：AI 執行 TASK-A 時，人類已在準備 TASK-B 的 SPEC。切換前 `make session-checkpoint NEXT="..."` 儲存進度。

---

## 與其他 Profile 的衝突說明

| 衝突的 Profile | 原因 |
|---------------|------|
| `autonomous_dev` | spike 豁免要求 hitl: strict；autonomous 以 hitl: minimal 運作，兩者互斥 |
| `autopilot` | Autopilot 是跨 session 自動執行；loose 是人類節奏驅動 |
| `pipeline` | G1-G6 gates 與 spike 豁免互斥；gates 屬 standard+ 等級 |
| `multi_agent` | Multi-agent 有 SPEC + ADR 前提；loose 無此前提（歷史名，v4.3 已併入 task_orchestrator） |

> 衝突裁決（消費端規則，ADR-014 D3/D8）：由 `workflow: vibe-coding` 衍生載入且同時啟用
> autonomous/autopilot 時，丟棄本 profile 並輸出 WARNING（向後相容）；顯式 `level: loose`
> 又啟用 autopilot 屬設定錯誤，編譯期（asp-compile）直接報錯。
