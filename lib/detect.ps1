# =====================================================================
# Windots 环境检测 (lib/detect.ps1)
# =====================================================================

$Global:WindotsDetectionCache = @{}
$Global:WindotsWingetList = $null
$Global:WindotsScoopList = $null
$Global:WindotsScoopGlobalList = $null
$Global:WindotsBucketList = $null

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Test-DeveloperMode {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    if (-not (Test-Path $key)) { return $false }
    $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($null -eq $props) { return $false }
    $prop = $props.PSObject.Properties['AllowDevelopmentWithoutDevLicense']
    if ($null -eq $prop) { return $false }
    return ($prop.Value -eq 1)
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string] $Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Reset-WindotsDetectionCache {
    $Global:WindotsWingetList = $null
    $Global:WindotsScoopList = $null
    $Global:WindotsScoopGlobalList = $null
    $Global:WindotsBucketList = $null
}

function Get-WindotsWingetList {
    if ($null -ne $Global:WindotsWingetList) { return $Global:WindotsWingetList }
    if (-not (Test-CommandExists -Name 'winget')) {
        $Global:WindotsWingetList = ''
        return ''
    }
    Write-Info (msg 'detect.winget.loading')
    $Global:WindotsWingetList = (& winget list --source winget --accept-source-agreements 2>$null | Out-String)
    return $Global:WindotsWingetList
}

function Test-WingetInstalled {
    param([Parameter(Mandatory)][string] $Id)
    $text = Get-WindotsWingetList
    if ([string]::IsNullOrEmpty($text)) { return $false }
    $pat = '(^|\s)' + [regex]::Escape($Id) + '(\s|$)'
    return [regex]::IsMatch($text, $pat, 'IgnoreCase,Multiline')
}

function Get-ScoopConfigPath {
    param(
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][string] $Default
    )
    if (-not (Test-CommandExists -Name 'scoop')) { return $Default }
    $value = (& scoop config $Key 2>$null | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Get-ScoopUserRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:SCOOP)) { return $env:SCOOP }
    return Get-ScoopConfigPath -Key 'root_path' -Default (Join-Path $env:USERPROFILE 'scoop')
}

function Get-ScoopGlobalRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:SCOOP_GLOBAL)) { return $env:SCOOP_GLOBAL }
    return Get-ScoopConfigPath -Key 'global_path' -Default (Join-Path $env:ProgramData 'scoop')
}

function Test-ScoopAppDirInstalled {
    param([Parameter(Mandatory)][string] $AppDir)
    if (Test-Path (Join-Path $AppDir 'current')) { return $true }
    foreach ($ver in Get-ChildItem $AppDir -Directory -ErrorAction SilentlyContinue) {
        if ([string]$ver.Name -ieq 'current') { continue }
        if ($ver.Name -match '^_') { continue }
        if (Test-Path (Join-Path $ver.FullName 'install.json')) { return $true }
    }
    return $false
}

function Build-ScoopInstalledMapFromDisk {
    param([Parameter(Mandatory)][string] $ScoopRoot)
    $map = @{}
    $appsDir = Join-Path $ScoopRoot 'apps'
    if (-not (Test-Path $appsDir)) { return $map }
    foreach ($entry in Get-ChildItem $appsDir -Directory -ErrorAction SilentlyContinue) {
        if ([string]$entry.Name -ieq 'scoop') { continue }
        if (Test-ScoopAppDirInstalled -AppDir $entry.FullName) {
            $map[$entry.Name.ToLowerInvariant()] = $true
        }
    }
    return $map
}

function Get-WindotsScoopList {
    param([switch] $GlobalInstall)

    if ($GlobalInstall) {
        if ($null -ne $Global:WindotsScoopGlobalList) { return $Global:WindotsScoopGlobalList }
        $map = Build-ScoopInstalledMapFromDisk -ScoopRoot (Get-ScoopGlobalRoot)
        $Global:WindotsScoopGlobalList = $map
        return $map
    }

    if ($null -ne $Global:WindotsScoopList) { return $Global:WindotsScoopList }
    $map = Build-ScoopInstalledMapFromDisk -ScoopRoot (Get-ScoopUserRoot)
    $Global:WindotsScoopList = $map
    return $map
}

function Get-ScoopAppBaseName {
    param([Parameter(Mandatory)][string] $Name)
    $idx = $Name.IndexOf('/')
    if ($idx -ge 0) { return $Name.Substring($idx + 1) }
    return $Name
}

function Test-ScoopInstalled {
    param(
        [Parameter(Mandatory)][string] $Name,
        [switch] $GlobalInstall
    )
    $base = Get-ScoopAppBaseName -Name $Name
    $key = $base.ToLowerInvariant()
    if ($GlobalInstall) {
        return (Get-WindotsScoopList -GlobalInstall).ContainsKey($key)
    }
    if ((Get-WindotsScoopList).ContainsKey($key)) { return $true }
    return (Get-WindotsScoopList -GlobalInstall).ContainsKey($key)
}

function Get-WindotsBucketList {
    if ($null -ne $Global:WindotsBucketList) { return $Global:WindotsBucketList }
    $map = @{}
    if (-not (Test-CommandExists -Name 'scoop')) { $Global:WindotsBucketList = $map; return $map }
    $out = (& scoop bucket list *>&1 | Out-String)
    foreach ($line in ($out -split "`r?`n")) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t -match '^Name\s+Source' -or $t -match '^----') { continue }
        $parts = $t -split '\s+', 3
        if ($parts.Length -gt 1) { $map[$parts[0]] = $parts[1] }
        elseif ($parts[0]) { $map[$parts[0]] = '' }
    }
    $Global:WindotsBucketList = $map
    return $map
}

function Update-SessionPath {
    $m = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u"
}
