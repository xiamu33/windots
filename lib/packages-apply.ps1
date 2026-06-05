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

function Get-ScoopAppsToUninstall {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string[]] $RemovedPackageNames,
        [Parameter(Mandatory)][string[]] $RemainingPackageNames
    )

    if (@($RemovedPackageNames).Count -eq 0) { return @() }

    $stillNeeded = @{}
    foreach ($app in (Get-ScoopAppsForPackageNames -PackagesDef $PackagesDef -PackageNames $RemainingPackageNames)) {
        $stillNeeded[$app] = $true
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($item in Get-AllPackageItems -PackagesDef $PackagesDef) {
        if ($RemovedPackageNames -contains [string]$item.Name) {
            foreach ($app in Get-PackageItemScoopApps -PackageItem $item) {
                if (-not $candidates.Contains($app)) { $candidates.Add($app) }
            }
        }
    }

    return [string[]]@($candidates | Where-Object { -not $stillNeeded.ContainsKey($_) })
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
