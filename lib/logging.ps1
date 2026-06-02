# =====================================================================
# Windots 日志模块 (lib/logging.ps1)
# =====================================================================

$Global:WindotsLogPath = $null

function Write-Log {
    param(
        [AllowEmptyString()] [string] $Message = '',
        [string] $Level = 'INFO',
        [ConsoleColor] $Color = [ConsoleColor]::Gray
    )
    if ([string]::IsNullOrEmpty($Message)) {
        Write-Host ''
        if ($Global:WindotsLogPath) { Add-Content -Path $Global:WindotsLogPath -Value '' -Encoding utf8 }
        return
    }
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $line = "[$stamp] [$Level] $Message"
    Write-Host $line -ForegroundColor $Color
    if ($Global:WindotsLogPath) {
        Add-Content -Path $Global:WindotsLogPath -Value $line -Encoding utf8
    }
}

function Write-Info { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'INFO' -Color Cyan }
function Write-Success { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'OK'   -Color Green }
function Write-Warn { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'WARN' -Color Yellow }
function Write-Err { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'ERR'  -Color Red }
function Write-Step { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'STEP' -Color Magenta }
function Write-Plan { param([AllowEmptyString()][string]$Message = '') Write-Log -Message $Message -Level 'PLAN' -Color Blue }

function Start-WindotsLog {
    param([Parameter(Mandatory)][string] $LogDir)
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $Global:WindotsLogPath = Join-Path $LogDir "setup-$stamp.log"
    Set-Content -Path $Global:WindotsLogPath -Value "# Windots setup log $stamp" -Encoding utf8
    return $Global:WindotsLogPath
}
