# =====================================================================
# Windots 交互 UI (lib/ui.ps1)
# =====================================================================

# 丢弃启动阶段或输出期间误触的按键，避免 Read-Host / ReadKey 直接消费缓冲输入
$script:WindotsConsoleInputFlush = $false
$script:WindotsConsoleCancelLoaded = $false
$script:WindotsConsoleInputInit = $false
$script:WindotsMenuCursorColor = [ConsoleColor]::Red

function Initialize-WindotsConsoleCancelType {
    if ($script:WindotsConsoleCancelLoaded -and ('WindotsConsoleCancel' -as [type])) { return }
    if (-not ('WindotsConsoleCancel' -as [type])) {
        Add-Type -TypeDefinition @'
using System;

public static class WindotsConsoleCancel {
    static DateTime LastCtrlC = DateTime.MinValue;
    static string Hint = "Press Ctrl+C again to exit";
    const int WindowMs = 800;

    public static void SetHint(string hint) {
        if (!string.IsNullOrEmpty(hint)) { Hint = hint; }
    }

    public static void Reset() {
        LastCtrlC = DateTime.MinValue;
    }

    static void OnSignal() {
        var now = DateTime.UtcNow;
        if ((now - LastCtrlC).TotalMilliseconds <= WindowMs) {
            Environment.Exit(130);
        }
        LastCtrlC = now;
        try {
            Console.WriteLine();
            Console.WriteLine(Hint);
        }
        catch { }
    }

    public static void OnCancel(object sender, ConsoleCancelEventArgs e) {
        e.Cancel = true;
        OnSignal();
    }

    public static void OnReadKey() {
        OnSignal();
    }
}
'@ -ErrorAction Stop
    }
    if (-not ('WindotsConsoleCancel' -as [type])) {
        throw [InvalidOperationException]::new('Failed to load WindotsConsoleCancel type.')
    }
    $script:WindotsConsoleCancelLoaded = $true
}

function Initialize-WindotsConsoleInput {
    Initialize-WindotsConsoleCancelType
    $hint = if (Get-Command -Name msg -ErrorAction SilentlyContinue) {
        [string](msg 'ui.ctrlc.hint' 'Press Ctrl+C again to exit')
    }
    else {
        'Press Ctrl+C again to exit'
    }
    [WindotsConsoleCancel]::SetHint($hint)
    if ($script:WindotsConsoleInputInit) { return }
    $script:WindotsConsoleInputInit = $true
    try { [Console]::TreatControlCAsInput = $true } catch { }
    try {
        [Console]::add_CancelKeyPress([ConsoleCancelEventHandler][WindotsConsoleCancel]::OnCancel)
    }
    catch { }
}

function Test-CtrlCKey {
    param($Key)
    return ($Key.Key -eq 'C' -and (($Key.Modifiers -band [ConsoleModifiers]::Control) -ne 0))
}

function Invoke-CtrlCExitCheck {
    Initialize-WindotsConsoleCancelType
    [WindotsConsoleCancel]::OnReadKey()
}

function Read-MenuKey {
    Initialize-WindotsConsoleInput
    while ($true) {
        $key = [Console]::ReadKey($true)
        if (Test-CtrlCKey $key) {
            Invoke-CtrlCExitCheck
            continue
        }
        [WindotsConsoleCancel]::Reset()
        return $key
    }
}

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
    Initialize-WindotsConsoleInput
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
    Initialize-WindotsConsoleInput
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

function Get-ConsoleHeight {
    param([int] $MinHeight = 24)
    $h = 0
    try {
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            try { $h = [int][Console]::WindowHeight } catch { }
        }
    }
    catch { }
    if ($h -le 0) {
        try {
            if ($Host.UI -and $Host.UI.RawUI) {
                $h = [int]$Host.UI.RawUI.WindowSize.Height
            }
        }
        catch { }
    }
    if ($h -le 0 -and $env:LINES) {
        try { $h = [int]$env:LINES } catch { }
    }
    if ($h -le 0) { return $MinHeight }
    return $h
}

function Clear-ConsoleViewport {
    param([int] $Lines)
    if ($Lines -le 0) { return }
    try {
        $w = [Math]::Max(1, [Console]::WindowWidth)
        $blank = ' ' * $w
        for ($y = 0; $y -lt $Lines; $y++) {
            [Console]::SetCursorPosition(0, $y)
            [Console]::Write($blank)
        }
        [Console]::SetCursorPosition(0, 0)
    }
    catch {
        Clear-Host
    }
}

# 多选菜单（↑↓/J/K 移动, 空格切换, A全选, N全不选, Enter确认, Esc取消）
# -Grouped：分组树模式（D/U/→/← 跳组, Shift+D/U 底/顶组, F/Shift+F 折叠, A/N 当前组, Shift+A/N 全局）
function Select-Items {
    param(
        [Parameter(Mandatory)][string]   $Title,
        [Parameter(Mandatory)][object[]] $Items,
        [scriptblock] $Labeler = { param($x) [string]$x },
        [scriptblock] $SuffixLabeler = $null,
        [scriptblock] $DefaultSet = { param($x) $false },
        [string[]]    $Disabled = @(),
        [string[]]    $NotInstalled = @(),
        [string[]]    $Installed = @(),
        [string[]]    $Locked = @(),
        [switch]      $Grouped,
        [string]      $HintKey = 'ui.select.hint',
        [switch]      $GlobalToggle,
        [switch]      $GlobalReadOnly,
        [scriptblock] $GlobalSet = $null,
        [ref]         $GlobalMapOut,
        [scriptblock] $InstalledChecker = $null,
        [scriptblock] $InstalledAnyChecker = $null
    )
    $Items = @($Items | Where-Object { $null -ne $_ })
    if ($Items.Count -eq 0) { Write-Warn (msg 'ui.empty' $Title); return @() }

    Clear-ConsoleInputBuffer

    $isGroupRow = { param($row) $Grouped -and $row.Kind -eq 'group' }
    $isPkgRow = { param($row) -not $Grouped -or $row.Kind -eq 'package' }

    $selected = New-Object 'bool[]' $Items.Count
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if (& $isGroupRow $Items[$i]) { $selected[$i] = $false; continue }
        $lbl = & $Labeler $Items[$i]
        $selected[$i] = if ($Locked -contains $lbl) { $true }
        elseif ($Disabled -contains $lbl -or $NotInstalled -contains $lbl) { $false }
        else { [bool](& $DefaultSet $Items[$i]) }
    }
    $initialSelected = New-Object 'bool[]' $Items.Count
    for ($i = 0; $i -lt $Items.Count; $i++) { $initialSelected[$i] = $selected[$i] }
    $collapsedGroups = @{}
    $hideLocked = $false
    $hasLockedPackages = @($Locked | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0

    $globalTagEnabled = $GlobalToggle -or $GlobalReadOnly
    $globalFlags = New-Object 'bool[]' $Items.Count
    if ($globalTagEnabled) {
        $setGlobal = if ($GlobalSet) { $GlobalSet } else { { param($x) $false } }
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (& $isGroupRow $Items[$i]) { continue }
            $globalFlags[$i] = [bool](& $setGlobal $Items[$i])
        }
    }

    $installedTag = msg 'ui.select.installed'
    $notInstalledTag = msg 'ui.select.not.installed'
    $unsupportedTag = msg 'ui.select.unsupported'
    $globalTag = if ($globalTagEnabled) { msg 'ui.select.global' } else { '' }
    $globalTagColor = [ConsoleColor]::DarkYellow
    if ($Grouped) {
        $hintMove = msg 'ui.select.tree.hint.move'
        $hintSelectKey = if ($GlobalReadOnly -and -not $GlobalToggle) {
            'ui.select.tree.hint.select.noglobal'
        }
        else {
            'ui.select.tree.hint.select'
        }
        $hintSelect = msg $hintSelectKey
    }
    else {
        $hint = msg $HintKey
    }
    $cursorColor = $script:WindotsMenuCursorColor
    $headerLines = if ($Grouped) { 4 } else { 3 }

    $isRowLockedPkg = {
        param([int] $Idx)
        if (-not (& $isPkgRow $Items[$Idx])) { return $false }
        $lbl = & $Labeler $Items[$Idx]
        return $Locked -contains $lbl
    }

    $isRowVisible = {
        param([int] $Idx)
        if ($hideLocked -and $hasLockedPackages -and (& $isRowLockedPkg $Idx)) { return $false }
        if (-not $Grouped) { return $true }
        $anc = $Items[$Idx].AncestorGroupRowIndices
        if ($null -eq $anc -or @($anc).Count -eq 0) { return $true }
        foreach ($a in @($anc)) {
            if ($collapsedGroups.ContainsKey([int]$a)) { return $false }
        }
        return $true
    }

    $getVisibleRowIndices = {
        $list = [System.Collections.Generic.List[int]]::new()
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (& $isRowVisible $i) { [void]$list.Add($i) }
        }
        return @($list)
    }

    $resolveGroupRow = {
        param([int] $From)
        if (& $isGroupRow $Items[$From]) { return $From }
        $anc = @($Items[$From].AncestorGroupRowIndices)
        if ($anc.Count -gt 0) { return [int]$anc[-1] }
        return $From
    }

    $getRowMark = {
        param([int] $Idx)
        if (& $isGroupRow $Items[$Idx]) {
            $indices = @($Items[$Idx].PackageIndices)
            $sel = 0; $total = 0
            foreach ($pi in $indices) {
                $lbl = & $Labeler $Items[$pi]
                if ($Disabled -contains $lbl -or $NotInstalled -contains $lbl) { continue }
                $total++
                if ($selected[$pi]) { $sel++ }
            }
            if ($total -eq 0 -or $sel -eq 0) { return ' ' }
            if ($sel -eq $total) { return 'x' }
            return '-'
        }
        if ($selected[$Idx]) { return 'x' }
        return ' '
    }

    $getGroupBoxMark = {
        param([int] $Idx, [bool] $Collapsed)
        $mark = & $getRowMark $Idx
        if (-not $Collapsed) { return [string]$mark }
        if ($mark -eq '-') { return '> -' }
        if ($mark -eq 'x') { return '> x' }
        return '> '
    }

    $rowNavigable = {
        param([int] $Idx)
        if (& $isGroupRow $Items[$Idx]) { return $true }
        $lbl = & $Labeler $Items[$Idx]
        return $Disabled -notcontains $lbl -and $NotInstalled -notcontains $lbl
    }

    $rowMovable = {
        param([int] $Idx)
        if (-not (& $rowNavigable $Idx)) { return $false }
        if (& $isGroupRow $Items[$Idx]) { return $true }
        $lbl = & $Labeler $Items[$Idx]
        return $Locked -notcontains $lbl
    }

    $rowGlobalToggleable = {
        param([int] $Idx)
        if (-not $GlobalToggle) { return $false }
        if (-not (& $isPkgRow $Items[$Idx])) { return $false }
        if (-not (& $rowNavigable $Idx)) { return $false }
        $lbl = & $Labeler $Items[$Idx]
        return $Locked -notcontains $lbl
    }

    $rowGroupGlobalToggleable = {
        param([int] $Idx)
        if (-not $GlobalToggle) { return $false }
        if (-not (& $isGroupRow $Items[$Idx])) { return $false }
        foreach ($pi in @($Items[$Idx].PackageIndices)) {
            if (& $rowGlobalToggleable $pi) { return $true }
        }
        return $false
    }

    $rowSelectable = {
        param([int] $Idx)
        if (-not (& $rowNavigable $Idx)) { return $false }
        if (& $isGroupRow $Items[$Idx]) { return $true }
        $lbl = & $Labeler $Items[$Idx]
        return $Locked -notcontains $lbl
    }

    $rowInstalledAtScope = {
        param([int] $Idx)
        $lbl = & $Labeler $Items[$Idx]
        if ($GlobalToggle -and ($Locked -contains $lbl) -and $InstalledAnyChecker) {
            return [bool](& $InstalledAnyChecker $Items[$Idx])
        }
        if ($GlobalToggle -and $InstalledChecker) {
            return [bool](& $InstalledChecker $Items[$Idx] $globalFlags[$Idx])
        }
        return ($Installed -contains $lbl)
    }

    $writePkgTags = {
        param(
            [string]         $LineText,
            [ConsoleColor]   $LineColor,
            [string]         $Suffix = '',
            [ConsoleColor]   $SuffixColor = [ConsoleColor]::DarkCyan,
            [string]         $StatusTag = '',
            [ConsoleColor]   $StatusTagColor = [ConsoleColor]::DarkGray,
            [bool]           $ShowGlobal = $false
        )
        if ($tagAreaStart -le 0) {
            Write-Host -NoNewline $LineText -ForegroundColor $LineColor
            if ($Suffix) { Write-Host $Suffix -ForegroundColor $SuffixColor }
            else { Write-Host '' }
            return
        }
        $line = [string]$LineText
        $sfx = [string]$Suffix
        $contentW = (Get-DisplayWidth $line) + (Get-DisplayWidth $sfx)
        if ($contentW -gt $tagAreaStart) {
            $line = Truncate-DisplayText -Text ($line + $sfx) -Width $tagAreaStart
            $sfx = ''
            $contentW = Get-DisplayWidth $line
        }
        $pad = $tagAreaStart - $contentW
        Write-Host -NoNewline $line -ForegroundColor $LineColor
        if ($sfx) { Write-Host -NoNewline $sfx -ForegroundColor $SuffixColor }
        if ($pad -gt 0) { Write-Host -NoNewline (' ' * $pad) -ForegroundColor $LineColor }
        if ($globalColWidth -gt 0) {
            if ($ShowGlobal) { Write-Host -NoNewline $globalTag -ForegroundColor $globalTagColor }
            $gRem = $globalColWidth - $(if ($ShowGlobal) { Get-DisplayWidth $globalTag } else { 0 })
            if ($gRem -gt 0) { Write-Host -NoNewline (' ' * $gRem) -ForegroundColor $LineColor }
            Write-Host -NoNewline ' ' -ForegroundColor $LineColor
        }
        if ($StatusTag) { Write-Host -NoNewline $StatusTag -ForegroundColor $StatusTagColor }
        Write-Host ''
    }

    $getNavigableRowIndices = {
        $list = [System.Collections.Generic.List[int]]::new()
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (-not (& $isRowVisible $i)) { continue }
            if (-not (& $rowMovable $i)) { continue }
            [void]$list.Add($i)
        }
        return @($list)
    }

    $moveCursor = {
        param([int] $From, [int] $Dir)
        $nav = @(& $getNavigableRowIndices)
        if ($nav.Count -eq 0) { return $From }
        $pos = [array]::IndexOf([object[]]$nav, $From)
        if ($pos -lt 0) {
            if ($Dir -gt 0) {
                foreach ($i in $nav) { if ($i -ge $From) { return [int]$i } }
                return [int]$nav[0]
            }
            for ($j = $nav.Count - 1; $j -ge 0; $j--) {
                if ($nav[$j] -le $From) { return [int]$nav[$j] }
            }
            return [int]$nav[$nav.Count - 1]
        }
        $next = ($pos + $Dir + $nav.Count) % $nav.Count
        return [int]$nav[$next]
    }

    $navInit = @(& $getNavigableRowIndices)
    $cursor = if ($navInit.Count -gt 0) { [int]$navInit[0] } else { 0 }

    $getSelectedCount = {
        $count = 0
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (-not $selected[$i]) { continue }
            if (-not (& $rowSelectable $i)) { continue }
            if ($Grouped -and -not (& $isPkgRow $Items[$i])) { continue }
            if ($initialSelected[$i]) { continue }
            $count++
        }
        return $count
    }

    $currentGroupRow = {
        if (& $isGroupRow $Items[$cursor]) { return $cursor }
        $anc = @($Items[$cursor].AncestorGroupRowIndices)
        if ($anc.Count -gt 0) { return [int]$anc[-1] }
        return -1
    }

    $setGroupSubtree = {
        param([int] $GroupRowIdx, [bool] $Value)
        foreach ($pi in @($Items[$GroupRowIdx].PackageIndices)) {
            $lbl = & $Labeler $Items[$pi]
            if ($Value) {
                if ($Disabled -notcontains $lbl -and $NotInstalled -notcontains $lbl -and $Locked -notcontains $lbl) {
                    $selected[$pi] = $true
                }
            }
            elseif ($Locked -notcontains $lbl) {
                $selected[$pi] = $false
            }
        }
    }

    $toggleGroupSubtreeGlobal = {
        param([int] $GroupRowIdx)
        $allGlobal = $true
        $anyToggleable = $false
        foreach ($pi in @($Items[$GroupRowIdx].PackageIndices)) {
            if (-not (& $rowGlobalToggleable $pi)) { continue }
            $anyToggleable = $true
            if (-not $globalFlags[$pi]) { $allGlobal = $false; break }
        }
        if (-not $anyToggleable) { return }
        $newVal = -not $allGlobal
        foreach ($pi in @($Items[$GroupRowIdx].PackageIndices)) {
            if (& $rowGlobalToggleable $pi) { $globalFlags[$pi] = $newVal }
        }
    }

    $toggleAllPackagesGlobal = {
        $allGlobal = $true
        $anyToggleable = $false
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (-not (& $rowGlobalToggleable $i)) { continue }
            $anyToggleable = $true
            if (-not $globalFlags[$i]) { $allGlobal = $false; break }
        }
        if (-not $anyToggleable) { return }
        $newVal = -not $allGlobal
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (& $rowGlobalToggleable $i) { $globalFlags[$i] = $newVal }
        }
    }

    $setByGroupRow = {
        param([int] $GroupRow, [bool] $Value)
        if ($GroupRow -lt 0) { return }
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (-not (& $isPkgRow $Items[$i])) { continue }
            $anc = @($Items[$i].AncestorGroupRowIndices)
            if ($anc.Count -eq 0 -or [int]$anc[-1] -ne $GroupRow) { continue }
            $lbl = & $Labeler $Items[$i]
            if ($Value) {
                if ($Disabled -notcontains $lbl -and $NotInstalled -notcontains $lbl -and $Locked -notcontains $lbl) {
                    $selected[$i] = $true
                }
            }
            elseif ($Locked -notcontains $lbl) {
                $selected[$i] = $false
            }
        }
    }

    $setAllPackages = {
        param([bool] $Value)
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (-not (& $isPkgRow $Items[$i])) { continue }
            $lbl = & $Labeler $Items[$i]
            if ($Value) {
                if ($Disabled -notcontains $lbl -and $NotInstalled -notcontains $lbl -and $Locked -notcontains $lbl) {
                    $selected[$i] = $true
                }
            }
            elseif ($Locked -notcontains $lbl) {
                $selected[$i] = $false
            }
        }
    }

    $jumpGroup = {
        param([int] $Dir, [int] $From)
        $indices = [System.Collections.Generic.List[int]]::new()
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if ((& $isGroupRow $Items[$i]) -and (& $isRowVisible $i)) { [void]$indices.Add($i) }
        }
        if ($indices.Count -eq 0) { return $From }
        $pos = 0
        for ($j = 0; $j -lt $indices.Count; $j++) {
            if ($indices[$j] -eq $From) { $pos = $j; break }
            if ($indices[$j] -lt $From) { $pos = $j }
        }
        $next = ($pos + $Dir + $indices.Count) % $indices.Count
        return $indices[$next]
    }

    $jumpGroupUp = {
        param([int] $From)
        if (& $isGroupRow $Items[$From]) {
            return & $jumpGroup -1 $From
        }
        return & $resolveGroupRow $From
    }

    $jumpGroupTop = {
        param([int] $From)
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (& $isGroupRow $Items[$i]) { return $i }
        }
        return $From
    }

    $expandGroupPath = {
        param([int] $GroupRowIdx)
        foreach ($a in @($Items[$GroupRowIdx].AncestorGroupRowIndices)) {
            if ($collapsedGroups.ContainsKey([int]$a)) { $collapsedGroups.Remove([int]$a) }
        }
    }

    $jumpGroupBottom = {
        param([int] $From)
        for ($i = $Items.Count - 1; $i -ge 0; $i--) {
            if (& $isGroupRow $Items[$i]) {
                & $expandGroupPath $i
                return $i
            }
        }
        return $From
    }

    $toggleAllGroups = {
        $groupRows = [System.Collections.Generic.List[int]]::new()
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if (& $isGroupRow $Items[$i]) { [void]$groupRows.Add($i) }
        }
        if ($groupRows.Count -eq 0) { return }
        $allCollapsed = $true
        foreach ($g in $groupRows) {
            if (-not $collapsedGroups.ContainsKey($g)) { $allCollapsed = $false; break }
        }
        if ($allCollapsed) { $collapsedGroups.Clear() }
        else {
            foreach ($g in $groupRows) { $collapsedGroups[$g] = $true }
        }
    }

    $scrollTop = 0
    $firstDraw = $true

    $globalColWidth = if ($globalTagEnabled) { Get-DisplayWidth $globalTag } else { 0 }
    $maxPkgContentWidth = 0
    for ($ti = 0; $ti -lt $Items.Count; $ti++) {
        if (-not (& $isPkgRow $Items[$ti])) { continue }
        $tLabel = & $Labeler $Items[$ti]
        $tSfx = if ($SuffixLabeler) { [string](& $SuffixLabeler $Items[$ti]) } else { '' }
        $tPrefix = if ($Grouped -and $Items[$ti].Depth -gt 0) { '  ' * [int]$Items[$ti].Depth } else { '' }
        $tw = [Math]::Max(
            (Get-DisplayWidth "${tPrefix}> [x] ${tLabel}${tSfx}"),
            [Math]::Max(
                (Get-DisplayWidth "${tPrefix}> [ ] ${tLabel}${tSfx}"),
                (Get-DisplayWidth "${tPrefix}  [ ] ${tLabel}${tSfx}")
            )
        )
        if ($tw -gt $maxPkgContentWidth) { $maxPkgContentWidth = $tw }
    }
    $tagAreaStart = if ($maxPkgContentWidth -gt 0) { $maxPkgContentWidth + 4 } else { 0 }

    while ($true) {
        $visibleRowIdx = @(& $getVisibleRowIndices)
        if ($Grouped -and ($visibleRowIdx -notcontains $cursor)) {
            $cursor = & $resolveGroupRow $cursor
            if ($visibleRowIdx -notcontains $cursor) {
                $cursor = if ($visibleRowIdx.Count -gt 0) { [int]$visibleRowIdx[0] } else { 0 }
            }
        }
        $navRowIdx = @(& $getNavigableRowIndices)
        if ($navRowIdx.Count -gt 0 -and ($navRowIdx -notcontains $cursor)) {
            $cursor = & $moveCursor $cursor 1
        }

        $consoleH = Get-ConsoleHeight
        $listAvail = [Math]::Max(1, $consoleH - $headerLines)
        $visCount = if ($Grouped) { $visibleRowIdx.Count } else { $Items.Count }
        $needScroll = $visCount -gt $listAvail
        $viewRows = if ($needScroll) { [Math]::Max(1, $listAvail - 4) } else { $visCount }
        $maxScrollVis = [Math]::Max(0, $visCount - $viewRows)
        $cursorVisPos = if ($Grouped) {
            $p = [array]::IndexOf([object[]]$visibleRowIdx, $cursor)
            if ($p -lt 0) { 0 } else { $p }
        }
        else { $cursor }
        # 光标上方预览约视口高度 1/3，至少 1 项（视口过窄时不强制）
        $scrollMargin = 0
        if ($viewRows -gt 1) {
            $scrollMargin = [Math]::Max(1, [Math]::Floor($viewRows / 3))
            $scrollMargin = [Math]::Min($scrollMargin, $viewRows - 1)
        }
        $idealTop = $cursorVisPos - $scrollMargin
        $scrollTopVis = [Math]::Max(0, [Math]::Min($idealTop, $maxScrollVis))

        if ($firstDraw) { Clear-Host; $firstDraw = $false }
        else { Clear-ConsoleViewport -Lines $consoleH }

        Write-Host $Title -ForegroundColor Magenta
        if ($Grouped) {
            Write-Host $hintMove -ForegroundColor DarkGray
            Write-Host $hintSelect -ForegroundColor DarkGray
        }
        else {
            Write-Host $hint -ForegroundColor DarkGray
        }
        $selectedCount = & $getSelectedCount
        if ($selectedCount -gt 0) {
            Write-Host -NoNewline (msg 'ui.select.selected.count' $selectedCount) -ForegroundColor $cursorColor
        }
        if ($hideLocked -and $hasLockedPackages) {
            $hiddenLockedCount = 0
            for ($hi = 0; $hi -lt $Items.Count; $hi++) {
                if (& $isRowLockedPkg $hi) { $hiddenLockedCount++ }
            }
            Write-Host -NoNewline (msg 'ui.select.locked.hidden' $hiddenLockedCount) -ForegroundColor DarkGray
        }
        Write-Host ''

        if ($needScroll -and $scrollTopVis -gt 0) {
            Write-Host (msg 'ui.select.scroll.up' $scrollTopVis) -ForegroundColor DarkGray
        }

        $renderEnd = [Math]::Min($scrollTopVis + $viewRows, $visCount)
        for ($vi = $scrollTopVis; $vi -lt $renderEnd; $vi++) {
            $i = if ($Grouped) { [int]$visibleRowIdx[$vi] } else { $vi }
            $label = & $Labeler $Items[$i]
            $sfx = if ($SuffixLabeler -and (& $isPkgRow $Items[$i])) { [string](& $SuffixLabeler $Items[$i]) } else { '' }
            $prefix = if ($Grouped -and $Items[$i].Depth -gt 0) { '  ' * [int]$Items[$i].Depth } else { '' }
            $isDisabled = $Disabled -contains $label
            $isNotInstalled = $NotInstalled -contains $label
            $isInstalled = $Installed -contains $label
            $isLocked = $Locked -contains $label
            $mark = & $getRowMark $i
            $arrow = if ($i -eq $cursor) { '>' } else { ' ' }

            if (& $isGroupRow $Items[$i]) {
                $color = if ($i -eq $cursor) { $cursorColor } else { [ConsoleColor]::Yellow }
                $box = & $getGroupBoxMark $i $collapsedGroups.ContainsKey($i)
                Write-Host ("$prefix$arrow [$box] $label") -ForegroundColor $color
                continue
            }

            if ($isDisabled) {
                & $writePkgTags "$prefix  [ ] $label" ([ConsoleColor]::DarkGray) '' ([ConsoleColor]::DarkCyan) $unsupportedTag ([ConsoleColor]::DarkGray) $false
            }
            elseif ($isNotInstalled) {
                $lineColor = if ($i -eq $cursor) { $cursorColor } else { [ConsoleColor]::DarkGray }
                $showG = $globalTagEnabled -and $globalFlags[$i]
                & $writePkgTags "$prefix$arrow [ ] $label" $lineColor $sfx ([ConsoleColor]::DarkGray) $notInstalledTag ([ConsoleColor]::DarkGray) $showG
            }
            elseif ($isLocked) {
                $lockedText = "$prefix$arrow [x] $label"
                $lineColor = if ($i -eq $cursor) { $cursorColor } else { [ConsoleColor]::DarkGray }
                $suffixColor = [ConsoleColor]::DarkGray
                $installedAtScope = & $rowInstalledAtScope $i
                $statusText = if ($installedAtScope) { $installedTag } else { '' }
                $statusColor = if ($installedAtScope) { [ConsoleColor]::DarkGreen } else { [ConsoleColor]::DarkGray }
                $showG = $globalTagEnabled -and $globalFlags[$i]
                & $writePkgTags $lockedText $lineColor $sfx $suffixColor $statusText $statusColor $showG
            }
            elseif ($isInstalled) {
                $itemColor = if ($selected[$i]) { [ConsoleColor]::Green } else { [ConsoleColor]::Gray }
                $color = if ($i -eq $cursor) { $cursorColor } else { $itemColor }
                $lineText = "$prefix$arrow [$mark] $label"
                $showG = $globalTagEnabled -and $globalFlags[$i]
                & $writePkgTags $lineText $color $sfx ([ConsoleColor]::DarkCyan) $installedTag ([ConsoleColor]::DarkGreen) $showG
            }
            else {
                $itemColor = if ($selected[$i]) { [ConsoleColor]::Green } else { [ConsoleColor]::Gray }
                $color = if ($i -eq $cursor) { $cursorColor } else { $itemColor }
                $lineText = "$prefix$arrow [$mark] $label"
                $showInstalled = & $rowInstalledAtScope $i
                $statusText = if ($GlobalToggle -and $showInstalled) { $installedTag } else { '' }
                $statusColor = [ConsoleColor]::DarkGreen
                $showG = $globalTagEnabled -and $globalFlags[$i]
                & $writePkgTags $lineText $color $sfx ([ConsoleColor]::DarkCyan) $statusText $statusColor $showG
            }
        }

        if ($needScroll -and ($scrollTopVis + $viewRows) -lt $visCount) {
            $below = $visCount - $scrollTopVis - $viewRows
            Write-Host (msg 'ui.select.scroll.down' $below) -ForegroundColor DarkGray
        }

        $key = Read-MenuKey
        $shift = ($key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0
        switch ($key.Key) {
            { $_ -in @('DownArrow', 'J') } { $cursor = & $moveCursor $cursor 1 }
            { $_ -in @('UpArrow', 'K') } { $cursor = & $moveCursor $cursor -1 }
            'RightArrow' { if ($Grouped) { $cursor = & $jumpGroup 1 $cursor } }
            'LeftArrow' { if ($Grouped) { $cursor = & $jumpGroupUp $cursor } }
            'D' {
                if ($Grouped) {
                    if ($shift) { $cursor = & $jumpGroupBottom $cursor }
                    else { $cursor = & $jumpGroup 1 $cursor }
                }
            }
            'U' {
                if ($Grouped) {
                    if ($shift) { $cursor = & $jumpGroupTop $cursor }
                    else { $cursor = & $jumpGroupUp $cursor }
                }
            }
            'F' {
                if ($Grouped) {
                    if ($shift) { & $toggleAllGroups }
                    else {
                        $g = & $resolveGroupRow $cursor
                        if ($collapsedGroups.ContainsKey($g)) { $collapsedGroups.Remove($g) }
                        else { $collapsedGroups[$g] = $true }
                        $cursor = $g
                    }
                }
            }
            'Spacebar' {
                if (& $isGroupRow $Items[$cursor]) {
                    $mark = & $getRowMark $cursor
                    & $setGroupSubtree $cursor ($mark -ne 'x')
                }
                elseif (& $rowSelectable $cursor) {
                    $selected[$cursor] = -not $selected[$cursor]
                }
            }
            'A' {
                if ($shift) { & $setAllPackages $true }
                elseif ($Grouped) { & $setByGroupRow (& $currentGroupRow) $true }
                else {
                    for ($i = 0; $i -lt $Items.Count; $i++) {
                        if (& $rowSelectable $i) { $selected[$i] = $true }
                    }
                }
            }
            'N' {
                if ($shift) { & $setAllPackages $false }
                elseif ($Grouped) { & $setByGroupRow (& $currentGroupRow) $false }
                else {
                    for ($i = 0; $i -lt $Items.Count; $i++) {
                        $lbl = & $Labeler $Items[$i]
                        if ($Locked -notcontains $lbl) { $selected[$i] = $false }
                    }
                }
            }
            'G' {
                if ($shift) { & $toggleAllPackagesGlobal }
                elseif (& $isGroupRow $Items[$cursor]) {
                    if (& $rowGroupGlobalToggleable $cursor) { & $toggleGroupSubtreeGlobal $cursor }
                }
                elseif (& $rowGlobalToggleable $cursor) {
                    $globalFlags[$cursor] = -not $globalFlags[$cursor]
                }
            }
            'H' {
                if ($hasLockedPackages) { $hideLocked = -not $hideLocked }
            }
            'Enter' {
                if ($GlobalToggle -and $PSBoundParameters.ContainsKey('GlobalMapOut') -and $null -ne $GlobalMapOut) {
                    $map = @{}
                    for ($i = 0; $i -lt $Items.Count; $i++) {
                        if (-not $selected[$i]) { continue }
                        if ($Grouped -and -not (& $isPkgRow $Items[$i])) { continue }
                        $lbl = & $Labeler $Items[$i]
                        $map[$lbl] = $globalFlags[$i]
                    }
                    $GlobalMapOut.Value = $map
                }
                $result = [System.Collections.Generic.List[object]]::new()
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    if (-not $selected[$i]) { continue }
                    if ($Grouped) {
                        if ($Items[$i].Kind -eq 'package') { [void]$result.Add($Items[$i].Package) }
                    }
                    else { [void]$result.Add($Items[$i]) }
                }
                return @($result)
            }
            'Escape' { return $null }
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
            $color = if ($i -eq $cursor) { $script:WindotsMenuCursorColor } else { [ConsoleColor]::Gray }
            Write-Host ("$arrow $label") -ForegroundColor $color
        }
        $key = Read-MenuKey
        switch ($key.Key) {
            { $_ -in @('UpArrow', 'K') } { $cursor = ($cursor - 1 + $Items.Count) % $Items.Count }
            { $_ -in @('DownArrow', 'J') } { $cursor = ($cursor + 1) % $Items.Count }
            'Enter' { return $Items[$cursor] }
        }
    }
}

Initialize-WindotsConsoleInput

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

function Get-DisplayTableOverhead {
    param([int] $ColumnCount)
    # │ sp cell sp │ per column → 3 display cols each, plus leading │
    return 1 + 3 * $ColumnCount
}

function Get-DisplayTableWidth {
    param([int[]] $ColumnWidths)
    return (Get-DisplayTableOverhead -ColumnCount $ColumnWidths.Count) + ($ColumnWidths | Measure-Object -Sum).Sum
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

    $overhead = Get-DisplayTableOverhead -ColumnCount $resolved.Count
    $fixedSum = ($resolved | Where-Object { $_.FixedWidth -gt 0 } | ForEach-Object { $_.FixedWidth } | Measure-Object -Sum).Sum
    $halfFlexItems = @($resolved | Where-Object { $_.HalfFlex })
    if ($halfFlexItems.Count -gt 0) {
        $remaining = $TotalWidth - $overhead - $fixedSum
        if ($remaining -lt $halfFlexItems.Count) {
            for ($hi = 0; $hi -lt $halfFlexItems.Count; $hi++) {
                $halfFlexItems[$hi].Width = [Math]::Max(1, [Math]::Floor($remaining / $halfFlexItems.Count))
            }
        }
        else {
            $base = [Math]::Floor($remaining / $halfFlexItems.Count)
            $extra = $remaining - ($base * $halfFlexItems.Count)
            for ($hi = 0; $hi -lt $halfFlexItems.Count; $hi++) {
                $halfFlexItems[$hi].Width = $base + $(if ($hi -eq ($halfFlexItems.Count - 1)) { $extra } else { 0 })
            }
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
        [int] $TotalWidth = 0
    )
    $seqWidth = Get-SeqColumnWidth -RowCount @($Rows).Count
    return @(
        @{ Header = (msg 'ui.packages.col.no'); Index = 0; FixedWidth = $seqWidth; FirstLineOnly = $true }
        @{ Header = (msg 'ui.packages.col.name'); Index = 1; AutoWidth = $true; FirstLineOnly = $true }
        @{ Header = (msg 'ui.packages.col.desc'); Index = 2; HalfFlex = $true; Wrap = $true }
        @{ Header = (msg 'ui.packages.col.deps'); Index = 3; HalfFlex = $true; Wrap = $true; CommaWrap = $true }
    )
}

function Get-ConsoleTableWidth {
    param(
        [int] $MinWidth = 80,
        [int] $Indent = 2
    )
    $consoleWidth = 0
    try {
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            try { $consoleWidth = [int][Console]::WindowWidth } catch { }
        }
    }
    catch { }
    if ($consoleWidth -le 0) {
        try {
            if ($Host.UI -and $Host.UI.RawUI) {
                $consoleWidth = [int]$Host.UI.RawUI.WindowSize.Width
            }
        }
        catch { }
    }
    if ($consoleWidth -le 0 -and $env:COLUMNS) {
        try { $consoleWidth = [int]$env:COLUMNS } catch { }
    }
    if ($consoleWidth -le 0) { return $MinWidth }

    $available = $consoleWidth - $Indent
    if ($available -lt 1) { return $MinWidth }
    return $available
}

function Get-PackageTableWidth {
    return Get-ConsoleTableWidth
}

function Test-ScoopAppHiddenInTable {
    param([Parameter(Mandatory)][string] $Name)
    # chezmoi 在启用同步时自动加入 Scoop_Apps，非用户手动勾选的包
    return (Get-ScoopAppBaseName -Name $Name) -ieq 'chezmoi'
}

function Get-PackageTableColumnsNamed {
    param(
        [Parameter(Mandatory)][object[]] $Rows,
        [Parameter(Mandatory)][string]    $NameColKey
    )
    $seqWidth = Get-SeqColumnWidth -RowCount @($Rows).Count
    return @(
        @{ Header = (msg 'ui.packages.col.no'); Index = 0; FixedWidth = $seqWidth; FirstLineOnly = $true }
        @{ Header = (msg $NameColKey); Index = 1; AutoWidth = $true; FirstLineOnly = $true }
        @{ Header = (msg 'ui.packages.col.desc'); Index = 2; HalfFlex = $true; Wrap = $true }
        @{ Header = (msg 'ui.packages.col.deps'); Index = 3; HalfFlex = $true; Wrap = $true; CommaWrap = $true }
    )
}

function Build-PackageListTableRows {
    param(
        [Parameter(Mandatory)] $SelectedSet,
        [Parameter(Mandatory)][hashtable] $PackagesDef,
        [string[]] $ScoopList,
        $ResolveState
    )

    $resolvedScoop = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $tableRows = [System.Collections.Generic.List[string[]]]::new()
    $orderedItems = [System.Collections.Generic.List[object]]::new()
    Invoke-PackageTreeWalk -Nodes @($PackagesDef.Packages) -Visitor {
        param($Kind, $Node, $GroupDefaults)
        if ($Kind -eq 'package' -and $SelectedSet.Contains([string]$Node.Name)) {
            [void]$orderedItems.Add($Node)
        }
    }
    $seq = 1
    foreach ($item in $orderedItems) {
        $name = [string]$item.Name
        $desc = Get-PackageDesc -Package $item
        $deps = ''
        if ($item.Contains('Packages') -and $null -ne $item.Packages) {
            $pkgNames = @($item.Packages | ForEach-Object { [string]$_ })
            foreach ($p in $pkgNames) { [void]$resolvedScoop.Add($p) }
            $extraPkgs = @($pkgNames | Where-Object {
                    (Get-ScoopAppBaseName -Name $_) -ine $name
                })
            if ($extraPkgs.Count -gt 0) {
                $deps = @($extraPkgs | ForEach-Object { Get-ScoopAppBaseName -Name $_ }) -join ', '
            }
        }
        else {
            [void]$resolvedScoop.Add($name)
        }
        [void]$tableRows.Add(@([string]$seq, $name, $desc, $deps))
        $seq++
    }

    $extras = @($ScoopList | Where-Object { -not $resolvedScoop.Contains([string]$_) })
    foreach ($name in $extras) {
        [void]$tableRows.Add(@([string]$seq, (Get-ScoopAppBaseName -Name ([string]$name)), '', ''))
        $seq++
    }

    $listedNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $tableRows) {
        if ($row.Count -gt 1) { [void]$listedNames.Add([string]$row[1]) }
    }
    foreach ($n in @($SelectedSet)) {
        $name = [string]$n
        if ($listedNames.Contains($name)) { continue }
        [void]$tableRows.Add(@([string]$seq, $name, '', ''))
        $seq++
    }

    return @($tableRows)
}

function Write-PackageListScopeSection {
    param(
        [Parameter(Mandatory)][string]      $TitleKey,
        [Parameter(Mandatory)]              $SelectedSet,
        [Parameter(Mandatory)][hashtable]   $PackagesDef,
        [string[]]                          $ScoopList,
        $ResolveState,
        [Parameter(Mandatory)][bool]        $GlobalInstall,
        [Parameter(Mandatory)][string]      $NameColKey,
        [Parameter(Mandatory)][int]         $TableWidth
    )

    $namesInScope = [System.Collections.Generic.List[string]]::new()
    foreach ($n in @($SelectedSet)) {
        $name = [string]$n
        $isGlobal = Get-PackageInstallGlobal -PackagesDef $PackagesDef -PackageName $name -State $ResolveState
        if ($isGlobal -eq $GlobalInstall) { [void]$namesInScope.Add($name) }
    }

    if ($namesInScope.Count -eq 0) { return }

    $scopeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $namesInScope) { [void]$scopeSet.Add([string]$n) }

    $scopeScoopApps = Get-ScoopAppsForPackageNames -PackagesDef $PackagesDef -PackageNames @($namesInScope)
    $scopedScoopList = @($ScoopList | Where-Object {
            $app = [string]$_
            if ([string]::IsNullOrWhiteSpace($app)) { return $false }
            $pkgItem = Find-PackageItemByScoopName -PackagesDef $PackagesDef -ScoopName $app
            if ($pkgItem) { return $scopeSet.Contains([string]$pkgItem.Name) }
            return $scopeScoopApps -contains $app
        })
    if ($scopedScoopList.Count -eq 0) { $scopedScoopList = @($scopeScoopApps) }
    $scoopCount = @($scopedScoopList | Where-Object { -not (Test-ScoopAppHiddenInTable -Name $_) }).Count
    if ($scoopCount -eq 0) { $scoopCount = $namesInScope.Count }

    $rows = Build-PackageListTableRows -SelectedSet $scopeSet -PackagesDef $PackagesDef `
        -ScoopList $scopedScoopList -ResolveState $ResolveState
    if ($rows.Count -eq 0) { return }

    $scopedTitleKey = if ($GlobalInstall) { "$TitleKey.global" } else { "$TitleKey.user" }
    Write-Plan (msg $scopedTitleKey $namesInScope.Count $scoopCount)
    Write-PlanBlock -Lines (Format-DisplayTable `
            -Columns (Get-PackageTableColumnsNamed -Rows $rows -NameColKey $NameColKey) `
            -Rows     $rows `
            -TotalWidth $TableWidth)
}

# 按 packages.psd1 分组展示已选安装包（计划摘要 / 已保存配置）
function Write-PackageList {
    param(
        [Parameter(Mandatory)][string]   $TitleKey,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]                       $SelectedNames,
        [string[]]                       $ScoopApps = @(),
        [Parameter(Mandatory)]             $PackagesDef,
        [string[]]                       $PackageGlobal = @(),
        $State = $null
    )

    $selectedSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $SelectedNames) {
        if (-not [string]::IsNullOrWhiteSpace([string]$n)) {
            [void]$selectedSet.Add([string]$n)
        }
    }

    $scoopList = @($ScoopApps | ForEach-Object { [string]$_ } | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and -not (Test-ScoopAppHiddenInTable -Name $_)
        })

    $resolveState = $State
    if ($PackageGlobal.Count -gt 0) {
        $resolveState = @{ Package_Global = @($PackageGlobal) }
    }
    elseif ($null -eq $resolveState) {
        $resolveState = @{}
    }

    $tableWidth = Get-PackageTableWidth

    if ($selectedSet.Count -eq 0) {
        if ($scoopList.Count -eq 0) { return }
        $userApps = [System.Collections.Generic.List[string]]::new()
        $globalApps = [System.Collections.Generic.List[string]]::new()
        foreach ($app in $scoopList) {
            $pkgItem = Find-PackageItemByScoopName -PackagesDef $PackagesDef -ScoopName $app
            $isGlobal = if ($pkgItem) {
                Get-PackageInstallGlobal -PackagesDef $PackagesDef -PackageName ([string]$pkgItem.Name) -State $resolveState
            }
            else { $false }
            if ($isGlobal) { [void]$globalApps.Add($app) }
            else { [void]$userApps.Add($app) }
        }
        if ($userApps.Count -gt 0) {
            Write-Plan (msg "$TitleKey.user" $userApps.Count $userApps.Count)
            $seq = 1
            $rows = [System.Collections.Generic.List[string[]]]::new()
            foreach ($app in $userApps) {
                [void]$rows.Add(@([string]$seq, (Get-ScoopAppBaseName -Name ([string]$app))))
                $seq++
            }
            $rowArr = @($rows)
            $cols = @(
                @{ Header = (msg 'ui.packages.col.no'); Index = 0; FixedWidth = (Get-SeqColumnWidth -RowCount $rows.Count); FirstLineOnly = $true }
                @{ Header = (msg 'ui.packages.col.name.user'); Index = 1; AutoWidth = $true; FirstLineOnly = $true }
            )
            Write-PlanBlock -Lines (Format-DisplayTable -Columns $cols -Rows $rowArr -TotalWidth $tableWidth)
        }
        if ($globalApps.Count -gt 0) {
            Write-Plan (msg "$TitleKey.global" $globalApps.Count $globalApps.Count)
            $seq = 1
            $rows = [System.Collections.Generic.List[string[]]]::new()
            foreach ($app in $globalApps) {
                [void]$rows.Add(@([string]$seq, (Get-ScoopAppBaseName -Name ([string]$app))))
                $seq++
            }
            $rowArr = @($rows)
            $cols = @(
                @{ Header = (msg 'ui.packages.col.no'); Index = 0; FixedWidth = (Get-SeqColumnWidth -RowCount $rows.Count); FirstLineOnly = $true }
                @{ Header = (msg 'ui.packages.col.name.global'); Index = 1; AutoWidth = $true; FirstLineOnly = $true }
            )
            Write-PlanBlock -Lines (Format-DisplayTable -Columns $cols -Rows $rowArr -TotalWidth $tableWidth)
        }
        return
    }

    Write-PackageListScopeSection -TitleKey $TitleKey -SelectedSet $selectedSet `
        -PackagesDef $PackagesDef -ScoopList $scoopList -ResolveState $resolveState `
        -GlobalInstall $false -NameColKey 'ui.packages.col.name.user' -TableWidth $tableWidth
    Write-PackageListScopeSection -TitleKey $TitleKey -SelectedSet $selectedSet `
        -PackagesDef $PackagesDef -ScoopList $scoopList -ResolveState $resolveState `
        -GlobalInstall $true -NameColKey 'ui.packages.col.name.global' -TableWidth $tableWidth
}
