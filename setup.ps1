# =====================================================================
# Windots Setup  (setup.ps1)
# Windows 开发环境初始化脚本
#
# 文件编码：UTF-8 with BOM（兼容 PS5.1 与 PS7）
#
# 用法：
#   .\setup.ps1              # 自动检测环境，引导全流程
#   .\setup.ps1 install      # 同上（子命令）
#   .\setup.ps1 update       # 更新所有 scoop 包 + chezmoi
#   .\setup.ps1 link         # 重新同步配置文件链接
#   .\setup.ps1 doctor       # 检查环境健康
#
# 参数：
#   -WhatIf       预演模式，不真正执行
#   -Reconfigure  强制重跑交互（忽略已有 state 文件）
#   -Resume       内部参数，由 PS5.1 bootstrap 拉起时使用
# =====================================================================

[CmdletBinding()]
param(
    # 子命令
    [string] $Command = '',
    # 预演模式
    [switch] $WhatIf,
    # 强制重跑交互
    [switch] $Reconfigure,
    # 内部：PS5.1 bootstrap 拉起 pwsh 后传递，跳过 bootstrap 检查
    [switch] $Resume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 控制台 UTF-8，避免中文乱码（对 PS5.1 和 PS7 都有效）
try {
    $null = & chcp 65001
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
}
catch { }

$Script:Root = $PSScriptRoot

# 加载公共函数库
. (Join-Path $Script:Root 'lib.ps1')


# =====================================================================
# 工具：读取配置与 state
# =====================================================================
function Get-Context {
    $settings = Read-DataFile -Path (Join-Path $Script:Root 'settings.psd1')
    $packages = Read-DataFile -Path (Join-Path $Script:Root 'packages.psd1')
    $logDir = Resolve-RepoPath -RepoRoot $Script:Root -Value $settings.Paths.Logs
    $logFile = Start-WindotsLog -LogDir $logDir
    $statePath = Resolve-RepoPath -RepoRoot $Script:Root -Value $settings.Paths.State
    $backupDir = Resolve-RepoPath -RepoRoot $Script:Root -Value $settings.Paths.Backup

    return [pscustomobject]@{
        Root      = $Script:Root
        Settings  = $settings
        Packages  = $packages
        StatePath = $statePath
        BackupDir = $backupDir
        LogFile   = $logFile
        WhatIf    = [bool]$WhatIf
    }
}

function Get-State {
    param([string] $StatePath)
    if (-not (Test-Path $StatePath)) { return $null }
    try {
        $s = Read-DataFile -Path $StatePath
        # Bootstrap-only state 只有 Bootstrap 键，是 PS5.1 引导阶段写的临时标记，不能当完整 state 使用
        if (-not $s.Contains('Proxy_Enabled')) { return $null }
        return $s
    }
    catch { }
    return $null
}


# =====================================================================
# 交互阶段：收集用户所有决策
# =====================================================================
function Invoke-Interactive {
    param([Parameter(Mandatory)][pscustomobject] $Ctx)

    $pkg = $Ctx.Packages
    $set = $Ctx.Settings

    Write-Step '=== Windots 交互配置 ==='
    Write-Info "仓库目录：$($Ctx.Root)"
    Write-Info "日志文件：$($Ctx.LogFile)"
    Write-Info ''

    # ------------------------------------------------------------------
    # 1. 代理
    # ------------------------------------------------------------------
    Write-Step '--- 1/6 代理配置 ---'
    Write-Info '国内访问 GitHub 可能较慢，可配置代理加速安装。'
    $useProxy = Read-YesNo -Prompt '是否使用代理？' -Default ([bool]$set.Proxy.Enabled)
    $proxyUrl = ''
    if ($useProxy) {
        $proxyUrl = Read-Text -Prompt '代理地址 (默认 http://127.0.0.1:10808)' -Default ([string]$set.Proxy.Url)
    }

    # ------------------------------------------------------------------
    # 2. 包管理器选择
    # ------------------------------------------------------------------
    Write-Step '--- 2/6 包管理器 ---'
    $pmItems = @($pkg.PackageManagers)
    $disabledPM = @($pmItems | Where-Object { -not [bool]$_.Supported } | ForEach-Object { $_.Name })
    $selectedPM = Select-Items -Title '选择包管理器：' `
        -Items $pmItems `
        -Labeler { param($x) $x.Name } `
        -DefaultSet { param($x) [bool]$x.Default } `
        -Disabled $disabledPM

    $useScoop = ($selectedPM | Where-Object { $_.Key -eq 'scoop' }).Count -gt 0

    # ------------------------------------------------------------------
    # 3. Scoop 镜像（仅当选了 scoop）
    # ------------------------------------------------------------------
    $useScoopMirror = $false
    if ($useScoop) {
        Write-Step '--- 3/6 Scoop 镜像 ---'
        Write-Info '切换到 gitee 镜像可加快 scoop 本体和 bucket 的下载速度。'
        $useScoopMirror = Read-YesNo -Prompt '是否切换 scoop 到 gitee 国内镜像？' -Default ([bool]$set.Scoop.UseMirror)
    }

    # ------------------------------------------------------------------
    # 4. 选择安装包
    # ------------------------------------------------------------------
    Write-Step '--- 4/6 选择安装包 ---'

    # 推荐
    $recItems = @($pkg.Recommended)
    $recSel = Select-Items -Title '推荐安装（默认全选）：' `
        -Items $recItems `
        -Labeler {
        param($x)
        $mark = if (Test-ScoopInstalled -Name $x.Name) { ' [已安装]' } else { '' }
        "$($x.Name)$mark"
    } `
        -DefaultSet { param($x) [bool]$x.Default }

    # 可选 - 开发环境
    $devItems = @($pkg.Optional.Dev)
    $devSel = Select-Items -Title '可选 - 开发环境：' `
        -Items $devItems `
        -Labeler {
        param($x)
        $mark = if (Test-ScoopInstalled -Name $x.Name) { ' [已安装]' } else { '' }
        "$($x.Name)$mark"
    } `
        -DefaultSet { param($x) [bool]$x.Default }

    # 可选 - 终端工具
    $termItems = @($pkg.Optional.Term)
    $termSel = Select-Items -Title '可选 - 终端工具：' `
        -Items $termItems `
        -Labeler {
        param($x)
        $mark = if (Test-ScoopInstalled -Name $x.Name) { ' [已安装]' } else { '' }
        "$($x.Name)$mark"
    } `
        -DefaultSet { param($x) [bool]$x.Default }

    # 可选 - 美化工具
    $beautyItems = @($pkg.Optional.Beauty)
    $beautySel = Select-Items -Title '可选 - 美化工具：' `
        -Items $beautyItems `
        -Labeler {
        param($x)
        $mark = if (Test-ScoopInstalled -Name $x.Name) { ' [已安装]' } else { '' }
        "$($x.Name)$mark"
    } `
        -DefaultSet { param($x) [bool]$x.Default }

    # 合并所有选中工具（去重）
    $allSelected = @()
    foreach ($s in @($recSel) + @($devSel) + @($termSel) + @($beautySel)) { $allSelected += $s }
    $scoopApps = @($allSelected | ForEach-Object { [string]$_.Name } | Select-Object -Unique)

    # ------------------------------------------------------------------
    # 5. chezmoi
    # ------------------------------------------------------------------
    Write-Step '--- 5/6 chezmoi 配置同步 ---'
    $useChezmoi = Read-YesNo -Prompt '是否使用 chezmoi 同步跨平台配置（nvim/starship/wezterm 等）？' -Default $false
    $chezmoiUser = ''
    $chezmoiApply = $true
    if ($useChezmoi) {
        $chezmoiUser = Read-Text -Prompt 'GitHub 用户名' -Default ([string]$set.Chezmoi.Username)
        $chezmoiApply = Read-YesNo -Prompt '是否立即 --apply（拉取并应用配置）？' -Default ([bool]$set.Chezmoi.ApplyOnInit)
        # 自动加入 chezmoi 包
        if ($scoopApps -notcontains 'chezmoi') { $scoopApps += 'chezmoi' }
    }

    # ------------------------------------------------------------------
    # 6. 配置处理方式
    # ------------------------------------------------------------------
    Write-Step '--- 6/6 配置文件应用方式 ---'

    $conflictChoice = Select-One -Title '已存在的配置文件如何处理？' `
        -Items @('直接覆盖（默认）', '备份后覆盖', '保留原文件') `
        -DefaultIdx 0
    $conflictMode = switch ($conflictChoice) {
        '备份后覆盖' { 'backup' }
        '保留原文件' { 'keep' }
        default { 'overwrite' }
    }

    $linkChoice = Select-One -Title '如何应用配置文件？' `
        -Items @('软链接（推荐）', '复制文件') `
        -DefaultIdx 0
    $linkMode = if ($linkChoice -eq '复制文件') { 'copy' } else { 'symlink' }

    # ------------------------------------------------------------------
    # 计划摘要
    # ------------------------------------------------------------------
    Clear-Host
    Write-Step '=== 执行计划摘要 ==='
    Write-Plan ("代理      : $(if ($useProxy) { $proxyUrl } else { '(无)' })")
    Write-Plan ("scoop 镜像: $(if ($useScoopMirror) { '启用 (gitee)' } else { '禁用' })")
    Write-Plan ("安装包    : $($scoopApps -join ', ')")
    Write-Plan ("chezmoi   : $(if ($useChezmoi) { $chezmoiUser + '/' + $set.Chezmoi.RepoName } else { '(跳过)' })")
    Write-Plan ("配置冲突  : $conflictMode")
    Write-Plan ("配置模式  : $linkMode")
    Write-Info ''

    # ------------------------------------------------------------------
    # 保存 state
    # ------------------------------------------------------------------
    $state = @{
        Proxy_Enabled = [bool]$useProxy
        Proxy_Url     = [string]$proxyUrl
        Scoop_Mirror  = [bool]$useScoopMirror
        Scoop_Apps    = @($scoopApps | ForEach-Object { [string]$_ })
        Chezmoi_Use   = [bool]$useChezmoi
        Chezmoi_User  = [string]$chezmoiUser
        Chezmoi_Apply = [bool]$chezmoiApply
        Conflict_Mode = [string]$conflictMode
        Link_Mode     = [string]$linkMode
        Timestamp     = (Get-Date).ToString('s')
    }
    if (-not $Ctx.WhatIf) {
        Save-WindotsState -Path $Ctx.StatePath -State $state
        Write-Success "配置已保存：$($Ctx.StatePath)"
    }

    return $state
}


# =====================================================================
# install：主安装流程
# =====================================================================
function Invoke-Install {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State   # hashtable 或 OrderedDictionary 均可
    )

    $results = [System.Collections.Generic.List[object]]::new()

    # 1. 代理
    if ($State.Proxy_Enabled -and -not [string]::IsNullOrWhiteSpace($State.Proxy_Url)) {
        Set-SessionProxy -Url ([string]$State.Proxy_Url)
    }
    else {
        Set-SessionProxy -Url ''
    }

    # 2. 安装 scoop
    Write-Step '--- 安装 scoop ---'
    if (Test-IsAdministrator) {
        Write-Err 'scoop 必须在普通用户窗口安装，当前为管理员窗口，跳过。'
        $results.Add([pscustomobject]@{ Label = 'scoop'; Status = 'failed'; Detail = '管理员窗口中不能安装 scoop' })
    }
    else {
        $ok = Install-Scoop -UseMirror:([bool]$State.Scoop_Mirror) -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{ Label = 'scoop'; Status = if ($ok) { 'ok' }else { 'failed' }; Detail = '' })
    }

    # 3. 切换镜像（需要 scoop 已装）
    if ([bool]$State.Scoop_Mirror -and ((Test-CommandExists -Name 'scoop') -or $Ctx.WhatIf)) {
        Write-Step '--- 切换 scoop 镜像 ---'
        Switch-ScoopMirror -WhatIf:$Ctx.WhatIf
    }

    # 4. 安装 scoop 包
    Write-Step '--- 安装 scoop 包 ---'
    foreach ($name in $State.Scoop_Apps) {
        $ok = Install-ScoopApp -Name $name -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{ Label = $name; Status = if ($ok) { 'ok' }else { 'failed' }; Detail = '' })
    }

    # 5. 应用本地 dotfiles 配置链接
    Write-Step '--- 应用配置文件 ---'
    $allItems = @()
    foreach ($s in @($Ctx.Packages.Recommended) + @($Ctx.Packages.Optional.Dev) + @($Ctx.Packages.Optional.Term) + @($Ctx.Packages.Optional.Beauty)) {
        if ($State.Scoop_Apps -contains $s.Name) { $allItems += $s }
    }
    $extras = @($Ctx.Packages.Extras)
    $planned = Get-PlannedLinks -RepoRoot $Ctx.Root -SelectedItems $allItems -Extras $extras

    # 在循环前一次性确定链接模式（含开发者模式检测 + 用户选择，只弹一次）
    $resolvedLinkMode = Resolve-LinkMode -RequestedMode ([string]$State.Link_Mode) -WhatIf:$Ctx.WhatIf

    foreach ($link in $planned) {
        if (-not (Test-Path $link.Src)) {
            Write-Warn "配置源不存在，跳过：$($link.Src)"
            $results.Add([pscustomobject]@{ Label = $link.Label; Status = 'skipped'; Detail = '源文件不存在' })
            continue
        }
        $status = Apply-Config `
            -Src          $link.Src `
            -Dest         $link.Dest `
            -BackupRoot   $Ctx.BackupDir `
            -ConflictMode ([string]$State.Conflict_Mode) `
            -LinkMode     $resolvedLinkMode `
            -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{ Label = $link.Label; Status = $status; Detail = '' })
    }

    # 6. chezmoi init（在本地 dotfiles 链接之后运行，chezmoi 管理的配置以 chezmoi 为准）
    if ([bool]$State.Chezmoi_Use -and -not [string]::IsNullOrWhiteSpace($State.Chezmoi_User)) {
        Write-Step '--- 初始化 chezmoi ---'
        $repoName = [string]$Ctx.Settings.Chezmoi.RepoName
        if (-not (Test-CommandExists -Name 'chezmoi')) {
            Write-Warn 'chezmoi 未找到，跳过（请确认已在包列表中选择 chezmoi）'
            $results.Add([pscustomobject]@{ Label = 'chezmoi init'; Status = 'skipped'; Detail = '命令未找到' })
        }
        else {
            $user = [string]$State.Chezmoi_User
            $apply = [bool]$State.Chezmoi_Apply
            if ($Ctx.WhatIf) {
                Write-Plan "[WhatIf] chezmoi init$(if ($apply) {' --apply'}) $user/$repoName"
            }
            else {
                Write-Info "chezmoi init $user/$repoName"
                if ($apply) { & chezmoi init --apply "$user/$repoName" }
                else { & chezmoi init "$user/$repoName" }
            }
            $results.Add([pscustomobject]@{ Label = 'chezmoi init'; Status = 'ok'; Detail = '' })
        }
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}


# =====================================================================
# update：更新包 + 重新链接
# =====================================================================
function Invoke-Update {
    param([Parameter(Mandatory)][pscustomobject] $Ctx)

    Write-Step '=== windots update ==='

    if (-not (Test-CommandExists -Name 'scoop')) {
        Write-Warn 'scoop 未安装，跳过包更新'
    }
    else {
        Write-Info '更新所有 scoop 包...'
        if (-not $Ctx.WhatIf) { & scoop update * }
        else { Write-Plan '[WhatIf] scoop update *' }
    }

    if (Test-CommandExists -Name 'chezmoi') {
        Write-Info '更新 chezmoi 配置...'
        if (-not $Ctx.WhatIf) { & chezmoi update }
        else { Write-Plan '[WhatIf] chezmoi update' }
    }

    Write-Info 'update 完成'
}


# =====================================================================
# link：仅重新同步配置文件链接
# =====================================================================
function Invoke-Link {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State   # hashtable 或 OrderedDictionary 均可
    )

    Write-Step '=== windots link ==='

    $allItems = @()
    foreach ($s in @($Ctx.Packages.Recommended) + @($Ctx.Packages.Optional.Dev) + @($Ctx.Packages.Optional.Term) + @($Ctx.Packages.Optional.Beauty)) {
        if ($State.Scoop_Apps -contains $s.Name) { $allItems += $s }
    }
    $extras = @($Ctx.Packages.Extras)
    $planned = Get-PlannedLinks -RepoRoot $Ctx.Root -SelectedItems $allItems -Extras $extras

    $resolvedLinkMode = Resolve-LinkMode -RequestedMode ([string]$State.Link_Mode) -WhatIf:$Ctx.WhatIf

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($link in $planned) {
        if (-not (Test-Path $link.Src)) {
            Write-Warn "源不存在，跳过：$($link.Src)"
            $results.Add([pscustomobject]@{ Label = $link.Label; Status = 'skipped'; Detail = '源文件不存在' })
            continue
        }
        $status = Apply-Config `
            -Src          $link.Src `
            -Dest         $link.Dest `
            -BackupRoot   $Ctx.BackupDir `
            -ConflictMode ([string]$State.Conflict_Mode) `
            -LinkMode     $resolvedLinkMode `
            -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{ Label = $link.Label; Status = $status; Detail = '' })
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}


# =====================================================================
# 主流程：根据参数路由
# =====================================================================
$ctx = Get-Context
$state = Get-State -StatePath $ctx.StatePath

# 1. Bootstrap 检测：只要在 PS5.1 且未携带 -Resume，就需要切换到 PS7
#    - pwsh 未安装 → 先用 winget 装 PS7，再拉起
#    - pwsh 已安装 → 直接拉起（不需要安装步骤）
if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $Resume) {
    if (-not (Test-CommandExists -Name 'pwsh')) {
        # PS7 尚未安装，走完整 bootstrap（询问代理 → 安装 → 写 state → 拉起）
        $ok = Invoke-Bootstrap -SetupScript (Join-Path $Script:Root 'setup.ps1') -StateFile $ctx.StatePath -WhatIf:$ctx.WhatIf
        if ($ok -and -not $ctx.WhatIf) { exit 0 }
        exit (if ($ok) { 0 } else { 1 })
    }
    else {
        # PS7 已安装，直接在 PS7 中重新运行本脚本
        Write-Warn '当前在 PowerShell 5.1 中运行，切换到 pwsh 7 继续...'
        $scriptPath = Join-Path $Script:Root 'setup.ps1'
        # 把当前收到的参数原样转发（去掉 -Resume，它只由 bootstrap 路径设置）
        $fwdArgs = [System.Collections.Generic.List[string]]::new()
        $fwdArgs.AddRange([string[]]@('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"", '-Resume'))
        if ($WhatIf) { $fwdArgs.Add('-WhatIf') }
        if ($Reconfigure) { $fwdArgs.Add('-Reconfigure') }
        if ($Command) { $fwdArgs.Add($Command) }
        if (-not $ctx.WhatIf) {
            Start-Process pwsh -ArgumentList $fwdArgs
            exit 0
        }
        else {
            Write-Plan "[WhatIf] Start-Process pwsh $($fwdArgs -join ' ')"
        }
    }
}

# PS7 环境：若是从 bootstrap 拉起，安装 git 后清除残缺 state（让后续强制进交互）
if ($Resume -and (Test-Path $ctx.StatePath)) {
    $bootState = try { Read-DataFile -Path $ctx.StatePath } catch { $null }
    if ($bootState -and $bootState.Contains('Bootstrap') -and -not $bootState.Contains('Proxy_Enabled')) {

        # 恢复 bootstrap 阶段的代理设置（用于安装 git）
        $bsProxy = if ($bootState.Contains('Bootstrap_ProxyUrl')) { [string]$bootState['Bootstrap_ProxyUrl'] } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($bsProxy)) {
            Set-SessionProxy -Url $bsProxy
        }

        # 安装 git（PS7 的基础依赖，与 pwsh 一样通过 winget 安装）
        Write-Step '--- 检测基础依赖：git ---'
        Install-Git -WhatIf:$ctx.WhatIf

        # 清除 bootstrap-only state，后续进入完整交互
        Remove-Item -Path $ctx.StatePath -Force -ErrorAction SilentlyContinue
        $state = $null
        Write-Info '基础依赖就绪，准备进入交互配置...'
    }
}

# 2. 注册 windots shim（每次运行都检查，幂等）
Register-WindotsShim -RepoRoot $Script:Root -WhatIf:$ctx.WhatIf

# 3. 注册 WINDOTS_ROOT 环境变量，让 windots.cmd 能定位仓库
if (-not $ctx.WhatIf) {
    [System.Environment]::SetEnvironmentVariable('WINDOTS_ROOT', $Script:Root, 'User')
    $env:WINDOTS_ROOT = $Script:Root
}

# 4. 子命令派发（空参数视为 install）
$cmd = $Command.ToLowerInvariant().Trim()
switch ($cmd) {
    'update' {
        Invoke-Update -Ctx $ctx
        exit 0
    }
    'doctor' {
        Invoke-Doctor -RepoRoot $Script:Root
        exit 0
    }
    'link' {
        if (-not $state) {
            Write-Err '未找到 state 文件，请先运行 windots install 完成初始化'
            exit 1
        }
        Invoke-Link -Ctx $ctx -State $state
        exit 0
    }
    { $_ -notin @('', 'install') } {
        Write-Err "未知子命令：$Command"
        Write-Info '可用子命令：install, update, link, doctor'
        exit 1
    }
    # '' 或 'install' → fall through 到下面的 install 主流程
}

# 5. install 主流程
if (-not $state -or $Reconfigure) {
    $state = Invoke-Interactive -Ctx $ctx
}
else {
    # state 存在时，展示摘要并询问是否直接使用（默认是）
    Clear-Host
    Write-Step '=== 发现已保存的配置 ==='
    Write-Plan ("上次保存时间 : $($state['Timestamp'])")
    Write-Plan ("代理         : $(if ($state['Proxy_Enabled']) { $state['Proxy_Url'] } else { '(无)' })")
    Write-Plan ("安装包       : $($state['Scoop_Apps'] -join ', ')")
    Write-Plan ("chezmoi      : $(if ($state['Chezmoi_Use']) { $state['Chezmoi_User'] } else { '(跳过)' })")
    Write-Plan ("配置冲突     : $($state['Conflict_Mode'])")
    Write-Plan ("配置模式     : $($state['Link_Mode'])")
    Write-Info ''
    $useSaved = Read-YesNo -Prompt '是否使用以上配置直接开始安装？' -Default $true
    if (-not $useSaved) {
        $state = Invoke-Interactive -Ctx $ctx
    }
}

Invoke-Install -Ctx $ctx -State $state