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
        Version: 1.0.0
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
        $esc = [char]27
        $useColor = -not $NoColor

        function Get-ColorCode {
            param([int]$Percent)
            if (-not $useColor) { return '' }
            if ($Percent -gt 80) { return "$esc[91m" }     # bright red
            if ($Percent -gt 60) { return "$esc[93m" }     # bright yellow
            return "$esc[92m"                               # bright green
        }

        $dim = if ($useColor) { "$esc[90m" } else { '' }
        $reset = if ($useColor) { "$esc[0m" } else { '' }
        $bold = if ($useColor) { "$esc[1m" } else { '' }
        $cyan = if ($useColor) { "$esc[96m" } else { '' }
        $white = if ($useColor) { "$esc[97m" } else { '' }
        $underline = if ($useColor) { "$esc[4m" } else { '' }

        # ---- Bar rendering ----
        function Format-Bar {
            param([int]$Percent, [int]$Width)
            if ($Percent -lt 0) { $Percent = 0 }
            if ($Percent -gt 100) { $Percent = 100 }
            $filled = [math]::Max(0, [math]::Round($Width * $Percent / 100))
            $empty = $Width - $filled
            $color = Get-ColorCode -Percent $Percent
            "${color}$([string]::new([char]0x2588, $filled))${dim}$([string]::new([char]0x2591, $empty))${reset}"
        }

        function Format-Size {
            param([double]$SizeKB)
            if ($SizeKB -ge 1048576) { return '{0:N1}G' -f ($SizeKB / 1048576) }
            if ($SizeKB -ge 1024) { return '{0:N0}M' -f ($SizeKB / 1024) }
            return '{0:N0}K' -f $SizeKB
        }

        function Format-SizeMB {
            param([double]$SizeMB)
            if ($SizeMB -ge 1024) { return '{0:N1}G' -f ($SizeMB / 1024) }
            return '{0:N0}M' -f $SizeMB
        }

        $sortMode = 'CPU'
        $running = $true
    }

    process {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') { return }

        $previousCtrlC = [Console]::TreatControlCAsInput
        $previousCursorVisible = [Console]::CursorVisible

        try {
            [Console]::TreatControlCAsInput = $true
            [Console]::CursorVisible = $false
            [Console]::Clear()

            while ($running) {
                $frameStart = [Diagnostics.Stopwatch]::StartNew()

                # ============================================================
                # DATA GATHERING
                # ============================================================
                $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction SilentlyContinue
                $cpuCores = @(Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne '_Total' } |
                    Sort-Object { [int]$_.Name })
                $cpuTotal = Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq '_Total' }

                $processes = @(Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfProc_Process' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' -and $_.IDProcess -ne 0 })

                $coreCount = [math]::Max(1, $cpuCores.Count)
                $width = [math]::Max(80, [Console]::WindowWidth)
                $height = [math]::Max(24, [Console]::WindowHeight)

                # Memory calculations (KB)
                $totalMemKB = $os.TotalVisibleMemorySize
                $freeMemKB = $os.FreePhysicalMemory
                $usedMemKB = $totalMemKB - $freeMemKB
                $memPercent = [math]::Round(($usedMemKB / $totalMemKB) * 100)

                # Page file (KB)
                $totalPageKB = $os.SizeStoredInPagingFiles
                $freePageKB = $os.FreeSpaceInPagingFiles
                $usedPageKB = $totalPageKB - $freePageKB
                $pagePercent = if ($totalPageKB -gt 0) { [math]::Round(($usedPageKB / $totalPageKB) * 100) } else { 0 }

                # Uptime
                $uptime = (Get-Date) - $os.LastBootUpTime
                $uptimeStr = '{0}d {1:D2}:{2:D2}:{3:D2}' -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds

                # Total CPU %
                $totalCpuPercent = if ($cpuTotal) { [int]$cpuTotal.PercentProcessorTime } else { 0 }

                # Process list
                $procList = foreach ($proc in $processes) {
                    $cpuPct = [math]::Round($proc.PercentProcessorTime / $coreCount, 1)
                    $memMB = [math]::Round($proc.WorkingSetPrivate / 1MB, 1)
                    $name = $proc.Name -replace '#\d+, ''
                    [PSCustomObject]@{
                        PID    = $proc.IDProcess
                        CPU    = $cpuPct
                        MemMB  = $memMB
                        Name   = $name
                    }
                }

                if ($sortMode -eq 'Memory') {
                    $sortedProcs = $procList | Sort-Object -Property 'MemMB' -Descending
                }
                elseif ($sortMode -eq 'PID') {
                    $sortedProcs = $procList | Sort-Object -Property 'PID'
                }
                elseif ($sortMode -eq 'Name') {
                    $sortedProcs = $procList | Sort-Object -Property 'Name'
                }
                else {
                    $sortedProcs = $procList | Sort-Object -Property 'CPU' -Descending
                }
                $topProcs = @($sortedProcs | Select-Object -First $ProcessCount)

                # ============================================================
                # FRAME RENDERING
                # ============================================================
                $frame = [System.Text.StringBuilder]::new(4096)

                # ---- Header ----
                $header = "  ${bold}${cyan}Show-SystemMonitor${reset} ${dim}-${reset} ${white}$($env:COMPUTERNAME)${reset} ${dim}|${reset} Up: ${white}$uptimeStr${reset} ${dim}|${reset} $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ${dim}|${reset} Procs: ${white}$($processes.Count)${reset}"
                [void]$frame.AppendLine($header)
                [void]$frame.AppendLine("  ${dim}$([string]::new([char]0x2500, $width - 4))${reset}")

                # ---- Summary bars (CPU / Mem / Swap) ----
                $barWidth = [math]::Min(40, $width - 30)

                $cpuBar = Format-Bar -Percent $totalCpuPercent -Width $barWidth
                $cpuLine = "  ${bold}CPU${reset}  [${cpuBar}] $('{0,5:N1}' -f $totalCpuPercent)%    Cores: ${white}$coreCount${reset}"
                [void]$frame.AppendLine($cpuLine)

                $memBar = Format-Bar -Percent $memPercent -Width $barWidth
                $memLine = "  ${bold}Mem${reset}  [${memBar}] $('{0,5:N1}' -f $memPercent)%    $(Format-Size $usedMemKB) / $(Format-Size $totalMemKB)"
                [void]$frame.AppendLine($memLine)

                $pageBar = Format-Bar -Percent $pagePercent -Width $barWidth
                $pageLine = "  ${bold}Swp${reset}  [${pageBar}] $('{0,5:N1}' -f $pagePercent)%    $(Format-Size $usedPageKB) / $(Format-Size $totalPageKB)"
                [void]$frame.AppendLine($pageLine)
                [void]$frame.AppendLine('')

                # ---- Per-core CPU bars (2 columns) ----
                $coreBarWidth = [math]::Min(20, [math]::Floor(($width - 30) / 2))
                $colWidth = $coreBarWidth + 16

                for ($i = 0; $i -lt $cpuCores.Count; $i += 2) {
                    $line = '  '

                    # Left column
                    $pct = [int]$cpuCores[$i].PercentProcessorTime
                    $bar = Format-Bar -Percent $pct -Width $coreBarWidth
                    $coreLabel = '{0,3}' -f $cpuCores[$i].Name
                    $line += "${dim}$coreLabel${reset} [${bar}] $('{0,3}' -f $pct)%"

                    # Right column (if exists)
                    if ($i + 1 -lt $cpuCores.Count) {
                        $padding = $colWidth - ($coreLabel.Length + $coreBarWidth + 8)
                        if ($padding -lt 2) { $padding = 2 }
                        $line += "$([string]::new(' ', $padding))"
                        $pct2 = [int]$cpuCores[$i + 1].PercentProcessorTime
                        $bar2 = Format-Bar -Percent $pct2 -Width $coreBarWidth
                        $coreLabel2 = '{0,3}' -f $cpuCores[$i + 1].Name
                        $line += "${dim}$coreLabel2${reset} [${bar2}] $('{0,3}' -f $pct2)%"
                    }

                    [void]$frame.AppendLine($line)
                }

                [void]$frame.AppendLine("  ${dim}$([string]::new([char]0x2500, $width - 4))${reset}")

                # ---- Process table header ----
                $pidH = if ($sortMode -eq 'PID') { "${underline}PID${reset}" } else { 'PID' }
                $cpuH = if ($sortMode -eq 'CPU') { "${underline}CPU%${reset}" } else { 'CPU%' }
                $memH = if ($sortMode -eq 'Memory') { "${underline}MEM(MB)${reset}" } else { 'MEM(MB)' }
                $nameH = if ($sortMode -eq 'Name') { "${underline}Name${reset}" } else { 'Name' }

                $procHeader = "  ${bold}$(' ' * 2)$pidH$(' ' * 3)$cpuH$(' ' * 3)$memH   $nameH${reset}"
                [void]$frame.AppendLine($procHeader)

                # ---- Process rows ----
                $maxRows = $height - $frame.ToString().Split("`n").Count - 3
                $displayCount = [math]::Min($topProcs.Count, [math]::Max(5, $maxRows))

                for ($i = 0; $i -lt $displayCount; $i++) {
                    $p = $topProcs[$i]
                    $cpuColor = Get-ColorCode -Percent ([math]::Min(100, $p.CPU * 2))
                    $procLine = '  {0,7} {1}{2,7:N1}{3} {4,9:N1}   {5}' -f $p.PID, $cpuColor, $p.CPU, $reset, $p.MemMB, $p.Name
                    [void]$frame.AppendLine($procLine)
                }

                # ---- Footer ----
                [void]$frame.AppendLine('')
                [void]$frame.AppendLine("  ${dim}$([string]::new([char]0x2500, $width - 4))${reset}")

                $footer = "  ${bold}[Q]${reset}uit  ${bold}[C]${reset}PU sort  ${bold}[M]${reset}em sort  ${bold}[P]${reset}ID sort  ${bold}[N]${reset}ame sort  ${dim}|${reset}  Refresh: ${white}${RefreshInterval}s${reset}  ${dim}|${reset}  Sort: ${white}$sortMode${reset}"
                [void]$frame.AppendLine($footer)

                # ---- Write frame ----
                [Console]::SetCursorPosition(0, 0)
                # Pad each line to full width to overwrite previous content
                $lines = $frame.ToString().Split("`n")
                foreach ($line in $lines) {
                    $padded = $line.PadRight($width + 40)  # Extra padding for ANSI escape sequences
                    [Console]::Write($padded.Substring(0, [math]::Min($padded.Length, $width + 100)))
                    [Console]::WriteLine()
                }

                # Clear remaining lines from previous frame
                $currentRow = $lines.Count
                while ($currentRow -lt $height) {
                    [Console]::SetCursorPosition(0, $currentRow)
                    [Console]::Write([string]::new(' ', $width))
                    $currentRow++
                }

                $frameStart.Stop()

                # ============================================================
                # INPUT HANDLING
                # ============================================================
                $sleepMs = [math]::Max(100, ($RefreshInterval * 1000) - $frameStart.ElapsedMilliseconds)
                $sleepEnd = [Diagnostics.Stopwatch]::StartNew()

                while ($sleepEnd.ElapsedMilliseconds -lt $sleepMs) {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)

                        # Ctrl+C check first
                        if ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                            $running = $false
                            break
                        }

                        if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') {
                            $running = $false
                            break
                        }
                        elseif ($key.Key -eq 'C') { $sortMode = 'CPU' }
                        elseif ($key.Key -eq 'M') { $sortMode = 'Memory' }
                        elseif ($key.Key -eq 'P') { $sortMode = 'PID' }
                        elseif ($key.Key -eq 'N') { $sortMode = 'Name' }

                        if (-not $running) { break }
                    }
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        finally {
            [Console]::CursorVisible = $previousCursorVisible
            [Console]::TreatControlCAsInput = $previousCtrlC
            [Console]::Clear()
            Write-Information -MessageData "System monitor stopped." -InformationAction Continue
        }
    }
}
