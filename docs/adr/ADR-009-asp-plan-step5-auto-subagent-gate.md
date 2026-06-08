# ADR-009：asp-plan Step 5 內建 G1/G2 subagent gate（AI 自律強制）

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-05-12 |
| **採納日期** | 2026-06-08 |
| **決策者** | astroicers + Claude |

---

## 背景（Context）

ASP v4.x 的 review automation 目前長這樣：

- `asp-gate` skill 提供 G1（Architecture）、G2（Specification）、G3（Test）、G4（Implementation）、G5（Validation）、G6（Production）六個 gate，皆採 **opt-in 軟性觸發**（使用者或 AI 須主動呼叫 `/asp-gate Gn`）。
- `asp-ship` Step 9 做 secret scan 與機械檢查，但**不**做語義 / 術語 / 一致性審查。
- 「subagent 獨立驗證」在 CLAUDE.md 強制力架構表中屬於 L4，列為「中等」強度。

### 觸發本 ADR 的具體事件（N=1 經驗證據）

ADR-008 + SPEC-005 草案完成後，使用者**手動**叫了 `/asp-gate G1+G2`，subagent 跑出 2 個 WARN：

| WARN | 性質 | 是否真實 |
|------|------|---------|
| 2.6 SPEC line 18 `workflow` 用詞與 CONTEXT.md avoid 清單衝突 | 術語一致性 | 真實 catch — 既有 asp-ship Step 9 不會抓 |
| 2.3 Done When 含 PENDING 註解 | 完整性 | 噪音 — SPEC 自己已宣告 Stage 1 預期狀態 |

訊噪比 1:1，但「真實 catch」是 asp-ship 機械正則層**不可能**抓到的層次。

### 問題定義

若 review automation 維持 opt-in，下次：
- 使用者沒提醒 → AI 可能直接 `/asp-ship`，WARN 2.6 級的問題會跟著 commit
- AI 自以為「ADR/SPEC 看起來夠紮實」→ 同上

這違反 ASP「硬機制優先」精神（CLAUDE.md 鐵則架構），是**強制力與信賴度的缺口**。

---

## 評估選項（Options Considered）

### 選項 A：P1 — 維持 opt-in 純人類觸發（現狀）

- **優點**：零實作成本；人類判斷靈活；不會誤觸發。
- **缺點**：依賴人類記得、依賴 AI 自我抑制趕進度的衝動；已知會被跳過（剛才的 session 就靠使用者主動提醒）。
- **風險**：累積到大型 ADR/SPEC 時漏報嚴重，技術債回沖。

### 選項 B：P2 — AI 自律 spawn（本 ADR 選擇）

- **機制**：`asp-plan` Step 5 寫完 ADR/SPEC 後，AI **必須**自動 spawn G1/G2 subagent，無需使用者明說。報告寫 `.asp-gate-log/{ts}-G{n}-{id}.md` + 主對話摘要。
- **觸發判斷（必須機械化，禁止 AI 啟發式判斷）**：以 `git diff --cached --name-only` 對 staged 變更做 glob 匹配 — 命中 `docs/adr/ADR-*.md` → G1；命中 `docs/specs/SPEC-*.md` → G2；兩者同時命中 → G1+G2 並行。其他 plan（只動 profile / skill / code）glob 不命中，不觸發。**這個判斷不可由 prompt 啟發式取代** — 因為「這次 plan 算不算修改了 ADR」若交給 AI 判斷，正是本 ADR 要關閉的 rationalization 面（"this isn't really an ADR-level change"）。具體 trigger 命令與 edge case（rename、status-only 修改、檔案刪除）由 SPEC-006 規定。
- **強制力來源**：
  1. `asp-plan.md` Step 5 加 "Common Rationalizations" 段落（mirror `asp-ship.md` 既有結構）禁止跳過理由
  2. `asp-ship.md` Step 9.6 偵測「commit 含新 ADR/SPEC 但無對應 gate log」→ WARN（不 BLOCK）。**步驟編號 9.6 是為了避開 ADR-008 已 reserve 的 Step 9.5（diagram WARN）**；若 ADR-008 最終被否決 → 本 ADR 的 Step 9.6 還原為 9.5
  3. 跳過走既有 `⚠️ ASP BYPASS` 流程，寫 `.asp-bypass-log.ndjson` 留痕（一行 NDJSON，schema 見 ADR-006）
- **優點**：可逆性高（純 prompt 工程，改回 P1 只要改 asp-plan.md）；成本低；強制力中等；保留人類最終裁決空間（BLOCKER 才暫停）。
- **缺點**：依賴 AI 紀律 — 若 prompt 對抗失敗，仍可能被 rationalize 跳過；只覆蓋 ADR/SPEC，不涵蓋大型重構 / migration script 等 case。
- **風險**：
  - AI 在 context 上限附近時仍可能跳過（已知失敗模式）→ 緩解：subagent 不佔主 context，且 ship Step 9.6 後驗會抓到
  - G2 對 SPEC 內 PENDING 註解誤判 WARN → 緩解：trial 期間調整 G2 prompt 模板

### 選項 C：P3 — Hook-level 強制（settings.json）

- **機制**：`.claude/settings.json` 加 PostToolUse hook，偵測 staged 含 ADR/SPEC → 阻擋 `git commit` 直到 `.asp-gate-log/` 有對應 entry。
- **優點**：強制力最硬，AI 無法繞過。
- **缺點**：每個 Draft ADR commit 都會觸發（即使內容沒實質變動，只改 Status）；hook 必須足夠快（< 5s）→ 限制 subagent 模板複雜度；新增 hook 是不可逆性較高的承諾（settings.json 改動牽連深）。
- **風險**：誤觸發頻繁 → 使用者習慣性 bypass → bypass log 爆炸 → 機制空轉。

### 選項 D：P2+P3 混合

- **機制**：P2 為日常路徑；只在「ADR Status 從 Draft 改 Accepted」這一次 commit 時走 P3 強制。
- **優點**：把硬擋用在最高價值的 transition 點。
- **缺點**：需要先建好 P2 基礎設施；P3 偵測 Status 變更的 hook 邏輯不簡單（需 git diff 解析 YAML/Markdown frontmatter）；複雜度高。
- **風險**：實作前無法驗證假設「Accepted transition 那次最重要」是否成立。

---

## 決策（Decision）

採 **選項 B（P2 — AI 自律 spawn）**。

### 理由

1. **可逆性最高**：純文件層（asp-plan.md / asp-ship.md），改回 P1 只要 revert 那兩個檔案；無 hook、無新依賴、無 schema 變動。
2. **成本/強制力最佳比**：實作成本 ~280 行 + 1 ADR，換到「中等強制力 + 完整審計痕跡」。P3 投資更大但風險更高，P1 投資為零但不解決問題。
3. **可驗證再升級**：跑 3 次 trial 後若仍被跳過 → 升級 P3（D 混合）；若訊噪比差 → prompt 工程調整。決策可逆。
4. **與 ASP 現有強制力架構對齊**：CLAUDE.md L4 Subagent QA「中等」強度 → P2 把它升格為「結構化軟性」，介於 L3 與 L4 之間，與 `asp-ship` 10 步檢查同一層級。
5. **不擴大範圍**：本 ADR 不涵蓋 G3/G4/G5/G6 自動化、不涵蓋專職 subagent 路由（reality-checker / test-engineer）— 這些等 P2 trial 結果出來再決定，避免過度設計。

### 不選 P3 的關鍵理由

ADR Draft commit 是常態（CLAUDE.md 明示允許），P3 每次都阻擋 → 使用者體感極差，會教育出「直接 bypass」的反射，反而傷害更深的 L1/L2/L3 強制力（既有 git commit 動態 deny）的信賴度。先用 P2 收集「跳過率」資料，跳過率高才升級 P3。

---

## 後果（Consequences）

### 正面影響

- ADR/SPEC 寫完即驗，設計問題在 plan 階段攔截，不沉澱進實作 commit。
- `.asp-gate-log/` 成為審計痕跡 — 之後可統計 catch / noise / 漏報數，量化 review automation 價值。
- 「subagent review 是 ASP 治理層的 first-class 機制」第一次被明文化（之前只在 CLAUDE.md 強制力架構表略提）。
- 同樣的 pattern 為未來 G3/G5 自動化提供模板。

### 負面影響 / 技術債

- `asp-plan` Step 5 變慢（+ 2-3 分鐘等 subagent）— 但通常是 plan 流程的結尾，使用者已準備等待 review，影響可接受。
- subagent API cost +每次 plan ~2 次 call × sonnet 用量 — 對個人/小型專案可忽略，企業需要編列預算。
- `.asp-gate-log/` 目錄需要長期維護（暫定保留全部，後續視大小可加 retention policy）。
- 「AI 自律」依賴 prompt 紀律，較硬擋有更大 false-negative 空間（AI 仍可能 rationalize 跳過）。
- 「跳過理由清單」維護負擔：新的 rationalization pattern 出現要更新 asp-plan.md。

### 後續追蹤

- [x] **本 ADR Accept 同一個 commit 內**：同步更新 `CLAUDE.md` 強制力架構表 L4 行 — **選項 (c) 已採用**（2026-06-08）：L4 保留為「on-demand Subagent QA」，auto-spawn G1/G2 歸入 L3 Skill Gates。CLAUDE.md 強制力架構表已更新。開放問題 #1 關閉。
- [ ] **SPEC-006 為本 ADR 落地實作的硬依賴**：`asp-plan.md` Step 5 文字、`asp-ship.md` Step 9.6 文字、trigger glob 命令、rationalization 初始集等實作細節皆 defer 到 SPEC-006。**禁止 Accept ADR-009 後直接動 `.claude/skills/asp/*.md` 而 SPEC-006 尚未存在** — 走 asp-plan flow 把 SPEC-006 寫出來 + 通過 G2 再實作
- [ ] **Trial 階段**（接下來 **≥ 3 個 distinct plans**，每個 plan 至少修改 1 個 ADR 或 1 個 SPEC；ADR-008 本次 session 那筆計 N=1，後續還需 ≥ 2 個獨立 plan 才可進評估）：每次紀錄 catch / noise / 漏報 / AI 是否真的有自動觸發 / 是否成功寫入 `.asp-gate-log/`
  > ⚠️ **注意（2026-06-08）**：本 ADR 因 SPEC-005/006 已 merge 而 ADR 仍 Draft 觸發 audit BLOCKER，緊急升 Accepted。Trial ≥3 distinct plans 前置條件**尚未完成**（目前 N=1）。Trial 需繼續追蹤，不可視為 closed。
  > 📌 **Trial 追蹤日誌**（TD-006）：
  > - `N=1`（2026-06-08，ADR-008 session）— 計入。
  > - （2026-06-08，tech-debt remediation session：TD-004/002/005/001 修復）本 session 為 bug 修復，**未走 asp-plan Step 5**，且 auto-spawn gate 機制**尚未實作** → 無 catch/noise/漏報 資料點可產生，**N 維持 1**。
  > - ⛓️ **關鍵依賴（更正分項追蹤）**：Trial 進度（TD-006）**硬依賴** SPEC-006 auto-gate 落地（TD-007）。auto-gate 實作前 N 無法 > 1（無機制可觸發 catch/noise）。下一個有效資料點 = SPEC-006 實作後第一個經 asp-plan Step 5 的 distinct plan。
- [ ] **Trial 結果評估**（≥ 3 distinct plans 後）：
  - 跳過率 0% + 訊噪比 ≥ 1.0 + log 完整率 100% → 接受 P2 為穩定狀態，標記本 ADR `Accepted` 並 close trial
  - 跳過率 > 0% → 開 ADR-010 評估升級到 P3 或 D 混合
  - 訊噪比 < 1.0 → prompt 工程迭代 G1/G2 模板，再跑 ≥ 3 個 distinct plans
- [ ] **3 個月後**：評估 G3（test gate）是否值得用同 pattern 自動化
- [ ] **6 個月後**：評估 `.asp-gate-log/` 累積資料是否能支撐 telemetry 報告（ADR-004 對接點）

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| AI 自動觸發 G1/G2 的 plan 比例 | ≥ 90% | **分母**：`git log --diff-filter=AM --name-only --pretty=format: \| grep -E 'docs/(adr\|specs)/(ADR\|SPEC)-.*\.md' \| sort -u`（從 git 反推 ADR/SPEC 異動次數）；**分子**：`.asp-gate-log/` 對應 entries 數。**禁止用 log 自己當分母**（log 沒寫進去的 plan 會被無視 → metric 假象變高） | Trial ≥ 3 distinct plans 後 |
| G1/G2 訊噪比（真實 catch ÷ 噪音 WARN） | ≥ 1.0 | 人工標註 `.asp-gate-log/` 每個 WARN entry | Trial ≥ 3 distinct plans 後 |
| 漏報事件數（事後使用者 / reality-check 發現但 gate 沒抓） | 0（trial 期間） | 人工回顧 | Trial ≥ 3 distinct plans 後 |
| `asp-plan` Step 5 平均耗時增量 | < 5 分鐘 | 主對話時間戳 | 每次 plan |
| `.asp-bypass-log.ndjson` 中「step=auto-gate」紀錄比例 | < 10% | **遷移後**（ADR-006/008 規定 `.ndjson` 為正式格式，目前 skills + Makefile 仍部分使用 `.json`）：`total=$(wc -l < .asp-bypass-log.ndjson); hit=$(jq -s 'map(select(.step == "auto-gate")) \| length' .asp-bypass-log.ndjson); echo "scale=2; $hit / $total" \| bc`。**遷移前**：metric 暫不可計算（視為 N/A，不阻擋本 ADR 落地） | 落地後 1 個月（且 bypass-log 已遷移至 ndjson） |

**重新評估觸發條件**：
- 任一指標連續 2 次未達標 → 開 ADR-010 升級到 P3
- AI 主動 bypass 出現「新型 rationalization」未被既有清單涵蓋 → asp-plan.md 即時補充，不開新 ADR

---

## 關聯（Relations）

- **取代**：無
- **被取代**：無
- **參考**：
  - ADR-005（Pre-GA holistic review gate）— 同屬 review automation 治理層；本 ADR 把 Pre-GA 那次「人類主導 review」往前移到 plan 階段、由 subagent 執行
  - ADR-008（asp-diagram skill）— 觸發本 ADR 的具體 session；ADR-008 自己經 G1+G2 驗證的經驗成為本 ADR 的 N=1 樣本
  - ADR-004（asp-telemetry）— `.asp-gate-log/` 為未來 telemetry 對接點
  - CLAUDE.md「強制力架構」表 L4 行（Subagent QA）— 本 ADR 把該行從「中等」升格為「結構化軟性」
  - SKILL.md 路由表（既有 `/asp-gate` 條目）— 不修改，繼續為 G3-G6 提供手動入口

- **協調（Coordinates-with）**：
  - **ADR-008**：共用 `asp-ship` Step 9 區段。ADR-008 占 Step 9.5（diagram WARN），本 ADR 占 Step 9.6（gate-log 後驗）。若 ADR-008 被否決 → 本 ADR Step 9.6 還原為 9.5（無實質衝突）

## 開放問題（Open Questions — 留給 SPEC-006 / Accept 前的人類裁決）

1. **L3 vs L4 邊界**：本 ADR 把 auto-spawn subagent gate 定位為「介於 L3 與 L4」。長期是 (a) 合併 L3+L4？(b) 新增 L3.5 行？(c) L4 保留為「on-demand subagent」，本 ADR 改寫的部分歸入 L3「Skill Gates」內？— **「必須擇一改表」是 Iron commitment（後續追蹤第 1 條）；「擇哪一個」是本開放問題**。三選項皆可，由 SPEC-006 階段或 Accept reviewer 決定，但不可懸置不選。
2. **G2 對 PENDING 註解的處理**：本 session N=1 顯示 G2 對 SPEC 內合法 PENDING 狀態誤判為 WARN。G2 prompt 模板需加例外規則「PENDING 是 Stage 1 合法狀態，不單獨 WARN」— 規則文字由 SPEC-006 定。
3. **rationalization 清單初始集**：「Common Rationalizations」段落要列哪些初始反例？至少：(a) "this ADR is simple"、(b) "I already mentally verified"、(c) "user is in a hurry"、(d) "the SPEC is just a draft"。後續發現新模式即時補。
4. **`.asp-gate-log/` retention policy**：目前規定「保留全部」，6 個月後若超 1MB / 1000 檔，要不要 archive？— 暫不在本 ADR 決定，留給未來營運觀察。
