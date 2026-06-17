# =====================================================================
# Windots 包 scope 迁移 (lib/commands/migrate.ps1)
# user ↔ global 单包安装位置迁移
# =====================================================================

function Get-MigrateScopePlan {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string[]]  $PackageNames,
        [Parameter(Mandatory)]            $PackageGlobalMap
    )

    $apps = [System.Collections.Generic.List[object]]::new()
    foreach ($pkgName in @($PackageNames | ForEach-Object { [string]$_ })) {
        $item = Find-PackageItemByName -PackagesDef $PackagesDef -PackageName $pkgName
        if ($null -eq $item) { continue }
        $targetGlobal = if ($PackageGlobalMap.Contains($pkgName)) {
            [bool]$PackageGlobalMap[$pkgName]
        }
        else {
            $fakeGlobalNames = @($PackageGlobalMap.Keys | Where-Object { [bool]$PackageGlobalMap[$_] })
            Get-PackageInstallGlobal -PackagesDef $PackagesDef -PackageName $pkgName -State @{
                Package_Global = @($fakeGlobalNames)
            }
        }
        foreach ($app in (Get-PackageItemScoopApps -PackageItem $item)) {
            $scope = Get-ScoopAppInstalledScope -Name $app
            if ($null -eq $scope) { continue }
            $currentGlobal = ($scope -eq 'global')
            if ($currentGlobal -eq $targetGlobal) { continue }
            [void]$apps.Add([pscustomobject]@{
                    PackageName  = $pkgName
                    AppName      = [string]$app
                    TargetGlobal = $targetGlobal
                })
        }
    }
    return @($apps)
}

function Invoke-InteractiveMigrate {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    $pkg = $Ctx.Packages
    $savedSelected = @()
    if ($State.Contains('Selected_Packages') -and $null -ne $State['Selected_Packages']) {
        $savedSelected = @($State['Selected_Packages'] | ForEach-Object { [string]$_ })
    }
    $savedPackageGlobal = Get-StatePackageGlobalNames -State $State

    if ($savedSelected.Count -eq 0) {
        Write-Warn (msg 'migrate.none.selected')
        return $null
    }

    Write-Step (msg 'migrate.interactive.title')
    Write-Info  (msg 'interactive.repo' $Ctx.Root)
    Write-Info  (msg 'interactive.log'  $Ctx.LogFile)
    Write-Info  ''

    Write-Step (msg 'migrate.interactive.step.packages')
    $selection = Get-InteractivePackageSelection -PackagesDef $pkg `
        -SavedSelected $savedSelected -SavedPackageGlobal $savedPackageGlobal -Mode 'migrate'
    if ($null -eq $selection) {
        Write-Info (msg 'interactive.cancelled')
        return $null
    }

    $migrateNames = [string[]]@($selection.SelectedPkgNames | ForEach-Object { [string]$_ })
    if (@($migrateNames).Count -eq 0) {
        Write-Info (msg 'migrate.nothing.todo')
        return $null
    }

    $scopePlan = Get-MigrateScopePlan -PackagesDef $pkg `
        -PackageNames $migrateNames -PackageGlobalMap $selection.PackageGlobalMap
    if (@($scopePlan).Count -eq 0) {
        Write-Info (msg 'migrate.nothing.todo')
        return $null
    }

    Clear-Host
    Write-Step (msg 'migrate.plan.title')
    $useMirror = if ($State.Contains('Scoop_Mirror')) { [bool]$State['Scoop_Mirror'] } else { [bool]$Ctx.Settings.Scoop.UseMirror }
    Write-ScoopSetConfigPlan -ScoopConfig $Ctx.Settings.Scoop -UseMirror $useMirror
    foreach ($entry in @($scopePlan)) {
        $fromLabel = if ((Get-ScoopAppInstalledScope -Name $entry.AppName) -eq 'global') {
            (msg 'scoop.scope.global')
        }
        else {
            (msg 'scoop.scope.user')
        }
        $toLabel = if ($entry.TargetGlobal) { (msg 'scoop.scope.global') } else { (msg 'scoop.scope.user') }
        Write-Plan (msg 'migrate.plan.item' (Get-ScoopAppBaseName -Name $entry.AppName) $fromLabel $toLabel)
    }
    Write-Info ''

    $confirmed = Read-YesNo -Prompt (msg 'migrate.plan.confirm.prompt') -Default $true
    if (-not $confirmed) {
        Write-Info (msg 'interactive.cancelled')
        return $null
    }

    return [pscustomobject]@{
        State              = $State
        MigratePackageNames = $migrateNames
        ScopePlan          = $scopePlan
        PackageGlobalMap   = $selection.PackageGlobalMap
    }
}

function Migrate-WindotsScoopApps {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $ScopePlan,
        [Parameter(Mandatory)]                 $Results
    )

    Write-Step (msg 'migrate.step.packages')
    foreach ($entry in @($ScopePlan)) {
        $appName = [string]$entry.AppName
        $pkgItem = Find-PackageItemByName -PackagesDef $Ctx.Packages -PackageName ([string]$entry.PackageName)
        $appResult = Install-ScoopAppResolved -Name $appName -TargetGlobal:([bool]$entry.TargetGlobal) -WhatIf:$Ctx.WhatIf
        $desc = if ($pkgItem) { Get-PackageDesc -Package $pkgItem } else { '' }
        $Results.Add([pscustomobject]@{
                Section = 'packages'
                Label   = Get-ScoopAppBaseName -Name $appName
                Desc    = $desc
                Status  = [string]$appResult.Status
                Detail  = [string]$appResult.Detail
            })
    }
}

function Update-WindotsMigrateState {
    param(
        [Parameter(Mandatory)]            $State,
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                        $MigratePackageNames,
        [hashtable]                       $PackageGlobalMap = $null
    )

    $allSelected = @()
    if ($State.Contains('Selected_Packages') -and $null -ne $State['Selected_Packages']) {
        $allSelected = @($State['Selected_Packages'] | ForEach-Object { [string]$_ })
    }

    $mergedMap = @{}
    foreach ($name in $allSelected) {
        if ($null -ne $PackageGlobalMap -and $PackageGlobalMap.Contains($name)) {
            $mergedMap[$name] = [bool]$PackageGlobalMap[$name]
        }
    }

    Set-StatePackageGlobal -State $State -SelectedNames $allSelected `
        -PackageGlobalMap $(if ($mergedMap.Count -gt 0) { $mergedMap } else { $null }) `
        -PackagesDef $PackagesDef
    $State['Timestamp'] = (Get-Date).ToString('s')
}

function Invoke-Migrate {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    if (-not (Test-CommandExists -Name 'scoop')) {
        Write-Err (msg 'migrate.scoop.missing')
        return
    }

    $plan = Invoke-InteractiveMigrate -Ctx $Ctx -State $State
    if ($null -eq $plan) { return }

    $results = [System.Collections.Generic.List[object]]::new()
    Set-WindotsSessionProxy -State $plan.State
    Migrate-WindotsScoopApps -Ctx $Ctx -ScopePlan $plan.ScopePlan -Results $results

    if (-not $Ctx.WhatIf) {
        Update-WindotsMigrateState -State $plan.State -PackagesDef $Ctx.Packages `
            -MigratePackageNames $plan.MigratePackageNames -PackageGlobalMap $plan.PackageGlobalMap
        Save-WindotsState -Path $Ctx.StatePath -State $plan.State
        Write-Success (msg 'interactive.state.saved' $Ctx.StatePath)
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}
