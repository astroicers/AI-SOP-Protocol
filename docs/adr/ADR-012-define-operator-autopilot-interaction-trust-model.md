# [ADR-012]: Define operator-autopilot interaction trust model

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-06-09（2026-06-11 修訂 DP2/DP5 + 新增 DP7 + reviewer 硬化，2026-06-11 人類 re-Accept） |
| **決策者** | 專案維護者（ASP framework maintainer，待人類審核 Accept） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）
>
> **修訂註記（2026-06-11）：** 對齊討論揭露原 DP2「外部一律須 Accepted ADR」過粗——外部瑣碎 / bugfix 不該被迫開 ADR（與已否決的選項 B 同樣的過度設計，只是搬到外部路徑）。本版把「授權」與「ADR」**解耦**：授權 artifact 隨架構影響**縮放**（DP2）、asp-op 先判影響再決定產物（DP5）、新增 bug 拓樸（DP7）。經獨立 reviewer 硬化（INV-1/2 + DP1–DP8 標籤、triage 強制力誠實標註、封 inbox 旁路）後，2026-06-11 由人類 re-Accept。

---

## 背景（Context）

ASP 由三個**不同時期、互不認識**的元件鬆耦合而成，靠檔案串接成「issue → 自動處理」迴圈：

```
asp-op（外部 GitHub App，App ID 3996872，*/30 cron，2026-06 建）
  poll_issues.py:71-77  以 label `ready-for-agent` 過濾 open issue
  task_translator.py:29-53  翻譯任務（不擷取 issue author，triggered_by 硬編 "customer" @:51）
  inbox_writer.py:30,61  直接 commit inbox 到 main（非 PR），409-retry 26-45
  ▼
.asp-task-inbox.json（main）→ inbox-ingest.sh（SessionStart 搬運工，無 flock，只搬不執行）
  ▼
ROADMAP.yaml → autopilot（~/.claude/asp/profiles/autopilot.md，2026-03 設計）
  唯有人類主動啟動才動；輸出永遠止於 draft PR（鐵則：不 merge、不 push main）
```

**核心洞見**：autopilot 100% 信任「被授權執行的工作單元」。安全的唯一問題是 **把「執行授權線」畫在信任強度光譜的哪一格**：

```
issue-label（弱，無授權模型） < inbox < ROADMAP-pending < ADR-Accepted（人類唯一硬閘，鐵則）
```

且**威脅是來源特定（provenance-specific）的**：只有**外部來源**任務（asp-op 從 GitHub issue 來）缺乏「人類撰寫」這道閘；**人類手寫**進 ROADMAP 的任務，作者本身即是那道閘。

**驅動本決策的觸發**：使用者要讓此迴圈運行並**推廣到未來其他專案**，但擔心非預期影響。一致性審計（三 read-only agent，grounded file:line）揭露三條**既有漂移（非本決策造成）**：

- **C1🔴（CRITICAL）**：asp-op 心智模型純「issue → inbox → 執行」、文件零提 ADR/autopilot；但 autopilot 早在 2026-03-12 就對架構級 `adr: null` 任務**自動建 Draft ADR 並標 blocked**（[autopilot.md:248-273](../../../.claude/asp/profiles/autopilot.md)）。→ inbox 的架構任務在現行管線**早已 dead-end 在 ADR 閘**，兩層從未一致性測試。
- **C2🟠（HIGH）**：ADR-006 Item 7 計劃「移除 autopilot.md profile、邏輯收回 asp-autopilot skill」（[ADR-006:89](ADR-006-feature-audit-roadmap.md)）**未執行** → autopilot 同時以 profile(582 行)＋skill(237 行) 並存；[ADR-001](ADR-001-autopilot--roadmap-.md) 的「被取代:(無)」已過時。
- **C3🟠（MED）**：asp-op 直推 main（`inbox_writer.py:30,61`）無 ADR 證成、牴觸其自身 README 原則「架構影響須先立 ADR」；且丟失 issue author（`task_translator.py:51`）→ 連 autopilot 自建的 Draft ADR 都無 approver 身份。

**誠實澄清（非腐化，避免過度宣稱）**：前置文件體系（SRS/SDS/UIUX/Deploy）、profile/skill 分工、agent-memory 退場皆健康且有追蹤；ADR-009/010 與 autopilot 執行流正交。本決策**不**主張全面重寫，只針對外部信任邊界。

---

## 評估選項（Options Considered）

### 選項 A：維持 ROADMAP-pending 授權 + 硬化 producer 側

保留現有 issue→inbox→ROADMAP 機制，逐項補洞：asp-op 存 issue author + `author_association` allowlist、asp-op 改 branch+PR、inbox-ingest 加 flock、bot-author 過濾。

- **優點**：改動最小、不動 autopilot；沿用既有元件。
- **缺點**：信任邊界仍停在**弱 issue-label**，護欄是疊加的補丁；屬 bespoke 機制、不易推廣到其他專案。
- **風險**：未解 C1 impedance（架構任務仍 dead-end 在 ADR 閘）；任一補丁失效即破口。

### 選項 B：blanket ADR-Accept（所有 autopilot 執行皆須 Accepted ADR）

把授權線升到 ADR-Accept，且套用於**所有**任務。

- **優點**：單一規則、最一致、最保守。
- **缺點**：**破壞瑣碎人類任務自動化**（[ADR-001](ADR-001-autopilot--roadmap-.md) 的核心用法是人類把一批小任務丟進 ROADMAP 跑）；**牴觸 asp-plan Step 2**（瑣碎工作本不該要 ADR）；動到 autopilot 核心權限模型。
- **風險**：向後不相容；為外部路徑的威脅去懲罰有信任的人類手寫路徑（過度設計）。

### 選項 C：provenance-scoped、授權隨架構影響縮放（人類手寫不變）← 選定

外部來源任務一律需**人類放行**，但放行的 artifact **隨架構影響縮放**（架構級→Accepted ADR；非架構→人類核准 PR/triage；瑣碎 bugfix→輕量 triage）；人類手寫 ROADMAP 任務維持現有機制。

- **優點**：精準打真實威脅（外部缺人類閘）；**autopilot 現行 ROADMAP 權限/機制向後相容、不動**；reuse 最強既有閘（ADR-Accept 鐵則，AI/bot 無法自升）；每個 ASP 專案天生繼承 → 可推廣；**授權與 ADR 解耦 → 不對外部瑣碎/ bugfix 過度設計**。
- **缺點**：引入 provenance + 影響兩層判別；triage-accept 為新機制（輕量）；asp-op pivot 為跨 repo 工作。
- **風險**：判別誤判（人類任務誤擋 / 影響誤判）→ 回歸測試 + 監看 +「不確定視為 non-trivial」緩解。

> **精修註**：本選項初稿曾寫「外部一律須 Accepted ADR」，於對齊中**否決**——對外部瑣碎/ bugfix 過度設計、且 bugfix 不配 ADR 會 dead-end；改為「需人類放行 + artifact 隨影響縮放」。

---

## 決策（Decision）

我們選擇 **選項 C：provenance-scoped、授權隨架構影響縮放**。ADR-012 只擁有以下**跨系統契約**（聚焦範圍；元件實作為 Accept 後的具名 follow-up）。

**不變量（Invariants，任何實作不得違反）：**
- **INV-1（人類啟動）**：autopilot 僅由**人類主動啟動**；任何自動觸發（cron / webhook / SessionStart hook）皆不被授權——違反即破壞 provenance 邊界。
- **INV-2（人類放行）**：無外部來源工作可不經**人類放行**就被 autopilot 執行。

**DP1 — provenance 判別**：每個任務攜帶來源標記（人類手寫 vs 外部來源）。asp-op 已蓋章 `source.type: github_issue` / `triggered_by`；pivot 後再補 `issue author / author_type`。

**DP2 — 外部來源任務 → 須人類放行，授權 artifact 隨架構影響縮放**（授權與 ADR 解耦）。放行形式依影響縮放——
- **架構級** → **Accepted ADR**（沿用 autopilot 既有 248-273 ADR 閘，機械強制）
- **非架構** → **人類核准 PR（triage-accept）**（非 ADR）
- **triage-accept 只負責「授權進場」**；進場後的**管線深度（spec+tdd vs impl+qa）由 autopilot 既有 severity 分類決定**（[global_core.md:159-171](../../../.claude/asp/profiles/global_core.md)：瑣碎 bugfix = ≤2 檔/≤10 行/不動 logic·DB·API·auth → impl+qa；其餘 → spec+tdd+impl+qa），**與人類手寫任務完全同規則**。asp-op/triage **不另立第二套管線**（消解「triage token 不帶管線深度」的歧義）。

  實作為在既有逐任務閘**加「來源 + 影響」檢查**，**不**替換 ROADMAP 迴圈。

**DP3 — 人類手寫任務 → 現有機制完全不變**：跑 pending；架構級走既有 ADR 閘；瑣碎照跑。**autopilot 的 ROADMAP 權限/機制向後相容、不降級、不改 resume。**

**DP4 — run-signal 綁人類放行（自我授權防線）**：外部任務所依的授權記號（Accepted ADR 或 triage-accept）須由**人類** commit/核准（非 bot/autopilot）才生效。
  **強制力範圍（誠實標註，勿過度宣稱）**：**架構路徑已機械強制**（autopilot.md:261-263 檢查 `adr.status != "Accepted"` → blocked）；**非架構 triage-accept 的 human-author 檢查尚待 SPEC 落地，在此之前不宣稱已強制**（見 DP8 過渡措施）。

**DP5 — asp-op 重定位（契約層，影響分類為「提案」）**：`ready-for-agent` issue → asp-op **先判架構影響**再決定產物，皆走 branch+PR、蓋 provenance/author、不再直推 inbox：
- **架構級** → 產 **Draft ADR**（弱 label 只生 harmless Draft，人類 Accept 才授權）
- **非架構** → 產 **triage PR**（輕量，人類核准即放行，不開 ADR）
- **asp-op 的分類僅為初步提案**：**人類在 accept ADR / merge triage-PR 時即對分類負責確認**（此即 INV-2 的 human go-ahead，杜絕「asp-op 分類 + autopilot assess 兩次 bot 分類、中間無人介入」）；asp-op **不確定時必須往高一級回退**（non-arch → arch）。

  （同時順手修 C3 直推 main + author 遺失。）實作 = asp-op repo 自己的 ADR。

**DP6 — 通用性**：本模型為框架級——任何採用 asp-operator 的專案皆繼承，因每個 ASP 專案都有 ADR-Accept 鐵則與 triage 流程。

**DP7 — bug 拓樸（post-implementation）**：實作後發現的 bug → **內部人類手寫 bugfix task**（internal provenance）→ autopilot 既有路徑修（瑣碎→impl+qa；非瑣碎→spec+tdd）。**不**自動轉 GitHub issue 走 asp-op 外部迴圈——避免 autopilot 自身 output-bug 被 re-ingest 的放大迴圈（#5）。重大 bug（影響 prod / retry>3 / 資料遺失 / 需 rollback，[global_core.md:209-220](../../../.claude/asp/profiles/global_core.md)）**仍並行觸發 Postmortem**。

**DP8 — 過渡措施（triage SPEC + inbox 封堵落地前）**：triage-accept 機制與 inbox 旁路封堵（見後續追蹤）落地前，**外部非架構路徑尚未啟用**；過渡期外部工作一律走架構級 ADR 路徑、或由人類手動置入 ROADMAP（internal provenance）。**不宣稱一個尚不存在的閘**。

> **重 framing**：升 ADR-Accept 錨**不是引入新架構，而是完成 autopilot 2026-03 已起的方向 + 收斂 asp-op 既有 impedance（C1）**。ADR-012 是「恢復三層一致性」的決策；DP2/DP5 的縮放讓它對瑣碎工作不過度設計。

### 威脅模型新增 — T-14

| 欄位 | 內容 |
|------|------|
| **ID** | T-14 |
| **名稱** | External-artifact → autopilot trust（inbox / 外部來源任務污染） |
| **STRIDE** | Tampering + Prompt-Injection |
| **攻擊面** | 外部 GitHub issue（弱 `ready-for-agent` label，無授權模型）→ asp-op → 任務 → autopilot 執行 |
| **緩解** | (1) 外部來源任務須**人類放行**，授權隨架構影響縮放（架構→Accepted ADR、非架構→triage-accept）；(2) run-signal 綁 **human-author**——**架構路徑**由鐵則 + session-audit 動態 deny **機械強制**；**非架構 triage 路徑**的 human-author 檢查**待 SPEC 落地**（過渡期該路徑未啟用，見 DP8），現行 session-audit **不**涵蓋 triage；(3) asp-op 先判影響再產物（架構→Draft ADR、非架構→triage PR），弱 label 至多生「需人類放行的提案」 |
| **落地** | 本 ADR 定義；**Accept 後併入 `docs/security/threat-model-v4.0.md`（現 T-01..T-13）** |

---

## 後果（Consequences）

**正面影響：**
- 精準打外部威脅：缺口 #1（ready-for-agent 無授權）/ #3（直推 main）/ #5（bot 放大迴圈）解；#2（無威脅條目）以 T-14 緩解免費。
- 恢復 C1 三層一致性；**autopilot 既有機制與向後相容性完整保住**。
- **授權與 ADR 解耦** → 外部瑣碎/ bugfix 不被迫開 ADR、不 dead-end；與內部 taxonomy 對稱。
- reuse 最強既有閘（ADR-Accept 鐵則），天生可推廣（符合「通用」範圍）。

**負面影響 / 技術債：**
- 外部工作需先取得人類放行（ADR 或 triage）才落地，多一道人類審（刻意的安全成本）。
- 引入 provenance + 影響判別兩層 + triage-accept 新機制；asp-op pivot 為跨 repo 工作。
- C2（ADR-001 profile/skill 並存漂移）本 ADR 不修，僅在 Relations 點名、留待 ADR-006 Item 7。

**後續追蹤（全部 gated on Accept；本 ADR Draft 階段一律不實作）：**
- [ ] SPEC：autopilot 於 248-273 加 **provenance + 影響閘**（外部來源依架構影響縮放授權：架構→Accepted ADR、非架構→triage-accept、瑣碎→輕量 triage）— 唯一的 autopilot 改動
- [ ] SPEC：**triage-accept 機制**（非架構外部工作的輕量人類放行記號）+ run-signal label 語意 + Accept/triage **human-author 檢查**（自我授權防線）
- [ ] **asp-op repo ADR + SPEC**：影響分類 pivot（架構→Draft ADR、非架構→triage PR/task；branch+PR、擷取並存 issue author/author_type）→ 解 C3
- [ ] **封 inbox-ingest 旁路（安全關鍵）**：asp-op pivot 後**停用/限制** `.asp/scripts/inbox-ingest.sh`（現仍於 SessionStart 注入 ROADMAP、**無 provenance 閘**）——否則任何人直推 `.asp-task-inbox.json` 到 main 即可繞過整個信任模型。pivot SPEC 必含項；在此之前 DP8 過渡措施生效
- [ ] **bug 拓樸（DP7）落地**：post-impl bug 走內部人類手寫 task 路徑、不自動進外部 issue 迴圈；重大 bug 並行 Postmortem
- [ ] T-14 併入 `docs/security/threat-model-v4.0.md`
- [x] 文件：更新 [ADR-001](ADR-001-autopilot--roadmap-.md) Relations 註明 profile/skill locus（承認 C2）——**C2 已於 v4.4 結案**（ADR-006 Item 7 經 SPEC-010 執行，2026-06-11；Context 段之 C2 敘述為決策當時的歷史審計事實，保留原文）
- [ ] （ADR-012 收尾後，獨立議題）一輪技術債討論：C1–C3 + 既有 backlog（逾期 HIGH A8.3、TD-006、TD-007 等），不混入本 ADR

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 外部來源任務**無任何人類放行**時被拒絕執行 | 100% 標 blocked、不開 PR | provenance+影響閘 TDD（注入 external + 無 ADR/無 triage task） | 閘實作完成時 |
| 外部**瑣碎 bugfix** 經輕量 triage-accept 可執行（不因缺 ADR 被擋） | 100% 放行至 impl+qa | triage-accept 路徑測試 | 閘實作完成時 |
| 人類手寫瑣碎任務行為無退化 | 0 回歸 | 既有 autopilot 任務回歸測試 | 閘實作完成時 |
| bot/autopilot 無法以自建 ADR/triage 自我授權 | 0 例通過 | run-signal human-author 檢查測試 | 防線 F 實作完成時 |
| post-impl bug 走內部 task、不自動進外部 issue 迴圈 | 0 自動外部 re-ingest | bug 拓樸（DP7）測試 | DP7 落地時 |

> **重新評估時機**：若 provenance/影響判別大量誤判（人類任務被誤擋、或瑣碎被誤判架構），或外部需求量小到 pivot 顯得過重，應重評（可回退選項 A）。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - [ADR-001](ADR-001-autopilot--roadmap-.md)（autopilot/ROADMAP 基礎設計；註：其 profile/skill locus 待 ADR-006 Item 7 執行，「被取代:(無)」現已過時）
  - [ADR-006](ADR-006-feature-audit-roadmap.md)（autopilot 重分類 roadmap，Item 7 尚未執行）
  - [ADR-002](ADR-002-asp-v4-security-threat-model.md)（v4 STRIDE 威脅模型；T-14 為其延伸）
  - **不 supersede** [ADR-007](ADR-007-v4.3-profile-skill-consolidation.md)（其未提 autopilot 是資料點，非矛盾）
  - 日後若於 autopilot 執行期加 gate，再與 ADR-009 / SPEC-006（TD-007）協調
  - asp-op repo 之 影響分類 pivot ADR（跨 repo，已建：asp-operator ADR-002）
  - 註（v4.4 / SPEC-010）：本 ADR 內文引用之 `autopilot.md:248-273` 為撰寫當時的歷史位置；provenance 閘的 **canonical 現居 `asp-autopilot` skill Part 2**（ADR-006 Item 7 整併，行為原文未變、契約測試保真）

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | （分支名稱 或 初步測試輸出連結） |
| **驗證日期** | （placeholder，升 FIRM 時填） |
| **驗證者** | 人名 / 角色 |
| **驗證摘要** | 一句話描述驗證了什麼 |
