# =====================================================================
# Windots Doctor (lib/doctor.ps1)
# =====================================================================

function Invoke-Doctor {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        $State = $null,
        $PackagesDef = $null
    )

    Write-Step (msg 'doctor.title')
    $checks = [System.Collections.Generic.List[object]]::new()

    $psVer = $PSVersionTable.PSVersion
    $psOk = $psVer.Major -ge 7
    $checks.Add([pscustomobject]@{
            Item   = msg 'doctor.ps.name'
            Status = if ($psOk) { 'OK' } else { 'WARN' }
            Detail = "$psVer$(if (-not $psOk) { msg 'doctor.ps.warn.suffix' })"
        })

    $scoopOk = Test-CommandExists -Name 'scoop'
    $checks.Add([pscustomobject]@{
            Item   = msg 'doctor.scoop.name'
            Status = if ($scoopOk) { 'OK' } else { 'FAIL' }
            Detail = if ($scoopOk) { msg 'doctor.scoop.installed' } else { msg 'doctor.scoop.missing' }
        })

    $gitOk = Test-CommandExists -Name 'git'
    $checks.Add([pscustomobject]@{
            Item   = msg 'doctor.git.name'
            Status = if ($gitOk) { 'OK' } else { 'WARN' }
            Detail = if ($gitOk) { msg 'doctor.git.installed' } else { msg 'doctor.git.missing' }
        })

    $localBin = Join-Path $HOME '.local\bin'
    $cmdShim = Join-Path $localBin 'windots.cmd'
    $ps1Shim = Join-Path $localBin 'windots.ps1'
    $cmdOk = Test-Path $cmdShim
    $ps1Ok = Test-Path $ps1Shim
    $shimParts = @()
    if ($cmdOk) { $shimParts += 'windots.cmd' }
    if ($ps1Ok) { $shimParts += 'windots.ps1' }
    $windotsOk = $cmdOk
    $checks.Add([pscustomobject]@{
            Item   = msg 'doctor.windots.name'
            Status = if ($windotsOk) { 'OK' } else { 'WARN' }
            Detail = if ($windotsOk) { "$localBin ($($shimParts -join ', '))" } else { msg 'doctor.windots.missing' }
        })

    $settings = Import-PowerShellDataFile -Path (Join-Path $RepoRoot 'settings.psd1')
    $statePath = Resolve-RepoPath -RepoRoot $RepoRoot -Value $settings.Paths.State
    $stateOk = Test-Path $statePath
    $checks.Add([pscustomobject]@{
            Item   = msg 'doctor.state.name'
            Status = if ($stateOk) { 'OK' } else { 'INFO' }
            Detail = if ($stateOk) { $statePath } else { msg 'doctor.state.missing' }
        })

    # --- Persist 漂移检查（需要 state + packages；仅对选中且 Dotfiles 含 SCOOP_PATH 的包） ---
    $doctorState = $State
    if ($null -eq $doctorState -and $stateOk) {
        try { $doctorState = Import-PowerShellDataFile -Path $statePath } catch { $doctorState = $null }
    }
    $doctorPkg = $PackagesDef
    if ($null -eq $doctorPkg) {
        try { $doctorPkg = Import-PowerShellDataFile -Path (Join-Path $RepoRoot 'packages.psd1') } catch { $doctorPkg = $null }
    }
    if ($null -ne $doctorState -and $null -ne $doctorPkg) {
        $userRoot = Get-ScoopUserRoot
        $globalRoot = Get-ScoopGlobalRoot
        foreach ($item in (Get-SelectedPackageItems -State $doctorState -PackagesDef $doctorPkg)) {
            if (-not $item.Contains('Dotfiles') -or $null -eq $item.Dotfiles) { continue }
            $hasScoopPath = $false
            foreach ($dot in @($item.Dotfiles)) {
                if ([string]$dot.Dest -like 'SCOOP_PATH*') { $hasScoopPath = $true; break }
            }
            if (-not $hasScoopPath) { continue }

            foreach ($d in (Get-PackagePersistDrift -PackagesDef $doctorPkg -PackageName ([string]$item.Name) -State $doctorState)) {
                if ($d.DualInstall) {
                    $checks.Add([pscustomobject]@{
                            Item   = msg 'doctor.persist.dual.name'
                            Status = 'WARN'
                            Detail = (msg 'doctor.persist.dual.detail' $d.App (Join-Path $userRoot "apps\$($d.App)") (Join-Path $globalRoot "apps\$($d.App)"))
                        })
                }
                if ($d.PersistDrift) {
                    $checks.Add([pscustomobject]@{
                            Item   = msg 'doctor.persist.empty.name'
                            Status = 'WARN'
                            Detail = (msg 'doctor.persist.empty.detail' $d.App $d.IntentPersist $d.OtherPersist)
                        })
                }
            }
        }
    }

    Write-Host ''
    foreach ($c in $checks) {
        $color = switch ($c.Status) {
            'OK' { [ConsoleColor]::Green }
            'WARN' { [ConsoleColor]::Yellow }
            'FAIL' { [ConsoleColor]::Red }
            default { [ConsoleColor]::Cyan }
        }
        Write-Host ("[{0,-4}] {1,-20} {2}" -f $c.Status, $c.Item, $c.Detail) -ForegroundColor $color
    }
    Write-Host ''
}
