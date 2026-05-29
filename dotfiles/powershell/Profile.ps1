# PowerShell profile scaffold.
# TODO: add aliases, prompt, and module bootstrap logic.
Invoke-Expression (&starship init powershell)

Invoke-Expression (& { (zoxide init powershell | Out-String) })

atuin init powershell | Out-String | Invoke-Expression

fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression

(&mise activate pwsh) | Out-String | Invoke-Expression

# Set-Alias -Name g -Value git # 已在psc中设置别名
function l { lsd -la @args }
function ll { lsd -l @args }

Import-Module PSCompletions
