#Requires -Version 5.1

function Get-NetworkStatistic {
    <#
    .SYNOPSIS
        Retrieves TCP and UDP connection statistics on one or more Windows computers.
    .DESCRIPTION
        Queries active network connections using Get-NetTCPConnection and Get-NetUDPEndpoint,
        then enriches each entry with the owning process name. Supports filtering by protocol,
        connection state, local/remote address, local/remote port, and process name.

        For the local machine, cmdlets are called directly. For remote machines, the query
        is executed via Invoke-Command, which requires WinRM / WS-Man enabled on the target.
    .PARAMETER ComputerName
        One or more computer names to query. Accepts pipeline input by value and
        by property name. Defaults to the local machine ($env:COMPUTERNAME).
    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for
        local machine queries.
    .PARAMETER Protocol
        Filter by protocol. Valid values: TCP, UDP. By default both are returned.
    .PARAMETER State
        Filter TCP connections by state (e.g. Established, Listen, TimeWait, CloseWait).
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
    .PARAMETER Continuous
        Enable real-time auto-refresh mode. The function loops, clears the screen,
        and re-queries all target computers at each interval. Output is written
        directly to the host (not to the pipeline). Press Ctrl+C to stop.
    .PARAMETER RefreshInterval
        Refresh interval in seconds when using -Continuous. Default: 2.
        Valid range: 1–300 seconds.
    .EXAMPLE
        Get-NetworkStatistic

        Returns all TCP and UDP connections on the local machine.
    .EXAMPLE
        Get-NetworkStatistic -Protocol TCP -State Established

        Returns only established TCP connections on the local machine.
    .EXAMPLE
        Get-NetworkStatistic -ComputerName 'SRV01', 'SRV02' -Protocol TCP -State Listen

        Returns listening TCP connections on two remote servers.
    .EXAMPLE
        Get-NetworkStatistic -ProcessName 'svchost' -LocalPort 443

        Returns connections on local port 443 owned by svchost.
    .EXAMPLE
        'SRV01', 'SRV02' | Get-NetworkStatistic -Credential (Get-Credential) -Protocol TCP

        Queries multiple servers via pipeline with explicit credentials.
    .EXAMPLE
        Get-NetworkStatistic -Continuous

        Starts real-time monitoring of all network connections on the local machine,
        refreshing every 2 seconds. Press Ctrl+C to stop.
    .EXAMPLE
        Get-NetworkStatistic -Continuous -RefreshInterval 5 -Protocol TCP -State Established

        Monitors only established TCP connections with a 5-second refresh interval.
    .EXAMPLE
        Get-NetworkStatistic -ComputerName 'SRV01', 'SRV02' -Continuous -Protocol TCP

        Monitors TCP connections on two remote servers in real time.
    .OUTPUTS
    PSWinOps.NetworkStatistic
        Network connection details including protocol, addresses, ports, state, and process info.
    .NOTES
        Author:        Franck SALLET
        Version:       1.1.0
        Last Modified: 2026-03-21
        Requires:      PowerShell 5.1+ / Windows only
        Permissions:   No admin required for basic queries
        Remote:        Requires WinRM / WS-Man enabled on target machines

        Inspired by AdminToolbox.Networking Get-NetworkStatistics by TheTaylorLee.
    .LINK
    https://docs.microsoft.com/en-us/powershell/module/nettcpip/get-nettcpconnection
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.NetworkStatistic')]
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
        [switch]$Continuous,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$RefreshInterval = 2
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network statistics query"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
        $hasCredential = $PSBoundParameters.ContainsKey('Credential')

        # When -Continuous is used, collect all computers first, then loop in end {}
        if ($Continuous) {
            $continuousComputers = [System.Collections.Generic.List[string]]::new()
        }

        # Build the scriptblock that collects connections (runs locally or via Invoke-Command)
        $queryScriptBlock = {
            param(
                [string[]]$QueryProtocol,
                [string[]]$QueryState,
                [string]$QueryLocalAddress,
                [int]$QueryLocalPort,
                [string]$QueryRemoteAddress,
                [int]$QueryRemotePort,
                [string]$QueryProcessName
            )

            $results = [System.Collections.Generic.List[PSObject]]::new()

            # Build process lookup table once (cast to [int] — OwningProcess is UInt32,
            # Process.Id is Int32; mismatched key types cause lookup failures)
            $processLookup = @{}
            foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
                $pidKey = [int]$proc.Id
                if (-not $processLookup.ContainsKey($pidKey)) {
                    $processLookup[$pidKey] = $proc.ProcessName
                }
            }

            # TCP connections
            if ($QueryProtocol -contains 'TCP') {
                $tcpParams = @{ ErrorAction = 'SilentlyContinue' }
                if ($QueryState) {
                    $tcpParams['State'] = $QueryState
                }
                $tcpConnections = Get-NetTCPConnection @tcpParams

                foreach ($conn in $tcpConnections) {
                    $ownerPid = [int]$conn.OwningProcess
                    $procName = if ($processLookup.ContainsKey($ownerPid)) {
                        $processLookup[$ownerPid]
                    } else {
                        'Unknown'
                    }

                    $obj = [PSCustomObject]@{
                        Protocol      = 'TCP'
                        LocalAddress  = $conn.LocalAddress
                        LocalPort     = $conn.LocalPort
                        RemoteAddress = $conn.RemoteAddress
                        RemotePort    = $conn.RemotePort
                        State         = [string]$conn.State
                        ProcessId     = $conn.OwningProcess
                        ProcessName   = $procName
                    }
                    $results.Add($obj)
                }
            }

            # UDP endpoints
            if ($QueryProtocol -contains 'UDP') {
                $udpEndpoints = Get-NetUDPEndpoint -ErrorAction SilentlyContinue

                foreach ($ep in $udpEndpoints) {
                    $ownerPid = [int]$ep.OwningProcess
                    $procName = if ($processLookup.ContainsKey($ownerPid)) {
                        $processLookup[$ownerPid]
                    } else {
                        'Unknown'
                    }

                    $obj = [PSCustomObject]@{
                        Protocol      = 'UDP'
                        LocalAddress  = $ep.LocalAddress
                        LocalPort     = $ep.LocalPort
                        RemoteAddress = '*'
                        RemotePort    = 0
                        State         = 'Stateless'
                        ProcessId     = $ep.OwningProcess
                        ProcessName   = $procName
                    }
                    $results.Add($obj)
                }
            }

            # Apply client-side filters
            $filtered = $results

            if ($QueryLocalAddress) {
                $filtered = @($filtered | Where-Object { $_.LocalAddress -like $QueryLocalAddress })
            }
            if ($QueryLocalPort -gt 0) {
                $filtered = @($filtered | Where-Object { $_.LocalPort -eq $QueryLocalPort })
            }
            if ($QueryRemoteAddress) {
                $filtered = @($filtered | Where-Object { $_.RemoteAddress -like $QueryRemoteAddress })
            }
            if ($QueryRemotePort -gt 0) {
                $filtered = @($filtered | Where-Object { $_.RemotePort -eq $QueryRemotePort })
            }
            if ($QueryProcessName) {
                $filtered = @($filtered | Where-Object { $_.ProcessName -like $QueryProcessName })
            }

            $filtered
        }
    }

    process {
        # In -Continuous mode, just collect computer names for the end {} block
        if ($Continuous) {
            foreach ($c in $ComputerName) { $continuousComputers.Add($c) }
            return
        }

        foreach ($targetComputer in $ComputerName) {
            try {
                $isLocal = $localNames -contains $targetComputer
                $timestamp = Get-Date -Format 'o'

                Write-Verbose "[$($MyInvocation.MyCommand)] Querying '$targetComputer' (local: $isLocal)"

                $queryArgs = @(
                    , $Protocol
                    $(if ($State) {
                            , $State
                        } else {
                            , $null
                        })
                    $(if ($PSBoundParameters.ContainsKey('LocalAddress')) {
                            $LocalAddress
                        } else {
                            $null
                        })
                    $(if ($PSBoundParameters.ContainsKey('LocalPort')) {
                            $LocalPort
                        } else {
                            0
                        })
                    $(if ($PSBoundParameters.ContainsKey('RemoteAddress')) {
                            $RemoteAddress
                        } else {
                            $null
                        })
                    $(if ($PSBoundParameters.ContainsKey('RemotePort')) {
                            $RemotePort
                        } else {
                            0
                        })
                    $(if ($PSBoundParameters.ContainsKey('ProcessName')) {
                            $ProcessName
                        } else {
                            $null
                        })
                )

                if ($isLocal) {
                    $rawResults = & $queryScriptBlock @queryArgs
                } else {
                    $invokeParams = @{
                        ComputerName = $targetComputer
                        ScriptBlock  = $queryScriptBlock
                        ArgumentList = $queryArgs
                        ErrorAction  = 'Stop'
                    }
                    if ($hasCredential) {
                        $invokeParams['Credential'] = $Credential
                    }
                    $rawResults = Invoke-Command @invokeParams
                }

                foreach ($entry in $rawResults) {
                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.NetworkStatistic'
                        ComputerName  = $targetComputer
                        Protocol      = $entry.Protocol
                        LocalAddress  = $entry.LocalAddress
                        LocalPort     = $entry.LocalPort
                        RemoteAddress = $entry.RemoteAddress
                        RemotePort    = $entry.RemotePort
                        State         = $entry.State
                        ProcessId     = $entry.ProcessId
                        ProcessName   = $entry.ProcessName
                        Timestamp     = $timestamp
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        if ($Continuous) {
            Write-Host "Network Statistics Monitor — Refresh every ${RefreshInterval}s — Press Ctrl+C to stop" -ForegroundColor Cyan
            try {
                while ($true) {
                    $allResults = [System.Collections.Generic.List[PSObject]]::new()

                    foreach ($targetComputer in $continuousComputers) {
                        try {
                            $isLocal = $localNames -contains $targetComputer
                            $timestamp = Get-Date -Format 'o'

                            $queryArgs = @(
                                , $Protocol
                                $(if ($State) { , $State } else { , $null })
                                $(if ($PSBoundParameters.ContainsKey('LocalAddress'))  { $LocalAddress  } else { $null })
                                $(if ($PSBoundParameters.ContainsKey('LocalPort'))     { $LocalPort     } else { 0 })
                                $(if ($PSBoundParameters.ContainsKey('RemoteAddress')) { $RemoteAddress } else { $null })
                                $(if ($PSBoundParameters.ContainsKey('RemotePort'))    { $RemotePort    } else { 0 })
                                $(if ($PSBoundParameters.ContainsKey('ProcessName'))   { $ProcessName   } else { $null })
                            )

                            if ($isLocal) {
                                $rawResults = & $queryScriptBlock @queryArgs
                            } else {
                                $invokeParams = @{
                                    ComputerName = $targetComputer
                                    ScriptBlock  = $queryScriptBlock
                                    ArgumentList = $queryArgs
                                    ErrorAction  = 'Stop'
                                }
                                if ($hasCredential) {
                                    $invokeParams['Credential'] = $Credential
                                }
                                $rawResults = Invoke-Command @invokeParams
                            }

                            foreach ($entry in $rawResults) {
                                $allResults.Add([PSCustomObject]@{
                                    PSTypeName    = 'PSWinOps.NetworkStatistic'
                                    ComputerName  = $targetComputer
                                    Protocol      = $entry.Protocol
                                    LocalAddress  = $entry.LocalAddress
                                    LocalPort     = $entry.LocalPort
                                    RemoteAddress = $entry.RemoteAddress
                                    RemotePort    = $entry.RemotePort
                                    State         = $entry.State
                                    ProcessId     = $entry.ProcessId
                                    ProcessName   = $entry.ProcessName
                                    Timestamp     = $timestamp
                                })
                            }
                        } catch {
                            Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
                        }
                    }

                    Clear-Host
                    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    $computerList = $continuousComputers -join ', '
                    Write-Host "=== Network Statistics on $computerList — $now — ${RefreshInterval}s refresh — Ctrl+C to stop ===" -ForegroundColor Cyan
                    Write-Host "Total connections: $($allResults.Count)" -ForegroundColor DarkGray
                    Write-Host ''

                    if ($allResults.Count -gt 0) {
                        $allResults | Sort-Object ComputerName, ProcessName, Protocol, RemoteAddress |
                            Format-Table -AutoSize |
                            Out-Host
                    } else {
                        Write-Host '(No matching connections found)' -ForegroundColor Yellow
                    }

                    Start-Sleep -Seconds $RefreshInterval
                }
            } catch {
                # Ctrl+C breaks the loop
            } finally {
                Write-Host ''
                Write-Host 'Network Statistics Monitor stopped.' -ForegroundColor Cyan
            }
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network statistics query"
    }
}
