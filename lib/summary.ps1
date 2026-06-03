# =====================================================================
# Windots 运行总结 (lib/summary.ps1)
# =====================================================================

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

    if ($ok.Count -gt 0) {
        Write-Host ('[OK]   ' + ($ok | ForEach-Object { $_.Label }) -join ', ') -ForegroundColor Green
    }
    if ($skipped.Count -gt 0) {
        Write-Host ('[SKIP]  ' + ($skipped | ForEach-Object { $_.Label }) -join ', ') -ForegroundColor Yellow
    }
    if ($failed.Count -gt 0) {
        Write-Host ('[FAIL]  ' + ($failed | ForEach-Object { $_.Label }) -join ', ') -ForegroundColor Red
    }
    Write-Host ''
    Write-Info (msg 'summary.done' $ok.Count $skipped.Count $failed.Count)
    if ($LogFile) { Write-Info (msg 'summary.log' $LogFile) }
    Write-Info (msg 'summary.hint')
}
