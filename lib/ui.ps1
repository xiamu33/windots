# =====================================================================
# Windots 交互 UI (lib/ui.ps1)
# =====================================================================

# 丢弃启动阶段或输出期间误触的按键，避免 Read-Host / ReadKey 直接消费缓冲输入
$script:WindotsConsoleInputFlush = $false

function Clear-ConsoleInputBuffer {
    if (-not $script:WindotsConsoleInputFlush) {
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
internal static class WindotsConsoleInputFlush {
    const int StdInputHandle = -10;
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool FlushConsoleInputBuffer(IntPtr hConsoleInput);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetStdHandle(int nStdHandle);
    internal static void Flush() {
        FlushConsoleInputBuffer(GetStdHandle(StdInputHandle));
    }
}
'@ -ErrorAction SilentlyContinue
        }
        $script:WindotsConsoleInputFlush = $true
    }
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        try { [WindotsConsoleInputFlush]::Flush() } catch { }
    }
    try {
        while ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
        }
    }
    catch { }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [bool] $Default = $true
    )
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        Clear-ConsoleInputBuffer
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
    Clear-ConsoleInputBuffer
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

    Clear-ConsoleInputBuffer

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

    Clear-ConsoleInputBuffer

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

function Pad-DisplayTextRaw {
    param(
        [string] $Text,
        [int]    $Width
    )
    $text = if ($null -eq $Text) { '' } else { [string]$Text }
    return $text + (' ' * [Math]::Max(0, $Width - (Get-DisplayWidth $text)))
}

function Pad-DisplayText {
    param(
        [string] $Text,
        [int]    $Width
    )
    $text = Truncate-DisplayText -Text $Text -Width $Width
    return $text + (' ' * [Math]::Max(0, $Width - (Get-DisplayWidth $text)))
}

function Truncate-DisplayText {
    param(
        [string] $Text,
        [int]    $Width
    )
    $text = if ($null -eq $Text) { '' } else { [string]$Text }
    if ($Width -le 0) { return '' }
    if ((Get-DisplayWidth $text) -le $Width) { return $text }

    $ellipsis = '...'
    $ellipsisW = Get-DisplayWidth $ellipsis
    if ($Width -le $ellipsisW) {
        return $ellipsis.Substring(0, [Math]::Min($Width, $ellipsis.Length))
    }

    $budget = $Width - $ellipsisW
    $sb = [System.Text.StringBuilder]::new()
    $used = 0
    foreach ($ch in $text.ToCharArray()) {
        $cw = Get-DisplayWidth ([string]$ch)
        if (($used + $cw) -gt $budget) { break }
        [void]$sb.Append($ch)
        $used += $cw
    }
    return $sb.ToString() + $ellipsis
}

function Split-DisplayTextLines {
    param(
        [string] $Text,
        [int]    $Width,
        [switch] $CommaBreak
    )
    $text = if ($null -eq $Text) { '' } else { [string]$Text }
    if ([string]::IsNullOrEmpty($text)) { return @('') }
    if ($Width -le 0) { return @($text) }
    if ((Get-DisplayWidth $text) -le $Width) { return @($text) }

    if ($CommaBreak) {
        $lines = [System.Collections.Generic.List[string]]::new()
        $current = ''
        foreach ($part in @($text -split ',\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $part = [string]$part
            $next = if ([string]::IsNullOrEmpty($current)) { $part } else { "$current, $part" }
            if ((Get-DisplayWidth $next) -le $Width) {
                $current = $next
                continue
            }
            if (-not [string]::IsNullOrEmpty($current)) {
                [void]$lines.Add($current)
                $current = ''
            }
            if ((Get-DisplayWidth $part) -le $Width) {
                $current = $part
            }
            else {
                foreach ($sub in @(Split-DisplayTextLines -Text $part -Width $Width)) {
                    [void]$lines.Add([string]$sub)
                }
            }
        }
        if (-not [string]::IsNullOrEmpty($current)) { [void]$lines.Add($current) }
        if ($lines.Count -eq 0) { return @('') }
        return [string[]]$lines.ToArray()
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new()
    $used = 0
    foreach ($ch in $text.ToCharArray()) {
        $cw = Get-DisplayWidth ([string]$ch)
        if (($used + $cw) -gt $Width -and $sb.Length -gt 0) {
            [void]$result.Add($sb.ToString())
            $sb.Clear() | Out-Null
            $used = 0
        }
        [void]$sb.Append($ch)
        $used += $cw
    }
    if ($sb.Length -gt 0) { [void]$result.Add($sb.ToString()) }
    if ($result.Count -eq 0) { return @('') }
    return [string[]]$result.ToArray()
}

function Get-DisplayTableWidth {
    param([int[]] $ColumnWidths)
    return 1 + ($ColumnWidths | ForEach-Object { $_ + 2 } | Measure-Object -Sum).Sum
}

function Get-SeqColumnWidth {
    param([int] $RowCount)
    if ($RowCount -le 0) { return 1 }
    return [Math]::Max(1, ([string]$RowCount).Length)
}

function Resolve-DisplayTableColumns {
    param(
        [object[]] $Columns,
        [object[]] $Rows = @(),
        [int]      $TotalWidth = 0
    )

    $resolved = [System.Collections.Generic.List[object]]::new()
    foreach ($col in $Columns) {
        $item = [ordered]@{
            Header        = [string]$col.Header
            Index         = [int]$col.Index
            FixedWidth    = if ($col.ContainsKey('FixedWidth')) { [int]$col.FixedWidth } else { 0 }
            AutoWidth     = [bool]($col.ContainsKey('AutoWidth') -and $col.AutoWidth)
            Flex          = [bool]($col.ContainsKey('Flex') -and $col.Flex)
            HalfFlex      = [bool]($col.ContainsKey('HalfFlex') -and $col.HalfFlex)
            Wrap          = [bool]($col.ContainsKey('Wrap') -and $col.Wrap)
            CommaWrap     = [bool]($col.ContainsKey('CommaWrap') -and $col.CommaWrap)
            FirstLineOnly = [bool]($col.ContainsKey('FirstLineOnly') -and $col.FirstLineOnly)
            Width         = 0
        }
        [void]$resolved.Add($item)
    }

    foreach ($item in $resolved) {
        if (-not $item.AutoWidth) { continue }
        $maxW = Get-DisplayWidth $item.Header
        foreach ($row in $Rows) {
            $cells = if ($row -is [string[]]) { $row } else { @([string]$row) }
            $idx = [int]$item.Index
            if ($idx -ge @($cells).Count) { continue }
            $w = Get-DisplayWidth ([string]$cells[$idx])
            if ($w -gt $maxW) { $maxW = $w }
        }
        $item.Width = [Math]::Max($maxW, 2)
        $item.FixedWidth = [int]$item.Width
    }

    if ($TotalWidth -le 0) {
        foreach ($item in $resolved) {
            if ($item.Width -gt 0) { continue }
            if ($item.FixedWidth -gt 0) {
                $item.Width = $item.FixedWidth
            }
            else {
                $item.Width = [Math]::Max(4, (Get-DisplayWidth $item.Header))
            }
        }
        return @($resolved)
    }

    $overhead = 1 + 2 * $resolved.Count
    $fixedSum = ($resolved | Where-Object { $_.FixedWidth -gt 0 } | ForEach-Object { $_.FixedWidth } | Measure-Object -Sum).Sum
    $halfFlexItems = @($resolved | Where-Object { $_.HalfFlex })
    if ($halfFlexItems.Count -gt 0) {
        $remaining = $TotalWidth - $overhead - $fixedSum
        $base = [Math]::Max(6, [Math]::Floor($remaining / $halfFlexItems.Count))
        $extra = $remaining - ($base * $halfFlexItems.Count)
        for ($hi = 0; $hi -lt $halfFlexItems.Count; $hi++) {
            $halfFlexItems[$hi].Width = $base + $(if ($hi -eq ($halfFlexItems.Count - 1)) { $extra } else { 0 })
        }
    }
    $flexWidth = [Math]::Max(8, $TotalWidth - $overhead - $fixedSum - ($halfFlexItems | ForEach-Object { $_.Width } | Measure-Object -Sum).Sum)

    foreach ($item in $resolved) {
        if ($item.Width -gt 0) { continue }
        if ($item.Flex) {
            $item.Width = $flexWidth
        }
        elseif ($item.FixedWidth -gt 0) {
            $item.Width = $item.FixedWidth
        }
        else {
            $item.Width = [Math]::Max(4, (Get-DisplayWidth $item.Header))
        }
    }
    return @($resolved)
}

function Expand-WrappedTableRows {
    param(
        [object[]] $Columns,
        [object[]] $Rows
    )

    $expanded = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $Rows) {
        $cells = if ($row -is [string[]]) { $row } else { @([string[]]$row) }
        $wrapped = @{}
        $maxLines = 1

        foreach ($col in $Columns) {
            $idx = [int]$col.Index
            $text = [string]$cells[$idx]
            if ($col.Wrap -and -not [string]::IsNullOrEmpty($text)) {
                if ($col.CommaWrap) {
                    $lines = @(Split-DisplayTextLines -Text $text -Width $col.Width -CommaBreak)
                }
                else {
                    $lines = @(Split-DisplayTextLines -Text $text -Width $col.Width)
                }
            }
            else {
                $lines = @($text)
            }
            $wrapped[$idx] = @($lines)
            if (@($lines).Count -gt $maxLines) { $maxLines = @($lines).Count }
        }

        foreach ($col in $Columns) {
            $idx = [int]$col.Index
            if (-not $col.Wrap) { continue }
            while (@($wrapped[$idx]).Count -lt $maxLines) {
                $wrapped[$idx] = @($wrapped[$idx] + '')
            }
        }

        $groupLines = [System.Collections.Generic.List[string[]]]::new()
        $maxIndex = ($Columns | ForEach-Object { [int]$_.Index } | Measure-Object -Maximum).Maximum
        for ($i = 0; $i -lt $maxLines; $i++) {
            $physical = [string[]]::new($maxIndex + 1)
            foreach ($col in $Columns) {
                $idx = [int]$col.Index
                if ($col.FirstLineOnly -and $i -gt 0) {
                    $physical[$idx] = ''
                    continue
                }
                $lineSet = @($wrapped[$idx])
                $physical[$idx] = if ($i -lt $lineSet.Count) { $lineSet[$i] } else { '' }
            }
            [void]$groupLines.Add($physical)
        }
        [void]$expanded.Add($groupLines)
    }

    return @($expanded)
}

function Format-DisplayTable {
    param(
        [Parameter(Mandatory)][object[]] $Columns,
        [Parameter(Mandatory)][object[]] $Rows,
        [int]  $TotalWidth = 0,
        [bool] $RowSeparator = $true
    )

    $colDefs = @(Resolve-DisplayTableColumns -Columns $Columns -Rows $Rows -TotalWidth $TotalWidth)
    $hasWrapCol = @($colDefs | Where-Object { $_.Wrap }).Count -gt 0
    if ($hasWrapCol) {
        $logicalGroups = @(Expand-WrappedTableRows -Columns $colDefs -Rows $Rows)
    }
    else {
        $logicalGroups = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $Rows) {
            $cells = if ($row -is [string[]]) { $row } else { @([string[]]$row) }
            $lineGroup = [System.Collections.Generic.List[string[]]]::new()
            [void]$lineGroup.Add($cells)
            [void]$logicalGroups.Add($lineGroup)
        }
    }

    $h = [char]0x2500  # ─
    $v = [char]0x2502  # │
    $tl = [char]0x250C; $tr = [char]0x2510; $bl = [char]0x2514; $br = [char]0x2518
    $lm = [char]0x251C; $rm = [char]0x2524; $tm = [char]0x252C; $bm = [char]0x2534; $cv = [char]0x253C

    function Get-TableBorderLine {
        param([char] $Left, [char] $Join, [char] $Right)
        $parts = foreach ($col in $colDefs) { ($h.ToString() * ($col.Width + 2)) }
        return $Left + ($parts -join $Join) + $Right
    }

    function Get-TableCell {
        param(
            [string[]] $Cells,
            [int]      $Index
        )
        if ($null -eq $Cells -or $Index -lt 0 -or $Index -ge @($Cells).Count) { return '' }
        return [string]$Cells[$Index]
    }

    function Get-TableDataLine {
        param([string[]] $Cells)
        $line = [System.Text.StringBuilder]::new()
        [void]$line.Append($v)
        for ($i = 0; $i -lt $colDefs.Count; $i++) {
            $idx = [int]$colDefs[$i].Index
            $cell = Pad-DisplayTextRaw -Text (Get-TableCell -Cells $Cells -Index $idx) -Width $colDefs[$i].Width
            [void]$line.Append(" $cell $v")
        }
        return $line.ToString()
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add((Get-TableBorderLine $tl $tm $tr))
    $headerCells = [string[]]::new((($colDefs | ForEach-Object { [int]$_.Index } | Measure-Object -Maximum).Maximum) + 1)
    foreach ($col in $colDefs) { $headerCells[[int]$col.Index] = $col.Header }
    [void]$lines.Add((Get-TableDataLine $headerCells))
    [void]$lines.Add((Get-TableBorderLine $lm $cv $rm))

    for ($gi = 0; $gi -lt @($logicalGroups).Count; $gi++) {
        $lineGroup = $logicalGroups[$gi]
        for ($li = 0; $li -lt $lineGroup.Count; $li++) {
            [void]$lines.Add((Get-TableDataLine $lineGroup[$li]))
        }
        if ($RowSeparator -and $gi -lt (@($logicalGroups).Count - 1)) {
            [void]$lines.Add((Get-TableBorderLine $lm $cv $rm))
        }
    }

    [void]$lines.Add((Get-TableBorderLine $bl $bm $br))
    return @($lines)
}

function Get-PackageTableColumns {
    param(
        [Parameter(Mandatory)][object[]] $Rows,
        [int] $TotalWidth = 80
    )
    $seqWidth = Get-SeqColumnWidth -RowCount @($Rows).Count
    return @(
        @{ Header = (msg 'ui.packages.col.no'); Index = 0; FixedWidth = $seqWidth; FirstLineOnly = $true }
        @{ Header = (msg 'ui.packages.col.name'); Index = 1; AutoWidth = $true; FirstLineOnly = $true }
        @{ Header = (msg 'ui.packages.col.desc'); Index = 2; HalfFlex = $true; Wrap = $true }
        @{ Header = (msg 'ui.packages.col.deps'); Index = 3; HalfFlex = $true; Wrap = $true; CommaWrap = $true }
    )
}

function Get-PackageTableWidth {
    return 80
}

# 按 packages.psd1 分组展示已选安装包（计划摘要 / 已保存配置）
function Write-PackageList {
    param(
        [Parameter(Mandatory)][string]   $TitleKey,
        [Parameter(Mandatory)][string[]] $SelectedNames,
        [string[]]                       $ScoopApps = @(),
        [Parameter(Mandatory)]             $PackagesDef
    )

    $selectedSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $SelectedNames) {
        if (-not [string]::IsNullOrWhiteSpace([string]$n)) {
            [void]$selectedSet.Add([string]$n)
        }
    }

    $scoopList = @($ScoopApps | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $itemCount = if ($selectedSet.Count -gt 0) { $selectedSet.Count } else { $scoopList.Count }
    $scoopCount = if ($scoopList.Count -gt 0) { $scoopList.Count } else { $itemCount }
    Write-Plan (msg $TitleKey $itemCount $scoopCount)

    $tableWidth = Get-PackageTableWidth

    if ($selectedSet.Count -eq 0) {
        $seq = 1
        $fallbackRows = @($scoopList | ForEach-Object {
                $row = @([string]$seq, [string]$_)
                $seq++
                , $row
            })
        $rows = @($fallbackRows)
        $cols = @(
            @{ Header = (msg 'ui.packages.col.no'); Index = 0; FixedWidth = (Get-SeqColumnWidth -RowCount $rows.Count); FirstLineOnly = $true }
            @{ Header = (msg 'ui.packages.col.name'); Index = 1; AutoWidth = $true; FirstLineOnly = $true }
        )
        Write-PlanBlock -Lines (Format-DisplayTable -Columns $cols -Rows $rows -TotalWidth $tableWidth)
        return
    }

    $resolvedScoop = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $tableRows = [System.Collections.Generic.List[string[]]]::new()
    $seq = 1

    $groups = @(
        @{ TitleKey = 'ui.packages.group.rec'; Items = @($PackagesDef.Recommended) }
        @{ TitleKey = 'ui.packages.group.dev'; Items = @($PackagesDef.Optional.Dev) }
        @{ TitleKey = 'ui.packages.group.term'; Items = @($PackagesDef.Optional.Term) }
        @{ TitleKey = 'ui.packages.group.beauty'; Items = @($PackagesDef.Optional.Beauty) }
    )

    foreach ($group in $groups) {
        $groupItems = @($group.Items | Where-Object { $selectedSet.Contains([string]$_.Name) })
        foreach ($item in $groupItems) {
            $name = [string]$item.Name
            $desc = Get-PackageDesc -Package $item
            $deps = ''
            if ($item.Contains('Packages') -and $null -ne $item.Packages) {
                $pkgNames = @($item.Packages | ForEach-Object { [string]$_ })
                foreach ($p in $pkgNames) { [void]$resolvedScoop.Add($p) }
                $extraPkgs = @($pkgNames | Where-Object { $_ -ne $name })
                if ($extraPkgs.Count -gt 0) { $deps = $extraPkgs -join ', ' }
            }
            else {
                [void]$resolvedScoop.Add($name)
            }
            [void]$tableRows.Add(@([string]$seq, $name, $desc, $deps))
            $seq++
        }
    }

    $extras = @($scoopList | Where-Object { -not $resolvedScoop.Contains([string]$_) })
    foreach ($name in $extras) {
        [void]$tableRows.Add(@([string]$seq, $name, '', ''))
        $seq++
    }

    $rows = @($tableRows)
    Write-PlanBlock -Lines (Format-DisplayTable `
            -Columns (Get-PackageTableColumns -Rows $rows -TotalWidth $tableWidth) `
            -Rows     $rows `
            -TotalWidth $tableWidth)
}
