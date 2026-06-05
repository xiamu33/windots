# =====================================================================
# Windots 全局命令注册 (lib/shim.ps1)
# =====================================================================

function Convert-FsutilListedPath {
    param([Parameter(Mandatory)][string] $Path)

    $p = $Path.Trim()
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    if ($p.StartsWith('\\?\')) { return [IO.Path]::GetFullPath($p.Substring(4)) }
    if ($p.StartsWith('\') -and -not $p.StartsWith('\\')) {
        return [IO.Path]::GetFullPath("$($env:SystemDrive)$p")
    }
    return [IO.Path]::GetFullPath($p)
}

function Get-HardLinkPaths {
    param([Parameter(Mandatory)][string] $Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    try {
        $lines = & fsutil hardlink list $resolved 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $lines) { return @($resolved) }
        return @($lines | ForEach-Object { Convert-FsutilListedPath ([string]$_) } | Select-Object -Unique)
    }
    catch {
        return @($resolved)
    }
}

function Test-HardLinkPeer {
    param(
        [Parameter(Mandatory)][string] $Src,
        [Parameter(Mandatory)][string] $Dest
    )

    if (-not (Test-Path -LiteralPath $Dest)) { return $false }
    $destPath = (Resolve-Path -LiteralPath $Dest).Path
    return ((Get-HardLinkPaths -Path $Src) -contains $destPath)
}

function Install-WindotsShimFile {
    param(
        [Parameter(Mandatory)][string] $Src,
        [Parameter(Mandatory)][string] $Dest,
        [Parameter(Mandatory)][string] $LinkedKey,
        [Parameter(Mandatory)][string] $SkipKey,
        [switch] $WhatIf
    )

    if ($WhatIf) {
        Write-Plan "[WhatIf] $(msg $LinkedKey $Dest)"
        return
    }

    if (Test-HardLinkPeer -Src $Src -Dest $Dest) {
        Write-Info (msg $SkipKey $Dest)
        return
    }

    if (Test-Path -LiteralPath $Dest) {
        Remove-Item -LiteralPath $Dest -Force
    }

    try {
        New-Item -ItemType HardLink -Path $Dest -Target $Src -Force | Out-Null
        Write-Success (msg $LinkedKey $Dest)
    }
    catch {
        Copy-Item -Path $Src -Destination $Dest -Force
        Write-Warn (msg 'shim.hardlink.fallback' $Dest $_.Exception.Message)
        Write-Success (msg $LinkedKey $Dest)
    }
}

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
        Install-WindotsShimFile -Src $ps1Src -Dest $ps1Dest -LinkedKey 'shim.linked' -SkipKey 'shim.skip' -WhatIf
        Install-WindotsShimFile -Src $cmdSrc -Dest $cmdDest -LinkedKey 'shim.cmd.linked' -SkipKey 'shim.skip' -WhatIf
        Write-Plan "[WhatIf] $(msg 'shim.path.added' $localBin)"
        return
    }

    if (-not (Test-Path $localBin)) {
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    }

    Install-WindotsShimFile -Src $ps1Src -Dest $ps1Dest -LinkedKey 'shim.linked' -SkipKey 'shim.skip'
    Install-WindotsShimFile -Src $cmdSrc -Dest $cmdDest -LinkedKey 'shim.cmd.linked' -SkipKey 'shim.skip'

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
