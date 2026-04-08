#Requires -Version 5.1

function Get-NetworkCIDR {
    <#
        .SYNOPSIS
            Retrieves CIDR notation for all IP addresses configured on network adapters

        .DESCRIPTION
            Enumerates all IPv4 and IPv6 addresses assigned to network interfaces and returns
            the corresponding CIDR notation (IP/PrefixLength), subnet mask, and network address.
            Combines data from Get-NetIPAddress and Get-NetAdapter for a consolidated view.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional credential for remote computer connections via Invoke-Command.

        .PARAMETER AddressFamily
            Filter by address family. Valid values: 'IPv4', 'IPv6', 'All'.
            Defaults to 'All'.

        .PARAMETER IncludeVirtual
            Include virtual and loopback adapters in the results.
            By default, only physical and connected adapters are shown.

        .EXAMPLE
            Get-NetworkCIDR

            Returns all configured CIDRs on the local machine.

        .EXAMPLE
            Get-NetworkCIDR -ComputerName 'SRV01' -AddressFamily IPv4

            Returns only IPv4 CIDRs from remote server SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-NetworkCIDR -AddressFamily IPv4

            Pipeline: returns IPv4 CIDRs from two remote servers.

        .OUTPUTS
            PSWinOps.NetworkCIDR
            Returns one object per configured IP address with CIDR notation.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-25
            Requires: PowerShell 5.1+ / Windows only
            Requires: NetTCPIP module (built-in on Windows)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-netipaddress
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.NetworkCIDR')]
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
        [ValidateSet('IPv4', 'IPv6', 'All')]
        [string]$AddressFamily = 'All',

        [Parameter(Mandatory = $false)]
        [switch]$IncludeVirtual
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network CIDR enumeration"

        $queryScriptBlock = {
            param([string]$Family, [bool]$ShowVirtual)

            # Get adapters for name lookup
            $adapterLookup = @{}
            Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
                $adapterLookup[$_.ifIndex] = $_
            }

            # Get IP addresses
            $ipParams = @{ ErrorAction = 'Stop' }
            if ($Family -eq 'IPv4') {
                $ipParams['AddressFamily'] = 'IPv4'
            } elseif ($Family -eq 'IPv6') {
                $ipParams['AddressFamily'] = 'IPv6'
            }

            $addresses = Get-NetIPAddress @ipParams

            foreach ($addr in $addresses) {
                $adapter = $adapterLookup[$addr.InterfaceIndex]

                # Skip virtual/loopback unless requested
                if (-not $ShowVirtual) {
                    if ($addr.InterfaceAlias -eq 'Loopback Pseudo-Interface 1') {
                        continue
                    }
                    if ($adapter -and $adapter.Virtual -eq $true) {
                        continue
                    }
                }

                # Calculate subnet mask for IPv4
                $subnetMask = $null
                $networkAddress = $null
                if ($addr.AddressFamily -eq 2) {
                    # IPv4
                    $prefix = $addr.PrefixLength
                    if ($prefix -eq 0) {
                        [uint32]$maskInt = 0
                    } else {
                        [uint32]$maskInt = [uint32]::MaxValue -shl (32 - $prefix)
                    }
                    $maskBytes = [byte[]]@(
                        [byte](($maskInt -shr 24) -band 0xFF),
                        [byte](($maskInt -shr 16) -band 0xFF),
                        [byte](($maskInt -shr 8) -band 0xFF),
                        [byte]($maskInt -band 0xFF)
                    )
                    $subnetMask = ($maskBytes -join '.')

                    # Calculate network address
                    $ipBytes = ([System.Net.IPAddress]::Parse($addr.IPAddress)).GetAddressBytes()
                    $networkBytes = for ($i = 0; $i -lt 4; $i++) {
                        $ipBytes[$i] -band $maskBytes[$i]
                    }
                    $networkAddress = ($networkBytes -join '.')
                }

                $addrFamily = if ($addr.AddressFamily -eq 2) {
                    'IPv4'
                } else {
                    'IPv6'
                }
                $networkCIDR = if ($networkAddress) {
                    '{0}/{1}' -f $networkAddress, $addr.PrefixLength
                } else {
                    $null
                }

                [PSCustomObject]@{
                    InterfaceName  = $addr.InterfaceAlias
                    InterfaceIndex = $addr.InterfaceIndex
                    AddressFamily  = $addrFamily
                    IPAddress      = $addr.IPAddress
                    PrefixLength   = $addr.PrefixLength
                    CIDR           = '{0}/{1}' -f $addr.IPAddress, $addr.PrefixLength
                    SubnetMask     = $subnetMask
                    NetworkAddress = $networkAddress
                    NetworkCIDR    = $networkCIDR
                    PrefixOrigin   = [string]$addr.PrefixOrigin
                    SuffixOrigin   = [string]$addr.SuffixOrigin
                    AdapterStatus  = if ($adapter) {
                        [string]$adapter.Status
                    } else {
                        'Unknown'
                    }
                }
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

                Write-Verbose "[$($MyInvocation.MyCommand)] Querying CIDR on '$targetComputer'"

                $rawResults = Invoke-RemoteOrLocal -ComputerName $targetComputer -ScriptBlock $queryScriptBlock -ArgumentList @($AddressFamily, $IncludeVirtual.IsPresent) -Credential $Credential

                foreach ($entry in $rawResults) {
                    [PSCustomObject]@{
                        PSTypeName     = 'PSWinOps.NetworkCIDR'
                        ComputerName   = $targetComputer
                        InterfaceName  = $entry.InterfaceName
                        InterfaceIndex = $entry.InterfaceIndex
                        AddressFamily  = $entry.AddressFamily
                        IPAddress      = $entry.IPAddress
                        PrefixLength   = $entry.PrefixLength
                        CIDR           = $entry.CIDR
                        SubnetMask     = $entry.SubnetMask
                        NetworkAddress = $entry.NetworkAddress
                        NetworkCIDR    = $entry.NetworkCIDR
                        PrefixOrigin   = $entry.PrefixOrigin
                        SuffixOrigin   = $entry.SuffixOrigin
                        AdapterStatus  = $entry.AdapterStatus
                        Timestamp      = $timestamp
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network CIDR enumeration"
    }
}
