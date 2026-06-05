# =====================================================================
# Windots 包安装流程 (lib/commands/install.ps1)
# =====================================================================

function Invoke-Install {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $Plan
    )

    $state = $Plan.PlannedState
    $results = [System.Collections.Generic.List[object]]::new()

    Set-WindotsSessionProxy -State $state
    Install-WindotsScoopApps -Ctx $Ctx -State $state -Results $results -StepKey 'install.step.packages'
    Update-WindotsInstallState -State $state -PackagesDef $Ctx.Packages `
        -BaseSelectedPackages $Plan.SavedSelected `
        -CandidatePackageNames $Plan.NewPackageNames `
        -InstallResults @($results)
    Apply-WindotsDotfiles -Ctx $Ctx -State $state -Results $results `
        -StepKey 'install.step.config' -SrcSkipKey 'install.config.src.skip'

    if (-not $Ctx.WhatIf) {
        Save-WindotsState -Path $Ctx.StatePath -State $state
        Write-Success (msg 'interactive.state.saved' $Ctx.StatePath)
    }

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}
