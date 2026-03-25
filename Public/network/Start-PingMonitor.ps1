#Requires -Version 5.1

function Start-PingMonitor {
    <#
        .SYNOPSIS
            Displays a real-time multi-host ping monitoring dashboard

        .DESCRIPTION
            Continuously pings multiple hosts and displays a live-updating table
            showing status (Up/Down), response time, and packet loss statistics.

            Similar to a NOC dashboard. Press Ctrl+C to stop and display final statistics.

            This is an interactive display function that writes directly to the console.
            It does not output objects to the pipeline.

        .PARAMETER ComputerName
            One or more hostnames or IP addresses to monitor.

        .PARAMETER RefreshInterval
            Refresh interval in seconds. Default: 2. Valid range: 1-60.

        .PARAMETER PingTimeoutMs
            Timeout per ping in milliseconds. Default: 2000. Valid range: 500-10000.

        .EXAMPLE
            Start-PingMonitor -ComputerName 'SRV01', 'SRV02', 'SRV03', 'gateway'

            Monitors 4 hosts with a live dashboard. Press Ctrl+C to stop.

        .EXAMPLE
            Start-PingMonitor -ComputerName (Get-Content servers.txt) -RefreshInterval 5

            Monitors hosts from a file with 5-second refresh.

        .EXAMPLE
            Start-PingMonitor -ComputerName '8.8.8.8', '1.1.1.1', 'gateway.local' -PingTimeoutMs 1000

            Monitors with a 1-second ping timeout.

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required (ICMP may be blocked by firewall)
            Output:        Writes to console only, no pipeline output.

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Write-Host is intentional for interactive console dashboard display')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Start-PingMonitor is a read-only monitoring loop, it does not change system state')]
    [CmdletBinding()]
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
        [int]$PingTimeoutMs = 2000
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting ping dashboard for $($ComputerName.Count) host(s)"

        # Initialize stats per host
        $hostStats = @{}
        foreach ($targetHost in $ComputerName) {
            $hostStats[$targetHost] = @{
                Sent     = 0
                Received = 0
                LastMs   = $null
                MinMs    = [double]::MaxValue
                MaxMs    = 0.0
                SumMs    = 0.0
                Status   = 'Pending'
            }
        }

        $pingSender = New-Object System.Net.NetworkInformation.Ping
        $buffer = [byte[]]::new(32)
        $pingOptions = New-Object System.Net.NetworkInformation.PingOptions(128, $true)
        $startTime = Get-Date
    }

    process {
        try {
            while ($true) {
                # Ping all hosts
                foreach ($target in $ComputerName) {
                    $stats = $hostStats[$target]
                    $stats.Sent++

                    try {
                        $reply = $pingSender.Send($target, $PingTimeoutMs, $buffer, $pingOptions)
                        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                            $stats.Received++
                            $stats.LastMs = $reply.RoundtripTime
                            $stats.SumMs += $reply.RoundtripTime
                            if ($reply.RoundtripTime -lt $stats.MinMs) { $stats.MinMs = $reply.RoundtripTime }
                            if ($reply.RoundtripTime -gt $stats.MaxMs) { $stats.MaxMs = $reply.RoundtripTime }
                            $stats.Status = 'Up'
                        } else {
                            $stats.LastMs = $null
                            $stats.Status = 'Down'
                        }
                    } catch {
                        $stats.LastMs = $null
                        $stats.Status = 'Down'
                    }
                }

                # Render dashboard
                Clear-Host
                $elapsed = (Get-Date) - $startTime
                $elapsedStr = '{0:hh\:mm\:ss}' -f $elapsed
                Write-Host "=== Ping Monitor === $($ComputerName.Count) host(s) === Elapsed: $elapsedStr === Refresh: ${RefreshInterval}s === Ctrl+C to stop ===" -ForegroundColor Cyan
                Write-Host ''

                # Table header
                $headerFmt = '{0,-28} {1,-8} {2,8} {3,8} {4,8} {5,8} {6,8} {7,8}'
                Write-Host ($headerFmt -f 'Host', 'Status', 'Last', 'Min', 'Avg', 'Max', 'Loss%', 'Sent') -ForegroundColor White
                Write-Host ($headerFmt -f '----', '------', '----', '---', '---', '---', '-----', '----') -ForegroundColor DarkGray

                foreach ($target in $ComputerName) {
                    $stats = $hostStats[$target]
                    $lossPercent = if ($stats.Sent -gt 0) { [math]::Round((($stats.Sent - $stats.Received) / $stats.Sent) * 100, 1) } else { 0 }
                    $avgMs = if ($stats.Received -gt 0) { [math]::Round($stats.SumMs / $stats.Received, 1) } else { $null }
                    $minDisplay = if ($stats.MinMs -lt [double]::MaxValue) { '{0}ms' -f [math]::Round($stats.MinMs, 0) } else { '-' }
                    $maxDisplay = if ($stats.Received -gt 0) { '{0}ms' -f [math]::Round($stats.MaxMs, 0) } else { '-' }
                    $avgDisplay = if ($null -ne $avgMs) { '{0}ms' -f $avgMs } else { '-' }
                    $lastDisplay = if ($null -ne $stats.LastMs) { '{0}ms' -f $stats.LastMs } else { '-' }

                    $statusColor = switch ($stats.Status) {
                        'Up'      { 'Green' }
                        'Down'    { 'Red' }
                        'Pending' { 'Yellow' }
                        default   { 'White' }
                    }

                    $lossColor = if ($lossPercent -eq 0) { 'Green' } elseif ($lossPercent -lt 10) { 'Yellow' } else { 'Red' }

                    Write-Host ('{0,-28} ' -f $target) -NoNewline
                    Write-Host ('{0,-8} ' -f $stats.Status) -ForegroundColor $statusColor -NoNewline
                    Write-Host ('{0,8} {1,8} {2,8} {3,8} ' -f $lastDisplay, $minDisplay, $avgDisplay, $maxDisplay) -NoNewline
                    Write-Host ('{0,8} ' -f "$lossPercent%") -ForegroundColor $lossColor -NoNewline
                    Write-Host ('{0,8}' -f $stats.Sent)
                }

                Write-Host ''
                $upCount = @($ComputerName | Where-Object { $hostStats[$_].Status -eq 'Up' }).Count
                $downCount = $ComputerName.Count - $upCount
                Write-Host "Summary: " -NoNewline
                Write-Host "$upCount Up" -ForegroundColor Green -NoNewline
                Write-Host ' / ' -NoNewline
                if ($downCount -gt 0) {
                    Write-Host "$downCount Down" -ForegroundColor Red
                } else {
                    Write-Host '0 Down' -ForegroundColor Green
                }

                Start-Sleep -Seconds $RefreshInterval
            }
        } catch {
            Write-Verbose "[$($MyInvocation.MyCommand)] Dashboard interrupted: $_"
        } finally {
            $pingSender.Dispose()

            # Final summary
            Write-Host ''
            Write-Host '=== Final Statistics ===' -ForegroundColor Cyan
            foreach ($target in $ComputerName) {
                $stats = $hostStats[$target]
                $lossPercent = if ($stats.Sent -gt 0) { [math]::Round((($stats.Sent - $stats.Received) / $stats.Sent) * 100, 1) } else { 0 }
                $avgMs = if ($stats.Received -gt 0) { [math]::Round($stats.SumMs / $stats.Received, 1) } else { 0 }
                Write-Host "  $target - Sent: $($stats.Sent), Received: $($stats.Received), Loss: ${lossPercent}%, Avg: ${avgMs}ms"
            }
            Write-Host ''
            Write-Host 'Ping Monitor stopped.' -ForegroundColor Cyan
        }
    }
}
