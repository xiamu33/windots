# =====================================================================
# Windots 交互 UI (lib/ui.ps1)
# =====================================================================

function Read-YesNo {
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [bool] $Default = $true
    )
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        switch ($answer.Trim().ToLowerInvariant()) {
            { $_ -in 'y', 'yes' } { return $true }
            { $_ -in 'n', 'no' } { return $false }
            default { Write-Warn (msg 'ui.yesno.invalid') }
        }
    }
}

function Read-Text {
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [string] $Default = ''
    )
    $shown = if ($Default) { msg 'ui.text.default' $Prompt $Default } else { $Prompt }
    $answer = Read-Host $shown
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

# 中文/全角字符显示宽度（宽字符计 2 列）
function Get-DisplayWidth {
    param([string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $width = 0
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int][char]$ch
        $isWide = (
            ($code -ge 0x1100 -and $code -le 0x115F) -or
            ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
            ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
            ($code -ge 0xF900 -and $code -le 0xFAFF) -or
            ($code -ge 0xFE10 -and $code -le 0xFE6F) -or
            ($code -ge 0xFF00 -and $code -le 0xFF60) -or
            ($code -ge 0xFFE0 -and $code -le 0xFFE6)
        )
        $width += if ($isWide) { 2 } else { 1 }
    }
    return $width
}

# 多选菜单（↑↓移动, 空格切换, A全选, N全不选, Enter确认, Esc取消）
function Select-Items {
    param(
        [Parameter(Mandatory)][string]   $Title,
        [Parameter(Mandatory)][object[]] $Items,
        [scriptblock] $Labeler = { param($x) [string]$x },
        [scriptblock] $SuffixLabeler = $null,
        [scriptblock] $DefaultSet = { param($x) $false },
        [string[]]    $Disabled = @(),
        [string[]]    $Locked = @()
    )
    if ($Items.Count -eq 0) { Write-Warn (msg 'ui.empty' $Title); return @() }

    $selected = New-Object 'bool[]' $Items.Count
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $lbl = & $Labeler $Items[$i]
        $selected[$i] = if ($Locked -contains $lbl) { $true } else { [bool](& $DefaultSet $Items[$i]) }
    }
    $cursor = 0

    $installedTag = msg 'ui.select.installed'
    $unsupportedTag = msg 'ui.select.unsupported'
    $hint = msg 'ui.select.hint'

    while ($true) {
        Clear-Host
        Write-Host $Title -ForegroundColor Magenta
        Write-Host $hint  -ForegroundColor DarkGray
        Write-Host ''

        $installedTagBaseWidth = 0
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $label = & $Labeler $Items[$i]
            $sfx = if ($SuffixLabeler) { [string](& $SuffixLabeler $Items[$i]) } else { '' }
            if ($Disabled -contains $label) { continue }
            $arrow = if ($i -eq $cursor) { '>' } else { ' ' }
            $mark = if ($selected[$i]) { 'x' } else { ' ' }
            $w = Get-DisplayWidth ("$arrow [$mark] $label$sfx")
            if ($w -gt $installedTagBaseWidth) { $installedTagBaseWidth = $w }
        }
        if ($installedTagBaseWidth -gt 0) { $installedTagBaseWidth += 2 }

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $label = & $Labeler $Items[$i]
            $sfx = if ($SuffixLabeler) { [string](& $SuffixLabeler $Items[$i]) } else { '' }
            $isDisabled = $Disabled -contains $label
            $isLocked = $Locked -contains $label
            $mark = if ($selected[$i]) { 'x' } else { ' ' }
            $arrow = if ($i -eq $cursor) { '>' } else { ' ' }

            if ($isDisabled) {
                Write-Host ("  [ ] $label  $unsupportedTag") -ForegroundColor DarkGray
            }
            elseif ($isLocked) {
                $lockedText = "$arrow [x] $label$sfx"
                $lockedWidth = Get-DisplayWidth $lockedText
                if ($installedTagBaseWidth -gt 0) {
                    Write-Host -NoNewline ($lockedText + (' ' * [Math]::Max(0, ($installedTagBaseWidth - $lockedWidth)))) -ForegroundColor DarkGray
                }
                else {
                    Write-Host -NoNewline $lockedText -ForegroundColor DarkGray
                    Write-Host -NoNewline '  '
                }
                Write-Host $installedTag -ForegroundColor DarkGreen
            }
            else {
                $color = if ($i -eq $cursor) { [ConsoleColor]::Cyan }
                elseif ($selected[$i]) { [ConsoleColor]::Green }
                else { [ConsoleColor]::Gray }
                Write-Host -NoNewline ("$arrow [$mark] $label") -ForegroundColor $color
                if ($sfx) { Write-Host $sfx -ForegroundColor DarkCyan }
                else { Write-Host '' }
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            { $_ -in @('UpArrow', 'K') } { $cursor = ($cursor - 1 + $Items.Count) % $Items.Count }
            { $_ -in @('DownArrow', 'J') } { $cursor = ($cursor + 1) % $Items.Count }
            'Spacebar' {
                $lbl = & $Labeler $Items[$cursor]
                if ($Disabled -notcontains $lbl -and $Locked -notcontains $lbl) {
                    $selected[$cursor] = -not $selected[$cursor]
                }
            }
            'A' {
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    $lbl = & $Labeler $Items[$i]
                    if ($Disabled -notcontains $lbl -and $Locked -notcontains $lbl) { $selected[$i] = $true }
                }
            }
            'N' {
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    $lbl = & $Labeler $Items[$i]
                    if ($Locked -notcontains $lbl) { $selected[$i] = $false }
                }
            }
            'Enter' {
                $result = @()
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    if ($selected[$i]) { $result += , $Items[$i] }
                }
                return $result
            }
            'Escape' { return @() }
        }
    }
}

# 单选菜单（↑↓移动，Enter选中）
function Select-One {
    param(
        [Parameter(Mandatory)][string]   $Title,
        [Parameter(Mandatory)][object[]] $Items,
        [scriptblock] $Labeler = { param($x) [string]$x },
        [int]         $DefaultIdx = 0
    )
    if ($Items.Count -eq 0) { return $null }
    $cursor = $DefaultIdx
    $hint = msg 'ui.single.hint'
    while ($true) {
        Clear-Host
        Write-Host $Title -ForegroundColor Magenta
        Write-Host $hint  -ForegroundColor DarkGray
        Write-Host ''
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $label = & $Labeler $Items[$i]
            $arrow = if ($i -eq $cursor) { '>' } else { ' ' }
            $color = if ($i -eq $cursor) { [ConsoleColor]::Cyan } else { [ConsoleColor]::Gray }
            Write-Host ("$arrow $label") -ForegroundColor $color
        }
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            { $_ -in @('UpArrow', 'K') } { $cursor = ($cursor - 1 + $Items.Count) % $Items.Count }
            { $_ -in @('DownArrow', 'J') } { $cursor = ($cursor + 1) % $Items.Count }
            'Enter' { return $Items[$cursor] }
        }
    }
}
