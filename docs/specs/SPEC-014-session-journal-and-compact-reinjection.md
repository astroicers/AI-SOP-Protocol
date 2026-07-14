# SPEC-014：Session 敘事日誌讀回閉環 + Compact-aware 重注入

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-014 |
| **關聯 ADR** | ADR-026（Accepted） |
| **估算複雜度** | 低（純 bash/jq，複用既有 hook 面） |
| **建議模型** | — |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

以純 bash/jq 借鑒 claude-mem 的「lifecycle-hook 記憶模式」，補上 ASP 兩個缺口：

- **Feature A（讀回閉環）**：新增 `SessionEnd` hook 自動把「本 session 的機械事實 + 人工 note」append 到 `.asp-session-journal.jsonl`；`session-audit.sh` 在 SessionStart 讀最後 N 筆注入 stdout → 讓跨 session 經驗真的被帶回。
- **Feature B（compact 重注入）**：`session-audit.sh` 解析 hook `source`，`compact` 時額外注入「動態狀態存活包」。

**非目標**：語意/向量檢索、決策記憶、外部依賴（見 ADR-026「明確不做」）。

---

## 📥 輸入規格（Inputs）

| 來源 | 內容 |
|------|------|
| SessionStart hook stdin | JSON，含 `source`（`startup`/`resume`/`clear`/`compact`）。無 stdin 時視為空 → fail-open。 |
| `.asp-session-marker.json`（gitignored） | SessionStart 寫入的 `{head, ts, branch}`，供 SessionEnd 計算本 session 差異。 |
| `.asp-session-notes.tmp`（gitignored） | `make journal-note NOTE="…"` 追加的人工 note（每行一條），SessionEnd 收斂進條目。 |
| `.asp-session-journal.jsonl`（gitignored, append-only） | 歷史條目；SessionStart 讀 tail-N。 |
| git、`.asp-gate-log/`、`.asp-test-result.json` | SessionEnd 計算 commits / files / gates / test_status。 |

---

## 📤 輸出規格（Expected Output）

**`.asp-session-journal.jsonl` 單筆條目（一行 JSON）**：
```json
{"ts":"2026-07-14T06:00:00Z","branch":"feat/x","head_before":"abc123","head_after":"def456","commits":["fix: y"],"files_changed_count":3,"gates":[],"test_status":"passed","notes":["發現 X 套件的 Y 陷阱"]}
```

**SessionStart stdout（`## ASP Session Audit` 之內）新增**：
- `### 📓 最近 Session 經驗`：最後 N=3 筆的可讀單行摘要。
- 當 `source == "compact"`：`### ⚠️ Post-Compaction 存活包`：義務速查鏡射 + 當前 draft/firm ADR + autopilot task + 最近 1 條 note。

---

## 🔗 副作用與連動（Side Effects）

- `session-audit.sh`：SessionStart 依 source 條件寫 `.asp-session-marker.json`（見邊界）。
- `session-end-journal.sh`：append journal、刪除 marker 與 notes.tmp。**輸出/exit code 被 Claude Code 忽略（官方確認）→ 純副作用**。
- Iron Rule A 保護清單（`session-audit.sh` L57）新增 `session-end-journal.sh`。
- `.gitignore` 新增 `.asp-session-journal.jsonl`、`.asp-session-marker.json`、`.asp-session-notes.tmp`。

---

## ⚠️ 邊界條件（Edge Cases）

| 情境 | 預期行為 |
|------|----------|
| SessionStart 無 stdin（測試/某些呼叫） | `source` 視為空，不當 compact；**不得 hang**（用 `timeout` 讀 stdin）。 |
| `source == compact` / `clear` | 視為 session 續接，**不覆寫既有 marker**（避免只捕捉半段）。 |
| marker 不存在（首次/前次崩潰） | SessionEnd 用 `head_after` 當基準、commits=[]；仍記 notes/test_status。 |
| 本 session 無 commit、無 note、test 未跑 | SessionEnd **不寫空條目**（避免噪音）。 |
| 非 git 專案 | commits/files 相關欄位給空值，不報錯。 |
| journal 過大 | tail-N 只讀尾端；rotate 由後續 tech-debt 處理（本 SPEC 不實作 rotate，只保證讀取只碰尾端）。 |
| jq 不存在 | 比照 session-audit：印警告、exit 0，不阻擋。 |

### 🔄 Rollback Plan
移除 `settings.json` 的 SessionEnd hook + 還原 `session-audit.sh` 增段 + 刪 `session-end-journal.sh`／2 個 Makefile target／gitignore 三行／Iron Rule A 清單一項。Feature B 可獨立回退（只還原 source 解析與 compact 區塊），不影響 Feature A。

---

## 🧪 測試矩陣（Test Matrix）

| 編號 | 場景 | 預期 |
|------|------|------|
| A-P1 | SessionEnd：marker 有、期間有 commit | journal append 一行，含 commits / head_before/after |
| A-P2 | `journal-note` 後 SessionEnd | 條目 `notes[]` 含該 note；notes.tmp 被清 |
| A-P3 | SessionStart：journal 有 ≥1 筆 | stdout 出現 `📓 最近 Session 經驗` 且含最後一筆 |
| A-N1 | SessionEnd：無 commit/note/test | **不** append（無空條目噪音） |
| A-N2 | SessionEnd：marker 不存在 | 不報錯；若有 note 仍寫、commits=[] |
| B-P1 | SessionStart `source=compact` | stdout 出現 `⚠️ Post-Compaction 存活包` |
| B-N1 | SessionStart `source=startup` | **不**輸出存活包 |
| B-N2 | SessionStart 無 stdin | 不 hang、不輸出存活包、其餘審計照常 |
| I-1 | Iron Rule A 覆蓋 | `session-end-journal.sh` 在保護清單內（`test_iron_rule_a_coverage.sh` 擴充） |

---

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Scenario: 跨 session 經驗被帶回
  Given 上個 session 有 1 個 commit 且執行了 make journal-note NOTE="踩到 X"
  When SessionEnd 觸發、隨後重開 session
  Then .asp-session-journal.jsonl 多一行含 "踩到 X"
  And 新 session 的 ## ASP Session Audit 出現 "📓 最近 Session 經驗" 且包含 "踩到 X"

Scenario: compact 後動態狀態被重注入
  Given 專案有一個 Accepted ADR 與 briefing 狀態
  When SessionStart 以 source=compact 觸發
  Then stdout 出現 "⚠️ Post-Compaction 存活包" 含義務速查與當前 ADR 狀態
  But 以 source=startup 觸發時不出現該區塊
```

---

## ✅ 驗收標準（Done When）

- [ ] 測試矩陣全綠（`make test` 涵蓋新測試 `tests/test_session_journal.sh`、`tests/test_session_audit_compact.sh`）
- [ ] SessionEnd hook 為純副作用、恆 exit 0、無 stdin 時不 hang
- [ ] 讀回閉環成立（A-P3 手動 E2E 亦通過）
- [ ] Feature B 只在 `source=compact` 觸發
- [ ] `make audit-health` 通過；Iron Rule A/B、briefing、dynamic deny 不破
- [ ] 文件同步：CLAUDE.md hook 清單 + GLOSSARY（如需）+ Iron Rule A 清單

---

## 🚫 禁止事項（Out of Scope）

- 語意/向量檢索、embedding、DB、MCP、Docker、外部 API。
- 自動生成或注入「決策」記憶（日誌僅 observations；決策走 ADR）。
- user-global 安裝。
- journal rotate/壓縮（留待後續 tech-debt，本 SPEC 只保證讀取只碰尾端）。

---

## 📎 參考資料（References）

- ADR-026（決策）、ADR-020（AI 遺忘 / 機械強制）、ADR-011（settings.local.json 隔離）
- `.asp/hooks/session-audit.sh`（§8.6/§9 邊界 L391-393、§11 stdout L484-508、Iron Rule A L57）
- `.asp/Makefile.inc` L425-432（`session-checkpoint`，讀回閉環的另一半）
- 官方 `code.claude.com/docs/en/hooks`（SessionEnd 輸出被忽略、SessionStart stdout 注入、hook source）
