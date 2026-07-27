# SPEC-017：session-audit worktree 感知 advisory 檢查（ADR-029 🟢 scope 實作）

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-017 |
| **狀態** | Draft（待 G2 + 人類核准；ADR-029 已 Accepted，本 SPEC 落地其 🟢 scope） |
| **日期** | 2026-07-24 |
| **關聯 ADR** | ADR-029（父，worktree-aware hooks L2 補篇）、ADR-027（worktree 隔離）、ADR-018（Iron Rule A/B、rule-registry）、ADR-012（inbox canonical-on-main） |
| **關聯 issue** | #73（本 SPEC 實作其 🟢 部分）、#72（PR #74，ship-gate 已解，helper 參考正例）、#56 |
| **估算複雜度** | 中（觸 Iron-Rule-A 保護的 `session-audit.sh`；新增 sourced helper；A19.1 判別式修正） |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

讓 `session-audit.sh` 的 **advisory worktree-local 檢查**（A5/A8/A18/.ai_profile/A19.1 判別式）反映使用者**實際所在的 worktree**，而非 `CLAUDE_PROJECT_DIR`（worktree session 下常＝主工作樹）；**同時嚴格保留** Iron Rule A、A19.1 `git worktree list`、Iron Rule B 三個 repo-wide 治理錨不被弱化。

**明確不做（延後至後續 SPEC）**：A3 ADR 掃描的非對稱 READ/WRITE（🟡）、inbox-triage 內在衝突（🟡）、briefing 整檔決策（🟡）、clean-allow-list（⚪ MUST keep）、hook 執行搬 `${CLAUDE_PLUGIN_ROOT}`（另 ADR）。

---

## 🚦 前置條件 #0（步驟 0 定論實驗 — 實作 gate）

ADR-029 定此為分界點。**實作 wiring 前必須先跑並記錄結果**（helper 本身 step-0-independent，可先建；但把 helper 接進 session-audit 的行為取決於此）。

### 0a — SessionStart 的 stdin `.cwd` 值
- **問題**：於 worktree **啟動**的 session（`cd <worktree> && claude`），SessionStart hook 的 stdin `.cwd` ＝該 worktree，還是主樹？
- **已知**（FC-007）：官方 schema 確認 SessionStart stdin **含** `cwd`＝「hook 被呼叫時的 cwd」。
- **已知細微差別**（本 session transcript 實證）：**EnterWorktree 於 session 中途切換**的情形，SessionStart 在切換**前**已於主樹觸發、切換**不重跑** SessionStart → 該情形 `.cwd`＝主樹。故本 fix 對「**啟動即在 worktree**」（使用者描述的 GitHub-per-issue 工作流）有效，對「EnterWorktree 中途切換」無效（後者 SessionStart 已過）。SPEC 須在文件標明此適用範圍。
- **probe（可直接執行）**：於 `.claude/settings.json` 暫加一條 SessionStart hook（**不 commit**）：
  ```json
  { "type": "command", "command": "jq -r '\"[step0a] cwd=\\(.cwd) | event=\\(.hook_event_name) | src=\\(.source)\"' >> /tmp/asp-step0-probe.log" }
  ```
  然後於 worktree `cd <worktree> && claude`（新 session）→ 讀 `/tmp/asp-step0-probe.log`。**通過條件**：`cwd` ＝該 worktree 絕對路徑。

### 0b — permission 解析根
- **問題**：Claude Code 從哪個目錄載入/強制 `settings.local.json`（決定 A3-WRITE / clean-allow-list 的正確目標）？
- **範圍**：本 SPEC **不**動 A3-WRITE / clean-allow-list（列為 🟡/⚪）；0b 結果供**後續 SPEC**決定，非本 SPEC 實作 gate。本 SPEC 僅要求記錄 0b 結論於 `.asp-fact-check.md`。

> **若 0a 失敗**（`.cwd` ≠ worktree）：session-audit 無可靠 in-hook worktree 訊號 → 本 SPEC 的 wiring 部分退回 ADR-029 🔴（需平台配合），僅保留 helper + 其單元測試（step-0-independent 交付）。**不得**在 0a 未過下把 advisory 檢查接 `$PWD`（`$PWD` 於 SessionStart 未證實＝worktree）。

---

## 📥 輸入規格（Inputs）

- SessionStart hook stdin JSON（含 `.cwd`、`.source`、`.hook_event_name`）——**新增讀取**（現行 `session-audit.sh:18` 完全不讀 stdin）。
- `CLAUDE_PROJECT_DIR` 環境變數（現行唯一來源，續作 repo-wide 檢查的錨）。

## 📤 輸出規格（Expected Output）

0. **session-audit.sh 新增 stdin 讀取**：現行 `session-audit.sh:18` 完全不讀 stdin。實作須於檔首讀 `INPUT=$(cat 2>/dev/null)`、`STDIN_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)`（jq 缺 → 空 → 後續退錨；fail-open 不阻 session）。**此為 worktree 訊號唯一來源**，非 `$PWD`（review #1：`$PWD` 於 SessionStart 未證實＝worktree）。
1. **新增 sourced helper** `asp_resolve_worktree`（見 DP1 決定置放）：
   ```sh
   asp_resolve_worktree() {           # $1 = cwd 訊號（SessionStart 傳 stdin .cwd）
     local anchor="${CLAUDE_PROJECT_DIR:-$PWD}" cwd="${1:-$PWD}" top a c
     top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || { printf '%s' "$anchor"; return; }
     [ "$top" = "$anchor" ] && { printf '%s' "$anchor"; return; }
     a=$(_abs_common_dir "$anchor")   # ⚠️ 逐字複用 #72 已驗證的 _abs_common_dir（ship-gate L35-42）
     c=$(_abs_common_dir "$cwd")      #    不得自創第三種正規化變體（review #5）
     [ -n "$c" ] && [ "$c" = "$a" ] && printf '%s' "$top" || printf '%s' "$anchor"
   }
   ```
   **`_abs_common_dir` 必須逐字取自 `pretooluse-ship-gate.sh` 現行實作**（`cd`+`pwd` 手動正規化，非 `--path-format=absolute` 旗標——後者未經 #72 兩輪審查）；DP1=(b) 時二者 source 同一 lib，DP1=(a) 時逐字複製並由 INV-2 parity 測試防漂移。
2. **worktree-local 檢查改用** `WT=$(asp_resolve_worktree "$STDIN_CWD")` 讀 `$WT/…`：**A5**（required-files）、**A8**（tech-debt）、**.ai_profile 相關 A1**。
   - **A18**（autopilot-state）**特殊 fail-open**（review #2）：**僅在 `asp_resolve_worktree` 明確解析到 worktree（`WT` ≠ `anchor`）時**讀 `$WT/.asp-autopilot-state.json`；**解析歧義/退錨（`WT` == `anchor` 且本 session 疑似在 worktree）時 SUPPRESS A18**（不報 resume）——**絕不**退回讀主樹的 state（否則會讀到他 session 殘留 → 誤報 resume，正是 ADR-029 Context §3 要消除的跨 session 污染）。「fail-open」＝寧可漏報 resume，不可誤報。
3. **A19.1 L78 判別式修正**：`[ -d "$PROJECT_DIR/.git" ]`（主樹恆為目錄→對已隔離 worktree cry-wolf）改為以 `asp_resolve_worktree "$STDIN_CWD"` 判斷**本 session 是否在 linked worktree**（`WT` ≠ `anchor` 即在 worktree）：在 worktree→**不**警告；在主樹且有其他活躍 worktree→警告（現行意圖）。
4. **rule-registry 無新增規則**（沿用 AUDIT-A19.1、A5.9、A8.3 等既有 id）。

## 🔗 副作用與連動（Side Effects）

| 連動點 | 觸發 | 護欄 | 驗證 |
|---|---|---|---|
| `session-audit.sh` 受 Iron Rule A hash 保護 | 任何本檔修改 | **Iron-Rule-A** | commit 後 HEAD 更新→hash 自愈（git-HEAD-based）；`test_session_audit*` 全綠 |
| **Iron Rule A（L56-70）續用 `CLAUDE_PROJECT_DIR`** | 不得改 | **MUST keep** | 既有 hash 測試不回歸——驗 helper **未**碰 Iron Rule A 區塊 |
| **A19.1 `git worktree list`（L81-84）續 repo-global** | 不得改 | **MUST keep** | 只改 L78 判別式，不動 list 邏輯 |
| **Iron Rule B log family 續用 `CLAUDE_PROJECT_DIR`** | 不得改 | **MUST keep** | HWM/hash-chain 測試不回歸 |
| **file-global `PROJECT_DIR` 不得重新賦值** | 鐵律 | 三錨 | 靜態檢查：`PROJECT_DIR=` 僅出現於 L18 定義 |

## ⚠️ 邊界條件（Edge Cases）

- `asp_resolve_worktree` 承 #72 的 A–F：worktree/子目錄/無關 repo（血緣守衛擋 planted-trace）/損壞 worktree（退錨，**不** crash）/非 git（退 `CLAUDE_PROJECT_DIR`）。
- SessionStart 無 stdin（極端/測試）→ `${1:-$PWD}` 退 `$PWD`，再由 helper 血緣守衛把關；仍解析不到→退 `CLAUDE_PROJECT_DIR`。
- **EnterWorktree 中途切換**：本 fix 不改善（SessionStart 已過）；文件明標「本 fix 針對啟動即在 worktree」。
- A18 **fail-open**：解析歧義時**絕不**誤報 autopilot resume（誤報比漏報擾民）。

### 🔄 Rollback
單檔可回退：`git revert` 該 commit；helper 為 additive，移除後行為回現狀（讀 `CLAUDE_PROJECT_DIR`）。

## 🧪 測試矩陣

> **⚠️ 測試 harness 鐵則（review #1 CRITICAL）**：所有模擬「worktree session」的 audit 案例，**必須**餵 stdin JSON `{"cwd":"<worktree>",...}` 且 `CLAUDE_PROJECT_DIR=<主樹>`——鏡像 `tests/test_shipgate_worktree.sh` 的 `run_gate()`（L31-38）。**嚴禁**沿用現行 `test_worktree_race_detection.sh` 的 `run_audit()`（直接 `CLAUDE_PROJECT_DIR=worktree`、不餵 stdin）——那**不模擬真 bug**（真況＝anchor 恆主樹 + cwd 訊號在 stdin），會讓 A19.1 修復「假綠」。新增 `run_audit_wt(){ printf '{"cwd":"%s",...}' "$1" | CLAUDE_PROJECT_DIR="$2" bash "$AUDIT"; }`。

| # | 案例（harness） | 期望 |
|---|---|---|
| T1 | `asp_resolve_worktree`：cwd=同 superproject worktree、anchor=主樹 | 回 worktree top |
| T2 | cwd=無關 repo（planted）、anchor=主樹 | 回 anchor（血緣守衛擋） |
| T3 | cwd=主樹子目錄、anchor=主樹 | 回主樹（top==anchor 短路） |
| T4 | 損壞 worktree / 非 git cwd | 回 anchor，不 crash |
| **T5** | A19.1：**stdin.cwd=worktree、CLAUDE_PROJECT_DIR=主樹**（真況）| **不**報 A19.1（cry-wolf 消除）。**必用 run_audit_wt**，否則無效 |
| **T6** | A19.1：**stdin.cwd=主樹、CLAUDE_PROJECT_DIR=主樹** + 有其他活躍 worktree | 報 A19.1（意圖保留） |
| T7 | A18：stdin.cwd=worktree（有 state）、CLAUDE_PROJECT_DIR=主樹（無 state）| 報 resume（讀對 worktree） |
| **T7b** | **A18 fail-open**（review #2）：**主樹有殘留 state**、stdin.cwd 解析歧義/退錨 | **不**報 resume（suppress，不讀主樹殘留） |
| **T5b** | A5：stdin.cwd=worktree 缺 README、主樹有 | 依 worktree 判 MISSING（讀對 worktree） |
| **T8b** | A8：stdin.cwd=worktree 有 overdue debt marker、主樹無 | 依 worktree 判 overdue |
| **T9b** | A1/.ai_profile：stdin.cwd=worktree 有 `.ai_profile`、主樹無 | 依 worktree 判（不誤報缺 profile） |
| **T-INV2** | **parity（INV-2）**：同一組 fixture 分別餵 `asp_resolve_worktree` 與 ship-gate 的解析 | 二者回傳的 PROJ **完全一致** |
| T8 | **回歸**：Iron Rule A / A19.1 list / Iron Rule B 既有測試 | 全綠（證三錨未弱化） |
| T9 | **靜態**：`grep -n 'PROJECT_DIR=' session-audit.sh` | 僅 L18 一處（未全域改寫） |
| **T10** | **靜態（DP1=b 時）**：新 lib 在 `session-audit.sh:57` CRITICAL_FILE 陣列內 | 命中（review #6：納入 Iron Rule A hash 保護） |

## 🎭 驗收場景（Gherkin）

```gherkin
Scenario: worktree session 不再被主樹 Draft ADR 誤報（A19.1 面）
  Given 使用者於 linked worktree 啟動 session（cd worktree && claude）
  And 主工作樹存在另一 session 的 Draft ADR
  When SessionStart session-audit 執行
  Then A19.1 不報「你在主工作樹」（已用 asp_resolve_worktree 判定在 worktree）
  And Iron Rule A / Iron Rule B / A19.1 worktree-list 行為不變

Scenario: 三錨不被 worktree 化弱化
  Given 對 session-audit.sh 套用本 SPEC 修改
  When 執行既有 Iron Rule A / A19.1 / Iron Rule B 測試
  Then 全數通過（helper 僅供 advisory 檢查、未觸三錨）
```

## 🧭 待人類拍板的設計決策點（DP）

| DP | 議題 | 選項 | 傾向 |
|---|---|---|---|
| **DP1** | helper 置放 | (a) inline 於 session-audit.sh　(b) 抽 `.asp/scripts/lib/worktree.sh` 供多 hook source | **(b)**：ship-gate（#72）已有等價邏輯，抽共用 lib 去重、單一真相；但增一個 sourced 相依（Iron Rule A hash 僅含 session-audit.sh，lib 需納入 critical-file 清單或內聯）。**待拍板** |
| **DP2** | A19.1 判別式修正觸 Iron Rule A hash | 走「人類核准 + hash 更新」流程 | 是（同 ADR-029 記載）；本 SPEC commit 後 hash 隨 HEAD 自愈 |
| **DP3** | 適用範圍文件化 | 明標「僅啟動即在 worktree」 vs 嘗試支援 EnterWorktree | **明標範圍**：EnterWorktree 中途切不重跑 SessionStart、in-hook 無法補救，列已知限制 |

## ✅ 驗收標準（Done When）

1. 步驟 0a 已跑並記錄於 `.asp-fact-check.md`（FC-00x）；**0a 通過**方進行下列 wiring（未過則只交付 helper + T1–T4 + T-INV2）。
2. `asp_resolve_worktree` 存在、`_abs_common_dir` 逐字取自 ship-gate、T1–T4 綠。
3. A19.1 L78 修正：**T5（run_audit_wt：stdin.cwd=worktree + CLAUDE_PROJECT_DIR=主樹）不報、T6 報**。**驗收明文要求 T5/T6 用 stdin-piping harness**（review #1）——`test_worktree_race_detection.sh` 擴充後，其 worktree 案例**不得**再用舊 `run_audit()`。
4. A5/A8/.ai_profile 改讀 `asp_resolve_worktree` 結果，**各有對應測試**（T5b/T8b/T9b，review #4，非只有 A18）。
5. A18 **fail-open 正確**：T7（解析到 worktree→讀對）**且** T7b（歧義/退錨 + 主樹殘留 state → **不**報 resume）皆綠（review #2）。
6. **INV-2 parity**：T-INV2 綠——`asp_resolve_worktree` 與 ship-gate 解析在同 fixture 回傳一致（review #3）。
7. **T8 全綠**（Iron Rule A / A19.1 list / Iron Rule B 不回歸）＋ **T9**（`PROJECT_DIR=` 僅 L18）＋（DP1=b）**T10**（新 lib 進 CRITICAL_FILE，review #6）。
8. `make test` 綠、`make lint` clean。
9. 文件標明適用範圍（啟動即在 worktree；EnterWorktree 中途切換為已知限制）。

## 🔗 跨元件不變式（G5.5）

- **INV-1**：worktree-local 檢查用 `asp_resolve_worktree`；repo-wide 檢查（Iron Rule A/B、A19.1 list、inbox）用 `CLAUDE_PROJECT_DIR`。二者**不混用**。**驗證**：T9 靜態（`PROJECT_DIR=` 僅 L18）+ code review 確認三錨區塊未觸 helper。
- **INV-2**：`session-audit.sh` 與 `pretooluse-ship-gate.sh`（#72）的 worktree 解析語意**一致**（同 anchor-first + 同 superproject 血緣守衛）。**由 T-INV2 parity 測試強制**（review #3）：非僅宣告——DP1=(b) 時二者 source 同一 lib（parity 恆真）；DP1=(a) 時 parity 測試在同 fixture 上比對兩份實作、抓漂移。**INV-2 若無法以 parity 測試通過，DP1 不得選 (a)**。

## 🔗 追溯性（實作後回填）
- 實作 commit：TBD
- 測試檔：`tests/test_worktree_resolve.sh`（新）、`tests/test_worktree_race_detection.sh`（擴充 T5/T6）
- Iron Rule A hash 更新：TBD
