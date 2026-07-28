<!-- Last Updated: 2026-07-24 | Status: Accepted | Audience: ASP framework maintainers -->
# [ADR-029]: ADR-027 L2 補篇 — ASP hooks 的 worktree 感知（不弱化 repo-wide 治理）

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-07-24 |
| **決策者** | ASP framework maintainers（astroicers 已核准 2026-07-24） |
| **觸發事件** | #73 — worktree session 下 hook 讀主工作樹狀態致跨 session 誤 BLOCKER；#72（ship-gate 已修，PR #74）的姊妹面向 |
| **關聯** | ADR-027（GitHub-native worktree 隔離，本篇為其 L2 補篇）；#72（PR #74，PreToolUse 已解）；#73；#56（競態事故源）；ADR-012（inbox canonical-on-main）；ADR-018（Iron Rule A/B）；FC-006/FC-007（`.asp-fact-check.md`） |

> **狀態說明：** `Draft`（初稿，**禁止實作生產碼**）→ `FIRM`（先跑 §5 定論實驗 + POC）→ `Accepted`（人類審核）。
> 本 ADR 為**設計/分流決策**，不含生產碼。實作待人類核准後另立 SPEC。
>
> ⬆️ 由 `Draft` 升 `Accepted`：使用者 2026-07-24 透過 `/asp:approve-adr ADR-029` 呼叫，看完本指令摘要的**決策分流**（🟢/🟡/🔴/⚪ + 「永不全域改寫 file-global `PROJECT_DIR`」鐵律 + MUST-keep 三錨清單）與 **Verification Evidence 現況（步驟 0 定論實驗 + POC 共 6 項全未勾）** 後明確同意 **Draft 直升**（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。**直升取捨**：本 ADR 為設計/分流決策，其骨架（分流矩陣、鐵律、MUST-keep 三錨）不依賴步驟 0 結果；**實作驗證（步驟 0 + POC）已 gate 於後續 SPEC、非本次 Accept 範圍**。SessionStart 相關項的 🟢/🔴 歸屬待步驟 0 實證後於 SPEC 定案。

---

## 背景（Context）

ADR-027（Accepted）以 per-session git worktree 隔離解決多 session 並行競態（#56）。#72 揭露：worktree 隔離**不完整**——ASP hooks 在 worktree session 中讀的是**主工作樹**的狀態，而非使用者實際所在的 worktree。

### 已確認事實（本 session 實錄）

1. **`CLAUDE_PROJECT_DIR` 於 worktree session 指向主工作樹**（#72 commit `eac1203` 直接模擬佐證）。
2. **SessionStart 亦然**：本 session（於 worktree 啟動）的 SessionStart hook 把 `.asp-session-briefing.json` 寫進**主 checkout**（`/home/ubuntu/AI-SOP-Protocol/.asp-session-briefing.json`），此 worktree 內**不存在**該檔 → CLAUDE.md 啟動 step 0 要 AI 讀的 briefing 反映的是**主樹**狀態。
3. **跨 session 污染實錄**：另一 session 在主 checkout 建的 **Draft ADR-028** 被本 worktree 的 session-audit 誤報為 A3.1 BLOCKER 並（若解析）注入 `Bash(git commit *)` 動態 deny → 誤擋本 worktree**無關**的合法 commit。正是 #56 競態的新形態（主樹狀態經 `CLAUDE_PROJECT_DIR` 洩漏進 worktree session 的治理判定）。
4. **hook 由主樹載入**：`.claude/settings.json` 註冊 `"$CLAUDE_PROJECT_DIR"/.asp/hooks/…` → **實際執行的永遠是主樹那份 hook**。任何 in-hook 修法**在 merge 進 main 前無效**（本 ADR 的 fix 於 worktree 內無法自測——#72 commit 因此合法用 `ASP_SHIP_OK=1`）。

### 全面盤點（7 檔、43-agent workflow）

盤點 `session-audit.sh`(42)、`clean-allow-list.sh`(4)、`pretooluse-ship-gate.sh`(4，已修)、`inbox-ingest.sh`、`inbox-triage.sh`、`l0-audit.sh`、`daily-audit.sh` 全部 `PROJECT_DIR` 使用點，逐點對抗驗證。**核心結論：這不是「把 `PROJECT_DIR` 換成 worktree」的機械修法**——`PROJECT_DIR` 在 `session-audit.sh` 是 file-global，被三個 repo-wide 治理錨（Iron Rule A、A19.1、Iron Rule B）共用，**任何全域切換都會同時靜默關閉這三者**。修法必須逐檢查分流、引入獨立 worktree-scoped 變數。

### 關鍵前提更正（FC-007，dissolves 假設的死結）

盤點 synthesis 一度假設「**SessionStart hook 無 stdin `.cwd`** → hook 內無法得知 active worktree → 需 Claude Code 平台改動（🔴）」。**經官方文件查證（FC-007，`code.claude.com/docs/en/hooks`），此假設錯誤**：SessionStart hook stdin **明確含 `cwd`**（官方 schema 逐字列 `"cwd": "…"`），與 ship-gate 用的 PreToolUse `.cwd` 同一欄。**故 worktree 訊號已由平台提供，session-audit 屬 in-hook 可修，非平台待改。** 唯一殘留是「`cwd` 值在 worktree 啟動時是否＝該 worktree」的一次 live 定論（§5 步驟 0）——機制已文件確認，屬「確認」非「賭注」。

---

## 決策（Decision）

**採「先實證、逐檢查分流」**：引入一個 worktree 解析 helper（僅供 advisory worktree-local 檢查），**明令禁止**重新賦值 file-global `PROJECT_DIR`；repo-wide 治理檢查**繼續**用 `CLAUDE_PROJECT_DIR`。以下矩陣為分流依據（語意欄採對抗 verdict 修正後結論）。

### 決策矩陣（節選重點；完整見 #73 workflow 附錄）

| 檔案 / 檢查 | worktree session 現況 | 正確語意 | 分類 |
|---|---|---|---|
| **session-audit A3 ADR 掃描 + dynamic deny** | 掃主樹 ADR → 主樹 Draft 誤擋、worktree Draft 漏擋 | READ=worktree-local；**WRITE=解析 permission 的目錄（非對稱）** | 🟡 延後（非對稱，需 permission 解析根定論） |
| **session-audit briefing 寫入** | 寫主樹、worktree 讀不到 | worktree-local（但 section-11 stdout 已直送 AI，部分緩解） | 🟡 延後（整檔決策） |
| **session-audit A5/A8/A18/.ai_profile** | 讀主樹 required-files/tech-debt/autopilot-state/profile | worktree-local（各自獨立變數） | 🟢 外科式（A18 須 fail-**open**，勿抄 #72 fail-closed） |
| **session-audit A4.7/A17** | 讀主樹 test-result/fact-check | keep（commit-time 已由 ship-gate 兜底；fact ledger canonical） | ⚪ keep |
| **session-audit A19.1 `[ -d $PROJECT_DIR/.git ]` (L78)** | 主樹 `.git` 恆為目錄 → 對**已隔離** worktree cry-wolf 誤報 | **BROKEN 判別式** | 🟢 修（但受 Iron Rule A hash 保護→須人類核准+hash 更新） |
| **session-audit A19.1 `git worktree list` / Iron Rule A / Iron Rule B / A15 inbox** | 讀主樹/全 repo | **repo-wide-intentional** | ⚪ **MUST keep**（見下） |
| **clean-allow-list（全）** | 維護主樹 permission 強制檔 | **repo-wide-intentional（安全政策）** | ⚪ **MUST keep**（worktree 化＝self-authorization bypass 破壞性操作鐵則） |
| **inbox-ingest / daily-audit（全）** | 讀主樹 canonical inbox / 排程日報 | **repo-wide-intentional** | ⚪ keep（daily-audit 非 #73 目標） |
| **inbox-triage（INBOX 讀 vs ROADMAP 寫）** | 讀要 canonical main、寫要 DP4 worktree、共用一變數 | **內在衝突** | 🟡 延後（ADR-012 級裁決，嚴禁逐行 patch → 會製造 dedup read/write split 重複授權） |

### 共用 resolver（僅供 worktree-local 檢查；鏡像 #72）

```sh
# CLAUDE_PROJECT_DIR 為信任錨；僅在 cwd 為「同一 superproject 的 linked worktree」
# （絕對 git-common-dir 相等）時才覆蓋 → 血緣守衛擋「cd 進無關 repo 植 planted-trace」。
asp_resolve_worktree() {           # $1 = 呼叫者的 cwd 訊號（SessionStart/PreToolUse 傳 stdin .cwd）
  local anchor="${CLAUDE_PROJECT_DIR:-$PWD}" cwd="${1:-$PWD}" top a c
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || { printf '%s' "$anchor"; return; }
  a=$(git -C "$anchor" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  c=$(git -C "$cwd"    rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$c" ] && [ "$c" = "$a" ] && printf '%s' "$top" || printf '%s' "$anchor"
}
```

> **註（2026-07-28）**：上方 snippet 為草稿，**已被 SPEC-017 版取代**——SPEC 版 `_abs_common_dir` 逐字取自 #72 ship-gate 的 `cd`+`pwd` 手動正規化（非本草稿的 `--path-format=absolute` 旗標，後者未經 #72 兩輪審查）並含 top==anchor 短路；語意錨（絕對 git-common-dir 相等＋同 superproject 血緣守衛）不變。**實作以 SPEC-017 為準**（單一實作在 `.asp/scripts/lib/worktree.sh`）。

**鐵律**：worktree-local 檢查呼叫 `WT=$(asp_resolve_worktree "$STDIN_CWD")` 讀 `$WT/…`；repo-wide 檢查繼續用 `$CLAUDE_PROJECT_DIR`。**永不重新賦值 file-global `PROJECT_DIR`**。

### 必須永遠 repo-wide（不可 worktree 化）

| 檢查 | 為何 MUST 保持 repo-wide |
|---|---|
| **Iron Rule A（hook 竄改偵測）** | 比對主樹 on-disk hook vs 主樹 HEAD＝驗證**正在執行的那份碼**（由主樹載入）。改 worktree HEAD → 分支把改過的 governance hook commit 進自己 HEAD 即可自我通過 → 竄改偵測失效 |
| **A19.1 `git worktree list`** | 刻意的跨 session 競態偵測（#56 護欄）；repo-global。只有 L78 `-d .git` 判別式壞、list 本身正確 |
| **Iron Rule B bypass log** | 中央化 gitignored 稽核軌跡 + HWM + hash-chain；拆 per-worktree → 誤觸 HWM shrink、截斷偵測失效 |
| **clean-allow-list deny 來源 + settings 維護** | 破壞性操作鐵則的強制來源，必來自人類掌控的 main；否則 worktree 可改自己分支的 `denied-commands.json` 放寬護欄（血緣守衛擋不住——合法 worktree 本就同 superproject） |
| **A15 / inbox 讀取** | ADR-012 明標 canonical-on-main；T-14 inbox-poisoning 緩解依賴單一佇列 |

### hook 載自主樹這一面（#73 第三面向）

in-hook 修法在 merge 進 main 前無效（實際跑主樹那份）。**plugin-marketplace 安裝（`${CLAUDE_PLUGIN_ROOT}`，FC-006）** 是讓 hook **程式碼** worktree-consistent 的最乾淨長期解（hook 碼住版本化 plugin 目錄、在任何 working tree 之外）。但它須改 **Iron Rule A 驗證模型**（改驗 plugin pinned 版本，非 `git show HEAD:`）+ 動 install.sh/asp-sync → **本 ADR 不做此遷移，另立 ADR**（ADR-021 marketplace 線的後續）。本 ADR 僅明文記載此性質。

---

## 建議 SCOPE

- **🟢 現在做（in-hook、低風險）**：§5 步驟 0 實驗 → 加 `asp_resolve_worktree` helper（sourced，僅 advisory 用）→ 修 A19.1 L78 cry-wolf（走 Iron Rule A 人類核准+hash 更新）→ 移除 dead `SETTINGS_FILE`（L20）→ 外科式 worktree 化 A18(fail-open)/A5/A8/.ai_profile。
- **🟡 延後（需人類設計裁決）**：A3 非對稱（READ→worktree/WRITE→permission 解析根，待步驟 0b 定論）；inbox-triage 整檔（inbox canonical vs ROADMAP worktree 的內在衝突，ADR-012 級）；briefing 整檔決策。
- **🔴 需 Claude Code 平台配合（縮小後）**：**permission 解析根保證**——clean-allow-list/dynamic-deny 要能**證明**寫的是 session 實際強制的 permission 檔（Claude Code 需保證「permission 檔從其 export 為 `CLAUDE_PROJECT_DIR` 的同一 root 載入」）。此保證未定前，clean-allow-list 與 A3-WRITE 維持 keep-as-is。**（註：FC-007 後，SessionStart worktree 訊號**不再**是 🔴——已由 stdin `.cwd` 提供。）**
- **⚪ 永久 keep**：Iron Rule A/B、A19.1 list、inbox 讀取、clean-allow-list 安全政策、daily-audit 排程日報。

---

## 後果（Consequences）

- **正面**：worktree 隔離補完 advisory 面；跨 session 誤 BLOCKER（如 ADR-028 誤擋）消除；A19.1 對已隔離 worktree 不再 cry-wolf；三個 repo-wide 治理錨**明文保護**、不被連坐關閉。
- **負面/成本**：session-audit 需引入 stdin 讀取 + helper（複雜度↑）；A19.1 修改觸 Iron Rule A（人類核准+hash 更新流程）；A3/inbox-triage 的深層分流延後，短期仍有 advisory 面誤報（純 INFO/WARNING，不阻擋）。
- **風險**：若實作者忽略「鐵律」而全域改寫 `PROJECT_DIR` → 靜默關閉 Iron Rule A/A19.1/Iron Rule B（本 ADR 已將此列為最大地雷）。

---

## 成功指標（Success Metrics）

1. worktree session 中，另一樹的 Draft ADR **不再**誤報為本 session 的 A3.1 BLOCKER。
2. 已隔離 linked worktree session **不再**觸發 A19.1「你在主工作樹」誤報。
3. `make test` 綠、Iron Rule A/A19.1/Iron Rule B 的既有測試**全數不回歸**（證明三錨未被弱化）。
4. `session-audit` 的 worktree-local advisory（A5/A8/A18/.ai_profile）反映**使用者實際所在 worktree** 的狀態。

---

## 關聯（Relations）

- **父**：ADR-027（本篇為其 L2 補篇）。
- **姊妹**：#72（PR #74，PreToolUse/ship-gate 已解，本 ADR 的參考正例）。
- **事實依據**：FC-006（plugin hook env / stdin cwd 通則）、FC-007（SessionStart stdin 含 cwd，dissolves 死結）。
- **受限於**：ADR-012（inbox canonical-on-main）、ADR-018（Iron Rule A/B、rule-registry）。
- **後續**：hook 執行搬 `${CLAUDE_PLUGIN_ROOT}`（另立 ADR，ADR-021 marketplace 線）。

---

## Verification Evidence（升級至 FIRM 時必填）

> Draft 階段留空。升 FIRM 前必須補：

### 步驟 0（定論實驗，L2 分支點）
- [ ] **0a**：於 worktree 啟動 session，令 SessionStart hook `echo` stdin `.cwd` → 確認值＝該 worktree（非主樹）。
- [ ] **0b**：確認 Claude Code 從哪個 root 載入/強制 permission（settings.local.json 解析根）→ 決定 A3-WRITE / clean-allow-list 的正確目標。

### POC（步驟 0 通過後）
- [ ] `asp_resolve_worktree` helper 單元測試（worktree/subdir/無關 repo/損壞 worktree/非 git，鏡像 #72 的 A–F）。
- [ ] A19.1 L78 修正後：主樹→報、已隔離 worktree→不報（回歸 `test_worktree_race_detection.sh`）。
- [ ] Iron Rule A / A19.1 list / Iron Rule B 既有測試全綠（證明三錨未弱化）。
- [ ] 端到端：worktree 有 Draft ADR → 擋本 worktree commit；主樹 Draft ADR → **不**擋本 worktree commit。
