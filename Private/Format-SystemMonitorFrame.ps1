#Requires -Version 5.1

function Format-SystemMonitorFrame {
    <#
        .SYNOPSIS
            Renders a single text frame for Show-SystemMonitor (pure formatter, no I/O).

        .DESCRIPTION
            Accepts a snapshot of system metrics and returns the complete console
            frame as a [string]. Contains no interactive, I/O, or CIM calls, making it
            fully unit-testable without a live Windows system.

        .PARAMETER CpuTotalPercent
            Overall CPU utilisation percentage (0-100).

        .PARAMETER CpuCores
            Array of objects with properties Name (string) and PercentProcessorTime (int),
            one per logical processor. Accepts CimInstance or PSCustomObject.

        .PARAMETER MemPercent
            Physical memory utilisation percentage (0-100).

        .PARAMETER MemUsedKB
            Used physical memory in kilobytes.

        .PARAMETER MemTotalKB
            Total physical memory in kilobytes.

        .PARAMETER PagePercent
            Page file utilisation percentage (0-100).

        .PARAMETER PageUsedKB
            Used page file in kilobytes.

        .PARAMETER PageTotalKB
            Total page file size in kilobytes.

        .PARAMETER UptimeStr
            Pre-formatted uptime string (e.g. "3d 02:15:44").

        .PARAMETER TimeStr
            Pre-formatted timestamp string (e.g. "2026-05-14 20:00:00").

        .PARAMETER ProcessCount
            Total number of running processes shown in the header.

        .PARAMETER TopProcesses
            Array of objects with properties PID (int), CPU (double), MemMB (double),
            Name (string), already sorted and pre-capped to the display limit.

        .PARAMETER SortMode
            Active sort column shown in the footer. Valid values: CPU, Memory, PID, Name.

        .PARAMETER Width
            Terminal width in columns used for bar sizing and line padding.

        .PARAMETER Height
            Terminal height in rows used for process list truncation and trailing erase.

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
        [int]$CpuTotalPercent = 0,

        [Parameter(Mandatory = $false)]
        [object[]]$CpuCores = @(),

        [Parameter(Mandatory = $false)]
        [int]$MemPercent = 0,

        [Parameter(Mandatory = $false)]
        [double]$MemUsedKB = 0,

        [Parameter(Mandatory = $false)]
        [double]$MemTotalKB = 1,

        [Parameter(Mandatory = $false)]
        [int]$PagePercent = 0,

        [Parameter(Mandatory = $false)]
        [double]$PageUsedKB = 0,

        [Parameter(Mandatory = $false)]
        [double]$PageTotalKB = 1,

        [Parameter(Mandatory = $false)]
        [string]$UptimeStr = '0d 00:00:00',

        [Parameter(Mandatory = $false)]
        [string]$TimeStr = '',

        [Parameter(Mandatory = $false)]
        [int]$ProcessCount = 0,

        [Parameter(Mandatory = $false)]
        [object[]]$TopProcesses = @(),

        [Parameter(Mandatory = $false)]
        [ValidateSet('CPU', 'Memory', 'PID', 'Name')]
        [string]$SortMode = 'CPU',

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

    # Threshold-based fg color: green / yellow / red
    function Get-ColorCode {
        param([int]$Percent)
        if (-not $useColor) { return '' }
        if ($Percent -gt 80) { return "${esc}[91m" }
        if ($Percent -gt 60) { return "${esc}[93m" }
        return "${esc}[92m"
    }

    # Label color: cyan at normal load, yellow at warning, red at critical
    function Get-LabelColor {
        param([int]$Percent)
        if (-not $useColor) { return '' }
        if ($Percent -gt 80) { return "${esc}[91m" }
        if ($Percent -gt 60) { return "${esc}[93m" }
        return "${esc}[96m"
    }

    # Strip ANSI CSI SGR sequences before measuring visual length
    function Get-VisualWidth {
        param([string]$Text)
        ($Text -replace "$([char]27)\[\d+(?:;\d+)*m", '').Length
    }

    # Pad a string (which may contain ANSI escapes) to a target visual width
    function ConvertTo-PaddedLine {
        param([string]$Text, [int]$TargetWidth)
        $visual = Get-VisualWidth -Text $Text
        $needed = $TargetWidth - $visual
        if ($needed -gt 0) { return $Text + [string]::new(' ', $needed) }
        return $Text
    }

    # Render a filled/empty block bar with threshold color
    function Format-Bar {
        param([int]$Percent, [int]$BarWidth)
        if ($Percent -lt 0)   { $Percent = 0 }
        if ($Percent -gt 100) { $Percent = 100 }
        $filled    = [math]::Max(0, [math]::Round($BarWidth * $Percent / 100))
        $empty     = $BarWidth - $filled
        $color     = Get-ColorCode -Percent $Percent
        $dimCode   = if ($useColor) { "${esc}[90m" } else { '' }
        $resetCode = if ($useColor) { "${esc}[0m" }  else { '' }
        $filledStr = [string]::new([char]0x2588, $filled)
        $emptyStr  = [string]::new([char]0x2591, $empty)
        "${color}${filledStr}${dimCode}${emptyStr}${resetCode}"
    }

    # Human-readable size (KB input -> K/M/G output)
    function Format-Size {
        param([double]$SizeKB)
        if ($SizeKB -ge 1048576) { return '{0:N1}G' -f ($SizeKB / 1048576) }
        if ($SizeKB -ge 1024)    { return '{0:N0}M' -f ($SizeKB / 1024) }
        return '{0:N0}K' -f $SizeKB
    }

    # Colored "used / total" ratio line
    function Format-MemRatio {
        param([string]$Used, [string]$Total, [int]$Percent)
        $color     = Get-LabelColor -Percent $Percent
        $dimCode   = if ($useColor) { "${esc}[90m" } else { '' }
        $resetCode = if ($useColor) { "${esc}[0m" }  else { '' }
        $whiteCode = if ($useColor) { "${esc}[97m" } else { '' }
        "${color}${Used}${resetCode} ${dimCode}/${resetCode} ${whiteCode}${Total}${resetCode}"
    }

    # Static ANSI codes
    $dim       = if ($useColor) { "${esc}[90m" }         else { '' }
    $reset     = if ($useColor) { "${esc}[0m" }          else { '' }
    $bold      = if ($useColor) { "${esc}[1m" }          else { '' }
    $cyan      = if ($useColor) { "${esc}[96m" }         else { '' }
    $white     = if ($useColor) { "${esc}[97m" }         else { '' }
    $underline = if ($useColor) { "${esc}[4m" }          else { '' }
    $yellow    = if ($useColor) { "${esc}[93m" }         else { '' }
    $magenta   = if ($useColor) { "${esc}[95m" }         else { '' }
    $bgDimRow  = if ($useColor) { "${esc}[48;5;235m" }   else { '' }
    $fgHot     = if ($useColor) { "${esc}[97m${esc}[1m" } else { '' }

    $coreCount = if ($null -eq $CpuCores -or $CpuCores.Count -eq 0) { 1 } else { $CpuCores.Count }

    $lines     = [System.Collections.Generic.List[string]]::new(64)
    $separator = [string]::new([char]0x2500, [math]::Max(1, $Width - 4))

    # ---- Header ----
    $lines.Add("  ${bold}${cyan}Show-SystemMonitor${reset} ${dim}-${reset} ${bold}${white}${env:COMPUTERNAME}${reset} ${dim}|${reset} Up: ${yellow}${UptimeStr}${reset} ${dim}|${reset} ${dim}${TimeStr}${reset} ${dim}|${reset} Procs: ${white}${ProcessCount}${reset}")
    $lines.Add("  ${dim}${separator}${reset}")

    # ---- Summary bars (CPU / Mem / Swap) ----
    $barWidth = [math]::Min(40, [math]::Max(1, $Width - 30))

    $cpuLabelColor = Get-LabelColor -Percent $CpuTotalPercent
    $cpuBar        = Format-Bar -Percent $CpuTotalPercent -BarWidth $barWidth
    $cpuPctStr     = '{0,5:N1}' -f $CpuTotalPercent
    $lines.Add("  ${cpuLabelColor}${bold}CPU${reset}  [${cpuBar}] ${cpuPctStr}%    Cores: ${white}${coreCount}${reset}")

    $memLabelColor = Get-LabelColor -Percent $MemPercent
    $memBar        = Format-Bar -Percent $MemPercent -BarWidth $barWidth
    $memPctStr     = '{0,5:N1}' -f $MemPercent
    $safeMemTotal  = if ($MemTotalKB -le 0) { 1 } else { $MemTotalKB }
    $memRatio      = Format-MemRatio -Used (Format-Size $MemUsedKB) -Total (Format-Size $safeMemTotal) -Percent $MemPercent
    $lines.Add("  ${memLabelColor}${bold}Mem${reset}  [${memBar}] ${memPctStr}%    ${memRatio}")

    $pageLabelColor = Get-LabelColor -Percent $PagePercent
    $pageBar        = Format-Bar -Percent $PagePercent -BarWidth $barWidth
    $pagePctStr     = '{0,5:N1}' -f $PagePercent
    $safePageTotal  = if ($PageTotalKB -le 0) { 1 } else { $PageTotalKB }
    $pageRatio      = Format-MemRatio -Used (Format-Size $PageUsedKB) -Total (Format-Size $safePageTotal) -Percent $PagePercent
    $lines.Add("  ${pageLabelColor}${bold}Swp${reset}  [${pageBar}] ${pagePctStr}%    ${pageRatio}")
    $lines.Add('')

    # ---- Per-core CPU bars (2 columns) ----
    $coreBarWidth       = [math]::Min(20, [math]::Max(1, [math]::Floor(($Width - 30) / 2)))
    $coreColVisualWidth = $coreBarWidth + 14

    if ($null -ne $CpuCores -and $CpuCores.Count -gt 0) {
        for ($i = 0; $i -lt $CpuCores.Count; $i += 2) {
            $pct          = [math]::Max(0, [math]::Min(100, [int]$CpuCores[$i].PercentProcessorTime))
            $bar          = Format-Bar -Percent $pct -BarWidth $coreBarWidth
            $coreNumColor = Get-ColorCode -Percent $pct
            $coreLabel    = '{0,3}' -f $CpuCores[$i].Name
            $pctStr       = '{0,3}' -f $pct
            $leftCol      = "${coreNumColor}${coreLabel}${reset} [${bar}] ${pctStr}%"

            if ($i + 1 -lt $CpuCores.Count) {
                $leftPadded    = ConvertTo-PaddedLine -Text $leftCol -TargetWidth $coreColVisualWidth
                $pct2          = [math]::Max(0, [math]::Min(100, [int]$CpuCores[$i + 1].PercentProcessorTime))
                $bar2          = Format-Bar -Percent $pct2 -BarWidth $coreBarWidth
                $coreNumColor2 = Get-ColorCode -Percent $pct2
                $coreLabel2    = '{0,3}' -f $CpuCores[$i + 1].Name
                $pct2Str       = '{0,3}' -f $pct2
                $rightCol      = "${coreNumColor2}${coreLabel2}${reset} [${bar2}] ${pct2Str}%"
                $lines.Add("  ${leftPadded}    ${rightCol}")
            }
            else {
                $lines.Add("  ${leftCol}")
            }
        }
    }
    $lines.Add("  ${dim}${separator}${reset}")

    # ---- Process table header ----
    $pidH  = if ($SortMode -eq 'PID')    { "${cyan}${underline}PID${reset}" }     else { "${dim}PID${reset}" }
    $cpuH  = if ($SortMode -eq 'CPU')    { "${cyan}${underline}CPU%${reset}" }    else { "${dim}CPU%${reset}" }
    $memH  = if ($SortMode -eq 'Memory') { "${cyan}${underline}MEM(MB)${reset}" } else { "${dim}MEM(MB)${reset}" }
    $nameH = if ($SortMode -eq 'Name')   { "${cyan}${underline}Name${reset}" }    else { "${dim}Name${reset}" }
    $lines.Add("  ${bold}  ${pidH}   ${cpuH}   ${memH}   ${nameH}${reset}")

    # ---- Process rows ----
    $availableRows = $Height - $lines.Count - 3
    $displayCount  = if ($null -eq $TopProcesses -or $TopProcesses.Count -eq 0) {
        0
    }
    else {
        [math]::Min($TopProcesses.Count, [math]::Max(5, $availableRows))
    }

    for ($i = 0; $i -lt $displayCount; $i++) {
        $p        = $TopProcesses[$i]
        $cpuColor = Get-ColorCode -Percent ([math]::Min(100, [math]::Max(0, [int]($p.CPU * 2))))
        $pidStr   = '{0,7}' -f $p.PID
        $cpuStr   = '{0,7:N1}' -f $p.CPU
        $memStr   = '{0,9:N1}' -f $p.MemMB

        $rowBg    = if ($useColor -and ($i % 2 -eq 1)) { $bgDimRow } else { '' }
        $rowReset = if ($useColor -and ($i % 2 -eq 1)) { $reset }    else { '' }

        $nameColor = if ($i -eq 0 -and $p.CPU -gt 0) { $magenta } elseif ($p.CPU -gt 50) { $fgHot } else { $white }
        $lines.Add("${rowBg}  ${pidStr} ${cpuColor}${cpuStr}${reset}${rowBg} ${memStr}   ${nameColor}$($p.Name)${rowReset}${reset}")
    }

    # ---- Footer ----
    $lines.Add('')
    $lines.Add("  ${dim}${separator}${reset}")
    $lines.Add("  ${bold}[${cyan}Q${reset}${bold}]${reset}uit  ${bold}[${cyan}C${reset}${bold}]${reset}PU  ${bold}[${cyan}M${reset}${bold}]${reset}em  ${bold}[${cyan}P${reset}${bold}]${reset}ID  ${bold}[${cyan}N${reset}${bold}]${reset}ame  ${dim}|${reset}  Refresh: ${yellow}${RefreshInterval}s${reset}  ${dim}|${reset}  Sort: ${cyan}${bold}${SortMode}${reset}")

    # ---- Single write buffer: cursor home + padded lines + erase tail ----
    $frame = [System.Text.StringBuilder]::new($lines.Count * ($Width + 20))
    [void]$frame.Append("${esc}[H")

    foreach ($line in $lines) {
        $padded = ConvertTo-PaddedLine -Text $line -TargetWidth $Width
        [void]$frame.AppendLine($padded)
    }

    $remainingRows = $Height - $lines.Count
    for ($r = 0; $r -lt $remainingRows; $r++) {
        [void]$frame.AppendLine("${esc}[2K")
    }

    return $frame.ToString()
}
