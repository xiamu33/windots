# Fish-like abbr: expand on Space/Enter (PSReadLine has no native abbr; functions break tab completion)
if (-not $global:ProfileAbbr) { $global:ProfileAbbr = @{} }

function global:Set-Abbr {
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [string]$Value
  )
  $global:ProfileAbbr[$Name] = $Value
}

if (-not $global:AbbrHandlerRegistered) {
  Import-Module PSReadLine -ErrorAction SilentlyContinue
  if (Get-Module PSReadLine) {
    Set-PSReadLineKeyHandler -Chord 'Spacebar' -BriefDescription 'Expand-Abbr' -ScriptBlock {
      param($key, $arg)
      $line = $null
      $cursor = $null
      [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
      $before = $line.Substring(0, $cursor)
      if ($before -match '(?:^|\s)(\S+)$') {
        $word = $Matches[1]
        if ($global:ProfileAbbr.ContainsKey($word)) {
          $expand = $global:ProfileAbbr[$word]
          $start = $cursor - $word.Length
          [Microsoft.PowerShell.PSConsoleReadLine]::Replace($start, $word.Length, "$expand ")
          return
        }
      }
      [Microsoft.PowerShell.PSConsoleReadLine]::SelfInsert($key, $arg)
    }
    Set-PSReadLineKeyHandler -Chord 'Enter' -BriefDescription 'Expand-Abbr-Enter' -ScriptBlock {
      $line = $null
      $cursor = $null
      [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
      $trimmed = $line.Trim()
      if ($trimmed -and $global:ProfileAbbr.ContainsKey($trimmed)) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $global:ProfileAbbr[$trimmed])
      }
      [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
    $global:AbbrHandlerRegistered = $true
  }
}
