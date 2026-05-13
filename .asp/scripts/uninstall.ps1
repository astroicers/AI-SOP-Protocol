# AI-SOP-Protocol Windows Uninstaller (PowerShell)
#
# 用法：
#   irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.ps1 | iex
#
#   # 移除 user-level（~/.claude\ 內的 ASP 核心）
#   $env:ASP_USER_LEVEL='1'; irm .../uninstall.ps1 | iex
#
#   # 非互動（自動 Yes）
#   $env:ASP_AUTO_YES='1'; irm .../uninstall.ps1 | iex
#
#   # 預覽（不執行）
#   $env:ASP_DRY_RUN='1'; irm .../uninstall.ps1 | iex
#
# 保留：.ai_profile、docs/adr/、docs/specs/、.asp-bypass-log.ndjson、.asp-fact-check.md

[CmdletBinding()]
param(
    [switch]$UserLevel,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

if ($env:ASP_USER_LEVEL -eq '1') { $UserLevel = $true }
if ($env:ASP_DRY_RUN -eq '1')    { $DryRun = $true }
if ($env:ASP_AUTO_YES -eq '1')   { $Yes = $true }

function Write-Success { param([string]$Msg) Write-Host "  ✓ $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "  ⚠ $Msg" -ForegroundColor Yellow }
function Write-Info    { param([string]$Msg) Write-Host "  $Msg" }
function Write-Dry     { param([string]$Msg) Write-Host "  [DRY] 移除: $Msg" }

function Confirm-Action {
    param([string]$Prompt)
    if ($Yes) { return $true }
    if (-not [Environment]::UserInteractive) { return $true }
    $ans = Read-Host "  $Prompt [y/N]"
    return $ans -match '^[Yy]'
}

function Remove-Target {
    param([string]$Path, [string]$Desc)
    if (-not (Test-Path $Path)) { return }
    if ($DryRun) {
        Write-Dry "$Path$(if ($Desc) { " ($Desc)" })"
    } else {
        Remove-Item -Recurse -Force $Path
        Write-Success "移除: $Path$(if ($Desc) { " ($Desc)" })"
    }
}

# ─── 清理 .claude\settings.json 內的 ASP hooks（保留其他）───────────
function Clear-AspHooks {
    param([string]$File)
    if (-not (Test-Path $File)) { return }
    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Warn "無 jq，請手動移除 $File 內的 session-audit / clean-allow-list hooks"
        return
    }

    $before = (& jq -r '(.hooks.SessionStart // []) | length' $File 2>$null)
    $jqFilter = @'
      .hooks.SessionStart = [
        (.hooks.SessionStart // [])[] |
        select(
          (.hooks // []) |
          all(.command | test("(session-audit|clean-allow-list)") | not)
        )
      ] |
      if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end |
      if ((.hooks // {}) | length) == 0 then del(.hooks) else . end
'@
    & jq $jqFilter $File | Set-Content "$File.asp-tmp" -Encoding UTF8
    Move-Item -Force "$File.asp-tmp" $File
    $after = (& jq -r '(.hooks.SessionStart // []) | length' $File 2>$null)
    $removed = [int]$before - [int]$after
    if ($removed -gt 0) {
        Write-Success "清理 $File — 移除 $removed 個 ASP hooks（使用者 hooks 保留）"
    } else {
        Write-Info "$File 內無 ASP hooks，跳過"
    }
}

# ═══════════════════════════════════════════════════════════════════
# User-level 移除
# ═══════════════════════════════════════════════════════════════════
if ($UserLevel) {
    Write-Host ''
    Write-Host 'ASP User-level 移除' -ForegroundColor Red
    Write-Host '═══════════════════════════════'
    if ($DryRun) { Write-Host '  ── DRY RUN 模式（不實際執行）──' }
    Write-Host ''

    $UserClaude = Join-Path $HOME '.claude'
    Remove-Target (Join-Path $UserClaude 'skills\asp') 'ASP skills'
    Remove-Target (Join-Path $UserClaude 'asp') 'ASP profiles/hooks/templates'
    Remove-Target (Join-Path $UserClaude 'scripts\asp-sync.sh') 'ASP sync 腳本'

    $userClaudeMd = Join-Path $UserClaude 'CLAUDE.md'
    if ((Test-Path $userClaudeMd) -and (Select-String -Path $userClaudeMd -Pattern 'ASP User-level Rules|AI-SOP-Protocol' -Quiet)) {
        if ($DryRun) {
            Write-Dry "$userClaudeMd（ASP user-level 鐵則）"
        } elseif (Confirm-Action '移除 ~/.claude/CLAUDE.md（ASP user-level 鐵則）？') {
            Remove-Item -Force $userClaudeMd
            Write-Success '移除 ~/.claude/CLAUDE.md'
        }
    }

    Write-Host ''
    Write-Warn '各專案內的 .asp/ 需個別執行專案層移除'
    if (-not $DryRun) {
        Write-Host ''
        Write-Host '  User-level ASP 移除完成' -ForegroundColor Green
    }
    exit 0
}

# ═══════════════════════════════════════════════════════════════════
# 專案層移除
# ═══════════════════════════════════════════════════════════════════
Write-Host ''
Write-Host 'ASP 專案移除' -ForegroundColor Red
Write-Host '═══════════════════════════════'
Write-Host "  目錄：$(Get-Location)"
if ($DryRun) { Write-Host '  ── DRY RUN 模式（不實際執行）──' }
Write-Host ''

# 安全：必須在 git repo 內
try {
    & git rev-parse --git-dir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'not a git repo' }
} catch {
    Write-Warn '目前不在 git repo 內，請在專案根目錄執行'
    exit 1
}

$HasAsp = (Test-Path '.asp') -or (Test-Path '.claude\skills\asp') -or (Test-Path '.ai_profile')
if (-not $HasAsp) {
    Write-Host '  未偵測到 ASP 設定，無需移除'
    exit 0
}

Remove-Target '.asp' 'ASP 核心（舊架構）'
Remove-Target '.claude\skills\asp' 'ASP skills（已改由 ~/.claude/skills/asp/ 提供）'

if (Test-Path '.claude\agents') {
    $aspAgents = Get-ChildItem '.claude\agents' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(reality-checker|asp-)' }
    if ($aspAgents) {
        if ($DryRun) {
            Write-Dry ".claude\agents\（$($aspAgents.Count) 個 ASP agent 定義）"
        } else {
            $aspAgents | Remove-Item -Force
            if (-not (Get-ChildItem '.claude\agents' -ErrorAction SilentlyContinue)) {
                Remove-Item '.claude\agents' -Force
            }
            Write-Success '移除 .claude\agents\ 內的 ASP agent 定義'
        }
    }
}

if ($DryRun) {
    if ((Test-Path '.claude\settings.json') -and (Select-String -Path '.claude\settings.json' -Pattern 'session-audit|clean-allow-list' -Quiet)) {
        Write-Dry '.claude\settings.json（移除 ASP hooks，保留其他）'
    }
} else {
    Clear-AspHooks '.claude\settings.json'
}

# CLAUDE.md
if ((Test-Path 'CLAUDE.md') -and (Select-String -Path 'CLAUDE.md' -Pattern 'AI-SOP-Protocol' -Quiet)) {
    if ($DryRun) {
        Write-Dry 'CLAUDE.md（ASP 產生）'
    } elseif (Confirm-Action 'CLAUDE.md 是 ASP 產生的，是否移除？') {
        Remove-Item -Force 'CLAUDE.md'
        Write-Success '移除 CLAUDE.md'
    } else {
        Write-Warn '保留 CLAUDE.md（手動清理 ASP 段落）'
    }
}

# 保留項目告知
Write-Host ''
Write-Host '  ── 以下項目已保留（使用者資料）──'
$kept = @()
if (Test-Path '.ai_profile')              { $kept += '.ai_profile' }
if (Test-Path 'docs\adr')                 { $kept += 'docs/adr/' }
if (Test-Path 'docs\specs')               { $kept += 'docs/specs/' }
if (Test-Path '.asp-bypass-log.ndjson')   { $kept += '.asp-bypass-log.ndjson（audit trail）' }
if (Test-Path '.asp-fact-check.md')       { $kept += '.asp-fact-check.md（外部事實記錄）' }
foreach ($item in $kept) { Write-Info "  保留：$item" }

Write-Host ''
if (-not $DryRun) {
    Write-Host '  專案 ASP 移除完成' -ForegroundColor Green
    Write-Host ''
    Write-Host '  若要移除 user-level ASP：'
    Write-Host '    $env:ASP_USER_LEVEL=''1''; irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.ps1 | iex'
} else {
    Write-Host '  [DRY RUN 完成 — 以上為預覽，未實際移除]'
}
Write-Host ''
