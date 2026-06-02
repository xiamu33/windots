# =====================================================================
# Windots Scoop 管理 (lib/scoop.ps1)
# =====================================================================

function Install-Scoop {
    param(
        [switch] $UseMirror,
        [switch] $WhatIf
    )
    if (Test-CommandExists -Name 'scoop') {
        Write-Success (msg 'scoop.installed')
        return $true
    }
    if (Test-IsAdministrator) {
        Write-Err (msg 'scoop.admin.err')
        return $false
    }

    $officialUrl = 'https://get.scoop.sh'
    $mirrorUrl = 'https://gitee.com/scoop-installer/install/raw/master/install.ps1'
    $srcUrl = if ($UseMirror) { $mirrorUrl } else { $officialUrl }

    if ($WhatIf) {
        Write-Plan "[WhatIf] $(msg 'scoop.installing' $srcUrl)"
        return $true
    }
    Write-Info (msg 'scoop.installing' $srcUrl)
    Invoke-Expression (Invoke-RestMethod -Uri $srcUrl)
    Update-SessionPath
    return (Test-CommandExists -Name 'scoop')
}

function Switch-ScoopMirror {
    param([switch] $WhatIf)

    $giteeRepo = 'https://gitee.com/scoop-installer/scoop'

    if ($WhatIf) {
        Write-Plan "[WhatIf] scoop config SCOOP_REPO `"$giteeRepo`""
        Write-Plan '[WhatIf] scoop update'
        Write-Plan '[WhatIf] scoop bucket rm main; scoop bucket add main; scoop bucket add extras'
        return
    }

    $currentRepo = (& scoop config SCOOP_REPO 2>$null | Out-String).Trim()
    if ($currentRepo -eq $giteeRepo) {
        Write-Success (msg 'scoop.mirror.already')
        return
    }

    Write-Info (msg 'scoop.mirror.switching')
    & scoop config SCOOP_REPO $giteeRepo
    & scoop update
    & scoop bucket rm main   2>$null
    & scoop bucket add main
    & scoop bucket add extras 2>$null

    $Global:WindotsBucketList = $null
    Write-Success (msg 'scoop.mirror.done')
}

function Install-ScoopApp {
    param(
        [Parameter(Mandatory)][string] $Name,
        [switch] $WhatIf
    )
    if (Test-ScoopInstalled -Name $Name) {
        Write-Success (msg 'scoop.app.installed' $Name)
        return $true
    }
    if ($WhatIf) {
        Write-Plan "[WhatIf] scoop install $Name"
        return $true
    }
    Write-Info (msg 'scoop.app.installing' $Name)
    & scoop install $Name
    if ($LASTEXITCODE -ne 0) {
        Write-Err (msg 'scoop.app.fail' $Name $LASTEXITCODE)
        return $false
    }
    $Global:WindotsScoopList = $null
    Write-Success (msg 'scoop.app.ok' $Name)
    return $true
}
