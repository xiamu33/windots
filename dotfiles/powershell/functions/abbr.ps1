# Fish-like abbr: expand on Space/Enter; Tab lists abbr names, ToolTip shows expanded command
if (-not $global:ProfileAbbr) { $global:ProfileAbbr = @{} }

function global:Set-Abbr {
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [string]$Value,
    [string]$Description
  )
  if (-not $Description) { $Description = $Value }
  $global:ProfileAbbr[$Name] = @{
    Value       = $Value
    Description = $Description
  }
}

function script:Get-AbbrExpandText {
  param([string]$Name)
  $entry = $global:ProfileAbbr[$Name]
  if ($entry -is [hashtable]) { return $entry.Value }
  return [string]$entry
}

function script:Register-AbbrCompletion {
  if ($script:AbbrTabExpansion2) { return }
  $script:AbbrTabExpansion2 = $function:global:TabExpansion2
  function global:TabExpansion2 {
    param(
      [Parameter(Mandatory)]
      [string]$inputScript,
      [Parameter(Mandatory)]
      [int]$cursorColumn,
      $ast = $null,
      $tokens = $null,
      $positionOfCursor = $null,
      $options = $null
    )
    $len = [Math]::Min($cursorColumn, $inputScript.Length)
    $before = $inputScript.Substring(0, $len)
    if ($before -match '^\s*(\S*)$') {
      $prefix = $Matches[1]
      $abbrMatches = @(
        $global:ProfileAbbr.GetEnumerator() |
        Where-Object { $_.Key -like "${prefix}*" } |
        Sort-Object Key
      )
      if ($abbrMatches.Count -gt 0) {
        $results = [System.Collections.ObjectModel.Collection[System.Management.Automation.CompletionResult]]::new()
        foreach ($item in $abbrMatches) {
          $desc = if ($item.Value -is [hashtable]) { $item.Value.Description } else { [string]$item.Value }
          $null = $results.Add([System.Management.Automation.CompletionResult]::new(
              $item.Key,
              $item.Key,
              [System.Management.Automation.CompletionResultType]::Command,
              $desc
            ))
        }
        return [System.Management.Automation.CommandCompletion]::new($results, -1, 0, $prefix.Length)
      }
    }
    & $script:AbbrTabExpansion2 @PSBoundParameters
  }
}

if (-not $global:AbbrHandlerRegistered) {
  if (-not (Get-Module PSReadLine -ErrorAction SilentlyContinue)) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
  }
  if (Get-Module PSReadLine -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Chord 'Spacebar' -BriefDescription 'Expand-Abbr' -ScriptBlock {
      param($key, $arg)
      $line = $null
      $cursor = $null
      [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
      $before = $line.Substring(0, $cursor).TrimEnd()
      if ($before -match '(?:^|\s)(\S+)$') {
        $word = $Matches[1]
        if ($global:ProfileAbbr.ContainsKey($word)) {
          $expand = Get-AbbrExpandText $word
          $start = $before.Length - $word.Length
          [Microsoft.PowerShell.PSConsoleReadLine]::Replace($start, $cursor - $start, "$expand ")
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
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, (Get-AbbrExpandText $trimmed))
      }
      [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
    $global:AbbrHandlerRegistered = $true
  }
  Register-AbbrCompletion
}
