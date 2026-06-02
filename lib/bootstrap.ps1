# =====================================================================
# Windots Bootstrap：PS5.1 引导阶段 (lib/bootstrap.ps1)
# =====================================================================

function Install-Git {
    param([switch] $WhatIf)

    if (Test-CommandExists -Name 'git') {
        Write-Success (msg 'git.installed')
        return $true
    }
    if (-not (Test-CommandExists -Name 'winget')) {
        Write-Err (msg 'git.winget.unavail')
        return $false
    }
    if ($WhatIf) {
        Write-Plan '[WhatIf] winget install --id Git.Git -e --scope user --accept-package-agreements --accept-source-agreements'
        return $true
    }
    Write-Info (msg 'git.installing')
    & winget install --id Git.Git --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Err (msg 'git.fail' $LASTEXITCODE)
        return $false
    }
    Update-SessionPath
    Write-Success (msg 'git.ok')
    return $true
}

function Install-PSCore7 {
    param([switch] $WhatIf)

    if (Test-CommandExists -Name 'pwsh') {
        Write-Success (msg 'ps7.installed')
        return $true
    }
    if (-not (Test-CommandExists -Name 'winget')) {
        Write-Err (msg 'ps7.winget.unavail')
        return $false
    }
    if ($WhatIf) {
        Write-Plan '[WhatIf] winget install --id Microsoft.PowerShell -e --scope user --accept-package-agreements --accept-source-agreements'
        return $true
    }
    Write-Info (msg 'ps7.installing')
    & winget install --id Microsoft.PowerShell --source winget
    if ($LASTEXITCODE -ne 0) {
        Write-Err (msg 'ps7.fail' $LASTEXITCODE)
        return $false
    }
    Update-SessionPath
    Write-Success (msg 'ps7.ok')
    return $true
}

function Invoke-Bootstrap {
    param(
        [Parameter(Mandatory)][string] $SetupScript,
        [Parameter(Mandatory)][string] $StateFile,
        [switch] $WhatIf
    )

    Write-Step (msg 'bootstrap.title')
    Write-Warn  (msg 'bootstrap.warn')

    $useProxy = Read-YesNo -Prompt (msg 'bootstrap.proxy.prompt') -Default $false
    $proxyUrl = ''
    if ($useProxy) {
        $proxyUrl = Read-Text -Prompt (msg 'bootstrap.proxy.url')
        Set-SessionProxy -Url $proxyUrl
    }

    $ok = Install-PSCore7 -WhatIf:$WhatIf
    if (-not $ok) {
        Write-Err (msg 'bootstrap.ps7.fail')
        return $false
    }

    $proxyForState = if ($useProxy) { $proxyUrl } else { '' }
    $state = @{ Bootstrap = $true; Bootstrap_ProxyUrl = $proxyForState }
    if (-not $WhatIf) {
        Save-WindotsState -Path $StateFile -State $state
    }

    if ($WhatIf) {
        Write-Plan "[WhatIf] Start-Process pwsh -ArgumentList '-NoProfile -NoExit -File ""$SetupScript"" -Resume'"
        return $true
    }

    Write-Info (msg 'bootstrap.launching')
    Start-Process pwsh -ArgumentList ('-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$SetupScript`"", '-Resume')
    Write-Success (msg 'bootstrap.launched')
    return $true
}
