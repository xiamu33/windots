function global:Invoke-CmdInit {
  param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Args
  )
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { return }
  $script = & $Name @Args | Out-String
  if ($script.Trim()) { Invoke-Expression $script }
}
