# Autopilot 標準作業程序（SOP）

`autopilot: enabled` 啟用 ROADMAP 驅動的持續自動執行。AI 讀取 `ROADMAP.yaml`，逐一完成所有任務，直到全部完成或 token 預算耗盡。

**適用場景：** 需求已明確寫入 ROADMAP、前置文件齊備、希望 AI 全自動開發不中斷。

---

## 前置條件

開始前請確認以下條件已滿足：

- [ ] ASP 已安裝（`curl -sSL ... | bash`）
- [ ] 專案根目錄存在 `.ai_profile`
- [ ] `.ai_profile` 中 `type` 已正確設定（system / content / architecture）

---

## 程序一：環境準備

### Step 1. 建立前置文件

依專案技術棧決定需要哪些文件：

| 文件 | 建立指令 | 何時需要 |
|------|----------|---------|
| `docs/SRS.md` | `make srs-new` | **永遠需要** |
| `docs/SDS.md` | `make sds-new` | 有 backend / database / api 時 |
| `docs/UIUX_SPEC.md` | `make uiux-spec-new` | 有 frontend / uiux 需求時 |
| `docs/DEPLOY_SPEC.md` | `make deploy-spec-new` | 有 infra（非 none）時 |

執行對應指令建立模板後，**填寫實際內容**。空模板無法提供 AI 足夠的專案資訊。

> **驗證：** 確認對應文件已存在且內容已填寫。

### Step 2. 建立 ROADMAP

```bash
make autopilot-init
```

此指令會從模板建立 `ROADMAP.yaml`。接著填寫以下區塊：

1. **專案元資料**（`stack`、`requires`、`conventions`、`architecture`）
2. **Milestones 與 Tasks**（每個 task 需有 `id`、`title`、`type`、`status: pending`）

> **驗證：** `ROADMAP.yaml` 存在且至少包含一個 milestone 和一個 task。
> 完整結構請參考 [附錄 B](#附錄-broadmapyaml-結構)。

### Step 3. 驗證

```bash
make autopilot-validate
```

此指令會：
- 檢查 ROADMAP 結構完整性
- 檢查依賴圖（無循環依賴）
- 驗證引用的 ADR 檔案存在
- 驗證所有文件路徑存在
- **自動產生 CLAUDE.md 的「專案概覽」區塊**（從 ROADMAP + .ai_profile + SRS 組合）

> **驗證：** 指令執行無錯誤，CLAUDE.md 中出現 `<!-- ASP-AUTO-PROJECT-DESCRIPTION -->` 區塊。

### Step 4. 啟用 Autopilot

編輯 `.ai_profile`，設定：

```yaml
autopilot: enabled
```

> **驗證：** `make autopilot-status` 顯示就緒狀態。

---

## 程序二：啟動與執行

### Step 1. 開啟新的 Claude Code session

關閉現有 session，開啟新 session 以載入最新設定。

### Step 2. 輸入啟動指令

```
請讀取 CLAUDE.md，依照 .ai_profile 載入對應 Profile，後續遵循 ASP 協議。
```

### Step 3. AI 自動執行

啟動後 AI 會依序執行以下流程，**全程無需人工確認**：

1. 載入 ROADMAP → 依 `stack` / `requires` 動態載入對應 Profile
2. 更新 CLAUDE.md 專案描述（若過期）
3. 驗證前置文件與 ADR 狀態
4. 建立任務佇列（依拓撲排序處理依賴）
5. 執行專案健康審計
6. 逐一執行任務（每個 task 走 SPEC → TDD → 實作 → 文件同步）
7. 全部完成或 token 耗盡時結束

### Step 4. 監控進度

在另一個終端執行：

```bash
make autopilot-status
```

顯示：目前狀態、已完成/失敗/阻塞的任務數、當前正在執行的任務。

---

## 程序三：跨 Session 續接

### Step 1. Session 中斷

當 context 使用量超過 75% 或 token 耗盡時，AI 會自動：

- 將執行狀態寫入 `.asp-autopilot-state.json`
- 更新 `ROADMAP.yaml` 中已完成任務的 status
- 輸出摘要（已完成 / 失敗 / 剩餘任務數）

### Step 2. 開啟新 Session 續接

開啟新 Claude Code session，輸入同樣的啟動指令。AI 偵測到 state 檔後會自動從上次中斷處繼續，**無需手動操作**。

### Step 3. 驗證續接狀態

```bash
make autopilot-status
```

> **驗證：** session_count 遞增，completed 數量與前次一致，當前任務為上次中斷後的下一個。

---

## 程序四：重置與清理

若需要重新開始 autopilot 執行：

```bash
make autopilot-reset
```

此指令會：
- 刪除 `.asp-autopilot-state.json`（執行狀態）
- **不會修改** `ROADMAP.yaml`（任務定義保持不變）

若需重置個別任務狀態，手動編輯 `ROADMAP.yaml` 中對應 task 的 `status` 欄位。

---

## 故障排除

| 問題 | 可能原因 | 處理方式 |
|------|---------|---------|
| Task 被標記 `blocked` | ADR 未 Accepted / 依賴的 task 未完成 / 依賴循環 | 完成依賴項或將 ADR 狀態改為 Accepted，重新啟動 |
| Task 被標記 `failed` | 自動修復失敗 ≥3 次 | 檢查錯誤 LOG，手動修復後將 status 改回 `pending`，重新啟動 |
| Autopilot 未自動續接 | state 檔不存在 / status 非 `in_progress` | 確認 `.asp-autopilot-state.json` 存在，或執行 `make autopilot-reset` 後重新啟動 |
| CLAUDE.md 描述未更新 | 缺少標記註解 / ROADMAP 解析錯誤 | 執行 `make autopilot-validate` 檢查錯誤訊息 |
| AI 跳過某些任務 | 任務的 `depends_on` 指向未完成的 task | 檢查 ROADMAP 依賴關係，優先完成前置任務 |
| `make autopilot-validate` 報錯 | ROADMAP.yaml 格式錯誤 / 引用的 ADR 不存在 | 依錯誤訊息修正 ROADMAP.yaml |

---

## 附錄 A：零確認執行策略

Autopilot 啟動後**不會提出任何確認問題**，所有決策由 AI 自主完成：

| 情境 | 自主處理策略 |
|------|------------|
| CLAUDE.md 專案描述過期 | 從 ROADMAP.yaml + .ai_profile + SRS 自動更新 |
| 前置文件缺失 | 自動執行 `make srs-new` 等建立模板 |
| ADR 不存在 | 自動建立 Draft ADR，標記相關 task 為 blocked 並跳過 |
| ADR 未 Accepted | 標記相關 task 為 blocked 並跳過（不違反鐵則） |
| 依賴循環 | 標記涉及的 tasks 為 blocked，繼續其他獨立 task |
| git push | 僅 commit，不 push。結束時報告 "N commits ready to push" |
| git rebase | 禁止，使用 merge |
| docker push / deploy | 跳過，記錄 post-autopilot 待辦 |
| 刪除檔案 | SPEC 範圍內暫存檔可刪；其他檔案備份（.bak）後刪 |
| 範圍超出 | 記錄 `tech-debt` 標記，繼續當前 task |
| 新增外部依賴 | ROADMAP stack 定義的標準依賴自動允許；非標準記 tech-debt |
| DB Schema 變更 | SPEC 指定時自動執行；未指定記 tech-debt |
| auto_fix 失敗 | task 標記 failed，跳過，繼續下一個獨立 task |
| context > 75% | 存 checkpoint，下次 session 自動續接 |

---

## 附錄 B：ROADMAP.yaml 結構

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

## 附錄 C：前置文件對照表

| 文件 | Make Target | 必要條件 |
|------|-------------|---------|
| `ROADMAP.yaml` | `make autopilot-init` | 永遠 |
| `docs/SRS.md` | `make srs-new` | 永遠 |
| `docs/SDS.md` | `make sds-new` | backend / database / api |
| `docs/UIUX_SPEC.md` | `make uiux-spec-new` | uiux / frontend |
| `docs/DEPLOY_SPEC.md` | `make deploy-spec-new` | infra != none |

---

## 附錄 D：安全邊界

### 可自主執行（不暫停）

| 類別 | 範圍 | 條件 |
|------|------|------|
| 讀取 ROADMAP | 解析任務佇列 | 永遠 |
| 自動建立 SPEC | `make spec-new` + 填寫 | task.spec 為 null 時 |
| 更新 ROADMAP status | 修改 task/milestone 狀態 | 任務完成/失敗/阻塞時 |
| 更新 state 檔 | 寫入 `.asp-autopilot-state.json` | 每次任務開始/完成時 |
| 動態載入 profile | `ENSURE_LOADED()` | ROADMAP requires 欄位 |
| 跳過 blocked task | 繼續下一個獨立任務 | 依賴未滿足時 |

### 禁止（即使 autopilot 模式也不可）

| 類別 | 說明 |
|------|------|
| 修改 ROADMAP task 定義 | 不可修改 title / type / description / depends_on / priority |
| 新增非 ROADMAP 任務 | 不可自行新增 ROADMAP 中不存在的任務 |
| 跳過 SPEC 建立 | 每個 task 必須有對應 SPEC |
| ADR 狀態變更 | 繼承 autonomous_dev 鐵則 |
| 跳過 TDD | 繼承 autonomous_dev 鐵則 |
