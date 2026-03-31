#Requires -Version 5.1

function New-NetworkRoute {
    <#
        .SYNOPSIS
            Creates a new static IP route on one or more Windows computers

        .DESCRIPTION
            Adds a static route to the routing table using the New-NetRoute cmdlet.
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
            The destination network prefix in CIDR notation (e.g. '10.0.0.0/8', '192.168.1.0/24').

        .PARAMETER NextHop
            The IP address of the next hop gateway.

        .PARAMETER InterfaceIndex
            The index of the network interface to use. Use Get-NetAdapter to find interface indexes.

        .PARAMETER InterfaceAlias
            The alias of the network interface to use (e.g. 'Ethernet'). Alternative to InterfaceIndex.

        .PARAMETER RouteMetric
            The route metric (cost). Lower values have higher priority. Defaults to 0 (automatic).

        .PARAMETER AddressFamily
            The address family. Valid values: IPv4, IPv6. Automatically inferred from
            DestinationPrefix if not specified.

        .EXAMPLE
            New-NetworkRoute -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet'

            Creates a static route to 10.10.0.0/16 via gateway 192.168.1.1 on the local machine.

        .EXAMPLE
            New-NetworkRoute -DestinationPrefix '172.16.0.0/12' -NextHop '10.0.0.1' -InterfaceIndex 4 -RouteMetric 100

            Creates a static route with a specific metric and interface index.

        .EXAMPLE
            'SRV01', 'SRV02' | New-NetworkRoute -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet'

            Creates the same static route on two remote servers via pipeline.

        .OUTPUTS
            PSWinOps.NetworkRoute
            The newly created route details.

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
            https://learn.microsoft.com/en-us/powershell/module/nettcpip/new-netroute
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

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NextHop,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 999999)]
        [int]$InterfaceIndex,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$InterfaceAlias,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 9999)]
        [int]$RouteMetric = 0,

        [Parameter(Mandatory = $false)]
        [ValidateSet('IPv4', 'IPv6')]
        [string]$AddressFamily
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting new network route creation"

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
                [string]$QNextHop,
                [int]$QInterfaceIndex,
                [string]$QInterfaceAlias,
                [int]$QRouteMetric,
                [string]$QAddressFamily
            )

            $newParams = @{
                DestinationPrefix = $QDestinationPrefix
                NextHop           = $QNextHop
                Confirm           = $false
                ErrorAction       = 'Stop'
            }

            if ($QInterfaceIndex -gt 0) {
                $newParams['InterfaceIndex'] = $QInterfaceIndex
            } elseif ($QInterfaceAlias) {
                $newParams['InterfaceAlias'] = $QInterfaceAlias
            }

            if ($QRouteMetric -gt 0) {
                $newParams['RouteMetric'] = $QRouteMetric
            }

            if ($QAddressFamily) {
                $newParams['AddressFamily'] = $QAddressFamily
            }

            $route = New-NetRoute @newParams

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
                $timestamp = Get-Date -Format 'o'
                $shouldProcessTarget = "Route $DestinationPrefix via $NextHop on '$targetComputer'"

                Write-Verbose "[$($MyInvocation.MyCommand)] Creating route on '$targetComputer'"

                if (-not $PSCmdlet.ShouldProcess($shouldProcessTarget, 'Create network route')) {
                    continue
                }

                $queryArgs = @(
                    $DestinationPrefix
                    $NextHop
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
                    $RouteMetric
                    $(if ($AddressFamily) {
                            $AddressFamily
                        } else {
                            $null
                        })
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
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed new network route creation"
    }
}
