#Requires -Version 5.1

function Get-ARPTable {
    <#
        .SYNOPSIS
            Retrieves the ARP (Address Resolution Protocol) cache as structured objects

        .DESCRIPTION
            Parses the output of 'Get-NetNeighbor' cmdlet to return the local ARP cache
            as structured PowerShell objects. Each entry shows the IP address, MAC address,
            interface, and state of the ARP entry.

            For remote computers, the query is executed via Invoke-Command.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input.

        .PARAMETER Credential
            Optional credential for remote computer connections.

        .PARAMETER State
            Filter by ARP entry state. Valid values: Reachable, Stale, Permanent, Unreachable, Incomplete.

        .PARAMETER AddressFamily
            Filter by address family: IPv4 or IPv6. Default: IPv4.

        .EXAMPLE
            Get-ARPTable

            Returns the local ARP cache (IPv4 entries).

        .EXAMPLE
            Get-ARPTable -State Reachable

            Returns only reachable ARP entries.

        .EXAMPLE
            Get-ARPTable -ComputerName 'SRV01' -Credential (Get-Credential)

            Returns the ARP cache from a remote server.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-ARPTable

            Returns ARP tables from multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.ArpEntry

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Requires:      NetTCPIP module (built-in on Windows 8+/Server 2012+)
            Permissions:   No admin required for reading ARP cache

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-netneighbor
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ArpEntry')]
    param (
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Reachable', 'Stale', 'Permanent', 'Unreachable', 'Incomplete')]
        [string]$State,

        [Parameter(Mandatory = $false)]
        [ValidateSet('IPv4', 'IPv6')]
        [string]$AddressFamily = 'IPv4'
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting ARP table query"

        $queryScriptBlock = {
            param([string]$QueryState, [string]$QueryAddressFamily)

            $getParams = @{
                ErrorAction = 'Stop'
            }

            if ($QueryAddressFamily -eq 'IPv4') {
                $getParams['AddressFamily'] = 2
            } elseif ($QueryAddressFamily -eq 'IPv6') {
                $getParams['AddressFamily'] = 23
            }

            $entries = Get-NetNeighbor @getParams

            if ($QueryState) {
                $entries = @($entries | Where-Object { $_.State -eq $QueryState })
            }

            # Get interface aliases for enrichment
            $interfaces = @{}
            try {
                Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
                    $interfaces[$_.ifIndex] = $_.Name
                }
            } catch {
                Write-Verbose "Failed to enumerate network adapters: $_"
            }

            foreach ($entry in $entries) {
                [PSCustomObject]@{
                    IPAddress      = $entry.IPAddress
                    LinkLayerAddr  = if ($entry.LinkLayerAddress) {
                        # Get-NetNeighbor returns dash-separated MACs (e.g. '00-50-56-86-4E-A4')
                        # Normalize: strip all non-hex chars, then insert colons every 2 chars
                        $hex = $entry.LinkLayerAddress -replace '[^0-9A-Fa-f]', ''
                        if ($hex.Length -ge 2) {
                            ($hex -replace '(..)', '$1:').TrimEnd(':')
                        } else {
                            $hex
                        }
                    } else {
                        ''
                    }
                    State          = [string]$entry.State
                    InterfaceAlias = if ($interfaces.ContainsKey($entry.InterfaceIndex)) {
                        $interfaces[$entry.InterfaceIndex]
                    } else {
                        "Index $($entry.InterfaceIndex)"
                    }
                    InterfaceIndex = $entry.InterfaceIndex
                    AddressFamily  = if ($entry.AddressFamily -eq 2) {
                        'IPv4'
                    } elseif ($entry.AddressFamily -eq 23) {
                        'IPv6'
                    } else {
                        [string]$entry.AddressFamily
                    }
                }
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $timestamp = Get-Date -Format 'o'

                Write-Verbose "[$($MyInvocation.MyCommand)] Querying ARP table on '$targetComputer'"

                $queryArgs = @(
                    $(if ($State) {
                            $State
                        } else {
                            $null
                        })
                    $AddressFamily
                )

                $rawResults = Invoke-RemoteOrLocal -ComputerName $targetComputer -ScriptBlock $queryScriptBlock -ArgumentList $queryArgs -Credential $Credential

                foreach ($entry in $rawResults) {
                    [PSCustomObject]@{
                        PSTypeName     = 'PSWinOps.ArpEntry'
                        ComputerName   = $targetComputer
                        IPAddress      = $entry.IPAddress
                        MACAddress     = $entry.LinkLayerAddr
                        State          = $entry.State
                        InterfaceAlias = $entry.InterfaceAlias
                        InterfaceIndex = $entry.InterfaceIndex
                        AddressFamily  = $entry.AddressFamily
                        Timestamp      = $timestamp
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed ARP table query"
    }
}
