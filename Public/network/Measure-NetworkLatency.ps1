#Requires -Version 5.1

function Measure-NetworkLatency {
    <#
        .SYNOPSIS
            Measures network latency to one or more hosts with statistical summary

        .DESCRIPTION
            Sends ICMP echo requests (ping) to target hosts and computes statistics:
            minimum, maximum, average, jitter (standard deviation), and packet loss
            percentage.

            Unlike Test-Connection, this function provides a statistical summary
            rather than individual ping results, making it ideal for network
            quality assessment.

        .PARAMETER ComputerName
            One or more target hostnames or IP addresses. Accepts pipeline input.

        .PARAMETER Count
            Number of ICMP echo requests to send per host. Default: 10.
            Valid range: 1-1000.

        .PARAMETER BufferSize
            Size of the ICMP payload in bytes. Default: 32. Valid range: 1-65500.

        .PARAMETER DelayMs
            Delay between pings in milliseconds. Default: 500. Valid range: 0-10000.

        .EXAMPLE
            Measure-NetworkLatency -ComputerName 'gateway.corp.local'

            Sends 10 pings and returns latency statistics.

        .EXAMPLE
            Measure-NetworkLatency -ComputerName '8.8.8.8', '1.1.1.1' -Count 50

            Compares latency to Google DNS and Cloudflare with 50 pings each.

        .EXAMPLE
            'SRV01', 'SRV02', 'SRV03' | Measure-NetworkLatency -Count 20

            Pipeline: measures latency to 3 servers with 20 pings each.

        .OUTPUTS
            PSWinOps.NetworkLatency

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required (ICMP may be blocked by firewall)

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.NetworkLatency')]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$Count = 10,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65500)]
        [int]$BufferSize = 32,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 10000)]
        [int]$DelayMs = 500
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting latency measurement (Count: $Count, Buffer: $BufferSize bytes)"
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Pinging '$targetComputer' ($Count times)"
                $pingSender = New-Object System.Net.NetworkInformation.Ping
                $buffer = [byte[]]::new($BufferSize)
                $pingOptions = New-Object System.Net.NetworkInformation.PingOptions(128, $true)

                $latencies = [System.Collections.Generic.List[double]]::new()
                $sent = 0
                $received = 0
                $resolvedAddress = $null

                for ($i = 0; $i -lt $Count; $i++) {
                    $sent++
                    try {
                        $reply = $pingSender.Send($targetComputer, 5000, $buffer, $pingOptions)
                        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                            $received++
                            $latencies.Add($reply.RoundtripTime)
                            if (-not $resolvedAddress) {
                                $resolvedAddress = $reply.Address.ToString()
                            }
                        }
                    } catch {
                        Write-Verbose "[$($MyInvocation.MyCommand)] Ping $($i + 1) to '$targetComputer' failed: $_"
                    }

                    if ($i -lt ($Count - 1) -and $DelayMs -gt 0) {
                        Start-Sleep -Milliseconds $DelayMs
                    }
                }

                $pingSender.Dispose()

                # Compute statistics
                $lost = $sent - $received
                $lossPercent = if ($sent -gt 0) { [math]::Round(($lost / $sent) * 100, 1) } else { 100.0 }

                if ($latencies.Count -gt 0) {
                    $minMs = [math]::Round(($latencies | Measure-Object -Minimum).Minimum, 1)
                    $maxMs = [math]::Round(($latencies | Measure-Object -Maximum).Maximum, 1)
                    $avgMs = [math]::Round(($latencies | Measure-Object -Average).Average, 1)

                    # Jitter = standard deviation
                    if ($latencies.Count -gt 1) {
                        $mean = ($latencies | Measure-Object -Average).Average
                        $sumSquares = ($latencies | ForEach-Object { ($_ - $mean) * ($_ - $mean) } | Measure-Object -Sum).Sum
                        $jitterMs = [math]::Round([math]::Sqrt($sumSquares / ($latencies.Count - 1)), 1)
                    } else {
                        $jitterMs = 0.0
                    }
                } else {
                    $minMs = $null
                    $maxMs = $null
                    $avgMs = $null
                    $jitterMs = $null
                }

                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.NetworkLatency'
                    ComputerName    = $targetComputer
                    IPAddress       = $resolvedAddress
                    Sent            = $sent
                    Received        = $received
                    Lost            = $lost
                    LossPercent     = $lossPercent
                    MinMs           = $minMs
                    MaxMs           = $maxMs
                    AvgMs           = $avgMs
                    JitterMs        = $jitterMs
                    Timestamp       = Get-Date -Format 'o'
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed latency measurement"
    }
}
