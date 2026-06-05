# =====================================================================
# Windots 更新 (lib/commands/update.ps1)
# =====================================================================

function Copy-WindotsPreserveData {
    param(
        [Parameter(Mandatory)][string] $FromRoot,
        [Parameter(Mandatory)][string] $ToRoot
    )

    foreach ($name in @('.windots-state.psd1', 'settings.psd1')) {
        $src = Join-Path $FromRoot $name
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $ToRoot $name) -Force
        }
    }
    foreach ($dirName in @('backup', 'logs')) {
        $srcDir = Join-Path $FromRoot $dirName
        if (Test-Path -LiteralPath $srcDir) {
            Copy-Item -LiteralPath $srcDir -Destination (Join-Path $ToRoot $dirName) -Recurse -Force
        }
    }
}

function Convert-WindotsToGitRepo {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RepoUrl,
        [switch] $WhatIf
    )

    if (-not (Test-CommandExists -Name 'git')) {
        Write-Warn (msg 'update.windots.git.missing')
        return $false
    }

    $parent = Split-Path $Root -Parent
    $leaf = Split-Path $Root -Leaf
    $staging = Join-Path $env:TEMP ("windots-clone-{0}" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    $bakName = "{0}.bak.{1}" -f $leaf, (Get-Date -Format 'yyyyMMddHHmmss')
    $bakPath = Join-Path $parent $bakName

    if ($WhatIf) {
        Write-Plan "[WhatIf] $(msg 'update.windots.convert.running' $RepoUrl)"
        Write-Plan "[WhatIf] preserve -> git clone -> copy backup $bakPath -> replace $Root contents"
        return $true
    }

    Write-Info (msg 'update.windots.convert.running' $RepoUrl)
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }

    & git clone $RepoUrl $staging
    if ($LASTEXITCODE -ne 0) {
        Write-Warn (msg 'update.windots.convert.fail' $LASTEXITCODE)
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $false
    }

    Copy-WindotsPreserveData -FromRoot $Root -ToRoot $staging

    Write-Info (msg 'update.windots.convert.backingup' $bakPath)
    Copy-Item -LiteralPath $Root -Destination $bakPath -Recurse -Force

    $previousLocation = (Get-Location).Path
    try {
        Set-Location -LiteralPath $env:TEMP

        Get-ChildItem -LiteralPath $Root -Force | Remove-Item -Recurse -Force

        Get-ChildItem -LiteralPath $staging -Force | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $Root $_.Name) -Force
        }
    }
    finally {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $Root) {
            Set-Location -LiteralPath $Root
        }
        elseif (Test-Path -LiteralPath $previousLocation) {
            Set-Location -LiteralPath $previousLocation
        }
    }

    Write-Info (msg 'update.windots.convert.bak' $bakPath)
    Write-Success (msg 'update.windots.convert.ok')
    return $true
}

function Update-WindotsSelf {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RepoUrl,
        [switch] $WhatIf
    )

    Write-Step (msg 'update.windots.step')

    if (-not (Test-CommandExists -Name 'git')) {
        Write-Warn (msg 'update.windots.git.missing')
        return
    }

    if (-not (Test-Path (Join-Path $Root '.git'))) {
        if ($WhatIf) {
            Write-Plan "[WhatIf] $(msg 'update.windots.convert.prompt') -> yes"
            Convert-WindotsToGitRepo -Root $Root -RepoUrl $RepoUrl -WhatIf | Out-Null
            return
        }

        $convert = Read-YesNo -Prompt (msg 'update.windots.convert.prompt') -Default $true
        if (-not $convert) {
            Write-Info (msg 'update.windots.convert.skip')
            return
        }

        if (-not (Convert-WindotsToGitRepo -Root $Root -RepoUrl $RepoUrl)) {
            return
        }

        Register-WindotsShim -RepoRoot $Root -WhatIf:$false
        return
    }

    if ($WhatIf) {
        Write-Plan "[WhatIf] git -C `"$Root`" pull"
        return
    }

    Write-Info (msg 'update.windots.running')
    & git -C $Root pull
    if ($LASTEXITCODE -ne 0) {
        Write-Warn (msg 'update.windots.fail' $LASTEXITCODE)
        return
    }

    Write-Success (msg 'update.windots.ok')
    Register-WindotsShim -RepoRoot $Root -WhatIf:$false
}

function Invoke-Update {
    param([Parameter(Mandatory)][pscustomobject] $Ctx)

    Write-Step (msg 'update.title')

    $state = Get-State -StatePath $Ctx.StatePath
    if ($state) {
        Set-WindotsSessionProxy -State $state
    }
    elseif ([bool]$Ctx.Settings.Proxy.Enabled) {
        Set-SessionProxy -Url ([string]$Ctx.Settings.Proxy.Url)
    }
    else {
        Set-SessionProxy -Url ''
    }

    $repoUrl = ''
    if ($Ctx.Settings.Contains('Repository') -and $null -ne $Ctx.Settings.Repository) {
        $repoUrl = [string]$Ctx.Settings.Repository.Url
    }
    if ([string]::IsNullOrWhiteSpace($repoUrl)) {
        Write-Err (msg 'update.windots.repo.missing')
    }
    else {
        Update-WindotsSelf -Root $Ctx.Root -RepoUrl $repoUrl -WhatIf:$Ctx.WhatIf
    }

    if (-not (Test-CommandExists -Name 'scoop')) {
        Write-Warn (msg 'update.scoop.missing')
    }
    else {
        Write-Info (msg 'update.scoop.running')
        if (-not $Ctx.WhatIf) { & scoop update * }
        else { Write-Plan '[WhatIf] scoop update *' }
    }

    if (Test-CommandExists -Name 'chezmoi') {
        Write-Info (msg 'update.chezmoi.running')
        if (-not $Ctx.WhatIf) { & chezmoi update }
        else { Write-Plan '[WhatIf] chezmoi update' }
    }

    Write-Info (msg 'update.done')
}
