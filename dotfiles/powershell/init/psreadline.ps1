if (-not $global:PsReadLineConfigured) {
  if (-not (Get-Module PSReadLine -ErrorAction SilentlyContinue)) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
  }
  if (Get-Module PSReadLine -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
    Set-PSReadLineKeyHandler -Chord 'End' -BriefDescription 'EndOfLineOrAcceptSuggestion' -LongDescription 'Move to end of line, or accept inline suggestion if already there' -ScriptBlock {
      param($key, $arg)
      $line = $null
      $cursor = $null
      [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
      if ($cursor -lt $line.Length) {
        [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine($key, $arg)
      }
      else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptSuggestion($key, $arg)
      }
    }
    $global:PsReadLineConfigured = $true
  }
}
