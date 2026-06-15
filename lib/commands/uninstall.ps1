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
        $pkgItem = Find-PackageItemByScoopName -PackagesDef $Ctx.Packages -ScoopName ([string]$name)
        $scope = Get-ScoopAppInstalledScope -Name ([string]$name)
        $global = ($scope -eq 'global')
        if ($null -eq $scope -and $pkgItem) {
            $global = Get-PackageInstallGlobal -PackagesDef $Ctx.Packages -PackageName ([string]$pkgItem.Name)
        }
        $appResult = Uninstall-ScoopApp -Name $name -GlobalInstall:$global -WhatIf:$Ctx.WhatIf
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

function Add-UninstallBlockedResults {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $Results,
        [Parameter(Mandatory)]                 $BlockedApps
    )

    foreach ($blocked in @($BlockedApps)) {
        $appName = [string]$blocked.App
        $pkgItem = Find-PackageItemByScoopName -PackagesDef $Ctx.Packages -ScoopName $appName
        $desc = if ($pkgItem) { Get-PackageDesc -Package $pkgItem } else { '' }
        $Results.Add([pscustomobject]@{
                Section = 'packages'
                Label   = Get-ScoopAppBaseName -Name $appName
                Desc    = $desc
                Status  = 'skipped'
                Detail  = (msg 'summary.detail.app.uninstall.blocked' ($blocked.RequiredBy -join ', '))
            })
    }
}

function Invoke-Uninstall {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    $plan = Invoke-InteractivePackagesUninstall -Ctx $Ctx -State $State
    if (@($plan.ScoopAppsToUninstall).Count -eq 0 -and @($plan.BlockedApps).Count -eq 0) {
        Write-Info (msg 'uninstall.nothing.todo')
        return
    }

    $results = [System.Collections.Generic.List[object]]::new()
    Set-WindotsSessionProxy -State $plan.State
    Add-UninstallBlockedResults -Ctx $Ctx -Results $results -BlockedApps @($plan.BlockedApps)
    Uninstall-WindotsScoopApps -Ctx $Ctx -AppNames ([string[]]@($plan.ScoopAppsToUninstall | ForEach-Object { [string]$_ })) -Results $results

    $actuallyRemoved = Update-WindotsUninstallState -State $plan.State -PackagesDef $Ctx.Packages `
        -BaseSelectedPackages $plan.SavedSelected `
        -CandidatePackageNames $plan.PackagesPlannedForRemoval `
        -AppsToUninstall @($plan.ScoopAppsToUninstall | ForEach-Object { [string]$_ }) `
        -UninstallResults @($results)

    if (-not $Ctx.WhatIf -and @($actuallyRemoved).Count -gt 0) {
        Save-WindotsState -Path $Ctx.StatePath -State $plan.State
        Write-Success (msg 'interactive.state.saved' $Ctx.StatePath)
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile -Mode 'uninstall'
}
