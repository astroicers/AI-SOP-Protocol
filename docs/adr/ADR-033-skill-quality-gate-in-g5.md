<!-- Last Updated: 2026-08-17 | Status: Accepted | Audience: ASP framework maintainers -->
# [ADR-033]: 把 skill 品質檢查掛入 G5,判準外部化到 skill-reviewer rubric

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-08-17 |
| **決策者** | ASP framework maintainers |
| **觸發事件** | ASP 有 G1–G6 完整管線,但**沒有任何 gate 檢查 skill 本身的品質**——新增或修改 SKILL.md 時,無論 frontmatter 是否合規、是否含安全紅旗,都能無阻通過 G5 |
| **關聯** | ADR-031(skill 內雙重編碼治理——本 ADR 的 canonical 設計直接受其約束);ADR-030(借入外部 agent skills 方法論的先例);ADR-022(複雜度預算棘輪);ADR-018(規則存留治理) |

> **狀態說明:** `Draft`(初稿,禁止實作生產碼)→ `FIRM`(允許實作 POC/commit,需 Verification Evidence,audit 輸出 🟡)→ `Accepted`(人類看驗證結果後審核直升)。
>
> **本 ADR 以 FIRM 起始的理由**:實作與驗證已於 PR #94 完成(見下方 Verification Evidence),
> 符合 ADR-031 的先例——先以 FIRM 允許 POC commit,人類看完證據後再直升 Accepted。
>
> ⬆️ **由 `FIRM` 升 `Accepted`**:使用者 2026-08-17 透過 `/asp:approve-adr 033` 呼叫、
> 看完本指令摘要的決策(D1 擋/不擋分界、D2 canonical 單一化、D3 Gate Checker 術語、
> D4 observed_by manual)與 Verification Evidence(5 個 eval 案例實跑、H-005 三情境、
> 誤報率 1/54、3 個已發布 repo 實戰、ADR-022 複雜度未觸發)後明確同意
> (人類顯式授權,非 AI 自行升級,符合 ADR 狀態變更鐵則)。
>
> ⚠️ **升級當下的例外情形(如實記錄)**:原訂 Accepted 條件含「至少一次真實 G5 觸發的
> 觀察結果」,**該觸發於升級當下尚未發生**。使用者選擇**先修訂條件再升級**——
> 判定原條件混淆了「設計決策的證據」與「執行期行為的觀察」,前者已充分、後者改列為
> 持續追蹤的已知殘留風險(修訂理由詳見文末 Verification Evidence 節)。
> **craft 路徑至本次升級為止仍未經真實執行驗證。**

---

## 背景(Context)

ASP 的 G1–G6 管線檢查 ADR、SPEC、測試、實作、驗證、部署,但**不檢查 skill 本身**。
這在 ASP 自己就是盲點:ASP 大量以 skill 承載治理邏輯(`/asp-gate`、`/asp-ship`、
`asp-autopilot` 等),skill 的 frontmatter 壞掉會讓 harness 靜默不載入,而管線全綠。

外部研究 [skill-quality-research](https://github.com/astroicers/skill-quality-research)
(97 個 repo 的星數梯度分析,三道 HITL gate 皆 approved)產出了一套證據導向的品質 rubric
與 `skill-reviewer` skill。本 ADR 決定如何把它接進 G5。

### 該研究的核心結論(決定了本設計的形狀)

**星數關聯的是「可安裝/可發現/可信任」的打包面,不是內容工藝。**
5 條可量測的差異化特徵全是 packaging/marketing;寫作工藝(觸發設計/風格/scope)
量化上全落 noise。

→ 直接後果:**lint 只能當 packaging 過濾器與安全門檻,craft 判讀必須交給 LLM 層。**
若把 lint 分數當品質總評,會系統性誤判——該研究回測 22 個內部 skill 時,
packaging 全部 0–5/14 卻 craft 全部 approved,實證了這一點。

---

## 評估選項(Options Considered)

### 選項 A:在 `evaluate_G5` 加條件子句(採用)

- **優點**:G5 既有形狀就已混用 agent 判讀(`qa_agent.independent_verify()`、
  `sec_agent.review()`)與 shell(`EXECUTE("make lint")`)——skill-reviewer 的
  LLM+script 兩層與此天然同構,**零新機制**;改動面積最小(pipeline.md +26 行、
  rule-registry +12 行);僅在變更觸及 `**/SKILL.md` 時觸發,對其他任務零成本
- **缺點**:G5 的 pseudocode 又長了一段
- **風險**:與 skill-reviewer 形成跨 repo 依賴(見「後果」)

### 選項 B:獨立 `profiles/skill_auditor.md`

- **優點**:彈性高,可跨多個 gate 使用
- **缺點**:需動 `profile-map.yaml` 與載入條件,面積大於收益;G5 子句已足夠
- **風險**:多一層 profile 增加載入複雜度,與 ADR-022 的複雜度預算精神相悖

### 選項 C:只在 `hooks/pretooluse-ship-gate.sh` 加檢查

- **優點**:最輕,走既有 hook 機制
- **缺點**:**只能跑 shell 層(lint),craft 完全掛不上**
- **風險**:與研究核心結論直接相悖——把「packaging 過濾器」當成品質檢查的全部

---

## 決策(Decision)

**選擇選項 A**,並附四個關鍵設計決定:

### D1. 只有 hygiene error 擋 gate;安全紅旗與 craft 一律 YELLOW_FLAG 不擋

| 訊號 | 處置 | 理由 |
|------|------|------|
| hygiene error | `issues` → **擋** | 確定性判定(frontmatter 有無合規 name/description),無假陽性疑慮 |
| 安全紅旗 | `YELLOW_FLAG` → **不擋** | 靜態 regex 有**實證**假陽性 |
| craft | `YELLOW_FLAG` → **不擋** | craft 是判斷不是事實,符合「AI proposes, human reviews」 |
| 工具缺席/JSON 非法 | `YELLOW_FLAG` | 工具沒裝不該阻斷別人的管線 |

**「安全不擋」是刻意取捨,不是疏漏——這是本 ADR 最需要被記錄的一點。**
實證:`S-001` 的 regex 會誤中 `anthropics/skills` 正當文件裡的
「follow the guide exactly」;`S-003 self_update` 曾對 3/3 已發布 repo 全部誤報
(命中的是 README 給人看的 `git pull` 更新說明)。取捨理由:**gate 假阻的代價
(阻斷正當開發、侵蝕對 gate 的信任)高於漏擋的代價(仍有 YELLOW_FLAG 提示人看)。**

> ⚠️ 未來若有人想「修好」這點(把安全改成擋 gate),請先讀本節與 Verification Evidence
> 的假陽性紀錄。這不是還沒做完,是評估後的決定。

### D2. 判準的 canonical 在 skill-reviewer 的 rubric,不在 pipeline.md(ADR-031 約束)

`pipeline.md` **不得重新編碼**「什麼該擋」的政策。實作上:
`lint_skill.py --changed-files` 自己算「本次變更 ∩ 不合規檔」並輸出**已定案的 severity**,
pipeline 只消費 `lint.hygiene[].severity`。

初版曾在 pipeline 內自行取交集判擋不擋,經 grill-with-docs 對照 ADR-031 發現
那與 rubric 形成雙重編碼(同一政策兩處),已修正。

### D3. `skill-reviewer` 是 Gate Checker,不是 team role

pseudocode 原寫 `skill_reviewer.review(...)`,但 `skill_reviewer` 既不符合 GLOSSARY 的
`Skill` 定義(`/skill-name` 觸發),也不是 team role(`qa_agent`/`sec_agent` 有
`IF "sec" IN current_team` 守衛且在 `team_compositions.yaml` 有定義,它沒有)。
執行者可能誤解為「未定義的 team 成員」而跳過。

新增術語 **Gate Checker**(CONTEXT.md canonical + GLOSSARY 一句話):
被 gate 呼叫、以 skill 形式實作的檢查器,**無 team 守衛**。
呼叫改寫為 `INVOKE_SKILL("skill-reviewer", scope=...)` 並在註解寫明執行者該做什麼
(載入哪個 SKILL.md、跑哪幾步)。

### D4. rule-registry 兩條規則皆 `observed_by: manual`

`rule-stats.sh:7` 定義待刪候選為「零命中 ∧ 非 exempt ∧ `observed_by ∉ {none, manual}`」。
子規則(`GATE-G5-SKILL-*`)無法被 gate-log 聚合產生(該聚合只合成 `GATE-<G1..G6>` 頂層 id),
若標 `gate-log` 會永遠 0 命中,90 天保護到期後被誤判為待刪候選。標 `manual` 歸類為
「不可觀測」,正確反映其性質。

---

## 後果(Consequences)

**正面影響:**
- skill 品質成為管線的一部分,不再靠人記得手動審
- 判準有 97-repo 的實證基礎,非拍腦袋
- 觸發條件收斂(僅 `**/SKILL.md` 變更),對絕大多數任務零成本

**負面影響 / 技術債:**
- **跨 repo 依賴**:ASP 的 G5 依賴 `~/.claude/skills/skill-reviewer/`(來自另一個 repo)。
  緩解:未安裝時走降級路徑(YELLOW_FLAG,不擋),過渡期安全
- **craft 那條路徑無法在 merge 前驗證**:`INVOKE_SKILL("skill-reviewer", ...)` 要等真實
  G5 HARDEN 跑起來,才知道執行者是否照註解載入並執行該 skill。已驗證的只有 lint 層。
  D3 的術語與明確指令降低了誤解風險,但無法消除「執行者會不會照做」的不確定性
- **H-001 的 repo 級盲點**:H-001 問「repo 內 ≥1 合規」,單獨無法抓「已有好 skill 的
  repo 新增一個壞的」。已由 H-005(逐檔合規 + change-scoped 交集)補上
- `REDFLAG_SELF_UPDATE` 等 regex 仍可能產生 flag 疲勞,需依實際使用調整

**後續追蹤:**
- [ ] 累積 ≥1 次真實 G5 觸發,確認執行者確實會跑 skill-reviewer(驗證 craft 路徑)
- [ ] 觀察 YELLOW_FLAG 數量,若出現 flag 疲勞則收窄對應 regex
- [ ] 90 天後檢視 `make rule-stats`,確認兩條規則正確歸類為「不可觀測」而非待刪候選

---

## 成功指標(Success Metrics)

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 未觸及 SKILL.md 的任務零影響 | G5 行為與現況完全相同 | 讀 pipeline.md 確認整段包在 `IF ... MATCHES "**/SKILL.md"` 內 | 已驗證 ✅ |
| hygiene error 正確擋 | 68 個 SKILL.md 全無 frontmatter 的 repo → 擋 | eval 案例實跑 | 已驗證 ✅ |
| 已知假陽性不擋 | `anthropics/skills` 的 S-001 → 只 flag | eval 案例實跑 | 已驗證 ✅ |
| H-005 誤報率 | ≤5% | 54 個研究樣本回歸掃描 | 已驗證 ✅(1/54) |
| craft 路徑可運作 | 執行者確實觸發 skill-reviewer | 首次真實 G5 觸發時觀察 | **未驗證** |
| 無 flag 疲勞 | YELLOW_FLAG 不會被使用者自動略過 | 使用一段時間後主觀評估 | 待觀察 |

**何時該重新評估**:若 YELLOW_FLAG 開始被自動略過(訊號變雜訊),
或 craft 路徑證實執行者不會照 pseudocode 觸發 skill-reviewer。

---

## 發現但未在本 ADR 處理:G5 定義的既有 drift

grill-with-docs 過程中發現 **G5 的定義在四處不一致**。這是**既有 drift,非本 ADR 造成**,
但它影響「skill 檢查該不該掛 G5」的判斷,故記錄於此:

| 來源 | G5 是什麼 |
|------|-----------|
| `GLOSSARY.md:15` | 六道門 = ADR→SPEC→測試先行→實作→**安全**→部署 ⇒ G5 = 安全 |
| `CONTEXT.md:68` | 「G5=**安全審查**」 |
| `.asp/profiles/pipeline.md:271` | 「G5: **Verification Gate**(HARDEN → DELIVER)」 |
| `.asp/config/rule-registry.yaml` | GATE-G5 desc = 「**Verification Gate**(含 G5.5 Cross-Component Parity)」 |
| `CLAUDE.md:58` | 「**驗證階段** → `/asp-gate G5` + `/asp-reality-check`」 |

**為何影響本 ADR**:若 G5 是「安全審查門」,那把「安全紅旗刻意不擋」(D1)放進 G5
概念上很彆扭——在安全門裡放一個不擋的安全檢查;若 G5 是「驗證/HARDEN 階段」
(安全只是其中一面,與 qa、lint、偷渡偵測、rollback 並列),則本設計完全合理。

**本 ADR 採後者**,因為實作面(`pipeline.md` 的 `evaluate_G5` 實際內容:qa 獨立驗證 +
sec 審查 + make lint + 偷渡偵測 + side effects + rollback)與 `CLAUDE.md` 的工作流描述
都站在「驗證階段」這一側;`GLOSSARY`/`CONTEXT` 的「安全」應是六字對仗的過時簡寫。

**刻意不在本 PR 修的理由**:修 drift 的正確做法是先定調哪個是 canonical 再收斂,
那是使用者對「G5 的本質」的判斷,不該由一個功能 PR 夾帶改動治理框架的核心術語定義。
ADR-031 的教訓是「兩處編碼會 drift」,但它同時示範了正確解法是**先逐項比對、確認零丟失,
再收斂到單一 canonical**——那需要獨立處理。

**建議後續**:另開 issue 收斂 G5 定義(canonical 建議取 `pipeline.md`,
`GLOSSARY`/`CONTEXT` 改為「驗證/HARDEN(含安全審查)」)。

> ✅ **已收斂(2026-08-17,issue #98)**:依上述建議執行——`CONTEXT.md:68` 與
> `GLOSSARY.md:15` 的第 5 道 gate 由「安全(審查)」改為「驗證」,並在 CONTEXT 的
> Gate 詞條加上**權威來源**宣告:每道 gate 的確切範圍以 `.asp/profiles/pipeline.md`
> 為準(ADR-031)。逐項比對確認**只有 G5 語意不符**,G1–G4/G6 兩處說法相容,零丟失。
> `docs/multi-agent-architecture.md:182` 原本就寫「G5: Verification Gate|獨立 QA +
> 安全審查 + 偷渡檢查」,無需改動。本節作為歷史紀錄保留,**決策本身未變更**。

---

## 關聯(Relations)

- 取代:(無)
- 被取代:(無)
- 參考:ADR-031(雙重編碼治理,約束本 ADR 的 D2)、ADR-030(借入外部方法論的先例)、
  ADR-022(複雜度預算:本次 `profiles.total_lines` 3670 < baseline 5177,未觸發棘輪)、
  ADR-018(規則存留治理:D4 的依據)

---

## Verification Evidence(升級至 FIRM 時必填)

| 欄位 | 內容 |
|------|------|
| **驗證日期** | 2026-08-17 |
| **驗證者** | ASP framework maintainers(實作於 PR #94) |
| **POC 範圍** | pipeline.md G5 子句 + rule-registry 兩條規則 + skill-reviewer 全域 symlink |
| **驗證方式** | 5 個 eval 案例實跑 + 54 樣本回歸 + 3 個已發布 repo 實戰檢測 |

**已驗證(lint 層):**
1. **擋/不擋分界正確**——5 個 eval 案例逐一實跑:
   `24kchengYe/human-skill-tree`(68 個 SKILL.md 全無 frontmatter)→ 擋;
   `anthropics/skills`(S-001 假陽性)→ 不擋只 flag;
   `ayghri/i-have-adhd`(craft 佳 packaging 低)→ 不擋;
   `NevaMind-AI/memU`(真 S-001)→ 不擋只 flag(刻意取捨);
   未觸及 SKILL.md → 整段跳過
2. **H-005 change-scoped 三情境**——變更含不合規檔 → error;變更為無關檔 → warning;
   不給 `--changed-files` → repo-wide warning
3. **H-005 誤報率 1/54**(初版誤標 3 個,查出是 naive parser 不認 YAML 隱式多行純量,已修)
4. **實戰檢測 3 個已發布 repo**(talk-craft / visual-web-stack / slidev-deck-stack):
   craft 全 approved;過程發現並修正 skill-reviewer 自身 3 個 bug
   (S-003 誤報、`noncompliant_skills` 未出現在 JSON 頂層、parser 缺口)
5. **ADR 合規**:`profiles.total_lines` 3670 < baseline 5177(ADR-022 未觸發);
   `bash -n install.sh` 通過;diff 除版本字串外全為新增;6 個 gate 函式結構未動

**未驗證(誠實記錄):**
- craft 路徑(`INVOKE_SKILL("skill-reviewer", ...)`)**從未真正執行過**。要等一次真實的
  G5 HARDEN 才知道執行者是否照做。D3 已把原本的 `skill_reviewer.review()`(易被誤解為
  未定義的 team role)改為明確指令 + Gate Checker 術語,但「指令明確」不等於「執行者會照做」——
  這是 merge 前無法驗證的殘留風險。

> **升 Accepted 的條件(2026-08-17 修訂)**:人類看完上述 **lint 層驗證證據**後,
> 以 `/asp:approve-adr 033` 顯式授權(非 AI 自行升級)。
>
> **原條件與修訂理由**:原訂條件為「上述證據 **+ 至少一次真實 G5 觸發的觀察結果**」。
> 修訂原因是原條件**混淆了兩件不同的事**——
> (a) **設計決策的證據**:掛哪個 gate、什麼該擋什麼不該擋、canonical 放哪裡。
>     這些已由 5 個 eval 案例、54 樣本回歸、3 個已發布 repo 實戰充分支撐,是本 ADR 的實質內容。
> (b) **執行期行為的觀察**:執行者讀到 `INVOKE_SKILL(...)` 會不會照做。
>     這是**運維面**的持續追蹤項,不是設計決策的成立前提。
>
> 本 ADR 採納的是 (a);(b) 維持為**已知殘留風險**,由「後續追蹤」第 1 項與成功指標的
> 「craft 路徑可運作 = 未驗證」列繼續追蹤。若日後證實執行者不照 pseudocode 觸發
> skill-reviewer,依「何時該重新評估」重啟本 ADR。
