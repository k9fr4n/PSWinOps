#Requires -Version 5.1

function Get-NetworkAdapter {
    <#
        .SYNOPSIS
            Retrieves consolidated network adapter information including IP, DNS, gateway, and speed

        .DESCRIPTION
            Combines data from Get-NetAdapter, Get-NetIPAddress, Get-NetIPConfiguration, and
            Get-DnsClientServerAddress into a single structured view per adapter.

            Replaces the need to run 4 separate cmdlets and manually correlate results.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input.

        .PARAMETER Credential
            Optional credential for remote computer connections.

        .PARAMETER IncludeDisabled
            Include network adapters that are in a disabled or disconnected state.
            By default, only 'Up' adapters are returned.

        .PARAMETER InterfaceName
            Filter by adapter name. Supports wildcards. Example: 'Ethernet*', 'Wi-Fi'.

        .EXAMPLE
            Get-NetworkAdapter

            Returns all active network adapters on the local machine.

        .EXAMPLE
            Get-NetworkAdapter -IncludeDisabled

            Returns all adapters including disabled ones.

        .EXAMPLE
            Get-NetworkAdapter -ComputerName 'SRV01', 'SRV02' -Credential (Get-Credential)

            Returns adapter info from two remote servers.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-NetworkAdapter -InterfaceName 'Ethernet*'

            Pipeline: returns only Ethernet adapters from 2 servers.

        .OUTPUTS
            PSWinOps.NetworkAdapterInfo

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Requires:      NetAdapter, NetTCPIP modules (built-in)
            Permissions:   No admin required for local, admin for remote

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.NetworkAdapterInfo')]
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
        [switch]$IncludeDisabled,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$InterfaceName
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network adapter query"

        $queryScriptBlock = {
            param([bool]$ShowDisabled, [string]$FilterName)

            $adapters = if ($ShowDisabled) {
                Get-NetAdapter -ErrorAction SilentlyContinue
            } else {
                Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            }

            if ($FilterName) {
                $adapters = @($adapters | Where-Object { $_.Name -like $FilterName })
            }

            # Build lookup tables
            $ipAddresses = @{}
            Get-NetIPAddress -ErrorAction SilentlyContinue | ForEach-Object {
                if (-not $ipAddresses.ContainsKey($_.InterfaceIndex)) {
                    $ipAddresses[$_.InterfaceIndex] = [System.Collections.Generic.List[PSObject]]::new()
                }
                $ipAddresses[$_.InterfaceIndex].Add($_)
            }

            $dnsServers = @{}
            Get-DnsClientServerAddress -ErrorAction SilentlyContinue | ForEach-Object {
                if (-not $dnsServers.ContainsKey($_.InterfaceIndex)) {
                    $dnsServers[$_.InterfaceIndex] = [System.Collections.Generic.List[string]]::new()
                }
                foreach ($addr in $_.ServerAddresses) {
                    if (-not $dnsServers[$_.InterfaceIndex].Contains($addr)) {
                        $dnsServers[$_.InterfaceIndex].Add($addr)
                    }
                }
            }

            $defaultGateways = @{}
            Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object {
                $defaultGateways[$_.InterfaceIndex] = $_.NextHop
            }

            foreach ($adapter in $adapters) {
                $idx = $adapter.ifIndex

                $ipv4Addrs = @($ipAddresses[$idx] | Where-Object { $_.AddressFamily -eq 2 })
                $ipv6Addrs = @($ipAddresses[$idx] | Where-Object { $_.AddressFamily -eq 23 })

                [PSCustomObject]@{
                    Name           = $adapter.Name
                    Description    = $adapter.InterfaceDescription
                    Status         = [string]$adapter.Status
                    Speed          = if ($adapter.LinkSpeed) {
                        $adapter.LinkSpeed
                    } else {
                        '-'
                    }
                    MacAddress     = $adapter.MacAddress
                    IPv4Address    = ($ipv4Addrs | ForEach-Object { $_.IPAddress }) -join ', '
                    SubnetPrefix   = ($ipv4Addrs | ForEach-Object { $_.PrefixLength }) -join ', '
                    IPv6Address    = ($ipv6Addrs | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | ForEach-Object { $_.IPAddress }) -join ', '
                    Gateway        = if ($defaultGateways[$idx]) {
                        $defaultGateways[$idx]
                    } else {
                        '-'
                    }
                    DnsServers     = ($dnsServers[$idx]) -join ', '
                    MTU            = $adapter.MtuSize
                    InterfaceIndex = $idx
                    MediaType      = $adapter.MediaType
                    DriverVersion  = $adapter.DriverVersion
                    VlanID         = $adapter.VlanID
                }
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $timestamp = Get-Date -Format 'o'

                Write-Verbose "[$($MyInvocation.MyCommand)] Querying adapters on '$targetComputer'"

                $queryArgs = @(
                    $IncludeDisabled.IsPresent
                    $(if ($InterfaceName) {
                            $InterfaceName
                        } else {
                            $null
                        })
                )

                $rawResults = Invoke-RemoteOrLocal -ComputerName $targetComputer -ScriptBlock $queryScriptBlock -ArgumentList $queryArgs -Credential $Credential

                foreach ($entry in $rawResults) {
                    [PSCustomObject]@{
                        PSTypeName     = 'PSWinOps.NetworkAdapterInfo'
                        ComputerName   = $targetComputer
                        Name           = $entry.Name
                        Description    = $entry.Description
                        Status         = $entry.Status
                        Speed          = $entry.Speed
                        MacAddress     = $entry.MacAddress
                        IPv4Address    = $entry.IPv4Address
                        SubnetPrefix   = $entry.SubnetPrefix
                        IPv6Address    = $entry.IPv6Address
                        Gateway        = $entry.Gateway
                        DnsServers     = $entry.DnsServers
                        MTU            = $entry.MTU
                        InterfaceIndex = $entry.InterfaceIndex
                        MediaType      = $entry.MediaType
                        DriverVersion  = $entry.DriverVersion
                        VlanID         = $entry.VlanID
                        Timestamp      = $timestamp
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network adapter query"
    }
}
