<!-- Last Updated: 2026-06-08 | Status: Accepted | Audience: ASP framework maintainers, asp-diagram skill implementers -->
# [ADR-008]: 引入 asp-diagram skill 管理 Mermaid 架構圖

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-05-11 |
| **採納日期** | 2026-06-08 |
| **決策者** | astroicers + Claude |
| **觸發事件** | ADR-007 完成三檔分離後，`docs/architecture.md` 仍畫舊單檔模型未同步；review 時發現 11 個內嵌 Mermaid 區塊無索引、無新鮮度標記、無校對機制 |
| **關聯 ADR** | ADR-007（schema v2 三檔分離 — 觸發本 ADR 的具體導火線） |

> ⏸️ **實作延後**（2026-06-12，外部失憶檢查 F3）：決策維持 `Accepted`，但 asp-diagram skill 實作延後，追蹤於 SPEC-005（`Draft (Deferred)`，全部實作項列 Stage 2 PENDING）。**觸發條件**：有實際 Mermaid 治理需求時走 asp-plan 落地 SPEC-005 Stage 2；否則維持 Deferred（不阻擋）。消除「Accepted ADR 卻無對應實作」的審計疑慮。注意：`make diagram`（定義於 `.asp/Makefile.inc:213`，舊 `architecture.html` 產生器，仍存在可跑）與本 skill 設計無關，不在實作範圍。

---

## 背景（Context）

ASP v4.x 已累積 11 個內嵌 Mermaid 區塊散佈於 3 個文件（`docs/architecture.md` 4 個、`docs/multi-agent-architecture.md` 5 個、`.asp/templates/architecture_spec.md` 2 個），缺四項治理機制：

1. **無索引**：找某張圖只能 `grep -rn '```mermaid' docs/`。
2. **無新鮮度**：圖最後更新 commit 未標記，過期不可見。
3. **無建立規範**：新 ADR/SPEC 該不該配圖、放哪、何種語法，沒有統一答案。
4. **無校對機制**：圖說 A、程式碼 / profile 已改成 B，無 gate 抓出。

具體案例：ADR-007 三檔分離已產生「PROJECT/BACKLOG/ROADMAP」資料流，但 `docs/architecture.md` 仍畫舊單檔模型 — 這就是缺機制的直接後果。

本 ADR 解決「Mermaid 圖文件納入 ASP 治理層」的範疇問題。

---

## 評估選項（Options Considered）

### 選項 A：純人工 + checklist

- **優點**：實作量零。
- **缺點**：依賴 AI / 人類自律，與 CLAUDE.md 強制力架構（L1-L4）哲學牴觸。
- **風險**：3 個月後跟現在一樣。

### 選項 B：擴充 asp-ship 增加單一 Step「檢查圖是否更新」（不開新 skill）

- **優點**：實作小，零新 skill。
- **缺點**：建圖（Mode A）與校對（Mode C）邏輯沉重，塞進 asp-ship 會讓 10 步檢查清單膨脹失焦；`/asp-plan` 寫完 ADR 後無法主動觸發；無「校對差異」的獨立入口。
- **風險**：滑坡式肥大化 asp-ship。

### 選項 B'：MVP — 只做 `make diagram-lint` + 手維護 `docs/diagrams/README.md`

- **優點**：covers 問題 1（索引）+ 問題 4（lint）約 50%，實作成本極低（< 1 天）。
- **缺點**：完全不解決問題 2（新鮮度）+ 問題 3（建立規範），無 Mode B 同步、無 Mode C 校對 — 3 個月後一樣會出現「圖說 A、程式 B」。
- **風險**：兩階段拉長 — 此 MVP 落地 → 6 個月後再做完整版，期間累積的圖只增不減。
- **與 ASP 哲學的差距**：與「硬機制優先」原則部分牴觸（lint 是硬機制，但同步/校對仍靠自律）。

### 選項 C（選擇）：新增獨立 asp-diagram skill，三模式設計

- Mode A 初始化（**index-only by default**：掃指定 glob 內所有 `\`\`\`mermaid` 區塊，建 `docs/diagrams/README.md` 索引；不自動建新檔案）
- Mode B 同步（git diff 偵測架構檔變動 → 透過明確的 `source_files` 映射演算法找對應圖檔 → 更新該檔的 mermaid 區塊，保留其他段落）
- Mode C 校對（讀現圖 + 程式碼 / profile，列差異，預設不退出 1；CI 用 `--strict` 旗標才回非 0）
- 整合：`asp-plan` Step 5 結尾提示 Mode A；`asp-ship` 新增 Step 9.5（**含明確 file glob + 排除規則**）偵測架構檔變動時提示 Mode B；獨立呼叫做 Mode C。
- **優點**：職責清晰、可獨立觸發、與 ADR/SPEC/Profile 平行成為治理層第四件套、零新依賴（Mermaid 為 GitHub/VSCode 原生 render）。
- **缺點**：新增 skill 1 份、新模板 1 份、5 個 Makefile target、6 個測試。實作量中等。
- **風險**：trigger word `diagram` 為英文常用詞，無法在「單關鍵詞 router」層做 2-keyword 過濾（router 為單關鍵詞匹配，SKILL.md:102） → 緩解策略改為「skill 本體入口判斷上下文，不相關則早期 redirect」（in-skill gating，不改 router）。

### 選項 D：把 Mermaid 內嵌限定於 ADR/SPEC 本文，不獨立 `docs/diagrams/`

- **優點**：避免「圖與決策分離」風險。
- **缺點**：跨 ADR 共用的系統圖（如多 agent 全景）無歸屬；對外分享時讀者要翻多個 ADR 才能拼出全貌。
- **風險**：圖會在 ADR 之間複製貼上，分歧無法治理。

---

## 決策（Decision）

採**選項 C**。

理由：

1. **職責分離**：建圖、同步、校對性質不同（產出 / 偵測 / 比對），共用一支 skill 但分 Mode 才能彈性觸發。
2. **強制力可疊加且克制**：`asp-ship` Step 9.5 作為 WARN 級提示（不 BLOCK），保留人類判斷空間；且 Step 9.5 的偵測 glob **排除 ADR/SPEC Status-only 變更**（避免每次 Accept 都 WARN），由 SPEC-005 明確定義 include/exclude 規則。
3. **與既有治理對齊**：把 Mermaid 圖視為與 ADR/SPEC 平行的 first-class 文件，落在 `docs/diagrams/`，與 `docs/adr/`、`docs/specs/`、`docs/agents/` 並排。
4. **零新依賴**：Mermaid 是 GitHub/VSCode 原生 render，已在 11 個現存區塊驗證可行。可選 PNG 匯出沿用既有 `make diagram` target（保留為 deprecated alias，新名稱為 `make diagram-render`）。
5. **可遞增採用**：Mode A 預設 index-only 不搬家；Mode B/C 邊用邊調，不需大爆炸 migration。既有 11 個內嵌區塊以 inline 連結納入索引，原檔不動。

**對選項 B' 的回應**：使用者與 reality-checker 提出「為何不先做 MVP」是合理質疑。選 C 而非 B' 的具體理由：問題 2（新鮮度）與問題 3（建立規範）是 ADR-007 落地後**已經發生的痛點**（`docs/architecture.md` 還畫舊模型），不是預想中的未來問題；若先做 B' 則此痛點要拖到 6 個月後。複雜度差距（C 約 3 天工 vs B' 約 1 天工）相對於治理層健全性，在當前 ASP 成熟度（L4 邁向 L5）情境下值得投資。

---

## 後果（Consequences）

**正面影響：**

- 架構文件視覺化首次有治理層，過期可被偵測（透過 `last_updated_commit` frontmatter）。
- 新 ADR/SPEC 配圖有預設動線（plan → diagram Mode A）。
- 「圖過時了」這類臨時需求有明確入口（trigger word `圖過時了` 直達 Mode C）。
- `docs/diagrams/README.md` 成為「圖總目錄」，新成員 onboarding 路徑變短。

**負面影響 / 技術債：**

- `asp-ship` 多一個 WARN 級步驟（Step 9.5），檢查時間 +2-3s（git diff scan）。
- `docs/diagrams/` 新目錄需要長期維護，否則會回到「無索引散落」狀態。
- 現存 11 個內嵌 Mermaid 區塊未自動遷移到 `docs/diagrams/`，新舊並存期會有兩種存放模式（緩解：Mode A 初次跑時建索引指向所有現存區塊，inline 連結，不強制搬家）。
- **兩層治理風險（known limitation）**：編輯既有 `docs/architecture.md` 內嵌區塊不會被 Mode B 偵測（無對應 `docs/diagrams/*.md`），只會被 Step 9.5 提示「考慮跑 Mode B」由人類判斷。此為刻意保留的灰色地帶，避免強制搬家；SPEC-005 邊界條件明列此情境。
- **`diagram` trigger word 誤觸風險**：router 為單關鍵詞匹配（SKILL.md:102），無法在 router 層 2-keyword 過濾；緩解採 in-skill gating（skill 本體偵測「database schema / SQL / API contract」等上下文 → 早期 redirect 不執行 Mode A）。

**後續追蹤：**

- [ ] 落地後第一次 `/asp-diagram Mode A` 跑完，把 11 張既有 Mermaid 區塊納入 `docs/diagrams/README.md` 索引。
- [ ] 觀察 3 個月，若 Mode B 從未被觸發 → 評估是否簡化 ship Step 9.5 偵測條件。
- [ ] 評估是否需要 ADR-009「Diagram 過期 SLA」（例如 ADR 變動後 7 天內必須跑 Mode B）。
- [ ] 評估是否需要把既有 11 個內嵌區塊逐步搬到 `docs/diagrams/`（policy 決定先不搬，到時若搬家成本下降可重議）。
- [ ] 觀察 in-skill gating 對 `diagram` 誤觸的攔截率（目標 ≥ 90%）。

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| `docs/diagrams/README.md` 存在且列出 ≥ 11 條圖連結 | 是 | `test -f docs/diagrams/README.md && [ $(grep -c '^- ' docs/diagrams/README.md) -ge 11 ]` | Mode A 首次執行後 |
| 新 ADR commit 後 14 天內 `docs/diagrams/` 有對應更新 | ≥ 80% | `git log --since=3.months docs/adr/` + `git log --since=3.months docs/diagrams/` 交叉比對 | 落地後 3 個月 |
| `make diagram-lint` 通過率 | 100% | `make diagram-lint` 在每次 commit 前跑 | 每次 commit |
| Mode A/B/C 至少各被呼叫過 1 次（健康度指標） | 是 | `grep -c '"skill":"asp-diagram"' .asp-bypass-log.ndjson` ≥ 3，或 telemetry 計數 | 落地後 1 個月 |
| `docs/architecture.md` 內嵌區塊與當前架構描述一致（透過 Mode C 驗證） | 0 drift | 手動跑 `/asp-diagram Mode C --strict` exit code = 0 | 落地後 1 個月、每季 |

> 註：原本提案中「Step 9.5 WARN 被處理比例 ≥ 70%」指標無法從 `.asp-bypass-log.ndjson` 機械計算（log 只記 bypass 事件，不記「已處理」狀態）→ 改為「Mode A/B/C 呼叫次數」可實際機械驗證。

> 若 3 個月後 Step 9.5 從未觸發 → 重新評估「架構檔變動」偵測規則是否過嚴或過鬆。

---

## 關聯（Relations）

- 取代：無
- 被取代：無
- 參考：
  - ADR-007（schema v2 三檔分離 — 觸發本 ADR 的具體導火線）
  - CLAUDE.md「強制力架構」表（asp-ship Step 9.5 屬 L3 Skill Gates，WARN 級）
  - SPEC-005（本 ADR 對應實作規格）
  - `.asp/hooks/session-audit.sh` lines 56-65（`.asp-bypass-log.ndjson` 為當前正式格式，`.asp-bypass-log.json` 已 deprecated）
  - SKILL.md line 102（router 單關鍵詞匹配機制）
