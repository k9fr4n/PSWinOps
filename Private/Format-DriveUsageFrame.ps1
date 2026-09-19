#Requires -Version 5.1

function Format-DriveUsageFrame {
    <#
        .SYNOPSIS
            Renders one text frame for Watch-DriveUsage (pure formatter, no I/O).

        .DESCRIPTION
            Takes a data snapshot of the currently explored path and its immediate
            children and returns the complete console frame as a single [string].
            The function contains no console, CIM, filesystem or network calls, so
            it is fully unit-testable without a live Windows disk. Colour is ANSI
            based and can be suppressed with -NoColor.

            The renderer draws a header (current path, optional drive label, drive
            usage bar, scanning indicator, current file-visibility mode), a width
            and height aware list of rows with a '>' marker on the selected entry,
            an optional one-line status message, and a key bar. Entry objects must
            already be sorted by the caller and are expected to expose Name,
            SizeBytes, FileCount, IsContainer and Inaccessible, exactly as
            Measure-FolderSize emits them. Rows whose IsContainer is false are
            drawn with a [file] marker so loose files stay distinguishable from
            folders in both colour and NoColor modes.

        .PARAMETER CurrentPath
            The path being explored. Shown in the header and truncated with an
            ellipsis when it does not fit the requested width.

        .PARAMETER Entries
            The already-sorted rows to draw. Each object must expose Name
            (string), SizeBytes (long), FileCount (long), IsContainer (bool) and
            Inaccessible (long), matching Measure-FolderSize output.

        .PARAMETER SelectedIndex
            Zero-based index of the highlighted row. Negative values are clamped
            to 0 and values at or beyond the entry count are clamped to the last
            row; an empty entry set renders no marker.

        .PARAMETER DriveLabel
            Optional friendly name of the drive (for example 'Windows') shown next
            to the current path in the header.

        .PARAMETER DriveSizeBytes
            Total size of the current drive in bytes, used for the header usage
            bar. When 0 the header bar is drawn at 0 percent.

        .PARAMETER DriveFreeBytes
            Free bytes on the current drive, subtracted from DriveSizeBytes to
            compute the used percentage shown in the header.

        .PARAMETER TotalBytes
            Denominator for each row percentage. When 0 or absent every row
            percentage is rendered as 0 without dividing by zero.

        .PARAMETER Width
            Terminal width in columns. Defaults to 80 and is floored at 80 so a
            too-narrow request never corrupts the layout.

        .PARAMETER Height
            Terminal height in rows. Limits how many entry rows are shown; the
            selected row is kept visible and a 'more' indicator is emitted when
            rows are hidden.

        .PARAMETER Scanning
            When set, adds a 'Scanning...' indicator to the header so a long scan
            does not look like a hang.

        .PARAMETER StatusMessage
            Optional one-line transient message (for example 'Access denied')
            drawn above the key bar.

        .PARAMETER IncludeFiles
            When set, the header shows the files mode. Loose-file rows are still
            recognised from their IsContainer property alone; this switch only
            advertises the current mode in the header.

        .PARAMETER NoColor
            When set, every ANSI escape sequence is suppressed and the frame is
            returned as plain text.

        .EXAMPLE
            Format-DriveUsageFrame -CurrentPath 'C:\' -Entries $entries -SelectedIndex 0
            Renders a minimal frame for the given already-sorted entries.

        .EXAMPLE
            Format-DriveUsageFrame -CurrentPath 'C:\' -DriveLabel 'Windows' `
                -DriveSizeBytes 1099511627776 -DriveFreeBytes 164926744166 `
                -TotalBytes 1099511627776 -Entries $entries -SelectedIndex 2 `
                -Width 120 -Height 30 -Scanning -StatusMessage 'Rescanning...'
            Renders a full header with drive usage and a transient status line.

        .EXAMPLE
            Format-DriveUsageFrame -CurrentPath 'C:\Windows' -Entries $entries `
                -SelectedIndex 0 -NoColor
            Renders the same frame as plain text with no ANSI escapes, suitable
            for logs or tests.

        .OUTPUTS
            System.String
            One complete console frame as a single string. Nothing is printed.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-09-19
            Requires: PowerShell 5.1+ / Windows only
            Scope: Private - not exported

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CurrentPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Entries,

        [Parameter(Mandatory = $true)]
        [int]$SelectedIndex,

        [Parameter(Mandatory = $false)]
        [string]$DriveLabel = '',

        [Parameter(Mandatory = $false)]
        [long]$DriveSizeBytes = 0,

        [Parameter(Mandatory = $false)]
        [long]$DriveFreeBytes = 0,

        [Parameter(Mandatory = $false)]
        [long]$TotalBytes = 0,

        [Parameter(Mandatory = $false)]
        [int]$Width = 80,

        [Parameter(Mandatory = $false)]
        [int]$Height = 24,

        [Parameter(Mandatory = $false)]
        [switch]$Scanning,

        [Parameter(Mandatory = $false)]
        [string]$StatusMessage = '',

        [Parameter(Mandatory = $false)]
        [switch]$IncludeFiles,

        [Parameter(Mandatory = $false)]
        [switch]$NoColor
    )

    if ($Width -lt 80) { $Width = 80 }
    if ($Height -lt 1) { $Height = 1 }

    $esc      = [char]27
    $useColor = -not $NoColor.IsPresent

    # Strip ANSI CSI SGR sequences before measuring visual length.
    function Get-VisualWidth {
        param([string]$Text)
        ($Text -replace "$([char]27)\[\d+(?:;\d+)*m", '').Length
    }

    # Pad a string (which may contain ANSI escapes) to a target visual width.
    function ConvertTo-PaddedLine {
        param([string]$Text, [int]$TargetWidth)
        $visual = Get-VisualWidth -Text $Text
        $needed = $TargetWidth - $visual
        if ($needed -gt 0) { return $Text + [string]::new(' ', $needed) }
        return $Text
    }

    # Truncate plain text with an ASCII ellipsis, never wrapping.
    function ConvertTo-Truncated {
        param([string]$Text, [int]$MaxWidth)
        if ($null -eq $Text) { $Text = '' }
        if ($MaxWidth -le 0) { return '' }
        if ((Get-VisualWidth -Text $Text) -le $MaxWidth) { return $Text }
        if ($MaxWidth -le 3) { return $Text.Substring(0, $MaxWidth) }
        return $Text.Substring(0, $MaxWidth - 3) + '...'
    }

    # Threshold-based foreground colour: green / yellow / red.
    function Get-ColorCode {
        param([int]$Percent)
        if (-not $useColor) { return '' }
        if ($Percent -gt 80) { return "${esc}[91m" }
        if ($Percent -gt 60) { return "${esc}[93m" }
        return "${esc}[92m"
    }

    # Label colour used for the header percentage.
    function Get-LabelColor {
        param([int]$Percent)
        if (-not $useColor) { return '' }
        if ($Percent -gt 80) { return "${esc}[91m" }
        if ($Percent -gt 60) { return "${esc}[93m" }
        return "${esc}[96m"
    }

    # Render a filled/empty block bar with threshold colour.
    function Format-Bar {
        param([int]$Percent, [int]$BarWidth)
        if ($Percent -lt 0) { $Percent = 0 }
        if ($Percent -gt 100) { $Percent = 100 }
        if ($BarWidth -lt 1) { $BarWidth = 1 }
        $filled    = [int][math]::Max(0, [math]::Round($BarWidth * $Percent / 100))
        $empty     = $BarWidth - $filled
        $color     = Get-ColorCode -Percent $Percent
        $dimCode   = if ($useColor) { "${esc}[90m" } else { '' }
        $resetCode = if ($useColor) { "${esc}[0m" }  else { '' }
        $filledStr = [string]::new([char]0x2588, $filled)
        $emptyStr  = [string]::new([char]0x2591, $empty)
        "${color}${filledStr}${dimCode}${emptyStr}${resetCode}"
    }

    # Human-readable size (bytes in -> B/KB/MB/GB/TB, decimals only when needed).
    function Format-Size {
        param([double]$Bytes)
        if ($Bytes -lt 0) { $Bytes = 0 }
        if ($Bytes -lt 1024) { return '{0:N0} B' -f $Bytes }

        $units = @('KB', 'MB', 'GB', 'TB')
        $value = $Bytes / 1024
        foreach ($unit in $units) {
            if ($value -lt 1024 -or $unit -eq 'TB') {
                $rounded = [math]::Round($value, 1)
                if ($rounded -eq [math]::Floor($rounded)) {
                    return '{0:N0} {1}' -f $value, $unit
                }
                return '{0:N1} {1}' -f $value, $unit
            }
            $value = $value / 1024
        }
    }

    # Build one entry row with the selection marker and per-row percentage.
    function Format-EntryRow {
        param($Entry, [int]$Index, [long]$TotalBytes)
        $isSelected = ($Index -eq $selIndex)

        $namePlain = if ($null -eq $Entry.Name) { '' } else { [string]$Entry.Name }

        $isFile = $false
        if ($null -ne $Entry.IsContainer -and -not [bool]$Entry.IsContainer) {
            $isFile = $true
        }

        # A literal marker keeps files distinguishable even with -NoColor; colour
        # mode additionally dims the whole name below. Reserve its width first so
        # the truncated name plus marker never overflows the name column.
        $fileMarker = if ($isFile) { ' [file]' } else { '' }
        $nameMax    = [math]::Max(1, $nameWidth - $fileMarker.Length)
        $nameText   = ConvertTo-Truncated -Text $namePlain -MaxWidth $nameMax
        $nameText   = $nameText + $fileMarker
        $namePadded = $nameText.PadRight($nameWidth)

        $sizeBytes = [double]0
        if ($null -ne $Entry.SizeBytes) { $sizeBytes = [double]$Entry.SizeBytes }
        $sizeText = (Format-Size -Bytes $sizeBytes).PadLeft(9)

        $pctValue = [double]0
        if ($TotalBytes -gt 0) {
            $pctValue = [math]::Min(100.0, [math]::Max(0.0, $sizeBytes * 100.0 / $TotalBytes))
        }
        $pctText = ('{0:N1}%' -f $pctValue).PadLeft(6)

        $fileCount = [long]0
        if ($null -ne $Entry.FileCount) { $fileCount = [long]$Entry.FileCount }
        $countText = ('{0:N0} files' -f $fileCount).PadLeft($countWidth)

        $inaccessible = [long]0
        if ($null -ne $Entry.Inaccessible) { $inaccessible = [long]$Entry.Inaccessible }
        $flagText = if ($inaccessible -gt 0) {
            if ($useColor) { " ${red}!${reset}" } else { ' !' }
        }
        else {
            '  '
        }

        $bar     = Format-Bar -Percent ([int][math]::Round($pctValue)) -BarWidth $rowBarWidth
        $barText = "[${bar}]"

        $marker = if ($isSelected) { '>' } else { ' ' }
        if ($isSelected -and $useColor) { $marker = "${yellow}${marker}${reset}" }

        if ($isSelected -and $useColor) {
            $nameStr = "${bold}${white}${bgSel}${namePadded}${reset}"
        }
        elseif ($isFile -and $useColor) {
            $nameStr = "${dim}${namePadded}${reset}"
        }
        elseif ($useColor) {
            $nameStr = "${white}${namePadded}${reset}"
        }
        else {
            $nameStr = $namePadded
        }

        $row = '  ' + $marker + ' ' + $nameStr + '  ' + $sizeText + '  ' + $pctText +
               '  ' + $barText + '  ' + $countText + $flagText
        return ConvertTo-PaddedLine -Text $row -TargetWidth $Width
    }

    # Static ANSI codes (empty when colour is disabled).
    $dim    = if ($useColor) { "${esc}[90m" }        else { '' }
    $reset  = if ($useColor) { "${esc}[0m" }         else { '' }
    $bold   = if ($useColor) { "${esc}[1m" }         else { '' }
    $cyan   = if ($useColor) { "${esc}[96m" }        else { '' }
    $white  = if ($useColor) { "${esc}[97m" }        else { '' }
    $yellow = if ($useColor) { "${esc}[93m" }        else { '' }
    $red    = if ($useColor) { "${esc}[91m" }        else { '' }
    $bgSel  = if ($useColor) { "${esc}[48;5;235m" }  else { '' }

    # Normalise input and clamp the selection to a valid row.
    if ($null -eq $Entries) { $Entries = @() }
    $entryCount = @($Entries).Count

    $selIndex = $SelectedIndex
    if ($entryCount -gt 0) {
        if ($selIndex -lt 0) { $selIndex = 0 }
        if ($selIndex -ge $entryCount) { $selIndex = $entryCount - 1 }
    }
    else {
        $selIndex = -1
    }

    # Drive usage figures for the header.
    $usedPercent = 0
    $usedBytes   = [long]0
    if ($DriveSizeBytes -gt 0) {
        $usedBytes = [long]$DriveSizeBytes - [long]$DriveFreeBytes
        if ($usedBytes -lt 0) { $usedBytes = 0 }
        if ($usedBytes -gt $DriveSizeBytes) { $usedBytes = $DriveSizeBytes }
        $usedPercent = [int][math]::Min(100, [math]::Max(0, [math]::Round($usedBytes * 100.0 / $DriveSizeBytes)))
    }

    # Bar and column sizing (name column absorbs whatever the fixed chrome leaves).
    $headerBarWidth = [int][math]::Min(40, [math]::Max(8, $Width - 6))
    $rowBarWidth    = [int][math]::Max(8, [math]::Min(30, [math]::Floor(($Width - 50) / 2)))

    $countWidth = 13
    if ($entryCount -gt 0) {
        foreach ($e in $Entries) {
            $t = '{0:N0} files' -f [long]$e.FileCount
            if ($t.Length -gt $countWidth) { $countWidth = $t.Length }
        }
    }
    $nameWidth = [math]::Max(6, $Width - 31 - $rowBarWidth - $countWidth)

    $lines     = [System.Collections.Generic.List[string]]::new([math]::Max(16, $Height + 4))
    $blankLine = [string]::new(' ', $Width)

    # ---- Header ----
    $leftPlain = $CurrentPath
    if (-not [string]::IsNullOrWhiteSpace($DriveLabel)) {
        $leftPlain = "${CurrentPath}  ${DriveLabel}"
    }

    $rightPlain = ''
    if ($DriveSizeBytes -gt 0) {
        $usedStr   = Format-Size -Bytes ([double]$usedBytes)
        $totalStr  = Format-Size -Bytes ([double]$DriveSizeBytes)
        $rightPlain = '{0} / {1}  {2,3}% used' -f $usedStr, $totalStr, $usedPercent
    }
    if ($Scanning) {
        if ($rightPlain) { $rightPlain += '   ' }
        $rightPlain += 'Scanning...'
    }

    $modePlain = if ($IncludeFiles) { 'Files' } else { 'Folders' }
    if ($rightPlain) { $rightPlain += '   ' }
    $rightPlain += $modePlain

    $rightVisual = if ($rightPlain) { Get-VisualWidth -Text $rightPlain } else { 0 }
    $maxLeft     = $Width - $rightVisual - 1
    if ($maxLeft -lt 3) { $maxLeft = 3 }
    $leftPlain   = ConvertTo-Truncated -Text $leftPlain -MaxWidth $maxLeft
    $leftVisual  = Get-VisualWidth -Text $leftPlain
    $pad         = $Width - $leftVisual - $rightVisual
    if ($pad -lt 1) { $pad = 1 }

    $coloredLeft  = if ($useColor) { "${bold}${cyan}${leftPlain}${reset}" } else { $leftPlain }
    $coloredRight = if ($rightPlain) {
        if ($useColor) { "${dim}${rightPlain}${reset}" } else { $rightPlain }
    }
    else {
        ''
    }
    $lines.Add((ConvertTo-PaddedLine -Text ($coloredLeft + (' ' * $pad) + $coloredRight) -TargetWidth $Width))

    $headerBar = Format-Bar -Percent $usedPercent -BarWidth $headerBarWidth
    $lines.Add((ConvertTo-PaddedLine -Text ("[${headerBar}]") -TargetWidth $Width))
    $lines.Add($blankLine)

    # ---- Entry rows, height aware ----
    $statusPresent  = -not [string]::IsNullOrWhiteSpace($StatusMessage)
    $chrome         = if ($statusPresent) { 6 } else { 5 }
    $availableRows  = [math]::Max(0, $Height - $chrome)

    if ($entryCount -eq 0) {
        $emptyLine = '  ' + $(if ($useColor) { "${dim}<empty>${reset}" } else { '<empty>' })
        $lines.Add((ConvertTo-PaddedLine -Text $emptyLine -TargetWidth $Width))
    }
    else {
        $showCount = $entryCount
        $start     = 0
        $showMore  = $false
        $hidden    = 0

        if ($entryCount -gt $availableRows) {
            $showMore  = $true
            $showCount = [math]::Max(0, $availableRows - 1)
            if ($showCount -gt 0) {
                $start = 0
                if ($selIndex -ge $showCount) { $start = $selIndex - $showCount + 1 }
                if ($start -lt 0) { $start = 0 }
                if ($start + $showCount -gt $entryCount) { $start = $entryCount - $showCount }
                $hidden = $entryCount - $showCount
            }
            else {
                $hidden = $entryCount
            }
        }

        for ($i = $start; $i -lt ($start + $showCount); $i++) {
            $lines.Add((Format-EntryRow -Entry $Entries[$i] -Index $i -TotalBytes $TotalBytes))
        }

        if ($showMore) {
            $moreLine = '  ' + $(if ($useColor) { "${dim}... ${hidden} more${reset}" } else { "... ${hidden} more" })
            $lines.Add((ConvertTo-PaddedLine -Text $moreLine -TargetWidth $Width))
        }
    }

    # ---- Footer ----
    $lines.Add($blankLine)
    if ($statusPresent) {
        $statusLine = if ($useColor) { "${yellow}${StatusMessage}${reset}" } else { $StatusMessage }
        $lines.Add((ConvertTo-PaddedLine -Text $statusLine -TargetWidth $Width))
    }

    $keyBar = '[Enter] Open   [Backspace] Parent   [F] Files   [R] Refresh   [Q] Quit'
    $lines.Add((ConvertTo-PaddedLine -Text $keyBar -TargetWidth $Width))

    return ($lines -join ([Environment]::NewLine))
}
