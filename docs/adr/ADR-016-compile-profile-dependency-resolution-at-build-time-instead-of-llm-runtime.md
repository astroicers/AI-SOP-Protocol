# [ADR-016]: Compile profile dependency resolution at build time instead of LLM runtime

| 欄位 | 內容 |
|------|------|
| **狀態** | `FIRM` |
| **日期** | 2026-06-11 |
| **決策者** | astroicers（v5 簡報 Phase 3）+ AI（編譯器設計） |

> **狀態說明：** `Draft`（初稿，禁止實作）→ `FIRM`（POC 驗證，允許 commit，需附驗證證據）→ `Accepted`（人類審核通過）

---

## 背景（Context）

Profile 檔頭的 `<!-- requires / optional / conflicts -->` 宣告目前靠 LLM 在 runtime「自覺解析」：CLAUDE.md 指示讀 `.ai_profile` → 對照散文映射表 → 自行展開 requires、自行避開 conflicts。這不可靠（LLM 可能漏載 requires、無視 conflicts）也不可審計（沒有任何 artifact 記錄「本 session 實際載入了什麼」）。ADR-013 已把映射機械化（profile-map.yaml）、ADR-014/015 已收斂分類學與瘦身內容——本 ADR 補上最後一塊：**把依賴解析從 LLM runtime 移到編譯期**，產出單一扁平載入產物。

---

## 評估選項（Options Considered）

### 選項 A：維持 LLM runtime 解析，只強化 CLAUDE.md 指示

- **優點**：零新腳本。
- **缺點**：「更用力地叮嚀 LLM」正是 v5 要淘汰的散文治理模式；漏載/衝突無機械防護，無審計 artifact。
- **風險**：v5 原則 1（確定性下沉）在載入鏈這個最上游環節缺位，前面所有瘦身的可靠性都被 runtime 解析的不確定性打折。

### 選項 B：編譯期解析，產出 `.asp-compiled-profile.md`（採用，簡報定案）

- **優點**：載入集合由 `asp-compile.sh` 確定性計算（同輸入同輸出、可測試）；conflicts 在編譯期報錯（exit 1 指明衝突對）而非 runtime 被忽略；產物檔頭記錄來源清單與行數 = 審計 artifact；mtime 比對自動重編（SessionStart hook 委派 `--check`）。
- **缺點**：新增一支 ~250 行編譯器腳本；產物與散文 profile 並存期需明確 fallback 順序。
- **風險**：與 asp-metrics 的選擇邏輯漂移 → 緩解：兩者讀同一 profile-map.yaml（ADR-013），且新增**契約測試**：`asp-compile --list` 輸出必須等於 `asp-metrics --simulate` 的 `profiles_loaded`（機械鎖定兩實作）。

### 選項 C：編譯進 CLAUDE.md 本體（取代而非並存）

- **優點**：單一檔案。
- **缺點**：CLAUDE.md 是人工編輯的行為憲法（鐵則、特殊規則），機器覆寫人工內容的衝突處理複雜且危險；compiled 產物應該 gitignored（per-machine），CLAUDE.md 是 tracked。
- **風險**：機器與人工互踩，違反「規則越少越鐵」。

---

## 決策（Decision）

選擇 **選項 B**：

### 1. `asp-compile.sh`（`.asp/scripts/`，隨 P2 的 scripts 複製進 user-level）

- 輸入：專案 `.ai_profile`（欄位先過 `validate-profile.sh` 把關，error 即 exit 2——不複寫驗證）；level 數字經 `level-resolve.sh` 正規化。
- 選集：讀 `profile-map.yaml` rules（與 asp-metrics 同一資料來源）→ 命中聯集。
- 展開：requires 以 DFS 後序展開（依賴在前的拓撲序）；**循環 → exit 5**；幽靈引用（如 `multi_agent`）→ WARNING 容錯跳過。
- **衝突裁決兩段式**（ADR-014 D3/D8 落地）：
  1. `loose_mode` 由 `workflow: vibe-coding` 衍生載入、且衝突方（autonomous_dev/autopilot/pipeline/multi_agent 任一）同時在載入集 → **丟棄 loose_mode + WARNING**（向後相容舊 L5 組態）；
  2. 其餘衝突（含顯式 `level: loose` + `autopilot: enabled`）→ **exit 1**，stderr 指明衝突對（`loose_mode × autopilot`）。
- 產出：`.asp-compiled-profile.md`（**gitignored**——per-machine 編譯結果）。檔頭：編譯時間、asp 版本、map 版本、來源 profile 清單（含各檔行數）、總行數；內文以 `<!-- ─── profile: name ─── -->` 分隔串接。總行數 > 2,500 → stderr WARNING。
- `--check`：產物 mtime ≥ max(.ai_profile, profile-map.yaml, 各來源 profile, 腳本自身) → 「fresh」exit 0 不重寫；否則重編。mtime 比對**只在此處實作**（單一來源）。
- `--list`：只印解析後載入集（契約測試 + 除錯用）。
- 退出碼：0 成功/fresh｜1 conflicts｜2 .ai_profile 缺失或欄位驗證失敗｜3 map 缺失/不可解析｜5 requires 循環｜6 缺 jq。

### 2. 觸發點

- **SessionStart**：session-audit.sh 新增 Section 1.5（A16，A1 之後 A5 之前）：`timeout 15 asp-compile --check --quiet`；rc=1 → WARNING `A16.1`（衝突屬設定錯誤，不擋 session）；其他失敗 → INFO `A16.2`（回退散文載入）；hook 維持恆 exit 0。briefing JSON 加 `compiled_profile_ok` / `compiled_profile_lines`。腳本尋徑：專案 `.asp/scripts/` → `~/.claude/asp/scripts/`（fallback），找不到整段靜默跳過。
- **install.sh Phase 2 結尾**：best-effort 首次編譯（失敗不擋安裝）；gitignore 清單加 `.asp-compiled-profile.md`。

### 3. CLAUDE.md 載入指示（dogfood + 模板）

- 本 repo CLAUDE.md 啟動程序加第 0 步：「`.asp-compiled-profile.md` 存在且新鮮 → 直接讀取之（其檔頭列來源清單）；不存在 → 依映射載入散文 profile（fallback）」。
- install.sh 專案 CLAUDE.md 模板同步加此指示。
- install.ps1：印 WARNING 註明 Windows 原生路徑暫以散文 fallback（known deviation，與 ADR-014 R5 同型）。

### 4. 回滾方式

單 commit revert：腳本/測試純新增；session-audit.sh §1.5 與 CLAUDE.md 指示行隨 revert 消失；`.asp-compiled-profile.md` 為 gitignored 產物，刪除即可。fallback 散文載入路徑全程保留，回滾無行為損失。

---

## 後果（Consequences）

**正面影響：**
- 載入鏈最上游變為確定性：漏載 requires / 無視 conflicts 從「LLM 自律」變「編譯期報錯」。
- 每個 session 有可審計的載入 artifact（產物檔頭 = 來源清單與行數）。

**負面影響 / 技術債：**
- 產物與散文並存期（直到使用者升級 + 重編）存在雙真相窗口 → CLAUDE.md 明示 fallback 順序 + briefing 欄位讓 AI 知道走哪條路。
- session-audit.sh 變更觸發 Iron Rule A → 同 commit stage（staged 豁免），CHANGELOG 註明升級提示。
- Windows（install.ps1）暫無編譯 → 散文 fallback + `tech-debt: MED test-pending`。

**後續追蹤：**
- [ ] 收尾：`asp-metrics --compare --assert-reduction 30 --assert-configs L3_system_design,L5_autonomous` 驗收（G1 F-7 校正：L3 現值 **-29.94%**，差 0.06pp——此降幅來自 Phase 1+2 內容瘦身，Phase 3 編譯器本身不刪內容；L5 -25.26%，待 Phase 4 凍結移出 multi-agent/rag 後預估 -34%。**兩者驗收統一移至 Phase 4 後收尾**，L3 缺口由收尾的死文字清理（global_core/pipeline 歷史註記）補足，向使用者回報）
- [ ] v6：散文 fallback 退場評估（產物成為唯一載入路徑）

---

## 成功指標（Success Metrics）

| 指標 | 目標值 | 驗證方式 | 檢查時間 |
|------|--------|----------|----------|
| 三組態編譯成功 | L1/L3/L5 exit 0、產物含對應來源清單、拓撲序正確 | `tests/test_asp_compile.sh` T1-T3 | 每次 make test |
| 顯式衝突報錯 | `level: loose` + `autopilot: enabled` → exit 1、stderr 含 `loose_mode` 與 `autopilot` | T4 | 每次 |
| 衍生衝突降級 | `workflow: vibe-coding` + `autonomous: enabled` → exit 0 + WARNING、loose_mode 不在產物 | T4b | 每次 |
| mtime 自動重編 | `--check` 新鮮不重寫；`touch .ai_profile` 後重編 | T7 + hook 實測 | 每次 |
| 與 metrics 零漂移 | `--list` 輸出 == `asp-metrics --simulate` 的 profiles_loaded（三組態） | T11 契約測試 | 每次 |
| context 稅 ≥30% 下降 | 對 ADR-013 baseline；L3 立即驗收，L5 於 Phase 4 後收尾驗收 | `--assert-reduction 30` | 收尾 |

---

## 關聯（Relations）

- 取代：（無——supersede CLAUDE.md「散文映射表 = 唯一載入指示」的現狀，散文降級為 fallback）
- 被取代：（無）
- 參考：ADR-013（profile-map 單一來源——本 ADR 是其 Phase 序第三個消費者，G1 F-3 措辭校正）、ADR-014（衝突裁決 D3/D8 的執行者）、ADR-015（scripts 複製進 user-level 的依賴）、ADR-011（settings.local 隔離先例——產物同屬 per-machine gitignored）
- **Partial supersede：ADR-013「Phase 3 單階段 ≥30% 驗收」**（G1 F-8）——拆為「L3+L5 統一於 Phase 4 後收尾驗收（`--assert-configs`）」；L1 增幅為 ADR-014 既載的刻意取捨，不列驗收組

---

## Verification Evidence（升級至 FIRM 時必填）

> 填寫後由人類將狀態改為 `FIRM`，允許對應生產代碼 commit（audit-health 輸出 YELLOW FLAG）。

| 欄位 | 內容 |
|------|------|
| **POC 分支 / 測試結果** | branch `asp/v5-slimming`：test_asp_compile.sh（含契約測試 T11）+ test_session_audit_compile.sh 全綠；本 repo 實際編譯產出產物 |
| **驗證日期** | 2026-06-11 |
| **驗證者** | astroicers（2026-06-11 對話 blanket 授權 ADR-015~018；AI 代筆狀態變更） |
| **驗證摘要** | 依賴解析移至編譯期：三組態編譯成功、衝突兩段式裁決、mtime 自動重編、與 metrics 契約鎖定 |
