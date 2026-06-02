# =====================================================================
# Windots 上下文构建 (lib/context.ps1)
# =====================================================================

function Get-Context {
    $settings = Import-PowerShellDataFile -Path (Join-Path $Script:Root 'settings.psd1')
    $packages = Import-PowerShellDataFile -Path (Join-Path $Script:Root 'packages.psd1')
    $logDir = Resolve-RepoPath -RepoRoot $Script:Root -Value $settings.Paths.Logs
    $logFile = Start-WindotsLog -LogDir $logDir
    $statePath = Resolve-RepoPath -RepoRoot $Script:Root -Value $settings.Paths.State
    $backupDir = Resolve-RepoPath -RepoRoot $Script:Root -Value $settings.Paths.Backup

    return [pscustomobject]@{
        Root      = $Script:Root
        Settings  = $settings
        Packages  = $packages
        StatePath = $statePath
        BackupDir = $backupDir
        LogFile   = $logFile
        WhatIf    = [bool]$WhatIf
    }
}

function Get-State {
    param([string] $StatePath)
    if (-not (Test-Path $StatePath)) { return $null }
    try {
        $s = Import-PowerShellDataFile -Path $StatePath
        if (-not $s.Contains('Proxy_Enabled')) { return $null }
        return $s
    }
    catch { }
    return $null
}
