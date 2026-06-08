# =====================================================================
# Windots 清理缓存 (lib/commands/clean.ps1)
# =====================================================================

function Remove-WindotsDirectoryContents {
    param(
        [Parameter(Mandatory)][string] $Path,
        [switch]                       $WhatIf
    )

    if (-not (Test-Path $Path)) { return 0 }

    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    if ($items.Count -eq 0) { return 0 }

    if ($WhatIf) {
        Write-Plan "[WhatIf] Remove-Item -Recurse -Force '$Path\*'"
        return $items.Count
    }

    foreach ($item in $items) {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
    return $items.Count
}

function Remove-WindotsBackupExceptLatest {
    param(
        [Parameter(Mandatory)][string] $Path,
        [switch]                       $WhatIf
    )

    $empty = @{ Removed = 0; Kept = $null }
    if (-not (Test-Path $Path)) { return $empty }

    $dirs = @(Get-ChildItem -LiteralPath $Path -Force -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) { return $empty }

    $sorted = $dirs | Sort-Object Name -Descending
    $kept = $sorted[0]
    $toRemove = @($sorted | Select-Object -Skip 1)
    if ($toRemove.Count -eq 0) {
        return @{ Removed = 0; Kept = $kept.Name }
    }

    if ($WhatIf) {
        foreach ($item in $toRemove) {
            Write-Plan "[WhatIf] Remove-Item -Recurse -Force '$($item.FullName)'"
        }
    }
    else {
        foreach ($item in $toRemove) {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        }
    }
    return @{ Removed = $toRemove.Count; Kept = $kept.Name }
}

function Invoke-Clean {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [switch]                               $All
    )

    Write-Step (msg 'clean.title')

    $logsDir = Split-Path -Parent $Ctx.LogFile
    $backupDir = $Ctx.BackupDir

    $logsRemoved = Remove-WindotsDirectoryContents -Path $logsDir -WhatIf:$Ctx.WhatIf
    if ($logsRemoved -gt 0) {
        if ($Ctx.WhatIf) { Write-Plan (msg 'clean.logs.done' $logsRemoved) }
        else { Write-Success (msg 'clean.logs.done' $logsRemoved) }
    }
    else {
        Write-Info (msg 'clean.logs.empty')
    }

    if ($All) {
        $backupRemoved = Remove-WindotsDirectoryContents -Path $backupDir -WhatIf:$Ctx.WhatIf
        if ($backupRemoved -gt 0) {
            if ($Ctx.WhatIf) { Write-Plan (msg 'clean.backup.done' $backupRemoved) }
            else { Write-Success (msg 'clean.backup.done' $backupRemoved) }
        }
        else {
            Write-Info (msg 'clean.backup.empty')
        }
    }
    else {
        $backupResult = Remove-WindotsBackupExceptLatest -Path $backupDir -WhatIf:$Ctx.WhatIf
        if ($backupResult.Removed -gt 0) {
            if ($Ctx.WhatIf) { Write-Plan (msg 'clean.backup.pruned' $backupResult.Removed $backupResult.Kept) }
            else { Write-Success (msg 'clean.backup.pruned' $backupResult.Removed $backupResult.Kept) }
        }
        elseif ($backupResult.Kept) {
            Write-Info (msg 'clean.backup.kept' $backupResult.Kept)
        }
        else {
            Write-Info (msg 'clean.backup.empty')
        }
    }

    if ($All) {
        if (Test-Path $Ctx.StatePath) {
            if ($Ctx.WhatIf) {
                Write-Plan "[WhatIf] Remove-Item '$($Ctx.StatePath)'"
            }
            else {
                Remove-Item -LiteralPath $Ctx.StatePath -Force
                Write-Success (msg 'clean.state.done' $Ctx.StatePath)
            }
        }
        else {
            Write-Info (msg 'clean.state.missing')
        }
    }
    else {
        Write-Info (msg 'clean.state.hint')
    }
}
