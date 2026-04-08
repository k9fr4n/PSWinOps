#Requires -Version 5.1
function Get-ServiceHealth {
    <#
        .SYNOPSIS
            Retrieves service health status from local or remote computers

        .DESCRIPTION
            Queries Win32_Service via CIM to report on Windows services state and health.
            By default returns only auto-start services that are not running (degraded),
            making it ideal for monitoring. Use -IncludeAll to see every service.
            Use -Name to filter by service name with wildcard support.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER ServiceName
            Optional wildcard filter on the service name. Uses -like matching.
            For example, 'sql*' returns all SQL-related services.

        .PARAMETER IncludeAll
            When specified, returns all services regardless of start mode or state.
            By default, only auto-start services that are not running are returned.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-ServiceHealth

            Returns auto-start services that are not running on the local computer.

        .EXAMPLE
            Get-ServiceHealth -ComputerName 'SRV01' -ServiceName 'sql*' -IncludeAll

            Returns all SQL-related services from SRV01 regardless of state.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-ServiceHealth

            Checks service health on multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.ServiceHealth
            Returns objects with service name, display name, state, start mode,
            account, process ID, and a health status indicator.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-25
            Requires: PowerShell 5.1+ / Windows only

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-service
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ServiceHealth')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeAll,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            @(Get-CimInstance -ClassName 'Win32_Service' -ErrorAction Stop)
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying Win32_Service on '$machine'"
                $services = @(Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential)

                $displayName = $machine

                foreach ($svc in $services) {
                    # Apply name filter if specified
                    if ($PSBoundParameters.ContainsKey('ServiceName') -and ($svc.Name -notlike $ServiceName)) {
                        continue
                    }

                    # Determine health status
                    $status = switch ($true) {
                        ($svc.State -eq 'Running') {
                            [PSWinOpsHealthStatus]::Healthy
                            break
                        }
                        ($svc.StartMode -eq 'Auto' -and $svc.State -ne 'Running') {
                            [PSWinOpsHealthStatus]::Degraded
                            break
                        }
                        ($svc.StartMode -eq 'Disabled') {
                            'Disabled'
                            break
                        }
                        default {
                            'Stopped'
                        }
                    }

                    # Default mode: only show degraded (auto-start not running)
                    if (-not $IncludeAll -and $status -ne [PSWinOpsHealthStatus]::Degraded) {
                        continue
                    }

                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.ServiceHealth'
                        ComputerName = $displayName
                        ServiceName  = $svc.Name
                        DisplayName  = $svc.DisplayName
                        State        = $svc.State
                        StartMode    = $svc.StartMode
                        Account      = $svc.StartName
                        ProcessId    = $svc.ProcessId
                        Status       = $status
                        Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                continue
            }

        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
