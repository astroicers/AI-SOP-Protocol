# [ADR-032]: 停用並凍結 asp-operator 感知層柱，ADR-012 信任模型標 dormant

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-08-04 |
| **決策者** | astroicers（grill-with-docs session 逐分支拍板）+ AI（探索、拷問、蒸餾） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）
> ⬆️ 由 `Draft` 升 `FIRM`：使用者 2026-08-04 指示「FIRM 的 POC 驗證先做」，AI 執行 POC-1/2/3（見 Verification Evidence）。承重宣稱「凍結對 ASP session 零爆炸半徑」實證成立；POC 另揭生產者/消費端 schema drift（`source.type` vs 扁平 `source_type`），凍結下無害、納入蒸餾 A/C。FIRM 允許 commit，audit 輸出 🟡；待人類 `/asp:approve-adr` 升 `Accepted` 後方全面執行 Decision 各 Locus。
> ⬆️ 由 `FIRM` 升 `Accepted`：使用者 2026-08-05 透過 `/asp:approve-adr 32` 呼叫、看完本指令摘要的決策與 Verification Evidence（POC-1 零爆炸半徑實證成立、POC-2 揭 schema drift 且 harmless under freeze、POC-3 workflow_dispatch 可逆）後明確同意（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。

---

## 背景（Context）

起點是一個提問：「asp 與 asp-operator 兩專案的意義與**整並**的思路」。經 grill-with-docs 逐分支拷問後，**問題前提被推翻**：

1. **文件從沒有人主張整並。** 跨兩 repo 搜 `整並/整合/merge/monorepo/併入`，唯一往結構走的文件（`docs/research/2026-06-22-external-benchmark-reflection.md`）反而主張把 ASP 拆更多 repo。被文件化的決策是「刻意分開」——三柱模型（operator README）+ ADR-012 反覆稱其「跨 repo 工作」 + ADR-001 最小權限 App 身分。

2. **使用者真動機是「不發散」＋「怕處理不好反而更貴」**，且自陳：**asp-operator 現在不會用、也不記得要用**。

3. **真正的問題不是「怎麼整並」，而是**：為何要為一個零實現價值的元件，持續扛著三份成本——
   - 一條獨立 ADR 序列（本 repo ADR-012 竟驅動 operator repo ADR-002 的認知稅）；
   - 一個以 GitHub App 身分（App ID 3996872）、對所有 opt-in repo **每 30 分鐘無人值守輪詢**的服務——正是 T-14「external-artifact → autopilot trust」的活體攻擊面；
   - 整套 ADR-012 信任模型（provenance/held/INV-1/INV-2/DP4），其存在前提正是「有一個外部機器生產者」。

4. **技術前提（已用 code 證實，零副作用）**：`inbox-ingest.sh:15` 明寫「永遠 exit 0（不阻擋 session）」，inbox 檔不存在（`:26`）或無 pending（`:30`）皆靜默退出；`session-audit.sh:414` 整段被 `[ -f "$INBOX_FILE" ]` 守住，至多吐 A15.1 **WARNING**、永不 BLOCKER。→ operator 停更 / inbox 消失 → 消費端**靜默無感**，凍結對 ASP session 爆炸半徑 = 0。

**核心洞察**：一個已被遺忘、卻對外常駐的 bot，不是資產，是帶著休眠攻擊面的維護負債。這才是「發散」的真正來源——不是 4 個 Python 檔難維護，而是在心裡持續維護一套「為了一個不存在的外部生產者而存在」的信任模型。

---

## 評估選項（Options Considered）

### 選項 A：維持現狀（續跑 + 修 last-mile 讓它好用）

- **優點**：保留無人值守 × 跨 repo 感知能力；三柱願景不動。
- **缺點**：使用者判定此能力其實不需要；「不用它」的病因若是入口太隱形，修 UX 是投資一個不想要的功能。持續扛 T-14 攻擊面與雙 ADR 序列。
- **風險**：投資後仍不用 → 沉沒成本擴大。

### 選項 B：monorepo 併入（operator 源碼搬進 AI-SOP-Protocol）

- **優點**：真正單 repo、單 ADR 序列、單 CONTEXT.md；契約與消費端同樹易同步。
- **缺點**：把已宣告死亡的 Python 匯進乾淨的 ASP 樹；工多、動 ASP；ADR-017「目錄=安裝範圍」需補一條 operator/ 例外。
- **風險**：為一個不用的元件做遷移手術，違背「不發散」與「風險保守」。

### 選項 C：吸收功能（刪 App，issue→inbox 改 ASP 內部 SessionStart skill）

- **優點**：消滅第二組憑證與整個 external-provenance 類別；表面最「不發散」。
- **缺點**：**不是搬移、是刪能力＋改信任模型**——降級為「開了這個 repo 的 session 才看得到這個 repo 的 issue」，失去跨 repo / 無人值守感知；且 provenance 整套（SPEC-007/008/009、T-14、INV-1/2）之存在前提消失，須整套拆除。與 INV-1 正面衝突（SessionStart 觸發＝自動觸發）。
- **風險**：最不可逆、最大手術、最違背「怕處理不好」的風險胃納。

### 選項 D：停用＋原地凍結（採用）

- **優點**：照 ASP 自身 ADR-017 凍結前例——凍結、不刪、保留解凍條件。立即消掉發散與 T-14 活體攻擊面，完全可逆；對 ASP session 爆炸半徑 0；archive 前把 doc/contract 級知識蒸餾回 ASP，crown jewel（ADR-012）本就在 ASP、不流失。
- **缺點**：無人值守 × 跨 repo 感知的願景暫緩（非否定，可解凍）。
- **風險**：極低——不刪碼、不刪金鑰、不刪 ADR，全部保留可撈。

---

## 決策（Decision）

選擇 **選項 D**。

### 1. Decommission（停止服務、斷攻擊面）
- `asp-operator/.github/workflows/poll-issues.yml`：移除／註解 `schedule: */30` 觸發（保留 `workflow_dispatch` 供解凍手動測），或於 GitHub UI disable 此 workflow。
- **卸載 GitHub App**（App ID 3996872）自所有 opt-in repo → 徹底斷 T-14 token 鑄造路徑。（人類手動，破壞性動作需確認。）
- **封存私鑰** `~/secrets/asp-operator.2026-06-08.private-key.pem`：**不刪**（App 卸載後已 inert），可移至 `~/secrets/archive/`；金鑰永不進 git。

### 2. Freeze（凍結、保留、可解凍）
- `asp-operator/README.md` 頂部加 `Status: FROZEN` banner（仿 `experimental/multi-agent/README.md`），指向本 ADR 與解凍條件。
- `asp-operator/docs/adr/ADR-002`（DP5 pivot，Draft）狀態 → `Superseded`（by 本 ADR），DP5 不再實作。
- **蒸餾完成後**（見第 4 點）將 asp-operator repo 於 GitHub 設為 **Archived（唯讀）**。

### 3. ADR-012 標 dormant（保留、不刪）
- 於 ADR-012 頂部加 dormancy note：外部生產者已凍結，本信任模型與消費端閘（SPEC-008/009、`asp-autopilot.md:450-499` provenance gate）處於 dormant；無 live external producer 故 gate 永不觸發；保留不刪以備解凍。
- **明確不動** SPEC-007/008/009 與 provenance gate 程式——它們 inert 且無害；移除即選項 C 的手術。

### 4. 蒸餾 harvest（archive 前完成，落在 ASP，零 code）
crown jewel（ADR-012 信任模型）本就在 ASP、無需搬。以下三項 doc/contract 級知識在 archive 前撈回，避免隨凍結流失：
- **A — Inbox 任務 schema → ASP 單一真理**：把 `asp-operator/src/task_translator.py::translate_issue()` 輸出形狀 + provenance 欄位正式化為 ASP contract（`docs/` schema 附錄或 `contracts/inbox-task.schema.json`）；並在 `asp-autopilot.md`（`is_external_provenance` 消費端）標註此為真理來源。
- **B — GitHub App 最小權限樣式 → ASP security reference**：把 operator ADR-001 精華蒸成一頁安全參考（`docs/security/`）：機器身分→GitHub App、least-priv installation token、1h TTL、opt-in、無 PR/admin/execute。
- **C — 生產者↔閘一致性教訓 → 治理原則**：把 ADR-012 context 的 C1/C2/C3 漂移蒸成與 operator 無關的一級原則，折入本 ADR 或 threat-model：凡向自主執行器供料的生產者，(1) 必對其授權閘做一致性測試、(2) provenance 與 author 端到端保存、(3) 永不直推 main。

### 5. 術語缺口修補（grill 核心產物）
- `CONTEXT.md` 新增一級術語 **Operator（感知層 / Perception Pillar，狀態 FROZEN）**；`GLOSSARY.md` 補一行。輕掃 ASP 文件中「假設 operator 為 live」的敘述加 dormancy 指標，以本 ADR 為主錨。

### 6. 排序與回滾
- **排序**：ADR-032 Accepted → 蒸餾（4）+ ADR-012 dormant（3）+ 術語（5）+ operator repo 凍結（1、2 的 README/ADR-002/停 cron）→ **蒸餾完成後**才 archive repo（2 末項）與卸 App（1）。
- **回滾/解凍**：re-enable workflow schedule、重裝 App、ADR-012 移除 dormant note、repo 取消 archive。仿 ADR-017 `experimental/multi-agent/` 的 unfreeze 語意。

---

## 後果（Consequences）

**正面影響：**
- 「發散」消除：只剩 ASP 一條活躍 ADR 序列；operator repo 唯讀退出視野。
- T-14 活體攻擊面歸零：App 卸載後無法鑄 token。
- 契約收成單一真理（蒸餾 A）：dormant 消費端假設被守住。
- 知識不流失：ADR-001 安全樣式（B）、C1/C2/C3 一致性教訓（C）蒸餾入 ASP。

**負面影響 / 技術債：**
- 無人值守 × 跨 repo 感知能力暫緩（可解凍，非否定）。
- operator repo 的 ADR 序列凍結於 ADR-002 Superseded。
- ADR-012 及其 SPEC 由 live 降為 dormant——保留為潛在解凍資產，但短期為死重（可接受）。

**後續追蹤：**
- [ ] 解凍評估：出現「單一 session 無法覆蓋、且確需無人值守 × 跨 repo 感知」的實際案例 → 解凍 ADR + 重啟。

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| Session 零影響 | 凍結後開新 session / 跑 session-audit 無新 BLOCKER、無 A15.1 | 手動 + 記入 PR | 實作後 |
| cron 已停 | `gh run list -R astroicers/asp-operator` 無新 scheduled run | gh CLI | 實作後 |
| App 攻擊面歸零 | GitHub Installed Apps 不再列出 App 3996872 | GitHub UI / gh api | Locus B 後 |
| repo 唯讀 | `gh repo view astroicers/asp-operator --json isArchived` = true | gh CLI | 蒸餾後 |
| 蒸餾落地 | ASP 有 inbox-task schema（A）、App 最小權限 reference（B）、一致性原則（C） | 檔案存在 + `asp-autopilot.md` 指向 schema | archive 前 |
| 術語一致 | `grep -i operator CONTEXT.md GLOSSARY.md` 命中且標 FROZEN | grep | 實作後 |
| 可逆性 | 金鑰仍在、workflow 保留 `workflow_dispatch`、無任何刪除 | 手動抽測 | 實作後 |

---

## 關聯（Relations）

- **參考：ADR-017**（凍結前例——experimental/multi-agent 的 FROZEN 手法、解凍語意、目錄=定位）。
- **標 dormant 的對象：ADR-012**（operator↔autopilot 信任模型）及其 SPEC-007/008/009；不刪，保留備解凍。
- **蒸餾來源：asp-operator ADR-001**（GitHub App 最小權限，蒸餾為 B）。
- **被本 ADR 取代：asp-operator ADR-002**（impact-classified output pivot，Draft → Superseded；DP5 不再實作）。
- 被取代：（無——operator 為凍結非廢棄）。
- 取代：（無）。

---

## Verification Evidence（FIRM）

> 使用者指示「FIRM 的 POC 驗證先做」；AI 於 2026-08-04 執行 POC-1/2/3，證據如下。FIRM 允許 commit（audit 🟡）；待人類 `/asp:approve-adr` 審核後升 `Accepted`，方全面執行 Decision 各 Locus（Draft/FIRM 期間不得執行不可逆的凍結動作）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | 分支 `asp/adr-032-freeze-operator`。**POC-1 承重·安全（零爆炸半徑）**：`inbox-ingest.sh` 凍結三情境（inbox 缺／空／殘留 1 pending）皆 `exit=0`；殘留 pending 僅出 held **WARNING、非 BLOCKER**；`session-audit.sh` 第 7 段以 `[ -f "$INBOX_FILE" ]` 守衛、`BLOCKERS+=` 計數 **0**；`tests/test_autopilot_provenance_gate.sh` **15/15 PASS**（gate 凍結後 inert）。**POC-2 蒸餾A可行性/schema**：`translate_issue()` 產出 `{id,type,priority,status,sla_hours,source.type,triggered_by,description}`；`is_external_provenance` 讀 `source_type`／`triggered_by`。**發現 drift**：consumer 讀扁平 `source_type`、producer 寫巢狀 `source.type` → `source_type` 路徑對 operator 任務失效，僅靠 `triggered_by="customer"` 仍正確分類 external（凍結下無操作影響；佐證蒸餾 A/C 必要）。**POC-3 可逆**：`poll-issues.yml` 同具 `schedule:*/30` 與 `workflow_dispatch` → 停 schedule、保留 workflow_dispatch 即可手動解凍。 |
| **驗證日期** | 2026-08-04 |
| **驗證者** | astroicers（指示先做 POC）+ AI（執行 POC-1/2/3） |
| **驗證摘要** | 承重宣稱「凍結對 ASP session 零爆炸半徑」**實證成立**；附帶揭露一處 producer/consumer schema drift（`source.type` vs `source_type`），harmless under freeze，已納入蒸餾 A（單一真理 schema）/ C（一致性教訓）。 |
