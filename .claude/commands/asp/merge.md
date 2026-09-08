---
description: 安全合併當前分支（智能判斷 PR 流程或本地 --no-ff；依 ASP 鐵則，破壞性動作前停下等人類確認）
argument-hint: [目標分支，預設 main]
---

把當前分支合併進 `$ARGUMENTS`（未指定時預設 `main`）。**你不自行決定要不要合**——實際的 merge / push 是 ASP 鐵則的人類確認範疇，你只負責把前置查驗做完、把選項與風險講清楚，停在最後一步等使用者明確同意。

## 合規前提（不可違反）

ASP 鐵則：`git push`（**任何**遠端分支）、`--force` / `--force-with-lease`、`rebase`、`gh pr merge`、`git reset --hard`、`git branch -D`、`git clean -f` 在執行前一律**先列出變更清單、等人類回覆一句明確授權**。本指令全程不得自動執行這些。

> **[2026-09-08 更正]** 本節原寫「`git push origin feature/*` 或 `asp/*` 可走（auto-PR 範疇）」，
> 與家目錄 `~/.claude/CLAUDE.md` 鐵則表（`git push` 無限定詞）及 asp-ng `skills/asp-merge/SKILL.md`
> §四（「`git push`(任何遠端分支)」）**兩處都相反**——同一條政策三側兩套，以嚴格側收斂。
>
> **機械層只覆蓋其中一部分**：`.asp/checks/git-guard.sh` 第十類擋的是強制推送、刪除遠端分支、
> 直推預設分支；`git push origin asp/foo` 這種**一般推送是放行的**（刻意，見 SPEC-016 B10：
> 擋掉每天做幾十次的事只會逼人整條關掉護欄）。故本節是**散文層義務**，不靠 hook 兜底——
> 人的確認與那道機械攔截並行，互不取代。

## 步驟

1. **盤點現況**（先報告再動手，用繁中）：
   - 當前分支、目標分支（`$ARGUMENTS` 或 `main`）。
   - `git status --short`（工作樹是否乾淨）、相對目標的 ahead/behind、變更檔摘要（`git diff --stat <target>...HEAD`）。
   - 是否有 remote、是否裝 `gh`、當前分支是否已有對應 PR（`gh pr view` / `gh pr status`）。

2. **前置閘**（任一不過 → 提醒並停下，不硬推）：
   - 工作樹須乾淨（未提交變更先 commit；**純文件 / config 改動直接乾淨 commit**，大型碼改動可選跑 `/asp-ship` 機械自檢）。
   - 測試須新鮮通過（提示跑 `make test`）；**有實質邏輯的碼改動於 land 前跑 `/asp:review-work` 獨立複審**；ADR 影響須 Accepted/FIRM。

### land 政策（2026-08-19 校準）

前置閘的措辭出自下列政策原文。**逐字轉錄，不改寫**——先前本檔把「於 land 前跑」寫成
「建議…先」、把「純文件 / config」寫成「瑣碎 / 文件」，同一條政策在兩側強度不同、
且 `config` 整個掉了（2026-09-08 複審揪出）。

<!-- verbatim-source: ~/.claude/CLAUDE.md:82（2026-08-19 land 政策校準段） -->
<!-- verbatim-sha256: 205d2782dacb01043fe4e1e1da91f184bd1587d34377ec369c292c97475c2700 -->
<!-- verbatim-begin -->
> **提交 / land 框架**（2026-08-19 校準）：land 一律走 `/asp:merge`；有實質邏輯的碼改動於 land 前跑 `/asp:review-work` 獨立複審；純文件 / config 改動直接乾淨 commit + `/asp:merge`。`/asp-ship` 已降為大型碼改動的選用自檢，**不再是「凡提交必跑」的前置**。
<!-- verbatim-end -->

雜湊與 asp-ng `skills/asp-merge/SKILL.md` 記錄值相同（`205d2782…`），2026-09-08 實測
三方一致：本檔轉錄段 = asp-ng 轉錄段 = `~/.claude/CLAUDE.md:82` 原文，逐字零差異。
重算方式：

```bash
awk '/^<!-- verbatim-begin -->$/{f=1;next} /^<!-- verbatim-end -->$/{f=0} f' \
  .claude/commands/asp/merge.md | sed -e '1{/^$/d}' -e '${/^$/d}' | sha256sum
```

3. **智能選路**（依步驟 1 的事實自動判斷，並向使用者說明選了哪條、為何）：

   **A. 有 remote + 有 `gh` → PR 流程（偏好）**
   - 當前分支未 push → **列出將推送的 commit 與目標分支，等使用者明確授權後**才 `git push origin <branch>`（含 `feature/*`、`asp/*`——見「合規前提」的 2026-09-08 更正）。
   - 無 PR → 用 `gh pr create` 起草（標題/內文交使用者確認後再建）。
   - 有 PR → 摘要 PR 狀態（CI、review、mergeable）。
   - **`gh pr merge` 是鐵則人類確認動作**，停在此處等使用者下令（AI 不自行執行 `gh pr merge`，含 `--auto`）。**提醒 stacked-PR 陷阱**：base 分支未刪時後續 PR 會合進該 base 而非 main——`--delete-branch` 可防。

     > **[2026-09-08 更正：auto-merge 的前提在本 repo 不成立]** 本項原寫「若 repo 已設
     > branch protection + auto-merge（**ASP 預設**）→ 建議 arm auto-merge」。**分支保護在
     > GitHub free 方案不存在**（2026-08-26 實查：分支保護與 rulesets 皆付費、私有 repo 拿不到；
     > 記於 `~/.claude/CLAUDE.md` 鐵則表與 `docs/specs/SPEC-016-*.md`）。本 repo
     > （`astroicers/AI-SOP-Protocol`）即 free 私有 repo，故：
     >
     > - 「ASP 預設」這個標示是錯的——那從來不是預設，是拿不到的東西。
     > - `--auto` 在**無 required check** 的 repo 上不會等任何東西，**等同立即合併**，
     >   卻讀起來像「CI 綠才合」。這比不用 auto-merge 更危險。
     >
     > **故本 repo 一律不建議 `--auto`**：`gh pr merge` 由人親手執行，AI 只列指令。
     > 日後若升付費方案並實際設定分支保護，再回頭放寬本項並更新此註記。

   **B. 純本地 / 無 remote → 本地 `--no-ff` 合併**
   - `git checkout <target> && git pull --ff-only`（有 remote 時）。
   - `git merge --no-ff <branch>`；**衝突 → 停下，列出衝突檔，交人類處理，不自行 resolve**。
   - 合併後提示是否刪除已併分支（`git branch -d <branch>`，未完全合併用 `-d` 會擋，不用 `-D` 強刪除非使用者明確要求）。

4. **不自動執行最後的破壞性步驟**。把「下一步要打的指令」明確列給使用者，等其確認後才執行；執行完回報結果（合併 commit、刪除的分支、PR 連結）。
