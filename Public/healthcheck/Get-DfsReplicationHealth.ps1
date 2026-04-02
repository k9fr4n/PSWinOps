#Requires -Version 5.1
function Get-DfsReplicationHealth {
    <#
        .SYNOPSIS
            Retrieves DFS Replication health status from local or remote computers

        .DESCRIPTION
            Queries the DFSR service status and CIM namespace root/microsoftdfs to collect
            replication state for each replicated folder. Returns one object per replicated
            folder with service status, replication state, conflict size, and overall health.
            Supports remote execution via Invoke-Command with optional credentials.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-DfsReplicationHealth

            Retrieves DFS Replication health for the local computer.

        .EXAMPLE
            Get-DfsReplicationHealth -ComputerName 'DFS01'

            Retrieves DFS Replication health from a single remote server.

        .EXAMPLE
            'DFS01', 'DFS02' | Get-DfsReplicationHealth -Credential (Get-Credential)

            Retrieves DFS Replication health from multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.DfsReplicationHealth
            Returns one object per replicated folder with ComputerName, ServiceName,
            ServiceStatus, ReplicationGroupName, ReplicatedFolderName, State,
            CurrentConflictSize, OverallHealth, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: DFSR role installed on target computers
            Requires: CIM namespace root/MicrosoftDfs (no extra PS module needed)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/storage/dfs-replication/dfsr-overview
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DfsReplicationHealth')]
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

        $remoteScriptBlock = {
            $outputList = [System.Collections.Generic.List[object]]::new()

            # Step 1 - Check DFSR service
            try {
                $dfsrService = Get-Service -Name 'DFSR' -ErrorAction Stop
                $serviceStatus = $dfsrService.Status.ToString()
            }
            catch {
                $serviceStatus = 'NotFound'
            }

            # Step 2 - Query CIM for DfsrReplicatedFolderInfo
            $cimAvailable = $true
            $replicatedFolderList = $null
            try {
                $replicatedFolderList = Get-CimInstance -Namespace 'root/microsoftdfs' -ClassName 'DfsrReplicatedFolderInfo' -ErrorAction Stop
            }
            catch {
                $cimAvailable = $false
            }

            if (-not $cimAvailable -or $null -eq $replicatedFolderList) {
                $outputList.Add(@{
                    ServiceStatus        = $serviceStatus
                    ReplicationGroupName = 'N/A'
                    ReplicatedFolderName = 'N/A'
                    State                = 'N/A'
                    CurrentConflictSize  = [long]0
                })
            }
            else {
                foreach ($folder in $replicatedFolderList) {
                    $stateValue = [int]$folder.State

                    $stateText = switch ($stateValue) {
                        0 { 'Uninitialized' }
                        1 { 'Initialized' }
                        2 { 'Initial Sync' }
                        3 { 'Auto Recovery' }
                        4 { 'Normal' }
                        5 { 'In Error' }
                        default { "Unknown ($stateValue)" }
                    }


                    $conflictSize = if ($null -ne $folder.CurrentConflictSizeInMb) {
                        [long]$folder.CurrentConflictSizeInMb
                    }
                    else {
                        [long]0
                    }

                    $outputList.Add(@{
                        ServiceStatus        = $serviceStatus
                        ReplicationGroupName = $folder.ReplicationGroupName
                        ReplicatedFolderName = $folder.ReplicatedFolderName
                        State                = $stateText
                        CurrentConflictSize  = $conflictSize
                    })
                }
            }

            $outputList
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()

            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $rawResults = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $remoteScriptBlock -Credential $Credential

                if ($null -eq $rawResults) {
                    Write-Warning -Message "[$($MyInvocation.MyCommand)] No data returned from '${machine}'"
                    continue
                }

                foreach ($entry in $rawResults) {
                    # Compute OverallHealth outside the scriptblock
                    $healthStatus = if ($entry.State -eq 'N/A') {
                        [PSWinOpsHealthStatus]::RoleUnavailable
                    }
                    elseif ($entry.ServiceStatus -ne 'Running' -or $entry.State -eq 'In Error') {
                        [PSWinOpsHealthStatus]::Critical
                    }
                    elseif ($entry.State -ne 'Normal') {
                        [PSWinOpsHealthStatus]::Degraded
                    }
                    else {
                        [PSWinOpsHealthStatus]::Healthy
                    }

                    [PSCustomObject]@{
                        PSTypeName           = 'PSWinOps.DfsReplicationHealth'
                        ComputerName         = $displayName
                        ServiceName          = 'DFSR'
                        ServiceStatus        = $entry.ServiceStatus
                        ReplicationGroupName = $entry.ReplicationGroupName
                        ReplicatedFolderName = $entry.ReplicatedFolderName
                        State                = $entry.State
                        CurrentConflictSize  = $entry.CurrentConflictSize
                        OverallHealth        = $healthStatus
                        Timestamp            = Get-Date -Format 'o'
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