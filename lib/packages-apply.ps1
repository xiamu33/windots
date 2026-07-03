# =====================================================================
# Windots 包选择与安装共享逻辑 (lib/packages-apply.ps1)
# =====================================================================

function Invoke-PackageTreeWalk {
    param(
        [Parameter(Mandatory)]            $Nodes,
        [object[]]                        $GroupDefaults = @(),
        [Parameter(Mandatory)][scriptblock] $Visitor
    )
    foreach ($node in @($Nodes | Where-Object { $null -ne $_ })) {
        if ($node.Contains('Items') -and $null -ne $node.Items) {
            $gd = @($GroupDefaults)
            if ($node.Contains('Default') -or $node.Contains('Global')) { $gd = @($GroupDefaults + @($node)) }
            & $Visitor 'group' $node $gd
            Invoke-PackageTreeWalk -Nodes $node.Items -GroupDefaults $gd -Visitor $Visitor
        }
        elseif ($node.Contains('Name')) {
            & $Visitor 'package' $node $GroupDefaults
        }
    }
}

function Get-ResolvedPackageDefault {
    param(
        [Parameter(Mandatory)] $Node,
        [object[]]             $GroupDefaults = @()
    )
    if ($Node.Contains('Default')) { return [bool]$Node.Default }
    for ($i = $GroupDefaults.Count - 1; $i -ge 0; $i--) {
        $g = $GroupDefaults[$i]
        if ($g.Contains('Default')) { return [bool]$g.Default }
    }
    return $false
}

function Get-ResolvedPackageGlobal {
    param(
        [Parameter(Mandatory)] $Node,
        [object[]]             $GroupDefaults = @()
    )
    if ($Node.Contains('Global')) { return [bool]$Node.Global }
    for ($i = $GroupDefaults.Count - 1; $i -ge 0; $i--) {
        $g = $GroupDefaults[$i]
        if ($g.Contains('Global')) { return [bool]$g.Global }
    }
    return $false
}

function Get-StatePackageGlobalNames {
    param($State)

    if ($null -eq $State) { return @() }
    $pg = $null
    if ($State -is [hashtable] -and $State.Contains('Package_Global')) {
        $pg = $State['Package_Global']
    }
    elseif ($null -ne $State.PSObject.Properties['Package_Global']) {
        $pg = $State.Package_Global
    }
    if ($null -eq $pg) { return @() }

    if ($pg -is [hashtable]) {
        return @($pg.Keys | Where-Object { [bool]$pg[$_] } | ForEach-Object { [string]$_ })
    }
    return @($pg | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-StateHasPackageScopeConfigured {
    param($State)

    if ($null -eq $State) { return $false }
    if ($State -is [System.Collections.IDictionary]) {
        return $State.Contains('Package_Global')
    }
    return $null -ne $State.PSObject.Properties['Package_Global']
}

function Get-StateSelectedPackageNames {
    param($State)

    if ($null -eq $State) { return @() }
    $selected = $null
    if ($State -is [System.Collections.IDictionary] -and $State.Contains('Selected_Packages')) {
        $selected = $State['Selected_Packages']
    }
    elseif ($null -ne $State.PSObject.Properties['Selected_Packages']) {
        $selected = $State.Selected_Packages
    }
    if ($null -eq $selected) { return @() }
    return @($selected | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-PackageInstallGlobal {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string]    $PackageName,
        $State = $null
    )

    $globalNames = Get-StatePackageGlobalNames -State $State
    if ($globalNames -contains $PackageName) { return $true }

    if ((Test-StateHasPackageScopeConfigured -State $State) -and
        (Get-StateSelectedPackageNames -State $State) -contains $PackageName) {
        return $false
    }

    $match = @{
        Found         = $false
        InstallGlobal = $false
    }
    Invoke-PackageTreeWalk -Nodes @($PackagesDef.Packages) -Visitor {
        param($Kind, $Node, $GroupDefaults)
        if ($Kind -ne 'package' -or $match.Found) { return }
        if ([string]$Node.Name -ne $PackageName) { return }
        $match.InstallGlobal = Get-ResolvedPackageGlobal -Node $Node -GroupDefaults $GroupDefaults
        $match.Found = $true
    }
    return [bool]$match.InstallGlobal
}

# 返回包 intent scope 对应的 scoop root（user 或 global）。
# intent 解析复用 Get-PackageInstallGlobal 的既有顺序（state.Package_Global → state user 默认 → psd1 树继承）。
# 用于 SCOOP_PATH\ Dest 占位符展开：链接目标跟随 intent scope，而非磁盘扫描的 user 优先结果。
function Resolve-ScoopPathRoot {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string]    $PackageName,
        $State = $null
    )

    if (Get-PackageInstallGlobal -PackagesDef $PackagesDef -PackageName $PackageName -State $State) {
        return Get-ScoopGlobalRoot
    }
    return Get-ScoopUserRoot
}

# Persist 漂移检测：给定包名 + State + PackagesDef，返回该包每个 scoop app 的 drift 结果。
# - DualInstall: app 在 user 与 global 两侧 apps\ 均已安装
# - PersistDrift: intent 侧 persist 目录为空（或不存在）且另一 scope 侧 persist 含文件
# intent 侧由 Resolve-ScoopPathRoot 决定（state.Package_Global → state user 默认 → psd1 继承）。
# 供 doctor（#03 非交互报告）与 Apply-WindotsDotfiles（#04 可选同步）共用。
function Get-PackagePersistDrift {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string]    $PackageName,
        $State = $null
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $item = Find-PackageItemByName -PackagesDef $PackagesDef -PackageName $PackageName
    if ($null -eq $item) { return @($results) }

    $intentGlobal = Get-PackageInstallGlobal -PackagesDef $PackagesDef -PackageName $PackageName -State $State
    $intentRoot   = Resolve-ScoopPathRoot   -PackagesDef $PackagesDef -PackageName $PackageName -State $State
    $otherRoot    = if ($intentGlobal) { Get-ScoopUserRoot } else { Get-ScoopGlobalRoot }

    foreach ($app in (Get-PackageItemScoopApps -PackageItem $item)) {
        $base = Get-ScoopAppBaseName -Name $app
        $userInstalled   = Test-ScoopInstalledAtScope -Name $app -GlobalInstall:$false
        $globalInstalled = Test-ScoopInstalledAtScope -Name $app -GlobalInstall:$true

        $intentPersist = Join-Path $intentRoot "persist\$base"
        $otherPersist  = Join-Path $otherRoot  "persist\$base"

        $intentEmpty = $true
        if (Test-Path -LiteralPath $intentPersist) {
            $intentFiles = @(Get-ChildItem -LiteralPath $intentPersist -Recurse -File -ErrorAction SilentlyContinue)
            $intentEmpty = $intentFiles.Count -eq 0
        }
        $otherHasFiles = $false
        if (Test-Path -LiteralPath $otherPersist) {
            $otherFiles = @(Get-ChildItem -LiteralPath $otherPersist -Recurse -File -ErrorAction SilentlyContinue)
            $otherHasFiles = $otherFiles.Count -gt 0
        }

        $results.Add([pscustomobject]@{
            App           = $base
            DualInstall   = ($userInstalled -and $globalInstalled)
            PersistDrift  = ($intentEmpty -and $otherHasFiles)
            IntentRoot    = $intentRoot
            OtherRoot     = $otherRoot
            IntentPersist = $intentPersist
            OtherPersist  = $otherPersist
        })
    }
    return @($results)
}

function Test-PackageItemScoopInstalledAtScope {
    param(
        [Parameter(Mandatory)]            $PackageItem,
        [Parameter(Mandatory)][bool]      $InstallGlobal
    )

    foreach ($app in (Get-PackageItemScoopApps -PackageItem $PackageItem)) {
        if (Test-ScoopInstalledAtScope -Name $app -GlobalInstall:$InstallGlobal) { return $true }
    }
    return $false
}

function Test-PackageItemScoopInstalledAnyScope {
    param([Parameter(Mandatory)] $PackageItem)

    foreach ($app in (Get-PackageItemScoopApps -PackageItem $PackageItem)) {
        if ($null -ne (Get-ScoopAppInstalledScope -Name $app)) { return $true }
    }
    return $false
}

function Find-PackageItemByName {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [Parameter(Mandatory)][string]    $PackageName
    )

    $match = @{ Item = $null }
    Invoke-PackageTreeWalk -Nodes @($PackagesDef.Packages) -Visitor {
        param($Kind, $Node, $GroupDefaults)
        if ($Kind -eq 'package' -and [string]$Node.Name -eq $PackageName) {
            $match.Item = $Node
        }
    }
    return $match.Item
}

function Test-ScoopAppNeedsScopeMigration {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][bool]   $TargetGlobal
    )
    $atUser = Test-ScoopInstalledAtScope -Name $Name -GlobalInstall:$false
    $atGlobal = Test-ScoopInstalledAtScope -Name $Name -GlobalInstall:$true
    if ($atUser -and $atGlobal -and -not $TargetGlobal) { return $true }
    $targetScope = if ($TargetGlobal) { 'global' } else { 'user' }
    $installedScope = Get-ScoopAppInstalledScope -Name $Name
    return ($null -ne $installedScope -and $installedScope -ne $targetScope)
}

function Test-PackageItemScopeMismatch {
    param(
        [Parameter(Mandatory)]       $PackageItem,
        [Parameter(Mandatory)][bool] $ExpectedGlobal
    )

    foreach ($app in (Get-PackageItemScoopApps -PackageItem $PackageItem)) {
        $scope = Get-ScoopAppInstalledScope -Name $app
        if ($null -eq $scope) { continue }
        $isGlobal = ($scope -eq 'global')
        if ($isGlobal -ne $ExpectedGlobal) { return $true }
    }
    return $false
}

function Test-PackageItemNeedsScopeMigration {
    param(
        [Parameter(Mandatory)]       $PackageItem,
        [Parameter(Mandatory)][bool] $TargetGlobal
    )

    return (Test-PackageItemScopeMismatch -PackageItem $PackageItem -ExpectedGlobal $TargetGlobal)
}

function Test-PackageItemScoopInstalled {
    param(
        [Parameter(Mandatory)]            $PackageItem,
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        $State = $null
    )

    $name = [string]$PackageItem.Name
    $global = Get-PackageInstallGlobal -PackagesDef $PackagesDef -PackageName $name -State $State
    return (Test-PackageItemScoopInstalledAtScope -PackageItem $PackageItem -InstallGlobal $global)
}

function Set-StatePackageGlobal {
    param(
        [Parameter(Mandatory)]                 $State,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                             $SelectedNames,
        [hashtable]                            $PackageGlobalMap = $null,
        [Parameter(Mandatory)][hashtable]      $PackagesDef
    )

    $globalNames = [System.Collections.Generic.List[string]]::new()
    foreach ($n in @($SelectedNames | ForEach-Object { [string]$_ })) {
        $isGlobal = $false
        if ($null -ne $PackageGlobalMap -and $PackageGlobalMap.Contains($n)) {
            $isGlobal = [bool]$PackageGlobalMap[$n]
        }
        else {
            $isGlobal = Get-PackageInstallGlobal -PackagesDef $PackagesDef -PackageName $n -State $State
        }
        if ($isGlobal -and -not $globalNames.Contains($n)) { [void]$globalNames.Add($n) }
    }
    $explicitScope = ($null -ne $PackageGlobalMap)
    if ($globalNames.Count -eq 0) {
        if ($explicitScope) {
            $State['Package_Global'] = @()
        }
        elseif ($State -is [hashtable] -and $State.Contains('Package_Global')) {
            $State.Remove('Package_Global')
        }
    }
    else {
        $State['Package_Global'] = [string[]]@($globalNames)
    }
}

function Remove-StatePackageGlobalEntries {
    param(
        [Parameter(Mandatory)]            $State,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                        $PackageNames
    )

    if (@($PackageNames).Count -eq 0) { return }
    $names = Get-StatePackageGlobalNames -State $State
    if ($names.Count -eq 0) { return }
    $updated = @($names | Where-Object { $PackageNames -notcontains [string]$_ })
    if ($updated.Count -eq 0) {
        if ($State -is [hashtable] -and $State.Contains('Package_Global')) {
            $State.Remove('Package_Global')
        }
    }
    else {
        $State['Package_Global'] = $updated
    }
}

function Get-AllPackageItems {
    param([Parameter(Mandatory)][hashtable] $PackagesDef)

    $items = [System.Collections.Generic.List[object]]::new()
    Invoke-PackageTreeWalk -Nodes @($PackagesDef.Packages) -Visitor {
        param($Kind, $Node, $GroupDefaults)
        if ($Kind -eq 'package') { [void]$items.Add($Node) }
    }
    return @($items)
}

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
    $allItems = [System.Collections.Generic.List[object]]::new()
    Invoke-PackageTreeWalk -Nodes @($PackagesDef.Packages) -Visitor {
        param($Kind, $Node, $GroupDefaults)
        if ($Kind -eq 'package' -and $pkgLookup -contains [string]$Node.Name) {
            [void]$allItems.Add($Node)
        }
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
    Remove-StatePackageGlobalEntries -State $State -PackageNames @($removed)
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
    if ($State.Contains('Package_Global')) {
        $globalNames = Get-StatePackageGlobalNames -State $State
        $pruned = @($globalNames | Where-Object { $State['Selected_Packages'] -contains [string]$_ })
        $State['Package_Global'] = [string[]]@($pruned)
    }
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
        [string]                               $StepKey = 'init.step.packages',
        [switch]                               $AllowScopeMigration
    )

    Write-Step (msg $StepKey)
    foreach ($name in $State.Scoop_Apps) {
        $pkgItem = Find-PackageItemByScoopName -PackagesDef $Ctx.Packages -ScoopName ([string]$name)
        $global = if ($pkgItem) {
            Get-PackageInstallGlobal -PackagesDef $Ctx.Packages -PackageName ([string]$pkgItem.Name) -State $State
        }
        else { $false }
        $isMigration = $AllowScopeMigration -and (Test-ScoopAppNeedsScopeMigration -Name $name -TargetGlobal:$global)
        if ($AllowScopeMigration) {
            $appResult = Install-ScoopAppResolved -Name $name -TargetGlobal:$global -WhatIf:$Ctx.WhatIf
        }
        else {
            $appResult = Install-ScoopAppEnsure -Name $name -TargetGlobal:$global -WhatIf:$Ctx.WhatIf
        }
        $desc = if ($pkgItem) { Get-PackageDesc -Package $pkgItem } else { '' }
        $Results.Add([pscustomobject]@{
                Section = if ($isMigration) { 'migrate' } else { 'packages' }
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
    $planned = Get-PlannedLinks -RepoRoot $Ctx.Root -SelectedItems $allItems -Extras $extras -State $State -PackagesDef $Ctx.Packages

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
