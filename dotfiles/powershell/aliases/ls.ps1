if (Get-Command eza -CommandType Application -ErrorAction SilentlyContinue) {
  function global:eza {
    & (Get-Command eza -CommandType Application).Source --icons --color-scale=age --git @args
  }
  Set-Alias -Name ls -Value eza -Scope Global -Force
  function global:l { eza -al @args }
  function global:ll { eza -l @args }
  function global:lt { eza -al --tree --git-ignore @args }
}
