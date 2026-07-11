# [ADR-026]: 借鑒 claude-mem 的 lifecycle-hook 記憶模式（純檔案版）

| 欄位 | 內容 |
|------|------|
| **狀態** | `Draft` |
| **日期** | 2026-07-11 |
| **決策者** | ASP framework maintainers（待人類核准） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

比較 [t2o0n321/claude-mem](https://github.com/t2o0n321/claude-mem)（PostgreSQL/pgvector + MCP + 外部 embedding 的持久記憶系統）與 ASP 後，誠實結論是：**claude-mem 的「產品」不適合裝進 ASP**——它是 user-global 安裝、帶 Docker/DB/外部 API 依賴、且會「自動注入未經人類驗證的記憶」，與 ASP 三條核心正面對撞：

1. 純 bash 零 runtime（vs Docker/PostgreSQL/Node）；
2. ADR 人類把關鐵則（vs 自動生成並注入決策式記憶）；
3. 複雜度預算棘輪（ADR-022）。

而且 ASP 已在 **ADR-003（cancel MCP server）**、**ADR-017（RAG 降 showcase 選配）** 主動拒絕過這條路線。

**唯一值得帶走的是抽象模式**：「Claude Code 的 lifecycle hook 就是記憶與強制的落點。」查證官方文件（`code.claude.com/docs/en/hooks`）確認 Claude Code 有 9 個 hook 事件，而 ASP 只用了 **2 個**（`SessionStart` + `PreToolUse`）。有兩個既有缺口正好能用這個模式、以**純 bash/jq** 補上：

- **缺口 A（讀回閉環）**：`make session-checkpoint`（`.asp/Makefile.inc` L425-429）把紀錄 append 進 `docs/session-log.md`（gitignored），但**沒有任何機制在下次 SessionStart 把它讀回注入 context**——AI 寫的 checkpoint 寫進黑洞。跨 session 的「經驗／踩過的坑」因此丟失（`.asp-autopilot-state.json` 只存 task 狀態，無知識）。ASP 記憶目前只有「durable（committed 決策）」與「transient（gitignored 狀態）」兩層，缺第三層「自動捕捉的經驗記憶」。
- **缺口 B（compact 後動態狀態流失）**：ADR-020 明載 compiled profile 在對話壓縮後蒸發。CLAUDE.md 的靜態速查（L60-65）會被 harness 重注入而存活，但**當前 draft ADR／gate 狀態／進行中的 autopilot task／最近經驗**這些*動態*狀態無法靠靜態 CLAUDE.md 攜帶。ASP 的 SessionStart hook 因**無 matcher**（`.claude/settings.json` L3-16），其實已在 compact 後重跑，但 `session-audit.sh` 不分辨 `source`、也沒重新注入這些動態重點。

**誠實的起點**：這不是引入新記憶系統，而是「把已存在的散落機制（session-checkpoint、session-briefing）接上 lifecycle hook 的讀回閉環」，並用官方已支援的 hook 能力補動態狀態。

---

## 評估選項（Options Considered）

### 選項 A：直接安裝 claude-mem（或其精神的 DB/向量版）
- **優點**：語意 hybrid search、成熟的自動捕捉。
- **缺點**：Docker + PostgreSQL + Node + 外部 embedding API；user-global 安裝污染所有專案；把 session 內容送第三方（撞秘密保護）。
- **風險**：撞核心 1/2/3 與 ADR-003/017/022；且「自動注入未驗證記憶」**主動製造** ASP 設計來防的失效模式。**駁回。**

### 選項 B：借「lifecycle-hook 記憶模式」，純檔案自製（採用）
- **優點**：複用既有 `session-audit.sh` / `session-checkpoint` / briefing；純 bash/jq，零新 runtime、零外部 API；一切留專案內、可版控、可稽核；語意內容人工把關（守核心 2）。
- **缺點**：無語意檢索（只有時序 tail-N 與機械事實）——但這正是「observations 非 decisions」的刻意取捨。
- **風險**：低。

### 選項 C：只做 Feature B（compact 重注入），不做日誌
- **優點**：改動最小。
- **缺點**：不補記憶第三層空白（缺口 A 才是 claude-mem 對照下最大的差距）。
- **風險**：低，但價值不完整。

### 選項 D：不做
- **優點**：零新增。
- **缺點**：放棄一個低成本、對照 claude-mem 明確存在的記憶缺口修補。
- **風險**：無，但漏掉低成本改善。

---

## ADR-010 摩擦評估（自證：本案不是「為抄 claude-mem 形式而加層」）

| 鏡頭 | 評估 |
|------|------|
| **新增元件清單** | **1 個新 hook 檔**（`.asp/hooks/session-end-journal.sh`）+ 對 `session-audit.sh` 的**增段**（非新 script）+ 2 個 Makefile target（`journal-note`/`journal`）+ 1 個新 gitignored 狀態檔。**無新 runtime、無新 daemon、無新掃描點、無 DB、無 MCP。** |
| **與既有層重疊？** | 不重疊而是**接合**：`session-checkpoint` 已寫紀錄但無人讀回 → Feature A 補「讀回」那一半；`session-audit.sh` 已在 SessionStart 注入 briefing → Feature A/B 只是**擴充同一 stdout 面**，非平行新機制。 |
| **overhead vs 節省** | overhead ≈ SessionEnd 一次 `git log/diff --stat` + `jq` append（毫秒級、純副作用，不阻擋 exit）；SessionStart 多讀 tail-3 jsonl。節省＝跨 session 經驗不再丟失、compact 後動態狀態可回。**淨值為正。** |
| **結論** | **通過**——複用既有 hook 面與既有 checkpoint 機制、零新層、零外部依賴。**翻盤點（誠實標註）**：見下方「Feature B 誠實邊界」——若 compact 動態注入實測價值低於雜訊，Feature B 可獨立回退，不影響 Feature A。 |

---

## Feature B 誠實邊界（必記，勿誇大）

官方文件確認：**`PreCompact` hook 不能注入 context**（只能 `block` 或做 side-effect）。故本案**不用 PreCompact 做注入**，改用 ASP 既有的無-matcher `SessionStart` hook（天然在 compact 後重跑）。

更關鍵的誠實邊界：**CLAUDE.md 靜態速查（L60-65）本就被 harness 在 compact 後重注入而存活**。因此 Feature B 的增量價值**僅在於動態狀態**（當前 draft ADR／gate／autopilot task／最近 journal note）——這些靜態 CLAUDE.md 攜帶不了。若實測顯示動態注入的價值不明顯，Feature B 應被檢討回退（見成功指標的重新評估條件）。

---

## 決策（Decision）

採 **選項 B**：借 claude-mem 的「lifecycle-hook 記憶模式」，以**純 bash/jq** 實作兩個 feature，全部留在專案內：

- **Feature A（讀回閉環）**：新增 `SessionEnd` hook（`session-end-journal.sh`）自動 append 機械事實到 `.asp-session-journal.jsonl`（append-only，gitignored）；`session-audit.sh` 於 SessionStart 讀 tail-N 注入 stdout，**關掉 checkpoint「寫了沒人讀」的缺口**。語意「學到什麼」由 AI／人類經 `make journal-note` 追加（守人類把關）。
- **Feature B（compact 重注入）**：`session-audit.sh` 解析 hook stdin 的 `source`，當 `source == "compact"` 時額外注入「動態狀態存活包」（draft ADR／gate／task／最近 journal note）。

**明確不做（維持核心）**：不引入 Docker/PostgreSQL/pgvector/MCP/外部 embedding；不自動生成或注入「決策」記憶（日誌只存 observations）；不做 user-global 安裝。

本決策為 `Draft` 提案——**禁止對應生產代碼**（hook／Makefile／settings.json 改動須待人類核准升 Accepted）。

---

## 後果（Consequences）

**正面影響：**
- 補上 ASP 記憶第三層（自動捕捉的經驗記憶），跨 session 經驗不再丟失。
- compact 後動態狀態可回，直擊 ADR-020 已知殘留痛點的*動態*部分。
- 全程純檔案、可版控、可稽核，示範「借觀念不借架構」。

**負面影響 / 技術債：**
- 無語意檢索（時序 tail-N）——刻意取捨，量大時可能需 rotate `.asp-session-journal.jsonl`（SPEC 須定義上限與 rotate）。
- `session-audit.sh` 首次讀 stdin JSON——須確保**無 stdin 時不 hang、不破壞既有 SessionStart**（fail-open）。
- Iron Rule A：`session-audit.sh` 受 hash 完整性保護（L53-70），修改後新 hash 須隨 commit 更新，並把 `session-end-journal.sh` 納入受保護清單。

**後續追蹤：**
- [ ] `[Accepted 後]` SPEC-014（兩 feature 二元驗收）
- [ ] `[Accepted 後]` TDD：先寫失敗的 hook 測試
- [ ] `[Accepted 後]` 實作 hook + Makefile + settings.json + .gitignore
- [ ] `[Accepted 後]` 文件同步：CLAUDE.md hook 清單、GLOSSARY、Iron Rule A 保護清單
- [ ] `[Accepted 後]` `make audit-health` 確認 Iron Rule A/B 與 briefing 不破

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 零新 runtime／外部依賴 | 只用 bash/jq/git，無 Docker/DB/API | 程式碼審查 | 實作時 |
| 讀回閉環成立 | 上個 session 的 journal 條目出現在下個 SessionStart stdout | 手動 E2E（重開 session） | 實作時 |
| SessionEnd 不阻擋、不破壞 | 純副作用，exit code 被忽略、session 正常結束 | hook 測試 | 實作時 |
| compact 分支正確 | `source=compact` 時輸出存活包；其他 source 不輸出 | `CLAUDE_SESSION_SOURCE=compact` 測試替身 | 實作時 |
| 不破壞既有強制力 | briefing／dynamic deny／Iron Rule A/B 全通過 | `make audit-health` | 實作後 |

> **重新評估條件**：(1) 若 journal 注入使 SessionStart 明顯變慢或 stdout 雜訊過高 → 縮小 tail-N 或改按需；(2) 若 Feature B 動態注入實測價值低於雜訊 → 回退 Feature B（保留 Feature A）；(3) 若有人提議把日誌升為「決策來源」→ 拒絕（撞 ADR 人類把關鐵則）。

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - **ADR-003**（cancel MCP server）、**ADR-017**（RAG 降 showcase）——本案「不做 DB/MCP」的既有依據
  - **ADR-020**（AI 遺忘 / 機械強制；偽硬 gate 之忌）——Feature B 針對其*動態*殘留；SessionEnd 純副作用不做偽 gate
  - **ADR-022**（治理複雜度棘輪）——本案僅 +1 hook +2 target，棘輪帳見上方摩擦評估
  - **ADR-010**（最小採納 / 摩擦評估）——本 ADR 須通過（接合既有層、零外部依賴）
  - `t2o0n321/claude-mem`（借鑒對象；借觀念不借架構）
  - `.asp/hooks/session-audit.sh`（增強目標）｜`.asp/Makefile.inc` L425-429（`session-checkpoint`，讀回閉環的另一半）｜`.claude/settings.json`（hook wiring）
  - 官方 `code.claude.com/docs/en/hooks`（SessionEnd 輸出被忽略、PreCompact 不能注入、SessionStart stdout 注入、多層 hook 皆觸發）

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由**人類**將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。AI 不可自行升級狀態。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | （待填，人類核准後進 TDD／POC） |
| **驗證日期** | （待填，人類） |
| **驗證者** | （待填，人類） |
| **驗證摘要** | （待填）預期驗：SessionEnd append 格式正確、SessionStart 讀回注入成立、compact 分支正確、既有強制力不破。 |
