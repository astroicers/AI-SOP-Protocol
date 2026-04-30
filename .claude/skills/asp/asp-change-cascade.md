---
name: asp-change-cascade
description: |
  Use when handling requirement changes that occur during implementation.
  Handles: change level determination (L1-L4), cascade action execution,
  scope impact assessment, ADR/SPEC cleanup protocols, pivot management.
  Triggers: change cascade, requirement change, 需求變更, scope change, change request,
  requirement changed, 需求改了, scope changed, pivot, 方向改變, adr override,
  spec cancelled, 功能改了, 需求有更新, change level, determine change level.
---

# ASP Change Cascade Skill

需求變更回溯協議。處理實作過程中 SPEC / ADR / 產品方向發生變更時的分級回溯。本 skill 自包含，L1-L4 協議直接內嵌，不依賴外部 profile。

---

## 變更等級判定

| 等級 | 觸發條件 | 範例 |
|------|----------|------|
| **L1 — 細節修改** | SPEC 的 Inputs/Outputs/Edge Cases 局部調整，Goal 不變 | 追加一個 optional 欄位、修改錯誤碼 |
| **L2 — SPEC 推翻** | SPEC 的 Goal 被推翻，或開發中的 SPEC 被廢棄 | 功能方向改變、半成品需清理 |
| **L3 — ADR 推翻** | Accepted ADR 被外部因素推翻，技術方向要換 | 換 DB、換協議、換認證方案 |
| **L4 — 方向 Pivot** | 多個 SPEC / ADR 同時廢棄，產品方向大幅改變 | 砍掉整個模組、轉換商業模式 |

**判定原則**：
- 不確定等級時，選**較高等級**（保守原則）
- L2 以上必須暫停並等待人類確認，即使 `hitl: minimal`

---

## L1 — 細節修改

**不需要新建 ADR / SPEC，不需要暫停。**

```
步驟：
1. 直接修改現有 SPEC
   → 在 SPEC 底部追加「變更記錄」區塊：
     | 日期 | 變更內容 | 原因 |
     |------|---------|------|
     | YYYY-MM-DD | {變更內容} | {原因} |

2. 評估已寫程式碼和測試的受影響範圍：
   ├── 不受影響 → 繼續開發
   └── 受影響 → 列出需修改的檔案，更新後重跑 make test

3. 更新 CHANGELOG.md：
   - Added/Changed: {變更摘要}
```

**影響範圍評估提示**：

```bash
# 找出引用 SPEC 的程式碼（確認變更影響）
grep -r "SPEC-{NNN}" . --include="*.{ts,tsx,js,jsx,py,go,java}"

# 找出受影響的函式 / 欄位
grep -r "{受影響的欄位名或函式名}" . --include="*.{ext}"
```

---

## L2 — SPEC 推翻

**必須暫停，等待人類確認後才執行。**

```
步驟：
1. 將 SPEC 標記為 Cancelled
   → 在 SPEC header 加入：
     | **狀態** | Cancelled — 原因：{原因} — 日期：{YYYY-MM-DD} |

2. 盤點半成品（列出清單給使用者確認）：
   ├── 已提交的程式碼 → revert commit 或建立清理 SPEC
   ├── 已寫但未提交的程式碼 → git stash 或刪除，說明處置方式
   └── 已寫的測試 → 評估是否有獨立價值（若有則保留，否則隨程式碼清理）

3. 檢查 Side Effects：
   → 查看 SPEC 的「Side Effects」欄位
   → 找出已影響的其他模組
   └── 已影響 → 建立「清理 SPEC」處理殘留狀態

4. 更新 CHANGELOG.md：
   - Removed: SPEC-{NNN} 已取消，原因：{原因}

5. [等待人類確認] 確認後才執行清理
```

**反向掃描指令**：

```bash
# 找出引用此 SPEC 的所有程式碼
grep -r "SPEC-{NNN}" . --include="*.{ts,tsx,js,jsx,py,go,java,md}"
```

---

## L3 — ADR 推翻

**必須暫停，等待人類確認後才執行。新 ADR Accepted 後才能開始新方向的實作。**

```
步驟：
1. 建立新 ADR（Draft 狀態）：
   make adr-new TITLE="Replace ADR-{舊NNN}: {新方向描述}"
   → 新 ADR 的「背景」說明為什麼舊 ADR 被推翻

2. 舊 ADR 標記為 Superseded：
   → 在舊 ADR header 加入：
     | **狀態** | Superseded by ADR-{新NNN} — 日期：{YYYY-MM-DD} |

3. 觸發反向掃描（找出所有引用舊 ADR 的產物）：
   grep -r "ADR-{舊NNN}" . --include="*.{md,ts,tsx,js,jsx,py,go}"
   
4. 受影響的 SPEC 逐個處理（輸出清單給人類確認）：
   ├── 仍有效（技術方向變但功能需求不變）→ 更新「關聯 ADR」指向新 ADR
   └── 不再有效 → 按 L2 流程處理

5. [等待人類確認] 新 ADR 進入 Accepted 狀態

6. 新 ADR Accepted 後，才能開始基於新方向的實作
   → 影響 team_pick：大概率需要升級至 MODIFICATION_L3_L4 場景
```

---

## L4 — 方向 Pivot

**必須立即暫停所有進行中的開發。強制等待人類確認。**

```
步驟：
1. 立即暫停所有進行中的 SPEC 開發
   → multi-agent 模式：暫停所有軌道

2. 建立 Pivot ADR：
   make adr-new TITLE="PIVOT-{方向描述}"
   → 記錄：
     - 舊方向（被放棄的方向）
     - 新方向（即將採用的方向）
     - 推翻原因（為什麼改方向）
     - 影響範圍評估（初步）

3. 批次盤點（輸出清單，不可 AI 自行決定哪些要廢）：
   make spec-list   # 輸出所有 SPEC，標記 Active / Cancelled / Needs-Revision
   make adr-list    # 輸出所有 ADR，標記 Active / Deprecated
   
   輸出摘要表格（格式）：
   | SPEC/ADR | 現狀 | Pivot 後建議 | 理由 |
   |---------|------|------------|------|
   | SPEC-NNN | Active | Cancelled | {原因} |
   | ADR-NNN | Active | Deprecated | {原因} |

4. [強制停點] 等待人類確認批次盤點結果

5. 人類確認後執行：
   ├── Cancelled 的 SPEC → 按 L2 批次清理
   ├── Deprecated 的 ADR → 按 L3 批次處理
   └── Needs-Revision 的 SPEC → 更新 Goal，重新走 Pre-Implementation Gate

6. 建立 session-checkpoint（確保跨 session 不丟失 pivot 決策）：
   → 記錄到 .asp-handoffs/ 目錄，使用 SESSION_BRIDGE 類型
```

---

## 共通規則（所有等級）

- 所有等級的變更記錄都寫入 `CHANGELOG.md`
- **L2 以上必須暫停並等待人類確認**（即使 `hitl: minimal`）
- 不可因為「反正要改」而跳過清理——殘留的半成品比缺少的功能更危險

---

## 影響範圍評估（輸出格式）

執行此 skill 時，先輸出影響範圍評估：

```
CHANGE CASCADE ASSESSMENT

變更描述：{一句話說明什麼改了}
判定等級：{L1 / L2 / L3 / L4}
判定依據：{為什麼是這個等級}

影響範圍：
- 直接影響 SPEC：{SPEC-NNN, SPEC-MMM, ...}
- 直接影響 ADR：{ADR-NNN, ... 或「無」}
- 半成品程式碼：{已提交 / 未提交 / 無}
- 受影響的模組：{模組列表}

建議動作：
{按等級列出 L1/L2/L3/L4 的具體步驟}

{L2+} [等待使用者確認後再執行]
```

---

## team_pick 對照

| 變更等級 | 對應 team_compositions 場景 |
|----------|--------------------------|
| L1 | MODIFICATION_L1_L2 |
| L2 | MODIFICATION_L1_L2 |
| L3 | MODIFICATION_L3_L4 |
| L4 | MODIFICATION_L3_L4（含 PIVOT ADR 建立） |