#Requires -Version 5.1
function Get-ClusterHealth {
    <#
        .SYNOPSIS
            Retrieves failover cluster health status from local or remote machines

        .DESCRIPTION
            Queries the Failover Clustering service and cluster components to assess overall
            cluster health. Checks ClusSvc service status, node states, resource states,
            group states, and quorum configuration on one or more machines.
            Returns a typed PSWinOps.ClusterHealth object per machine with an OverallHealth
            assessment of Healthy, Degraded, Critical, or RoleUnavailable.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-ClusterHealth

            Queries cluster health on the local machine.

        .EXAMPLE
            Get-ClusterHealth -ComputerName 'YOURCLUSTER01'

            Queries cluster health on a single remote machine using current credentials.

        .EXAMPLE
            'YOURCLUSTER01', 'YOURCLUSTER02' | Get-ClusterHealth

            Queries cluster health on multiple machines via pipeline input.

        .OUTPUTS
            PSWinOps.ClusterHealth
            Returns one object per queried machine with cluster health properties
            including ServiceStatus, NodeState, QuorumState, and OverallHealth.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: Failover-Clustering feature
            Requires: Module FailoverClusters (RSAT-Clustering-PowerShell)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/failoverclusters/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ClusterHealth')]
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
            $data = @{
                ServiceStatus   = 'NotInstalled'
                ModuleAvailable = $false
                ClusterName     = 'N/A'
                NodeName        = 'N/A'
                NodeState       = 'N/A'
                TotalNodes      = 0
                NodesUp         = 0
                NodesDown       = 0
                NodesPaused     = 0
                TotalResources  = 0
                ResourcesOnline = 0
                ResourcesFailed = 0
                TotalGroups     = 0
                GroupsOnline    = 0
                QuorumType      = 'N/A'
                QuorumState     = 'N/A'
                QueryError      = $null
            }

            # 1. Check ClusSvc service
            try {
                $svc = Get-Service -Name 'ClusSvc' -ErrorAction Stop
                $data.ServiceStatus = $svc.Status.ToString()
            }
            catch {
                Write-Verbose -Message "ClusSvc service not found: $_"
            }

            # 2. Check FailoverClusters module availability
            if (Get-Module -Name 'FailoverClusters' -ListAvailable -ErrorAction SilentlyContinue) {
                $data.ModuleAvailable = $true
            }

            # 3. Query cluster only if service is running and module is available
            if ($data.ServiceStatus -eq 'Running' -and $data.ModuleAvailable) {
                try {
                    Import-Module -Name 'FailoverClusters' -ErrorAction Stop

                    $cluster = Get-Cluster -ErrorAction Stop
                    $data.ClusterName = $cluster.Name

                    $nodeList = @(Get-ClusterNode -ErrorAction Stop)
                    $localNode = $nodeList |
                        Where-Object -FilterScript { $_.Name -eq $env:COMPUTERNAME }
                    $data.NodeName = if ($localNode) { $localNode.Name } else { $env:COMPUTERNAME }
                    $data.NodeState = if ($localNode) { $localNode.State.ToString() } else { 'Unknown' }
                    $data.TotalNodes = $nodeList.Count
                    $data.NodesUp = @($nodeList | Where-Object -FilterScript { $_.State -eq 'Up' }).Count
                    $data.NodesDown = @($nodeList | Where-Object -FilterScript { $_.State -eq 'Down' }).Count
                    $data.NodesPaused = @($nodeList | Where-Object -FilterScript { $_.State -eq 'Paused' }).Count

                    $resourceList = @(Get-ClusterResource -ErrorAction Stop)
                    $data.TotalResources = $resourceList.Count
                    $data.ResourcesOnline = @($resourceList | Where-Object -FilterScript { $_.State -eq 'Online' }).Count
                    $data.ResourcesFailed = @($resourceList | Where-Object -FilterScript { $_.State -eq 'Failed' }).Count

                    $groupList = @(Get-ClusterGroup -ErrorAction Stop)
                    $data.TotalGroups = $groupList.Count
                    $data.GroupsOnline = @($groupList | Where-Object -FilterScript { $_.State -eq 'Online' }).Count

                    $quorumInfo = Get-ClusterQuorum -ErrorAction Stop
                    $data.QuorumType = $quorumInfo.QuorumType.ToString()
                    if ($quorumInfo.QuorumResource) {
                        $resourceState = $quorumInfo.QuorumResource.State
                        $data.QuorumState = if ($resourceState -eq 'Online') { 'Normal' } else { 'Warning' }
                    }
                    else {
                        $data.QuorumState = 'Normal'
                    }
                }
                catch {
                    $data.QueryError = $_.Exception.Message
                }
            }

            return $data
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $clusterData = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                # Determine OverallHealth
                if (-not $clusterData.ModuleAvailable) {
                    $healthStatus = [PSWinOpsHealthStatus]::RoleUnavailable
                }
                elseif ($clusterData.ServiceStatus -ne 'Running' -or
                        $clusterData.NodesDown -gt 0 -or
                        $clusterData.ResourcesFailed -gt 0 -or
                        $clusterData.QueryError) {
                    $healthStatus = [PSWinOpsHealthStatus]::Critical
                }
                elseif ($clusterData.NodesPaused -gt 0 -or
                        $clusterData.GroupsOnline -lt $clusterData.TotalGroups) {
                    $healthStatus = [PSWinOpsHealthStatus]::Degraded
                }
                else {
                    $healthStatus = [PSWinOpsHealthStatus]::Healthy
                }

                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.ClusterHealth'
                    ComputerName    = $displayName
                    ServiceName     = 'ClusSvc'
                    ServiceStatus   = $clusterData.ServiceStatus
                    ClusterName     = $clusterData.ClusterName
                    NodeName        = $clusterData.NodeName
                    NodeState       = $clusterData.NodeState
                    TotalNodes      = [int]$clusterData.TotalNodes
                    NodesUp         = [int]$clusterData.NodesUp
                    TotalResources  = [int]$clusterData.TotalResources
                    ResourcesOnline = [int]$clusterData.ResourcesOnline
                    ResourcesFailed = [int]$clusterData.ResourcesFailed
                    TotalGroups     = [int]$clusterData.TotalGroups
                    GroupsOnline    = [int]$clusterData.GroupsOnline
                    QuorumType      = $clusterData.QuorumType
                    QuorumState     = $clusterData.QuorumState
                    OverallHealth   = $healthStatus
                    Timestamp       = Get-Date -Format 'o'
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