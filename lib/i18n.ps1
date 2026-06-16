# =====================================================================
# Windots 国际化引擎 (lib/i18n.ps1)
# =====================================================================

$Script:WindotsDefaultLocale = 'en-US'

$Global:WindotsMessages = $null
$Global:WindotsMessagesFallback = $null
$Global:WindotsLocale = $Script:WindotsDefaultLocale

# 以 UTF-8 无 BOM 读取消息目录（PS5.1 下 Import-PowerShellDataFile 可能误判编码）
function Import-WindotsMessageCatalog {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path $Path)) { return @{} }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $offset = 3
    }
    $utf8 = [Text.UTF8Encoding]::new($false)
    $text = $utf8.GetString($bytes, $offset, $bytes.Length - $offset)
    $data = Invoke-Expression $text
    if ($data -is [hashtable]) { return $data }
    return @{}
}

# 加载 i18n 目录。优先级：$Language 参数 > settings.psd1 Language > 系统区域 > 回退 en-US
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
        else { $Script:WindotsDefaultLocale }
    }

    $i18nDir = Join-Path $Root 'i18n'
    $catalogPath = Join-Path $i18nDir "$locale.psd1"

    if (-not (Test-Path $catalogPath)) {
        $locale = $Script:WindotsDefaultLocale
        $catalogPath = Join-Path $i18nDir "$($Script:WindotsDefaultLocale).psd1"
    }

    $Global:WindotsLocale = $locale

    if (Test-Path $catalogPath) {
        $Global:WindotsMessages = Import-WindotsMessageCatalog -Path $catalogPath
    }
    else {
        $Global:WindotsMessages = @{}
    }

    # 当主语言不是默认语言时，用 en-US 作为键缺失回退
    if ($locale -ne $Script:WindotsDefaultLocale) {
        $fallbackPath = Join-Path $i18nDir "$($Script:WindotsDefaultLocale).psd1"
        if (Test-Path $fallbackPath) {
            $Global:WindotsMessagesFallback = Import-WindotsMessageCatalog -Path $fallbackPath
        }
    }
    else {
        $Global:WindotsMessagesFallback = $null
    }
}

# 查询消息键并格式化。额外参数以 {0},{1}... 顺序填入
# 用法：Get-Message 'key'  / Get-Message 'key' $arg1 $arg2
#       Get-Message 'key' 'fallback' — 键缺失时返回 fallback，否则 fallback 作为 {0}
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
        if ($FmtArgs -and $FmtArgs.Count -gt 0) {
            return [string]$FmtArgs[0]
        }
        return $Key
    }

    if ($FmtArgs -and $FmtArgs.Count -gt 0) {
        try { return [string]::Format($msg, [object[]]$FmtArgs) }
        catch { return $msg }
    }
    return $msg
}

Set-Alias -Name msg -Value Get-Message -Scope Global
