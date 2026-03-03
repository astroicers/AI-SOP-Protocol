# System Development Profile

> 載入條件：`type: system` 或 `type: architecture`

適用：後端服務、微服務、Kubernetes、Docker、API 開發。

---

## ADR 工作流

### 何時必須建立/更新 ADR

| 情境 | 必要性 |
|------|--------|
| 新增微服務或模組 | 🔴 必須 |
| 更換技術棧（DB、框架、協議） | 🔴 必須 |
| 調整核心架構（Auth、API Gateway） | 🔴 必須 |
| 效能優化方向決策 | 🟡 建議 |
| 單一函數邏輯修改 | ⚪ 豁免 |

### ADR 狀態

```
Draft → Proposed → Accepted → Deprecated / Superseded by ADR-XXX
```

### 執行規則

- 提議方案前，先 `make adr-list` 確認是否與現有決策衝突
- ADR 狀態為 `Draft` 時，禁止撰寫對應的生產代碼（鐵則）
- `Accepted` ADR 被推翻時，必須建立新 ADR 說明原因，不可直接修改舊 ADR

### 批次 ADR 預審（Autonomous 模式專用）

當多個功能需要同時進入自主開發時，可使用批次預審流程：

```
FUNCTION batch_adr_review(adr_list):

  // 1. AI 一次性建立所有 ADR（狀態為 Draft）
  FOR adr IN adr_list:
    CREATE adr_from_template(adr)
    adr.status = "Draft"

  // 2. 暫停 — 人類一次性審核所有 ADR
  PAUSE("請審核以下 ADR 並決定是否 Accept：")
  PRESENT(adr_list)

  // 3. 人類審核完畢
  FOR adr IN adr_list:
    IF human_approves(adr):
      adr.status = "Accepted"
    ELSE:
      adr.status = "Rejected"
      REMOVE from autonomous_queue(adr.related_features)

  // 4. 所有 Accepted ADR → AI 進入自主開發，不再暫停
  RETURN accepted_adrs
```

**使用時機**：
- 版本升級（多功能同步開發）
- 人類希望一次審核、一次放行，AI 不間斷執行

**限制**：
- 批次預審不適用於跨版本的架構變更
- 每個 ADR 仍須獨立評估，不可因批次而降低審核標準

---

## 標準開發流程

```
ADR（為什麼）→ [Design Gate] → [OpenAPI Gate] → SDD（如何設計）→ TDD（驗證標準）→ BDD（業務確認）→ 實作 → 文件
               ↑ design: enabled    ↑ openapi: enabled
```

**Bug 修復流程：**

| Bug 類型 | 流程 |
|----------|------|
| 非 trivial（跨模組、邏輯修正、行為變更） | `make spec-new TITLE="BUG-..."` → 分析 → TDD → 實作 → 文件 |
| trivial（單行修復、typo、配置錯誤） | 直接修復，但需在回覆中說明豁免理由 |
| 涉及架構決策 | 同上 + 補 ADR |

**TDD 場景區分：**

| 場景 | TDD 要求 |
|------|----------|
| 新功能 | 🔴 必須測試先於代碼 |
| Bug 修復 | 🟡 可跳過，需標記 `tech-debt: test-pending` |
| 原型驗證 | 🟡 可跳過，需標記 `tech-debt: test-pending` |

**其他允許的簡化路徑（需在回覆中說明）：**

- 明確小功能：可跳過 BDD，直接 TDD

---

## Pre-Implementation Gate

修改原始碼（非 trivial）前，執行此檢查：

```
1. SPEC 確認
   └── make spec-list
       ├── 有對應 SPEC → 確認理解 Goal 和 Done When
       └── 無對應 SPEC → make spec-new TITLE="..."
           └── 至少填寫：Goal、Inputs、Expected Output、Done When（含測試條件）、Edge Cases

2. ADR 確認（僅架構變更時）
   └── make adr-list → 有相關 ADR 且為 Accepted → 繼續
       └── 無相關 ADR → make adr-new TITLE="..."

3. ADR↔SPEC 連動（僅涉及架構變更時）
   └── ADR 狀態為 Accepted → 才能建立對應 SPEC
       ├── SPEC「關聯 ADR」欄位必須填入 ADR-NNN
       └── ADR 為 Draft → 先完成 ADR 審議，不建 SPEC、不寫生產代碼

4. Design Gate（僅 design: enabled 時）
   └── 需求涉及 UI → CALL design_gate(requirement)
       ├── 設計已存在且與需求一致 → 繼續
       └── 設計不存在或不一致 → 建立/更新設計 → 等待人類確認
       └── 純後端需求 → 豁免（需說明理由）

5. OpenAPI Gate（僅 openapi: enabled 時）
   └── 需求涉及 API → CALL openapi_gate(requirement)
       ├── spec 已存在且與需求一致 → 繼續
       └── spec 不存在或不一致 → 建立/更新 spec → 等待人類確認
       └── 純前端需求（不涉及 API） → 豁免（需說明理由）

6. 回覆格式：
   「SPEC-NNN（關聯 ADR-NNN）已確認/已建立，開始實作。」
   或
   「SPEC-NNN 已確認/已建立，無架構影響，開始實作。」
   或
   「trivial 修改，豁免 SPEC，理由：...」
```

**豁免路徑**（需在回覆中明確說明）：
- trivial（單行/typo/配置）→ 直接修復，說明理由
- 原型驗證 → 標記 `tech-debt: spec-pending`，24h 內補 SPEC
- autonomous 模式既有架構延伸 → 可由 AI 建立 SPEC 後直接實作，前提是對應 ADR 已 Accepted

> 此規則依賴 AI 自律執行，無 Hook 技術強制。

---

## 環境管理

以下動作統一使用 Makefile，禁止輸出原生指令：

```
make build    建立 Docker Image
make clean    清理暫存與未使用資源
make deploy   重新部署（需確認）
make test     執行測試套件
make diagram  更新架構圖
make adr-new  建立新 ADR
make spec-new 建立新規格書
```

---

## 部署前檢查清單

```
□ 環境變數完整（對照 .env.example）
□ 所有測試通過（make test）
□ ADR 已標記 Accepted
□ architecture.md 與當前代碼一致
□ Dockerfile 無明顯優化缺失
```

---

## 架構圖維護

- Mermaid 格式，存放於 `docs/architecture.md`
- 核心邏輯變動後必須更新
- 架構圖與代碼不一致 = 技術債，本次任務結束前修正
