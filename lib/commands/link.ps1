# =====================================================================
# Windots 配置链接重建 (lib/commands/link.ps1)
# =====================================================================

function Invoke-Link {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    Write-Step (msg 'link.title')

    $pkgLookup = if ($State.Contains('Selected_Packages') -and $null -ne $State.Selected_Packages) {
        $State.Selected_Packages
    }
    else {
        $State.Scoop_Apps
    }
    $allItems = @()
    foreach ($s in @($Ctx.Packages.Recommended) + @($Ctx.Packages.Optional.Dev) + @($Ctx.Packages.Optional.Term) + @($Ctx.Packages.Optional.Beauty)) {
        if ($pkgLookup -contains $s.Name) { $allItems += $s }
    }
    $extras = @($Ctx.Packages.Extras)
    $planned = Get-PlannedLinks -RepoRoot $Ctx.Root -SelectedItems $allItems -Extras $extras

    $resolvedLinkMode = Resolve-LinkMode -RequestedMode ([string]$State.Link_Mode) -WhatIf:$Ctx.WhatIf

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($link in $planned) {
        if (-not (Test-Path $link.Src)) {
            Write-Warn (msg 'link.src.skip' $link.Src)
            $results.Add([pscustomobject]@{ Label = $link.Label; Status = 'skipped'; Detail = msg 'link.src.skip' $link.Src })
            continue
        }
        $status = Apply-Config `
            -Src          $link.Src `
            -Dest         $link.Dest `
            -BackupRoot   $Ctx.BackupDir `
            -ConflictMode ([string]$State.Conflict_Mode) `
            -LinkMode     $resolvedLinkMode `
            -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{ Label = $link.Label; Status = $status; Detail = '' })
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}
