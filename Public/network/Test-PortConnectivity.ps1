#Requires -Version 5.1

function Test-PortConnectivity {
    <#
        .SYNOPSIS
            Tests TCP port connectivity on one or more remote hosts

        .DESCRIPTION
            Uses System.Net.Sockets.TcpClient to test whether specified TCP ports are
            reachable on target computers. Much faster than Test-NetConnection for
            bulk testing because it uses a configurable timeout and tests multiple
            port/host combinations sequentially.

            Returns structured objects suitable for pipeline processing and reporting.

        .PARAMETER ComputerName
            One or more target hostnames or IP addresses to test.
            Accepts pipeline input.

        .PARAMETER Port
            One or more TCP port numbers to test. Valid range: 1-65535.

        .PARAMETER TimeoutMs
            Connection timeout in milliseconds per port test. Default: 1000 (1 second).
            Valid range: 100-30000.

        .EXAMPLE
            Test-PortConnectivity -ComputerName 'SRV01' -Port 443

            Tests if port 443 is open on SRV01.

        .EXAMPLE
            Test-PortConnectivity -ComputerName 'SRV01', 'SRV02' -Port 80, 443, 3389

            Tests 3 ports on 2 servers (6 tests total).

        .EXAMPLE
            'WEB01', 'WEB02', 'WEB03' | Test-PortConnectivity -Port 443, 8080

            Pipeline input: tests 2 ports on 3 servers.

        .EXAMPLE
            Test-PortConnectivity -ComputerName '10.0.0.1' -Port 1..1024 -TimeoutMs 500

            Scans ports 1-1024 on a host with a 500ms timeout.

        .OUTPUTS
            PSWinOps.PortConnectivity

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/dotnet/api/system.net.sockets.tcpclient
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.PortConnectivity')]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int[]]$Port,

        [Parameter(Mandatory = $false)]
        [ValidateRange(100, 30000)]
        [int]$TimeoutMs = 1000
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting port connectivity tests (timeout: ${TimeoutMs}ms)"
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            foreach ($targetPort in $Port) {
                $tcpClient = $null
                try {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Testing ${targetComputer}:${targetPort}"
                    $tcpClient = New-Object System.Net.Sockets.TcpClient
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $connectTask = $tcpClient.ConnectAsync($targetComputer, $targetPort)
                    $completed = $connectTask.Wait($TimeoutMs)
                    $stopwatch.Stop()

                    if ($completed -and -not $connectTask.IsFaulted) {
                        [PSCustomObject]@{
                            PSTypeName     = 'PSWinOps.PortConnectivity'
                            ComputerName   = $targetComputer
                            Port           = $targetPort
                            Protocol       = 'TCP'
                            Open           = $true
                            ResponseTimeMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 1)
                            Timestamp      = Get-Date -Format 'o'
                        }
                    } else {
                        [PSCustomObject]@{
                            PSTypeName     = 'PSWinOps.PortConnectivity'
                            ComputerName   = $targetComputer
                            Port           = $targetPort
                            Protocol       = 'TCP'
                            Open           = $false
                            ResponseTimeMs = $null
                            Timestamp      = Get-Date -Format 'o'
                        }
                    }
                } catch {
                    [PSCustomObject]@{
                        PSTypeName     = 'PSWinOps.PortConnectivity'
                        ComputerName   = $targetComputer
                        Port           = $targetPort
                        Protocol       = 'TCP'
                        Open           = $false
                        ResponseTimeMs = $null
                        Timestamp      = Get-Date -Format 'o'
                    }
                } finally {
                    if ($tcpClient) {
                        $tcpClient.Close()
                        $tcpClient.Dispose()
                    }
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed port connectivity tests"
    }
}
