---
description: 人類看完並同意後，執行把指定 ADR 升 Accepted 的機械步驟（AI 不自行判斷是否同意）
argument-hint: [ADR 編號，如 020 或 ADR-020]
---

把 `$ARGUMENTS` 指定的 ADR 升級為 `Accepted`。

## 合規前提（不可違反）

ASP 鐵則：**AI 不可自行升級 ADR 狀態，只能人類變更**。本指令的觸發者就是使用者本人——使用者「看完並同意」後才呼叫 `/asp:approve-adr`，因此你只負責**落實機械步驟**，不替使用者判斷該不該同意、不做架構決策。

## 步驟

1. 在 `docs/adr/` 找出編號為 `$ARGUMENTS` 的 ADR 檔（支援 `020`、`ADR-020`、完整檔名）。讀取它。
2. **先摘要、再動手**：用繁中向使用者報告——該 ADR 的決策重點、目前 `狀態`（Draft / FIRM / Accepted）、Verification Evidence 的**具體狀態**（引用實際勾選／測試結果行，不要只說「全綠」帶過）。
   - 若已是 `Accepted`：告知無需動作，停止。
   - 若仍是 `Draft`：提醒「Draft 直升 Accepted 會跳過 FIRM 的 POC 驗證」，然後**停在此處、等待使用者明確表達同意直升（如「確認直升」「直接升」等）後才進入步驟 3，不可自行推進**。（Draft 直升風險高於 FIRM→Accepted，故即使使用者已呼叫本指令，仍需這道二次確認。）
3. **升級（自適應該 ADR 既有格式，不新增欄位）**。先用 `date +%Y-%m-%d` 取得今天日期，然後：
   - 把狀態欄 `| **狀態** | `<舊狀態>` |` 改為 `| **狀態** | `Accepted` |`。
   - 沿用該 ADR 既有的**升級記錄 blockquote 慣例**追加一條（不是新增欄位）。**措辭要可稽核**：標注觸發指令，並帶上本次同意**升級當下實際看到的**依據（本指令呈現的摘要 + Verification Evidence）。⚠️ 同意依據只能是升級當下已存在的證據，**不可納入升級後才產生的 review／reality-check**（否則時序倒置、自我背書）。不要寫「看完 review」這種無法回溯的套話：

     ```
     > ⬆️ 由 `<舊狀態>` 升 `Accepted`：使用者 <今天日期> 透過 `/asp:approve-adr <編號>` 呼叫、看完本指令摘要的決策與 Verification Evidence 後明確同意（人類顯式授權，非 AI 自行升級，符合 ADR 狀態變更鐵則）。
     ```
   - 若檔頭有 `<!-- ... Status: ... -->` HTML 註解 → 同步把 `Status:` 改 `Accepted`；若沒有（如 ADR-020）→ 略過。
   - 若該 ADR 有「採納日期」欄位 → 更新為今天；沒有 → 不強加。
4. 提示使用者：跑 `make asp-refresh` 重新審計，清掉 session-audit A3.2 對該 ADR（升級前 FIRM 狀態殘留）的 🟡 黃旗。
5. **不要自動 commit**——commit 走 `/asp-ship`，且屬人類確認範疇。**但要主動提醒使用者**：此時工作樹與 HEAD 不一致（HEAD 仍是舊狀態），升級尚未持久化，請盡快走 `/asp-ship` + commit，否則升級可能因後續 git 操作（checkout / stash / reset）被丟棄。最後回報這次改了哪些欄位即可。
