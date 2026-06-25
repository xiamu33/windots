# Compile toggle-win-maximize.exe (run once after windots link).
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$src = Join-Path $dir 'toggle-win-maximize.cs'
$out = Join-Path $dir 'toggle-win-maximize.exe'

if (-not (Test-Path $src)) {
    throw "Missing source: $src"
}

$csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $csc) {
    throw 'csc.exe not found; install .NET Framework developer pack or enable Windows optional feature.'
}

& $csc /nologo /optimize+ /target:winexe /out:$out $src
if ($LASTEXITCODE -ne 0) {
    throw "csc failed with exit code $LASTEXITCODE"
}

Write-Host "Built $out"
