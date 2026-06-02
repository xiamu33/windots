# =====================================================================
# Windots 配置应用 (lib/links.ps1)
# =====================================================================

function Get-PlannedLinks {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [object[]] $SelectedItems = @(),
        [object[]] $Extras = @()
    )
    $links = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $SelectedItems) {
        if ((-not $item.Contains('Dotfiles')) -or ($null -eq $item.Dotfiles)) { continue }
        $dotfilesList = @($item.Dotfiles)
        foreach ($dot in $dotfilesList) {
            if ($null -eq $dot) { continue }
            $src = Resolve-RepoPath -RepoRoot $RepoRoot -Value ([string]$dot.Src)
            $dest = Resolve-DestPath -Dest ([string]$dot.Dest)
            $links.Add([pscustomobject]@{ Src = $src; Dest = $dest; Label = $item.Name })
        }
    }

    foreach ($extra in $Extras) {
        $src = Resolve-RepoPath -RepoRoot $RepoRoot -Value ([string]$extra.Src)
        $dest = Resolve-DestPath -Dest ([string]$extra.Dest)
        $links.Add([pscustomobject]@{ Src = $src; Dest = $dest; Label = (Split-Path $src -Leaf) })
    }

    return @($links)
}

function Get-NtfsFileIdentity {
    param([Parameter(Mandatory)][string] $Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer) { return $null }
    try {
        $lines = @(& fsutil.exe file queryfileid $item.FullName 2>&1)
        $joined = ($lines | ForEach-Object { [string]$_ }) -join ' '
        if ($joined -match '(0x[0-9a-fA-F]+)') {
            $vol = $item.Directory.Root.FullName.TrimEnd('\')
            return "$vol|$($matches[1].ToLower())"
        }
    }
    catch { }
    return $null
}

function Test-SameNtfsFile {
    param(
        [Parameter(Mandatory)][string] $Path1,
        [Parameter(Mandatory)][string] $Path2
    )
    if (-not ((Test-Path -LiteralPath $Path1) -and (Test-Path -LiteralPath $Path2))) { return $false }
    try {
        $full1 = [IO.Path]::GetFullPath($Path1)
        $full2 = [IO.Path]::GetFullPath($Path2)
        if ($full1 -eq $full2) { return $true }
    }
    catch { return $false }
    $id1 = Get-NtfsFileIdentity -Path $Path1
    $id2 = Get-NtfsFileIdentity -Path $Path2
    return ($null -ne $id1) -and ($id1 -eq $id2)
}

function Set-ConfigFileLink {
    param(
        [Parameter(Mandatory)][string] $Src,
        [Parameter(Mandatory)][string] $Dest,
        [Parameter(Mandatory)][string] $LinkMode
    )
    $srcItem = Get-Item -LiteralPath $Src -Force
    $tryModes = @()

    switch ($LinkMode) {
        'hardlink' {
            if (-not $srcItem.PSIsContainer) { $tryModes += 'hardlink' }
            else { Write-Warn (msg 'links.dir.no.hardlink' $Dest) }
            $tryModes += 'symlink'
            $tryModes += 'copy'
        }
        'symlink' { $tryModes += 'symlink' }
        default { $tryModes += 'copy' }
    }

    foreach ($mode in $tryModes) {
        if ($mode -eq 'hardlink') {
            try {
                New-Item -ItemType HardLink -Path $Dest -Target $Src -Force | Out-Null
                Write-Success (msg 'links.hardlink.ok' $Dest $Src)
                return 'ok'
            }
            catch {
                Write-Warn (msg 'links.hardlink.fail' $_.Exception.Message)
            }
            continue
        }
        if ($mode -eq 'symlink') {
            try {
                New-Item -ItemType SymbolicLink -Path $Dest -Target $Src -Force | Out-Null
                Write-Success (msg 'links.symlink.ok' $Dest $Src)
                return 'ok'
            }
            catch {
                if ($LinkMode -eq 'hardlink') {
                    Write-Warn (msg 'links.symlink.fail.fallback' $_.Exception.Message)
                }
                else {
                    Write-Err (msg 'links.symlink.fail' $Dest $_.Exception.Message)
                    return 'failed'
                }
            }
            continue
        }
        # copy
        try {
            if ($srcItem.PSIsContainer) {
                Copy-Item -Path $Src -Destination $Dest -Recurse -Force
            }
            else {
                Copy-Item -Path $Src -Destination $Dest -Force
            }
            Write-Success (msg 'links.copy.ok' $Dest $Src)
            return 'ok'
        }
        catch {
            Write-Err (msg 'links.copy.fail' $Dest $_.Exception.Message)
            return 'failed'
        }
    }

    return 'failed'
}

function Resolve-LinkMode {
    param(
        [string] $RequestedMode = 'hardlink',
        [switch] $WhatIf
    )
    if ($WhatIf -or $RequestedMode -eq 'copy' -or $RequestedMode -eq 'hardlink') { return $RequestedMode }
    if ($RequestedMode -ne 'symlink') { return $RequestedMode }

    if ((Test-DeveloperMode) -or (Test-IsAdministrator)) { return 'symlink' }

    Clear-Host
    Write-Warn (msg 'links.symlink.devmode.title')
    Write-Info (msg 'links.symlink.devmode.guide1')
    Write-Info (msg 'links.symlink.devmode.guide2')
    Write-Host ''

    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'R' -or $key.KeyChar -eq 'r') {
            if (Test-DeveloperMode) {
                Write-Success (msg 'links.symlink.devmode.ok')
                return 'symlink'
            }
            Write-Warn (msg 'links.symlink.devmode.retry')
        }
        elseif ($key.Key -eq 'C' -or $key.KeyChar -eq 'c') {
            Write-Info (msg 'links.symlink.copy.chosen')
            return 'copy'
        }
    }
}

function Apply-Config {
    param(
        [Parameter(Mandatory)][string] $Src,
        [Parameter(Mandatory)][string] $Dest,
        [Parameter(Mandatory)][string] $BackupRoot,
        [string] $ConflictMode = 'overwrite',
        [string] $LinkMode = 'hardlink',
        [switch] $WhatIf
    )

    if (-not (Test-Path $Src)) {
        Write-Warn (msg 'links.src.missing' $Src)
        return 'skipped'
    }

    if (Test-Path $Dest -ErrorAction SilentlyContinue) {
        $item = Get-Item $Dest -Force -ErrorAction SilentlyContinue
        if ($item) {
            $isSymlink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ($isSymlink) {
                $target = $item.Target
                if ($target -is [array]) { $target = $target[0] }
                try {
                    $targetFull = [IO.Path]::GetFullPath($target)
                    $srcFull = [IO.Path]::GetFullPath($Src)
                    if ($targetFull -eq $srcFull) {
                        Write-Success (msg 'links.dest.ok' $Dest)
                        return 'ok'
                    }
                }
                catch { }
            }
            elseif (-not $item.PSIsContainer) {
                if (Test-SameNtfsFile -Path1 $Dest -Path2 $Src) {
                    Write-Success (msg 'links.dest.hardlink.ok' $Dest)
                    return 'ok'
                }
            }
        }

        switch ($ConflictMode) {
            'keep' {
                Write-Warn (msg 'links.dest.keep' $Dest)
                return 'skipped'
            }
            'backup' {
                if ($WhatIf) { Write-Plan "[WhatIf] $(msg 'backup.file.bak' $Dest)" }
                else {
                    Backup-Path -Path $Dest -BackupRoot $BackupRoot | Out-Null
                    Remove-Item -Path $Dest -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            default {
                if ($WhatIf) { Write-Plan "[WhatIf] overwrite: $Dest" }
                else { Remove-Item -Path $Dest -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    $parent = Split-Path $Dest -Parent
    if ($parent -and -not (Test-Path $parent)) {
        if ($WhatIf) { Write-Plan "[WhatIf] New-Item Directory $parent" }
        else { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    }

    if ($WhatIf) {
        switch ($LinkMode) {
            'hardlink' { Write-Plan "[WhatIf] hardlink (fallback symlink→copy) '$Dest' ⇄ '$Src'" }
            'symlink' { Write-Plan "[WhatIf] New-Item SymbolicLink '$Dest' → '$Src'" }
            default { Write-Plan "[WhatIf] Copy-Item '$Src' → '$Dest'" }
        }
        return 'ok'
    }

    return Set-ConfigFileLink -Src $Src -Dest $Dest -LinkMode $LinkMode
}
