# =====================================================================
# Windots 公共函数库  (lib.ps1)
# 由 setup.ps1 通过 dot-source ". (Join-Path $PSScriptRoot 'lib.ps1')" 加载
# =====================================================================

# 全局缓存：避免反复调用 winget/scoop 子进程
$Global:WindotsDetectionCache = @{}
$Global:WindotsWingetList = $null
$Global:WindotsScoopList = $null
$Global:WindotsBucketList = $null

# 全局日志文件路径（Start-WindotsLog 设置）
$Global:WindotsLogPath = $null


# =====================================================================
# 日志
# =====================================================================

# 写控制台（彩色）+ 文件（若已初始化）
# Message 允许空字符串，用于输出空行
function Write-Log {
    param(
        [AllowEmptyString()] [string] $Message = '',
        [string] $Level = 'INFO',
        [ConsoleColor] $Color = [ConsoleColor]::Gray
    )
    if ([string]::IsNullOrEmpty($Message)) {
        Write-Host ''
        if ($Global:WindotsLogPath) { Add-Content -Path $Global:WindotsLogPath -Value '' -Encoding utf8 }
        return
    }
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $line = "[$stamp] [$Level] $Message"
    Write-Host $line -ForegroundColor $Color
    if ($Global:WindotsLogPath) {
        Add-Content -Path $Global:WindotsLogPath -Value $line -Encoding utf8
    }
}

function Write-Info { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'INFO' -Color Cyan }
function Write-Success { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'OK'   -Color Green }
function Write-Warn { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'WARN' -Color Yellow }
function Write-Err { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'ERR'  -Color Red }
function Write-Step { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'STEP' -Color Magenta }
function Write-Plan { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'PLAN' -Color Blue }

# 初始化日志文件，返回文件路径
function Start-WindotsLog {
    param([Parameter(Mandatory)][string] $LogDir)
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $Global:WindotsLogPath = Join-Path $LogDir "setup-$stamp.log"
    Set-Content -Path $Global:WindotsLogPath -Value "# Windots setup log $stamp" -Encoding utf8
    return $Global:WindotsLogPath
}


# =====================================================================
# 配置与状态文件
# =====================================================================

# 读取 psd1 文件（Import-PowerShellDataFile 只允许字面量，不能执行代码）
function Read-DataFile {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path $Path)) { throw "找不到数据文件: $Path" }
    return Import-PowerShellDataFile -Path $Path
}

# 将相对路径解析为基于仓库根的绝对路径
function Resolve-RepoPath {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Value
    )
    if ([System.IO.Path]::IsPathRooted($Value)) { return $Value }
    return (Join-Path $RepoRoot $Value)
}

# packages.psd1 Dotfiles.Dest 使用占位符前缀，由此函数展开为系统实际路径
# 支持的占位符：
#   HOME\...               -> $HOME\...
#   APPDATA\...            -> $env:APPDATA\...
#   LOCAL_APPDATA\...      -> $env:LOCALAPPDATA\...
#   HOMEPATH\...           -> $env:HOMEPATH\...（较少用）
#   PROFILE_CurrentUserAllHosts -> $PROFILE.CurrentUserAllHosts
function Resolve-DestPath {
    param([Parameter(Mandatory)][string] $Dest)

    if ($Dest -eq 'PROFILE_CurrentUserAllHosts') {
        return $PROFILE.CurrentUserAllHosts
    }
    if ($Dest.StartsWith('HOME\')) {
        return Join-Path $HOME $Dest.Substring(5)
    }
    if ($Dest.StartsWith('APPDATA\')) {
        return Join-Path $env:APPDATA $Dest.Substring(8)
    }
    if ($Dest.StartsWith('LOCAL_APPDATA\')) {
        return Join-Path $env:LOCALAPPDATA $Dest.Substring(13)
    }
    if ($Dest.StartsWith('HOMEPATH\')) {
        return Join-Path $env:HOMEPATH $Dest.Substring(9)
    }
    # 无占位符则原样返回
    return $Dest
}

# 将 hashtable 序列化为 psd1 字符串（仅支持基础类型+数组）
function ConvertTo-PsLiteral {
    param([object] $Value)
    if ($null -eq $Value) { return '$null' }
    switch ($Value.GetType().FullName) {
        'System.Boolean' { return $(if ($Value) { '$true' } else { '$false' }) }
        'System.Int32' { return [string]$Value }
        'System.Int64' { return [string]$Value }
        'System.String' { return "'" + ($Value -replace "'", "''") + "'" }
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [hashtable])) {
        $items = @()
        foreach ($item in $Value) { $items += (ConvertTo-PsLiteral -Value $item) }
        return '@(' + ($items -join ', ') + ')'
    }
    if ($Value -is [hashtable]) {
        $parts = @()
        foreach ($k in $Value.Keys) { $parts += "$k = $(ConvertTo-PsLiteral -Value $Value[$k])" }
        return '@{ ' + ($parts -join '; ') + ' }'
    }
    return "'" + ($Value.ToString() -replace "'", "''") + "'"
}

# 保存交互结果到 state 文件（用 UTF-8 BOM 写入，兼容 PS5.1）
function Save-WindotsState {
    param(
        [Parameter(Mandatory)][string]    $Path,
        [Parameter(Mandatory)][hashtable] $State
    )
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Auto-generated by setup.ps1, do not edit by hand.')
    [void]$sb.AppendLine('@{')
    foreach ($key in ($State.Keys | Sort-Object)) {
        [void]$sb.AppendLine("    $key = $(ConvertTo-PsLiteral -Value $State[$key])")
    }
    [void]$sb.AppendLine('}')
    $utf8Bom = [Text.UTF8Encoding]::new($true)
    [IO.File]::WriteAllText($Path, $sb.ToString(), $utf8Bom)
}


# =====================================================================
# 检测函数（全部使用一次性缓存，避免反复调用外部进程）
# =====================================================================

# 当前会话是否为管理员
function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# 是否已开启 Windows 开发者模式（开启后普通用户也能建符号链接）
function Test-DeveloperMode {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    if (-not (Test-Path $key)) { return $false }
    $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($null -eq $props) { return $false }
    $prop = $props.PSObject.Properties['AllowDevelopmentWithoutDevLicense']
    if ($null -eq $prop) { return $false }
    return ($prop.Value -eq 1)
}

# 命令是否存在于当前 PATH
function Test-CommandExists {
    param([Parameter(Mandatory)][string] $Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# 失效所有列表缓存（安装包后需调用）
function Reset-WindotsDetectionCache {
    $Global:WindotsWingetList = $null
    $Global:WindotsScoopList = $null
    $Global:WindotsBucketList = $null
}

# 一次性获取 winget 已安装列表（全文本，正则匹配 id）
function Get-WindotsWingetList {
    if ($null -ne $Global:WindotsWingetList) { return $Global:WindotsWingetList }
    if (-not (Test-CommandExists -Name 'winget')) {
        $Global:WindotsWingetList = ''
        return ''
    }
    Write-Info '正在获取 winget 已安装列表（首次稍慢）...'
    $Global:WindotsWingetList = (& winget list --source winget --accept-source-agreements 2>$null | Out-String)
    return $Global:WindotsWingetList
}

# winget 包是否已安装（精确 id 匹配）
function Test-WingetInstalled {
    param([Parameter(Mandatory)][string] $Id)
    $text = Get-WindotsWingetList
    if ([string]::IsNullOrEmpty($text)) { return $false }
    $pat = '(^|\s)' + [regex]::Escape($Id) + '(\s|$)'
    return [regex]::IsMatch($text, $pat, 'IgnoreCase,Multiline')
}

# 一次性获取 scoop 已安装包列表（小写 hashtable）
function Get-WindotsScoopList {
    if ($null -ne $Global:WindotsScoopList) { return $Global:WindotsScoopList }
    $map = @{}
    if (-not (Test-CommandExists -Name 'scoop')) { $Global:WindotsScoopList = $map; return $map }
    # *>&1 把所有输出流合并，避免 scoop 的 Write-Host 泄漏到控制台
    $out = (& scoop list *>&1 | Out-String)
    foreach ($line in ($out -split "`r?`n")) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t -match '^Name\s+Version' -or $t -match '^----' -or $t -match '^Installed apps') { continue }
        $parts = $t -split '\s+', 2
        if ($parts[0]) { $map[$parts[0].ToLowerInvariant()] = $true }
    }
    $Global:WindotsScoopList = $map
    return $map
}

# scoop 包是否已安装
function Test-ScoopInstalled {
    param([Parameter(Mandatory)][string] $Name)
    return (Get-WindotsScoopList).ContainsKey($Name.ToLowerInvariant())
}

# 一次性获取 scoop bucket 列表（名 → URL）
function Get-WindotsBucketList {
    if ($null -ne $Global:WindotsBucketList) { return $Global:WindotsBucketList }
    $map = @{}
    if (-not (Test-CommandExists -Name 'scoop')) { $Global:WindotsBucketList = $map; return $map }
    $out = (& scoop bucket list *>&1 | Out-String)
    foreach ($line in ($out -split "`r?`n")) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t -match '^Name\s+Source' -or $t -match '^----') { continue }
        $parts = $t -split '\s+', 3
        if ($parts.Length -gt 1) { $map[$parts[0]] = $parts[1] }
        elseif ($parts[0]) { $map[$parts[0]] = '' }
    }
    $Global:WindotsBucketList = $map
    return $map
}


# =====================================================================
# 代理
# =====================================================================

# 设置或清除当前会话的代理（HTTP_PROXY / HTTPS_PROXY / ALL_PROXY）
# winget、curl、git、chezmoi 都会读取这些环境变量
function Set-SessionProxy {
    param([string] $Url)
    if ([string]::IsNullOrWhiteSpace($Url)) {
        Remove-Item Env:HTTP_PROXY  -ErrorAction SilentlyContinue
        Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
        Remove-Item Env:ALL_PROXY   -ErrorAction SilentlyContinue
        return
    }
    $env:HTTP_PROXY = $Url
    $env:HTTPS_PROXY = $Url
    $env:ALL_PROXY = $Url
    Write-Info "已为当前会话设置代理：$Url"
}


# =====================================================================
# 交互 UI
# =====================================================================

# 是 / 否提示（回车走默认值）
function Read-YesNo {
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [bool] $Default = $true
    )
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        switch ($answer.Trim().ToLowerInvariant()) {
            { $_ -in 'y', 'yes' } { return $true }
            { $_ -in 'n', 'no' } { return $false }
            default { Write-Warn '请输入 y 或 n' }
        }
    }
}

# 文本输入（回车走默认值）
function Read-Text {
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [string] $Default = ''
    )
    $shown = if ($Default) { "$Prompt (默认: $Default)" } else { $Prompt }
    $answer = Read-Host $shown
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

# 多选菜单（↑↓移动, 空格切换, A全选, N全不选, Enter确认, Esc取消）
# 返回被选中的对象数组
function Select-Items {
    param(
        [Parameter(Mandatory)][string]   $Title,
        [Parameter(Mandatory)][object[]] $Items,
        [scriptblock] $Labeler = { param($x) [string]$x },
        [scriptblock] $DefaultSet = { param($x) $false },
        [string[]]    $Disabled = @()           # 这些名称显示为灰色占位，不可选
    )
    if ($Items.Count -eq 0) { Write-Warn "$Title : 无可选项，跳过"; return @() }

    $selected = New-Object 'bool[]' $Items.Count
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $selected[$i] = [bool](& $DefaultSet $Items[$i])
    }
    $cursor = 0

    while ($true) {
        Clear-Host
        Write-Host $Title -ForegroundColor Magenta
        Write-Host '  ↑/↓ 移动  空格 切换  A 全选  N 全不选  Enter 确认  Esc 取消' -ForegroundColor DarkGray
        Write-Host ''

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $label = & $Labeler $Items[$i]
            $isDisabled = $Disabled -contains $label
            $mark = if ($selected[$i]) { 'x' } else { ' ' }
            $arrow = if ($i -eq $cursor) { '>' } else { ' ' }

            if ($isDisabled) {
                $color = [ConsoleColor]::DarkGray
                Write-Host ("  [ ] $label  [暂不支持]") -ForegroundColor $color
            }
            else {
                $color = if ($i -eq $cursor) { [ConsoleColor]::Cyan }
                elseif ($selected[$i]) { [ConsoleColor]::Green }
                else { [ConsoleColor]::Gray }
                Write-Host ("$arrow [$mark] $label") -ForegroundColor $color
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' { if ($cursor -gt 0) { $cursor-- } }
            'DownArrow' { if ($cursor -lt $Items.Count - 1) { $cursor++ } }
            'Spacebar' {
                $lbl = & $Labeler $Items[$cursor]
                if ($Disabled -notcontains $lbl) { $selected[$cursor] = -not $selected[$cursor] }
            }
            'A' {
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    $lbl = & $Labeler $Items[$i]
                    if ($Disabled -notcontains $lbl) { $selected[$i] = $true }
                } 
            }
            'N' { for ($i = 0; $i -lt $Items.Count; $i++) { $selected[$i] = $false } }
            'Enter' {
                $result = @()
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    if ($selected[$i]) { $result += , $Items[$i] }
                }
                return $result
            }
            'Escape' { return @() }
        }
    }
}

# 单选菜单（↑↓移动，Enter选中）
# 返回被选中的对象
function Select-One {
    param(
        [Parameter(Mandatory)][string]   $Title,
        [Parameter(Mandatory)][object[]] $Items,
        [scriptblock] $Labeler = { param($x) [string]$x },
        [int]         $DefaultIdx = 0
    )
    if ($Items.Count -eq 0) { return $null }
    $cursor = $DefaultIdx
    while ($true) {
        Clear-Host
        Write-Host $Title -ForegroundColor Magenta
        Write-Host '  ↑/↓ 移动  Enter 确认' -ForegroundColor DarkGray
        Write-Host ''
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $label = & $Labeler $Items[$i]
            $arrow = if ($i -eq $cursor) { '>' } else { ' ' }
            $color = if ($i -eq $cursor) { [ConsoleColor]::Cyan } else { [ConsoleColor]::Gray }
            Write-Host ("$arrow $label") -ForegroundColor $color
        }
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' { if ($cursor -gt 0) { $cursor-- } }
            'DownArrow' { if ($cursor -lt $Items.Count - 1) { $cursor++ } }
            'Enter' { return $Items[$cursor] }
        }
    }
}


# =====================================================================
# Bootstrap：PS5.1 引导阶段
# 负责安装 PowerShell 7，然后拉起 pwsh 继续执行
# =====================================================================

# 安装 git（通过 winget user scope，不需管理员）
# git 是后续所有脚本的基础依赖（chezmoi / scoop 等均需要）
function Install-Git {
    param([switch] $WhatIf)

    if (Test-CommandExists -Name 'git') {
        Write-Success 'git 已安装，跳过'
        return $true
    }
    if (-not (Test-CommandExists -Name 'winget')) {
        Write-Err 'winget 不可用，无法安装 git'
        return $false
    }
    if ($WhatIf) {
        Write-Plan '[WhatIf] winget install --id Git.Git -e --scope user --accept-package-agreements --accept-source-agreements'
        return $true
    }
    Write-Info '正在通过 winget 安装 git...'
    & winget install --id Git.Git --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Err "git 安装失败 (exit=$LASTEXITCODE)"
        return $false
    }
    Update-SessionPath
    Write-Success 'git 安装完成'
    return $true
}

# 安装 PowerShell 7（通过 winget user scope，不需管理员）
function Install-PSCore7 {
    param([switch] $WhatIf)

    if (Test-CommandExists -Name 'pwsh') {
        Write-Success 'PowerShell 7 已安装，跳过'
        return $true
    }
    if (-not (Test-CommandExists -Name 'winget')) {
        Write-Err 'winget 不可用。请在 Microsoft Store 安装「应用安装程序」后重试。'
        return $false
    }
    if ($WhatIf) {
        Write-Plan '[WhatIf] winget install --id Microsoft.PowerShell -e --scope user --accept-package-agreements --accept-source-agreements'
        return $true
    }
    Write-Info '正在通过 winget 安装 PowerShell 7...'
    & winget install --id Microsoft.PowerShell --source winget
    # winget install --id Microsoft.PowerShell -e --scope user --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Err "PowerShell 7 安装失败 (exit=$LASTEXITCODE)"
        return $false
    }
    Update-SessionPath
    Write-Success 'PowerShell 7 安装完成'
    return $true
}

# PS5.1 Bootstrap 主函数：装完 PS7 后，写 state 并启动 pwsh 继续运行
# $SetupScript : setup.ps1 的绝对路径
# $StateFile   : state 文件路径（写入 Bootstrap=true 标记）
# $WhatIf      : 预演模式
function Invoke-Bootstrap {
    param(
        [Parameter(Mandatory)][string] $SetupScript,
        [Parameter(Mandatory)][string] $StateFile,
        [switch] $WhatIf
    )

    Write-Step '=== Bootstrap：PowerShell 5.1 引导 ==='
    Write-Warn '当前在 PowerShell 5.1 中运行。将先安装 PowerShell 7，再在新窗口继续执行。'

    # 询问代理（仅在这里问，因为后续 PS7 里重新交互时会再问一次）
    $useProxy = Read-YesNo -Prompt '安装 PowerShell 7 时是否使用代理（访问 GitHub）？' -Default $false
    if ($useProxy) {
        $proxyUrl = Read-Text -Prompt '代理地址'
        Set-SessionProxy -Url $proxyUrl
    }

    $ok = Install-PSCore7 -WhatIf:$WhatIf
    if (-not $ok) {
        Write-Err '无法安装 PowerShell 7，退出。'
        return $false
    }

    # 写入 bootstrap 标记，同时保存代理设置（PS7 拉起后安装 git 时复用）
    $proxyForState = if ($useProxy) { $proxyUrl } else { '' }
    $state = @{ Bootstrap = $true; Bootstrap_ProxyUrl = $proxyForState }
    if (-not $WhatIf) {
        Save-WindotsState -Path $StateFile -State $state
    }

    if ($WhatIf) {
        Write-Plan "[WhatIf] Start-Process pwsh -ArgumentList '-NoExit -File ""$SetupScript"" -Resume'"
        return $true
    }

    Write-Info '正在启动 PowerShell 7 窗口继续执行...'
    # -NoExit 让窗口保持，用户能看到输出；脚本里 -Resume 告知跳过 bootstrap
    Start-Process pwsh -ArgumentList ('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$SetupScript`"", '-Resume')
    Write-Success 'PowerShell 7 窗口已启动，本窗口可以关闭。'
    return $true
}


# =====================================================================
# windots 全局命令注册
# =====================================================================

# 把 bin/windots.cmd 复制到 ~/.local/bin/ 并确保其在用户 PATH 中
function Register-WindotsShim {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [switch] $WhatIf
    )

    $shimSrc = Join-Path $RepoRoot 'bin\windots.cmd'
    $localBin = Join-Path $HOME '.local\bin'
    $shimDest = Join-Path $localBin 'windots.cmd'

    if (-not (Test-Path $shimSrc)) {
        Write-Warn "找不到 shim 源文件：$shimSrc，跳过 windots 注册"
        return
    }

    if ($WhatIf) {
        Write-Plan "[WhatIf] 复制 $shimSrc → $shimDest"
        Write-Plan "[WhatIf] 添加 $localBin 到用户 PATH"
        return
    }

    # 确保 ~/.local/bin 存在
    if (-not (Test-Path $localBin)) {
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    }

    Copy-Item -Path $shimSrc -Destination $shimDest -Force
    Write-Success "windots.cmd 已复制到 $shimDest"

    # 把 ~/.local/bin 加入用户 PATH（如果还没有）
    $currentUserPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if ($currentUserPath -notlike "*$localBin*") {
        $newPath = if ([string]::IsNullOrEmpty($currentUserPath)) { $localBin } else { "$currentUserPath;$localBin" }
        [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        # 也更新当前会话的 PATH
        $env:Path = $env:Path + ";$localBin"
        Write-Success "已将 $localBin 加入用户 PATH"
        Write-Warn '请重开 PowerShell 窗口后 windots 命令才生效'
    }
    else {
        Write-Success "windots 已在 PATH 中可用"
    }
}


# =====================================================================
# Scoop 镜像切换
# =====================================================================

# 把 PATH 从注册表重新刷到当前会话（安装包后调用）
function Update-SessionPath {
    $m = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u"
}

# 安装 scoop 本体
function Install-Scoop {
    param(
        [switch] $UseMirror,
        [switch] $WhatIf
    )
    if (Test-CommandExists -Name 'scoop') {
        Write-Success 'scoop 已安装，跳过'
        return $true
    }
    if (Test-IsAdministrator) {
        Write-Err 'scoop 不能在管理员窗口中安装。请使用普通用户 PowerShell 窗口重新运行。'
        return $false
    }

    $officialUrl = 'https://get.scoop.sh'
    $mirrorUrl = 'https://gitee.com/scoop-installer/install/raw/master/install.ps1'
    $srcUrl = if ($UseMirror) { $mirrorUrl } else { $officialUrl }

    if ($WhatIf) {
        Write-Plan "[WhatIf] 从 $srcUrl 下载并执行 scoop 安装脚本"
        return $true
    }
    Write-Info "正在安装 scoop（来源：$srcUrl）..."
    Invoke-Expression (Invoke-RestMethod -Uri $srcUrl)
    Update-SessionPath
    return (Test-CommandExists -Name 'scoop')
}

# 切换 scoop 本体和 bucket 到 gitee 镜像（按 Interactive.md 提供的命令）
# 若已是 gitee 镜像则跳过，避免重复执行
function Switch-ScoopMirror {
    param([switch] $WhatIf)

    $giteeRepo = 'https://gitee.com/scoop-installer/scoop'

    if ($WhatIf) {
        Write-Plan "[WhatIf] scoop config SCOOP_REPO `"$giteeRepo`""
        Write-Plan '[WhatIf] scoop update'
        Write-Plan '[WhatIf] scoop bucket rm main; scoop bucket add main; scoop bucket add extras'
        return
    }

    # 检测当前 SCOOP_REPO 是否已是 gitee，是则跳过
    $currentRepo = (& scoop config SCOOP_REPO 2>$null | Out-String).Trim()
    if ($currentRepo -eq $giteeRepo) {
        Write-Success 'scoop 镜像已是 gitee，跳过'
        return
    }

    Write-Info '正在切换 scoop 到 gitee 镜像...'
    & scoop config SCOOP_REPO $giteeRepo
    & scoop update
    & scoop bucket rm main   2>$null
    & scoop bucket add main
    & scoop bucket add extras 2>$null

    $Global:WindotsBucketList = $null
    Write-Success 'scoop 镜像已切换'
}

# 安装单个 scoop 包（一次性缓存，只调用一次 scoop list）
function Install-ScoopApp {
    param(
        [Parameter(Mandatory)][string] $Name,
        [switch] $WhatIf
    )
    if (Test-ScoopInstalled -Name $Name) {
        Write-Success "scoop: $Name 已安装，跳过"
        return $true
    }
    if ($WhatIf) {
        Write-Plan "[WhatIf] scoop install $Name"
        return $true
    }
    Write-Info "正在通过 scoop 安装：$Name"
    & scoop install $Name
    if ($LASTEXITCODE -ne 0) {
        Write-Err "scoop 安装失败：$Name (exit=$LASTEXITCODE)"
        return $false
    }
    $Global:WindotsScoopList = $null
    Write-Success "scoop: $Name 安装完成"
    return $true
}


# =====================================================================
# 备份
# =====================================================================

# 将 $Path 备份到 $BackupRoot/<timestamp>/
#   单文件 → <timestamp>/<basename>.bak
#   目录   → <timestamp>/<dirname>.bak.zip
# 返回备份目标路径，失败返回 $null
function Backup-Path {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $BackupRoot
    )
    if (-not (Test-Path $Path)) { return $null }

    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $destDir = Join-Path $BackupRoot $stamp
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $item = Get-Item $Path -Force
    if ($item.PSIsContainer) {
        # 目录 → zip
        $zipName = $item.Name + '.bak.zip'
        $zipPath = Join-Path $destDir $zipName
        Compress-Archive -Path $Path -DestinationPath $zipPath -Force
        Write-Warn "目录已备份为 zip：$zipPath"
        return $zipPath
    }
    else {
        # 单文件 → .bak
        $bakName = $item.Name + '.bak'
        $bakPath = Join-Path $destDir $bakName
        Copy-Item -Path $Path -Destination $bakPath -Force
        Write-Warn "文件已备份：$bakPath"
        return $bakPath
    }
}


# =====================================================================
# 配置应用
# =====================================================================

# 将 packages.psd1 中所有选中工具的 Dotfiles + Extras 展开为待处理列表
# 返回对象数组，每项含 Src（绝对路径）和 Dest（绝对路径）
function Get-PlannedLinks {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [object[]] $SelectedItems = @(),   # 用户选中的工具项（可为空）
        [object[]] $Extras = @()    # packages.psd1 Extras 数组（可为空）
    )
    $links = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $SelectedItems) {
        if ((-not $item.Contains('Dotfiles')) -or ($null -eq $item.Dotfiles)) { continue }
        $dotfilesList = @($item.Dotfiles)
        foreach ($dot in $dotfilesList) {
            if ($null -eq $dot) { continue }
            $src = Resolve-RepoPath -RepoRoot $RepoRoot -Value ([string]$dot.Src)
            $dest = Resolve-DestPath -Dest ([string]$dot.Dest)
            $links.Add([pscustomobject]@{ Src = $src; Dest = $dest; Label = $item.Name })
        }
    }

    foreach ($extra in $Extras) {
        $src = Resolve-RepoPath -RepoRoot $RepoRoot -Value ([string]$extra.Src)
        $dest = Resolve-DestPath -Dest ([string]$extra.Dest)
        $links.Add([pscustomobject]@{ Src = $src; Dest = $dest; Label = (Split-Path $src -Leaf) })
    }

    return @($links)
}

# 在应用所有配置前，一次性确定实际使用的链接模式
# 若请求 symlink 但未开启开发者模式，弹一次提示让用户选择 (R)重试/(C)复制
# WhatIf 模式下直接返回请求的模式（不交互）
function Resolve-LinkMode {
    param(
        [string] $RequestedMode = 'symlink',
        [switch] $WhatIf
    )

    if ($RequestedMode -ne 'symlink' -or $WhatIf) { return $RequestedMode }

    # 已有权限（开发者模式或管理员）→ 直接用 symlink
    if ((Test-DeveloperMode) -or (Test-IsAdministrator)) { return 'symlink' }

    # 没有权限，提示用户选择一次（适用于全部配置文件）
    Clear-Host
    Write-Warn '=== 需要开发者模式或管理员权限才能创建符号链接 ==='
    Write-Info '请前往：设置 → 隐私与安全性 → 开发者专用 → 开启「开发人员模式」'
    Write-Info '开启后按 R 重试检测，或按 C 改为复制文件模式'
    Write-Host ''

    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'R' -or $key.KeyChar -eq 'r') {
            if (Test-DeveloperMode) {
                Write-Success '已检测到开发者模式，使用符号链接'
                return 'symlink'
            }
            Write-Warn '未检测到开发者模式，请确认已开启后再按 R'
        }
        elseif ($key.Key -eq 'C' -or $key.KeyChar -eq 'c') {
            Write-Info '已选择复制模式，所有配置文件将使用复制方式应用'
            return 'copy'
        }
    }
}

# 应用单个配置项（软链接或复制）
# $ConflictMode : 'overwrite' | 'backup' | 'keep'
# $LinkMode     : 'symlink' | 'copy'（应已由 Resolve-LinkMode 预先确定，不再自行弹交互）
# 返回 'ok' | 'skipped' | 'failed'
function Apply-Config {
    param(
        [Parameter(Mandatory)][string] $Src,
        [Parameter(Mandatory)][string] $Dest,
        [Parameter(Mandatory)][string] $BackupRoot,
        [string] $ConflictMode = 'overwrite',
        [string] $LinkMode = 'symlink',
        [switch] $WhatIf
    )

    # 源必须存在
    if (-not (Test-Path $Src)) {
        Write-Warn "源不存在，跳过：$Src"
        return 'skipped'
    }

    # 目标已存在的处理
    if (Test-Path $Dest -ErrorAction SilentlyContinue) {
        # 检查是否已是指向正确源的符号链接
        $item = Get-Item $Dest -Force -ErrorAction SilentlyContinue
        if ($item) {
            $isSymlink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ($isSymlink -and $item.Target -eq $Src) {
                Write-Success "链接已正确：$Dest"
                return 'ok'
            }
        }

        switch ($ConflictMode) {
            'keep' {
                Write-Warn "保留原配置，跳过：$Dest"
                return 'skipped'
            }
            'backup' {
                if ($WhatIf) {
                    Write-Plan "[WhatIf] 备份 $Dest"
                }
                else {
                    Backup-Path -Path $Dest -BackupRoot $BackupRoot | Out-Null
                    Remove-Item -Path $Dest -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            default {
                # overwrite
                if ($WhatIf) {
                    Write-Plan "[WhatIf] 覆盖现有配置：$Dest"
                }
                else {
                    Remove-Item -Path $Dest -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # 确保父目录存在
    $parent = Split-Path $Dest -Parent
    if ($parent -and -not (Test-Path $parent)) {
        if ($WhatIf) {
            Write-Plan "[WhatIf] New-Item Directory $parent"
        }
        else {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }

    if ($LinkMode -eq 'symlink') {
        if ($WhatIf) {
            Write-Plan "[WhatIf] New-Item -ItemType SymbolicLink -Path '$Dest' -Target '$Src'"
            return 'ok'
        }
        try {
            New-Item -ItemType SymbolicLink -Path $Dest -Target $Src -Force | Out-Null
            Write-Success "符号链接：$Dest → $Src"
            return 'ok'
        }
        catch {
            Write-Err "创建符号链接失败：$Dest ($($_.Exception.Message))"
            return 'failed'
        }
    }
    else {
        # copy
        if ($WhatIf) {
            Write-Plan "[WhatIf] Copy-Item '$Src' → '$Dest'"
            return 'ok'
        }
        try {
            if ((Get-Item $Src).PSIsContainer) {
                Copy-Item -Path $Src -Destination $Dest -Recurse -Force
            }
            else {
                Copy-Item -Path $Src -Destination $Dest -Force
            }
            Write-Success "已复制：$Dest ← $Src"
            return 'ok'
        }
        catch {
            Write-Err "复制失败：$Dest ($($_.Exception.Message))"
            return 'failed'
        }
    }
}


# =====================================================================
# windots doctor
# =====================================================================

# 检查关键环境是否健康，输出检查表
function Invoke-Doctor {
    param([Parameter(Mandatory)][string] $RepoRoot)

    Write-Step '=== windots doctor ==='
    $checks = [System.Collections.Generic.List[object]]::new()

    # PS 版本
    $psVer = $PSVersionTable.PSVersion
    $psOk = $psVer.Major -ge 7
    $checks.Add([pscustomobject]@{ Item = 'PowerShell 版本'; Status = if ($psOk) { 'OK' }else { 'WARN' }; Detail = "$psVer$(if(-not $psOk){' (建议升级到 7+)'})" })

    # scoop
    $scoopOk = Test-CommandExists -Name 'scoop'
    $checks.Add([pscustomobject]@{ Item = 'scoop'; Status = if ($scoopOk) { 'OK' }else { 'FAIL' }; Detail = if ($scoopOk) { '已安装' }else { '未找到' } })

    # git
    $gitOk = Test-CommandExists -Name 'git'
    $checks.Add([pscustomobject]@{ Item = 'git'; Status = if ($gitOk) { 'OK' }else { 'WARN' }; Detail = if ($gitOk) { '已安装' }else { '未找到' } })

    # windots PATH
    $localBin = Join-Path $HOME '.local\bin'
    $windotsOk = Test-Path (Join-Path $localBin 'windots.cmd')
    $checks.Add([pscustomobject]@{ Item = 'windots.cmd'; Status = if ($windotsOk) { 'OK' }else { 'WARN' }; Detail = if ($windotsOk) { "$localBin" }else { '未注册，运行 windots install 重新安装' } })

    # state 文件
    $settings = Read-DataFile -Path (Join-Path $RepoRoot 'settings.psd1')
    $statePath = Resolve-RepoPath -RepoRoot $RepoRoot -Value $settings.Paths.State
    $stateOk = Test-Path $statePath
    $checks.Add([pscustomobject]@{ Item = 'state 文件'; Status = if ($stateOk) { 'OK' }else { 'INFO' }; Detail = if ($stateOk) { $statePath }else { '不存在，首次运行会自动创建' } })

    # 输出检查表
    Write-Host ''
    foreach ($c in $checks) {
        $color = switch ($c.Status) {
            'OK' { [ConsoleColor]::Green }
            'WARN' { [ConsoleColor]::Yellow }
            'FAIL' { [ConsoleColor]::Red }
            default { [ConsoleColor]::Cyan }
        }
        Write-Host ("[{0,-4}] {1,-20} {2}" -f $c.Status, $c.Item, $c.Detail) -ForegroundColor $color
    }
    Write-Host ''
}


# =====================================================================
# 末尾总结
# =====================================================================

# 汇总本次运行结果，输出彩色表格
function Show-Summary {
    param(
        [Parameter(Mandatory)][object[]] $Results,  # @{ Label=; Status='ok'|'skipped'|'failed'; Detail= }
        [string] $LogFile = ''
    )
    Write-Host ''
    Write-Step '=== 运行总结 ==='

    $ok = @($Results | Where-Object { $_.Status -eq 'ok' })
    $skipped = @($Results | Where-Object { $_.Status -eq 'skipped' })
    $failed = @($Results | Where-Object { $_.Status -eq 'failed' })

    if ($ok.Count -gt 0) {
        Write-Host ('[OK]    ' + ($ok | ForEach-Object { $_.Label }) -join ', ') -ForegroundColor Green
    }
    if ($skipped.Count -gt 0) {
        Write-Host ('[SKIP]  ' + ($skipped | ForEach-Object { $_.Label }) -join ', ') -ForegroundColor Yellow
    }
    if ($failed.Count -gt 0) {
        Write-Host ('[FAIL]  ' + ($failed | ForEach-Object { $_.Label }) -join ', ') -ForegroundColor Red
    }
    Write-Host ''
    Write-Info ("完成: $($ok.Count) 成功  $($skipped.Count) 跳过  $($failed.Count) 失败")
    if ($LogFile) { Write-Info "详细日志：$LogFile" }
}