#Requires -Version 5.1

function Get-NetworkRoute {
    <#
    .SYNOPSIS
        Retrieves IP routing table entries on one or more Windows computers.
    .DESCRIPTION
        Queries the routing table using the Get-NetRoute cmdlet from the NetTCPIP module.
        Supports filtering by destination prefix, next hop gateway, interface alias,
        and address family (IPv4/IPv6).

        For remote computers, the query is executed via Invoke-Command, which requires
        WinRM / WS-Man enabled on the target.
    .PARAMETER ComputerName
        One or more computer names to query. Accepts pipeline input by value and
        by property name. Defaults to the local machine ($env:COMPUTERNAME).
    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for
        local machine queries.
    .PARAMETER DestinationPrefix
        Filter routes by destination prefix. Supports wildcards (e.g. '10.0.*', '0.0.0.0/0').
    .PARAMETER NextHop
        Filter routes by next hop gateway address. Supports wildcards.
    .PARAMETER InterfaceAlias
        Filter routes by network interface alias (e.g. 'Ethernet', 'Wi-Fi'). Supports wildcards.
    .PARAMETER AddressFamily
        Filter routes by address family. Valid values: IPv4, IPv6. By default both are returned.
    .EXAMPLE
        Get-NetworkRoute

        Returns all routing table entries on the local machine.
    .EXAMPLE
        Get-NetworkRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0'

        Returns the default IPv4 gateway route on the local machine.
    .EXAMPLE
        Get-NetworkRoute -ComputerName 'SRV01' -Credential (Get-Credential)

        Returns all routes on remote server SRV01.
    .EXAMPLE
        'SRV01', 'SRV02' | Get-NetworkRoute -AddressFamily IPv4

        Returns IPv4 routes for two servers via pipeline.
    .OUTPUTS
    PSWinOps.NetworkRoute
        Route details including destination, next hop, interface, metric and address family.
    .NOTES
        Author:        Franck SALLET
        Version:       1.0.0
        Last Modified: 2026-03-20
        Requires:      PowerShell 5.1+ / Windows only
        Permissions:   No admin required for reading routes
        Remote:        Requires WinRM / WS-Man enabled on target machines
    .LINK
    https://docs.microsoft.com/en-us/powershell/module/nettcpip/get-netroute
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.NetworkRoute')]
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
        [SupportsWildcards()]
        [string]$DestinationPrefix,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$NextHop,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$InterfaceAlias,

        [Parameter(Mandatory = $false)]
        [ValidateSet('IPv4', 'IPv6')]
        [string]$AddressFamily
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network route query"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
        $hasCredential = $PSBoundParameters.ContainsKey('Credential')

        $queryScriptBlock = {
            param(
                [string]$QueryAddressFamily,
                [string]$QueryDestinationPrefix,
                [string]$QueryNextHop,
                [string]$QueryInterfaceAlias
            )

            $getParams = @{ ErrorAction = 'Stop' }
            if ($QueryAddressFamily) {
                $getParams['AddressFamily'] = $QueryAddressFamily
            }

            $routes = Get-NetRoute @getParams

            if ($QueryDestinationPrefix) {
                $routes = @($routes | Where-Object { $_.DestinationPrefix -like $QueryDestinationPrefix })
            }
            if ($QueryNextHop) {
                $routes = @($routes | Where-Object { $_.NextHop -like $QueryNextHop })
            }
            if ($QueryInterfaceAlias) {
                $routes = @($routes | Where-Object { $_.InterfaceAlias -like $QueryInterfaceAlias })
            }

            foreach ($route in $routes) {
                [PSCustomObject]@{
                    DestinationPrefix = $route.DestinationPrefix
                    NextHop           = $route.NextHop
                    InterfaceAlias    = $route.InterfaceAlias
                    InterfaceIndex    = $route.InterfaceIndex
                    RouteMetric       = $route.RouteMetric
                    AddressFamily     = if ($route.AddressFamily -eq 2) {
                        'IPv4'
                    } elseif ($route.AddressFamily -eq 23) {
                        'IPv6'
                    } else {
                        [string]$route.AddressFamily
                    }
                    Protocol          = [string]$route.Protocol
                    Store             = [string]$route.Store
                }
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $isLocal = $localNames -contains $targetComputer
                $timestamp = Get-Date -Format 'o'

                Write-Verbose "[$($MyInvocation.MyCommand)] Querying '$targetComputer' (local: $isLocal)"

                $queryArgs = @(
                    $(if ($AddressFamily) {
                            $AddressFamily
                        } else {
                            $null
                        })
                    $(if ($PSBoundParameters.ContainsKey('DestinationPrefix')) {
                            $DestinationPrefix
                        } else {
                            $null
                        })
                    $(if ($PSBoundParameters.ContainsKey('NextHop')) {
                            $NextHop
                        } else {
                            $null
                        })
                    $(if ($PSBoundParameters.ContainsKey('InterfaceAlias')) {
                            $InterfaceAlias
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
                        PSTypeName        = 'PSWinOps.NetworkRoute'
                        ComputerName      = $targetComputer
                        DestinationPrefix = $entry.DestinationPrefix
                        NextHop           = $entry.NextHop
                        InterfaceAlias    = $entry.InterfaceAlias
                        InterfaceIndex    = $entry.InterfaceIndex
                        RouteMetric       = $entry.RouteMetric
                        AddressFamily     = $entry.AddressFamily
                        Protocol          = $entry.Protocol
                        Store             = $entry.Store
                        Timestamp         = $timestamp
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network route query"
    }
}
