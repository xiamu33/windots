# =====================================================================
# Windots 包安装流程 (lib/commands/install.ps1)
# =====================================================================

function Invoke-Install {
    param(
        [Parameter(Mandatory)][pscustomobject] $Ctx,
        [Parameter(Mandatory)]                 $State
    )

    $results = [System.Collections.Generic.List[object]]::new()

    Set-WindotsSessionProxy -State $State
    Install-WindotsScoopApps -Ctx $Ctx -State $State -Results $results -StepKey 'install.step.packages'
    Apply-WindotsDotfiles -Ctx $Ctx -State $State -Results $results `
        -StepKey 'install.step.config' -SrcSkipKey 'install.config.src.skip'

    Show-Summary -Results $results -LogFile $Ctx.LogFile
}
