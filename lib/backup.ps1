# =====================================================================
# Windots 备份 (lib/backup.ps1)
# =====================================================================

function Backup-Path {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $BackupRoot
    )
    if (-not (Test-Path $Path)) { return $null }

    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $destDir = Join-Path $BackupRoot $stamp
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $item = Get-Item $Path -Force
    if ($item.PSIsContainer) {
        $zipPath = Join-Path $destDir ($item.Name + '.bak.zip')
        Compress-Archive -Path $Path -DestinationPath $zipPath -Force
        Write-Warn (msg 'backup.dir.zip' $zipPath)
        return $zipPath
    }
    else {
        $bakPath = Join-Path $destDir ($item.Name + '.bak')
        Copy-Item -Path $Path -Destination $bakPath -Force
        Write-Warn (msg 'backup.file.bak' $bakPath)
        return $bakPath
    }
}
