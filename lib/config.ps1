# =====================================================================
# Windots 配置与状态文件 (lib/config.ps1)
# =====================================================================

function Read-DataFile {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path $Path)) { throw (msg 'config.notfound' $Path) }
    return Import-PowerShellDataFile -Path $Path
}

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Value
    )
    if ([System.IO.Path]::IsPathRooted($Value)) { return $Value }
    return (Join-Path $RepoRoot $Value)
}

# packages.psd1 Dotfiles.Dest 占位符展开
# 支持：HOME\  APPDATA\  LOCAL_APPDATA\  HOMEPATH\  SCOOP_ROOT\  SCOOP_GLOBAL\  SCOOP_PATH\
#       PROFILE  PROFILE_CurrentUserAllHosts  PROFILE_ROOT\
# SCOOP_PATH\：按包 intent scope 自动选 user/global scoop 根（需 -PackageName -State -PackagesDef）
# Src/Dest glob: * matches one path segment; star count must match in Src and Dest
function Test-DotfilesGlobPattern {
    param([Parameter(Mandatory)][string] $Path)
    return ($Path.IndexOf('*') -ge 0) -or ($Path.IndexOf('?') -ge 0)
}

function Convert-DotfilesGlobToRegex {
    param([Parameter(Mandatory)][string] $Glob)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')
    for ($i = 0; $i -lt $Glob.Length; $i++) {
        $c = $Glob[$i]
        switch ($c) {
            '*' { [void]$sb.Append('([^\\/]*)') }
            '?' { [void]$sb.Append('[^\\/]') }
            '\' { [void]$sb.Append('\\') }
            '/' { [void]$sb.Append('[\\/]') }
            default {
                [void]$sb.Append([regex]::Escape([string]$c))
            }
        }
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

function Merge-DotfilesGlobDest {
    param(
        [Parameter(Mandatory)][string] $LiteralPrefix,
        [Parameter(Mandatory)][string] $GlobSuffix,
        [Parameter(Mandatory)][string[]] $Captures
    )

    $parts = $GlobSuffix -split '\*', [System.StringSplitOptions]::None
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append($LiteralPrefix)
    for ($i = 0; $i -lt $parts.Length; $i++) {
        [void]$sb.Append($parts[$i])
        if ($i -lt $Captures.Length) { [void]$sb.Append($Captures[$i]) }
    }
    return $sb.ToString()
}

function Expand-DotfilesGlobEntry {
    param(
        [Parameter(Mandatory)][string] $SrcPattern,
        [Parameter(Mandatory)][string] $DestPattern,
        [Parameter(Mandatory)][string] $RepoRoot,
        [string]  $PackageName = '',
        $State = $null,
        $PackagesDef = $null
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $srcNorm = $SrcPattern.Trim().Replace('\', '/')

    if (-not (Test-DotfilesGlobPattern $srcNorm)) {
        $src = Resolve-RepoPath -RepoRoot $RepoRoot -Value $SrcPattern
        $dest = Resolve-DestPath -Dest $DestPattern -PackageName $PackageName -State $State -PackagesDef $PackagesDef
        $results.Add([pscustomobject]@{ Src = $src; Dest = $dest })
        return $results.ToArray()
    }

    $starIdx = $srcNorm.IndexOf('*')
    if ($starIdx -lt 0) { $starIdx = $srcNorm.IndexOf('?') }
    $literalPrefix = $srcNorm.Substring(0, $starIdx)
    $globSuffix = $srcNorm.Substring($starIdx)
    $searchRoot = Join-Path $RepoRoot ($literalPrefix.TrimEnd('/') -replace '/', '\')

    $destResolved = Resolve-DestPath -Dest $DestPattern -PackageName $PackageName -State $State -PackagesDef $PackagesDef
    if (-not (Test-DotfilesGlobPattern $destResolved)) {
        Write-Warn (msg 'links.glob.dest.mismatch' $DestPattern)
        return @()
    }

    $destStarIdx = $destResolved.IndexOf('*')
    if ($destStarIdx -lt 0) { $destStarIdx = $destResolved.IndexOf('?') }
    $destLiteralPrefix = $destResolved.Substring(0, $destStarIdx)
    $destGlobSuffix = $destResolved.Substring($destStarIdx)

    $srcStars = ([regex]::Matches($globSuffix, '\*')).Count
    $destStars = ([regex]::Matches($destGlobSuffix, '\*')).Count
    if ($srcStars -ne $destStars) {
        Write-Warn (msg 'links.glob.star.mismatch' $SrcPattern $DestPattern)
        return @()
    }

    if (-not (Test-Path -LiteralPath $searchRoot)) { return @() }

    $globRegex = Convert-DotfilesGlobToRegex -Glob ($globSuffix -replace '/', '\')
    Get-ChildItem -LiteralPath $searchRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($searchRoot.Length).TrimStart('\')
        $m = [regex]::Match($rel, $globRegex)
        if (-not $m.Success) { return }

        $captures = [string[]]@()
        for ($g = 1; $g -lt $m.Groups.Count; $g++) {
            $captures += $m.Groups[$g].Value
        }

        $dest = Merge-DotfilesGlobDest -LiteralPrefix $destLiteralPrefix -GlobSuffix $destGlobSuffix -Captures $captures
        $results.Add([pscustomobject]@{ Src = $_.FullName; Dest = $dest })
    }

    return $results.ToArray()
}

function Resolve-DestPath {
    param(
        [Parameter(Mandatory)][string] $Dest,
        [string]  $PackageName = '',
        $State = $null,
        $PackagesDef = $null
    )

    if ($Dest -eq 'PROFILE') { return $PROFILE }
    if ($Dest -eq 'PROFILE_CurrentUserAllHosts') { return $PROFILE.CurrentUserAllHosts }
    if ($Dest.StartsWith('PROFILE_ROOT\')) { return Join-Path $PROFILE.Substring(0, $PROFILE.LastIndexOf('\') + 1) $Dest.Substring('PROFILE_ROOT\'.Length) }

    # SCOOP_PATH\：按包 intent scope 选择 user/global scoop root（需 PackageName + PackagesDef 上下文）
    # 无上下文时降级为 user root，与 SCOOP_ROOT 行为一致
    if ($Dest -eq 'SCOOP_PATH') {
        if ([string]::IsNullOrWhiteSpace($PackageName) -or $null -eq $PackagesDef) { return Get-ScoopUserRoot }
        return Resolve-ScoopPathRoot -PackagesDef $PackagesDef -PackageName $PackageName -State $State
    }
    if ($Dest.StartsWith('SCOOP_PATH\')) {
        $rest = $Dest.Substring('SCOOP_PATH\'.Length)
        if ([string]::IsNullOrWhiteSpace($PackageName) -or $null -eq $PackagesDef) { return Join-Path (Get-ScoopUserRoot) $rest }
        return Join-Path (Resolve-ScoopPathRoot -PackagesDef $PackagesDef -PackageName $PackageName -State $State) $rest
    }
    if ($Dest -eq 'SCOOP_ROOT') { return Get-ScoopUserRoot }
    if ($Dest.StartsWith('SCOOP_ROOT\')) { return Join-Path (Get-ScoopUserRoot) $Dest.Substring('SCOOP_ROOT\'.Length) }
    if ($Dest -eq 'SCOOP_GLOBAL') { return Get-ScoopGlobalRoot }
    if ($Dest.StartsWith('SCOOP_GLOBAL\')) { return Join-Path (Get-ScoopGlobalRoot) $Dest.Substring('SCOOP_GLOBAL\'.Length) }

    if ($Dest.StartsWith('HOME\')) { return Join-Path $HOME              $Dest.Substring(5) }
    if ($Dest.StartsWith('APPDATA\')) { return Join-Path $env:APPDATA       $Dest.Substring(8) }
    if ($Dest.StartsWith('LOCAL_APPDATA\')) { return Join-Path $env:LOCALAPPDATA  $Dest.Substring(13) }
    if ($Dest.StartsWith('HOMEPATH\')) { return Join-Path $env:HOMEPATH      $Dest.Substring(9) }
    return $Dest
}

# packages.psd1 Desc 字段解析
# 字符串 Desc：任意语言通用
# 对象 Desc：当前语言 Desc > i18n 当前语言 > 默认语言 Desc > i18n 默认语言
# 无 Desc：i18n 当前语言 > i18n 默认语言
function Get-PackageI18nDesc {
    param(
        [Parameter(Mandatory)][string] $Name,
        [ValidateSet('Any', 'Primary', 'Fallback')]
        [string] $Scope = 'Any'
    )

    $descKey = "pkg.$Name.desc"
    if ($Scope -in 'Any', 'Primary') {
        if ($null -ne $Global:WindotsMessages -and $Global:WindotsMessages.ContainsKey($descKey)) {
            return [string]$Global:WindotsMessages[$descKey]
        }
    }
    if ($Scope -in 'Any', 'Fallback') {
        if ($null -ne $Global:WindotsMessagesFallback -and $Global:WindotsMessagesFallback.ContainsKey($descKey)) {
            return [string]$Global:WindotsMessagesFallback[$descKey]
        }
    }
    return ''
}

function Get-PackageDesc {
    param(
        [Parameter(Mandatory)]
        $Package
    )

    $name = [string]$Package.Name
    if ([string]::IsNullOrWhiteSpace($name)) { return '' }

    $locale = [string]$Global:WindotsLocale
    $defaultLocale = $Script:WindotsDefaultLocale

    if ($Package.Contains('Desc') -and $null -ne $Package.Desc) {
        $desc = $Package.Desc
        if ($desc -is [string]) {
            $text = $desc.Trim()
            if ($text) { return $text }
        }
        elseif ($desc -is [System.Collections.IDictionary]) {
            if ($desc.Contains($locale)) {
                $text = [string]$desc[$locale]
                if (-not [string]::IsNullOrWhiteSpace($text)) { return $text.Trim() }
            }

            $primaryI18n = Get-PackageI18nDesc -Name $name -Scope Primary
            if ($primaryI18n) { return $primaryI18n }

            if ($locale -ne $defaultLocale -and $desc.Contains($defaultLocale)) {
                $text = [string]$desc[$defaultLocale]
                if (-not [string]::IsNullOrWhiteSpace($text)) { return $text.Trim() }
            }

            $fallbackI18n = Get-PackageI18nDesc -Name $name -Scope Fallback
            if ($fallbackI18n) { return $fallbackI18n }

            return ''
        }
    }

    $i18nDesc = Get-PackageI18nDesc -Name $name
    if ($i18nDesc) { return $i18nDesc }
    return ''
}

function Find-PackageItemByScoopName {
    param(
        [Parameter(Mandatory)] $PackagesDef,
        [Parameter(Mandatory)][string] $ScoopName
    )
    foreach ($item in Get-AllPackageItems -PackagesDef $PackagesDef) {
        if ([string]$item.Name -eq $ScoopName) { return $item }
        if ($item.Contains('Packages') -and $null -ne $item.Packages) {
            foreach ($p in @($item.Packages)) {
                if ([string]$p -eq $ScoopName) { return $item }
            }
        }
    }
    return $null
}

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
        foreach ($k in $Value.Keys) {
            $keyLit = "'" + ([string]$k -replace "'", "''") + "'"
            $parts += "$keyLit = $(ConvertTo-PsLiteral -Value $Value[$k])"
        }
        return '@{ ' + ($parts -join '; ') + ' }'
    }
    return "'" + ($Value.ToString() -replace "'", "''") + "'"
}

function Save-WindotsState {
    param(
        [Parameter(Mandatory)][string]    $Path,
        [Parameter(Mandatory)][hashtable] $State
    )
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Auto-generated by setup.ps1, do not edit by hand.')
    [void]$sb.AppendLine('@{')
    $sortedKeys = @($State.Keys | Sort-Object)
    $maxKeyLen = ($sortedKeys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    foreach ($key in $sortedKeys) {
        $pad = ' ' * ($maxKeyLen - $key.Length)
        [void]$sb.AppendLine("    $key$pad = $(ConvertTo-PsLiteral -Value $State[$key])")
    }
    [void]$sb.AppendLine('}')
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path, $sb.ToString(), $utf8)
}
