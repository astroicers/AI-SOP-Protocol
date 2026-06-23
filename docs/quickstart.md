# ⚡ ASP 5 分鐘快速體驗

> **這頁是第一次用 ASP 時「線性照抄」的體驗劇本**——跟著走一遍，親眼看到護欄擋下一次該被擋的 commit。
> 裝完後各種情境該下什麼指令 → [where-to-start.md](where-to-start.md)；安裝細節與功能概覽 → [README.md](../README.md)；術語不熟 → [GLOSSARY.md](../GLOSSARY.md)。

ASP 的核心承諾是「AI 在沒人盯著時也守紀律」。與其先讀十頁治理文件，不如花 5 分鐘看它擋你一次。

---

## 0. 前提

- 已裝 [Claude Code](https://docs.anthropic.com/claude-code)（ASP 的執行環境）。
- macOS 請先 `brew install bash`（系統內建 bash 3.2 不符）。

## 1. 裝 ASP 核心（每台電腦一次）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.sh)
```

裝完 `~/.claude/asp/`（hooks/profiles）與 `~/.claude/skills/asp/`（skills）即可用於所有專案。

## 2. 開一個 loose 等級的 demo 專案

```bash
mkdir asp-demo && cd asp-demo && git init
ASP_TYPE=system ASP_LEVEL=loose bash ~/.claude/asp/scripts/install.sh
```

非互動安裝會建立 `.ai_profile`（`type: system` / `level: loose`）、精簡版 `CLAUDE.md`、`.claude/settings.json`（hooks）。
`loose` 是最小治理等級——沒有 G1-G6 重 gate，但鐵則與 commit 閘仍在。

```bash
cat .ai_profile   # 確認 type: system / level: loose
```

## 3. 故意製造一次「該被擋的」commit

在這個 demo 專案裡開一個 Claude Code session，做一點改動並先 stage：

```bash
echo "print('hi')" > app.py
git add app.py
```

接著在 session 裡跟 Claude 說「幫我 git commit」。你會看到 commit 被擋下，理由類似：

> ASP commit 閘：commit 前未見新鮮測試痕跡（.asp-test-result.json）。請先跑 /asp-ship 或 make test 再 commit；若確認要跳過，用 ASP_SHIP_OK=1 git commit ...（會留 bypass 遙測）。

> **誠實邊界**：這個閘是 Claude Code 的 PreToolUse hook，攔的是 session 內 Claude 發出的 `git commit`。你自己在終端機直接打 `git commit` 不會經過它——要在 session 內請 Claude commit 才看得到擋。

這就是 ASP 的 L1.5 機械護欄（ADR-020）：沒有新鮮測試痕跡，commit 不放行。

## 4. 正規放行——跑 `/asp ship`

在 session 裡執行 `/asp ship`。它跑完 10 步 pre-commit 檢查後，會寫下「測試通過」痕跡（`.asp-test-result.json`，`passed: true`），同一個 commit 就會放行。

> ⚠️ **注意**：單獨跑 `make test` **不會**寫這個痕跡（它只跑測試、回傳結果）。清掉 commit 閘要用 `/asp ship`。

## 5.（可選）看一眼逃生口

趕時間、確認要跳過時：

```bash
ASP_SHIP_OK=1 git commit -m "demo: skip gate once"
```

放行，但會留下一筆 bypass 遙測——逃生口存在，但不是免費的。

---

## 你剛剛看到的三件事

| 機制 | 你看到什麼 | 出處 |
|------|-----------|------|
| commit 閘（L1.5） | 沒測試痕跡 → commit 被擋 | `pretooluse-ship-gate.sh`（ADR-020） |
| 測試痕跡 | `/asp ship` 寫 `.asp-test-result.json` 才放行 | `asp-ship` Step 10 |
| 逃生口 | `ASP_SHIP_OK=1` 放行但留遙測 | fail-open 防死鎖 |

接下來想做真正的功能？→ [where-to-start.md](where-to-start.md) 有「新功能 / Bug 修復 / Autopilot」各情境的指令劇本。
