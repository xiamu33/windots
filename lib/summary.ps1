# =====================================================================
# Windots 运行总结 (lib/summary.ps1)
# =====================================================================

function Get-SummaryBlockType {
    param([string] $Section)
    switch ([string]$Section) {
        { $_ -in @('scoop', 'mirror') } { return 'pkgmgr' }
        'migrate' { return 'migrate' }
        'packages' { return 'packages' }
        'config' { return 'config' }
        'chezmoi' { return 'chezmoi' }
        default { return 'packages' }
    }
}

function Write-SummaryStatusGroup {
    param(
        [Parameter(Mandatory)][string]   $TitleKey,
        [Parameter(Mandatory)][string]   $Status,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                       $Items,
        [ConsoleColor]                   $Color = [ConsoleColor]::DarkGray,
        [switch]                         $WithFailDetail,
        [string]                         $FailDetailKey = 'summary.detail.app.fail'
    )

    $statusItems = @($Items | Where-Object { $_.Status -eq $Status })
    if (@($statusItems).Count -eq 0) { return }

    $blocks = @(
        @{ Type = 'pkgmgr'; LabelKey = 'summary.block.pkgmgr' }
        @{ Type = 'packages'; LabelKey = 'summary.block.packages' }
        @{ Type = 'migrate'; LabelKey = 'summary.block.migrate' }
        @{ Type = 'config'; LabelKey = 'summary.block.config' }
        @{ Type = 'chezmoi'; LabelKey = 'summary.block.chezmoi' }
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($block in $blocks) {
        $blockItems = @($statusItems | Where-Object { (Get-SummaryBlockType -Section $_.Section) -eq $block.Type })
        if (@($blockItems).Count -eq 0) { continue }

        $label = msg $block.LabelKey
        if ($WithFailDetail) {
            [void]$lines.Add("$label`:")
            foreach ($f in $blockItems) {
                [void]$lines.Add([string]$f.Label)
                $detail = if ($f.PSObject.Properties['Detail'] -and -not [string]::IsNullOrWhiteSpace([string]$f.Detail)) {
                    [string]$f.Detail
                }
                else {
                    (msg $FailDetailKey)
                }
                [void]$lines.Add("  $detail")
            }
        }
        else {
            $names = @($blockItems | ForEach-Object { [string]$_.Label })
            [void]$lines.Add("$label`: $($names -join ', ')")
        }
    }

    if ($lines.Count -eq 0) { return }

    Write-Host ''
    Write-Host (msg $TitleKey) -ForegroundColor $Color
    Write-SummaryBlock -Lines @($lines) -Color $Color
}

function Show-Summary {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]                       $Results,
        [string]                         $LogFile = '',
        [ValidateSet('default', 'uninstall')]
        [string]                         $Mode = 'default'
    )
    Write-Host ''
    $titleKey = if ($Mode -eq 'uninstall') { 'summary.title.uninstall' } else { 'summary.title' }
    Write-Step (msg $titleKey)

    $items = @($Results)
    $regularItems = @($items | Where-Object { [string]$_.Section -ne 'migrate' })
    $migrateItems = @($items | Where-Object { [string]$_.Section -eq 'migrate' })

    $okKey = if ($Mode -eq 'uninstall') { 'summary.status.group.ok.uninstall' } else { 'summary.status.group.ok' }
    $skipKey = if ($Mode -eq 'uninstall') { 'summary.status.group.skip.uninstall' } else { 'summary.status.group.skip' }
    $failKey = if ($Mode -eq 'uninstall') { 'summary.status.group.fail.uninstall' } else { 'summary.status.group.fail' }
    $failDetailKey = if ($Mode -eq 'uninstall') { 'summary.detail.app.uninstall.fail' } else { 'summary.detail.app.fail' }

    Write-SummaryStatusGroup -TitleKey $okKey -Status 'ok' -Items $regularItems -Color Green
    Write-SummaryStatusGroup -TitleKey $skipKey -Status 'skipped' -Items $regularItems
    Write-SummaryStatusGroup -TitleKey $failKey -Status 'failed' -Items $regularItems -Color Red -WithFailDetail -FailDetailKey $failDetailKey

    Write-SummaryStatusGroup -TitleKey 'summary.status.group.migrate.ok' -Status 'ok' -Items $migrateItems -Color Green
    Write-SummaryStatusGroup -TitleKey 'summary.status.group.migrate.fail' -Status 'failed' -Items $migrateItems -Color Red `
        -WithFailDetail -FailDetailKey 'summary.detail.migrate.incomplete'

    $okCount = @($regularItems | Where-Object { $_.Status -eq 'ok' }).Count
    $skipCount = @($regularItems | Where-Object { $_.Status -eq 'skipped' }).Count
    $failCount = @($regularItems | Where-Object { $_.Status -eq 'failed' }).Count
    $migrateOkCount = @($migrateItems | Where-Object { $_.Status -eq 'ok' }).Count
    $migrateFailCount = @($migrateItems | Where-Object { $_.Status -eq 'failed' }).Count

    Write-Host ''
    $doneKey = if ($Mode -eq 'uninstall') { 'summary.done.uninstall' } else { 'summary.done' }
    if ($migrateOkCount + $migrateFailCount -gt 0) {
        Write-Info (msg 'summary.done.with_migrate' $okCount $skipCount $failCount $migrateOkCount $migrateFailCount)
    }
    else {
        Write-Info (msg $doneKey $okCount $skipCount $failCount)
    }
    if ($LogFile) { Write-Info (msg 'summary.log' $LogFile) }
    Write-Info (msg 'summary.hint')
}
