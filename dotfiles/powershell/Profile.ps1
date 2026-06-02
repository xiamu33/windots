# PowerShell profile scaffold.
if (Get-Command starship -ErrorAction SilentlyContinue) {
  &starship init powershell | Invoke-Expression
}
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  zoxide init powershell | Out-String | Invoke-Expression
}
if (Get-Command atuin -ErrorAction SilentlyContinue) {
  atuin init powershell | Out-String | Invoke-Expression
}
if (Get-Command fnm -ErrorAction SilentlyContinue) {
  fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}
if (Get-Command mise -ErrorAction SilentlyContinue) {
  (&mise activate pwsh) | Out-String | Invoke-Expression
}

# Set-Alias -Name g -Value git # 已在psc中设置别名
function l { lsd -la @args }
function ll { lsd -l @args }

if (Get-Module -ListAvailable -Name PSCompletions) {
  Import-Module PSCompletions
}
