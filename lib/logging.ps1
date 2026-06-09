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

function Write-PlanBlock {
    param(
        [AllowEmptyString()][string[]] $Lines = @(''),
        [int] $Indent = 2
    )
    $prefix = ' ' * $Indent
    foreach ($line in $Lines) {
        $out = if ([string]::IsNullOrEmpty($line)) { '' } else { $prefix + $line }
        Write-Host $out -ForegroundColor Blue
        if ($Global:WindotsLogPath) {
            $stamp = (Get-Date).ToString('HH:mm:ss')
            Add-Content -Path $Global:WindotsLogPath -Value "[$stamp] [PLAN] $out" -Encoding utf8
        }
    }
}

function Write-SummaryBlock {
    param(
        [AllowEmptyString()][string[]] $Lines = @(''),
        [int] $Indent = 2,
        [ConsoleColor] $Color = [ConsoleColor]::DarkGray
    )
    $prefix = ' ' * $Indent
    foreach ($line in $Lines) {
        $out = if ([string]::IsNullOrEmpty($line)) { '' } else { $prefix + $line }
        Write-Host $out -ForegroundColor $Color
        if ($Global:WindotsLogPath) {
            $stamp = (Get-Date).ToString('HH:mm:ss')
            Add-Content -Path $Global:WindotsLogPath -Value "[$stamp] [INFO] $out" -Encoding utf8
        }
    }
}

function Invoke-CapturedPwshCommand {
    param(
        [Parameter(Mandatory)][string] $Command
    )

    $output = [System.Collections.Generic.List[string]]::new()
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    [void]$psi.ArgumentList.Add('-NoProfile')
    [void]$psi.ArgumentList.Add('-NonInteractive')
    [void]$psi.ArgumentList.Add('-Command')
    [void]$psi.ArgumentList.Add("$Command; exit `$LASTEXITCODE")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        if ($null -ne $line) {
            Write-Host $line
            [void]$output.Add($line)
        }
    }
    while (-not $proc.StandardError.EndOfStream) {
        $line = $proc.StandardError.ReadLine()
        if ($null -ne $line) {
            Write-Host $line
            [void]$output.Add($line)
        }
    }
    $proc.WaitForExit()

    return @{
        ExitCode = $proc.ExitCode
        Output   = @($output)
    }
}

function Get-CommandOutputLineText {
    param($Item)
    if ($null -eq $Item) { return '' }
    if ($Item -is [System.Management.Automation.ErrorRecord]) {
        $msg = [string]$Item.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace($msg)) { return $msg.Trim() }
        return $Item.ToString().Trim()
    }
    return ([string]$Item).Trim()
}

function Get-CommandOutputError {
    param([object[]] $Output)
    if ($null -eq $Output) { return '' }
    $lines = @($Output | ForEach-Object {
            $text = Get-CommandOutputLineText $_
            if ([string]::IsNullOrWhiteSpace($text)) { return $null }
            if ($text -match '^\[[\d:]+\]\s*\[(INFO|OK|WARN|ERR|STEP|PLAN)\]\s') { return $null }
            if ($text -match 'scoop 安装失败|scoop install failed') { return $null }
            $text
        } | Where-Object { $_ })
    if ($lines.Count -eq 0) { return '' }

    $noise = '^(Installing|Downloading|Extracting|Running installer|Linking|Creating shim|Adding|WARN\s|Scoop\s|Updating|Checking|.*\.\.\.\s*$)'
    $candidates = @($lines | Where-Object { $_ -notmatch $noise })
    if ($candidates.Count -gt 0) {
        return [string]($candidates | Select-Object -Last 1)
    }
    return [string]($lines | Select-Object -Last 1)
}

function Start-WindotsLog {
    param([Parameter(Mandatory)][string] $LogDir)
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $Global:WindotsLogPath = Join-Path $LogDir "setup-$stamp.log"
    Set-Content -Path $Global:WindotsLogPath -Value "# Windots setup log $stamp" -Encoding utf8
    return $Global:WindotsLogPath
}
