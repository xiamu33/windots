# =====================================================================
# Windots 国际化引擎 (lib/i18n.ps1)
# =====================================================================

$Global:WindotsMessages = $null
$Global:WindotsMessagesFallback = $null
$Global:WindotsLocale = 'zh-CN'

# 加载 i18n 目录。优先级：$Language 参数 > settings.psd1 Language > 系统区域 > 回退 zh-CN
function Initialize-I18n {
    param(
        [Parameter(Mandatory)][string] $Root,
        [string] $Language = ''
    )

    $locale = if (-not [string]::IsNullOrWhiteSpace($Language)) {
        $Language.Trim()
    }
    else {
        $culture = (Get-Culture).Name
        if ($culture -like 'zh-*') { 'zh-CN' }
        elseif ($culture -like 'en-*') { 'en-US' }
        else { 'zh-CN' }
    }

    $i18nDir = Join-Path $Root 'i18n'
    $catalogPath = Join-Path $i18nDir "$locale.psd1"

    if (-not (Test-Path $catalogPath)) {
        $locale = 'zh-CN'
        $catalogPath = Join-Path $i18nDir 'zh-CN.psd1'
    }

    $Global:WindotsLocale = $locale

    if (Test-Path $catalogPath) {
        $Global:WindotsMessages = Import-PowerShellDataFile -Path $catalogPath
    }
    else {
        $Global:WindotsMessages = @{}
    }

    # 非 zh-CN 时加载 zh-CN 作为回退
    if ($locale -ne 'zh-CN') {
        $fallbackPath = Join-Path $i18nDir 'zh-CN.psd1'
        if (Test-Path $fallbackPath) {
            $Global:WindotsMessagesFallback = Import-PowerShellDataFile -Path $fallbackPath
        }
    }
    else {
        $Global:WindotsMessagesFallback = $null
    }
}

# 查询消息键并格式化。额外参数以 {0},{1}... 顺序填入
# 用法：Get-Message 'key'  / Get-Message 'key' $arg1 $arg2
function Get-Message {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]  $Key,
        [Parameter(ValueFromRemainingArguments)][object[]] $FmtArgs
    )
    $msg = $null
    if ($null -ne $Global:WindotsMessages -and $Global:WindotsMessages.ContainsKey($Key)) {
        $msg = [string]$Global:WindotsMessages[$Key]
    }
    elseif ($null -ne $Global:WindotsMessagesFallback -and $Global:WindotsMessagesFallback.ContainsKey($Key)) {
        $msg = [string]$Global:WindotsMessagesFallback[$Key]
    }
    else {
        return $Key
    }

    if ($FmtArgs -and $FmtArgs.Count -gt 0) {
        try { return [string]::Format($msg, [object[]]$FmtArgs) }
        catch { return $msg }
    }
    return $msg
}

Set-Alias -Name msg -Value Get-Message -Scope Global
