#Requires -Version 5.1

function Set-NetworkRoute {
    <#
        .SYNOPSIS
            Modifies an existing IP route on one or more Windows computers

        .DESCRIPTION
            Updates properties of an existing route in the routing table using the
            Set-NetRoute cmdlet. Can modify the route metric of a route identified by
            its destination prefix and interface.

            Requires Administrator privileges.

            For remote computers, the operation is executed via Invoke-Command, which
            requires WinRM / WS-Man enabled on the target.

        .PARAMETER ComputerName
            One or more computer names to configure. Accepts pipeline input by value and
            by property name. Defaults to the local machine ($env:COMPUTERNAME).

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote machines. Ignored for
            local machine operations.

        .PARAMETER DestinationPrefix
            The destination prefix of the route to modify (e.g. '10.0.0.0/8').

        .PARAMETER InterfaceIndex
            The interface index that identifies the route to modify.

        .PARAMETER InterfaceAlias
            The interface alias that identifies the route to modify. Alternative to InterfaceIndex.

        .PARAMETER NextHop
            Optional: the next hop address to narrow route selection when multiple routes
            share the same destination prefix and interface.

        .PARAMETER RouteMetric
            The new route metric value to set.

        .EXAMPLE
            Set-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50

            Changes the metric of the route to 10.10.0.0/16 on the Ethernet interface to 50.

        .EXAMPLE
            Set-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceIndex 4 -RouteMetric 200

            Changes the metric using interface index instead of alias.

        .EXAMPLE
            'SRV01', 'SRV02' | Set-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50

            Modifies the route metric on two remote servers via pipeline.

        .OUTPUTS
            PSWinOps.NetworkRoute
            The modified route details.

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-20
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   Administrator privileges required
            Remote:        Requires WinRM / WS-Man enabled on target machines

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-netroute
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPrefix,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 999999)]
        [int]$InterfaceIndex,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$InterfaceAlias,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$NextHop,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 9999)]
        [int]$RouteMetric
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network route modification"

        if (-not $PSBoundParameters.ContainsKey('InterfaceIndex') -and -not $PSBoundParameters.ContainsKey('InterfaceAlias')) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new('Either InterfaceIndex or InterfaceAlias must be specified.'),
                    'MissingInterfaceParameter',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $null
                )
            )
        }

        $queryScriptBlock = {
            param(
                [string]$QDestinationPrefix,
                [int]$QInterfaceIndex,
                [string]$QInterfaceAlias,
                [string]$QNextHop,
                [int]$QRouteMetric
            )

            # Build params to identify the route
            $setParams = @{
                DestinationPrefix = $QDestinationPrefix
                RouteMetric       = $QRouteMetric
                Confirm           = $false
                ErrorAction       = 'Stop'
            }

            if ($QInterfaceIndex -gt 0) {
                $setParams['InterfaceIndex'] = $QInterfaceIndex
            } elseif ($QInterfaceAlias) {
                $setParams['InterfaceAlias'] = $QInterfaceAlias
            }

            if ($QNextHop) {
                $setParams['NextHop'] = $QNextHop
            }

            Set-NetRoute @setParams

            # Retrieve the updated route
            $getParams = @{
                DestinationPrefix = $QDestinationPrefix
                ErrorAction       = 'Stop'
            }
            if ($QInterfaceIndex -gt 0) {
                $getParams['InterfaceIndex'] = $QInterfaceIndex
            } elseif ($QInterfaceAlias) {
                $getParams['InterfaceAlias'] = $QInterfaceAlias
            }

            $route = Get-NetRoute @getParams | Select-Object -First 1

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

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $shouldProcessTarget = "Route $DestinationPrefix on '$targetComputer' — set metric to $RouteMetric"

                Write-Verbose "[$($MyInvocation.MyCommand)] Modifying route on '$targetComputer'"

                if (-not $PSCmdlet.ShouldProcess($shouldProcessTarget, 'Modify network route')) {
                    continue
                }

                $queryArgs = @(
                    $DestinationPrefix
                    $(if ($PSBoundParameters.ContainsKey('InterfaceIndex')) {
                            $InterfaceIndex
                        } else {
                            0
                        })
                    $(if ($PSBoundParameters.ContainsKey('InterfaceAlias')) {
                            $InterfaceAlias
                        } else {
                            $null
                        })
                    $(if ($PSBoundParameters.ContainsKey('NextHop')) {
                            $NextHop
                        } else {
                            $null
                        })
                    $RouteMetric
                )

                $rawResult = Invoke-RemoteOrLocal -ComputerName $targetComputer -ScriptBlock $queryScriptBlock -ArgumentList $queryArgs -Credential $Credential

                [PSCustomObject]@{
                    PSTypeName        = 'PSWinOps.NetworkRoute'
                    ComputerName      = $targetComputer
                    DestinationPrefix = $rawResult.DestinationPrefix
                    NextHop           = $rawResult.NextHop
                    InterfaceAlias    = $rawResult.InterfaceAlias
                    InterfaceIndex    = $rawResult.InterfaceIndex
                    RouteMetric       = $rawResult.RouteMetric
                    AddressFamily     = $rawResult.AddressFamily
                    Protocol          = $rawResult.Protocol
                    Store             = $rawResult.Store
                    Timestamp         = $timestamp
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network route modification"
    }
}
