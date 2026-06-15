# =====================================================================
# Windots Scoop 管理 (lib/scoop.ps1)
# =====================================================================

function New-ScoopStepResult {
    param(
        [Parameter(Mandatory)][string] $Status,
        [Parameter(Mandatory)][string] $Detail
    )
    return [pscustomobject]@{ Status = $Status; Detail = $Detail }
}

function Resolve-ScoopBucketEntry {
    param([Parameter(Mandatory)] $Entry)

    if ($Entry -is [string]) {
        $name = $Entry.Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { return $null }
        return [pscustomobject]@{ Name = $name; Url = $null }
    }
    if ($Entry -is [System.Collections.IDictionary]) {
        $name = [string]$Entry.Name
        if ([string]::IsNullOrWhiteSpace($name)) { return $null }
        $url = $null
        if ($Entry.Contains('Url') -and -not [string]::IsNullOrWhiteSpace([string]$Entry.Url)) {
            $url = [string]$Entry.Url
        }
        return [pscustomobject]@{ Name = $name; Url = $url }
    }
    return $null
}

function Get-ScoopConfigValue {
    param(
        [Parameter(Mandatory)] $ScoopConfig,
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][string] $Default
    )
    if ($null -eq $ScoopConfig) { return $Default }
    if ($ScoopConfig -is [System.Collections.IDictionary] -and $ScoopConfig.Contains($Key)) {
        $value = [string]$ScoopConfig[$Key]
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $Default
}

function Install-Scoop {
    param(
        $ScoopConfig,
        [switch] $UseMirror,
        [switch] $WhatIf
    )
    if (Test-CommandExists -Name 'scoop') {
        Write-Success (msg 'scoop.installed')
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.scoop.skip'))
    }
    if (Test-IsAdministrator) {
        Write-Err (msg 'scoop.admin.err')
        return (New-ScoopStepResult -Status 'failed' -Detail (msg 'summary.detail.scoop.fail'))
    }

    $officialUrl = 'https://get.scoop.sh'
    $mirrorUrl = Get-ScoopConfigValue -ScoopConfig $ScoopConfig -Key 'MirrorUrl' -Default 'https://gitee.com/scoop-installer/install/raw/master/install.ps1'
    $srcUrl = if ($UseMirror) { $mirrorUrl } else { $officialUrl }

    if ($WhatIf) {
        Write-Plan "[WhatIf] $(msg 'scoop.installing' $srcUrl)"
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }
    Write-Info (msg 'scoop.installing' $srcUrl)
    Invoke-Expression (Invoke-RestMethod -Uri $srcUrl)
    Update-SessionPath
    if (Test-CommandExists -Name 'scoop') {
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.scoop.ok'))
    }
    return (New-ScoopStepResult -Status 'failed' -Detail (msg 'summary.detail.scoop.fail'))
}

function Switch-ScoopMirror {
    param(
        $ScoopConfig,
        [switch] $WhatIf
    )

    $giteeRepo = Get-ScoopConfigValue -ScoopConfig $ScoopConfig -Key 'GiteeRepo' -Default 'https://gitee.com/scoop-installer/scoop'

    if ($WhatIf) {
        Write-Plan "[WhatIf] scoop config SCOOP_REPO `"$giteeRepo`""
        Write-Plan '[WhatIf] scoop update'
        Write-Plan '[WhatIf] scoop bucket rm main; scoop bucket add main'
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }

    $currentRepo = (& scoop config SCOOP_REPO 2>$null | Out-String).Trim()
    if ($currentRepo -eq $giteeRepo) {
        Write-Success (msg 'scoop.mirror.already')
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.mirror.skip'))
    }

    Write-Info (msg 'scoop.mirror.switching')
    & scoop config SCOOP_REPO $giteeRepo
    & scoop update
    & scoop bucket rm main 2>$null
    & scoop bucket add main
    $Global:WindotsBucketList = $null

    Write-Success (msg 'scoop.mirror.done')
    return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.mirror.ok'))
}

function Install-ScoopBuckets {
    param(
        $ScoopConfig,
        [switch] $WhatIf
    )

    $rawBuckets = @()
    if ($null -ne $ScoopConfig -and $ScoopConfig -is [System.Collections.IDictionary] -and $ScoopConfig.Contains('Buckets')) {
        $rawBuckets = @($ScoopConfig.Buckets)
    }
    if ($rawBuckets.Count -eq 0) {
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.bucket.none'))
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $rawBuckets) {
        $resolved = Resolve-ScoopBucketEntry -Entry $item
        if ($null -ne $resolved) { $entries.Add($resolved) }
    }
    if ($entries.Count -eq 0) {
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.bucket.none'))
    }

    $added = 0
    $skipped = 0

    foreach ($entry in $entries) {
        $name = [string]$entry.Name
        $url = [string]$entry.Url
        $installed = (Get-WindotsBucketList).ContainsKey($name)

        if ($installed) {
            Write-Success (msg 'scoop.bucket.installed' $name)
            $skipped++
            continue
        }

        if ($WhatIf) {
            if ($url) { Write-Plan "[WhatIf] scoop bucket add $name $url" }
            else { Write-Plan "[WhatIf] scoop bucket add $name" }
            $added++
            continue
        }

        Write-Info (msg 'scoop.bucket.adding' $name)
        if ($url) { & scoop bucket add $name $url 2>$null }
        else { & scoop bucket add $name 2>$null }
        $Global:WindotsBucketList = $null
        $added++
    }

    if ($WhatIf) {
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }

    if ($added -eq 0 -and $skipped -gt 0) {
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.bucket.skip'))
    }
    return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.bucket.ok' $added))
}

function Get-ScoopSudoInvokePrefix {
    if (Test-IsAdministrator) { return '' }
    if (-not (Test-ScoopInstalled -Name 'sudo')) { return $null }
    $sudoScript = Join-Path (Get-ScoopUserRoot) 'apps\sudo\current\sudo.ps1'
    if (-not (Test-Path -LiteralPath $sudoScript)) { return $null }
    $safe = $sudoScript.Replace("'", "''")
    return "& '$safe' "
}

function Install-ScoopApp {
    param(
        [Parameter(Mandatory)][string] $Name,
        [switch] $GlobalInstall,
        [switch] $WhatIf
    )
    $displayName = Get-ScoopAppBaseName -Name $Name
    if (Test-ScoopInstalled -Name $Name -GlobalInstall:$GlobalInstall) {
        Write-Success (msg 'scoop.app.installed' $displayName)
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.app.skip'))
    }
    $sudoPrefix = ''
    if ($GlobalInstall -and -not (Test-IsAdministrator)) {
        $sudoPrefix = Get-ScoopSudoInvokePrefix
        if ($null -eq $sudoPrefix) {
            Write-Err (msg 'scoop.global.admin.err' $displayName)
            return (New-ScoopStepResult -Status 'failed' -Detail (msg 'summary.detail.scoop.global.admin'))
        }
    }
    if ($WhatIf) {
        $flag = if ($GlobalInstall) { '-g ' } else { '' }
        $sudoLabel = if ($sudoPrefix) { 'sudo ' } else { '' }
        Write-Plan "[WhatIf] ${sudoLabel}scoop install ${flag}$Name"
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }
    Write-Info (msg $(if ($sudoPrefix) { 'scoop.global.using.sudo' } else { 'scoop.app.installing' }) $displayName)
    $safeName = $Name.Replace("'", "''")
    $globalFlag = if ($GlobalInstall) { '-g ' } else { '' }
    $run = Invoke-CapturedPwshCommand -Command "${sudoPrefix}scoop install ${globalFlag}'$safeName'"
    if ($run.ExitCode -ne 0) {
        $rawErr = Get-CommandOutputError -Output $run.Output
        if ([string]::IsNullOrWhiteSpace($rawErr)) {
            $rawErr = (msg 'summary.detail.raw.unknown' $run.ExitCode)
        }
        Write-Err (msg 'scoop.app.fail' $displayName $run.ExitCode)
        return (New-ScoopStepResult -Status 'failed' -Detail $rawErr)
    }
    $Global:WindotsScoopList = $null
    $Global:WindotsScoopGlobalList = $null
    $outputText = ($run.Output -join "`n")
    if ($outputText -match 'already installed') {
        Write-Success (msg 'scoop.app.installed' $displayName)
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.app.skip'))
    }
    Write-Success (msg 'scoop.app.ok' $displayName)
    return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.app.ok'))
}

function Uninstall-ScoopApp {
    param(
        [Parameter(Mandatory)][string] $Name,
        [switch] $GlobalInstall,
        [switch] $WhatIf
    )
    $displayName = Get-ScoopAppBaseName -Name $Name
    if (-not (Test-ScoopInstalled -Name $Name -GlobalInstall:$GlobalInstall)) {
        Write-Warn (msg 'scoop.app.not.installed' $displayName)
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.app.not.installed'))
    }
    $sudoPrefix = ''
    if ($GlobalInstall -and -not (Test-IsAdministrator)) {
        $sudoPrefix = Get-ScoopSudoInvokePrefix
        if ($null -eq $sudoPrefix) {
            Write-Err (msg 'scoop.global.admin.err' $displayName)
            return (New-ScoopStepResult -Status 'failed' -Detail (msg 'summary.detail.scoop.global.admin'))
        }
    }
    if ($WhatIf) {
        $flag = if ($GlobalInstall) { '-g ' } else { '' }
        $sudoLabel = if ($sudoPrefix) { 'sudo ' } else { '' }
        Write-Plan "[WhatIf] ${sudoLabel}scoop uninstall ${flag}$Name"
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }
    Write-Info (msg $(if ($sudoPrefix) { 'scoop.global.using.sudo' } else { 'scoop.app.uninstalling' }) $displayName)
    $safeName = $Name.Replace("'", "''")
    $globalFlag = if ($GlobalInstall) { '-g ' } else { '' }
    $run = Invoke-CapturedPwshCommand -Command "${sudoPrefix}scoop uninstall ${globalFlag}'$safeName'"
    if ($run.ExitCode -ne 0) {
        $rawErr = Get-CommandOutputError -Output $run.Output
        if ([string]::IsNullOrWhiteSpace($rawErr)) {
            $rawErr = (msg 'summary.detail.raw.unknown' $run.ExitCode)
        }
        Write-Err (msg 'scoop.app.uninstall.fail' $displayName $run.ExitCode)
        return (New-ScoopStepResult -Status 'failed' -Detail $rawErr)
    }
    $Global:WindotsScoopList = $null
    $Global:WindotsScoopGlobalList = $null
    Write-Success (msg 'scoop.app.uninstalled' $displayName)
    return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.app.uninstalled'))
}
