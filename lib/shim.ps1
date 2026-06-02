# =====================================================================
# Windots 全局命令注册 (lib/shim.ps1)
# =====================================================================

function Register-WindotsShim {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [switch] $WhatIf
    )

    $shimSrc = Join-Path $RepoRoot 'bin\windots.cmd'
    $localBin = Join-Path $HOME '.local\bin'
    $shimDest = Join-Path $localBin 'windots.cmd'

    if (-not (Test-Path $shimSrc)) {
        Write-Warn (msg 'shim.notfound' $shimSrc)
        return
    }

    if ($WhatIf) {
        Write-Plan "[WhatIf] $(msg 'shim.copied' $shimDest)"
        Write-Plan "[WhatIf] $(msg 'shim.path.added' $localBin)"
        return
    }

    if (-not (Test-Path $localBin)) {
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    }

    Copy-Item -Path $shimSrc -Destination $shimDest -Force
    Write-Success (msg 'shim.copied' $shimDest)

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
