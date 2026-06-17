# =====================================================================
# Windots 包 scope 迁移 (lib/commands/migrate.ps1)
# user ↔ global 单包安装位置迁移
# =====================================================================

function Get-MigrateSpecifiedGlobal {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string]    $PackageName,
        [Parameter(Mandatory)]            $PackageGlobalMap
    )

    if ($PackageGlobalMap.Contains($PackageName)) {
        return [bool]$PackageGlobalMap[$PackageName]
    }
    $fakeGlobalNames = @($PackageGlobalMap.Keys | Where-Object { [bool]$PackageGlobalMap[$_] })
    return Get-PackageInstallGlobal -PackagesDef $PackagesDef -PackageName $PackageName -State @{
        Package_Global = @($fakeGlobalNames)
    }
}

function Resolve-MigrateScopePlan {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string[]]  $PackageNames,
        [Parameter(Mandatory)]            $PackageGlobalMap
    )

    $direct = [System.Collections.Generic.List[object]]::new()
    $prompt = [System.Collections.Generic.List[object]]::new()

    foreach ($pkgName in @($PackageNames | ForEach-Object { [string]$_ })) {
        $item = Find-PackageItemByName -PackagesDef $PackagesDef -PackageName $pkgName
        if ($null -eq $item) { continue }
        $specifiedGlobal = Get-MigrateSpecifiedGlobal -PackagesDef $PackagesDef `
            -PackageName $pkgName -PackageGlobalMap $PackageGlobalMap
        $otherGlobal = -not $specifiedGlobal

        foreach ($app in (Get-PackageItemScoopApps -PackageItem $item)) {
            $appName = [string]$app
            $atSpec = Test-ScoopInstalledAtScope -Name $appName -GlobalInstall:$specifiedGlobal
            $atOther = Test-ScoopInstalledAtScope -Name $appName -GlobalInstall:$otherGlobal
            if (-not $atSpec -and -not $atOther) { continue }

            if ($atOther) {
                [void]$direct.Add([pscustomobject]@{
                        PackageName  = $pkgName
                        AppName      = $appName
                        TargetGlobal = $specifiedGlobal
                    })
            }
            elseif ($atSpec) {
                [void]$prompt.Add([pscustomobject]@{
                        PackageName           = $pkgName
                        AppName               = $appName
                        SpecifiedGlobal       = $specifiedGlobal
                        SuggestedTargetGlobal = $otherGlobal
                    })
            }
        }
    }

    return @{
        DirectEntries = @($direct)
        PromptEntries = @($prompt)
    }
}

function Get-MigrateAppFromScopeLabel {
    param(
        [Parameter(Mandatory)][string] $AppName,
        [Parameter(Mandatory)][bool]   $TargetGlobal
    )

    $atUser = Test-ScoopInstalledAtScope -Name $AppName -GlobalInstall:$false
    $atGlobal = Test-ScoopInstalledAtScope -Name $AppName -GlobalInstall:$true
    if ($atUser -and $atGlobal) {
        if ($TargetGlobal) { return (msg 'scoop.scope.user') }
        return (msg 'scoop.scope.global')
    }
    if ($atGlobal) { return (msg 'scoop.scope.global') }
    return (msg 'scoop.scope.user')
}

function Write-MigrateScopePlanSummary {
    param(
        [Parameter(Mandatory)] $ScopePlan
    )

    foreach ($entry in @($ScopePlan)) {
        Write-MigratePlanItemLine -AppName ([string]$entry.AppName) -TargetGlobal ([bool]$entry.TargetGlobal)
    }
}

function Write-MigratePlanItemLine {
    param(
        [Parameter(Mandatory)][string] $AppName,
        [Parameter(Mandatory)][bool]   $TargetGlobal,
        [bool]                         $FromSpecifiedScope = $false,
        [bool]                         $SpecifiedGlobal = $false
    )

    if ($FromSpecifiedScope) {
        $fromLabel = if ($SpecifiedGlobal) { (msg 'scoop.scope.global') } else { (msg 'scoop.scope.user') }
    }
    else {
        $fromLabel = Get-MigrateAppFromScopeLabel -AppName $AppName -TargetGlobal $TargetGlobal
    }
    $toLabel = if ($TargetGlobal) { (msg 'scoop.scope.global') } else { (msg 'scoop.scope.user') }
    Write-Plan (msg 'migrate.plan.item' (Get-ScoopAppBaseName -Name $AppName) $fromLabel $toLabel)
}

function Write-MigrateForgotGPrompt {
    param(
        [Parameter(Mandatory)] $PromptEntries
    )

    Write-Info ''
    Write-Warn (msg 'migrate.prompt.forgot_g.hint')
    foreach ($entry in @($PromptEntries)) {
        Write-MigratePlanItemLine -AppName ([string]$entry.AppName) `
            -TargetGlobal ([bool]$entry.SuggestedTargetGlobal) `
            -FromSpecifiedScope $true `
            -SpecifiedGlobal ([bool]$entry.SpecifiedGlobal)
    }
    Write-Info ''
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

    $resolved = Resolve-MigrateScopePlan -PackagesDef $pkg `
        -PackageNames $migrateNames -PackageGlobalMap $selection.PackageGlobalMap

    $scopePlan = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($resolved.DirectEntries)) { [void]$scopePlan.Add($entry) }

    if (@($resolved.PromptEntries).Count -gt 0) {
        Write-MigrateForgotGPrompt -PromptEntries $resolved.PromptEntries
        $acceptPrompt = Read-YesNo -Prompt (msg 'migrate.prompt.forgot_g.prompt') -Default $true
        if ($acceptPrompt) {
            foreach ($entry in @($resolved.PromptEntries)) {
                [void]$scopePlan.Add([pscustomobject]@{
                        PackageName  = [string]$entry.PackageName
                        AppName      = [string]$entry.AppName
                        TargetGlobal = [bool]$entry.SuggestedTargetGlobal
                    })
            }
        }
    }

    if ($scopePlan.Count -eq 0) {
        Write-Info (msg 'migrate.nothing.todo')
        return $null
    }

    Clear-Host
    Write-Step (msg 'migrate.plan.title')
    $useMirror = if ($State.Contains('Scoop_Mirror')) { [bool]$State['Scoop_Mirror'] } else { [bool]$Ctx.Settings.Scoop.UseMirror }
    Write-ScoopSetConfigPlan -ScoopConfig $Ctx.Settings.Scoop -UseMirror $useMirror
    Write-MigrateScopePlanSummary -ScopePlan @($scopePlan)
    Write-Info ''

    $confirmed = Read-YesNo -Prompt (msg 'migrate.plan.confirm.prompt') -Default $true
    if (-not $confirmed) {
        Write-Info (msg 'interactive.cancelled')
        return $null
    }

    return [pscustomobject]@{
        State               = $State
        MigratePackageNames = $migrateNames
        ScopePlan           = @($scopePlan)
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
        $targetGlobal = [bool]$entry.TargetGlobal
        $pkgItem = Find-PackageItemByName -PackagesDef $Ctx.Packages -PackageName ([string]$entry.PackageName)
        $atUser = Test-ScoopInstalledAtScope -Name $appName -GlobalInstall:$false
        $atGlobal = Test-ScoopInstalledAtScope -Name $appName -GlobalInstall:$true

        if ($atUser -and $atGlobal -and -not $targetGlobal) {
            $appResult = Uninstall-ScoopApp -Name $appName -GlobalInstall -WhatIf:$Ctx.WhatIf
        }
        else {
            $appResult = Install-ScoopAppResolved -Name $appName -TargetGlobal:$targetGlobal -WhatIf:$Ctx.WhatIf
        }

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

function Get-MigrateSucceededTargetMap {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                        $ScopePlan,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                        $MigrateResults
    )

    $resultByLabel = @{}
    foreach ($r in @($MigrateResults)) {
        if ([string]$r.Section -ne 'packages') { continue }
        $resultByLabel[[string]$r.Label] = [string]$r.Status
    }

    $pkgOk = @{}
    foreach ($entry in @($ScopePlan)) {
        $pkg = [string]$entry.PackageName
        $appName = [string]$entry.AppName
        $label = Get-ScoopAppBaseName -Name $appName
        $targetGlobal = [bool]$entry.TargetGlobal

        if (-not $pkgOk.ContainsKey($pkg)) { $pkgOk[$pkg] = $true }
        $status = if ($resultByLabel.ContainsKey($label)) { $resultByLabel[$label] } else { 'failed' }
        if ($status -eq 'failed') {
            $pkgOk[$pkg] = $false
            continue
        }
        if (-not (Test-ScoopInstalledAtScope -Name $appName -GlobalInstall:$targetGlobal)) {
            $pkgOk[$pkg] = $false
        }
    }

    $targetMap = @{}
    foreach ($entry in @($ScopePlan)) {
        $pkg = [string]$entry.PackageName
        if (-not $pkgOk[$pkg]) { continue }
        $targetMap[$pkg] = [bool]$entry.TargetGlobal
    }
    return $targetMap
}

function Update-WindotsMigrateState {
    param(
        [Parameter(Mandatory)]            $State,
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                        $ScopePlan,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                        $MigrateResults
    )

    $allSelected = @()
    if ($State.Contains('Selected_Packages') -and $null -ne $State['Selected_Packages']) {
        $allSelected = @($State['Selected_Packages'] | ForEach-Object { [string]$_ })
    }

    $targetMap = Get-MigrateSucceededTargetMap -ScopePlan $ScopePlan -MigrateResults $MigrateResults
    if ($targetMap.Count -gt 0) {
        Set-StatePackageGlobal -State $State -SelectedNames $allSelected `
            -PackageGlobalMap $targetMap -PackagesDef $PackagesDef
    }
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
            -ScopePlan $plan.ScopePlan -MigrateResults @($results)
        Save-WindotsState -Path $Ctx.StatePath -State $plan.State
        Write-Success (msg 'interactive.state.saved' $Ctx.StatePath)
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}
