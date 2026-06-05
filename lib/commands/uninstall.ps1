# =====================================================================
# Windots 包卸载流程 (lib/commands/uninstall.ps1)
# =====================================================================

function Uninstall-WindotsScoopApps {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $AppNames,
        [Parameter(Mandatory)]                 $Results,
        [string]                               $StepKey = 'uninstall.step.packages'
    )

    if (@($AppNames).Count -eq 0) { return }

    Write-Step (msg $StepKey)
    foreach ($name in $AppNames) {
        $appResult = Uninstall-ScoopApp -Name $name -WhatIf:$Ctx.WhatIf
        $pkgItem = Find-PackageItemByScoopName -PackagesDef $Ctx.Packages -ScoopName ([string]$name)
        $desc = if ($pkgItem) { Get-PackageDesc -Package $pkgItem } else { '' }
        $Results.Add([pscustomobject]@{
                Section = 'packages'
                Label   = Get-ScoopAppBaseName -Name ([string]$name)
                Desc    = $desc
                Status  = [string]$appResult.Status
                Detail  = [string]$appResult.Detail
            })
    }
}

function Invoke-Uninstall {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    $plan = Invoke-InteractivePackagesUninstall -Ctx $Ctx -State $State
    if (@($plan.RemovedPackages).Count -eq 0) {
        Write-Info (msg 'uninstall.nothing.todo')
        return
    }

    $results = [System.Collections.Generic.List[object]]::new()
    Set-WindotsSessionProxy -State $plan.State
    Uninstall-WindotsScoopApps -Ctx $Ctx -AppNames ([string[]]@($plan.ScoopAppsToUninstall | ForEach-Object { [string]$_ })) -Results $results

    Show-Summary -Results $results -LogFile $Ctx.LogFile -Mode 'uninstall'
}
