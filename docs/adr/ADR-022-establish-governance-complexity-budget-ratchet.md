# [ADR-022]: Establish governance complexity budget ratchet

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-23 |
| **決策者** | ASP framework maintainers（待人類核准） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）
>
> ⬆️ 由 `Draft` 升 `Accepted`：使用者 2026-06-23 透過 `/asp:approve-adr ADR-022` 呼叫、看完本指令摘要的決策（行數棘輪機械 gate + 去重 advisory）與 Verification Evidence（POC-1 行數 gate 三情境驗證可行、POC-2 可推導性證偽後已收窄，兩 POC 皆完成附證據）後明確同意（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。直升不跳過實質驗證——FIRM 所需 POC 證據已齊，僅省 FIRM 中間 label。

---

## 背景（Context）

ASP 已知病徵是**治理過載**：ADR+SPEC ≈ 6,039 行，同一義務常在 CLAUDE.md、`global_core.md`、skill 三處重述，mono-router skill 巨型化（`asp-autopilot` 829 行、`asp-gate` 419 行）。現有的適應度信號 `make rule-stats`（ADR-018）**只有負向半邊**——偵測「90 天零命中規則 → 評估移除」，且判定靠人讀，沒有「防止複雜度漲上去」的正向閘。

nuwa-skill 深層借鏡研究（`docs/research/2026-06-23-nuwa-skill-deep-borrow.md`，承接反思報告 P3）蒸餾出三條最高遷移性的底層思維，翻譯成 ASP 機械判定後正好補上缺口：

- **棘輪（只進不退）**：複雜度指標只能降不能升，越界須顯式認列。
- **職能分離（評者≠作者）**：複雜度的保留/移除評分由獨立 `reality-checker` 跑，非提案者自評（ASP 已有此胚胎，ADR-005 + reality-check skill）。
- **可推導性（HOW≠WHAT）**：規則自問「刪掉它，AI 能否從其餘規則推導出同樣行為？」能推導＝冗餘查找表＝砍除候選。

**翻譯規則（ADR-020 立身之本）**：nuwa 靠「誠實標註」（執行者是人），ASP 必須翻成「機械判定」（執行者是會被壓縮的 AI，散文義務壓縮後最先蒸發）。故本決策的所有閘都必須是 exit-code 級可判定，不可是散文勸導。

---

## 評估選項（Options Considered）

### 選項 A：維持現狀（rule-stats 單向、人讀）

- **優點**：零新增機制，不碰既有層。
- **缺點**：只砍不防漲，治理過載持續惡化；複雜度增長無任何閘。
- **風險**：報告診斷的「治理過載」病徵無對策，與 v5 瘦身方向背道。

### 選項 B：軟規則勸導（散文寫「ADR+SPEC 不該超過 X 行」）

- **優點**：實作成本近零。
- **缺點**：又一條沒人理的散文軟規則；**直接撞 ADR-020**——散文義務在長對話壓縮後最先蒸發。
- **風險**：製造「看似有治理、實質無強制」的治理劇場，反而加重認知負荷。

### 選項 C：機械棘輪（採用）

- **優點**：複雜度只進不退由 **CI exit-code** 機械封頂；ASP 自己吃自己的狗糧（用機械強制管自己的複雜度）；複用既有 telemetry（rule-hits）與既有獨立評分（reality-checker），不新建層。
- **缺點**：棘輪可能鎖死正當的複雜度增長（須逃生門）；可推導性軸已由 POC-2 spike 結案為「不可便宜機械化」→ 降為 advisory（機械 gate 僅行數軸）。
- **風險**：若無差別套用會誤傷鐵則層、或退化成「為填而填」的儀式——須以 ADR-010 摩擦評估收口。

---

## ADR-010 摩擦評估（自證：棘輪不是「用更多治理治治理過載」）

本 ADR 宣稱治理過載是病、卻新增機制，必須正面通過 ADR-010 摩擦評估，否則自相矛盾：

| 鏡頭 | 評估 |
|------|------|
| **新增元件清單** | (1) 行數棘輪＝**1 個 CI step + 複用既有 `asp-metrics.sh`**；(2) 去重 advisory review＝**複用既有 rule-hits telemetry 的非阻擋 review，非新 gate 層**；(3) 獨立評分＝**複用既有 `reality-checker`，非新層**；(4) 逃生門＝**沿用既有 FIRM ADR 認列模式，非新協定** |
| **與既有層重疊？** | **不重疊**——四元件全部嫁接在既有 telemetry（rule-hits）/ 腳本（asp-metrics）/ 評者（reality-checker）/ ADR 機制上，**無新 orchestration 層**（對照 ADR-010 當初拒絕 UA 的同一判準） |
| **overhead vs 節省** | overhead ≈ 1 CI step + `rule-stats.sh` 擴充（數十行）；節省＝每 PR **自動**阻擋行數膨脹，取代易漏的人工目視 review。**淨值為正**的關鍵：棘輪本身的行數**計入它自己管的 baseline**（自我約束），不能無限長大 |
| **結論** | **通過**——不新建層、自我約束、機械判定。**已驗證的翻盤點**：POC-2 spike 證實「可推導性」無法便宜機械化（語意關係），故**已觸發降級**——去重不上 per-commit judge 迴圈、改 advisory review；機械 gate 只剩確定性的行數軸。 |

---

## 決策（Decision）

採用 **選項 C（POC-2 spike 後收窄）**：建立**治理複雜度預算棘輪**——**一個機械 gate + 一個 advisory review**：

1. **行數棘輪（機械 gate，POC-1）**：`profiles.total_lines`（`.asp-metrics-baseline.json` 已凍結 5177）設為**只進不退硬上限**。任何使治理產物總行數超過當前 baseline 的 PR → CI gate red，除非附一份明確認列複雜度增加理由的 ADR（逃生門，與既有 FIRM ADR → audit 🟡 同構）。確定性、全自動、exit-code 化。
2. **去重 advisory review（非機械 gate，由 POC-2 收窄）**：「可推導性/去重」**不做成每-commit 機械閘**——POC-2 spike 證實字面代理無法機械近似可推導性（語意關係，見 `docs/research/2026-06-23-poc2-derivability-spike.md`）。改為**定期 LLM-judge 輔助的 advisory review**（列去重候選給人類判斷，**不阻擋 commit**），避免把非確定性判官偽裝成硬 gate（撞 ADR-020）。
3. **獨立評分（職能分離）**：advisory review 的去重評分由 `reality-checker` 獨立 read-only subagent 跑，不由提案 PR 的同一 context 自評（複用 ADR-005 機制）。

**豁免（不可省）**：四條鐵則 + Iron Rule A/B/C（registry `exempt: true`）**永不進入棘輪**——鐵則的價值正在於不退場（沿用 ADR-018 既有豁免）。

> 本決策為 `Draft` 提案——**禁止對應生產代碼**，待人類核准並完成下方 POC 後方可實作。落點為 P3（複雜度預算），須與 P2 拆層的 reality-checker 職能分離對齊。

---

## 後果（Consequences）

**正面影響：**
- 治理層複雜度由機械 exit-code 封頂，正面回應「治理過載」病徵。
- 去重 advisory review 把「同一義務多處重述」變成定期可審的候選清單（非機械 gate——POC-2 證實語意去重無法便宜機械化）。
- ASP 示範「用自己的強制力管自己」——最強的 dogfooding。

**負面影響 / 技術債：**
- **「可推導性」軸已由 POC-2 spike 結案為「不可便宜機械化」**：字面代理精確度 ~33%、且漏掉「換句話說」的語意重述（見 spike 報告）。故機械 gate 僅行數軸一條腿；去重退為 advisory，是**已知並接受**的降級，非懸而未決的風險。
- 棘輪逃生門（ADR 認列）若被濫用，會退化成橡皮圖章——須監控豁免頻率。
- baseline 需隨正當演化更新，更新本身要走治理。

**後續追蹤：**
- [x] **POC-1（行數棘輪）— 已驗證**。探針（`docs/research/2026-06-23-poc1-linecount-ratchet.md` + `poc1-linecount-ratchet-probe.sh`）三情境跑通：真實 PASS(exit0)、合成 violation(exit1)、豁免放行(exit0)。複用 `asp-metrics.sh` 現值 vs `.asp-metrics-baseline.json`。生產化僅剩接 CI step（無技術未知）。附帶 finding：current 3626 << baseline 5177，生產化時應 re-freeze baseline。
- [x] **POC-2（可推導性軸）— 已完成，結果：負面 → 降級**。spike（`docs/research/2026-06-23-poc2-derivability-spike.md` + `poc2-derivability-probe.py`）證實字面代理無法機械近似可推導性（語意關係：精確度 ~33%、召回失敗）。**已觸發降級**：去重從機械 gate 改為 advisory review，不上 per-commit LLM judge 迴圈（避免撞 ADR-020）。
- [ ] **逃生門濫用監控**：豁免 ADR 認列次數記錄於既有 telemetry（rule-hits / `.asp-gate-log/`），定期計算豁免率；> 50% 觸發「重新評估條件」重議（量測機制不另建，複用既有記錄）。
- [ ] 鐵則 / Iron Rule 豁免清單繼承（沿用 rule-stats `exempt: true`）。
- [ ] 與 P2 拆層的 reality-checker 職能分離硬約束對齊（避免重複造層，ADR-010）。

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 行數棘輪生效 | `total_lines > baseline 且無豁免` → CI exit 1 | CI gate + `asp-metrics.sh` | POC-1 完成時 |
| 行數 gate 對象明確 | 機械 gate＝`asp-metrics.sh` 算 `total_lines`（**非** rule-stats）；rule-stats 維持 ADR-018 零命中職責不變 | 程式碼審查 | 實作完成時 |
| 去重 advisory 產出 | 定期 review 列出去重候選清單（非阻擋；交人類判斷） | `make rule-dedup-review` | advisory 機制建好時 |
| 鐵則零誤傷 | 4 鐵則 + Iron Rule A/B/C 不被棘輪標記 | 豁免清單測試 | 實作完成時 |

> **重新評估條件**：POC-2「可推導性無法便宜機械化」**已成立並觸發降級**（去重轉 advisory）；剩餘條件——若行數棘輪的逃生門（ADR 認列）被濫用率 > 50% → 棘輪形同虛設，須重議閘門設計。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - **ADR-018**（rule-hit telemetry / rule-stats）——本棘輪的負向半邊與 telemetry 基礎；收窄後**去重 advisory review 複用 ADR-018 rule-hits telemetry**（非改其 exit-code；機械 gate 改由 `asp-metrics.sh` 的行數軸承擔）
  - **ADR-005**（GA 前獨立 Reality-Checker holistic review）——職能分離機制來源
  - **ADR-020**（AI 遺忘為一級威脅、機械化過程義務）——「誠實標註 → 機械判定」翻譯規則的立身依據
  - **ADR-010**（最小採納 UA orchestration）——摩擦評估／拒絕重疊既有層的鐵律，本 ADR 須通過
  - `docs/research/2026-06-23-nuwa-skill-deep-borrow.md`（蒸餾來源：棘輪 / 可證偽 / HOW≠WHAT）
  - 反思報告 P3（`docs/research/2026-06-22-external-benchmark-reflection.md`）
  - `.asp-metrics-baseline.json`（`profiles.total_lines` 凍結錨點）、`reality_checker.md`（評者）

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由**人類**將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。AI 不可自行升級狀態。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | **POC-1：已驗證**——`docs/research/2026-06-23-poc1-linecount-ratchet.md`，探針三情境跑通（PASS exit0 / violation exit1 / 豁免 exit0），確定性可行。**POC-2：已完成（負面）**——`docs/research/2026-06-23-poc2-derivability-spike.md`，可推導性不可便宜機械化 → 去重降 advisory（決策已收窄）。 |
| **驗證日期** | （待填） |
| **驗證者** | （待填，人類） |
| **驗證摘要** | （驗證者待人類確認）兩個 POC 均已完成：POC-1 行數棘輪 gate 三情境驗證可行（exit-code 確定性）；POC-2 可推導性證實無法便宜機械化 → 去重已降 advisory。收窄後決策＝**行數棘輪（確定性機械 gate）+ 去重 advisory review**，可行性已全數驗證；生產化僅剩工程接線（含 baseline re-freeze）。 |
