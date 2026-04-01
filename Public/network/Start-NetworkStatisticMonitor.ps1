#Requires -Version 5.1

function Start-NetworkStatisticMonitor {
    <#
        .SYNOPSIS
            Monitors network connections in real time with auto-refresh display

        .DESCRIPTION
            Provides a live, auto-refreshing console view of TCP and UDP network connections.
            Internally calls Get-NetworkConnection at each refresh interval and displays the
            results in a formatted table using Write-Host. Output goes to the console only,
            not the pipeline, to support the interactive monitoring experience.

            Press Ctrl+C to stop the monitor. All filtering parameters from
            Get-NetworkConnection are available (Protocol, State, LocalPort, etc.).

        .PARAMETER ComputerName
            One or more computer names to monitor. Accepts pipeline input by value and
            by property name. Defaults to the local machine ($env:COMPUTERNAME).

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote machines via WinRM.
            Ignored for local machine queries.

        .PARAMETER Protocol
            Filter by protocol. Valid values: TCP, UDP. By default both are shown.

        .PARAMETER State
            Filter TCP connections by state (e.g. Established, Listen, TimeWait).
            Ignored for UDP endpoints (UDP is stateless).

        .PARAMETER LocalAddress
            Filter by local IP address. Supports wildcards.

        .PARAMETER LocalPort
            Filter by local port number.

        .PARAMETER RemoteAddress
            Filter by remote IP address. Supports wildcards.

        .PARAMETER RemotePort
            Filter by remote port number.

        .PARAMETER ProcessName
            Filter by owning process name. Supports wildcards.

        .PARAMETER RefreshInterval
            Refresh interval in seconds. Default: 2. Valid range: 1-300 seconds.

        .EXAMPLE
            Start-NetworkStatisticMonitor

            Starts real-time monitoring of all network connections on the local machine,
            refreshing every 2 seconds. Press Ctrl+C to stop.

        .EXAMPLE
            Start-NetworkStatisticMonitor -Protocol TCP -State Established -RefreshInterval 5

            Monitors only established TCP connections with a 5-second refresh interval.

        .EXAMPLE
            Start-NetworkStatisticMonitor -ComputerName 'SRV01', 'SRV02' -Protocol TCP

            Monitors TCP connections on two remote servers in real time.

        .OUTPUTS
            None
            This function writes directly to the host for interactive display.
            It does not produce pipeline output.

        .NOTES
            Author:        Franck SALLET
            Version:       1.1.0
            Last Modified: 2026-03-23
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required for basic queries
            Remote:        Requires WinRM / WS-Man enabled on target machines

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-nettcpconnection
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Write-Host is intentional for interactive console monitoring display')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'This function is read-only (monitoring); it does not modify system state')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateSet('TCP', 'UDP')]
        [string[]]$Protocol = @('TCP', 'UDP'),

        [Parameter(Mandatory = $false)]
        [ValidateSet('Bound', 'Closed', 'CloseWait', 'Closing', 'DeleteTCB',
            'Established', 'FinWait1', 'FinWait2', 'LastAck', 'Listen',
            'SynReceived', 'SynSent', 'TimeWait')]
        [string[]]$State,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$LocalAddress,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$LocalPort,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$RemoteAddress,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$RemotePort,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$ProcessName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$RefreshInterval = 2
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network statistics monitor"

        # Collect all computer names from pipeline before starting the loop
        $allComputers = [System.Collections.Generic.List[string]]::new()

        # Build the splat for Get-NetworkConnection (all filter params except ComputerName)
        $getStatParams = @{}
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $getStatParams['Credential'] = $Credential
        }
        if ($PSBoundParameters.ContainsKey('Protocol')) {
            $getStatParams['Protocol'] = $Protocol
        }
        if ($PSBoundParameters.ContainsKey('State')) {
            $getStatParams['State'] = $State
        }
        if ($PSBoundParameters.ContainsKey('LocalAddress')) {
            $getStatParams['LocalAddress'] = $LocalAddress
        }
        if ($PSBoundParameters.ContainsKey('LocalPort')) {
            $getStatParams['LocalPort'] = $LocalPort
        }
        if ($PSBoundParameters.ContainsKey('RemoteAddress')) {
            $getStatParams['RemoteAddress'] = $RemoteAddress
        }
        if ($PSBoundParameters.ContainsKey('RemotePort')) {
            $getStatParams['RemotePort'] = $RemotePort
        }
        if ($PSBoundParameters.ContainsKey('ProcessName')) {
            $getStatParams['ProcessName'] = $ProcessName
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            $allComputers.Add($computer)
        }
    }

    end {
        $computerList = $allComputers -join ', '
        Write-Host "Network Statistics Monitor - Refresh every ${RefreshInterval}s - Press Ctrl+C to stop" -ForegroundColor Cyan

        try {
            while ($true) {
                $allResults = @(Get-NetworkConnection -ComputerName $allComputers.ToArray() @getStatParams -ErrorAction SilentlyContinue)

                Clear-Host
                $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Write-Host "=== Network Statistics on $computerList - $now - ${RefreshInterval}s refresh - Ctrl+C to stop ===" -ForegroundColor Cyan
                Write-Host "Total connections: $($allResults.Count)" -ForegroundColor DarkGray
                Write-Host ''

                if ($allResults.Count -gt 0) {
                    $allResults |
                        Sort-Object ComputerName, ProcessName, Protocol, RemoteAddress |
                        Format-Table -AutoSize |
                        Out-Host
                } else {
                    Write-Host '(No matching connections found)' -ForegroundColor Yellow
                }

                Start-Sleep -Seconds $RefreshInterval
            }
        } catch {
            Write-Verbose "[$($MyInvocation.MyCommand)] Monitoring interrupted: $_"
        } finally {
            Write-Host ''
            Write-Host 'Network Statistics Monitor stopped.' -ForegroundColor Cyan
        }
    }
}
