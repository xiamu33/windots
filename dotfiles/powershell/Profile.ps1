# PowerShell profile entry (linked to $PROFILE).
$ProfileRoot = $PSScriptRoot

function script:Import-ProfileDir {
  param([string]$RelativePath)
  $dir = Join-Path $ProfileRoot $RelativePath
  if (-not (Test-Path $dir)) { return }
  Get-ChildItem $dir -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object { . $_.FullName }
}

Import-ProfileDir 'functions'
Import-ProfileDir 'aliases'
Import-ProfileDir 'init'
