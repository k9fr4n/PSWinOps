#Requires -Version 5.1

function Format-NetworkStatisticMonitorFrame {
    <#
        .SYNOPSIS
            Renders a single text frame for Show-NetworkStatisticMonitor (pure formatter, no I/O).

        .DESCRIPTION
            Accepts a pre-sorted snapshot of network connection objects and returns the
            complete console frame as a [string]. Contains no interactive or I/O calls,
            making it fully unit-testable without a live terminal or network stack.

        .PARAMETER SortedConnections
            Array of connection objects (already sorted) with properties:
            Protocol, LocalAddress, LocalPort, RemoteAddress, RemotePort, State, ProcessName.

        .PARAMETER ComputerList
            Display string of monitored computers (e.g. "SRV01, SRV02").

        .PARAMETER CurrentSortMode
            Active sort column. Valid values: Process, Protocol, State, LocalPort, RemoteAddr.

        .PARAMETER SortDescending
            When $true, the descending sort indicator is shown next to the sort column.

        .PARAMETER Paused
            When $true, the (PAUSED) indicator is shown in the header.

        .PARAMETER TimeStr
            Pre-formatted timestamp string to display in the header.

        .PARAMETER Width
            Terminal width in columns used for line padding.

        .PARAMETER Height
            Terminal height in rows used for available data rows and trailing erase.

        .PARAMETER RefreshInterval
            Refresh interval in seconds displayed in the footer.

        .PARAMETER NoColor
            When set, ANSI escape sequences are suppressed.

        .OUTPUTS
            System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $false)]
        [object[]]$SortedConnections = @(),

        [Parameter(Mandatory = $true)]
        [string]$ComputerList,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Process', 'Protocol', 'State', 'LocalPort', 'RemoteAddr')]
        [string]$CurrentSortMode,

        [Parameter(Mandatory = $false)]
        [bool]$SortDescending = $false,

        [Parameter(Mandatory = $false)]
        [bool]$Paused = $false,

        [Parameter(Mandatory = $true)]
        [string]$TimeStr,

        [Parameter(Mandatory = $false)]
        [int]$Width = 80,

        [Parameter(Mandatory = $false)]
        [int]$Height = 24,

        [Parameter(Mandatory = $false)]
        [int]$RefreshInterval = 2,

        [Parameter(Mandatory = $false)]
        [switch]$NoColor
    )

    $esc      = [char]27
    $useColor = -not $NoColor.IsPresent

    $dim       = if ($useColor) { "${esc}[90m" }  else { '' }
    $reset     = if ($useColor) { "${esc}[0m" }   else { '' }
    $bold      = if ($useColor) { "${esc}[1m" }   else { '' }
    $cyan      = if ($useColor) { "${esc}[96m" }  else { '' }
    $white     = if ($useColor) { "${esc}[97m" }  else { '' }
    $yellow    = if ($useColor) { "${esc}[93m" }  else { '' }
    $green     = if ($useColor) { "${esc}[92m" }  else { '' }
    $red       = if ($useColor) { "${esc}[91m" }  else { '' }
    $underline = if ($useColor) { "${esc}[4m" }   else { '' }

    function Get-VisualWidth {
        param([string]$Text)
        ($Text -replace "$([char]27)\[\d+(?:;\d+)*m", '').Length
    }

    function ConvertTo-PaddedLine {
        param([string]$Text, [int]$TargetWidth)
        $visual = Get-VisualWidth -Text $Text
        $needed = $TargetWidth - $visual
        if ($needed -gt 0) { return $Text + [string]::new(' ', $needed) }
        return $Text
    }

    function Get-ProtocolColor {
        param([string]$Proto)
        if (-not $useColor) { return '' }
        if ($Proto -eq 'TCP') { return $cyan }
        if ($Proto -eq 'UDP') { return $yellow }
        return ''
    }

    function Get-StateColor {
        param([string]$ConnState)
        if (-not $useColor) { return '' }
        switch ($ConnState) {
            'Established' { return $green }
            'Listen'      { return "${white}${bold}" }
            'TimeWait'    { return $dim }
            'CloseWait'   { return $red }
            'Closing'     { return $red }
            'LastAck'     { return $red }
            default       { return '' }
        }
    }

    $connectionCount = if ($null -eq $SortedConnections) { 0 } else { $SortedConnections.Count }

    $frame     = [System.Text.StringBuilder]::new(4096)
    $lineCount = 0
    $separator = [string]::new('-', [math]::Min($Width - 4, 120))

    # Header
    $pauseIndicator = if ($Paused) { " ${red}${bold}(PAUSED)${reset}" } else { '' }
    $headerLine = "  ${bold}${cyan}Network Monitor${reset} ${dim}-${reset} ${bold}${white}${ComputerList}${reset}${pauseIndicator} ${dim}|${reset} ${dim}${TimeStr}${reset}"
    [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $headerLine -TargetWidth $Width))
    $lineCount++
    [void]$frame.AppendLine((ConvertTo-PaddedLine -Text "  ${dim}${separator}${reset}" -TargetWidth $Width))
    $lineCount++

    # Column widths
    $colProto = 7; $colLAddr = 23; $colLPort = 12
    $colRAddr = 23; $colRPort = 13; $colState = 14

    # Sort direction arrow
    $sortArrow = if ($SortDescending) {
        if ($useColor) { "${cyan}v${reset}" } else { 'v' }
    } else {
        if ($useColor) { "${cyan}^${reset}" } else { '^' }
    }

    # Table header with active sort highlighted
    $protoH = if ($CurrentSortMode -eq 'Protocol')   { "${cyan}${underline}PROTO${reset}" }          else { "${dim}PROTO${reset}" }
    $lAddrH = "${dim}LOCAL ADDRESS${reset}"
    $lPortH = if ($CurrentSortMode -eq 'LocalPort')  { "${cyan}${underline}LOCAL PORT${reset}" }     else { "${dim}LOCAL PORT${reset}" }
    $rAddrH = if ($CurrentSortMode -eq 'RemoteAddr') { "${cyan}${underline}REMOTE ADDRESS${reset}" } else { "${dim}REMOTE ADDRESS${reset}" }
    $rPortH = "${dim}REMOTE PORT${reset}"
    $stateH = if ($CurrentSortMode -eq 'State')      { "${cyan}${underline}STATE${reset}" }          else { "${dim}STATE${reset}" }
    $procH  = if ($CurrentSortMode -eq 'Process')    { "${cyan}${underline}PROCESS${reset}" }        else { "${dim}PROCESS${reset}" }

    $headerRow = '  {0}{1}{2}{3}{4}{5}{6}' -f `
        (ConvertTo-PaddedLine -Text $protoH -TargetWidth $colProto),
        (ConvertTo-PaddedLine -Text $lAddrH -TargetWidth $colLAddr),
        (ConvertTo-PaddedLine -Text $lPortH -TargetWidth $colLPort),
        (ConvertTo-PaddedLine -Text $rAddrH -TargetWidth $colRAddr),
        (ConvertTo-PaddedLine -Text $rPortH -TargetWidth $colRPort),
        (ConvertTo-PaddedLine -Text $stateH -TargetWidth $colState),
        $procH
    [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $headerRow -TargetWidth $Width))
    $lineCount++

    $dashRow = "  ${dim}{0}{1}{2}{3}{4}{5}{6}${reset}" -f `
        ('{0,-7}'  -f '-----'),
        ('{0,-23}' -f '-------------'),
        ('{0,-12}' -f '----------'),
        ('{0,-23}' -f '--------------'),
        ('{0,-13}' -f '-----------'),
        ('{0,-14}' -f '-----'),
        '-------'
    [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $dashRow -TargetWidth $Width))
    $lineCount++

    # Data rows
    $availableRows = $Height - $lineCount - 4
    if ($connectionCount -gt 0) {
        $displayCount = [math]::Min($connectionCount, [math]::Max(5, $availableRows))
        for ($i = 0; $i -lt $displayCount; $i++) {
            $conn       = $SortedConnections[$i]
            $protoColor = Get-ProtocolColor -Proto $conn.Protocol
            $stateColor = Get-StateColor -ConnState $conn.State

            $dataRow = '  {0}  {1}  {2}  {3}  {4}  {5}  {6}' -f `
                "${protoColor}$('{0,-5}' -f $conn.Protocol)${reset}",
                ('{0,-21}' -f $conn.LocalAddress),
                ('{0,-10}' -f $conn.LocalPort),
                ('{0,-21}' -f $conn.RemoteAddress),
                ('{0,-11}' -f $conn.RemotePort),
                "${stateColor}$('{0,-12}' -f $conn.State)${reset}",
                "${white}$($conn.ProcessName)${reset}"

            [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $dataRow -TargetWidth $Width))
            $lineCount++
        }
    }
    else {
        [void]$frame.AppendLine((ConvertTo-PaddedLine -Text "  ${yellow}(No matching connections found)${reset}" -TargetWidth $Width))
        $lineCount++
    }

    # Footer
    [void]$frame.AppendLine('')
    $lineCount++
    [void]$frame.AppendLine((ConvertTo-PaddedLine -Text "  ${dim}${separator}${reset}" -TargetWidth $Width))
    $lineCount++

    $footerLine = "  ${bold}[${cyan}Q${reset}${bold}]${reset}uit  ${bold}[${cyan}S${reset}${bold}]${reset}ort  ${bold}[${cyan}R${reset}${bold}]${reset}everse  ${bold}[${cyan}P${reset}${bold}]${reset}ause  ${dim}|${reset}  Refresh: ${yellow}${RefreshInterval}s${reset}  ${dim}|${reset}  Sort: ${cyan}${bold}${CurrentSortMode}${reset} ${sortArrow}  ${dim}|${reset}  Connections: ${white}${connectionCount}${reset}"
    [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $footerLine -TargetWidth $Width))
    $lineCount++

    # Erase trailing lines
    $remainingRows = $Height - $lineCount
    for ($r = 0; $r -lt $remainingRows; $r++) {
        [void]$frame.AppendLine("${esc}[2K")
    }

    return $frame.ToString()
}
