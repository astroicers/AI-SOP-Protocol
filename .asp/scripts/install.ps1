# AI-SOP-Protocol Windows Installer (PowerShell) v4.1
#
# 對應 install.sh 的 Windows 版本。安裝兩段：
#   Phase 1：ASP 核心安裝到 $env:USERPROFILE\.claude\asp\（所有專案共用）
#   Phase 2：當前專案建立輕量設定（.ai_profile + CLAUDE.md + .claude\settings.json）
#
# 用法：
#   # 一行安裝（PowerShell 5.1+ 或 PowerShell 7+）
#   irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.ps1 | iex
#
#   # 非互動式（CI / 預設值）
#   $env:ASP_TYPE='system'; $env:ASP_LEVEL='2'
#   irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.ps1 | iex
#
# 必要前置：
#   • Git for Windows（提供 bash.exe 給 Claude Code 執行 hook）
#   • Python 3.10+
#   • jq 1.6+（chocolatey/scoop/winget 皆可）
#
# 移除：irm https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.ps1 | iex

[CmdletBinding()]
param(
    [string]$ProtocolRepo = 'https://github.com/astroicers/AI-SOP-Protocol',
    [switch]$SkipPrecheck
)

$ErrorActionPreference = 'Stop'

# ─── 工具函式 ────────────────────────────────────────────────────────
function Write-Success { param([string]$Msg) Write-Host "  ✓ $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "  ⚠ $Msg" -ForegroundColor Yellow }
function Write-ErrLine { param([string]$Msg) Write-Host "  ✗ $Msg" -ForegroundColor Red }

function Test-VersionAtLeast {
    param([string]$Required, [string]$Actual)
    try {
        return [version]$Actual -ge [version]$Required
    } catch {
        return $false
    }
}

function Get-CmdVersion {
    param([string]$Cmd, [string]$ArgList, [string]$Pattern)
    try {
        $output = & $Cmd $ArgList.Split(' ') 2>&1 | Out-String
        if ($output -match $Pattern) { return $matches[1] }
    } catch { }
    return $null
}

# ─── Phase 0：Runtime precheck ───────────────────────────────────────
function Invoke-Precheck {
    if ($SkipPrecheck -or $env:ASP_SKIP_PRECHECK -eq '1') {
        Write-Warn 'ASP_SKIP_PRECHECK=1 — 跳過 runtime 檢查'
        return
    }

    $missing = 0

    # git
    $gitVer = Get-CmdVersion 'git' '--version' 'git version ([\d\.]+)'
    if (-not $gitVer) {
        Write-ErrLine 'git 未安裝（需 ≥ 2.20）— 請安裝 Git for Windows: https://git-scm.com/download/win'
        $missing++
    } elseif (-not (Test-VersionAtLeast '2.20' $gitVer)) {
        Write-ErrLine "git $gitVer < 2.20"
        $missing++
    } else {
        Write-Success "git $gitVer ≥ 2.20"
    }

    # bash（Git for Windows 提供）— Claude Code 執行 .sh hook 需要
    $bashExe = (Get-Command bash -ErrorAction SilentlyContinue)
    if (-not $bashExe) {
        Write-ErrLine 'bash.exe 未找到 — 請安裝 Git for Windows（內含 bash），或使用 WSL2 安裝。'
        Write-ErrLine '  Claude Code 在 Windows 執行 ASP hook 需要 bash。'
        $missing++
    } else {
        $bashVer = Get-CmdVersion 'bash' '--version' 'version ([\d\.]+)'
        if ($bashVer -and (Test-VersionAtLeast '4.4' $bashVer)) {
            Write-Success "bash $bashVer ≥ 4.4 ($($bashExe.Source))"
        } else {
            Write-Warn "bash $bashVer 可能 < 4.4 — Git for Windows 內建版本應該足夠，繼續"
        }
    }

    # jq
    $jqVer = Get-CmdVersion 'jq' '--version' 'jq-([\d\.]+)'
    if (-not $jqVer) {
        Write-ErrLine 'jq 未安裝（需 ≥ 1.6）— winget install jqlang.jq  或  choco install jq  或  scoop install jq'
        $missing++
    } elseif (-not (Test-VersionAtLeast '1.6' $jqVer)) {
        Write-ErrLine "jq $jqVer < 1.6"
        $missing++
    } else {
        Write-Success "jq $jqVer ≥ 1.6"
    }

    # python
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pyCmd) { $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $pyCmd) {
        Write-ErrLine 'python 未安裝（需 ≥ 3.10）— https://www.python.org/downloads/'
        $missing++
    } else {
        $pyVer = Get-CmdVersion $pyCmd.Source '--version' 'Python ([\d\.]+)'
        if (-not $pyVer -or -not (Test-VersionAtLeast '3.10' $pyVer)) {
            Write-ErrLine "python $pyVer < 3.10"
            $missing++
        } else {
            Write-Success "python $pyVer ≥ 3.10"
        }
    }

    if ($missing -gt 0) {
        Write-Host ''
        Write-Host "ERROR: $missing 項必要套件未安裝。安裝後重跑，或設 `$env:ASP_SKIP_PRECHECK='1' 跳過。" -ForegroundColor Red
        exit 13
    }
}

# ─── 偵測專案類型 ────────────────────────────────────────────────────
function Get-DetectedType {
    if ((Test-Path 'docker-compose.yml') -and (Test-Path 'docs/adr')) { return 'architecture' }
    if ((Get-ChildItem -Path . -Filter Dockerfile -Recurse -Depth 1 -ErrorAction SilentlyContinue) -or
        (Test-Path 'terraform') -or (Test-Path 'pulumi') -or (Test-Path 'helmfile.yaml')) {
        return 'architecture'
    }
    foreach ($f in @('go.mod','Cargo.toml','pom.xml','package.json','requirements.txt','pyproject.toml','Dockerfile','Makefile')) {
        if (Test-Path $f) { return 'system' }
    }
    return 'content'
}

# ─── 套用 preset（對應 install.sh apply_preset）───────────────────────
function Set-Preset {
    param([int]$Level)
    $script:ASP_LEVEL = $Level
    $script:HITL_LEVEL = 'standard'
    $script:WORKFLOW = 'standard'
    $script:MODE = 'auto'
    $script:ENABLE_AUTONOMOUS = 'n'
    $script:ENABLE_ORCHESTRATOR = 'n'
    $script:ENABLE_AUTOPILOT = 'n'
    $script:ENABLE_RAG = 'n'
    $script:ENABLE_GUARDRAIL = 'n'
    $script:ENABLE_CODING_STYLE = 'n'

    switch ($Level) {
        2 { $script:ENABLE_GUARDRAIL='y'; $script:ENABLE_CODING_STYLE='y' }
        3 { $script:ENABLE_GUARDRAIL='y'; $script:ENABLE_CODING_STYLE='y' }
        4 { $script:MODE='multi-agent'; $script:ENABLE_ORCHESTRATOR='y'; $script:ENABLE_GUARDRAIL='y'; $script:ENABLE_CODING_STYLE='y' }
        5 { $script:MODE='multi-agent'; $script:HITL_LEVEL='minimal'; $script:WORKFLOW='vibe-coding';
            $script:ENABLE_AUTONOMOUS='y'; $script:ENABLE_ORCHESTRATOR='y'; $script:ENABLE_AUTOPILOT='y';
            $script:ENABLE_RAG='y'; $script:ENABLE_GUARDRAIL='y'; $script:ENABLE_CODING_STYLE='y' }
    }
}

# ─── 將 Windows 路徑轉成 bash 友善（forward slash）─────────────────────
function ConvertTo-BashPath {
    param([string]$Path)
    # C:\Users\x\.claude → C:/Users/x/.claude（Git Bash 接受此格式）
    return ($Path -replace '\\', '/')
}

# ═══════════════════════════════════════════════════════════════════
# 開場
# ═══════════════════════════════════════════════════════════════════
Write-Host ''
Write-Host '🤖 AI-SOP-Protocol 安裝程式 v4.1（Windows / PowerShell）'
Write-Host '================================================='
Write-Host '  架構：User-level（%USERPROFILE%\.claude\asp\）— 所有專案共用'
Write-Host ''

Write-Host '🔍 Phase 0：runtime 環境檢查'
Write-Host '──────────────────────────────────────'
Invoke-Precheck
Write-Host ''

# ═══════════════════════════════════════════════════════════════════
# Phase 1：User-level 安裝
# ═══════════════════════════════════════════════════════════════════
$UserClaude = Join-Path $HOME '.claude'
$UserAsp    = Join-Path $UserClaude 'asp'
$UserSkills = Join-Path $UserClaude 'skills\asp'
$TmpDir     = Join-Path $env:TEMP "asp-install-$(Get-Random)"

Write-Host '📦 Phase 1：安裝 ASP 核心到 ~/.claude/'
Write-Host '──────────────────────────────────────'

$IsUserUpgrade = (Test-Path $UserAsp) -or (Test-Path $UserSkills)
$InstalledVersion = 'unknown'
if ($IsUserUpgrade) {
    if (Test-Path (Join-Path $UserAsp 'VERSION')) {
        $InstalledVersion = (Get-Content (Join-Path $UserAsp 'VERSION') -Raw).Trim()
    }
    Write-Host "  🔄 偵測到已安裝 ASP v$InstalledVersion，執行升級"
}

Write-Host '  從 GitHub 下載 ASP...'
try {
    & git clone --quiet --depth=1 $ProtocolRepo $TmpDir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }

    $NewVersion = (Get-Content (Join-Path $TmpDir '.asp\VERSION') -Raw -ErrorAction SilentlyContinue).Trim()
    if (-not $NewVersion) { $NewVersion = 'unknown' }
    $NewCommit = (& git -C $TmpDir rev-parse --short HEAD 2>&1).Trim()
    Write-Host "  版本：v$NewVersion ($NewCommit)"

    New-Item -ItemType Directory -Path $UserAsp -Force | Out-Null
    foreach ($dir in @('profiles','hooks','templates','levels','agents','config','advanced')) {
        $src = Join-Path $TmpDir ".asp\$dir"
        $dst = Join-Path $UserAsp $dir
        if (Test-Path $src) {
            if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
            Copy-Item -Recurse -Force $src $dst
        }
    }
    Copy-Item -Force (Join-Path $TmpDir '.asp\VERSION') (Join-Path $UserAsp 'VERSION') -ErrorAction SilentlyContinue

    New-Item -ItemType Directory -Path $UserSkills -Force | Out-Null
    Get-ChildItem $UserSkills -Force | Remove-Item -Recurse -Force
    Copy-Item -Recurse -Force (Join-Path $TmpDir '.claude\skills\asp\*') $UserSkills

    $UserClaudeMd = Join-Path $UserClaude 'CLAUDE.md'
    $SrcClaudeMd  = Join-Path $TmpDir '.claude\CLAUDE.md'
    $ShouldWriteClaudeMd = $false
    if (-not (Test-Path $UserClaudeMd)) {
        $ShouldWriteClaudeMd = $true
    } elseif (Select-String -Path $UserClaudeMd -Pattern 'ASP User-level Rules|AI-SOP-Protocol' -Quiet -ErrorAction SilentlyContinue) {
        $ShouldWriteClaudeMd = $true
    }
    if ($ShouldWriteClaudeMd -and (Test-Path $SrcClaudeMd)) {
        Copy-Item -Force $SrcClaudeMd $UserClaudeMd
        Write-Success '~/.claude/CLAUDE.md（user-level 鐵則）'
    }

    $UserScripts = Join-Path $UserClaude 'scripts'
    New-Item -ItemType Directory -Path $UserScripts -Force | Out-Null
    $SrcSync = Join-Path $TmpDir '.claude\scripts\asp-sync.sh'
    if (Test-Path $SrcSync) {
        Copy-Item -Force $SrcSync (Join-Path $UserScripts 'asp-sync.sh')
        Write-Success '~/.claude/scripts/asp-sync.sh'
    }

    if ($IsUserUpgrade) {
        Write-Success "User-level 升級完成（v$InstalledVersion → v$NewVersion）"
    } else {
        Write-Success "User-level 安裝完成（v$NewVersion）"
    }
} catch {
    Write-Warn "無法連接 GitHub 或下載失敗：$_"
    $NewVersion = 'local'
    $NewCommit  = 'local'
} finally {
    if (Test-Path $TmpDir) { Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue }
}

Write-Host ''

# ═══════════════════════════════════════════════════════════════════
# Phase 2：專案輕量設定
# ═══════════════════════════════════════════════════════════════════
Write-Host "📋 Phase 2：設定專案輕量層（$(Get-Location)）"
Write-Host '──────────────────────────────────────'

$IsProjectUpgrade = (Test-Path '.ai_profile') -or (Test-Path '.asp')

if (Test-Path '.asp') {
    Write-Warn '.asp\ 偵測到舊架構 — 自動清理'
    Remove-Item -Recurse -Force '.asp'
    Write-Success '移除 .asp/（已由 ~/.claude/asp/ 取代）'
}
if (Test-Path '.claude\skills\asp') {
    Remove-Item -Recurse -Force '.claude\skills\asp'
    Write-Success '移除 .claude/skills/asp/（已由 ~/.claude/skills/asp/ 取代）'
}

$Detected = Get-DetectedType
$DefaultName = Split-Path -Leaf (Get-Location)

# 互動：判斷是否有 TTY
$Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

if ($Interactive -and -not $env:ASP_TYPE -and -not $env:ASP_LEVEL) {
    Write-Host ''
    Write-Host "  專案類型：[1] system  [2] content  [3] architecture  （偵測：$Detected）"
    $typeChoice = Read-Host '  選擇 (Enter 使用偵測值)'
    $PROJECT_TYPE = switch ($typeChoice) {
        '1' { 'system' }
        '2' { 'content' }
        '3' { 'architecture' }
        default { $Detected }
    }

    Write-Host ''
    Write-Host '  成熟度等級：'
    Write-Host '    [1] L1 Starter       — 最小治理（ADR + SPEC + 測試）'
    Write-Host '    [2] L2 Disciplined   — + guardrail + coding_style'
    Write-Host '    [3] L3 Test-First    — + pipeline gates G1-G6'
    Write-Host '    [4] L4 Collaborative — + multi-agent'
    Write-Host '    [5] L5 Autonomous    — + autopilot + RAG'
    $levelChoice = Read-Host '  選擇 level (Enter = L1)'
    if (-not $levelChoice) { $levelChoice = '1' }
    Set-Preset ([int]$levelChoice)
} else {
    $PROJECT_TYPE = if ($env:ASP_TYPE) { $env:ASP_TYPE } else { $Detected }
    $envLevel = if ($env:ASP_LEVEL) { [int]$env:ASP_LEVEL } else { 1 }
    Set-Preset $envLevel
    Write-Host "  非互動模式 — type: $PROJECT_TYPE | level: L$envLevel"
}

$PROJECT_NAME = $DefaultName
Write-Host ''

# .ai_profile
if (Test-Path '.ai_profile') {
    Write-Warn '.ai_profile 已存在，保留（如需重設請刪除後重跑）'
} else {
    $ragVal = if ($ENABLE_RAG -eq 'y') { 'enabled' } else { 'disabled' }
    $grdVal = if ($ENABLE_GUARDRAIL -eq 'y') { 'enabled' } else { 'disabled' }
    $autVal = if ($ENABLE_AUTONOMOUS -eq 'y') { 'enabled' } else { 'disabled' }
    $orcVal = if ($ENABLE_ORCHESTRATOR -eq 'y') { 'enabled' } else { 'disabled' }
    $aplVal = if ($ENABLE_AUTOPILOT -eq 'y') { 'enabled' } else { 'disabled' }
    $csVal  = if ($ENABLE_CODING_STYLE -eq 'y') { 'enabled' } else { 'disabled' }

    $profileContent = @"
type: $PROJECT_TYPE
level: $ASP_LEVEL
mode: $MODE
workflow: $WORKFLOW
hitl: $HITL_LEVEL
rag: $ragVal
guardrail: $grdVal
autonomous: $autVal
orchestrator: $orcVal
autopilot: $aplVal
coding_style: $csVal
name: $PROJECT_NAME
"@
    Set-Content -Path '.ai_profile' -Value $profileContent -Encoding UTF8
    Write-Success '.ai_profile'
}

# CLAUDE.md（精簡版）
$hasClaudeMd = Test-Path 'CLAUDE.md'
$claudeMdIsAsp = $false
if ($hasClaudeMd) {
    $claudeMdIsAsp = Select-String -Path 'CLAUDE.md' -Pattern 'AI-SOP-Protocol|ASP' -Quiet -ErrorAction SilentlyContinue
}
if ($hasClaudeMd -and $claudeMdIsAsp) {
    Write-Warn 'CLAUDE.md 已存在（ASP 版），保留'
} elseif (-not $hasClaudeMd) {
    $claudeMdContent = @"
# $PROJECT_NAME — AI 行為設定

> ASP v4.0 | 讀取順序：本檔案 → ``.ai_profile`` → ``~/.claude/CLAUDE.md``（user-level 鐵則）
> Profile 邏輯與 ASP skills 詳見 ``~/.claude/asp/profiles/`` 與 ``~/.claude/skills/asp/``

## 專案說明

[請填寫專案用途]

## 特殊規則（選填，覆蓋 user-level 預設）

[例如：禁止修改 legacy/ 目錄；必須保持向後相容]
"@
    Set-Content -Path 'CLAUDE.md' -Value $claudeMdContent -Encoding UTF8
    Write-Success 'CLAUDE.md（精簡版）'
}

# .claude/settings.json — hooks 透過 bash 執行（Windows 上的 .sh 需要）
New-Item -ItemType Directory -Path '.claude' -Force | Out-Null

$bashHomeForward = ConvertTo-BashPath $HOME
$hookAudit = "bash `"$bashHomeForward/.claude/asp/hooks/session-audit.sh`""
$hookAllow = "bash `"$bashHomeForward/.claude/asp/hooks/clean-allow-list.sh`""

$settingsPath = '.claude\settings.json'
$jqAvailable = $null -ne (Get-Command jq -ErrorAction SilentlyContinue)

if ($jqAvailable -and (Test-Path $settingsPath)) {
    # 升級：清理舊 ASP hooks、加入 user-level hooks
    $tmpSettings = "$settingsPath.tmp"
    $jqFilter = @'
      .hooks.SessionStart = [
        ((.hooks.SessionStart // [])[] |
          select((.hooks // []) | all(.command |
            test("(session-audit|clean-allow-list)") | not))
        ),
        {"hooks": [
          {"type": "command", "command": $allow},
          {"type": "command", "command": $audit}
        ]}
      ] |
      .permissions.allow = ((.permissions.allow // []) + ["Bash(*)"] | unique)
'@
    & jq --arg audit $hookAudit --arg allow $hookAllow $jqFilter $settingsPath | Set-Content $tmpSettings -Encoding UTF8
    Move-Item -Force $tmpSettings $settingsPath
    Write-Success '.claude\settings.json（hooks 更新為 user-level 路徑 + bash 啟動）'
} else {
    $settingsObj = [ordered]@{
        hooks = @{
            SessionStart = @(
                @{
                    hooks = @(
                        @{ type='command'; command=$hookAllow },
                        @{ type='command'; command=$hookAudit }
                    )
                }
            )
        }
        permissions = @{
            allow = @('Bash(*)')
            ask = @(
                'Bash(git push *)', 'Bash(git push)',
                'Bash(git rebase *)', 'Bash(rm -rf *)', 'Bash(rm -r *)',
                'Bash(docker push *)', 'Bash(docker deploy *)'
            )
        }
    }
    $settingsObj | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    Write-Success '.claude\settings.json（hooks 透過 bash 執行 .sh）'
}

# denied-commands 合併
$denyJson = Join-Path $UserAsp 'hooks\denied-commands.json'
if ($jqAvailable -and (Test-Path $denyJson)) {
    $tmpSettings = "$settingsPath.tmp"
    $denyContent = Get-Content $denyJson -Raw
    & jq --argjson ask $denyContent '.permissions.ask = ((.permissions.ask // []) + $ask | unique)' $settingsPath | Set-Content $tmpSettings -Encoding UTF8
    Move-Item -Force $tmpSettings $settingsPath
}

# docs/
New-Item -ItemType Directory -Path 'docs\adr' -Force | Out-Null
New-Item -ItemType Directory -Path 'docs\specs' -Force | Out-Null
Write-Success 'docs/adr/ docs/specs/'

# ADR-001
$adrSrc = Join-Path $UserAsp 'templates\ADR_Template.md'
$adrDst = 'docs\adr\ADR-001-initial-technology-stack.md'
if ((Test-Path $adrSrc) -and -not (Get-ChildItem -Path 'docs\adr' -Filter 'ADR-001-*.md' -ErrorAction SilentlyContinue)) {
    $today = Get-Date -Format 'yyyy-MM-dd'
    (Get-Content $adrSrc -Raw) `
        -replace 'ADR-000', 'ADR-001' `
        -replace '決策標題', '初始技術棧選型' `
        -replace 'YYYY-MM-DD', $today |
        Set-Content $adrDst -Encoding UTF8
    Write-Success "$adrDst（請填入技術棧）"
}

# .gitignore
$aspGitignoreEntries = @(
    '.asp-session-briefing.json',
    '.asp-audit-baseline.json',
    '.asp-bypass-log.ndjson',
    '.asp-telemetry.jsonl',
    '.asp-fact-check.md',
    '.asp-review-calibration.jsonl'
)
if (Test-Path '.gitignore') {
    $existing = Get-Content '.gitignore'
    $added = 0
    foreach ($entry in $aspGitignoreEntries) {
        if ($existing -notcontains $entry) {
            Add-Content '.gitignore' $entry
            $added++
        }
    }
    if ($added -gt 0) { Write-Success ".gitignore（補充 $added 條 ASP 執行時檔案）" }
}

# ═══════════════════════════════════════════════════════════════════
# 完成
# ═══════════════════════════════════════════════════════════════════
Write-Host ''
if ($IsProjectUpgrade) {
    Write-Host "🎉 升級完成！（v$NewVersion @ $NewCommit）"
} else {
    Write-Host "🎉 安裝完成！（v$NewVersion @ $NewCommit）"
}
Write-Host ''
Write-Host '  每個專案只需：'
Write-Host '    .ai_profile           ← 專案設定'
Write-Host '    CLAUDE.md             ← 精簡版行為設定'
Write-Host '    .claude\settings.json ← hooks 透過 bash 指向 ~/.claude/asp/hooks/'
Write-Host ''
Write-Host '  ASP 核心在 %USERPROFILE%\.claude\asp\（所有專案共用）'
Write-Host '  更新 ASP：bash ~/.claude/scripts/asp-sync.sh'
Write-Host ''
Write-Host '  啟動 Claude Code，輸入：'
Write-Host '  「請讀取 CLAUDE.md，依照 .ai_profile 載入對應設定。」'
Write-Host ''
Write-Host '💡 建議：開始前執行 /asp-audit 做初始健康檢查'
