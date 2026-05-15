#Requires -Version 5.1

function Format-PingMonitorFrame {
    <#
        .SYNOPSIS
            Renders a single text frame for Show-PingMonitor (pure formatter, no I/O).

        .DESCRIPTION
            Accepts a snapshot of ping statistics and returns the complete console
            frame as a [string]. Contains no interactive or I/O calls, making it
            fully unit-testable without a live terminal.

        .PARAMETER StatsTable
            Hashtable keyed by hostname. Each value is a hashtable with keys:
            Sent, Received, Lost, LastMs, MinMs, MaxMs, TotalMs, Status.

        .PARAMETER HostList
            Ordered array of hostnames to display.

        .PARAMETER MaxHostLen
            Minimum column width for the HOST column (characters).

        .PARAMETER SortMode
            Active sort column. Valid values: Host, Status, LastMs, Loss.

        .PARAMETER Paused
            When $true, the (PAUSED) indicator is shown in the header.

        .PARAMETER ElapsedStr
            Pre-formatted elapsed time string (HH:MM:SS) to display in header/footer.

        .PARAMETER RefreshInterval
            Refresh interval in seconds displayed in the footer.

        .PARAMETER NoColor
            When set, ANSI escape sequences are suppressed.

        .PARAMETER TerminalHeight
            Number of terminal rows available. Rows beyond the frame content are
            erased with ESC[2K sequences appended to the returned string.

        .OUTPUTS
            System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$StatsTable,

        [Parameter(Mandatory = $true)]
        [string[]]$HostList,

        [Parameter(Mandatory = $true)]
        [int]$MaxHostLen,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Host', 'Status', 'LastMs', 'Loss')]
        [string]$SortMode,

        [Parameter(Mandatory = $true)]
        [bool]$Paused,

        [Parameter(Mandatory = $true)]
        [string]$ElapsedStr,

        [Parameter(Mandatory = $false)]
        [int]$RefreshInterval = 2,

        [Parameter(Mandatory = $false)]
        [switch]$NoColor,

        [Parameter(Mandatory = $false)]
        [int]$TerminalHeight = 24
    )

    $esc      = [char]27
    $useColor = -not $NoColor.IsPresent

    $bold   = if ($useColor) { "${esc}[1m" }  else { '' }
    $dim    = if ($useColor) { "${esc}[90m" } else { '' }
    $reset  = if ($useColor) { "${esc}[0m" }  else { '' }
    $cyan   = if ($useColor) { "${esc}[96m" } else { '' }
    $white  = if ($useColor) { "${esc}[97m" } else { '' }
    $green  = if ($useColor) { "${esc}[92m" } else { '' }
    $red    = if ($useColor) { "${esc}[91m" } else { '' }
    $yellow = if ($useColor) { "${esc}[93m" } else { '' }

    $frameBuilder = [System.Text.StringBuilder]::new(4096)

    # Header
    $pauseLabel = if ($Paused) { " ${yellow}(PAUSED)${reset}" } else { '' }
    [void]$frameBuilder.AppendLine("${bold}${cyan}=== PING MONITOR ===${reset}${pauseLabel}        ${dim}Elapsed: ${ElapsedStr}${reset}")
    [void]$frameBuilder.AppendLine('')

    # Column headers - highlight the active sort column
    $hHost   = if ($SortMode -eq 'Host')   { "${cyan}${bold}" } else { $bold }
    $hStatus = if ($SortMode -eq 'Status') { "${cyan}${bold}" } else { $bold }
    $hLast   = if ($SortMode -eq 'LastMs') { "${cyan}${bold}" } else { $bold }
    $hLoss   = if ($SortMode -eq 'Loss')   { "${cyan}${bold}" } else { $bold }
    $columnLine = "  ${hHost}$('HOST'.PadRight($MaxHostLen))${reset}  ${hStatus}$('STATUS'.PadRight(8))${reset}  ${hLast}$('LAST(ms)'.PadLeft(8))${reset}  ${bold}$('MIN(ms)'.PadLeft(8))${reset}  ${bold}$('MAX(ms)'.PadLeft(8))${reset}  ${bold}$('AVG(ms)'.PadLeft(8))${reset}  ${bold}$('SENT'.PadLeft(6))${reset}  ${bold}$('RECV'.PadLeft(6))${reset}  ${hLoss}$('LOSS'.PadLeft(7))${reset}"
    [void]$frameBuilder.AppendLine($columnLine)
    $sepLine = "  ${dim}$('-' * $MaxHostLen)  $('-' * 8)  $('-' * 8)  $('-' * 8)  $('-' * 8)  $('-' * 8)  $('-' * 6)  $('-' * 6)  $('-' * 7)${reset}"
    [void]$frameBuilder.AppendLine($sepLine)

    # Sort hosts
    $sortedHosts = switch ($SortMode) {
        'Host'   { $HostList | Sort-Object -Property { $_ } }
        'Status' { $HostList | Sort-Object -Property { switch ($StatsTable[$_].Status) { 'Down' { 0 } 'Pending' { 1 } 'Up' { 2 } default { 3 } } } }
        'LastMs' { $HostList | Sort-Object -Property { $StatsTable[$_].LastMs } -Descending }
        'Loss'   { $HostList | Sort-Object -Property { $s = $StatsTable[$_]; if ($s.Sent -gt 0) { $s.Lost / $s.Sent } else { 0 } } -Descending }
    }

    $upCount = 0; $downCount = 0; $pendingCount = 0
    foreach ($displayHost in $sortedHosts) {
        $hostStat = $StatsTable[$displayHost]

        switch ($hostStat.Status) {
            'Up'      { $upCount++ }
            'Down'    { $downCount++ }
            'Pending' { $pendingCount++ }
        }

        $statusColor = switch ($hostStat.Status) {
            'Up'      { $green }
            'Down'    { $red }
            'Pending' { $yellow }
            default   { $reset }
        }

        $hostPad   = $displayHost.PadRight($MaxHostLen)
        $statusPad = $hostStat.Status.PadRight(8)
        $lastMsStr = if ($hostStat.LastMs -ge 0) { $hostStat.LastMs.ToString().PadLeft(8) } else { '--'.PadLeft(8) }
        $minMsStr  = if ($hostStat.MinMs -ne [int]::MaxValue) { $hostStat.MinMs.ToString().PadLeft(8) } else { '--'.PadLeft(8) }
        $maxMsStr  = if ($hostStat.MaxMs -gt 0) { $hostStat.MaxMs.ToString().PadLeft(8) } else { '--'.PadLeft(8) }
        $avgMsStr  = if ($hostStat.Received -gt 0) { ([math]::Round($hostStat.TotalMs / $hostStat.Received, 1)).ToString('0.0').PadLeft(8) } else { '--'.PadLeft(8) }
        $sentStr   = $hostStat.Sent.ToString().PadLeft(6)
        $recvStr   = $hostStat.Received.ToString().PadLeft(6)
        $lossVal   = if ($hostStat.Sent -gt 0) { [math]::Round(($hostStat.Lost / $hostStat.Sent) * 100, 1) } else { [double]0 }
        $lossPad   = ('{0:0.0}%' -f $lossVal).PadLeft(7)

        $lossColor = if ($lossVal -eq 0) { $green } elseif ($lossVal -lt 10) { $yellow } else { $red }

        $row = "  ${white}${hostPad}${reset}  ${statusColor}${statusPad}${reset}  ${lastMsStr}  ${minMsStr}  ${maxMsStr}  ${avgMsStr}  ${sentStr}  ${recvStr}  ${lossColor}${lossPad}${reset}"
        [void]$frameBuilder.AppendLine($row)
    }

    # Summary + footer
    [void]$frameBuilder.AppendLine('')
    [void]$frameBuilder.AppendLine("  ${dim}$($HostList.Count) hosts${reset}  ${dim}|${reset}  ${green}${upCount} Up${reset}  ${dim}|${reset}  ${red}${downCount} Down${reset}  ${dim}|${reset}  ${yellow}${pendingCount} Pending${reset}")
    [void]$frameBuilder.AppendLine('')
    [void]$frameBuilder.AppendLine("  ${bold}[${cyan}Q${reset}${bold}]${reset}uit  ${bold}[${cyan}S${reset}${bold}]${reset}ort  ${bold}[${cyan}C${reset}${bold}]${reset}lear  ${bold}[${cyan}P${reset}${bold}]${reset}ause  ${dim}|${reset}  Refresh: ${yellow}${RefreshInterval}s${reset}  ${dim}|${reset}  Sort: ${yellow}${SortMode}${reset}  ${dim}|${reset}  Elapsed: ${yellow}${ElapsedStr}${reset}")

    # Pad remaining rows with erase sequences
    $currentLines = $frameBuilder.ToString().Split("`n").Count
    for ($r = $currentLines; $r -lt $TerminalHeight; $r++) {
        [void]$frameBuilder.AppendLine("${esc}[2K")
    }

    return $frameBuilder.ToString()
}
