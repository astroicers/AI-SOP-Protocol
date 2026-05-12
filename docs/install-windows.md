# Windows 安裝指南

ASP 在 Windows 上有兩條路：**WSL2（推薦）** 或 **原生 PowerShell + Git Bash**。
兩者底層都需要 bash，因為 Claude Code 的 SessionStart hook 是 `.sh` 腳本。

---

## 路線 A：WSL2（推薦，零差異體驗）

Windows 10/11 內建 WSL2。在 WSL 內 ASP 行為與 macOS/Linux 完全一致。

```powershell
# 1. 安裝 WSL2（PowerShell 系統管理員）
wsl --install
# 重啟，完成 Ubuntu 初始化（建立帳號密碼）

# 2. 進入 WSL，安裝相依
wsl
sudo apt update && sudo apt install -y git jq python3
```

```bash
# 3. 在 WSL 中跑標準 install.sh
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.sh)
```

**Claude Code 設定：** 在 Claude Code 開啟 WSL 路徑下的專案（`\\wsl$\Ubuntu\home\...`），hook 會自動透過 WSL 的 bash 執行。

---

## 路線 B：原生 PowerShell + Git Bash

如果不想用 WSL，可用 PowerShell 安裝、由 Git for Windows 內建的 `bash.exe` 執行 hook。

### 前置安裝

| 套件 | 版本 | 安裝 |
|------|------|------|
| Git for Windows | ≥ 2.20 | https://git-scm.com/download/win（內含 bash.exe） |
| Python | ≥ 3.10 | https://www.python.org/downloads/ |
| jq | ≥ 1.6 | `winget install jqlang.jq`（或 `choco install jq` / `scoop install jq`）|

### 安裝 ASP

```powershell
# 一次性 user-level + 當前專案安裝
irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.ps1 | iex
```

非互動式（CI / 預設 L2）：
```powershell
$env:ASP_TYPE='system'; $env:ASP_LEVEL='2'
irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.ps1 | iex
```

### 驗證

安裝後檢查：

```powershell
Test-Path "$HOME\.claude\asp\hooks\session-audit.sh"   # → True
Test-Path .\.ai_profile                                # → True
Get-Content .\.claude\settings.json | Select-String 'bash'  # 看到 bash 啟動 hook
```

### 移除

```powershell
# 當前專案
irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.ps1 | iex

# user-level（~/.claude/asp/）
$env:ASP_USER_LEVEL='1'
irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.ps1 | iex
```

---

## Windows 特定注意事項

1. **Hook 執行：** `.claude\settings.json` 的 hook command 會被寫成 `bash "C:/Users/<you>/.claude/asp/hooks/session-audit.sh"`。Git Bash 的 `bash.exe` 必須在 PATH 中。
2. **PowerShell 執行原則：** 若 `irm | iex` 被擋，先執行：
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```
3. **`make` 指令：** 多數 ASP 工作流用 `make`。Windows 原生沒有 make——透過 WSL 或安裝 `choco install make`。
4. **路徑分隔符：** ASP 內部腳本仍使用 forward slash 路徑（POSIX 風格），由 bash 解釋；PowerShell 端的 Windows 路徑會在寫入時自動轉換。

---

## 常見問題

**Q: hook 跑不起來，Claude Code 沒讀取 `.asp-session-briefing.json`？**
A: 開新 session 後在 Claude Code 執行 `where bash`（或 `Get-Command bash`），確認 `bash.exe` 在 PATH。若沒裝 Git for Windows，hook 無法執行。

**Q: 我要更新 ASP 到最新版？**
A: 兩種路線都用：
```bash
bash ~/.claude/scripts/asp-sync.sh
```
（PowerShell 也能執行此命令，前提是 Git Bash 在 PATH。）

**Q: WSL 和原生哪個快？**
A: WSL2 啟動 bash hook 較慢（每次 hook 約 +200ms），但執行 ASP 工具鏈（`make test` 等）會比較流暢。原生 + Git Bash 啟動快，但複雜的 multi-agent worktree 場景在 NTFS 上可能較慢。建議重度使用者選 WSL2。
