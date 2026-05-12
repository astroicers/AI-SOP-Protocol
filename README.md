# AI-SOP-Protocol (ASP)

> 把開發文化寫成機器可讀的約束，讓 AI 自動遵守。
> 不用每次提醒 AI「記得寫測試」「不要亂推版」「更新文件」。

**v4.1.1**（2026-05-10）｜ 詳見 [CHANGELOG](CHANGELOG.md)

---

## 一句話：ASP 是什麼

ASP 規範**怎麼做**——ADR 先於實作、測試先於代碼、部署必須確認、文件同步更新。
ASP **不管你做什麼**（產品方向、功能優先序、時程規劃自己決定）。

> 你決定蓋什麼房子，ASP 確保施工流程不出錯。

---

## 安裝（依你的作業系統挑一條）

### macOS / Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.sh)
```

### Windows — PowerShell + Git Bash

```powershell
irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.ps1 | iex
```

> 需要 [Git for Windows](https://git-scm.com/download/win)（提供 bash.exe）、Python 3.10+、jq 1.6+。

### Windows — WSL2（推薦）

進入 WSL 後執行上方 macOS/Linux 指令即可。

> 📖 Windows 完整指引（前置、驗證、移除、FAQ）：[`docs/install-windows.md`](docs/install-windows.md)

---

## 三步啟動

```bash
# 1. 安裝（一次安裝 user-level，每個專案再跑一次建立輕量設定）
bash <(curl -fsSL .../install.sh)   # 或 PowerShell 版本

# 2. 進入 Claude Code，貼一行：
#    「請讀取 CLAUDE.md，依照 .ai_profile 載入對應 Profile，後續遵循 ASP 協議。」

# 3. 確認 AI 回覆中提到已載入 Profile 名稱
```

安裝會問兩題：**專案類型** → **成熟度等級（L1–L5）**。全按 Enter 用預設值。

---

## 預設行為（不用記，AI 會自動執行）

| 時機 | AI 做的事 |
|------|---------|
| Commit 前 | `/asp-ship` 十步檢查（測試、文件、敏感資訊） |
| 跨模組變更 | 先建 ADR；Draft 狀態下 `git commit` 被動態阻擋 |
| 寫測試前 | `/asp-gate G1,G2`；寫完跑 G3；實作完跑 G4 |
| 第三方 API / 版本 | `/asp-fact-verify` 記錄至 `.asp-fact-check.md` |
| Session 啟動 | 自動讀 `.asp-session-briefing.json`，報告 BLOCKER |

---

## .ai_profile 最小範例

安裝會自動建立。要改行為時改這個檔，**開新 session 生效**。

```yaml
type: system        # system | content | architecture
level: 1            # L0 Spike | L1 Starter | L2 Disciplined | L3 Test-First | L4 Collaborative | L5 Autonomous
mode: auto          # auto（推薦） | single | multi-agent
hitl: standard      # minimal | standard | strict
autopilot: disabled # enabled 時讀 ROADMAP.yaml 零確認執行
```

完整欄位：`~/.claude/asp/templates/example-profile-full.yaml`

---

## 常用指令

```bash
make adr-new TITLE="..."      # 新增 ADR（架構決策）
make spec-new TITLE="..."     # 新增 SPEC（功能規格）
make test                     # 跑測試
make audit-health             # 9 維度健康審計
make audit-quick              # 只看 blocker
make asp-unlock-commit        # 解除 Draft ADR 動態 commit deny
make help                     # 顯示全部
```

---

## 鐵則（不可被任何 profile 覆蓋）

- 破壞性操作（`git push / rebase / rm -rf / docker push`）必須人類確認
- 禁止輸出 API Key / 密碼 / 憑證
- ADR Draft 狀態下禁止實作（commit 動態阻擋）
- 第三方事實（API / 版本 / 法規）必須 `asp-fact-verify`

詳全部 7 條：[`CLAUDE.md`](CLAUDE.md)。

---

## 想深入了解

| 主題 | 文件 |
|------|------|
| 不確定該下哪個指令 | [`docs/where-to-start.md`](docs/where-to-start.md) |
| 從零建 MVP / 大型功能 / 事故應急 | [`docs/runbooks/`](docs/runbooks/) |
| 成熟度等級（L0–L5） | `~/.claude/asp/levels/level-N.yaml` |
| Multi-Agent worktree 隔離（v4.1 GA） | [`docs/specs/SPEC-004-multi-agent-worktree-isolation.md`](docs/specs/SPEC-004-multi-agent-worktree-isolation.md) |
| Autopilot（ROADMAP 驅動） | [`docs/autopilot.md`](docs/autopilot.md) |
| 架構總覽（含序列圖） | [`docs/architecture.md`](docs/architecture.md) |
| 完整 Profile schema | `~/.claude/asp/templates/example-profile-full.yaml` |

---

## 移除

```bash
# macOS / Linux
bash <(curl -fsSL .../uninstall.sh)            # 當前專案
bash <(curl -fsSL .../uninstall.sh) --user-level  # user-level

# Windows
irm .../uninstall.ps1 | iex
$env:ASP_USER_LEVEL='1'; irm .../uninstall.ps1 | iex
```

保留 `.ai_profile`、`docs/adr/`、`docs/specs/` 等使用者撰寫的內容。
