if (Get-Command eza -CommandType Application -ErrorAction SilentlyContinue) {
  function global:eza {
    & (Get-Command eza -CommandType Application).Source --icons --color-scale=age --git @args
  }
  Set-Alias -Name ls -Value eza -Scope Global -Force
  function global:lt { ls -al --tree --git-ignore @args }
}
function global:l { ls -al @args }
function global:ll { ls -l @args }
