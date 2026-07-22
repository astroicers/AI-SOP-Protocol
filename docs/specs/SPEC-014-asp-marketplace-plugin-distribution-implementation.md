# SPEC-014：ASP marketplace plugin 分發實作（enforcement-first）

> 結構完整的規格書讓 AI 零確認直接執行。本 SPEC 為 ADR-021 的**實作規格**（#41 (b)/(c)）；通過 G2 + 人類核准後方可實作。
> **範圍界定（enforcement-first，2026-07-22 依 G2 review 收窄）**：本 SPEC 只涵蓋**強制力層**（SessionStart deny 注入 + PreToolUse commit 閘）由 plugin 承載。**profile/level/template 內容**的 plugin-root standalone 解析**不在本 SPEC**（選項 C dual-path 期間仍由 installer / `~/.claude/asp` 提供）——列為 follow-up。

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-014 |
| **關聯 ADR** | ADR-021（marketplace 分發，Accepted）、ADR-017（分層）、ADR-011（deny 隔離 settings.local.json）、ADR-019（Iron Rule A/B）、ADR-020/SPEC-013（commit 閘） |
| **估算複雜度** | 中（enforcement-first 大幅收窄；核心強制力 POC-1 已證無需改 hook） |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

讓 ASP 的**強制力 hooks**（SessionStart 的 Draft-ADR→`settings.local.json` deny 注入、PreToolUse 的 commit 閘）能以 `/plugin marketplace add astroicers/AI-SOP-Protocol` 一鍵帶入**任何專案**，強制力與現行 `.claude/settings.json` 佈線等價。價值：外部使用者零 installer 即獲護欄。**本 SPEC 不含 profile 驅動行為的 standalone 化**（見範圍界定）。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| `CLAUDE_PROJECT_DIR` | path(env) | plugin hook runtime | 使用者專案根；FC-006 確認對 plugin hook **有保證** |
| `CLAUDE_PLUGIN_ROOT` | path(env) | plugin runtime | plugin 安裝目錄；更新後會變（勿存 state）；非 plugin 時為空 |
| hook stdin JSON | json | Claude Code | 含 `cwd`、`tool_input.command`（PreToolUse）等（FC-002/FC-006） |
| marketplace entry | json | `.claude-plugin/marketplace.json` | `source:"./"`、`strict:false`、`hooks:"./hooks/hooks.json"` |

---

## 📤 輸出規格（Expected Output）

**成功（plugin 安裝於任意專案）：**
- SessionStart → `session-audit.sh`（plugin 承載）掃該專案 `docs/adr/`，有 Draft ADR 時把 `Bash(git commit *)`/`Bash(git commit)` 寫入該專案 `.claude/settings.local.json`（**不碰** tracked `settings.json`，sha256 不變）。
- PreToolUse(Bash) → `pretooluse-ship-gate.sh` 依 `.asp-test-result.json` 新鮮度擋/放 commit。
- **與現行 `.claude/settings.json` 佈線逐位元等價**（同一組腳本；POC-1 已證核心 deny 在 plugin env 下 PASS，且**不依賴任何 `.asp/` 資源**——只讀 `docs/adr` + 寫 `settings.local.json`）。

**明確界定（enforcement-first，誠實）：**

| 面向 | plugin-only 使用者（無 installer）行為 |
|------|------|
| 核心 deny + commit 閘 | ✅ 可用、與現況等價 |
| Iron Rule B（bypass-log 完整性，`bypass-hash.sh`）| 需 plugin-root 解析——本 SPEC **可選**納入（見 Side Effects），否則降級（非 fatal） |
| profile 驗證 A1 / compiled-profile / 散文載入 / `inbox-ingest` A15.1 / Iron Rule A CRITICAL_FILE | **out-of-scope**：dual-path 期間靠 installer / `~/.claude/asp`；純 plugin 下優雅降級（見 Edge Cases E3–E6）。follow-up SPEC 補 standalone |

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| 新增 repo-root `.claude-plugin/marketplace.json` + `hooks/hooks.json`（映射既有 `.asp/hooks/*.sh`） | 實作時 | 分發層（**不動** `.claude/settings.json` 現行佈線） | jq-valid + `/plugin` 互動安裝實測 |
| **必要** double-fire 冪等 sentinel（如 `ASP_HOOK_FIRED_<event>` env 於同一 hook 執行內短路重入） | installer settings.json + plugin hooks.json **共存**同專案（選項 C dual-path） | 三 hook（session-audit / ship-gate / clean-allow-list） | 共存 harness：兩路徑並存 → 每 event 僅生效一次（見 B3） |
| （可選）`session-audit.sh:117` bypass-hash 探索迴圈加 `${CLAUDE_PLUGIN_ROOT}/.asp/scripts/` 段 | 若要 Iron Rule B 在 plugin 下運作 | `session-audit.sh`（**Iron-Rule-A CRITICAL_FILE 之一**，line 57 清單） | 若動此檔：**須人類核准**（Iron Rule A 保護），且 harness 驗非 plugin 行為不變 |

> **驗證方式必填**（G5 檢查）。**注意**：核心 deny + commit 閘**無需改任何 hook 腳本**（POC-1 證）；本 SPEC 的 hook 腳本變更僅限「可選的 bypass-hash plugin-root 段」，且動 `session-audit.sh` 屬 Iron Rule A 保護檔、須人類核准——故列**可選、預設不做**，Iron Rule B 在 plugin 下的完整性另評。

---

## ⚠️ 邊界條件（Edge Cases）

- **E1 純 plugin 使用者（無 installer、專案無 `.asp/`）**：核心 deny + commit 閘 ✅（POC-1 證）；profile 驅動行為降級（out-of-scope）。
- **E2 double-fire 共存（選項 C dual-path 的實際情境）**：外部專案同時有 installer 複製的 `.claude/settings.json` hooks **與** plugin `hooks.json` → 同 event 兩次觸發。**緩解為必要（非可選）**：hook 腳本內加冪等 sentinel，每 event 僅生效一次。「不把 ASP plugin 裝進 ASP repo 自身」僅解自我安裝，不足以覆蓋此情境。
- **E3 Iron Rule A CRITICAL_FILE 檢查在 plugin 下 inert（design decision，非 bug）**：`session-audit.sh:56-64` 以 `git -C ${PROJECT_DIR} show HEAD:.asp/...` 比對——plugin-consumer 專案不 track `.asp/` → 該 guard 為 false、**整段跳過**。**判定安全且刻意**：Iron Rule A 保護的是 **ASP 開發 repo** 的關鍵檔不被場外竄改；plugin 版本完整性由 **plugin loader 的 git-SHA / marketplace 機制**承載（ADR-021 §分發：commit SHA = 版本）。SPEC 明載此界定，**不試圖**在 consumer 專案重建 Iron Rule A。
- **E4 封裝邊界**：`experimental/`、`showcase/` **不在** plugin（ADR-017）；marketplace 不映射；installer 進階/離線路徑仍承載 showcase。
- **E5 測試退役「誠實再定範」**：ADR-021「≥3 sync 測試退役」metric 前提是選項 B（移除 installer）。選項 C 保留 installer → 4 支 installer/sync 測試仍守出貨路徑、`test_managed_deny_reconcile` 守核心 ADR-011（非 sync）。→ **本次不退役任何測試**；defer 到 installer 真被移除（另 ADR）。ADR-021 已補 clarifying 註。
- **E6 profile/inbox 資源在 plugin 下的降級（out-of-scope，記錄以免誤解）**：`asp-compile.sh:41` 的 `ASPR=PROJECT/.asp else ~/.claude/asp`（無 plugin 分支）、`session-audit.sh:184` 呼叫未帶 `--asp-root`、`session-audit.sh:337` `inbox-ingest` PROJECT_DIR-only、`clean-allow-list.sh:21` `denied-commands.json` 無 fallback（靠腳本內建 default）、CLAUDE.md 散文載入路徑硬編 `~/.claude/asp`——這些在純 plugin 下**優雅降級**（compile exit 3 → 散文 fallback INFO；inbox 靜默略過；clean-allow-list 走內建 default）、**皆非 fatal**、**皆不影響核心 deny + commit 閘**。standalone 化為 follow-up SPEC。

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | 移除 `.claude-plugin/`、`hooks/hooks.json`；若曾加 sentinel / bypass-hash 段，還原對應 hook |
| **資料影響** | 無遷移；`settings.local.json` 本地可重建 |
| **回滾驗證** | `make test` 綠 + 現行 settings.json 佈線行為不變 |
| **回滾已測試** | ☐ 是（實作輪填） |

---

## 🧪 測試矩陣（Test Matrix）

| # | 類型 | 輸入條件 | 預期結果 | 對應場景 |
|---|------|---------|---------|---------|
| P1 | ✅ 正向 | plugin 安裝於乾淨專案（無 `.asp/`）+ 該專案有 Draft ADR | 由 plugin 承載的 session-audit 寫 `Bash(git commit *)` 入 `settings.local.json`、commit 被擋 | S1 |
| P2 | ✅ 正向 | 非 plugin（repo 開發 / installer） | 行為與現況逐位元一致、`make test` 綠 | S2 |
| N1 | ❌ 負向 | plugin 安裝但無 Draft ADR | 不注入、commit 放行、`settings.local.json` 自清 | S3 |
| B1 | 🔶 邊界 | tracked `settings.json` 有使用者 deny | 全程 sha256 不變（ADR-011 不變式） | S1 |
| B2 | 🔶 邊界 | 純 plugin、profile/inbox 資源缺 | 核心 deny+閘 ✅；profile/inbox 優雅降級、非 fatal | S4 |
| B3 | 🔶 邊界 | installer settings.json + plugin hooks.json **共存** | 冪等 sentinel → 每 event 僅生效一次（無 double-fire） | S5 |

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: ASP marketplace plugin 強制力等價（enforcement-first）
  作為 外部使用者
  我想要 用 /plugin 一鍵安裝 ASP 強制力到我的專案
  以便 不跑 installer 也享有與 settings.json 佈線等價的護欄

  Background:
    Given ASP repo 含 .claude-plugin/marketplace.json 與 hooks/hooks.json
    And plugin 的 hooks.json 以 ${CLAUDE_PLUGIN_ROOT}/.asp/hooks/*.sh 承載三 hook

  Scenario: S1 - plugin 下 Draft ADR 擋 commit（核心不變式）
    Given 使用者在一個乾淨專案（無 .asp/、無 installer）安裝了 asp plugin
    And 該專案 docs/adr/ 有一份 狀態=Draft 的 ADR
    When SessionStart 觸發 plugin 的 session-audit.sh
    Then .claude/settings.local.json 被注入 "Bash(git commit *)"
    And tracked .claude/settings.json 的 sha256 不變
    And 隨後 session 內的 git commit 被 PreToolUse 閘擋下

  Scenario: S2 - 非 plugin 行為不變（回歸）
    Given CLAUDE_PLUGIN_ROOT 未設
    When 執行三 hook
    Then 行為與現況逐位元一致
    And make test 全數維持綠

  Scenario: S3 - Draft 解除後 deny 自清
    Given plugin 安裝、原有 Draft ADR
    When 該 ADR 改為 Accepted 並重啟 session
    Then settings.local.json 的 git-commit deny 被自清為 []

  Scenario: S4 - 純 plugin 下 profile/inbox 資源缺 → 優雅降級
    Given plugin 安裝、專案無 .asp/、~/.claude/asp 不存在
    When session-audit 嘗試 compile-profile 與 inbox 檢查
    Then 兩者優雅降級（compile 回退散文 INFO、inbox 靜默略過）
    And 核心 deny + commit 閘仍正常（不受影響）

  Scenario: S5 - installer + plugin 共存不 double-fire
    Given 專案同時有 installer 複製的 settings.json hooks 與 plugin hooks.json
    When 同一 SessionStart / PreToolUse event 觸發
    Then 冪等 sentinel 使該 event 的 ASP 邏輯僅生效一次
```

> 每場景 ≥1 `Then`；S1 為 ADR-011 不變式回歸；S5 覆蓋選項 C dual-path 共存。

---

## ✅ 驗收標準（Done When）

- [ ] `.claude-plugin/marketplace.json` + `hooks/hooks.json` 存在、`jq` 合法、schema 正確（`source:"./"`、`strict:false`、hooks 映射）、引用腳本皆存在。
- [ ] **2a（CI-gateable，harness）**：擴充 plugin-layout harness——以 plugin env（`CLAUDE_PLUGIN_ROOT`+`CLAUDE_PROJECT_DIR`）跑承載腳本 → Draft→`settings.local.json` 注入 deny、tracked `settings.json` sha 不變、Draft 解除自清。`make test` 可驗。
- [ ] **2b（human-only，非自動閘範圍）**：互動終端 `/plugin marketplace add ./…` + `/plugin install` 實測 Draft→commit 被擋——**明確排除於 G4/G5 自動閘**，追蹤為人類 sign-off（比照 ADR-021 POC-1「astroicers 待覆核」）。
- [ ] **共存冪等**：S5 harness 通過（installer settings.json + plugin hooks.json 同專案，每 event 僅生效一次）。
- [ ] **P2 回歸**：非 plugin 下 `make test` 綠、三 hook 行為逐位元不變。
- [ ] Iron Rule A CRITICAL_FILE 在 plugin 下 inert 已於 SPEC/程式碼註解**明載為刻意** + 理由（plugin loader git-SHA 承載）；**未**改 `session-audit.sh` 的 Iron Rule A 邏輯。（Iron Rule B bypass-hash plugin-root 段為可選、若動 `session-audit.sh` 須人類核准。）
- [ ] `experimental/`、`showcase/` **不在** plugin 封裝。
- [ ] README/quickstart 有雙路徑契約（`/plugin` 預設、installer 進階/離線）。
- [ ] **無測試被退役**；`make test` 綠。`make lint` 無 error。

---

## 🔗 跨元件不變式（Cross-Component Invariants，G5.5）

| 不變式 | 上游 SSOT | 下游 consumer | 現有格式（grep 證據，已核實） |
|--------|-----------|---------------|----------------------|
| 專案目錄解析（deny 落點正確） | `session-audit.sh:18` `${CLAUDE_PROJECT_DIR:-.}` | `ship-gate:25` `${CLAUDE_PROJECT_DIR:-$(…cwd)}` | 兩者皆用 `CLAUDE_PROJECT_DIR`（FC-006 保證）→ plugin 下 deny 落對專案。ship-gate 另有 stdin `.cwd` fallback（更穩）；此不對稱不影響 plugin（env 有保證），列 robustness 觀察 |
| 核心 deny 路徑不依賴 `.asp/` 資源 | `session-audit.sh` ADR Draft 掃描 + settings.local.json 寫入 | — | 只讀 `docs/adr`、寫 `settings.local.json`（POC-1 證，零 `.asp/` 依賴）→ 核心強制力 plugin-ready |
| double-fire 冪等 | 三 hook 執行入口 | installer settings.json 佈線 vs plugin hooks.json | 現**無** sentinel；SPEC 要求三 hook 同步加（E2/S5） |
| out-of-scope 資源站（記錄，不在本 SPEC 修） | `asp-compile.sh:41` `ASPR`、`session-audit.sh:337` `inbox-ingest`、`clean-allow-list.sh:21` `denied-commands.json`、CLAUDE.md 散文路徑 | — | 皆 PROJECT/HOME 導向、無 plugin 分支；純 plugin 下優雅降級、非 fatal（E6）→ follow-up standalone SPEC |

> 實作 PR 對上表每個 symbol 跨 hook grep 確認（G5.5）；out-of-scope 列僅為**避免誤解範圍**，本 SPEC 不改它們。

---

## 🔗 追溯性（Traceability）

<!-- 實作完成後回填 -->

| 實作檔案 | 測試檔案 | 最後驗證日期 |
|----------|----------|-------------|
| （實作時填入：`.claude-plugin/marketplace.json`、`hooks/hooks.json`、三 hook 若加 sentinel） | （實作時填入：plugin-layout harness + 共存 harness） | YYYY-MM-DD |

---

## 📊 非功能需求（NFR）

| 類別 | 需求 | 驗證方式 |
|------|------|----------|
| 安全（強制力） | plugin 下 L1/L1.5 強制力與 settings.json 佈線等價、不可繞過 | 2a harness + 2b 互動 e2e |
| 相容 | 非 plugin 路徑零回歸；共存不 double-fire | P2 `make test` + S5 |
| 可維護 | 不新增 sync 漂移面（不退役測試、不動 installer 契約、不動 Iron Rule A 邏輯） | 測試清單 diff = 0 退役 |
