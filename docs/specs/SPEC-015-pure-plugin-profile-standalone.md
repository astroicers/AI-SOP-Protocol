# SPEC-015：純 plugin profile-standalone（讓 plugin 使用者無 installer 亦得 profile 驅動行為）

> 結構完整的規格書讓 AI 零確認直接執行。本 SPEC 承接 SPEC-014「範圍界定」列為 follow-up 的 profile-standalone（#67）；通過 G2 + 人類核准後方可實作。
> **範圍**：讓**純 plugin 使用者（無 installer、無 `~/.claude/asp`）**經 marketplace plugin 即獲 **profile 驅動行為**（compiled-profile 載入 + A1 驗證），補齊 SPEC-014 enforcement-first 留下的最後一塊。**強制力（deny + commit 閘）SPEC-014 已達成，本 SPEC 不動。**

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-015 |
| **關聯 ADR** | ADR-021（marketplace）、ADR-017（分層）、ADR-016（compiled-profile）、ADR-013（profile-map）、ADR-027（ASP 不 ship 下游 CLAUDE.md 模板——本 SPEC DP2 須重審） |
| **估算複雜度** | 高（觸及 Iron-Rule-A session-audit.sh + 新 bootstrap 元件 + 下游 CLAUDE.md 立場） |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

純 plugin 使用者（`/plugin install asp` 後，無 installer）在其專案能得到 **profile 驅動的 session 行為**——`.asp-compiled-profile.md` 由 plugin 承載的 profiles 編譯而生、AI 於 SessionStart 讀取——而非只有強制力 hooks。價值：`/plugin marketplace add` 成為 installer 的**真正替代**，而非僅「護欄子集」。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制 |
|----------|------|------|------|
| `CLAUDE_PLUGIN_ROOT` | path(env) | plugin hook runtime | FC-006 保證；plugin cache 含 `.asp/{profiles,config,scripts}`（source `./`） |
| `.ai_profile` | file | 使用者專案 | **純 plugin 使用者預設無**——本 SPEC 須提供 bootstrap（DP1） |
| plugin `.asp/config/profile-map.yaml`+`.asp/profiles/` | files | plugin cache | 已隨 source `./` 打包（確認存在） |

---

## 📤 輸出規格（Expected Output）

**成功（純 plugin 使用者，專案有 `.ai_profile`）：**
- SessionStart → `session-audit.sh` 由 **`${CLAUDE_PLUGIN_ROOT}/.asp/scripts/asp-compile.sh --asp-root ${CLAUDE_PLUGIN_ROOT}/.asp`** 編譯 → 於使用者專案生 `.asp-compiled-profile.md`（自足產物，含來源清單）。
- AI 依 root `CLAUDE.md` 啟動程序 step 0 讀 `.asp-compiled-profile.md` → 得 profile 驅動行為（無需解析 `~/.claude/asp` 路徑——**compiled 產物自足，繞過 prose-load 硬編路徑問題**）。

**明確界定：**
- **compiled path 為主**；prose-load fallback（CLAUDE.md 硬編 `~/.claude/asp/profiles`）對純 plugin 使用者**無法解析**（`${CLAUDE_PLUGIN_ROOT}` 是 hook env、AI 讀 CLAUDE.md 時不可見）→ 本 SPEC **不靠 prose-load**，改確保 compiled path 恆可用；prose-load 僅在 compile 失敗時降級（degraded，記錄）。

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發 | 影響模組 | 驗證 |
|--------|------|---------|------|
| `session-audit.sh:180-184` asp-compile 探索迴圈加 `${CLAUDE_PLUGIN_ROOT}/.asp/scripts`（順序 project→home→plugin），並傳 `--asp-root <對應 root>` | 實作 | **Iron-Rule-A 保護檔** | harness：純 plugin env（無 project `.asp`、無 `~/.claude/asp`）+ `.ai_profile` → 編譯出 `.asp-compiled-profile.md`；非 plugin 行為逐位元不變（COMPILE_ASPR == 舊解析）；**plugin+home 並存 → home 勝**（S5）|
| **（G2-F2）`session-audit.sh:117` Iron Rule B `bypass-hash.sh` 探索迴圈同加 `${CLAUDE_PLUGIN_ROOT}/.asp/scripts` 段**——同一 file 同一類兩分支 gap，否則純 plugin 的 tamper-evidence（`:120-125`）靜默略過 | 實作 | **Iron-Rule-A/B** | harness：純 plugin + `.asp-bypass-log.chained` → hash 驗證確實執行（非略過）|
| **（G2-F3）`session-audit.sh:166-170` 既有 A1 `WARNING`（`.ai_profile 不存在`）augment 引導 `/asp:init`**——更正 N1 措辭：此處**現為 WARNING、非靜默 INFO** | SessionStart 無 `.ai_profile` | **Iron-Rule-A** | 驗 WARNING 訊息含「跑 /asp:init」|
| 新 `/asp:init` 命令（DP1）：於當前專案建 `.ai_profile`(+ 專案 CLAUDE.md，DP2) | 使用者執行 | `.claude/commands/asp/`（plugin 已映射） | 命令產出正確 `.ai_profile`；冪等（已存在則保留）|
| （DP2）plugin 是否 ship 專案 CLAUDE.md 模板 | 設計決策 | 觸及 ADR-027「ASP 不 ship 下游 CLAUDE.md」立場 | 見 DP2 |

> **asp-compile 已支援 `--asp-root`**（`asp-compile.sh:30`）→ **compile 端零改動**；只改 session-audit 呼叫端（Iron-Rule-A，須人類核准 + commit）。

---

## ⚠️ 邊界條件（Edge Cases）

- **E1 純 plugin、專案無 `.ai_profile`**：session-audit `[ -f PROFILE_FILE ]` 為否 → 跳過編譯（現狀）。→ 使用者須先 `/asp:init`（DP1）bootstrap。SPEC 須讓「無 `.ai_profile`」時 session-audit 印一則 INFO 引導跑 `/asp:init`（非 fatal）。
- **E2 installer + plugin 共存**：探索順序 `project → home → plugin`（DP3，G2 修正）——**home 先於 plugin**：installer 的 `~/.claude/asp`（含使用者客製 profiles / 刻意 pin 的舊版）優先，plugin 僅在 project/home 皆無時生效。COMPILE_ASPR 必與所選 script 同 root（一致性不變式）。**須測 plugin+home 並存 → home 勝**（S5；原 SPEC 的 S2 只測 `CLAUDE_PLUGIN_ROOT` 未設，未覆蓋此共存組合）。
- **E3 prose-load 對純 plugin 不可解析**：如上界定——compiled path 為主；SPEC **不**試圖讓 AI 解析 `${CLAUDE_PLUGIN_ROOT}`。
- **E4 plugin 更新換路徑**：`${CLAUDE_PLUGIN_ROOT}` 更新後變——每次 SessionStart 即時解析、compiled 產物寫在使用者專案（非 plugin dir），故不受 plugin 路徑變動影響。

### 🔄 Rollback
移除 session-audit 探索迴圈的 plugin 段 + `/asp:init` 命令；`make test` 綠 + 非 plugin 行為不變。

---

## 🧪 測試矩陣

| # | 類型 | 輸入 | 預期 | 場景 |
|---|------|------|------|------|
| P1 | ✅ | 純 plugin env（無 project `.asp`/無 `~/.claude/asp`）+ 專案有 `.ai_profile` | session-audit 由 plugin root 編譯 → `.asp-compiled-profile.md` 生成、含來源 | S1 |
| P2 | ✅ | 非 plugin（installer） | COMPILE_ASPR 與現況一致、行為逐位元不變、`make test` 綠 | S2 |
| N1 | ❌ | 純 plugin、專案無 `.ai_profile` | 跳過編譯 + 既有 A1 **WARNING** augment 引導 `/asp:init`（非 fatal、不擋 session） | S3 |
| P3 | ✅ | `/asp:init` 於空專案 | 建正確 `.ai_profile`；再跑已存在則保留（冪等） | S4 |
| P2b | ✅ 邊界 | **plugin + `~/.claude/asp` 並存**（dual-path）、無 project `.asp` | COMPILE_ASPR = **home**（installer 優先，plugin 不搶） | S5 |

## 🎭 驗收場景（Gherkin）

```gherkin
Feature: 純 plugin profile-standalone
  作為 只用 /plugin 安裝 ASP 的外部使用者
  我想要 不裝 installer 也得到 profile 驅動行為
  以便 /plugin 成為 installer 的真正替代

  Scenario: S1 - 純 plugin + .ai_profile → 由 plugin 編譯 profile
    Given 專案無 .asp/、無 ~/.claude/asp，但有 .ai_profile
    And ASP plugin 已安裝（CLAUDE_PLUGIN_ROOT 指向 plugin cache）
    When SessionStart 觸發 session-audit.sh
    Then asp-compile 以 --asp-root ${CLAUDE_PLUGIN_ROOT}/.asp 執行
    And 使用者專案生成 .asp-compiled-profile.md（含來源清單）

  Scenario: S2 - installer 使用者行為不變（回歸）
    Given CLAUDE_PLUGIN_ROOT 未設、~/.claude/asp 存在
    When session-audit 編譯 profile
    Then COMPILE_ASPR == 舊解析結果（~/.claude/asp 或 project/.asp）
    And make test 全綠

  Scenario: S3 - 純 plugin 無 .ai_profile → 引導 init（不擋）
    Given 純 plugin、專案無 .ai_profile
    When SessionStart 觸發
    Then 既有 A1 WARNING augment 為含「跑 /asp:init 以啟用 profile 驅動行為」
    And session 正常啟動（非 fatal）、強制力 hooks 仍運作

  Scenario: S5 - installer+plugin 共存 → home 勝（回歸，G2-F1）
    Given ~/.claude/asp 存在（installer）、CLAUDE_PLUGIN_ROOT 已設（plugin）、專案無 .asp/
    When session-audit 解析 asp-compile 來源
    Then COMPILE_SCRIPT 與 COMPILE_ASPR 來自 ~/.claude/asp（home 先於 plugin）
    And 不使用 plugin 的 profiles（符合 marketplace「dual-path 期間 profile 由 installer 提供」）

  Scenario: S4 - /asp:init bootstrap 冪等
    Given 空專案
    When 執行 /asp:init
    Then 建立 .ai_profile（+ 專案 CLAUDE.md，依 DP2）
    And 再次執行時保留既有 .ai_profile
```

---

## 🧭 待人類拍板的設計決策點（DP）

| DP | 決策 | 選項 | 初步建議 |
|----|------|------|---------|
| **DP1** | 純 plugin 使用者的 `.ai_profile` bootstrap | (a) 新 `/asp:init` 命令　(b) SessionStart hook 自動建預設　(c) 純文件教學 | **(a)**：顯式、不 intrusive、plugin 已映射 commands。**G2 修正**：非「直譯 installer Phase 2 bash」——`.claude/commands/asp/*.md` 是**自然語言 AI 指令檔**，故 `/asp:init` 為 **AI 驅動對話**（用 AskUserQuestion 問 type/level）建 `.ai_profile`(+CLAUDE.md，DP2)。**明確排除** installer Phase 2 的 `.claude/settings.json` hook 佈線步驟（`install.sh:505-524`）——純 plugin 的 hooks 已由 `hooks/hooks.json`+`${CLAUDE_PLUGIN_ROOT}` 佈線，該步會指向不存在的 `~/.claude/asp/hooks`。(b) 會讓 hook 未經同意寫使用者專案（違反最小驚訝）|
| **DP2** | plugin 是否 ship 專案 CLAUDE.md 模板 | (a) `/asp:init` 產一份最小專案 CLAUDE.md（指向 compiled 產物）　(b) 完全靠 compiled 產物、不 ship CLAUDE.md | **(a) 最小模板**——但**須重審 ADR-027**「ASP 不 ship 下游 CLAUDE.md」立場（本 SPEC 是該立場的第一個實際反例，須 ADR 補充或 supersede）|
| **DP3** | asp-compile 探索順序 | project → home → plugin ／ project → plugin → home | **project → home → plugin**（**home 先於 plugin**——G2 修正：若 plugin 先於 home，dual-path 使用者（有 `~/.claude/asp` + plugin、無 project `.asp`）的 profile 來源會被 plugin 搶走，**牴觸 `marketplace.json:13`「profile 內容 dual-path 期間仍由 installer 提供」**。故 home 優先保 installer 使用者行為不變；plugin 僅在 project/home 皆無時生效。）|

---

## ✅ 驗收標準（Done When）

- [ ] `session-audit.sh` asp-compile 探索迴圈含 `${CLAUDE_PLUGIN_ROOT}/.asp/scripts`，且傳 `--asp-root` = 所選 script 對應 root（一致性）。
- [ ] **P1**：純 plugin env + `.ai_profile` → 生成 `.asp-compiled-profile.md`（harness 驗）。
- [ ] **P2 回歸**：非 plugin 下 COMPILE_ASPR 與現況一致、`make test` 綠、三 hook 逐位元不變（除本探索段）。
- [ ] **P2b 共存回歸（G2-F1）**：plugin + `~/.claude/asp` 並存、無 project `.asp` → COMPILE_ASPR = home（installer 優先，plugin 不搶）。
- [ ] **Iron Rule B（G2-F2）**：`session-audit.sh:117` bypash-hash 探索含 `${CLAUDE_PLUGIN_ROOT}` 段 → 純 plugin 的 tamper-evidence 執行（非略過）。
- [ ] **N1**：純 plugin 無 `.ai_profile` → 既有 A1 WARNING augment 引導 `/asp:init`、非 fatal、強制力仍運作。
- [ ] `/asp:init`（DP1）建正確 `.ai_profile`、冪等；（DP2）依決策產專案 CLAUDE.md。
- [ ] Iron Rule A：session-audit.sh 變更已 commit（disk == HEAD）、無 A 系列 BLOCKER。
- [ ] DP2 若採 (a)：ADR-027「不 ship 下游 CLAUDE.md」已由新 ADR 補充/supersede。
- [ ] `make test` 綠、`make lint` clean、無測試退役。

---

## 🔗 跨元件不變式（G5.5）

| 不變式 | SSOT | consumer | 現況 |
|--------|------|----------|------|
| COMPILE_SCRIPT 與 COMPILE_ASPR 同 root | session-audit 探索迴圈 | asp-compile `--asp-root` | 現不傳 --asp-root（讓 asp-compile 自解析）；本 SPEC 改為顯式傳、須與 script 來源一致 |
| asp-compile `--asp-root` 語意 | `asp-compile.sh:30,41` | session-audit 呼叫 | 已支援；本 SPEC 只是開始使用它 |

---

## 🔗 追溯性（實作後回填）
| 實作檔案 | 測試檔案 | 日期 |
|---|---|---|
| （`session-audit.sh` 探索段、`.claude/commands/asp/init.md`、DP2 CLAUDE.md 模板） | （純 plugin compile harness + /asp:init 測試） | YYYY-MM-DD |
