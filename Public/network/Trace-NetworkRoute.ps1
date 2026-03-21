#Requires -Version 5.1

function Trace-NetworkRoute {
    <#
    .SYNOPSIS
        Performs a traceroute to a target host and returns structured hop-by-hop results.
    .DESCRIPTION
        Sends ICMP packets with incrementing TTL values to trace the network path
        to a destination. Each hop is returned as a structured object with hop number,
        IP address, hostname (via reverse DNS), and round-trip latency.

        Uses System.Net.NetworkInformation.Ping with controlled TTL values,
        which is more reliable and parseable than the native tracert.exe.
    .PARAMETER ComputerName
        One or more target hostnames or IP addresses to trace. Accepts pipeline input.
    .PARAMETER MaxHops
        Maximum number of hops (TTL). Default: 30. Valid range: 1-128.
    .PARAMETER TimeoutMs
        Timeout per hop in milliseconds. Default: 3000. Valid range: 500-30000.
    .PARAMETER PingsPerHop
        Number of pings per hop for latency averaging. Default: 3. Valid range: 1-10.
    .PARAMETER ResolveHostnames
        Attempt reverse DNS lookup for each hop IP. Default: true.
        Disable for faster traces when hostnames are not needed.
    .EXAMPLE
        Trace-NetworkRoute -ComputerName '8.8.8.8'

        Traces the route to Google DNS.
    .EXAMPLE
        Trace-NetworkRoute -ComputerName 'srv01.corp.local' -MaxHops 15

        Traces route to an internal server with max 15 hops.
    .EXAMPLE
        '8.8.8.8', '1.1.1.1' | Trace-NetworkRoute -ResolveHostnames:$false

        Traces routes to two targets without reverse DNS (faster).
    .OUTPUTS
    PSWinOps.TraceRouteHop
    .NOTES
        Author:        Franck SALLET
        Version:       1.0.0
        Last Modified: 2026-03-21
        Requires:      PowerShell 5.1+ / Windows only
        Permissions:   No admin required (ICMP may be blocked by firewall)
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.TraceRouteHop')]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName', 'Destination')]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 128)]
        [int]$MaxHops = 30,

        [Parameter(Mandatory = $false)]
        [ValidateRange(500, 30000)]
        [int]$TimeoutMs = 3000,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]$PingsPerHop = 3,

        [Parameter(Mandatory = $false)]
        [bool]$ResolveHostnames = $true
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting route trace (MaxHops: $MaxHops, Timeout: ${TimeoutMs}ms)"
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Tracing route to '$targetComputer'"

                # Resolve target IP first
                try {
                    $targetIP = [System.Net.Dns]::GetHostAddresses($targetComputer) |
                        Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                        Select-Object -First 1
                    if (-not $targetIP) {
                        Write-Error "[$($MyInvocation.MyCommand)] Cannot resolve '$targetComputer' to an IPv4 address"
                        continue
                    }
                    $targetIPString = $targetIP.ToString()
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] DNS resolution failed for '$targetComputer': $_"
                    continue
                }

                $pingSender = New-Object System.Net.NetworkInformation.Ping
                $buffer = [byte[]]::new(32)
                $timestamp = Get-Date -Format 'o'
                $reachedTarget = $false

                for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
                    $hopIP = $null
                    $latencies = [System.Collections.Generic.List[double]]::new()
                    $timedOut = $true

                    $pingOptions = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)

                    for ($p = 0; $p -lt $PingsPerHop; $p++) {
                        try {
                            $reply = $pingSender.Send($targetIPString, $TimeoutMs, $buffer, $pingOptions)

                            if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::TtlExpired -or
                                $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                                $timedOut = $false
                                $hopIP = $reply.Address.ToString()
                                $latencies.Add($reply.RoundtripTime)
                            }
                        } catch {
                            Write-Verbose "[$($MyInvocation.MyCommand)] Ping to '$targetIPString' (TTL=$ttl, attempt $($p+1)) failed: $_"
                        }
                    }

                    # Resolve hostname if requested
                    $hostname = $null
                    if ($hopIP -and $ResolveHostnames) {
                        try {
                            $hostEntry = [System.Net.Dns]::GetHostEntry($hopIP)
                            $hostname = $hostEntry.HostName
                        } catch {
                            $hostname = $null
                        }
                    }

                    # Compute latency stats for this hop
                    $avgMs = $null
                    $minMs = $null
                    $maxMs = $null
                    if ($latencies.Count -gt 0) {
                        $avgMs = [math]::Round(($latencies | Measure-Object -Average).Average, 1)
                        $minMs = [math]::Round(($latencies | Measure-Object -Minimum).Minimum, 1)
                        $maxMs = [math]::Round(($latencies | Measure-Object -Maximum).Maximum, 1)
                    }

                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.TraceRouteHop'
                        Destination  = $targetComputer
                        Hop          = $ttl
                        IPAddress    = if ($hopIP) { $hopIP } else { '*' }
                        Hostname     = if ($hostname) { $hostname } else { '' }
                        AvgMs        = $avgMs
                        MinMs        = $minMs
                        MaxMs        = $maxMs
                        Status       = if ($timedOut) { 'TimedOut' } elseif ($hopIP -eq $targetIPString) { 'Reached' } else { 'Hop' }
                        Timestamp    = $timestamp
                    }

                    # Stop if we reached the destination
                    if ($hopIP -eq $targetIPString) {
                        $reachedTarget = $true
                        break
                    }
                }

                $pingSender.Dispose()

                if (-not $reachedTarget) {
                    Write-Warning "[$($MyInvocation.MyCommand)] Destination '$targetComputer' not reached within $MaxHops hops"
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed tracing '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed route trace"
    }
}
