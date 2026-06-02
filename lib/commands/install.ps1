# =====================================================================
# Windots 安装流程 (lib/commands/install.ps1)
# =====================================================================

function Invoke-Install {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    $results = [System.Collections.Generic.List[object]]::new()

    # 1. 代理
    if ($State.Proxy_Enabled -and -not [string]::IsNullOrWhiteSpace($State.Proxy_Url)) {
        Set-SessionProxy -Url ([string]$State.Proxy_Url)
    }
    else {
        Set-SessionProxy -Url ''
    }

    # 2. 安装 scoop
    Write-Step (msg 'install.step.scoop')
    if (Test-IsAdministrator) {
        Write-Err (msg 'install.scoop.admin.err')
        $results.Add([pscustomobject]@{ Label = 'scoop'; Status = 'failed'; Detail = msg 'install.scoop.admin.err' })
    }
    else {
        $ok = Install-Scoop -UseMirror:([bool]$State.Scoop_Mirror) -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{ Label = 'scoop'; Status = if ($ok) { 'ok' } else { 'failed' }; Detail = '' })
    }

    # 3. 切换镜像
    if ([bool]$State.Scoop_Mirror -and ((Test-CommandExists -Name 'scoop') -or $Ctx.WhatIf)) {
        Write-Step (msg 'install.step.mirror')
        Switch-ScoopMirror -WhatIf:$Ctx.WhatIf
    }

    # 4. 安装 scoop 包
    Write-Step (msg 'install.step.packages')
    foreach ($name in $State.Scoop_Apps) {
        $ok = Install-ScoopApp -Name $name -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{ Label = $name; Status = if ($ok) { 'ok' } else { 'failed' }; Detail = '' })
    }

    # 5. 应用本地 dotfiles 配置链接
    Write-Step (msg 'install.step.config')
    $pkgLookup = if ($State.Contains('Selected_Packages') -and $null -ne $State.Selected_Packages) {
        $State.Selected_Packages
    }
    else {
        $State.Scoop_Apps
    }
    $allItems = @()
    foreach ($s in @($Ctx.Packages.Recommended) + @($Ctx.Packages.Optional.Dev) + @($Ctx.Packages.Optional.Term) + @($Ctx.Packages.Optional.Beauty)) {
        if ($pkgLookup -contains $s.Name) { $allItems += $s }
    }
    $extras = @($Ctx.Packages.Extras)
    $planned = Get-PlannedLinks -RepoRoot $Ctx.Root -SelectedItems $allItems -Extras $extras

    $resolvedLinkMode = Resolve-LinkMode -RequestedMode ([string]$State.Link_Mode) -WhatIf:$Ctx.WhatIf

    foreach ($link in $planned) {
        if (-not (Test-Path $link.Src)) {
            Write-Warn (msg 'install.config.src.skip' $link.Src)
            $results.Add([pscustomobject]@{ Label = $link.Label; Status = 'skipped'; Detail = msg 'install.config.src.skip' $link.Src })
            continue
        }
        $status = Apply-Config `
            -Src          $link.Src `
            -Dest         $link.Dest `
            -BackupRoot   $Ctx.BackupDir `
            -ConflictMode ([string]$State.Conflict_Mode) `
            -LinkMode     $resolvedLinkMode `
            -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{ Label = $link.Label; Status = $status; Detail = '' })
    }

    # 6. chezmoi init
    if ([bool]$State.Chezmoi_Use -and -not [string]::IsNullOrWhiteSpace($State.Chezmoi_User)) {
        Write-Step (msg 'install.step.chezmoi')
        $repoName = [string]$Ctx.Settings.Chezmoi.RepoName
        if (-not (Test-CommandExists -Name 'chezmoi')) {
            Write-Warn (msg 'install.chezmoi.missing')
            $results.Add([pscustomobject]@{ Label = 'chezmoi init'; Status = 'skipped'; Detail = msg 'install.chezmoi.missing' })
        }
        else {
            $user = [string]$State.Chezmoi_User
            $apply = [bool]$State.Chezmoi_Apply
            if ($Ctx.WhatIf) {
                Write-Plan "[WhatIf] $(msg 'install.chezmoi.init' $user $repoName)$(if ($apply) {' --apply'})"
            }
            else {
                Write-Info (msg 'install.chezmoi.init' $user $repoName)
                if ($apply) { & chezmoi init --apply "$user/$repoName" }
                else { & chezmoi init "$user/$repoName" }
            }
            $results.Add([pscustomobject]@{ Label = 'chezmoi init'; Status = 'ok'; Detail = '' })
        }
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}
