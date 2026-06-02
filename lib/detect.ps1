# =====================================================================
# Windots 环境检测 (lib/detect.ps1)
# =====================================================================

$Global:WindotsDetectionCache = @{}
$Global:WindotsWingetList = $null
$Global:WindotsScoopList = $null
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

function Get-WindotsScoopList {
    if ($null -ne $Global:WindotsScoopList) { return $Global:WindotsScoopList }
    $map = @{}
    if (-not (Test-CommandExists -Name 'scoop')) { $Global:WindotsScoopList = $map; return $map }
    $out = (& scoop list *>&1 | Out-String)
    foreach ($line in ($out -split "`r?`n")) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t -match '^Name\s+Version' -or $t -match '^----' -or $t -match '^Installed apps') { continue }
        $parts = $t -split '\s+', 2
        if ($parts[0]) { $map[$parts[0].ToLowerInvariant()] = $true }
    }
    $Global:WindotsScoopList = $map
    return $map
}

function Test-ScoopInstalled {
    param([Parameter(Mandatory)][string] $Name)
    return (Get-WindotsScoopList).ContainsKey($Name.ToLowerInvariant())
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
