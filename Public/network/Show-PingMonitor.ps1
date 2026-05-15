#Requires -Version 5.1

function Show-PingMonitor {
    <#
        .SYNOPSIS
            Interactive real-time ping monitor with ANSI-colored console display

        .DESCRIPTION
            Continuously pings one or more hosts and displays live statistics in an
            interactive console interface with ANSI color-coded status indicators.
            Supports keyboard controls for sorting, pausing, clearing statistics,
            and quitting. Press Q to quit, S to cycle sort, C to clear stats,
            P to pause/resume monitoring.

        .PARAMETER ComputerName
            One or more hostnames or IP addresses to monitor.

        .PARAMETER RefreshInterval
            Refresh interval in seconds. Default: 2. Valid range: 1-60.

        .PARAMETER PingTimeoutMs
            Timeout per ping in milliseconds. Default: 2000. Valid range: 500-10000.

        .PARAMETER NoClear
            Suppresses the console clear on exit so the final frame remains visible
            in the scrollback buffer.

        .PARAMETER NoColor
            Disables ANSI color output for terminals that do not support escape sequences.

        .EXAMPLE
            Show-PingMonitor -ComputerName '192.168.1.1', 'google.com'

            Monitors two hosts with default settings. Press Q to quit, S to sort,
            C to clear statistics, P to pause or resume monitoring.

        .EXAMPLE
            Show-PingMonitor -ComputerName 'SRV01' -RefreshInterval 5 -NoColor

            Monitors a single server with 5-second refresh and ANSI colors disabled.

        .EXAMPLE
            'SRV01', 'SRV02', 'SRV03' | Show-PingMonitor -PingTimeoutMs 1000

            Monitors three servers via pipeline input with a 1-second ping timeout.

        .OUTPUTS
            None
            This function renders an interactive TUI and does not produce pipeline output.

        .NOTES
            Author: Franck SALLET
            Version: 2.0.0
            Last Modified: 2026-04-11
            Requires: PowerShell 5.1+ / Windows only
            Requires: Interactive console (not ISE or redirected output)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/dotnet/api/system.net.networkinformation.ping
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$RefreshInterval = 2,

        [Parameter(Mandatory = $false)]
        [ValidateRange(500, 10000)]
        [int]$PingTimeoutMs = 2000,

        [Parameter(Mandatory = $false)]
        [switch]$NoClear,

        [Parameter(Mandatory = $false)]
        [switch]$NoColor
    )

    begin {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ISE is not supported. Use Windows Terminal, ConHost, or a remote SSH session."
            return
        }

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"
        $hostList = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') { return }
        foreach ($targetHost in $ComputerName) {
            if (-not $hostList.Contains($targetHost)) {
                $hostList.Add($targetHost)
            }
        }
    }

    end {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') { return }
        if ($hostList.Count -eq 0) {
            Write-Warning -Message "[$($MyInvocation.MyCommand)] No hosts specified"
            return
        }

        # ---- ANSI setup ----
        $esc      = [char]27
        $useColor = -not $NoColor

        $bold   = if ($useColor) { "${esc}[1m" }  else { '' }
        $dim    = if ($useColor) { "${esc}[90m" } else { '' }
        $reset  = if ($useColor) { "${esc}[0m" }  else { '' }
        $cyan   = if ($useColor) { "${esc}[96m" } else { '' }
        $white  = if ($useColor) { "${esc}[97m" } else { '' }
        $green  = if ($useColor) { "${esc}[92m" } else { '' }
        $red    = if ($useColor) { "${esc}[91m" } else { '' }
        $yellow = if ($useColor) { "${esc}[93m" } else { '' }

        # ---- Per-host statistics ----
        $statsTable = @{}
        foreach ($targetHost in $hostList) {
            $statsTable[$targetHost] = @{
                Sent = 0; Received = 0; Lost = 0
                LastMs = -1; MinMs = [int]::MaxValue; MaxMs = 0; TotalMs = [long]0
                Status = 'Pending'
            }
        }

        # Column width for host names
        $maxHostLen = 4
        foreach ($targetHost in $hostList) {
            if ($targetHost.Length -gt $maxHostLen) { $maxHostLen = $targetHost.Length }
        }

        # ---- Sort modes ----
        $sortModes = @('Host', 'Status', 'LastMs', 'Loss')
        $sortIndex = 0
        $sortMode  = $sortModes[$sortIndex]

        $running      = $true
        $paused       = $false
        $monitorStart = Get-Date
        $pinger       = [System.Net.NetworkInformation.Ping]::new()

        $previousCtrlC         = [Console]::TreatControlCAsInput
        $previousCursorVisible = [Console]::CursorVisible

        try {
            [Console]::TreatControlCAsInput = $true
            [Console]::CursorVisible        = $false
            [Console]::Clear()

            while ($running) {
                $frameStart = [Diagnostics.Stopwatch]::StartNew()

                # ---- Ping all hosts (skip when paused) ----
                if (-not $paused) {
                    foreach ($targetHost in $hostList) {
                        $hostStat = $statsTable[$targetHost]
                        $hostStat.Sent++
                        try {
                            $pingReply = $pinger.Send($targetHost, $PingTimeoutMs)
                            if ($pingReply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                                $hostStat.Received++
                                $roundtrip = [int]$pingReply.RoundtripTime
                                $hostStat.LastMs = $roundtrip
                                $hostStat.TotalMs += $roundtrip
                                if ($roundtrip -lt $hostStat.MinMs) { $hostStat.MinMs = $roundtrip }
                                if ($roundtrip -gt $hostStat.MaxMs) { $hostStat.MaxMs = $roundtrip }
                                $hostStat.Status = 'Up'
                            }
                            else {
                                $hostStat.Lost++
                                $hostStat.Status = 'Down'
                            }
                        }
                        catch {
                            $hostStat.Lost++
                            $hostStat.Status = 'Down'
                        }
                    }
                }

                # ---- Build display frame ----
                $elapsed    = (Get-Date) - $monitorStart
                $elapsedStr = '{0:00}:{1:00}:{2:00}' -f [math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds
                $height     = [math]::Max(24, [Console]::WindowHeight)

                $frameContent = Format-PingMonitorFrame `
                    -StatsTable      $statsTable `
                    -HostList        @($hostList) `
                    -MaxHostLen      $maxHostLen `
                    -SortMode        $sortMode `
                    -Paused          $paused `
                    -ElapsedStr      $elapsedStr `
                    -RefreshInterval $RefreshInterval `
                    -TerminalHeight  $height `
                    -NoColor:$NoColor

                [Console]::SetCursorPosition(0, 0)
                [Console]::Write($frameContent)
                $frameStart.Stop()

                # ---- Input handling ----
                $sleepMs    = [math]::Max(100, ($RefreshInterval * 1000) - $frameStart.ElapsedMilliseconds)
                $inputTimer = [Diagnostics.Stopwatch]::StartNew()

                while ($inputTimer.ElapsedMilliseconds -lt $sleepMs) {
                    if ([Console]::KeyAvailable) {
                        $keyInfo = [Console]::ReadKey($true)

                        if (($keyInfo.Key -eq 'C') -and (($keyInfo.Modifiers -band [ConsoleModifiers]::Control) -eq [ConsoleModifiers]::Control)) {
                            $running = $false
                            break
                        }

                        switch ($keyInfo.Key) {
                            'Q'      { $running = $false }
                            'Escape' { $running = $false }
                            'S'      { $sortIndex = ($sortIndex + 1) % $sortModes.Count; $sortMode = $sortModes[$sortIndex] }
                            'C'      {
                                foreach ($resetHost in $hostList) {
                                    $resetStat = $statsTable[$resetHost]
                                    $resetStat.Sent = 0; $resetStat.Received = 0; $resetStat.Lost = 0
                                    $resetStat.LastMs = -1; $resetStat.MinMs = [int]::MaxValue
                                    $resetStat.MaxMs = 0; $resetStat.TotalMs = [long]0
                                    $resetStat.Status = 'Pending'
                                }
                                $monitorStart = Get-Date
                            }
                            'P'      { $paused = -not $paused }
                        }

                        if (-not $running) { break }
                    }
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        finally {
            if ($null -ne $pinger) { $pinger.Dispose() }
            [Console]::CursorVisible        = $previousCursorVisible
            [Console]::TreatControlCAsInput = $previousCtrlC
            if (-not $NoClear) { [Console]::Clear() }
            Write-Information -MessageData 'Ping Monitor stopped.' -InformationAction Continue
        }
    }
}
