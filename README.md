# AI-SOP-Protocol (ASP)

把開發規範寫成機器可讀的約束，讓 Claude 自動遵守——不用每次提醒「記得寫測試」「先建 ADR」「不要亂推版」。

**v4.2.0** · [CHANGELOG](CHANGELOG.md) · [架構文件](docs/architecture.md) · [入門指引](docs/where-to-start.md)

---

## 它解決什麼問題

你每次開新 session，Claude 都忘記你的開發規範。ASP 把規範固化成 hooks + profiles + skills，session 啟動時自動載入，無需重複交代。

| 沒有 ASP | 有 ASP |
|---------|-------|
| 每次提醒「先寫測試」 | G3 Gate 強制：測試先 FAIL 才能實作 |
| ADR 說好不實作，AI 還是動了 | Draft ADR → `git commit` 動態阻擋 |
| 推版前忘記掃密碼 | `/asp-ship` 10 步驟含敏感資訊掃描 |
| 不知道 AI 改了什麼範圍 | SPEC Done When 是二元驗收條件 |

---

## 安裝

ASP 分兩層：**User-level**（所有專案共用，裝一次）和 **Project-level**（每個專案的設定，輕量）。

### Step 1 — User-level 核心（每台電腦一次）

**macOS / Linux / WSL2**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.sh)
```

> macOS：系統預設 bash 3.2 不符，請先 `brew install bash`。

**Windows（PowerShell）**
```powershell
irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.ps1 | iex
```

> 需要 Git for Windows、Python 3.10+、jq 1.6+。詳見 [docs/install-windows.md](docs/install-windows.md)。

安裝後：`~/.claude/asp/`（profiles/hooks）和 `~/.claude/skills/asp/`（24 個 skills）即可用於所有專案。

### Step 2 — Project-level 設定（每個專案一次，在專案根目錄執行）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.sh)
```

同一支腳本，第二次在**專案目錄**跑時，會偵測已有 user-level 並只執行 Phase 2：建立 `.ai_profile`、`CLAUDE.md`、`.claude/settings.json`（hooks 設定）。

安裝腳本會問兩題：**專案類型**（system / content / architecture）→ **成熟度等級（loose / standard / autonomous，v5 三級制）**。全按 Enter 用預設值。

---

## 啟動

```bash
# 在 Claude Code session 開始時貼這一行：
# 「請讀取 CLAUDE.md，依照 .ai_profile 載入對應 Profile，後續遵循 ASP 協議。」
```

AI 回覆會列出已載入的 Profile 名稱，和當前 session 的 BLOCKER / WARNING。

---

## 預設行為（AI 自動執行，不用記）

| 時機 | AI 做的事 |
|------|---------|
| Session 啟動 | 讀 `.asp-session-briefing.json`，報告 BLOCKER；回報 Task Inbox 待授權任務（held，不自動注入；ADR-012/SPEC-007） |
| 跨模組變更 | 先建 ADR；`Draft` 狀態下 `git commit` 被動態阻擋 |
| 寫測試前 | `/asp-gate G1,G2`；寫完跑 G3；實作完跑 G4 |
| Commit 前 | `/asp-ship` 十步驟（測試、文件、敏感資訊掃描） |
| Autopilot 完成 | 自動建 `asp/TASK-*` branch + Draft PR，等待人工 merge |
| 第三方 API / 版本 | 查證並記錄至 `.asp-fact-check.md`（global_core.md 自動觸發） |
| 發布版本 | `/asp-release`：自動判斷 semver bump、更新 CHANGELOG、建 Draft Release PR |

---

## 專案設定（.ai_profile）

安裝自動建立，要改行為時編輯它，**開新 session 生效**。

```yaml
type: system        # system | content | architecture
level: loose        # loose | standard | autonomous（v5；遺留 0-5 自動映射）
mode: auto          # auto（推薦） | single | multi-agent
hitl: standard      # minimal | standard | strict
autopilot: disabled # enabled 時讀 ROADMAP.yaml 自動執行
```

完整欄位：`~/.claude/asp/templates/example-profile-full.yaml`

---

## 常用指令

```bash
make adr-new TITLE="..."      # 新增架構決策記錄（ADR）
make spec-new TITLE="..."     # 新增功能規格（SPEC）
make audit-health             # 9 維度健康審計
make audit-quick              # 只看 blocker（快速）
make daily-audit              # 產生每日健康日報 .asp-daily-report.md
make ci-install               # 複製 GitHub Actions CI 模板至 .github/workflows/
make asp-unlock-commit        # 解除 Draft ADR 動態 commit 阻擋
make asp-update               # 更新 ASP 核心到最新版
make help                     # 顯示全部指令
```

不確定該下什麼指令？→ [docs/where-to-start.md](docs/where-to-start.md)（場景決策樹）

> 專案沒有 `make`：直接請 Claude 執行 `/asp-audit`，自動 fallback 到 `~/.claude/asp/scripts/audit-fallback.sh`。

---

## ADR 狀態機

ASP 用三個狀態管理架構決策的生命週期：

| 狀態 | 誰可設定 | 允許行為 |
|------|---------|---------|
| `Draft` | AI 建立時自動設定 | 禁止生產代碼；`git commit` 動態阻擋 |
| `FIRM` | 人類（需填 Verification Evidence） | 允許 commit；`audit-health` 輸出 🟡 |
| `Accepted` | 人類 | 完全放行 |

---

## 鐵則（不可被任何設定覆蓋）

- `git push origin main / --force / rebase / rm -rf / docker push / gh pr merge` 必須人類確認；`feature/* 或 asp/*` 由 autopilot 自動推送
- 禁止輸出 API Key / 密碼 / 憑證
- ADR `Draft` 狀態下禁止實作（commit 動態阻擋）
- 涉及第三方 API / 版本 / 法規 → 必須查證，記錄至 `.asp-fact-check.md`

完整 7 條：[CLAUDE.md](CLAUDE.md)

---

## 更新 ASP

### 這台電腦（有 repo）

```bash
cd ~/AI-SOP-Protocol
git pull
make asp-update
```

### 其他電腦（全新安裝）

重新執行 Step 1 安裝指令，腳本自動覆蓋舊版並 clone repo 到 `~/AI-SOP-Protocol/`。

| 內容 | 更新時 |
|------|--------|
| `~/.claude/asp/`、`~/.claude/skills/asp/` | ✅ 覆蓋 |
| `~/.claude/CLAUDE.md`（ASP 版本） | ✅ 更新 |
| `.ai_profile`、`docs/adr/`、`docs/specs/` | ❌ 不動 |

---

## 深入了解

| 主題 | 位置 |
|------|------|
| 不確定下什麼指令（場景決策樹） | [docs/where-to-start.md](docs/where-to-start.md) |
| MVP / 大型功能 / 事故應急 | [docs/runbooks/](docs/runbooks/) |
|  成熟度等級（v5 三級制） | `~/.claude/asp/levels/{loose,standard,autonomous}.yaml` |
| Multi-Agent worktree 隔離 | [docs/specs/SPEC-004-multi-agent-worktree-isolation.md](docs/specs/SPEC-004-multi-agent-worktree-isolation.md) |
| Autopilot（ROADMAP 驅動） | [docs/autopilot.md](docs/autopilot.md) |
| 架構總覽（含序列圖） | [docs/architecture.md](docs/architecture.md) |
| Task Inbox schema | [.asp/templates/task-inbox-schema.json](.asp/templates/task-inbox-schema.json) |
| CI 模板設定 | [.asp/templates/cron-setup.md](.asp/templates/cron-setup.md) |

---

## 移除

```bash
# macOS / Linux — 當前專案
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.sh)
# macOS / Linux — user-level
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.sh) --user-level

# Windows
irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.ps1 | iex
$env:ASP_USER_LEVEL='1'; irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.ps1 | iex
```

移除保留 `.ai_profile`、`docs/adr/`、`docs/specs/` 等你自己撰寫的內容。
