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
    [string] $Command = '',
    [switch] $WhatIf,
    [switch] $Reconfigure,
    [switch] $Resume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $null = & chcp 65001
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
}
catch { }

$Script:Root = $PSScriptRoot

# 加载所有库函数
. (Join-Path $Script:Root 'lib\_load.ps1')

# 早期初始化上下文与 i18n（PS5.1 和 PS7 均需要）
$ctx = Get-Context
Initialize-I18n -Root $ctx.Root -Language ([string]$ctx.Settings.Language)
$state = Get-State -StatePath $ctx.StatePath


# =====================================================================
# Bootstrap 检测：PS5.1 → PS7
# =====================================================================
if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $Resume) {
    if (-not (Test-CommandExists -Name 'pwsh')) {
        $ok = Invoke-Bootstrap `
            -SetupScript (Join-Path $Script:Root 'setup.ps1') `
            -StateFile   $ctx.StatePath `
            -WhatIf:$ctx.WhatIf
        if ($ok -and -not $ctx.WhatIf) { exit 0 }
        exit (if ($ok) { 0 } else { 1 })
    }
    else {
        Write-Warn (msg 'setup.ps5.switching')
        $scriptPath = Join-Path $Script:Root 'setup.ps1'
        $fwdArgs = [System.Collections.Generic.List[string]]::new()
        $fwdArgs.AddRange([string[]]@('-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"", '-Resume'))
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


# =====================================================================
# PS7 环境：-Resume 阶段安装 git 并清除 bootstrap state
# =====================================================================
if ($Resume -and (Test-Path $ctx.StatePath)) {
    $bootState = try { Import-PowerShellDataFile -Path $ctx.StatePath } catch { $null }
    if ($bootState -and $bootState.Contains('Bootstrap') -and -not $bootState.Contains('Proxy_Enabled')) {
        $bsProxy = if ($bootState.Contains('Bootstrap_ProxyUrl')) { [string]$bootState['Bootstrap_ProxyUrl'] } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($bsProxy)) { Set-SessionProxy -Url $bsProxy }

        Write-Step (msg 'setup.git.step')
        Install-Git -WhatIf:$ctx.WhatIf

        Remove-Item -Path $ctx.StatePath -Force -ErrorAction SilentlyContinue
        $state = $null
        Write-Info (msg 'setup.deps.ready')
    }
}

# 注册 windots shim（幂等）
Register-WindotsShim -RepoRoot $Script:Root -WhatIf:$ctx.WhatIf

# 设置 WINDOTS_ROOT 用户环境变量
if (-not $ctx.WhatIf) {
    [System.Environment]::SetEnvironmentVariable('WINDOTS_ROOT', $Script:Root, 'User')
    $env:WINDOTS_ROOT = $Script:Root
}


# =====================================================================
# 子命令派发（空参数视为 install）
# =====================================================================
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
            Write-Err (msg 'setup.state.missing.err')
            exit 1
        }
        Invoke-Link -Ctx $ctx -State $state
        exit 0
    }
    { $_ -notin @('', 'install') } {
        Write-Err  (msg 'setup.cmd.unknown' $Command)
        Write-Info (msg 'setup.cmd.hint')
        exit 1
    }
}


# =====================================================================
# install 主流程
# =====================================================================
if (-not $state -or $Reconfigure) {
    $state = Invoke-Interactive -Ctx $ctx
}
else {
    Clear-Host
    Write-Step (msg 'setup.state.title')
    Write-Plan (msg 'setup.state.timestamp' $state['Timestamp'])
    Write-Plan (msg 'setup.state.proxy'     $(if ($state['Proxy_Enabled']) { $state['Proxy_Url'] } else { msg 'interactive.plan.proxy.none' }))
    Write-Plan (msg 'setup.state.packages'  ($state['Scoop_Apps'] -join ', '))
    Write-Plan (msg 'setup.state.chezmoi'   $(if ($state['Chezmoi_Use']) { $state['Chezmoi_User'] } else { msg 'interactive.plan.chezmoi.skip' }))
    Write-Plan (msg 'setup.state.conflict'  $state['Conflict_Mode'])
    Write-Plan (msg 'setup.state.linkmode'  $state['Link_Mode'])
    Write-Info ''
    $useSaved = Read-YesNo -Prompt (msg 'setup.state.use.prompt') -Default $true
    if (-not $useSaved) {
        $state = Invoke-Interactive -Ctx $ctx
    }
}

Invoke-Install -Ctx $ctx -State $state
