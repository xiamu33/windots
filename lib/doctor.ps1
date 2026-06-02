# =====================================================================
# Windots Doctor (lib/doctor.ps1)
# =====================================================================

function Invoke-Doctor {
    param([Parameter(Mandatory)][string] $RepoRoot)

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
    $windotsOk = Test-Path (Join-Path $localBin 'windots.cmd')
    $checks.Add([pscustomobject]@{
            Item   = msg 'doctor.windots.name'
            Status = if ($windotsOk) { 'OK' } else { 'WARN' }
            Detail = if ($windotsOk) { $localBin } else { msg 'doctor.windots.missing' }
        })

    $settings = Import-PowerShellDataFile -Path (Join-Path $RepoRoot 'settings.psd1')
    $statePath = Resolve-RepoPath -RepoRoot $RepoRoot -Value $settings.Paths.State
    $stateOk = Test-Path $statePath
    $checks.Add([pscustomobject]@{
            Item   = msg 'doctor.state.name'
            Status = if ($stateOk) { 'OK' } else { 'INFO' }
            Detail = if ($stateOk) { $statePath } else { msg 'doctor.state.missing' }
        })

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
