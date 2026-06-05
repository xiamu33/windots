# =====================================================================
# Windots 包选择与安装共享逻辑 (lib/packages-apply.ps1)
# =====================================================================

function Get-SelectedPackageItems {
    param(
        [Parameter(Mandatory)]                 $State,
        [Parameter(Mandatory)][hashtable]      $PackagesDef
    )

    $pkgLookup = if ($State.Contains('Selected_Packages') -and $null -ne $State.Selected_Packages) {
        $State.Selected_Packages
    }
    else {
        $State.Scoop_Apps
    }
    $allItems = @()
    foreach ($s in @($PackagesDef.Recommended) + @($PackagesDef.Optional.Dev) + @($PackagesDef.Optional.Term) + @($PackagesDef.Optional.Beauty)) {
        if ($pkgLookup -contains $s.Name) { $allItems += $s }
    }
    return @($allItems)
}

function Get-PackageItemScoopApps {
    param([Parameter(Mandatory)] $PackageItem)

    if ($PackageItem.Contains('Packages') -and $null -ne $PackageItem.Packages) {
        return @($PackageItem.Packages | ForEach-Object { [string]$_ })
    }
    return @([string]$PackageItem.Name)
}

function Get-AllPackageItems {
    param([Parameter(Mandatory)][hashtable] $PackagesDef)

    return @(
        @($PackagesDef.Recommended) + @($PackagesDef.Optional.Dev) + @($PackagesDef.Optional.Term) + @($PackagesDef.Optional.Beauty)
    )
}

function Get-ScoopAppsForPackageNames {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string[]] $PackageNames
    )

    $apps = [System.Collections.Generic.List[string]]::new()
    foreach ($item in Get-AllPackageItems -PackagesDef $PackagesDef) {
        if ($PackageNames -contains [string]$item.Name) {
            foreach ($app in Get-PackageItemScoopApps -PackageItem $item) {
                if (-not $apps.Contains($app)) { $apps.Add($app) }
            }
        }
    }
    return [string[]]@($apps)
}

function Get-PackagesPlannedForRemoval {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $RemovedPackageNames,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $AppsToUninstall
    )

    $appsSet = @{}
    foreach ($app in @($AppsToUninstall)) { $appsSet[$app] = $true }

    $planned = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($RemovedPackageNames)) {
        $pkgApps = Get-ScoopAppsForPackageNames -PackagesDef $PackagesDef -PackageNames @([string]$name)
        foreach ($app in $pkgApps) {
            if ($appsSet.ContainsKey($app)) {
                $planned.Add([string]$name)
                break
            }
        }
    }
    return [string[]]@($planned)
}

function Get-PackagesActuallyUninstalled {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $CandidatePackageNames,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $AppsToUninstall,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                               $UninstallResults
    )

    $appsSet = @{}
    foreach ($app in @($AppsToUninstall)) { $appsSet[$app] = $true }

    $resultByLabel = @{}
    foreach ($r in @($UninstallResults)) {
        if ([string]$r.Section -ne 'packages') { continue }
        $resultByLabel[[string]$r.Label] = [string]$r.Status
    }

    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($CandidatePackageNames)) {
        $pkgApps = Get-ScoopAppsForPackageNames -PackagesDef $PackagesDef -PackageNames @([string]$name)
        $attempted = 0
        $succeeded = $true
        foreach ($app in $pkgApps) {
            if (-not $appsSet.ContainsKey($app)) { continue }
            $label = Get-ScoopAppBaseName -Name ([string]$app)
            if (-not $resultByLabel.ContainsKey($label)) { continue }
            $attempted++
            if ($resultByLabel[$label] -eq 'failed') {
                $succeeded = $false
                break
            }
        }
        if ($succeeded -and $attempted -gt 0) {
            $removed.Add([string]$name)
        }
    }
    return [string[]]@($removed)
}

function Update-WindotsUninstallState {
    param(
        [Parameter(Mandatory)]                 $State,
        [Parameter(Mandatory)][hashtable]      $PackagesDef,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $BaseSelectedPackages,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $CandidatePackageNames,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $AppsToUninstall,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                               $UninstallResults
    )

    $removed = Get-PackagesActuallyUninstalled -PackagesDef $PackagesDef `
        -CandidatePackageNames $CandidatePackageNames `
        -AppsToUninstall $AppsToUninstall `
        -UninstallResults $UninstallResults

    $finalRemaining = [System.Collections.Generic.List[string]]::new()
    foreach ($n in @($BaseSelectedPackages | ForEach-Object { [string]$_ })) {
        if ($removed -notcontains $n) {
            if (-not $finalRemaining.Contains($n)) { $finalRemaining.Add($n) }
        }
    }

    $State['Selected_Packages'] = [string[]]@($finalRemaining)
    $State['Scoop_Apps'] = Get-ScoopAppsForPackageNames -PackagesDef $PackagesDef -PackageNames $State['Selected_Packages']
    $State['Timestamp'] = (Get-Date).ToString('s')
    return [string[]]@($removed)
}

function Get-UninstallScoopPlan {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string[]] $RemovedPackageNames,
        [Parameter(Mandatory)][string[]] $RemainingPackageNames
    )

    if (@($RemovedPackageNames).Count -eq 0) {
        return [pscustomobject]@{
            ScoopAppsToUninstall = [string[]]@()
            BlockedApps          = @()
        }
    }

    $appRequiredBy = @{}
    foreach ($item in Get-AllPackageItems -PackagesDef $PackagesDef) {
        if ($RemainingPackageNames -notcontains [string]$item.Name) { continue }
        foreach ($app in Get-PackageItemScoopApps -PackageItem $item) {
            if (-not $appRequiredBy.ContainsKey($app)) {
                $appRequiredBy[$app] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            }
            [void]$appRequiredBy[$app].Add([string]$item.Name)
        }
    }

    $toUninstall = [System.Collections.Generic.List[string]]::new()
    $blocked = [System.Collections.Generic.List[object]]::new()

    foreach ($item in Get-AllPackageItems -PackagesDef $PackagesDef) {
        if ($RemovedPackageNames -notcontains [string]$item.Name) { continue }
        foreach ($app in Get-PackageItemScoopApps -PackageItem $item) {
            if ($appRequiredBy.ContainsKey($app)) {
                $blocked.Add([pscustomobject]@{
                        PackageName = [string]$item.Name
                        App         = [string]$app
                        RequiredBy  = [string[]]@($appRequiredBy[$app] | Sort-Object)
                    })
            }
            elseif (-not $toUninstall.Contains($app)) {
                $toUninstall.Add($app)
            }
        }
    }

    $blockedDeduped = [System.Collections.Generic.List[object]]::new()
    $blockedSeen = @{}
    foreach ($entry in $blocked) {
        $key = [string]$entry.App
        if ($blockedSeen.ContainsKey($key)) { continue }
        $blockedSeen[$key] = $true
        $requiredBy = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($other in $blocked) {
            if ([string]$other.App -ieq $key) {
                foreach ($p in @($other.RequiredBy)) { [void]$requiredBy.Add([string]$p) }
            }
        }
        $blockedDeduped.Add([pscustomobject]@{
                App        = $key
                RequiredBy = [string[]]@($requiredBy | Sort-Object)
            })
    }

    return [pscustomobject]@{
        ScoopAppsToUninstall = [string[]]@($toUninstall)
        BlockedApps          = @($blockedDeduped)
    }
}

function Get-ScoopAppsToUninstall {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string[]] $RemovedPackageNames,
        [Parameter(Mandatory)][string[]] $RemainingPackageNames
    )

    return (Get-UninstallScoopPlan -PackagesDef $PackagesDef `
            -RemovedPackageNames $RemovedPackageNames `
            -RemainingPackageNames $RemainingPackageNames).ScoopAppsToUninstall
}

function Get-PackagesActuallyInstalled {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $CandidatePackageNames,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                               $InstallResults
    )

    $resultByLabel = @{}
    foreach ($r in @($InstallResults)) {
        if ([string]$r.Section -ne 'packages') { continue }
        $resultByLabel[[string]$r.Label] = [string]$r.Status
    }

    $installed = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($CandidatePackageNames)) {
        $pkgApps = Get-ScoopAppsForPackageNames -PackagesDef $PackagesDef -PackageNames @([string]$name)
        $attempted = 0
        $succeeded = $true
        foreach ($app in $pkgApps) {
            $label = Get-ScoopAppBaseName -Name ([string]$app)
            if (-not $resultByLabel.ContainsKey($label)) { continue }
            $attempted++
            if ($resultByLabel[$label] -eq 'failed') {
                $succeeded = $false
                break
            }
        }
        if ($succeeded -and $attempted -gt 0) {
            $installed.Add([string]$name)
        }
    }
    return [string[]]@($installed)
}

function Update-WindotsInstallState {
    param(
        [Parameter(Mandatory)]                 $State,
        [Parameter(Mandatory)][hashtable]      $PackagesDef,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $BaseSelectedPackages,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $CandidatePackageNames,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                               $InstallResults
    )

    $added = Get-PackagesActuallyInstalled -PackagesDef $PackagesDef `
        -CandidatePackageNames $CandidatePackageNames -InstallResults $InstallResults

    $finalSelected = [System.Collections.Generic.List[string]]::new()
    foreach ($n in @($BaseSelectedPackages | ForEach-Object { [string]$_ })) {
        if (-not $finalSelected.Contains($n)) { $finalSelected.Add($n) }
    }
    foreach ($n in @($added)) {
        if (-not $finalSelected.Contains($n)) { $finalSelected.Add($n) }
    }

    $State['Selected_Packages'] = [string[]]@($finalSelected)
    $State['Scoop_Apps'] = Get-ScoopAppsForPackageNames -PackagesDef $PackagesDef -PackageNames $State['Selected_Packages']
    $State['Timestamp'] = (Get-Date).ToString('s')
}

function Set-WindotsSessionProxy {
    param([Parameter(Mandatory)] $State)

    if ($State.Proxy_Enabled -and -not [string]::IsNullOrWhiteSpace($State.Proxy_Url)) {
        Set-SessionProxy -Url ([string]$State.Proxy_Url)
    }
    else {
        Set-SessionProxy -Url ''
    }
}

function Install-WindotsScoopApps {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State,
        [Parameter(Mandatory)]                 $Results,
        [string]                               $StepKey = 'init.step.packages'
    )

    Write-Step (msg $StepKey)
    foreach ($name in $State.Scoop_Apps) {
        $appResult = Install-ScoopApp -Name $name -WhatIf:$Ctx.WhatIf
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

function Apply-WindotsDotfiles {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State,
        [Parameter(Mandatory)]                 $Results,
        [string]                               $StepKey = 'init.step.config',
        [string]                               $SrcSkipKey = 'init.config.src.skip'
    )

    Write-Step (msg $StepKey)
    $allItems = Get-SelectedPackageItems -State $State -PackagesDef $Ctx.Packages
    $extras = @($Ctx.Packages.Extras)
    $planned = Get-PlannedLinks -RepoRoot $Ctx.Root -SelectedItems $allItems -Extras $extras

    $resolvedLinkMode = Resolve-LinkMode -RequestedMode ([string]$State.Link_Mode) -WhatIf:$Ctx.WhatIf

    foreach ($link in $planned) {
        if (-not (Test-Path $link.Src)) {
            Write-Warn (msg $SrcSkipKey $link.Src)
            $Results.Add([pscustomobject]@{
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
        $Results.Add([pscustomobject]@{
                Section = 'config'
                Label   = [string]$link.Label
                Status  = [string]$applyResult.Status
                Detail  = [string]$applyResult.Detail
            })
    }
}
