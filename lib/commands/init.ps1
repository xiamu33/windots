# =====================================================================
# Windots 初始化流程 (lib/commands/init.ps1)
# =====================================================================

function Invoke-Init {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    $results = [System.Collections.Generic.List[object]]::new()

    Set-WindotsSessionProxy -State $State

    Write-Step (msg 'init.step.scoop')
    if (Test-IsAdministrator) {
        Write-Err (msg 'init.scoop.admin.err')
        $results.Add([pscustomobject]@{
                Section = 'scoop'
                Label   = 'scoop'
                Status  = 'failed'
                Detail  = (msg 'summary.detail.scoop.fail')
            })
    }
    else {
        $scoopResult = Install-Scoop -UseMirror:([bool]$State.Scoop_Mirror) -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{
                Section = 'scoop'
                Label   = 'scoop'
                Status  = [string]$scoopResult.Status
                Detail  = [string]$scoopResult.Detail
            })
    }

    if ([bool]$State.Scoop_Mirror -and ((Test-CommandExists -Name 'scoop') -or $Ctx.WhatIf)) {
        Write-Step (msg 'init.step.mirror')
        $mirrorResult = Switch-ScoopMirror -WhatIf:$Ctx.WhatIf
        $results.Add([pscustomobject]@{
                Section = 'mirror'
                Label   = (msg 'summary.label.mirror')
                Status  = [string]$mirrorResult.Status
                Detail  = [string]$mirrorResult.Detail
            })
    }

    Install-WindotsScoopApps -Ctx $Ctx -State $State -Results $results
    $candidateNames = [string[]]@($State['Selected_Packages'] | ForEach-Object { [string]$_ })
    Update-WindotsInstallState -State $State -PackagesDef $Ctx.Packages `
        -BaseSelectedPackages @() `
        -CandidatePackageNames $candidateNames `
        -InstallResults @($results)
    Apply-WindotsDotfiles -Ctx $Ctx -State $State -Results $results

    if ([bool]$State.Chezmoi_Use -and -not [string]::IsNullOrWhiteSpace($State.Chezmoi_User)) {
        Write-Step (msg 'init.step.chezmoi')
        $repoName = [string]$Ctx.Settings.Chezmoi.RepoName
        $user = [string]$State.Chezmoi_User
        $apply = [bool]$State.Chezmoi_Apply
        $chezmoiLabel = "$(msg 'summary.label.chezmoi') ($user/$repoName)"

        if (-not (Test-CommandExists -Name 'chezmoi')) {
            Write-Warn (msg 'init.chezmoi.missing')
            $results.Add([pscustomobject]@{
                    Section = 'chezmoi'
                    Label   = $chezmoiLabel
                    Status  = 'skipped'
                    Detail  = (msg 'summary.detail.chezmoi.skip')
                })
        }
        elseif ($Ctx.WhatIf) {
            Write-Plan "[WhatIf] $(msg 'init.chezmoi.init' $user $repoName)$(if ($apply) {' --apply'})"
            $results.Add([pscustomobject]@{
                    Section = 'chezmoi'
                    Label   = $chezmoiLabel
                    Status  = 'ok'
                    Detail  = (msg 'summary.detail.whatif')
                })
        }
        else {
            Write-Info (msg 'init.chezmoi.init' $user $repoName)
            if ($apply) { & chezmoi init --apply "$user/$repoName" }
            else { & chezmoi init "$user/$repoName" }
            $chezmoiOk = ($LASTEXITCODE -eq 0)
            $results.Add([pscustomobject]@{
                    Section = 'chezmoi'
                    Label   = $chezmoiLabel
                    Status  = if ($chezmoiOk) { 'ok' } else { 'failed' }
                    Detail  = if ($chezmoiOk) { (msg 'summary.detail.chezmoi.ok') } else { (msg 'summary.detail.chezmoi.fail') }
                })
        }
    }

    if (-not $Ctx.WhatIf) {
        Save-WindotsState -Path $Ctx.StatePath -State $State
        Write-Success (msg 'interactive.state.saved' $Ctx.StatePath)
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}
