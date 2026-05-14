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

        $sortMode = 'CPU'
        $running  = $true
    }

    process {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') {
            return 
        }

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
                $width = [math]::Max(80, [Console]::WindowWidth)
                $height = [math]::Max(24, [Console]::WindowHeight)

                # Memory (KB)
                $totalMemKB = $os.TotalVisibleMemorySize
                $freeMemKB = $os.FreePhysicalMemory
                $usedMemKB = $totalMemKB - $freeMemKB
                $memPercent = [math]::Round(($usedMemKB / $totalMemKB) * 100)

                # Page file (KB)
                $totalPageKB = $os.SizeStoredInPagingFiles
                $freePageKB = $os.FreeSpaceInPagingFiles
                $usedPageKB = $totalPageKB - $freePageKB
                $pagePercent = if ($totalPageKB -gt 0) {
                    [math]::Round(($usedPageKB / $totalPageKB) * 100) 
                } else {
                    0 
                }

                # Uptime
                $uptime = (Get-Date) - $os.LastBootUpTime
                $uptimeStr = '{0}d {1:D2}:{2:D2}:{3:D2}' -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds

                # Total CPU %
                $totalCpuPercent = if ($cpuTotal) {
                    [int]$cpuTotal.PercentProcessorTime 
                } else {
                    0 
                }

                # Process list
                $procList = foreach ($proc in $processes) {
                    $cpuPct = [math]::Round($proc.PercentProcessorTime / $coreCount, 1)
                    $memMB = [math]::Round($proc.WorkingSetPrivate / 1MB, 1)
                    $cleanName = $proc.Name -replace '#\d+$', ''
                    [PSCustomObject]@{
                        PID   = $proc.IDProcess
                        CPU   = $cpuPct
                        MemMB = $memMB
                        Name  = $cleanName
                    }
                }

                $sortedProcs = switch ($sortMode) {
                    'Memory' {
                        $procList | Sort-Object -Property 'MemMB' -Descending 
                    }
                    'PID' {
                        $procList | Sort-Object -Property 'PID'               
                    }
                    'Name' {
                        $procList | Sort-Object -Property 'Name'              
                    }
                    default {
                        $procList | Sort-Object -Property 'CPU' -Descending  
                    }
                }
                $topProcs = @($sortedProcs | Select-Object -First $ProcessCount)

                # ============================================================
                # FRAME RENDERING — delegate to pure formatter
                # ============================================================
                $timeStr      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $frameContent = Format-SystemMonitorFrame `
                    -CpuTotalPercent $totalCpuPercent `
                    -CpuCores        $cpuCores `
                    -MemPercent      $memPercent `
                    -MemUsedKB       $usedMemKB `
                    -MemTotalKB      $totalMemKB `
                    -PagePercent     $pagePercent `
                    -PageUsedKB      $usedPageKB `
                    -PageTotalKB     $totalPageKB `
                    -UptimeStr       $uptimeStr `
                    -TimeStr         $timeStr `
                    -ProcessCount    $processes.Count `
                    -TopProcesses    $topProcs `
                    -SortMode        $sortMode `
                    -Width           $width `
                    -Height          $height `
                    -RefreshInterval $RefreshInterval `
                    -NoColor:$NoColor

                [Console]::Write($frameContent)
                $frameStart.Stop()

                # ============================================================
                # INPUT HANDLING
                # ============================================================
                $sleepMs = [math]::Max(100, ($RefreshInterval * 1000) - $frameStart.ElapsedMilliseconds)
                $inputTimer = [Diagnostics.Stopwatch]::StartNew()

                while ($inputTimer.ElapsedMilliseconds -lt $sleepMs) {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)

                        # Ctrl+C — checked first so it always wins
                        if ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                            $running = $false
                            break
                        }

                        if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') {
                            $running = $false 
                        } elseif ($key.Key -eq 'C') {
                            $sortMode = 'CPU'    
                        } elseif ($key.Key -eq 'M') {
                            $sortMode = 'Memory' 
                        } elseif ($key.Key -eq 'P') {
                            $sortMode = 'PID'    
                        } elseif ($key.Key -eq 'N') {
                            $sortMode = 'Name'   
                        }

                        if (-not $running) {
                            break 
                        }
                    }
                    Start-Sleep -Milliseconds 50
                }
            }
        } finally {
            [Console]::CursorVisible = $previousCursorVisible
            [Console]::TreatControlCAsInput = $previousCtrlC
            [Console]::Clear()
            Write-Information -MessageData 'System monitor stopped.' -InformationAction Continue
        }
    }
}
