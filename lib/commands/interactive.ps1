# =====================================================================
# Windots 交互配置阶段 (lib/commands/interactive.ps1)
# =====================================================================

function Get-InteractivePackageSelection {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [string[]]                        $SavedSelected = @(),
        [hashtable]                       $SavedPackageGlobal = $null,
        [ValidateSet('install', 'uninstall')]
        [string]                          $Mode = 'install'
    )

    $isInstallMode = $Mode -eq 'install'
    $allPackages = Get-AllPackageItems -PackagesDef $PackagesDef

    $locked = @($allPackages | Where-Object {
            (Test-PackageItemScoopInstalledAnyScope -PackageItem $_) -or
            ($isInstallMode -and $SavedSelected -contains [string]$_.Name)
        } | ForEach-Object { [string]$_.Name } | Select-Object -Unique)

    $notInstalled = @($allPackages | Where-Object {
            -not (Test-PackageItemScoopInstalledAnyScope -PackageItem $_)
        } | ForEach-Object { [string]$_.Name })

    $rows = [System.Collections.Generic.List[object]]::new()
    $groupStack = [System.Collections.Generic.List[object]]::new()
    $nextGroupIdx = 0

    function Invoke-PackageMenuWalk {
        param(
            $Nodes,
            $GroupDefaults = @(),
            [ref] $NextGroupIdx
        )
        foreach ($node in @($Nodes | Where-Object { $null -ne $_ })) {
            if ($node.Contains('Items') -and $null -ne $node.Items) {
                $gd = @($GroupDefaults)
                if ($node.Contains('Default') -or $node.Contains('Global')) { $gd = @($GroupDefaults + @($node)) }
                $gi = $NextGroupIdx.Value
                $NextGroupIdx.Value = $NextGroupIdx.Value + 1
                $grp = [pscustomobject]@{
                    Kind                    = 'group'
                    Label                   = msg ([string]$node.Title)
                    GroupIdx                = $gi
                    RowIdx                  = $rows.Count
                    Depth                   = $groupStack.Count
                    AncestorGroupRowIndices = @($groupStack | ForEach-Object { [int]$_.RowIdx })
                    PackageIndices          = [System.Collections.Generic.List[int]]::new()
                }
                [void]$rows.Add($grp)
                [void]$groupStack.Add($grp)
                Invoke-PackageMenuWalk -Nodes $node.Items -GroupDefaults $gd -NextGroupIdx $NextGroupIdx
                [void]$groupStack.RemoveAt($groupStack.Count - 1)
            }
            elseif ($node.Contains('Name')) {
                $idx = $rows.Count
                [void]$rows.Add([pscustomobject]@{
                        Kind                    = 'package'
                        Label                   = [string]$node.Name
                        Package                 = $node
                        GroupIdx                = if ($groupStack.Count -gt 0) { $groupStack[-1].GroupIdx } else { -1 }
                        RowIdx                  = $rows.Count
                        Depth                   = $groupStack.Count
                        AncestorGroupRowIndices = @($groupStack | ForEach-Object { [int]$_.RowIdx })
                        ResolvedDefault         = Get-ResolvedPackageDefault -Node $node -GroupDefaults $GroupDefaults
                        ResolvedGlobal          = Get-ResolvedPackageGlobal -Node $node -GroupDefaults $GroupDefaults
                    })
                foreach ($g in $groupStack) { [void]$g.PackageIndices.Add($idx) }
            }
        }
    }

    Invoke-PackageMenuWalk -Nodes @($PackagesDef.Packages) -NextGroupIdx ([ref]$nextGroupIdx)

    $pkgSuffix = {
        param($row)
        $desc = Get-PackageDesc -Package $row.Package
        if ($desc) { " ($desc)" } else { '' }
    }
    $defaultSetFn = if ($isInstallMode -and $SavedSelected.Count -gt 0) {
        { param($row) $SavedSelected -contains [string]$row.Package.Name }
    }
    elseif ($isInstallMode) {
        { param($row) [bool]$row.ResolvedDefault }
    }
    else {
        { param($row) $false }
    }

    $globalMapOut = @{}
    $globalMapRef = [ref]$globalMapOut
    $selectParams = @{
        Title         = (msg 'interactive.packages.title')
        Items         = @($rows)
        Grouped       = $true
        Labeler       = { param($row) [string]$row.Label }
        SuffixLabeler = $pkgSuffix
        DefaultSet    = $defaultSetFn
    }
    if ($isInstallMode) {
        $selectParams['Locked'] = $locked
        $selectParams['GlobalToggle'] = $true
        $selectParams['GlobalMapOut'] = $globalMapRef
        $selectParams['GlobalSet'] = {
            param($row)
            $pkgName = [string]$row.Package.Name
            if ($null -ne $SavedPackageGlobal -and $SavedPackageGlobal.Contains($pkgName)) {
                return [bool]$SavedPackageGlobal[$pkgName]
            }
            return [bool]$row.ResolvedGlobal
        }
        $selectParams['InstalledChecker'] = {
            param($row, $isGlobal)
            Test-PackageItemScoopInstalledAtScope -PackageItem $row.Package -InstallGlobal $isGlobal
        }
        $selectParams['InstalledAnyChecker'] = {
            param($row)
            Test-PackageItemScoopInstalledAnyScope -PackageItem $row.Package
        }
    }
    else { $selectParams['NotInstalled'] = $notInstalled }

    $allSelected = Select-Items @selectParams
    if ($null -eq $allSelected) { return $null }

    $selectedPkgNames = [string[]]@($allSelected | ForEach-Object { [string]$_.Name } | Select-Object -Unique)

    $packageGlobal = @{}
    foreach ($name in $selectedPkgNames) {
        if ($globalMapOut.ContainsKey($name)) {
            $packageGlobal[$name] = [bool]$globalMapOut[$name]
        }
        else {
            $packageGlobal[$name] = Get-PackageInstallGlobal -PackagesDef $PackagesDef -PackageName $name
        }
    }

    $scoopAppsList = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $allSelected) {
        foreach ($app in (Get-PackageItemScoopApps -PackageItem $item)) {
            if (-not $scoopAppsList.Contains($app)) { $scoopAppsList.Add($app) }
        }
    }

    return @{
        SelectedPkgNames = $selectedPkgNames
        ScoopApps        = @($scoopAppsList)
        Package_Global   = $packageGlobal
    }
}

function Invoke-InteractivePackages {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    $pkg = $Ctx.Packages
    $savedSelected = @()
    if ($State.Contains('Selected_Packages') -and $null -ne $State['Selected_Packages']) {
        $savedSelected = @($State['Selected_Packages'] | ForEach-Object { [string]$_ })
    }
    $savedPackageGlobal = Get-StatePackageGlobalMap -State $State

    Write-Step (msg 'install.interactive.title')
    Write-Info  (msg 'interactive.repo' $Ctx.Root)
    Write-Info  (msg 'interactive.log'  $Ctx.LogFile)
    Write-Info  ''

    Write-Step (msg 'interactive.step.packages')
    $selection = Get-InteractivePackageSelection -PackagesDef $pkg `
        -SavedSelected $savedSelected -SavedPackageGlobal $savedPackageGlobal
    if ($null -eq $selection) {
        Write-Info (msg 'interactive.cancelled')
        return $null
    }

    $newNames = [string[]]@($selection.SelectedPkgNames | Where-Object { $savedSelected -notcontains $_ })

    Clear-Host
    Write-Step (msg 'install.plan.title')
    Write-PackageList -TitleKey 'install.plan.packages' `
        -SelectedNames $selection.SelectedPkgNames `
        -ScoopApps     $selection.ScoopApps `
        -PackagesDef   $pkg `
        -PackageGlobal $selection.Package_Global
    if (@($newNames).Count -gt 0) {
        Write-Plan (msg 'install.plan.added' ($newNames -join ', '))
    }
    else {
        Write-Plan (msg 'install.plan.added.none')
    }
    Write-Info ''

    $State['Scoop_Apps'] = @($selection.ScoopApps | ForEach-Object { [string]$_ })
    $State['Selected_Packages'] = @($selection.SelectedPkgNames | ForEach-Object { [string]$_ })
    Set-StatePackageGlobal -State $State -SelectedNames $selection.SelectedPkgNames `
        -PackageGlobalMap $selection.Package_Global -PackagesDef $pkg

    return [pscustomobject]@{
        PlannedState    = $State
        SavedSelected   = [string[]]@($savedSelected | ForEach-Object { [string]$_ })
        NewPackageNames = $newNames
    }
}

function Invoke-InteractivePackagesUninstall {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    $pkg = $Ctx.Packages
    $savedSelected = @()
    if ($State.Contains('Selected_Packages') -and $null -ne $State['Selected_Packages']) {
        $savedSelected = @($State['Selected_Packages'] | ForEach-Object { [string]$_ })
    }
    $savedPackageGlobal = Get-StatePackageGlobalMap -State $State

    if ($savedSelected.Count -eq 0) {
        Write-Warn (msg 'uninstall.none.selected')
        return [pscustomobject]@{
            State                = $State
            RemovedPackages      = @()
            ScoopAppsToUninstall = @()
            BlockedApps          = @()
        }
    }

    Write-Step (msg 'uninstall.interactive.title')
    Write-Info  (msg 'interactive.repo' $Ctx.Root)
    Write-Info  (msg 'interactive.log'  $Ctx.LogFile)
    Write-Info  ''

    Write-Step (msg 'uninstall.interactive.step.packages')
    $selection = Get-InteractivePackageSelection -PackagesDef $pkg -SavedSelected $savedSelected -Mode 'uninstall'
    if ($null -eq $selection) {
        Write-Info (msg 'interactive.cancelled')
        return [pscustomobject]@{
            State                = $State
            RemovedPackages      = @()
            ScoopAppsToUninstall = @()
            BlockedApps          = @()
        }
    }

    $removedNames = [string[]]@($selection.SelectedPkgNames | ForEach-Object { [string]$_ })
    if (@($removedNames).Count -eq 0) {
        Write-Info (msg 'uninstall.nothing.todo')
        return [pscustomobject]@{
            State                = $State
            RemovedPackages      = @()
            ScoopAppsToUninstall = @()
            BlockedApps          = @()
        }
    }

    $remainingNames = [string[]]@($savedSelected | Where-Object { $removedNames -notcontains $_ })
    $uninstallPlan = Get-UninstallScoopPlan `
        -PackagesDef           $pkg `
        -RemovedPackageNames    $removedNames `
        -RemainingPackageNames  $remainingNames
    $appsToRemove = [string[]]@($uninstallPlan.ScoopAppsToUninstall)
    $packagesPlannedForRemoval = Get-PackagesPlannedForRemoval `
        -PackagesDef          $pkg `
        -RemovedPackageNames  $removedNames `
        -AppsToUninstall      $appsToRemove
    $finalRemainingNames = [string[]]@($savedSelected | Where-Object { $packagesPlannedForRemoval -notcontains $_ })
    $remainingScoopApps = Get-ScoopAppsForPackageNames -PackagesDef $pkg -PackageNames $finalRemainingNames

    $remainingPackageGlobal = @{}
    if ($null -ne $savedPackageGlobal) {
        foreach ($n in $finalRemainingNames) {
            if ($savedPackageGlobal.Contains($n)) {
                $remainingPackageGlobal[$n] = [bool]$savedPackageGlobal[$n]
            }
        }
    }

    Clear-Host
    Write-Step (msg 'uninstall.plan.title')
    Write-PackageList -TitleKey 'uninstall.plan.remaining' `
        -SelectedNames $finalRemainingNames `
        -ScoopApps     $remainingScoopApps `
        -PackagesDef   $pkg `
        -PackageGlobal $remainingPackageGlobal
    if (@($packagesPlannedForRemoval).Count -gt 0) {
        Write-Plan (msg 'uninstall.plan.removed' ($packagesPlannedForRemoval -join ', '))
    }
    else {
        Write-Plan (msg 'uninstall.plan.removed.none')
    }
    if (@($appsToRemove).Count -gt 0) {
        Write-Plan (msg 'uninstall.plan.apps' ($appsToRemove -join ', '))
    }
    else {
        Write-Plan (msg 'uninstall.plan.apps.none')
    }
    foreach ($blocked in @($uninstallPlan.BlockedApps)) {
        $appLabel = Get-ScoopAppBaseName -Name ([string]$blocked.App)
        Write-Warn (msg 'uninstall.blocked.app' $appLabel ($blocked.RequiredBy -join ', '))
    }
    Write-Info ''

    return [pscustomobject]@{
        State                     = $State
        SavedSelected             = [string[]]@($savedSelected | ForEach-Object { [string]$_ })
        PackagesPlannedForRemoval = @($packagesPlannedForRemoval | ForEach-Object { [string]$_ })
        ScoopAppsToUninstall      = @($appsToRemove | ForEach-Object { [string]$_ })
        BlockedApps               = @($uninstallPlan.BlockedApps)
    }
}

function Invoke-Interactive {
    param([Parameter(Mandatory)][pscustomobject] $Ctx)

    $pkg = $Ctx.Packages
    $set = $Ctx.Settings

    Write-Step (msg 'interactive.title')
    Write-Info  (msg 'interactive.repo' $Ctx.Root)
    Write-Info  (msg 'interactive.log'  $Ctx.LogFile)
    Write-Info  ''

    # ------------------------------------------------------------------
    # 1. 代理
    # ------------------------------------------------------------------
    Write-Step (msg 'interactive.step.proxy')
    Write-Info  (msg 'interactive.proxy.desc')
    $useProxy = Read-YesNo -Prompt (msg 'interactive.proxy.prompt') -Default ([bool]$set.Proxy.Enabled)
    $proxyUrl = ''
    if ($useProxy) {
        $proxyUrl = Read-Text -Prompt (msg 'interactive.proxy.url.prompt') -Default ([string]$set.Proxy.Url)
    }

    # ------------------------------------------------------------------
    # 2. 包管理器
    # ------------------------------------------------------------------
    Write-Step (msg 'interactive.step.pkgmgr')
    $pmItems = @($pkg.PackageManagers)
    $disabledPM = @($pmItems | Where-Object { -not [bool]$_.Supported } | ForEach-Object { $_.Name })
    $selectedPM = Select-Items -Title (msg 'interactive.pkgmgr.title') `
        -Items      $pmItems `
        -Labeler { param($x) $x.Name } `
        -DefaultSet { param($x) [bool]$x.Default } `
        -Disabled   $disabledPM
    if ($null -eq $selectedPM) {
        Write-Info (msg 'interactive.cancelled')
        return $null
    }

    $useScoop = ($selectedPM | Where-Object { $_.Key -eq 'scoop' }).Count -gt 0

    # ------------------------------------------------------------------
    # 3. Scoop 镜像
    # ------------------------------------------------------------------
    $useScoopMirror = $false
    if ($useScoop) {
        Write-Step (msg 'interactive.step.mirror')
        Write-Info  (msg 'interactive.mirror.desc')
        $useScoopMirror = Read-YesNo -Prompt (msg 'interactive.mirror.prompt') -Default ([bool]$set.Scoop.UseMirror)
    }

    # ------------------------------------------------------------------
    # 4. 选择安装包
    # ------------------------------------------------------------------
    Write-Step (msg 'interactive.step.packages')
    $selection = Get-InteractivePackageSelection -PackagesDef $pkg
    if ($null -eq $selection) {
        Write-Info (msg 'interactive.cancelled')
        return $null
    }
    $selectedPkgNames = $selection.SelectedPkgNames
    $scoopApps = $selection.ScoopApps
    $packageGlobal = $selection.Package_Global

    # ------------------------------------------------------------------
    # 5. chezmoi
    # ------------------------------------------------------------------
    Write-Step (msg 'interactive.step.chezmoi')
    $useChezmoi = Read-YesNo -Prompt (msg 'interactive.chezmoi.prompt') -Default ([bool]$set.Chezmoi.Enabled)
    $chezmoiUser = ''
    $chezmoiApply = $true
    if ($useChezmoi) {
        $chezmoiUser = Read-Text   -Prompt (msg 'interactive.chezmoi.user.prompt')  -Default ([string]$set.Chezmoi.Username)
        $chezmoiApply = Read-YesNo  -Prompt (msg 'interactive.chezmoi.apply.prompt') -Default ([bool]$set.Chezmoi.ApplyOnInit)
        if ($scoopApps -notcontains 'chezmoi') { $scoopApps += 'chezmoi' }
    }

    # ------------------------------------------------------------------
    # 6. 配置处理方式
    # ------------------------------------------------------------------
    Write-Step (msg 'interactive.step.config')

    $conflictChoice = Select-One -Title (msg 'interactive.conflict.title') `
        -Items @(
        (msg 'interactive.conflict.overwrite'),
        (msg 'interactive.conflict.backup'),
        (msg 'interactive.conflict.keep')
    ) `
        -DefaultIdx 0
    $conflictMode = if ($conflictChoice -eq (msg 'interactive.conflict.backup')) { 'backup' }
    elseif ($conflictChoice -eq (msg 'interactive.conflict.keep')) { 'keep' }
    else { 'overwrite' }

    $linkChoice = Select-One -Title (msg 'interactive.linkmode.title') `
        -Items @(
        (msg 'interactive.linkmode.hardlink'),
        (msg 'interactive.linkmode.symlink'),
        (msg 'interactive.linkmode.copy')
    ) `
        -DefaultIdx 0
    $linkMode = if ($linkChoice -eq (msg 'interactive.linkmode.copy')) { 'copy' }
    elseif ($linkChoice -eq (msg 'interactive.linkmode.symlink')) { 'symlink' }
    else { 'hardlink' }

    # ------------------------------------------------------------------
    # 计划摘要
    # ------------------------------------------------------------------
    Clear-Host
    Write-Step (msg 'interactive.plan.title')
    Write-Plan (msg 'interactive.plan.proxy'    $(if ($useProxy) { $proxyUrl } else { msg 'interactive.plan.proxy.none' }))
    Write-Plan (msg 'interactive.plan.mirror'   $(if ($useScoopMirror) { msg 'interactive.plan.mirror.enabled' } else { msg 'interactive.plan.mirror.disabled' }))
    Write-PackageList -TitleKey 'interactive.plan.packages' `
        -SelectedNames $selectedPkgNames `
        -ScoopApps     $scoopApps `
        -PackagesDef   $pkg `
        -PackageGlobal $packageGlobal
    Write-Plan (msg 'interactive.plan.chezmoi'  $(if ($useChezmoi) { $chezmoiUser } else { msg 'interactive.plan.chezmoi.skip' }))
    Write-Plan (msg 'interactive.plan.conflict' $conflictMode)
    Write-Plan (msg 'interactive.plan.linkmode' $linkMode)
    Write-Info ''

    # ------------------------------------------------------------------
    # 返回计划（安装成功后再写入 state）
    # ------------------------------------------------------------------
    $state = @{
        Proxy_Enabled     = [bool]$useProxy
        Proxy_Url         = [string]$proxyUrl
        Scoop_Mirror      = [bool]$useScoopMirror
        Scoop_Apps        = @($scoopApps | ForEach-Object { [string]$_ })
        Selected_Packages = @($selectedPkgNames | ForEach-Object { [string]$_ })
        Package_Global    = $packageGlobal
        Chezmoi_Use       = [bool]$useChezmoi
        Chezmoi_User      = [string]$chezmoiUser
        Chezmoi_Apply     = [bool]$chezmoiApply
        Conflict_Mode     = [string]$conflictMode
        Link_Mode         = [string]$linkMode
        Timestamp         = (Get-Date).ToString('s')
    }

    return $state
}
