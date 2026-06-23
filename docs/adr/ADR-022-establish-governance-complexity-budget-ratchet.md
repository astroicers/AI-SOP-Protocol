# [ADR-022]: Establish governance complexity budget ratchet

| 欄位 | 內容 |
|------|------|
| **狀態** | `Draft` |
| **日期** | 2026-06-23 |
| **決策者** | ASP framework maintainers（待人類核准） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

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
- **缺點**：棘輪可能鎖死正當的複雜度增長（須逃生門）；「可推導性」軸如何機械化是真實難題（見後續追蹤 POC-2）。
- **風險**：若無差別套用會誤傷鐵則層、或退化成「為填而填」的儀式——須以 ADR-010 摩擦評估收口。

---

## ADR-010 摩擦評估（自證：棘輪不是「用更多治理治治理過載」）

本 ADR 宣稱治理過載是病、卻新增機制，必須正面通過 ADR-010 摩擦評估，否則自相矛盾：

| 鏡頭 | 評估 |
|------|------|
| **新增元件清單** | (1) 行數棘輪＝**1 個 CI step + 複用既有 `asp-metrics.sh`**；(2) 雙軸 rule-stats＝**改寫既有 `rule-stats.sh`，非新檔**；(3) 獨立評分＝**複用既有 `reality-checker`，非新層**；(4) 逃生門＝**沿用既有 FIRM ADR 認列模式，非新協定** |
| **與既有層重疊？** | **不重疊**——四元件全部嫁接在既有 telemetry（rule-hits）/ 腳本（asp-metrics）/ 評者（reality-checker）/ ADR 機制上，**無新 orchestration 層**（對照 ADR-010 當初拒絕 UA 的同一判準） |
| **overhead vs 節省** | overhead ≈ 1 CI step + `rule-stats.sh` 擴充（數十行）；節省＝每 PR **自動**阻擋行數膨脹，取代易漏的人工目視 review。**淨值為正**的關鍵：棘輪本身的行數**計入它自己管的 baseline**（自我約束），不能無限長大 |
| **結論** | **通過**——不新建層、自我約束、機械判定。**唯一會翻盤的情況**：POC-2「可推導性」若退化成「多 LLM judge 投票」，那才是 ADR-010 警告的過度 orchestration → 屆時降級為純行數軸，不上 judge 迴圈 |

---

## 決策（Decision）

採用 **選項 C**：建立**治理複雜度預算棘輪**，三個機械元件：

1. **行數棘輪（line-count ceiling）**：`profiles.total_lines`（`.asp-metrics-baseline.json` 已凍結 5177）設為**只進不退硬上限**。任何使治理產物總行數超過當前 baseline 的 PR → CI gate red，除非附一份明確認列複雜度增加理由的 ADR（逃生門，與既有 FIRM ADR → audit 🟡 同構）。
2. **雙軸 rule-stats**：`rule-stats`（ADR-018）從「命中率」單軸升級為**命中率 × 可推導性**雙軸——零命中＝既有砍除信號；**高命中但可由他條推導**＝去重候選（治理重複的主來源）。
3. **獨立評分**：複雜度的保留/砍除評分由 `reality-checker` 獨立 read-only subagent 跑，不由提案 PR 的同一 context 自評（職能分離，複用 ADR-005 機制）。

**豁免（不可省）**：四條鐵則 + Iron Rule A/B/C（registry `exempt: true`）**永不進入棘輪**——鐵則的價值正在於不退場（沿用 ADR-018 既有豁免）。

> 本決策為 `Draft` 提案——**禁止對應生產代碼**，待人類核准並完成下方 POC 後方可實作。落點為 P3（複雜度預算），須與 P2 拆層的 reality-checker 職能分離對齊。

---

## 後果（Consequences）

**正面影響：**
- 治理層複雜度由機械 exit-code 封頂，正面回應「治理過載」病徵。
- 雙軸 rule-stats 把「同一義務三處重述」變成可機械識別的去重候選。
- ASP 示範「用自己的強制力管自己」——最強的 dogfooding。

**負面影響 / 技術債：**
- **「可推導性」軸的機械化是未解難題**：如何 exit-code 級判定「規則 X 可由其餘規則推導」？候選方案（LLM judge / 啟發式 / 人工標記）各有成本與不確定性，須 spike（POC-2）。在它落地前，棘輪只有「行數軸」一條腿可全自動。
- 棘輪逃生門（ADR 認列）若被濫用，會退化成橡皮圖章——須監控豁免頻率。
- baseline 需隨正當演化更新，更新本身要走治理。

**後續追蹤：**
- [ ] **POC-1（行數棘輪，全自動可行）**：CI gate 機械化——`total_lines > baseline 且無豁免 ADR → exit 1`。複用 `.asp-metrics-baseline.json` 與既有 `asp-metrics.sh`。
- [ ] **POC-2（可推導性軸，高不確定）**：spike「如何機械判定可推導性」。先以「同義務字串跨檔重複偵測」當低保真代理（呼應 `feedback_compiled_artifact_scan_blindspot` 的重複病），再評估是否值得上 LLM judge。**若採 LLM judge，其輸出必須轉成 exit-code 機械判定**——否則違反 ADR-020 翻譯規則（LLM 判定義務是治理散文中最先蒸發的）。**這是本 ADR 風險最高的一格，POC 不過則棘輪降級為純行數軸。**
- [ ] **逃生門濫用監控**：豁免 ADR 認列次數記錄於既有 telemetry（rule-hits / `.asp-gate-log/`），定期計算豁免率；> 50% 觸發「重新評估條件」重議（量測機制不另建，複用既有記錄）。
- [ ] 鐵則 / Iron Rule 豁免清單繼承（沿用 rule-stats `exempt: true`）。
- [ ] 與 P2 拆層的 reality-checker 職能分離硬約束對齊（避免重複造層，ADR-010）。

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 行數棘輪生效 | `total_lines > baseline 且無豁免` → CI exit 1 | CI gate + `asp-metrics.sh` | POC-1 完成時 |
| rule-stats 機器可讀 budget 判定 | 輸出 violation 時 exit≠0（非僅人讀） | `make rule-stats` | 實作完成時 |
| 去重識別力 | ≥ 1 條「高命中可推導」規則被標為砍除候選 | 雙軸 rule-stats | POC-2 完成時 |
| 鐵則零誤傷 | 4 鐵則 + Iron Rule A/B/C 不被棘輪標記 | 豁免清單測試 | 實作完成時 |

> **重新評估條件**：若 POC-2 證實「可推導性」無法以可接受成本機械化 → 棘輪降級為純行數軸（仍有價值），並重議是否值得保留雙軸目標；若行數棘輪的逃生門（ADR 認列）被濫用率 > 50% → 棘輪形同虛設，須重議閘門設計。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - **ADR-018**（rule-hit telemetry / rule-stats）——本棘輪的負向半邊與 telemetry 基礎；**本案 Extends ADR-018**：`rule-stats.sh` exit-code 語意擴充（violation 時 exit≠0，非僅人讀）
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
| **POC 分支 / 測試結果** | （待 POC-1：行數棘輪 CI gate；POC-2：可推導性軸 spike——最高風險格，須先證可機械化或誠實降級） |
| **驗證日期** | （待填） |
| **驗證者** | （待填，人類） |
| **驗證摘要** | （待填）行數棘輪可全自動；雙軸的「可推導性」尚待 spike 證實能以可接受成本機械判定，否則降級為純行數軸 |
