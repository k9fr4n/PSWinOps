#Requires -Version 5.1

function Get-NetworkConnection {
    <#
        .SYNOPSIS
            Retrieves TCP and UDP network connections enriched with process info

        .DESCRIPTION
            Returns one object per TCP or UDP connection on the target machine, including
            local and remote address/port, connection state, and the owning process name.
            Supports both local and remote queries via WinRM. Filtering is available on
            protocol, state, address, port, and process name.

            For the local machine, cmdlets are called directly. For remote machines,
            the query is executed via Invoke-Command with WinRM.

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

        .EXAMPLE
            Get-NetworkConnection

            Returns all TCP and UDP connections on the local machine.

        .EXAMPLE
            Get-NetworkConnection -Protocol TCP -State Established

            Returns only established TCP connections on the local machine.

        .EXAMPLE
            Get-NetworkConnection -ComputerName 'SRV01', 'SRV02' -Protocol TCP -State Listen

            Returns listening TCP connections on two remote servers.

        .EXAMPLE
            Get-NetworkConnection -ProcessName 'svchost' -LocalPort 443

            Returns connections on local port 443 owned by svchost.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-NetworkConnection -Credential (Get-Credential) -Protocol TCP

            Queries multiple servers via pipeline with explicit credentials.

        .OUTPUTS
            PSWinOps.NetworkConnection
            One object per connection with ComputerName, Protocol, LocalAddress,
            LocalPort, RemoteAddress, RemotePort, State, ProcessId, ProcessName,
            and Timestamp properties.

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-23
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required for basic queries
            Remote:        Requires WinRM / WS-Man enabled on target machines

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-nettcpconnection
    #>

    [CmdletBinding()]
    [OutputType('PSWinOps.NetworkConnection')]
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
        [string]$ProcessName
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network connection query"

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

        foreach ($targetComputer in $ComputerName) {
            try {
                $timestamp = Get-Date -Format 'o'

                Write-Verbose "[$($MyInvocation.MyCommand)] Querying '$targetComputer'"

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

                $rawResults = Invoke-RemoteOrLocal -ComputerName $targetComputer -ScriptBlock $queryScriptBlock -ArgumentList $queryArgs -Credential $Credential

                foreach ($entry in $rawResults) {
                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.NetworkConnection'
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
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network connection query"
    }
}
