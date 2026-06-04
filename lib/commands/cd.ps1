# =====================================================================
# Windots cd (lib/commands/cd.ps1)
# =====================================================================

function Invoke-Cd {
    param([Parameter(Mandatory)][string] $Root)

    Set-Location $Root
    Write-Info (msg 'cd.done' $Root)
}
