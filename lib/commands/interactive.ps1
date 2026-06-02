# =====================================================================
# Windots 交互配置阶段 (lib/commands/interactive.ps1)
# =====================================================================

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

    $pkgSuffix = {
        param($x)
        $desc = Get-PackageDesc -Package $x
        if ($desc) { " ($desc)" } else { '' }
    }

    $getLockedNames = {
        param($list)
        @($list | Where-Object {
                $chk = if ($_.Contains('Packages') -and $null -ne $_.Packages) { [string](@($_.Packages)[0]) } else { [string]$_.Name }
                Test-ScoopInstalled -Name $chk
            } | ForEach-Object { [string]$_.Name })
    }

    $recItems = @($pkg.Recommended)
    $recLocked = & $getLockedNames $recItems
    $recSel = Select-Items -Title (msg 'interactive.packages.rec.title') `
        -Items         $recItems `
        -Labeler { param($x) [string]$x.Name } `
        -SuffixLabeler $pkgSuffix `
        -DefaultSet { param($x) [bool]$x.Default } `
        -Locked        $recLocked

    $devItems = @($pkg.Optional.Dev)
    $devLocked = & $getLockedNames $devItems
    $devSel = Select-Items -Title (msg 'interactive.packages.dev.title') `
        -Items         $devItems `
        -Labeler { param($x) [string]$x.Name } `
        -SuffixLabeler $pkgSuffix `
        -DefaultSet { param($x) [bool]$x.Default } `
        -Locked        $devLocked

    $termItems = @($pkg.Optional.Term)
    $termLocked = & $getLockedNames $termItems
    $termSel = Select-Items -Title (msg 'interactive.packages.term.title') `
        -Items         $termItems `
        -Labeler { param($x) [string]$x.Name } `
        -SuffixLabeler $pkgSuffix `
        -DefaultSet { param($x) [bool]$x.Default } `
        -Locked        $termLocked

    $beautyItems = @($pkg.Optional.Beauty)
    $beautyLocked = & $getLockedNames $beautyItems
    $beautySel = Select-Items -Title (msg 'interactive.packages.beauty.title') `
        -Items         $beautyItems `
        -Labeler { param($x) [string]$x.Name } `
        -SuffixLabeler $pkgSuffix `
        -DefaultSet { param($x) [bool]$x.Default } `
        -Locked        $beautyLocked

    $allSelected = @()
    foreach ($s in @($recSel) + @($devSel) + @($termSel) + @($beautySel)) { $allSelected += $s }

    $selectedPkgNames = @($allSelected | ForEach-Object { [string]$_.Name } | Select-Object -Unique)

    $scoopAppsList = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $allSelected) {
        if ($item.Contains('Packages') -and $null -ne $item.Packages) {
            foreach ($pkg in @($item.Packages)) {
                $pkgStr = [string]$pkg
                if (-not $scoopAppsList.Contains($pkgStr)) { $scoopAppsList.Add($pkgStr) }
            }
        }
        else {
            $pkgStr = [string]$item.Name
            if (-not $scoopAppsList.Contains($pkgStr)) { $scoopAppsList.Add($pkgStr) }
        }
    }
    $scoopApps = @($scoopAppsList)

    # ------------------------------------------------------------------
    # 5. chezmoi
    # ------------------------------------------------------------------
    Write-Step (msg 'interactive.step.chezmoi')
    $useChezmoi = Read-YesNo -Prompt (msg 'interactive.chezmoi.prompt') -Default $false
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
    Write-Plan (msg 'interactive.plan.packages' ($scoopApps -join ', '))
    Write-Plan (msg 'interactive.plan.chezmoi'  $(if ($useChezmoi) { "$chezmoiUser/$($set.Chezmoi.RepoName)" } else { msg 'interactive.plan.chezmoi.skip' }))
    Write-Plan (msg 'interactive.plan.conflict' $conflictMode)
    Write-Plan (msg 'interactive.plan.linkmode' $linkMode)
    Write-Info ''

    # ------------------------------------------------------------------
    # 保存 state
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
    if (-not $Ctx.WhatIf) {
        Save-WindotsState -Path $Ctx.StatePath -State $state
        Write-Success (msg 'interactive.state.saved' $Ctx.StatePath)
    }

    return $state
}
