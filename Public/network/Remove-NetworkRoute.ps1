#Requires -Version 5.1

function Remove-NetworkRoute {
    <#
    .SYNOPSIS
        Removes an IP route from the routing table on one or more Windows computers.
    .DESCRIPTION
        Deletes a route from the routing table using the Remove-NetRoute cmdlet.
        The route is identified by its destination prefix and optionally by interface
        and next hop.

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
        The destination prefix of the route to remove (e.g. '10.0.0.0/8').
    .PARAMETER InterfaceIndex
        The interface index to narrow which route to remove.
    .PARAMETER InterfaceAlias
        The interface alias to narrow which route to remove. Alternative to InterfaceIndex.
    .PARAMETER NextHop
        Optional next hop address to narrow route selection when multiple routes
        share the same destination prefix.
    .EXAMPLE
        Remove-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet'

        Removes the route to 10.10.0.0/16 on the Ethernet interface.
    .EXAMPLE
        Remove-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -NextHop '192.168.1.1'

        Removes a specific route identified by destination, interface and next hop.
    .EXAMPLE
        'SRV01', 'SRV02' | Remove-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet'

        Removes the route on two remote servers via pipeline.
    .OUTPUTS
    None
        This function does not produce pipeline output.
    .NOTES
        Author:        Franck SALLET
        Version:       1.0.0
        Last Modified: 2026-03-20
        Requires:      PowerShell 5.1+ / Windows only
        Permissions:   Administrator privileges required
        Remote:        Requires WinRM / WS-Man enabled on target machines
    .LINK
    https://docs.microsoft.com/en-us/powershell/module/nettcpip/remove-netroute
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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
        [string]$NextHop
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network route removal"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
        $hasCredential = $PSBoundParameters.ContainsKey('Credential')

        $queryScriptBlock = {
            param(
                [string]$QDestinationPrefix,
                [int]$QInterfaceIndex,
                [string]$QInterfaceAlias,
                [string]$QNextHop
            )

            $removeParams = @{
                DestinationPrefix = $QDestinationPrefix
                Confirm           = $false
                ErrorAction       = 'Stop'
            }

            if ($QInterfaceIndex -gt 0) {
                $removeParams['InterfaceIndex'] = $QInterfaceIndex
            } elseif ($QInterfaceAlias) {
                $removeParams['InterfaceAlias'] = $QInterfaceAlias
            }

            if ($QNextHop) {
                $removeParams['NextHop'] = $QNextHop
            }

            Remove-NetRoute @removeParams
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $isLocal = $localNames -contains $targetComputer
                $shouldProcessTarget = "Route $DestinationPrefix on '$targetComputer'"

                Write-Verbose "[$($MyInvocation.MyCommand)] Removing route on '$targetComputer' (local: $isLocal)"

                if (-not $PSCmdlet.ShouldProcess($shouldProcessTarget, 'Remove network route')) {
                    continue
                }

                $queryArgs = @(
                    $DestinationPrefix
                    $(if ($PSBoundParameters.ContainsKey('InterfaceIndex')) { $InterfaceIndex } else { 0 })
                    $(if ($PSBoundParameters.ContainsKey('InterfaceAlias')) { $InterfaceAlias } else { $null })
                    $(if ($PSBoundParameters.ContainsKey('NextHop')) { $NextHop } else { $null })
                )

                if ($isLocal) {
                    & $queryScriptBlock @queryArgs
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
                    Invoke-Command @invokeParams
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Route '$DestinationPrefix' removed successfully on '$targetComputer'"
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network route removal"
    }
}
