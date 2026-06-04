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

function Install-Scoop {
    param(
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
    $mirrorUrl = 'https://gitee.com/scoop-installer/install/raw/master/install.ps1'
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
    param([switch] $WhatIf)

    $giteeRepo = 'https://gitee.com/scoop-installer/scoop'

    if ($WhatIf) {
        Write-Plan "[WhatIf] scoop config SCOOP_REPO `"$giteeRepo`""
        Write-Plan '[WhatIf] scoop update'
        Write-Plan '[WhatIf] scoop bucket rm main; scoop bucket add main; scoop bucket add extras'
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
    & scoop bucket rm main   2>$null
    & scoop bucket add main
    & scoop bucket add extras 2>$null

    $Global:WindotsBucketList = $null
    Write-Success (msg 'scoop.mirror.done')
    return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.mirror.ok'))
}

function Install-ScoopApp {
    param(
        [Parameter(Mandatory)][string] $Name,
        [switch] $WhatIf
    )
    if (Test-ScoopInstalled -Name $Name) {
        Write-Success (msg 'scoop.app.installed' $Name)
        return (New-ScoopStepResult -Status 'skipped' -Detail (msg 'summary.detail.app.skip'))
    }
    if ($WhatIf) {
        Write-Plan "[WhatIf] scoop install $Name"
        return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.whatif'))
    }
    Write-Info (msg 'scoop.app.installing' $Name)
    $safeName = $Name.Replace("'", "''")
    $run = Invoke-CapturedPwshCommand -Command "scoop install '$safeName'"
    if ($run.ExitCode -ne 0) {
        $rawErr = Get-CommandOutputError -Output $run.Output
        if ([string]::IsNullOrWhiteSpace($rawErr)) {
            $rawErr = (msg 'summary.detail.raw.unknown' $run.ExitCode)
        }
        Write-Err (msg 'scoop.app.fail' $Name $run.ExitCode)
        return (New-ScoopStepResult -Status 'failed' -Detail $rawErr)
    }
    $Global:WindotsScoopList = $null
    Write-Success (msg 'scoop.app.ok' $Name)
    return (New-ScoopStepResult -Status 'ok' -Detail (msg 'summary.detail.app.ok'))
}
