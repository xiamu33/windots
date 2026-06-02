# =====================================================================
# Windots 单命令安装器 (install.ps1)
# PS5.1 兼容、自包含、不依赖 lib/
#
# 用法（从网络直接执行）：
#   irm https://raw.githubusercontent.com/xiamu33/windots/main/install.ps1 | iex
#
# 或本地执行（指定参数透传给 setup.ps1）：
#   .\install.ps1
#   .\install.ps1 -Branch dev -WhatIf
# =====================================================================

[CmdletBinding()]
param(
    # 安装目标目录，默认 ~/.local/share/windots
    [string] $InstallDir = '',
    # GitHub 分支
    [string] $Branch = 'main',
    # 代理地址（留空则询问）
    [string] $ProxyUrl = '',
    # 跳过代理询问
    [switch] $NoProxyPrompt,
    # 预演模式（透传给 setup.ps1）
    [switch] $WhatIf,
    # 强制重跑交互（透传给 setup.ps1）
    [switch] $Reconfigure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $null = & chcp 65001
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
}
catch { }

# ──────────────────────────────────────────────────────────────────────
# 极简日志（不依赖 lib/logging.ps1）
# ──────────────────────────────────────────────────────────────────────
function _Info { param([string]$m) Write-Host "[INFO] $m"  -ForegroundColor Cyan }
function _Ok { param([string]$m) Write-Host "[OK]   $m"  -ForegroundColor Green }
function _Warn { param([string]$m) Write-Host "[WARN] $m"  -ForegroundColor Yellow }
function _Err { param([string]$m) Write-Host "[ERR]  $m"  -ForegroundColor Red }
function _Step { param([string]$m) Write-Host "[STEP] $m"  -ForegroundColor Magenta }

# ──────────────────────────────────────────────────────────────────────
# 目标路径
# ──────────────────────────────────────────────────────────────────────
$WindotsHome = if ($InstallDir) {
    $InstallDir
}
else {
    Join-Path $HOME '.local\share\windots'
}

$RepoUrl = 'https://github.com/xiamu33/windots'
$ZipUrl = "https://github.com/xiamu33/windots/archive/refs/heads/$Branch.zip"

_Step '=== Windots Installer ==='
_Info "目标目录：$WindotsHome"
_Info "分支：$Branch"
_Info ''

# ──────────────────────────────────────────────────────────────────────
# 代理配置
# ──────────────────────────────────────────────────────────────────────
if (-not $NoProxyPrompt -and [string]::IsNullOrWhiteSpace($ProxyUrl)) {
    $ans = Read-Host '是否配置代理以加速 GitHub 访问？ [y/N]'
    if ($ans -match '^[yY]') {
        $ProxyUrl = (Read-Host '代理地址（如 http://127.0.0.1:10808）').Trim()
    }
}
if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
    $env:HTTP_PROXY = $ProxyUrl
    $env:HTTPS_PROXY = $ProxyUrl
    $env:ALL_PROXY = $ProxyUrl
    _Info "已设置代理：$ProxyUrl"
}

# ──────────────────────────────────────────────────────────────────────
# 下载/更新仓库
# ──────────────────────────────────────────────────────────────────────
$gitAvail = $null -ne (Get-Command 'git' -ErrorAction SilentlyContinue)
$isRepo = $gitAvail -and (Test-Path (Join-Path $WindotsHome '.git'))

if ($isRepo) {
    # 已是 git 仓库：直接 pull
    _Step '--- 更新已有仓库 ---'
    if ($WhatIf) {
        _Info "[WhatIf] git -C `"$WindotsHome`" pull"
    }
    else {
        & git -C $WindotsHome pull
        if ($LASTEXITCODE -ne 0) {
            _Warn "git pull 失败（exit=$LASTEXITCODE），继续使用现有版本..."
        }
        else {
            _Ok '仓库已更新'
        }
    }
}
elseif ($gitAvail) {
    # git 可用：clone
    _Step '--- git clone 仓库 ---'
    if (Test-Path $WindotsHome) {
        _Warn "目标目录已存在但不是 git 仓库：$WindotsHome"
        _Warn '将备份后重新 clone...'
        if (-not $WhatIf) {
            $bak = $WindotsHome + '.bak.' + (Get-Date).ToString('yyyyMMddHHmmss')
            Rename-Item -Path $WindotsHome -NewName $bak -Force
            _Ok "已备份至：$bak"
        }
    }
    if ($WhatIf) {
        _Info "[WhatIf] git clone $RepoUrl `"$WindotsHome`""
    }
    else {
        $parentDir = Split-Path $WindotsHome -Parent
        if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
        & git clone $RepoUrl $WindotsHome
        if ($LASTEXITCODE -ne 0) {
            _Err "git clone 失败 (exit=$LASTEXITCODE)，请检查网络或代理设置"
            exit 1
        }
        _Ok "仓库已 clone 到：$WindotsHome"
    }
}
else {
    # git 不可用：zip 回退
    _Step '--- 下载 zip 包（git 不可用）---'
    _Info "下载：$ZipUrl"
    if ($WhatIf) {
        _Info "[WhatIf] Invoke-WebRequest $ZipUrl → 解压到 $WindotsHome"
    }
    else {
        $tmpZip = Join-Path $env:TEMP 'windots-install.zip'
        $tmpDir = Join-Path $env:TEMP 'windots-install-extract'

        try {
            Invoke-WebRequest -Uri $ZipUrl -OutFile $tmpZip -UseBasicParsing
        }
        catch {
            _Err "下载失败：$($_.Exception.Message)"
            _Warn '请安装 git 后重试，或手动下载：https://github.com/xiamu33/windots'
            exit 1
        }

        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

        # zip 解压后目录名为 windots-<branch>
        $extractedDir = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
        if (-not $extractedDir) {
            _Err 'zip 包解压失败，未找到解压目录'
            exit 1
        }

        $parentDir = Split-Path $WindotsHome -Parent
        if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
        if (Test-Path $WindotsHome) {
            $bak = $WindotsHome + '.bak.' + (Get-Date).ToString('yyyyMMddHHmmss')
            Rename-Item -Path $WindotsHome -NewName $bak -Force
            _Ok "已备份旧目录：$bak"
        }
        Move-Item -Path $extractedDir.FullName -Destination $WindotsHome -Force

        Remove-Item $tmpZip  -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDir  -Recurse -Force -ErrorAction SilentlyContinue

        _Ok "仓库已安装到：$WindotsHome"
    }
}

# ──────────────────────────────────────────────────────────────────────
# 执行 setup.ps1
# ──────────────────────────────────────────────────────────────────────
_Step '--- 启动 setup.ps1 ---'
$setupScript = Join-Path $WindotsHome 'setup.ps1'
if (-not (Test-Path $setupScript)) {
    _Err "找不到 setup.ps1：$setupScript"
    exit 1
}

$fwdArgs = [System.Collections.Generic.List[string]]::new()
if ($WhatIf) { $fwdArgs.Add('-WhatIf') }
if ($Reconfigure) { $fwdArgs.Add('-Reconfigure') }

_Info "执行：pwsh -File `"$setupScript`" $($fwdArgs -join ' ')"

if ($WhatIf) {
    _Info '[WhatIf] 跳过实际执行 setup.ps1'
}
else {
    if ($null -ne (Get-Command 'pwsh' -ErrorAction SilentlyContinue)) {
        & pwsh -ExecutionPolicy Bypass -File $setupScript @fwdArgs
    }
    else {
        & powershell -ExecutionPolicy Bypass -File $setupScript @fwdArgs
    }
}
