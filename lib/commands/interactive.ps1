# =====================================================================
# Windots 交互配置阶段 (lib/commands/interactive.ps1)
# =====================================================================

function Get-InteractivePackageSelection {
    param(
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [string[]]                        $SavedSelected = @(),
        [ValidateSet('install', 'uninstall')]
        [string]                          $Mode = 'install'
    )

    $isInstallMode = $Mode -eq 'install'

    $pkgSuffix = {
        param($x)
        $desc = Get-PackageDesc -Package $x
        if ($desc) { " ($desc)" } else { '' }
    }

    $testPkgInstalled = {
        param($x)
        $chk = if ($x.Contains('Packages') -and $null -ne $x.Packages) { [string](@($x.Packages)[0]) } else { [string]$x.Name }
        Test-ScoopInstalled -Name $chk
    }

    $getLockedNames = {
        param($list)
        @($list | Where-Object { & $testPkgInstalled $_ } | ForEach-Object { [string]$_.Name })
    }

    $mergeLocked = {
        param($list)
        $installed = & $getLockedNames $list
        if ($isInstallMode -and $SavedSelected.Count -gt 0) {
            @($SavedSelected + $installed | Select-Object -Unique)
        }
        else {
            $installed
        }
    }

    $defaultSetFn = if ($isInstallMode -and $SavedSelected.Count -gt 0) {
        { param($x) $SavedSelected -contains [string]$x.Name }
    }
    elseif ($isInstallMode) {
        { param($x) [bool]$x.Default }
    }
    else {
        { param($x) $false }
    }

    $getNotInstalledNames = {
        param($list)
        @($list | Where-Object { -not (& $testPkgInstalled $_) } | ForEach-Object { [string]$_.Name })
    }

    $selectGroup = {
        param(
            [string] $TitleKey,
            $Items
        )
        $Items = @($Items | Where-Object { $null -ne $_ })
        if ($Items.Count -eq 1 -and ($Items[0] -is [System.Array])) {
            $nested = @($Items[0] | Where-Object { $null -ne $_ })
            if ($nested.Count -gt 0) { $Items = $nested }
        }
        if ($Items.Count -eq 0) { return @() }
        $selectParams = @{
            Title         = (msg $TitleKey)
            Items         = $Items
            Labeler       = { param($x) [string]$x.Name }
            SuffixLabeler = $pkgSuffix
            DefaultSet    = $defaultSetFn
        }
        if ($isInstallMode) {
            $selectParams['Locked'] = & $mergeLocked $Items
        }
        else {
            $selectParams['NotInstalled'] = & $getNotInstalledNames $Items
        }
        Select-Items @selectParams
    }

    $recSel = & $selectGroup 'interactive.packages.rec.title' @($PackagesDef.Recommended)
    $devSel = & $selectGroup 'interactive.packages.dev.title' @($PackagesDef.Optional.Dev)
    $termSel = & $selectGroup 'interactive.packages.term.title' @($PackagesDef.Optional.Term)
    $beautySel = & $selectGroup 'interactive.packages.beauty.title' @($PackagesDef.Optional.Beauty)

    $allSelected = @()
    foreach ($group in @($recSel, $devSel, $termSel, $beautySel)) {
        foreach ($s in @($group)) { $allSelected += $s }
    }

    $selectedPkgNames = [string[]]@($allSelected | ForEach-Object { [string]$_.Name } | Select-Object -Unique)

    $scoopAppsList = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $allSelected) {
        foreach ($app in (Get-PackageItemScoopApps -PackageItem $item)) {
            if (-not $scoopAppsList.Contains($app)) { $scoopAppsList.Add($app) }
        }
    }

    return @{
        SelectedPkgNames = $selectedPkgNames
        ScoopApps        = @($scoopAppsList)
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

    Write-Step (msg 'install.interactive.title')
    Write-Info  (msg 'interactive.repo' $Ctx.Root)
    Write-Info  (msg 'interactive.log'  $Ctx.LogFile)
    Write-Info  ''

    Write-Step (msg 'interactive.step.packages')
    $selection = Get-InteractivePackageSelection -PackagesDef $pkg -SavedSelected $savedSelected

    $newNames = [string[]]@($selection.SelectedPkgNames | Where-Object { $savedSelected -notcontains $_ })

    Clear-Host
    Write-Step (msg 'install.plan.title')
    Write-PackageList -TitleKey 'install.plan.packages' `
        -SelectedNames $selection.SelectedPkgNames `
        -ScoopApps     $selection.ScoopApps `
        -PackagesDef   $pkg
    if (@($newNames).Count -gt 0) {
        Write-Plan (msg 'install.plan.added' ($newNames -join ', '))
    }
    else {
        Write-Plan (msg 'install.plan.added.none')
    }
    Write-Info ''

    $State['Scoop_Apps'] = @($selection.ScoopApps | ForEach-Object { [string]$_ })
    $State['Selected_Packages'] = @($selection.SelectedPkgNames | ForEach-Object { [string]$_ })

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

    Clear-Host
    Write-Step (msg 'uninstall.plan.title')
    Write-PackageList -TitleKey 'uninstall.plan.remaining' `
        -SelectedNames $finalRemainingNames `
        -ScoopApps     $remainingScoopApps `
        -PackagesDef   $pkg
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
    $selectedPkgNames = $selection.SelectedPkgNames
    $scoopApps = $selection.ScoopApps

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
        -PackagesDef   $pkg
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
        Chezmoi_Use       = [bool]$useChezmoi
        Chezmoi_User      = [string]$chezmoiUser
        Chezmoi_Apply     = [bool]$chezmoiApply
        Conflict_Mode     = [string]$conflictMode
        Link_Mode         = [string]$linkMode
        Timestamp         = (Get-Date).ToString('s')
    }

    return $state
}
