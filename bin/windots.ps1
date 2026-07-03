# windots - Windows dev environment manager (PowerShell shim)
# Usage: windots [init|install|i|uninstall|rm|update|up|migrate|clean|link|harvest|hv|doctor|cd]
# PS 7+: cd runs in the current shell; other subcommands delegate to setup.ps1.
# PS 5.1: cd runs in the current shell; other subcommands delegate to windots.cmd.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $WindotsArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cmdArgs = [string[]]@()
if ($null -ne $WindotsArgs) {
    $cmdArgs = [string[]]@($WindotsArgs)
}

$root = $env:WINDOTS_ROOT
if ([string]::IsNullOrWhiteSpace($root)) {
    $root = [System.Environment]::GetEnvironmentVariable('WINDOTS_ROOT', 'User')
}
if ([string]::IsNullOrWhiteSpace($root)) {
    Write-Error 'WINDOTS_ROOT not set. Please run setup.ps1 from the repo first.'
    exit 1
}

if ($cmdArgs.Count -ge 1 -and $cmdArgs[0] -ieq 'cd') {
    Set-Location $root
    exit 0
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $cmdShim = Join-Path $PSScriptRoot 'windots.cmd'
    if (-not (Test-Path $cmdShim)) {
        Write-Error "windots.cmd not found: $cmdShim"
        exit 1
    }
    & $cmdShim @cmdArgs
    exit $LASTEXITCODE
}

& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'setup.ps1') @cmdArgs
exit $LASTEXITCODE
