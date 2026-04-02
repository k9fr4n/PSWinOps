#Requires -Version 5.1
function Get-DhcpServerHealth {
    <#
        .SYNOPSIS
            Checks DHCP Server role health on Windows servers

        .DESCRIPTION
            Performs a comprehensive health check of the DHCP Server role on one or more Windows
            servers. Evaluates service status, scope statistics, address utilization, and failover
            relationships to produce a per-scope health assessment with an overall health rating.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-DhcpServerHealth

            Checks DHCP Server health on the local machine.

        .EXAMPLE
            Get-DhcpServerHealth -ComputerName 'DHCP01'

            Checks DHCP Server health on the remote server DHCP01.

        .EXAMPLE
            'DHCP01', 'DHCP02' | Get-DhcpServerHealth -Credential (Get-Credential)

            Checks DHCP Server health on multiple servers using explicit credentials via pipeline.

        .OUTPUTS
            PSWinOps.DhcpServerHealth
            Returns one object per DHCP scope found, or one summary object if no scopes exist
            or the role is unavailable. Each object includes service status, scope details,
            address utilization, failover state, and an overall health rating.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: DHCP Server role
            Requires: Module DhcpServer (RSAT-DHCP)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/dhcpserver/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DhcpServerHealth')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            $scopeResults = [System.Collections.Generic.List[object]]::new()

            # Check DHCPServer service status
            $serviceStatus = 'NotFound'
            try {
                $dhcpService = Get-Service -Name 'DHCPServer' -ErrorAction Stop
                $serviceStatus = [string]$dhcpService.Status
            }
            catch {
                $serviceStatus = 'NotFound'
            }

            # Check DhcpServer module availability
            $moduleAvailable = $false
            $dhcpModule = Get-Module -Name 'DhcpServer' -ListAvailable -ErrorAction SilentlyContinue
            if ($dhcpModule) {
                $moduleAvailable = $true
            }

            # If module is not available, return a single summary hashtable
            if (-not $moduleAvailable) {
                $scopeResults.Add(@{
                    ServiceStatus   = $serviceStatus
                    ModuleAvailable = $false
                    ScopeId         = 'N/A'
                    ScopeName       = 'N/A'
                    ScopeState      = 'N/A'
                    AddressesTotal  = 0
                    AddressesInUse  = 0
                    AddressesFree   = 0
                    PercentInUse    = [decimal]0
                    FailoverPartner = 'None'
                    FailoverState   = 'None'
                })
                return $scopeResults
            }

            # If service is not running, return summary
            if ($serviceStatus -ne 'Running') {
                $scopeResults.Add(@{
                    ServiceStatus   = $serviceStatus
                    ModuleAvailable = $true
                    ScopeId         = 'N/A'
                    ScopeName       = 'N/A'
                    ScopeState      = 'N/A'
                    AddressesTotal  = 0
                    AddressesInUse  = 0
                    AddressesFree   = 0
                    PercentInUse    = [decimal]0
                    FailoverPartner = 'None'
                    FailoverState   = 'None'
                })
                return $scopeResults
            }

            # Get all failover relationships and index by ScopeId for O(1) lookup
            $failoverIndex = @{}
            try {
                $failoverRelationships = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
                if ($failoverRelationships) {
                    foreach ($failover in $failoverRelationships) {
                        foreach ($scopeId in $failover.ScopeId) {
                            $failoverIndex[[string]$scopeId] = @{
                                Partner = [string]$failover.PartnerServer
                                State   = [string]$failover.State
                            }
                        }
                    }
                }
            }
            catch {
                Write-Verbose -Message "DHCP failover query skipped: $_"
            }

            # Get all IPv4 scopes
            $dhcpScopes = $null
            try {
                $dhcpScopes = Get-DhcpServerv4Scope -ErrorAction Stop
            }
            catch {
                Write-Verbose -Message "DHCP scope retrieval failed: $_"
            }

            if (-not $dhcpScopes) {
                $scopeResults.Add(@{
                    ServiceStatus   = $serviceStatus
                    ModuleAvailable = $true
                    ScopeId         = 'N/A'
                    ScopeName       = 'No scopes configured'
                    ScopeState      = 'N/A'
                    AddressesTotal  = 0
                    AddressesInUse  = 0
                    AddressesFree   = 0
                    PercentInUse    = [decimal]0
                    FailoverPartner = 'None'
                    FailoverState   = 'None'
                })
                return $scopeResults
            }

            foreach ($scope in $dhcpScopes) {
                $scopeIdStr = [string]$scope.ScopeId

                # Get scope statistics
                $addressesFree  = 0
                $addressesInUse = 0
                $percentInUse   = [decimal]0
                try {
                    $scopeStats = Get-DhcpServerv4ScopeStatistics -ScopeId $scope.ScopeId -ErrorAction Stop
                    $addressesFree  = [int]$scopeStats.AddressesFree
                    $addressesInUse = [int]$scopeStats.AddressesInUse
                    $percentInUse   = [decimal]$scopeStats.PercentageInUse
                }
                catch {
                    Write-Verbose -Message "Statistics unavailable for scope $($scope.ScopeId): $_"
                }

                $addressesTotal = $addressesInUse + $addressesFree

                # Lookup failover info from pre-built index
                $failoverPartner = 'None'
                $failoverState   = 'None'
                if ($failoverIndex.ContainsKey($scopeIdStr)) {
                    $failoverPartner = $failoverIndex[$scopeIdStr].Partner
                    $failoverState   = $failoverIndex[$scopeIdStr].State
                }

                $scopeResults.Add(@{
                    ServiceStatus   = $serviceStatus
                    ModuleAvailable = $true
                    ScopeId         = $scopeIdStr
                    ScopeName       = [string]$scope.Name
                    ScopeState      = [string]$scope.State
                    AddressesTotal  = $addressesTotal
                    AddressesInUse  = $addressesInUse
                    AddressesFree   = $addressesFree
                    PercentInUse    = $percentInUse
                    FailoverPartner = $failoverPartner
                    FailoverState   = $failoverState
                })
            }

            $scopeResults
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $rawResults = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                if (-not $rawResults) {
                    Write-Warning -Message "[$($MyInvocation.MyCommand)] No results returned from '${machine}'"
                    continue
                }

                foreach ($scopeData in $rawResults) {
                    # Determine OverallHealth
                    if (-not $scopeData.ModuleAvailable) {
                        $healthStatus = [PSWinOpsHealthStatus]::RoleUnavailable
                    }
                    elseif ($scopeData.ServiceStatus -ne 'Running') {
                        $healthStatus = [PSWinOpsHealthStatus]::Critical
                    }
                    elseif ($scopeData.ScopeId -eq 'N/A') {
                        $healthStatus = [PSWinOpsHealthStatus]::Healthy
                    }
                    elseif ($scopeData.ScopeState -eq 'Inactive' -and $scopeData.AddressesInUse -gt 0) {
                        $healthStatus = [PSWinOpsHealthStatus]::Critical
                    }
                    elseif ($scopeData.PercentInUse -gt 90) {
                        $healthStatus = [PSWinOpsHealthStatus]::Degraded
                    }
                    elseif ($scopeData.FailoverState -ne 'None' -and $scopeData.FailoverState -ne 'Normal') {
                        $healthStatus = [PSWinOpsHealthStatus]::Degraded
                    }
                    else {
                        $healthStatus = [PSWinOpsHealthStatus]::Healthy
                    }

                    [PSCustomObject]@{
                        PSTypeName      = 'PSWinOps.DhcpServerHealth'
                        ComputerName    = $displayName
                        ServiceName     = 'DHCPServer'
                        ServiceStatus   = [string]$scopeData.ServiceStatus
                        ScopeId         = [string]$scopeData.ScopeId
                        ScopeName       = [string]$scopeData.ScopeName
                        ScopeState      = [string]$scopeData.ScopeState
                        AddressesTotal  = [int]$scopeData.AddressesTotal
                        AddressesInUse  = [int]$scopeData.AddressesInUse
                        AddressesFree   = [int]$scopeData.AddressesFree
                        PercentInUse    = [decimal]$scopeData.PercentInUse
                        FailoverPartner = [string]$scopeData.FailoverPartner
                        FailoverState   = [string]$scopeData.FailoverState
                        OverallHealth   = $healthStatus
                        Timestamp       = Get-Date -Format 'o'
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