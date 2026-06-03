# =====================================================================
# Windots 运行总结 (lib/summary.ps1)
# =====================================================================

function Get-SummaryStatusLabel {
    param([string] $Status)
    switch ($Status) {
        'ok' { return (msg 'summary.status.ok') }
        'skipped' { return (msg 'summary.status.skip') }
        'failed' { return (msg 'summary.status.fail') }
        default { return [string]$Status }
    }
}

function Get-SummaryTableColumns {
    param(
        [Parameter(Mandatory)][object[]] $Rows,
        [int] $TotalWidth = 80
    )
    $seqWidth = Get-SeqColumnWidth -RowCount @($Rows).Count
    $statusWidth = [Math]::Max((Get-DisplayWidth (msg 'summary.col.status')), 4)
    return @(
        @{ Header = (msg 'summary.col.no'); Index = 0; FixedWidth = $seqWidth; FirstLineOnly = $true }
        @{ Header = (msg 'summary.col.label'); Index = 1; AutoWidth = $true; FirstLineOnly = $true }
        @{ Header = (msg 'summary.col.status'); Index = 2; FixedWidth = $statusWidth; FirstLineOnly = $true }
    )
}

function Show-Summary {
    param(
        [Parameter(Mandatory)][object[]] $Results,
        [string] $LogFile = ''
    )
    Write-Host ''
    Write-Step (msg 'summary.title')

    $ok = @($Results | Where-Object { $_.Status -eq 'ok' })
    $skipped = @($Results | Where-Object { $_.Status -eq 'skipped' })
    $failed = @($Results | Where-Object { $_.Status -eq 'failed' })

    if (@($Results).Count -gt 0) {
        $tableRows = [System.Collections.Generic.List[string[]]]::new()
        $seq = 1
        foreach ($r in $Results) {
            [void]$tableRows.Add(@(
                    [string]$seq
                    [string]$r.Label
                    (Get-SummaryStatusLabel -Status ([string]$r.Status))
                ))
            $seq++
        }
        $rows = @($tableRows)
        $tableWidth = Get-PackageTableWidth
        Write-SummaryBlock -Lines (Format-DisplayTable `
                -Columns (Get-SummaryTableColumns -Rows $rows -TotalWidth $tableWidth) `
                -Rows     $rows `
                -TotalWidth $tableWidth)
    }

    Write-Host ''
    Write-Info (msg 'summary.done' $ok.Count $skipped.Count $failed.Count)
    if ($LogFile) { Write-Info (msg 'summary.log' $LogFile) }
    Write-Info (msg 'summary.hint')
}
