#Requires -Version 5.1

function Show-SystemMonitor {
    <#
    .SYNOPSIS
        Displays an interactive real-time system monitor inspired by htop

    .DESCRIPTION
        Renders a full-screen terminal UI showing per-core CPU usage bars, memory
        and page file utilization, and a sortable process list refreshed at a
        configurable interval. Designed for use over SSH, remoting sessions, or
        any terminal where Task Manager is not available. Press Q to quit, or use
        C/M/P/N keys to change the sort column interactively.

    .PARAMETER RefreshInterval
        Number of seconds between display updates. Valid range is 1 to 60.
        Defaults to 2 seconds.

    .PARAMETER ProcessCount
        Maximum number of processes to display. Valid range is 5 to 100.
        Defaults to 25.

    .PARAMETER NoColor
        Disables ANSI color output for terminals that do not support escape sequences.

    .EXAMPLE
        Show-SystemMonitor

        Launches the monitor with default settings (2-second refresh, top 25 processes).

    .EXAMPLE
        Show-SystemMonitor -RefreshInterval 5 -ProcessCount 40

        Refreshes every 5 seconds and shows the top 40 processes.

    .EXAMPLE
        Show-SystemMonitor -NoColor

        Launches without color for terminals that do not support ANSI escape sequences.

    .OUTPUTS
        None. This function renders an interactive TUI and does not produce pipeline output.

    .NOTES
        Author: Franck SALLET
        Version: 1.3.0
        Last Modified: 2026-04-06
        Requires: PowerShell 5.1+ / Windows only
        Requires: Interactive console (not ISE or redirected output)

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance
    #>
    [CmdletBinding()]
    # Variables defined in begin{} are used in process{} via string interpolation "${var}"
    # and [Console] method calls — PSScriptAnalyzer cannot track cross-block or interpolation usage
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    param(
        [Parameter()]
        [ValidateRange(1, 60)]
        [int]$RefreshInterval = 2,

        [Parameter()]
        [ValidateRange(5, 100)]
        [int]$ProcessCount = 25,

        [Parameter()]
        [switch]$NoColor
    )

    begin {
        # ---- Console check ----
        if ($Host.Name -eq 'Windows PowerShell ISE Host') {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ISE is not supported. Use Windows Terminal, ConHost, or a remote SSH session."
            return
        }

        # ---- ANSI helpers ----
        $esc      = [char]27
        $useColor = -not $NoColor

        # Returns a threshold-based fg color for percentage values (green / yellow / red)
        function Get-ColorCode {
            param([int]$Percent)
            if (-not $script:useColor) { return '' }
            if ($Percent -gt 80) { return "$script:esc[91m" }   # bright red
            if ($Percent -gt 60) { return "$script:esc[93m" }   # bright yellow
            return "$script:esc[92m"                             # bright green
        }

        # Returns a color for section labels (CPU / Mem / Swp) that reflects current load.
        # Same thresholds as Get-ColorCode but returns cyan at normal load instead of green
        # so labels are visually distinct from bar fill characters.
        function Get-LabelColor {
            param([int]$Percent)
            if (-not $script:useColor) { return '' }
            if ($Percent -gt 80) { return "$script:esc[91m" }   # bright red   — critical
            if ($Percent -gt 60) { return "$script:esc[93m" }   # bright yellow — warning
            return "$script:esc[96m"                             # cyan          — normal
        }

        # Strips all ANSI CSI SGR sequences before measuring visual length.
        # Regex is defined inline to avoid scope-capture issues with nested functions.
        function Get-VisualWidth {
            param([string]$Text)
            ($Text -replace "$([char]27)\[\d+(?:;\d+)*m", '').Length
        }

        # Pads a string (which may contain ANSI escapes) to a target visual width.
        # Non-approved verb is intentional — private helper, never exported.
        function ConvertTo-PaddedLine {
            param([string]$Text, [int]$TargetWidth)
            $visual = Get-VisualWidth -Text $Text
            $needed = $TargetWidth - $visual
            if ($needed -gt 0) { return $Text + [string]::new(' ', $needed) }
            return $Text
        }

        # ---- Static ANSI codes ----
        $dim       = if ($useColor) { "$esc[90m" } else { '' }
        $reset     = if ($useColor) { "$esc[0m"  } else { '' }
        $bold      = if ($useColor) { "$esc[1m"  } else { '' }
        $cyan      = if ($useColor) { "$esc[96m" } else { '' }
        $white     = if ($useColor) { "$esc[97m" } else { '' }
        $underline = if ($useColor) { "$esc[4m"  } else { '' }
        $yellow    = if ($useColor) { "$esc[93m" } else { '' }   # uptime, refresh value
        $magenta   = if ($useColor) { "$esc[95m" } else { '' }   # top CPU consumer name
        $bgDimRow  = if ($useColor) { "$esc[48;5;235m" } else { '' }  # zebra stripe background
        $fgHot     = if ($useColor) { "$esc[97m$esc[1m" } else { '' } # bright white bold — heavy process

        # ---- Bar rendering ----
        function Format-Bar {
            param([int]$Percent, [int]$Width)
            if ($Percent -lt 0)   { $Percent = 0   }
            if ($Percent -gt 100) { $Percent = 100 }
            $filled    = [math]::Max(0, [math]::Round($Width * $Percent / 100))
            $empty     = $Width - $filled
            $color     = Get-ColorCode -Percent $Percent
            $filledStr = [string]::new([char]0x2588, $filled)
            $emptyStr  = [string]::new([char]0x2591, $empty)
            "${color}${filledStr}$script:dim${emptyStr}$script:reset"
        }

        function Format-Size {
            param([double]$SizeKB)
            if ($SizeKB -ge 1048576) { return '{0:N1}G' -f ($SizeKB / 1048576) }
            if ($SizeKB -ge 1024)    { return '{0:N0}M' -f ($SizeKB / 1024)    }
            return '{0:N0}K' -f $SizeKB
        }

        # Renders a colored "used / total" ratio — color driven by usage percent
        function Format-MemRatio {
            param([string]$Used, [string]$Total, [int]$Percent)
            $color = Get-LabelColor -Percent $Percent
            "${color}${Used}$script:reset $script:dim/$script:reset $script:white${Total}$script:reset"
        }

        $sortMode = 'CPU'
        $running  = $true
    }

    process {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') { return }

        $previousCtrlC         = [Console]::TreatControlCAsInput
        $previousCursorVisible = [Console]::CursorVisible

        try {
            [Console]::TreatControlCAsInput = $true
            [Console]::CursorVisible        = $false
            [Console]::Clear()

            while ($running) {
                $frameStart = [Diagnostics.Stopwatch]::StartNew()

                # ============================================================
                # DATA GATHERING
                # ============================================================
                $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction SilentlyContinue

                # Guard against WMI failure — skip frame instead of crashing
                if (-not $os) {
                    Start-Sleep -Seconds 1
                    continue
                }

                $cpuCores = @(
                    Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne '_Total' } |
                    Sort-Object { [int]$_.Name }
                )

                $cpuTotal = Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq '_Total' }

                $processes = @(
                    Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfProc_Process' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' -and $_.IDProcess -ne 0 }
                )

                $coreCount = [math]::Max(1, $cpuCores.Count)
                $width     = [math]::Max(80, [Console]::WindowWidth)
                $height    = [math]::Max(24, [Console]::WindowHeight)

                # Memory (KB)
                $totalMemKB = $os.TotalVisibleMemorySize
                $freeMemKB  = $os.FreePhysicalMemory
                $usedMemKB  = $totalMemKB - $freeMemKB
                $memPercent = [math]::Round(($usedMemKB / $totalMemKB) * 100)

                # Page file (KB)
                $totalPageKB = $os.SizeStoredInPagingFiles
                $freePageKB  = $os.FreeSpaceInPagingFiles
                $usedPageKB  = $totalPageKB - $freePageKB
                $pagePercent = if ($totalPageKB -gt 0) { [math]::Round(($usedPageKB / $totalPageKB) * 100) } else { 0 }

                # Uptime
                $uptime    = (Get-Date) - $os.LastBootUpTime
                $uptimeStr = '{0}d {1:D2}:{2:D2}:{3:D2}' -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds

                # Total CPU %
                $totalCpuPercent = if ($cpuTotal) { [int]$cpuTotal.PercentProcessorTime } else { 0 }

                # Process list
                $procList = foreach ($proc in $processes) {
                    $cpuPct    = [math]::Round($proc.PercentProcessorTime / $coreCount, 1)
                    $memMB     = [math]::Round($proc.WorkingSetPrivate / 1MB, 1)
                    $cleanName = $proc.Name -replace '#\d+$', ''
                    [PSCustomObject]@{
                        PID   = $proc.IDProcess
                        CPU   = $cpuPct
                        MemMB = $memMB
                        Name  = $cleanName
                    }
                }

                $sortedProcs = switch ($sortMode) {
                    'Memory' { $procList | Sort-Object -Property 'MemMB' -Descending }
                    'PID'    { $procList | Sort-Object -Property 'PID'               }
                    'Name'   { $procList | Sort-Object -Property 'Name'              }
                    default  { $procList | Sort-Object -Property 'CPU'  -Descending  }
                }
                $topProcs = @($sortedProcs | Select-Object -First $ProcessCount)

                # ============================================================
                # FRAME RENDERING — single buffer, single Console::Write
                # ============================================================
                $lines     = [System.Collections.Generic.List[string]]::new(64)
                $separator = [string]::new([char]0x2500, $width - 4)

                # ---- Header ----
                # Hostname: bold white  |  Uptime: yellow  |  Timestamp: dimmed
                $timeStr   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $procCount = $processes.Count
                $lines.Add("  ${bold}${cyan}Show-SystemMonitor${reset} ${dim}-${reset} ${bold}${white}${env:COMPUTERNAME}${reset} ${dim}|${reset} Up: ${yellow}${uptimeStr}${reset} ${dim}|${reset} ${dim}${timeStr}${reset} ${dim}|${reset} Procs: ${white}${procCount}${reset}")
                $lines.Add("  ${dim}${separator}${reset}")

                # ---- Summary bars (CPU / Mem / Swap) ----
                # Label color reflects current load — one Get-LabelColor call per resource, negligible cost
                $barWidth = [math]::Min(40, $width - 30)

                $cpuLabelColor = Get-LabelColor -Percent $totalCpuPercent
                $cpuBar        = Format-Bar -Percent $totalCpuPercent -Width $barWidth
                $cpuPctStr     = '{0,5:N1}' -f $totalCpuPercent
                $lines.Add("  ${cpuLabelColor}${bold}CPU${reset}  [${cpuBar}] ${cpuPctStr}%    Cores: ${white}${coreCount}${reset}")

                $memLabelColor = Get-LabelColor -Percent $memPercent
                $memBar        = Format-Bar -Percent $memPercent -Width $barWidth
                $memPctStr     = '{0,5:N1}' -f $memPercent
                $memRatio      = Format-MemRatio -Used (Format-Size $usedMemKB) -Total (Format-Size $totalMemKB) -Percent $memPercent
                $lines.Add("  ${memLabelColor}${bold}Mem${reset}  [${memBar}] ${memPctStr}%    ${memRatio}")

                $pageLabelColor = Get-LabelColor -Percent $pagePercent
                $pageBar        = Format-Bar -Percent $pagePercent -Width $barWidth
                $pagePctStr     = '{0,5:N1}' -f $pagePercent
                $pageRatio      = Format-MemRatio -Used (Format-Size $usedPageKB) -Total (Format-Size $totalPageKB) -Percent $pagePercent
                $lines.Add("  ${pageLabelColor}${bold}Swp${reset}  [${pageBar}] ${pagePctStr}%    ${pageRatio}")
                $lines.Add('')

                # ---- Per-core CPU bars (2 columns) ----
                # Core number takes the same color as its fill bar for instant visual scanning
                $coreBarWidth       = [math]::Min(20, [math]::Floor(($width - 30) / 2))
                $coreColVisualWidth = $coreBarWidth + 14

                for ($i = 0; $i -lt $cpuCores.Count; $i += 2) {
                    $pct          = [int]$cpuCores[$i].PercentProcessorTime
                    $bar          = Format-Bar -Percent $pct -Width $coreBarWidth
                    $coreNumColor = Get-ColorCode -Percent $pct
                    $coreLabel    = '{0,3}' -f $cpuCores[$i].Name
                    $pctStr       = '{0,3}' -f $pct
                    $leftCol      = "${coreNumColor}${coreLabel}${reset} [${bar}] ${pctStr}%"

                    if ($i + 1 -lt $cpuCores.Count) {
                        $leftPadded    = ConvertTo-PaddedLine -Text $leftCol -TargetWidth $coreColVisualWidth
                        $pct2          = [int]$cpuCores[$i + 1].PercentProcessorTime
                        $bar2          = Format-Bar -Percent $pct2 -Width $coreBarWidth
                        $coreNumColor2 = Get-ColorCode -Percent $pct2
                        $coreLabel2    = '{0,3}' -f $cpuCores[$i + 1].Name
                        $pct2Str       = '{0,3}' -f $pct2
                        $rightCol      = "${coreNumColor2}${coreLabel2}${reset} [${bar2}] ${pct2Str}%"
                        $lines.Add("  ${leftPadded}    ${rightCol}")
                    }
                    else {
                        $lines.Add("  ${leftCol}")
                    }
                }
                $lines.Add("  ${dim}${separator}${reset}")

                # ---- Process table header ----
                # Active sort column highlighted in cyan + underline; inactive columns dimmed
                $pidH  = if ($sortMode -eq 'PID')    { "${cyan}${underline}PID${reset}"     } else { "${dim}PID${reset}"     }
                $cpuH  = if ($sortMode -eq 'CPU')    { "${cyan}${underline}CPU%${reset}"    } else { "${dim}CPU%${reset}"    }
                $memH  = if ($sortMode -eq 'Memory') { "${cyan}${underline}MEM(MB)${reset}" } else { "${dim}MEM(MB)${reset}" }
                $nameH = if ($sortMode -eq 'Name')   { "${cyan}${underline}Name${reset}"    } else { "${dim}Name${reset}"    }
                $lines.Add("  ${bold}  ${pidH}   ${cpuH}   ${memH}   ${nameH}${reset}")

                # ---- Process rows ----
                # Reserve 3 lines for: blank + separator + footer
                $availableRows = $height - $lines.Count - 3
                $displayCount  = [math]::Min($topProcs.Count, [math]::Max(5, $availableRows))

                for ($i = 0; $i -lt $displayCount; $i++) {
                    $p        = $topProcs[$i]
                    $cpuColor = Get-ColorCode -Percent ([math]::Min(100, $p.CPU * 2))
                    $pidStr   = '{0,7}'    -f $p.PID
                    $cpuStr   = '{0,7:N1}' -f $p.CPU
                    $memStr   = '{0,9:N1}' -f $p.MemMB

                    # Zebra striping: odd rows get a barely-visible dark background
                    $rowBg    = if ($useColor -and ($i % 2 -eq 1)) { $bgDimRow } else { '' }
                    $rowReset = if ($useColor -and ($i % 2 -eq 1)) { $reset    } else { '' }

                    # Process name coloring:
                    #   rank 0 (top consumer) → magenta
                    #   CPU > 50%             → bright white bold
                    #   otherwise             → normal white
                    $nameColor = if ($i -eq 0 -and $p.CPU -gt 0) { $magenta }
                                 elseif ($p.CPU -gt 50)           { $fgHot   }
                                 else                             { $white   }

                    $lines.Add("${rowBg}  ${pidStr} ${cpuColor}${cpuStr}${reset}${rowBg} ${memStr}   ${nameColor}$($p.Name)${rowReset}${reset}")
                }

                # ---- Footer ----
                # Hotkey letters in cyan; active sort value in cyan bold
                $lines.Add('')
                $lines.Add("  ${dim}${separator}${reset}")
                $lines.Add("  ${bold}[${cyan}Q${reset}${bold}]${reset}uit  ${bold}[${cyan}C${reset}${bold}]${reset}PU  ${bold}[${cyan}M${reset}${bold}]${reset}em  ${bold}[${cyan}P${reset}${bold}]${reset}ID  ${bold}[${cyan}N${reset}${bold}]${reset}ame  ${dim}|${reset}  Refresh: ${yellow}${RefreshInterval}s${reset}  ${dim}|${reset}  Sort: ${cyan}${bold}${sortMode}${reset}")

                # ============================================================
                # SINGLE WRITE — move cursor home, write all lines, erase tail
                # ============================================================
                $frame = [System.Text.StringBuilder]::new($lines.Count * ($width + 20))

                # Move cursor to top-left without clearing (avoids flash)
                [void]$frame.Append("$esc[H")

                foreach ($line in $lines) {
                    $padded = ConvertTo-PaddedLine -Text $line -TargetWidth $width
                    [void]$frame.AppendLine($padded)
                }

                # Erase remaining rows — ESC[2K clears the current line,
                # AppendLine advances the cursor to the next row
                $remainingRows = $height - $lines.Count
                for ($r = 0; $r -lt $remainingRows; $r++) {
                    [void]$frame.AppendLine("$esc[2K")
                }

                [Console]::Write($frame.ToString())
                $frameStart.Stop()

                # ============================================================
                # INPUT HANDLING
                # ============================================================
                $sleepMs    = [math]::Max(100, ($RefreshInterval * 1000) - $frameStart.ElapsedMilliseconds)
                $inputTimer = [Diagnostics.Stopwatch]::StartNew()

                while ($inputTimer.ElapsedMilliseconds -lt $sleepMs) {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)

                        # Ctrl+C — checked first so it always wins
                        if ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                            $running = $false
                            break
                        }

                        if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') { $running = $false }
                        elseif ($key.Key -eq 'C') { $sortMode = 'CPU'    }
                        elseif ($key.Key -eq 'M') { $sortMode = 'Memory' }
                        elseif ($key.Key -eq 'P') { $sortMode = 'PID'    }
                        elseif ($key.Key -eq 'N') { $sortMode = 'Name'   }

                        if (-not $running) { break }
                    }
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        finally {
            [Console]::CursorVisible        = $previousCursorVisible
            [Console]::TreatControlCAsInput = $previousCtrlC
            [Console]::Clear()
            Write-Information -MessageData 'System monitor stopped.' -InformationAction Continue
        }
    }
}