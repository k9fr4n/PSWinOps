#Requires -Version 5.1

function Get-NetworkStatistic {
    <#
        .SYNOPSIS
            Retrieves network connection statistics grouped by process

        .DESCRIPTION
            Aggregates TCP and UDP connection data by process, providing a summary view
            of how many connections each process holds in each state. Internally calls
            Get-NetworkConnection to collect raw connection data, then groups and counts
            by process name and connection state.

            This function is ideal for identifying which processes consume the most
            network connections or hold stale connections.

        .PARAMETER ComputerName
            One or more computer names to query. Accepts pipeline input by value and
            by property name. Defaults to the local machine ($env:COMPUTERNAME).

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote machines. Ignored for
            local machine queries.

        .PARAMETER Protocol
            Filter by protocol before aggregation. Valid values: TCP, UDP.
            By default both are included.

        .PARAMETER State
            Filter TCP connections by state before aggregation (e.g. Established, Listen).
            Ignored for UDP endpoints.

        .PARAMETER ProcessName
            Filter by owning process name before aggregation. Supports wildcards.

        .EXAMPLE
            Get-NetworkStatistic

            Returns connection count summary grouped by process on the local machine.

        .EXAMPLE
            Get-NetworkStatistic -ComputerName 'SRV01' -Protocol TCP

            Returns TCP connection statistics grouped by process on SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-NetworkStatistic

            Aggregates connection statistics by process across two remote servers.

        .EXAMPLE
            Get-NetworkStatistic -ProcessName 'w3wp'

            Shows connection breakdown for the IIS worker process only.

        .OUTPUTS
            PSWinOps.NetworkStatistic
            Summary of network connections per process including counts by state.

        .NOTES
            Author:        Franck SALLET
            Version:       3.0.0
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
        [string]$ProcessName
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network statistics aggregation"
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $timestamp = Get-Date -Format 'o'

                Write-Verbose "[$($MyInvocation.MyCommand)] Aggregating connections on '$targetComputer'"

                # Build splat for Get-NetworkConnection
                $connParams = @{
                    ComputerName = $targetComputer
                    ErrorAction  = 'Stop'
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $connParams['Credential'] = $Credential
                }
                if ($PSBoundParameters.ContainsKey('Protocol')) {
                    $connParams['Protocol'] = $Protocol
                }
                if ($PSBoundParameters.ContainsKey('State')) {
                    $connParams['State'] = $State
                }
                if ($PSBoundParameters.ContainsKey('ProcessName')) {
                    $connParams['ProcessName'] = $ProcessName
                }

                $connections = @(Get-NetworkConnection @connParams)

                if ($connections.Count -eq 0) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] No connections found on '$targetComputer'"
                    continue
                }

                # Group by ProcessName + ProcessId
                $grouped = $connections | Group-Object -Property ProcessName, ProcessId

                foreach ($group in $grouped) {
                    $items = $group.Group
                    $firstItem = $items[0]

                    [PSCustomObject]@{
                        PSTypeName       = 'PSWinOps.NetworkStatistic'
                        ComputerName     = $targetComputer
                        ProcessName      = $firstItem.ProcessName
                        ProcessId        = $firstItem.ProcessId
                        TcpEstablished   = @($items | Where-Object { $_.Protocol -eq 'TCP' -and $_.State -eq 'Established' }).Count
                        TcpListening     = @($items | Where-Object { $_.Protocol -eq 'TCP' -and $_.State -eq 'Listen' }).Count
                        TcpTimeWait      = @($items | Where-Object { $_.Protocol -eq 'TCP' -and $_.State -eq 'TimeWait' }).Count
                        TcpCloseWait     = @($items | Where-Object { $_.Protocol -eq 'TCP' -and $_.State -eq 'CloseWait' }).Count
                        TcpOther         = @($items | Where-Object { $_.Protocol -eq 'TCP' -and $_.State -notin @('Established', 'Listen', 'TimeWait', 'CloseWait') }).Count
                        UdpEndpoints     = @($items | Where-Object { $_.Protocol -eq 'UDP' }).Count
                        TotalConnections = $items.Count
                        Timestamp        = $timestamp
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network statistics aggregation"
    }
}
