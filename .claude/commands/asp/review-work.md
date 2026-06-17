---
description: 派獨立 read-only subagent 客觀回顧整個 session 或某段修復過程（未指定範圍時自動判斷 session/fix）
argument-hint: [session|fix（可省略，省略則依 context 自動判斷）]
---

派**一個全新、獨立 context 的 read-only subagent** 做客觀回顧。你（主 agent）**不要自己回顧**——這個指令的價值就在於借一個沒有當事人偏誤的新 context 來檢視。

## 範圍判定（先做這步，再派 subagent）

- `$ARGUMENTS` 為 `session` 或 `fix` → **照字面用，不要再推斷**。
- `$ARGUMENTS` 為空 → **依本次對話 context 自動判斷**（規則見下表），並在彙整最開頭一句話說明：「未指定範圍，自動判定為 **X**，因為 …；要改範圍請執行 `/asp:review-work {另一個}`」（仿 `merge.md` 智能選路的透明化）。

### 推斷規則（未指定時）

先快速盤點訊號：跑 `git status -s` 與 `git diff --stat`（必要時 `git log --oneline <主分支>..HEAD`），再回看本次對話的聚焦點，對照下表：

| 訊號 | 判定 | 理由 |
|------|------|------|
| 本次對話／分支聚焦單一 bug 修復或單一 PR、改動集中、有清楚 root-cause 線索 | `fix` | 聚焦修復品質（治標 vs 治本、回歸、同類 grep） |
| 涵蓋計劃→實作→測試的混合工作、含 ADR/SPEC/探索、或多個不相干任務 | `session` | 需全週期 + ASP 鐵則／過程義務檢視 |
| 訊號不明確／兩者皆有／無明確修改標的 | `session`（保守預設） | 寧可全景檢視，不漏掉鐵則違反 |

本次範圍：**$ARGUMENTS**（為空時填入上面自動判定的結果）

## 若範圍為 `session`

派一個 `reality-checker` subagent（預設懷疑、唯讀），回顧**整個本次對話 / session**：

- 做了哪些工作、決策鏈是否合理、有無偷工或未完成項。
- 是否符合 ASP 鐵則與過程義務：commit 前跑測試 / asp-ship、實作前 ADR 須 Accepted/FIRM、bug 修復後**全專案 grep** 同類問題、外部事實查證並記錄 `.asp-fact-check.md`、假設未明先 Assumption Checkpoint。
- 列出風險、遺漏、未驗證的宣稱，依嚴重度排序。

## 若範圍為 `fix`

派一個 `Code Reviewer`（或 `superpowers:code-reviewer`）subagent，回顧**某段修復 / PR 過程**：

- root cause vs workaround——是否只治標。
- 是否**全專案 grep** 過同類問題（同型 bug 是否還潛伏他處）。
- 測試是否真的涵蓋該 bug、回歸風險。
- 文件 / ADR / CHANGELOG 是否同步。

## 鐵則（不可違反）

- subagent **必須 read-only**，不得寫入任何檔案。（曾有對抗式 agent 拿到寫入權竄改真實檔——例如把 ADR 從 Draft 偷改成 Accepted。）
- subagent 跑完後，你**必須**自己跑一次 `git diff --stat`（必要時加 `git status`）確認真實檔未被動到，再彙整結論。
- 用繁體中文彙整：先給總評，再逐條列 finding（嚴重度 + 位置 + 具體建議）。