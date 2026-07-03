# =====================================================================
# Windots 配置链接重建 (lib/commands/link.ps1)
# =====================================================================

function Invoke-Link {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    Write-Step (msg 'link.title')

    $allItems = Get-SelectedPackageItems -State $State -PackagesDef $Ctx.Packages
    $extras = @($Ctx.Packages.Extras)
    $planned = Get-PlannedLinks -RepoRoot $Ctx.Root -SelectedItems $allItems -Extras $extras -State $State -PackagesDef $Ctx.Packages

    $resolvedLinkMode = Resolve-LinkMode -RequestedMode ([string]$State.Link_Mode) -WhatIf:$Ctx.WhatIf

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($link in $planned) {
        if (-not (Test-Path $link.Src)) {
            Write-Warn (msg 'link.src.skip' $link.Src)
            $results.Add([pscustomobject]@{
                    Section = 'config'
                    Label   = [string]$link.Label
                    Status  = 'skipped'
                    Detail  = (msg 'summary.detail.config.missing')
                })
            continue
        }
        $applyResult = Apply-Config `
            -Src          $link.Src `
            -Dest         $link.Dest `
            -BackupRoot   $Ctx.BackupDir `
            -ConflictMode ([string]$State.Conflict_Mode) `
            -LinkMode     $resolvedLinkMode `
            -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{
                Section = 'config'
                Label   = [string]$link.Label
                Status  = [string]$applyResult.Status
                Detail  = [string]$applyResult.Detail
            })
    }

    $glazeBuild = Join-Path $env:USERPROFILE '.glzr\glazewm\build-toggle-win-maximize.ps1'
    if ((Test-Path $glazeBuild) -and -not $Ctx.WhatIf) {
        try { & $glazeBuild | Out-Null } catch { Write-Warn $_.Exception.Message }
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}
