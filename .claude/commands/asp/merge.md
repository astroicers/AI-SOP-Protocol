---
description: 安全合併當前分支（智能判斷 PR 流程或本地 --no-ff；依 ASP 鐵則，破壞性動作前停下等人類確認）
argument-hint: [目標分支，預設 main]
---

把當前分支合併進 `$ARGUMENTS`（未指定時預設 `main`）。**你不自行決定要不要合**——實際的 merge / push 是 ASP 鐵則的人類確認範疇，你只負責把前置查驗做完、把選項與風險講清楚，停在最後一步等使用者明確同意。

## 合規前提（不可違反）

ASP 鐵則：`git push origin main`、`--force`、`rebase`、`gh pr merge` **必須人類確認**。本指令全程不得自動執行這些；`git push origin feature/*` 或 `asp/*` 可走（auto-PR 範疇）。

## 步驟

1. **盤點現況**（先報告再動手，用繁中）：
   - 當前分支、目標分支（`$ARGUMENTS` 或 `main`）。
   - `git status --short`（工作樹是否乾淨）、相對目標的 ahead/behind、變更檔摘要（`git diff --stat <target>...HEAD`）。
   - 是否有 remote、是否裝 `gh`、當前分支是否已有對應 PR（`gh pr view` / `gh pr status`）。

2. **前置閘**（任一不過 → 提醒並停下，不硬推）：
   - 工作樹須乾淨（未提交變更先 commit，commit 走 `/asp-ship`）。
   - 測試須新鮮通過（提示跑 `make test` / `/asp-ship`）；ADR 影響須 Accepted/FIRM。

3. **智能選路**（依步驟 1 的事實自動判斷，並向使用者說明選了哪條、為何）：

   **A. 有 remote + 有 `gh` → PR 流程（偏好）**
   - 當前分支未 push → `git push origin <branch>`（feature/* 或 asp/* 可直接做）。
   - 無 PR → 用 `gh pr create` 起草（標題/內文交使用者確認後再建）。
   - 有 PR → 摘要 PR 狀態（CI、review、mergeable）。
   - **`gh pr merge` 是鐵則人類確認動作**：若 repo 已設 branch protection + auto-merge（ASP 預設），**建議 arm auto-merge**：`gh pr merge <#> --auto --squash --delete-branch`——CI 綠才自動合、合後自動刪分支，使用者一鍵即走、不必盯。未啟用 auto-merge 的 repo 才退回立即 `--merge`/`--squash`。**提醒 stacked-PR 陷阱**：base 分支未刪時後續 PR 會合進該 base 而非 main——`--delete-branch` 可防。停在此處等使用者下令（AI 不自行執行 `gh pr merge`，含 `--auto`）。

   **B. 純本地 / 無 remote → 本地 `--no-ff` 合併**
   - `git checkout <target> && git pull --ff-only`（有 remote 時）。
   - `git merge --no-ff <branch>`；**衝突 → 停下，列出衝突檔，交人類處理，不自行 resolve**。
   - 合併後提示是否刪除已併分支（`git branch -d <branch>`，未完全合併用 `-d` 會擋，不用 `-D` 強刪除非使用者明確要求）。

4. **不自動執行最後的破壞性步驟**。把「下一步要打的指令」明確列給使用者，等其確認後才執行；執行完回報結果（合併 commit、刪除的分支、PR 連結）。
