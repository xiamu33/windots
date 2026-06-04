# =====================================================================
# Windots 全局命令注册 (lib/shim.ps1)
# =====================================================================

function Register-WindotsShim {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [switch] $WhatIf
    )

    $ps1Src = Join-Path $RepoRoot 'bin\windots.ps1'
    $cmdSrc = Join-Path $RepoRoot 'bin\windots.cmd'
    $localBin = Join-Path $HOME '.local\bin'
    $ps1Dest = Join-Path $localBin 'windots.ps1'
    $cmdDest = Join-Path $localBin 'windots.cmd'

    if (-not (Test-Path $ps1Src)) {
        Write-Warn (msg 'shim.notfound' $ps1Src)
        return
    }
    if (-not (Test-Path $cmdSrc)) {
        Write-Warn (msg 'shim.notfound' $cmdSrc)
        return
    }

    if ($WhatIf) {
        Write-Plan "[WhatIf] $(msg 'shim.copied' $ps1Dest)"
        Write-Plan "[WhatIf] $(msg 'shim.cmd.copied' $cmdDest)"
        Write-Plan "[WhatIf] $(msg 'shim.path.added' $localBin)"
        return
    }

    if (-not (Test-Path $localBin)) {
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    }

    Copy-Item -Path $ps1Src -Destination $ps1Dest -Force
    Write-Success (msg 'shim.copied' $ps1Dest)

    Copy-Item -Path $cmdSrc -Destination $cmdDest -Force
    Write-Success (msg 'shim.cmd.copied' $cmdDest)

    $currentUserPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if ($currentUserPath -notlike "*$localBin*") {
        $newPath = if ([string]::IsNullOrEmpty($currentUserPath)) { $localBin } else { "$currentUserPath;$localBin" }
        [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $env:Path = $env:Path + ";$localBin"
        Write-Success (msg 'shim.path.added' $localBin)
        Write-Warn    (msg 'shim.path.reopen')
    }
    else {
        Write-Success (msg 'shim.available')
    }
}
