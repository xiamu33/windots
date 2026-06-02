# =====================================================================
# Windots 更新 (lib/commands/update.ps1)
# =====================================================================

function Invoke-Update {
    param([Parameter(Mandatory)][pscustomobject] $Ctx)

    Write-Step (msg 'update.title')

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
