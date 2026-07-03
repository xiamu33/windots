# =====================================================================
# Windots Dotfiles 反向回收 (lib/commands/harvest.ps1)
# 把运行态 Dest 的最新内容复制回 dotfiles Src 入库文件，
# 用于捕获应用侧（如 Flow Launcher 原子写）断裂硬链接后的配置变更。
# 行为是 link 的反向：复用 Get-PlannedLinks 规划，逐条判定后 Dest→Src。
# =====================================================================

function Test-LinkIntact {
    param(
        [Parameter(Mandatory)][string] $Src,
        [Parameter(Mandatory)][string] $Dest
    )
    # 复用 Apply-Config 的幂等判定：symlink 指向 src / hardlink 同 NTFS fileid。
    $item = Get-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    $isSymlink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    if ($isSymlink) {
        $target = $item.Target
        if ($target -is [array]) { $target = $target[0] }
        try {
            $targetFull = [IO.Path]::GetFullPath($target)
            $srcFull    = [IO.Path]::GetFullPath($Src)
            return ($targetFull -eq $srcFull)
        }
        catch { return $false }
    }
    if (-not $item.PSIsContainer) {
        return (Test-SameNtfsFile -Path1 $Dest -Path2 $Src)
    }
    return $false
}

function Invoke-Harvest {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State,
        [string[]]                             $PackageNames = @()
    )

    Write-Step (msg 'harvest.title')

    $allItems = Get-SelectedPackageItems -State $State -PackagesDef $Ctx.Packages
    if ($PackageNames.Count -gt 0) {
        $wanted = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($n in $PackageNames) { [void]$wanted.Add([string]$n) }
        $filtered = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $allItems) {
            if ($wanted.Contains([string]$item.Name)) { [void]$filtered.Add($item) }
        }
        $allItems = @($filtered)
        $extras = @()
    }
    else {
        $extras = @($Ctx.Packages.Extras)
    }

    $planned = Get-PlannedLinks -RepoRoot $Ctx.Root -SelectedItems $allItems -Extras $extras -State $State -PackagesDef $Ctx.Packages

    $toHarvest = [System.Collections.Generic.List[object]]::new()
    $results   = [System.Collections.Generic.List[object]]::new()

    foreach ($link in $planned) {
        $src  = [string]$link.Src
        $dest = [string]$link.Dest
        $label = [string]$link.Label

        if (-not (Test-Path -LiteralPath $src)) {
            Write-Warn (msg 'harvest.skip.nodest' $src)
            $results.Add([pscustomobject]@{ Section='harvest'; Label=$label; Status='skipped'; Detail=(msg 'harvest.skip.nodest' $src) })
            continue
        }
        $srcItem = Get-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
        if ($srcItem -and $srcItem.PSIsContainer) {
            Write-Warn (msg 'harvest.skip.dir' $src)
            $results.Add([pscustomobject]@{ Section='harvest'; Label=$label; Status='skipped'; Detail=(msg 'harvest.skip.dir' $src) })
            continue
        }
        if (-not (Test-Path -LiteralPath $dest)) {
            Write-Warn (msg 'harvest.skip.nodest' $dest)
            $results.Add([pscustomobject]@{ Section='harvest'; Label=$label; Status='skipped'; Detail=(msg 'harvest.skip.nodest' $dest) })
            continue
        }
        if (Test-LinkIntact -Src $src -Dest $dest) {
            Write-Success (msg 'harvest.skip.linked' $dest)
            $results.Add([pscustomobject]@{ Section='harvest'; Label=$label; Status='skipped'; Detail=(msg 'harvest.skip.linked' $dest) })
            continue
        }
        $srcHash = (Get-FileHash -LiteralPath $src  -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        if ($srcHash -eq $dstHash) {
            Write-Info (msg 'harvest.skip.unchanged' $dest)
            $results.Add([pscustomobject]@{ Section='harvest'; Label=$label; Status='skipped'; Detail=(msg 'harvest.skip.unchanged' $dest) })
            continue
        }
        $toHarvest.Add([pscustomobject]@{ Src=$src; Dest=$dest; Label=$label })
    }

    if ($toHarvest.Count -eq 0) {
        Write-Info (msg 'harvest.nothing')
        Show-Summary -Results $results -LogFile $Ctx.LogFile
        return
    }

    if ($Ctx.WhatIf) {
        foreach ($h in $toHarvest) {
            Write-Plan (msg 'harvest.plan' $h.Dest $h.Src)
            $results.Add([pscustomobject]@{ Section='harvest'; Label=[string]$h.Label; Status='planned'; Detail=(msg 'harvest.plan' $h.Dest $h.Src) })
        }
        Show-Summary -Results $results -LogFile $Ctx.LogFile
        return
    }

    $yes = Read-YesNo -Prompt (msg 'harvest.confirm' $toHarvest.Count) -Default $true
    if (-not $yes) {
        Write-Info (msg 'harvest.nothing')
        Show-Summary -Results $results -LogFile $Ctx.LogFile
        return
    }

    foreach ($h in $toHarvest) {
        try {
            Copy-Item -LiteralPath $h.Dest -Destination $h.Src -Force
            Write-Success (msg 'harvest.done' $h.Dest $h.Src)
            $results.Add([pscustomobject]@{ Section='harvest'; Label=[string]$h.Label; Status='ok'; Detail=(msg 'harvest.done' $h.Dest $h.Src) })
        }
        catch {
            Write-Err (msg 'harvest.done' $h.Dest $h.Src)
            $results.Add([pscustomobject]@{ Section='harvest'; Label=[string]$h.Label; Status='failed'; Detail=[string]$_.Exception.Message })
        }
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}
