# =====================================================================
# Windots one-shot installer (install.ps1)
# PS 5.1 compatible, self-contained, no lib/ dependency
# Encoding: UTF-8 without BOM; source must be ASCII-only (no CJK in this file)
#
# Remote:
#   irm https://raw.githubusercontent.com/xiamu33/windots/main/install.ps1 | iex
#
# Local (forwards -WhatIf / -Reconfigure to setup.ps1):
#   .\install.ps1
#   .\install.ps1 -Branch dev -WhatIf
# =====================================================================

[CmdletBinding()]
param(
    [string] $InstallDir = '',
    [string] $Branch = 'main',
    [string] $ProxyUrl = '',
    [switch] $NoProxyPrompt,
    [switch] $WhatIf,
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

function _Info { param([string]$m) Write-Host "[INFO] $m"  -ForegroundColor Cyan }
function _Ok { param([string]$m) Write-Host "[OK]   $m"  -ForegroundColor Green }
function _Warn { param([string]$m) Write-Host "[WARN] $m"  -ForegroundColor Yellow }
function _Err { param([string]$m) Write-Host "[ERR]  $m"  -ForegroundColor Red }
function _Step { param([string]$m) Write-Host "[STEP] $m"  -ForegroundColor Magenta }

function _Refresh-Path {
    $m = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u"
}

function _Ensure-Pwsh {
    if ($null -ne (Get-Command 'pwsh' -ErrorAction SilentlyContinue)) {
        _Ok 'PowerShell 7 (pwsh) is already installed'
        return $true
    }
    if ($null -eq (Get-Command 'winget' -ErrorAction SilentlyContinue)) {
        _Err 'winget is not available; cannot install PowerShell 7'
        return $false
    }
    if ($WhatIf) {
        _Info '[WhatIf] winget install --id Microsoft.PowerShell --source winget'
        return $true
    }
    _Info 'Installing PowerShell 7 via winget...'
    & winget install --id Microsoft.PowerShell --source winget
    if ($LASTEXITCODE -ne 0) {
        _Err "Failed to install PowerShell 7 (exit=$LASTEXITCODE)"
        return $false
    }
    _Refresh-Path
    if ($null -eq (Get-Command 'pwsh' -ErrorAction SilentlyContinue)) {
        _Err 'PowerShell 7 was installed but pwsh is not on PATH; open a new terminal and re-run install.ps1'
        return $false
    }
    _Ok 'PowerShell 7 installed'
    return $true
}

function _Ensure-Git {
    if ($null -ne (Get-Command 'git' -ErrorAction SilentlyContinue)) {
        _Ok 'Git is already installed'
        return $true
    }
    if ($null -eq (Get-Command 'winget' -ErrorAction SilentlyContinue)) {
        _Err 'winget is not available; cannot install Git'
        return $false
    }
    if ($WhatIf) {
        _Info '[WhatIf] winget install --id Git.Git --source winget --accept-package-agreements --accept-source-agreements'
        return $true
    }
    _Info 'Installing Git via winget...'
    & winget install --id Git.Git --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        _Err "Failed to install Git (exit=$LASTEXITCODE)"
        return $false
    }
    _Refresh-Path
    if ($null -eq (Get-Command 'git' -ErrorAction SilentlyContinue)) {
        _Warn 'Git was installed but git is not on PATH yet; zip fallback may still work'
        return $true
    }
    _Ok 'Git installed'
    return $true
}

$WindotsHome = if ($InstallDir) { $InstallDir } else { Join-Path $HOME '.local\share\windots' }

$RepoUrl = 'https://github.com/xiamu33/windots'
$ZipUrl = "https://github.com/xiamu33/windots/archive/refs/heads/$Branch.zip"

_Step '=== Windots Installer ==='
_Info "Install dir: $WindotsHome"
_Info "Branch: $Branch"
_Info ''

if (-not $NoProxyPrompt -and [string]::IsNullOrWhiteSpace($ProxyUrl)) {
    $ans = Read-Host 'Configure a proxy for GitHub? [y/N]'
    if ($ans -match '^[yY]') {
        $ProxyUrl = (Read-Host 'Proxy URL (e.g. http://127.0.0.1:10808)').Trim()
    }
}
if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
    $env:HTTP_PROXY = $ProxyUrl
    $env:HTTPS_PROXY = $ProxyUrl
    $env:ALL_PROXY = $ProxyUrl
    _Info "Proxy set: $ProxyUrl"
}

$gitAvail = $null -ne (Get-Command 'git' -ErrorAction SilentlyContinue)
$isRepo = $gitAvail -and (Test-Path (Join-Path $WindotsHome '.git'))

if ($isRepo) {
    _Step '--- Update existing repo ---'
    if ($WhatIf) {
        _Info "[WhatIf] git -C `"$WindotsHome`" pull"
    }
    else {
        & git -C $WindotsHome pull
        if ($LASTEXITCODE -ne 0) {
            _Warn "git pull failed (exit=$LASTEXITCODE); continuing with existing tree..."
        }
        else {
            _Ok 'Repository updated'
        }
    }
}
elseif ($gitAvail) {
    _Step '--- git clone ---'
    if (Test-Path $WindotsHome) {
        _Warn "Target exists but is not a git repo: $WindotsHome"
        _Warn 'Will back up and clone again...'
        if (-not $WhatIf) {
            $bak = $WindotsHome + '.bak.' + (Get-Date).ToString('yyyyMMddHHmmss')
            Rename-Item -Path $WindotsHome -NewName $bak -Force
            _Ok "Backed up to: $bak"
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
            _Err "git clone failed (exit=$LASTEXITCODE); check network or proxy"
            exit 1
        }
        _Ok "Cloned to: $WindotsHome"
    }
}
else {
    _Step '--- Download zip (git not available) ---'
    _Info "URL: $ZipUrl"
    if ($WhatIf) {
        _Info "[WhatIf] Invoke-WebRequest $ZipUrl -> extract to $WindotsHome"
    }
    else {
        $tmpZip = Join-Path $env:TEMP 'windots-install.zip'
        $tmpDir = Join-Path $env:TEMP 'windots-install-extract'

        try {
            Invoke-WebRequest -Uri $ZipUrl -OutFile $tmpZip -UseBasicParsing
        }
        catch {
            _Err "Download failed: $($_.Exception.Message)"
            _Warn 'Install git and retry, or download manually: https://github.com/xiamu33/windots'
            exit 1
        }

        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

        $extractedDir = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
        if (-not $extractedDir) {
            _Err 'Zip extract failed: no top-level directory found'
            exit 1
        }

        $parentDir = Split-Path $WindotsHome -Parent
        if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
        if (Test-Path $WindotsHome) {
            $bak = $WindotsHome + '.bak.' + (Get-Date).ToString('yyyyMMddHHmmss')
            Rename-Item -Path $WindotsHome -NewName $bak -Force
            _Ok "Backed up old dir: $bak"
        }
        Move-Item -Path $extractedDir.FullName -Destination $WindotsHome -Force

        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        _Ok "Installed to: $WindotsHome"
    }
}

_Step '--- Ensure PowerShell 7 and Git ---'
if (-not (_Ensure-Pwsh)) { exit 1 }
if (-not (_Ensure-Git)) { exit 1 }

_Step '--- Start setup.ps1 ---'
$setupScript = Join-Path $WindotsHome 'setup.ps1'
if (-not (Test-Path $setupScript)) {
    _Err "setup.ps1 not found: $setupScript"
    exit 1
}

$fwdArgs = [System.Collections.Generic.List[string]]::new()
if ($WhatIf) { $fwdArgs.Add('-WhatIf') }
if ($Reconfigure) { $fwdArgs.Add('-Reconfigure') }

_Info "Running: pwsh -NoProfile -ExecutionPolicy Bypass -File `"$setupScript`" $($fwdArgs -join ' ')"

if ($WhatIf) {
    _Info '[WhatIf] skip running setup.ps1'
    exit 0
}

if ($null -eq (Get-Command 'pwsh' -ErrorAction SilentlyContinue)) {
    _Err 'pwsh is required but not found on PATH'
    exit 1
}

& pwsh -NoProfile -ExecutionPolicy Bypass -File $setupScript @fwdArgs
exit $LASTEXITCODE
