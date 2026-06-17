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

function Resolve-ScoopSetConfigKey {
    param([Parameter(Mandatory)][string] $Key)
    $k = $Key.Trim()
    switch -Regex ($k) {
        '^(?i)root_path$' { return 'root_path' }
        '^(?i)global_path$' { return 'global_path' }
        '^(?i)scoop_repo$' { return 'SCOOP_REPO' }
        default { return $k }
    }
}

function Get-ScoopSetConfigFromSettings {
    param($ScoopConfig)

    $result = @{}
    if ($null -eq $ScoopConfig) { return $result }
    if (-not ($ScoopConfig -is [System.Collections.IDictionary]) -or -not $ScoopConfig.Contains('SetConfig')) {
        return $result
    }
    $raw = $ScoopConfig.SetConfig
    if ($null -eq $raw) { return $result }
    foreach ($k in @($raw.Keys)) {
        $value = [string]$raw[$k]
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $scoopKey = Resolve-ScoopSetConfigKey -Key ([string]$k)
        $result[$scoopKey] = $value.Trim()
    }
    return $result
}

function Get-ScoopSetConfigValue {
    param(
        $ScoopConfig,
        [Parameter(Mandatory)][string] $Key,
        [string] $Default = ''
    )
    $cfg = Get-ScoopSetConfigFromSettings -ScoopConfig $ScoopConfig
    if ($cfg.Contains($Key) -and -not [string]::IsNullOrWhiteSpace([string]$cfg[$Key])) {
        return [string]$cfg[$Key]
    }
    return $Default
}

function Test-ScoopPathsConfiguredInSettings {
    param($ScoopConfig)

    $root = Get-ScoopSetConfigValue -ScoopConfig $ScoopConfig -Key 'root_path'
    $global = Get-ScoopSetConfigValue -ScoopConfig $ScoopConfig -Key 'global_path'
    return -not [string]::IsNullOrWhiteSpace($root) -and -not [string]::IsNullOrWhiteSpace($global)
}

function Get-ScoopRuntimeConfigValue {
    param([Parameter(Mandatory)][string] $Key)
    if (-not (Test-CommandExists -Name 'scoop')) { return '' }
    return (& scoop config $Key 2>$null | Out-String).Trim()
}

function Apply-ScoopSetConfig {
    param(
        $ScoopConfig,
        [switch] $WhatIf
    )

    if (-not (Test-CommandExists -Name 'scoop') -and -not $WhatIf) {
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.scoop.skip'))
    }

    $desired = Get-ScoopSetConfigFromSettings -ScoopConfig $ScoopConfig
    if ($desired.Count -eq 0) {
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.scoop.config.none'))
    }

    $applied = 0
    $skipped = 0
    foreach ($key in @($desired.Keys | Sort-Object)) {
        $target = [string]$desired[$key]
        $current = if ($WhatIf) { '' } else { Get-ScoopRuntimeConfigValue -Key $key }
        if ($current -eq $target) {
            $skipped++
            continue
        }
        if ($WhatIf) {
            Write-Plan "[WhatIf] scoop config $key `"$target`""
            $applied++
            continue
        }
        Write-Info (msg 'scoop.config.setting' $key $target)
        & scoop config $key $target | Out-Null
        $applied++
    }

    if ($applied -gt 0) {
        $Global:WindotsScoopList = $null
        $Global:WindotsScoopGlobalList = $null
    }

    if ($WhatIf) {
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }
    if ($applied -eq 0 -and $skipped -gt 0) {
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.scoop.config.skip'))
    }
    return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.scoop.config.ok' $applied))
}

function Write-ScoopSetConfigPlan {
    param(
        $ScoopConfig,
        [bool] $UseMirror = $false
    )

    $cfg = Get-ScoopSetConfigFromSettings -ScoopConfig $ScoopConfig
    $root = if ($cfg.Contains('root_path')) { [string]$cfg['root_path'] } else { (msg 'interactive.plan.scoop.path.unset') }
    $global = if ($cfg.Contains('global_path')) { [string]$cfg['global_path'] } else { (msg 'interactive.plan.scoop.path.unset') }
    Write-Plan (msg 'interactive.plan.scoop.root' $root)
    Write-Plan (msg 'interactive.plan.scoop.global_path' $global)

    if ($UseMirror) {
        $repo = if ($cfg.Contains('SCOOP_REPO')) { [string]$cfg['SCOOP_REPO'] } else { (msg 'interactive.plan.scoop.repo.unset') }
        Write-Plan (msg 'interactive.plan.scoop.repo' $repo)
    }
    else {
        Write-Plan (msg 'interactive.plan.scoop.repo' (msg 'interactive.plan.scoop.repo.official'))
    }
}

function Wait-ScoopSetConfigPaths {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [ref]                                  $Settings
    )

    $settingsPath = Join-Path $Ctx.Root 'settings.psd1'
    $wasMissing = -not (Test-ScoopPathsConfiguredInSettings -ScoopConfig $Settings.Value.Scoop)

    if ($wasMissing) {
        while (-not (Test-ScoopPathsConfiguredInSettings -ScoopConfig $Settings.Value.Scoop)) {
            Write-Warn (msg 'interactive.scoop.paths.missing' $settingsPath)
            Write-Info  (msg 'interactive.scoop.paths.hint')
            $ready = Read-YesNo -Prompt (msg 'interactive.scoop.paths.ready.prompt') -Default $false
            if (-not $ready) { return $false }
            $Settings.Value = Import-PowerShellDataFile -Path $settingsPath
        }
        return $true
    }

    $cfg = Get-ScoopSetConfigFromSettings -ScoopConfig $Settings.Value.Scoop
    Write-Info (msg 'interactive.scoop.paths.review')
    Write-Info (msg 'interactive.plan.scoop.root' ([string]$cfg['root_path']))
    Write-Info (msg 'interactive.plan.scoop.global_path' ([string]$cfg['global_path']))
    $confirmed = Read-YesNo -Prompt (msg 'interactive.scoop.paths.confirm.prompt') -Default $true
    return [bool]$confirmed
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

    $setConfig = Get-ScoopSetConfigFromSettings -ScoopConfig $ScoopConfig
    $scoopRepo = if ($setConfig.Contains('SCOOP_REPO')) { [string]$setConfig['SCOOP_REPO'] } else { '' }
    if ([string]::IsNullOrWhiteSpace($scoopRepo)) {
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.scoop.config.none'))
    }

    if ($WhatIf) {
        if (Test-CommandExists -Name 'scoop') {
            $currentRepo = Get-ScoopRuntimeConfigValue -Key 'SCOOP_REPO'
            if ($currentRepo -eq $scoopRepo) {
                Write-Plan (msg 'scoop.mirror.already')
                return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.mirror.skip'))
            }
        }
        Write-Plan '[WhatIf] scoop update'
        Write-Plan '[WhatIf] scoop bucket rm main; scoop bucket add main'
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }

    $currentRepo = Get-ScoopRuntimeConfigValue -Key 'SCOOP_REPO'
    if ($currentRepo -eq $scoopRepo) {
        Write-Success (msg 'scoop.mirror.already')
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.mirror.skip'))
    }

    if ($currentRepo -ne $scoopRepo) {
        Write-Warn (msg 'scoop.mirror.repo.pending')
    }

    Write-Info (msg 'scoop.mirror.switching')
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
        if ($url) { & scoop bucket add $name $url }
        else { & scoop bucket add $name }
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

function Get-ScoopSudoScriptPath {
    if (Test-IsAdministrator) { return $null }
    if (-not (Test-ScoopInstalled -Name 'sudo')) { return $null }
    $sudoScript = Join-Path (Get-ScoopUserRoot) 'apps\sudo\current\sudo.ps1'
    if (-not (Test-Path -LiteralPath $sudoScript)) { return $null }
    return $sudoScript
}

function Get-ScoopSudoInvokePrefix {
    $script = Get-ScoopSudoScriptPath
    if (-not $script) {
        if (Test-IsAdministrator) { return '' }
        return $null
    }
    $safe = $script.Replace("'", "''")
    return "& '$safe' "
}

function Build-ScoopShellCommandString {
    param(
        [Parameter(Mandatory)][string] $Verb,
        [Parameter(Mandatory)][string] $Name,
        [switch] $GlobalInstall,
        [string] $SudoScript = ''
    )
    $safeName = $Name.Replace("'", "''")
    $globalFlag = if ($GlobalInstall) { '-g ' } else { '' }
    $prefix = if (-not [string]::IsNullOrWhiteSpace($SudoScript)) {
        $safe = $SudoScript.Replace("'", "''")
        "& '$safe' "
    }
    else { '' }
    return "${prefix}scoop $Verb ${globalFlag}'$safeName'"
}

function Invoke-ScoopShellCommand {
    param(
        [Parameter(Mandatory)][ValidateSet('install', 'uninstall')]
        [string] $Verb,
        [Parameter(Mandatory)][string] $Name,
        [switch] $GlobalInstall,
        [switch] $CaptureOutput
    )
    $sudoScript = $null
    if ($GlobalInstall -and -not (Test-IsAdministrator)) {
        $sudoScript = Get-ScoopSudoScriptPath
    }

    $capture = $CaptureOutput -or ($Verb -eq 'uninstall')
    if ($capture) {
        # scoop 用 Write-Host 输出 ERROR，进程内 2>&1 捕获不到；子进程重定向可拿到 stdout/stderr
        $cmd = Build-ScoopShellCommandString -Verb $Verb -Name $Name `
            -GlobalInstall:$GlobalInstall -SudoScript ([string]$sudoScript)
        $run = Invoke-CapturedPwshCommand -Command $cmd
        return @{
            ExitCode = [int]$run.ExitCode
            Output   = @($run.Output)
        }
    }

    if ($sudoScript) {
        if ($GlobalInstall) { & $sudoScript scoop $Verb -g $Name }
        else { & $sudoScript scoop $Verb $Name }
    }
    elseif ($GlobalInstall) { & scoop $Verb -g $Name }
    else { & scoop $Verb $Name }

    $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    return @{
        ExitCode = $exitCode
        Output   = @()
    }
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
    $sudoScript = $null
    if ($GlobalInstall -and -not (Test-IsAdministrator)) {
        $sudoScript = Get-ScoopSudoScriptPath
        if ($null -eq $sudoScript) {
            Write-Err (msg 'scoop.global.admin.err' $displayName)
            return (New-ScoopStepResult -Status 'failed' -Detail (msg 'summary.detail.scoop.global.admin'))
        }
    }
    if ($WhatIf) {
        $flag = if ($GlobalInstall) { '-g ' } else { '' }
        $sudoLabel = if ($sudoScript) { 'sudo ' } else { '' }
        Write-Plan "[WhatIf] ${sudoLabel}scoop install ${flag}$Name"
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }
    Write-Info (msg $(if ($sudoScript) { 'scoop.global.using.sudo' } else { 'scoop.app.installing' }) $displayName)
    $run = Invoke-ScoopShellCommand -Verb install -Name $Name -GlobalInstall:$GlobalInstall
    if ($run.ExitCode -ne 0) {
        $rawErr = Get-ScoopCommandErrorDetail -Output $run.Output -ExitCode $run.ExitCode
        Write-Err (msg 'scoop.app.fail' $displayName $run.ExitCode)
        return (New-ScoopStepResult -Status 'failed' -Detail $rawErr)
    }
    $Global:WindotsScoopList = $null
    $Global:WindotsScoopGlobalList = $null
    Write-Success (msg 'scoop.app.ok' $displayName)
    return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.app.ok'))
}

function Install-ScoopAppResolved {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][bool]   $TargetGlobal,
        [switch] $WhatIf
    )
    $displayName = Get-ScoopAppBaseName -Name $Name
    $targetScope = if ($TargetGlobal) { 'global' } else { 'user' }
    $installedScope = Get-ScoopAppInstalledScope -Name $Name

    if ($installedScope -eq $targetScope) {
        return (Install-ScoopApp -Name $Name -GlobalInstall:$TargetGlobal -WhatIf:$WhatIf)
    }

    if ($null -ne $installedScope) {
        $fromLabel = if ($installedScope -eq 'global') { (msg 'scoop.scope.global') } else { (msg 'scoop.scope.user') }
        $toLabel = if ($targetScope -eq 'global') { (msg 'scoop.scope.global') } else { (msg 'scoop.scope.user') }
        Write-Info (msg 'scoop.scope.migrating' $displayName $fromLabel $toLabel)
        $oldGlobal = ($installedScope -eq 'global')
        $un = Uninstall-ScoopApp -Name $Name -GlobalInstall:$oldGlobal -WhatIf:$WhatIf -ForMigration
        if ($un.Status -eq 'failed') { return $un }
    }

    return (Install-ScoopApp -Name $Name -GlobalInstall:$TargetGlobal -WhatIf:$WhatIf)
}

function Install-ScoopAppEnsure {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][bool]   $TargetGlobal,
        [switch] $WhatIf
    )
    $displayName = Get-ScoopAppBaseName -Name $Name
    if (Test-ScoopInstalled -Name $Name) {
        Write-Success (msg 'scoop.app.installed' $displayName)
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.app.skip'))
    }
    return (Install-ScoopApp -Name $Name -GlobalInstall:$TargetGlobal -WhatIf:$WhatIf)
}

function Uninstall-ScoopApp {
    param(
        [Parameter(Mandatory)][string] $Name,
        [switch] $GlobalInstall,
        [switch] $WhatIf,
        [switch] $ForMigration
    )
    $displayName = Get-ScoopAppBaseName -Name $Name
    if (-not (Test-ScoopInstalled -Name $Name -GlobalInstall:$GlobalInstall)) {
        Write-Warn (msg 'scoop.app.not.installed' $displayName)
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.app.not.installed'))
    }
    $sudoScript = $null
    if ($GlobalInstall -and -not (Test-IsAdministrator)) {
        $sudoScript = Get-ScoopSudoScriptPath
        if ($null -eq $sudoScript) {
            Write-Err (msg 'scoop.global.admin.err' $displayName)
            return (New-ScoopStepResult -Status 'failed' -Detail (msg 'summary.detail.scoop.global.admin'))
        }
    }
    if ($WhatIf) {
        $flag = if ($GlobalInstall) { '-g ' } else { '' }
        $sudoLabel = if ($sudoScript) { 'sudo ' } else { '' }
        Write-Plan "[WhatIf] ${sudoLabel}scoop uninstall ${flag}$Name"
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }
    Write-Info (msg $(if ($sudoScript) { 'scoop.global.using.sudo' } else { 'scoop.app.uninstalling' }) $displayName)
    $run = Invoke-ScoopShellCommand -Verb uninstall -Name $Name -GlobalInstall:$GlobalInstall
    $Global:WindotsScoopList = $null
    $Global:WindotsScoopGlobalList = $null
    $failKey = if ($ForMigration) { 'scoop.app.migrate.fail' } else { 'scoop.app.uninstall.fail' }
    $stillKey = if ($ForMigration) { 'scoop.app.migrate.incomplete' } else { 'scoop.app.uninstall.still' }
    $stillDetailKey = if ($ForMigration) { 'summary.detail.migrate.incomplete' } else { 'summary.detail.app.uninstall.still' }
    if ($run.ExitCode -ne 0) {
        $rawErr = Get-ScoopCommandErrorDetail -Output $run.Output -ExitCode $run.ExitCode
        Write-Err (msg $failKey $displayName $rawErr)
        return (New-ScoopStepResult -Status 'failed' -Detail $rawErr)
    }
    if (Test-ScoopInstalled -Name $Name -GlobalInstall:$GlobalInstall) {
        $rawErr = Get-ScoopCommandErrorDetail -Output $run.Output
        if ([string]::IsNullOrWhiteSpace($rawErr)) {
            $rawErr = (msg $stillDetailKey)
        }
        Write-Err (msg $stillKey $displayName $rawErr)
        return (New-ScoopStepResult -Status 'failed' -Detail $rawErr)
    }
    Write-Success (msg 'scoop.app.uninstalled' $displayName)
    return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.app.uninstalled'))
}
