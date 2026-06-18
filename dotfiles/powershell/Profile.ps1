# PowerShell profile entry (linked to $PROFILE).
$ProfileRoot = $PSScriptRoot

function script:Import-ProfileDir {
  param([string]$RelativePath)
  $dir = Join-Path $ProfileRoot $RelativePath
  if (-not (Test-Path $dir)) { return }
  Get-ChildItem $dir -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object { . $_.FullName }
}

Import-ProfileDir 'functions'
. (Join-Path $ProfileRoot 'init/tools.ps1')
Import-ProfileDir 'aliases'
Import-ProfileDir 'abbr'

. (Join-Path $ProfileRoot 'init/completions.ps1')
