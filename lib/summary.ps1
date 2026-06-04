# =====================================================================
# Windots 运行总结 (lib/summary.ps1)
# =====================================================================

function Get-SummaryBlockType {
    param([string] $Section)
    switch ([string]$Section) {
        { $_ -in @('scoop', 'mirror') } { return 'pkgmgr' }
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
        [Parameter(Mandatory)][object[]] $Items,
        [ConsoleColor]                   $Color = [ConsoleColor]::DarkGray,
        [switch]                         $WithFailDetail
    )

    $statusItems = @($Items | Where-Object { $_.Status -eq $Status })
    if (@($statusItems).Count -eq 0) { return }

    $blocks = @(
        @{ Type = 'pkgmgr'; LabelKey = 'summary.block.pkgmgr' }
        @{ Type = 'packages'; LabelKey = 'summary.block.packages' }
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
                    (msg 'summary.detail.app.fail')
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
        [Parameter(Mandatory)][object[]] $Results,
        [string] $LogFile = ''
    )
    Write-Host ''
    Write-Step (msg 'summary.title')

    $items = @($Results)

    Write-SummaryStatusGroup -TitleKey 'summary.status.group.ok' -Status 'ok' -Items $items -Color Green
    Write-SummaryStatusGroup -TitleKey 'summary.status.group.skip' -Status 'skipped' -Items $items
    Write-SummaryStatusGroup -TitleKey 'summary.status.group.fail' -Status 'failed' -Items $items -Color Red -WithFailDetail

    $okCount = @($items | Where-Object { $_.Status -eq 'ok' }).Count
    $skipCount = @($items | Where-Object { $_.Status -eq 'skipped' }).Count
    $failCount = @($items | Where-Object { $_.Status -eq 'failed' }).Count

    Write-Host ''
    Write-Info (msg 'summary.done' $okCount $skipCount $failCount)
    if ($LogFile) { Write-Info (msg 'summary.log' $LogFile) }
    Write-Info (msg 'summary.hint')
}
