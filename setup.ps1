# =====================================================================
# Windots Setup  (setup.ps1)
# 需要 PowerShell 7+（pwsh）；首次安装请使用 install.ps1
# 编码：UTF-8 无 BOM
#
# 用法：
#   .\setup.ps1              # 智能默认：无 state → init；有 state → install
#   .\setup.ps1 init         # 全量交互初始化
#   .\setup.ps1 install      # 增选包并安装
#   .\setup.ps1 update       # scoop update * + chezmoi
#   .\setup.ps1 link         # 重新应用配置文件链接
#   .\setup.ps1 doctor       # 环境健康检查
#
# 参数：
#   -WhatIf       预演模式
#   -Reconfigure  忽略已保存的 state，强制重跑 init 交互（仅 init 有效）
# =====================================================================

[CmdletBinding()]
param(
    [string] $Command = '',
    [switch] $WhatIf,
    [switch] $Reconfigure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    try {
        $null = & chcp 65001
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    }
    catch { }
    $root = $PSScriptRoot
    . (Join-Path $root 'lib\i18n.ps1')
    $lang = ''
    $settingsPath = Join-Path $root 'settings.psd1'
    if (Test-Path $settingsPath) {
        try {
            $settings = Import-PowerShellDataFile -Path $settingsPath
            if ($settings.Language -and -not [string]::IsNullOrWhiteSpace([string]$settings.Language)) {
                $lang = [string]$settings.Language
            }
        }
        catch { }
    }
    Initialize-I18n -Root $root -Language $lang
    Write-Error (msg 'setup.ps7.required')
    exit 1
}

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

# 注册 windots shim（幂等）
Register-WindotsShim -RepoRoot $Script:Root -WhatIf:$ctx.WhatIf

# 设置 WINDOTS_ROOT 用户环境变量
if (-not $ctx.WhatIf) {
    $currentRoot = [System.Environment]::GetEnvironmentVariable('WINDOTS_ROOT', 'User')
    if ($currentRoot -ne $Script:Root) {
        [System.Environment]::SetEnvironmentVariable('WINDOTS_ROOT', $Script:Root, 'User')
    }
    $env:WINDOTS_ROOT = $Script:Root
}


# =====================================================================
# 子命令派发（空参数智能默认：无 state / -Reconfigure → init，否则 → install）
# =====================================================================
$cmd = $Command.ToLowerInvariant().Trim()
if ($cmd -eq '') {
    if ($Reconfigure -or -not $state) { $cmd = 'init' }
    else { $cmd = 'install' }
}

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
    'install' {
        if ($Reconfigure) {
            Write-Warn (msg 'setup.reconfigure.init.hint')
        }
        if (-not $state) {
            Write-Err (msg 'install.state.missing.err')
            exit 1
        }
        $state = Invoke-InteractivePackages -Ctx $ctx -State $state
        Invoke-Install -Ctx $ctx -State $state
        exit 0
    }
    'init' {
        if (-not $state -or $Reconfigure) {
            $state = Invoke-Interactive -Ctx $ctx
        }
        else {
            Clear-Host
            Write-Step (msg 'setup.state.title')
            Write-Plan (msg 'setup.state.timestamp' $state['Timestamp'])
            Write-Plan (msg 'setup.state.proxy'     $(if ($state['Proxy_Enabled']) { $state['Proxy_Url'] } else { msg 'interactive.plan.proxy.none' }))
            Write-Plan (msg 'setup.state.mirror'    $(if ([bool]$state['Scoop_Mirror']) { msg 'interactive.plan.mirror.enabled' } else { msg 'interactive.plan.mirror.disabled' }))
            $savedSelected = @()
            if ($state.Contains('Selected_Packages') -and $null -ne $state['Selected_Packages']) {
                $savedSelected = @($state['Selected_Packages'] | ForEach-Object { [string]$_ })
            }
            Write-PackageList -TitleKey 'setup.state.packages' `
                -SelectedNames $savedSelected `
                -ScoopApps     @($state['Scoop_Apps'] | ForEach-Object { [string]$_ }) `
                -PackagesDef   $ctx.Packages
            Write-Plan (msg 'setup.state.chezmoi'   $(if ($state['Chezmoi_Use']) { $state['Chezmoi_User'] } else { msg 'interactive.plan.chezmoi.skip' }))
            Write-Plan (msg 'setup.state.conflict'  $state['Conflict_Mode'])
            Write-Plan (msg 'setup.state.linkmode'  $state['Link_Mode'])
            Write-Info ''
            $useSaved = Read-YesNo -Prompt (msg 'setup.state.use.prompt') -Default $true
            if (-not $useSaved) {
                $state = Invoke-Interactive -Ctx $ctx
            }
        }
        Invoke-Init -Ctx $ctx -State $state
        exit 0
    }
    default {
        Write-Err  (msg 'setup.cmd.unknown' $Command)
        Write-Info (msg 'setup.cmd.hint')
        exit 1
    }
}
