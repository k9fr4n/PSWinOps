#Requires -Version 5.1
function Get-DfsNamespaceHealth {
    <#
        .SYNOPSIS
            Retrieves DFS Namespace health status from local or remote computers

        .DESCRIPTION
            Checks the DFS service state and enumerates all DFS namespace roots on
            the target computer. For each root, it queries root targets to determine
            how many are online versus offline, then computes an overall health status.
            Uses Invoke-Command for remote execution because the DFSN cmdlets only
            work locally on the DFS server.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-DfsNamespaceHealth

            Returns DFS namespace health for all roots on the local computer.

        .EXAMPLE
            Get-DfsNamespaceHealth -ComputerName 'SRV01'

            Returns DFS namespace health from a single remote DFS server.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-DfsNamespaceHealth

            Checks DFS namespace health on multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.DfsNamespaceHealth
            Returns objects with computer name, DFS service status, root path,
            root type, state, target counts, and an overall health indicator.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: Module DFSN (FS-DFS-Namespace + RSAT-DFS-Mgmt-Con)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/dfsn/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DfsNamespaceHealth')]
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
            $resultList = [System.Collections.Generic.List[object]]::new()

            # Step 1 - Check DFS service
            try {
                $dfsSvc = Get-Service -Name 'Dfs' -ErrorAction Stop
                $svcStatus = $dfsSvc.Status.ToString()
            }
            catch {
                $svcStatus = 'NotFound'
            }

            # Step 2 - Check DFSN module availability
            $dfsnAvailable = $false
            if ($svcStatus -eq 'Running') {
                $dfsnAvailable = [bool](Get-Module -ListAvailable -Name 'DFSN' -ErrorAction SilentlyContinue)
            }

            if (-not $dfsnAvailable) {
                $resultList.Add(@{
                    ServiceStatus  = $svcStatus
                    RootPath       = 'N/A'
                    RootType       = 'N/A'
                    State          = 'N/A'
                    TargetCount    = 0
                    HealthyTargets = 0
                    DfsnAvailable  = $false
                    QueryError     = $false
                })
                return $resultList.ToArray()
            }

            # Step 3 - Enumerate DFS roots
            $dfsRoots = $null
            try {
                $dfsRoots = @(Get-DfsnRoot -ErrorAction Stop)
            }
            catch {
                $resultList.Add(@{
                    ServiceStatus  = $svcStatus
                    RootPath       = 'N/A'
                    RootType       = 'N/A'
                    State          = 'N/A'
                    TargetCount    = 0
                    HealthyTargets = 0
                    DfsnAvailable  = $true
                    QueryError     = $true
                })
                return $resultList.ToArray()
            }

            if ($dfsRoots.Count -eq 0) {
                $resultList.Add(@{
                    ServiceStatus  = $svcStatus
                    RootPath       = 'N/A'
                    RootType       = 'N/A'
                    State          = 'N/A'
                    TargetCount    = 0
                    HealthyTargets = 0
                    DfsnAvailable  = $true
                    QueryError     = $false
                })
                return $resultList.ToArray()
            }

            # Step 4 - Check each root and its targets
            foreach ($root in $dfsRoots) {
                $rootState = if ($root.State) { $root.State.ToString() } else { 'N/A' }
                $rootType  = if ($root.Type)  { $root.Type.ToString()  } else { 'N/A' }

                $targetTotal   = 0
                $targetHealthy = 0
                try {
                    $targets = @(Get-DfsnRootTarget -Path $root.Path -ErrorAction Stop)
                    $targetTotal = $targets.Count
                    foreach ($target in $targets) {
                        if ($target.State -eq 'Online') {
                            $targetHealthy++
                        }
                    }
                }
                catch {
                    $targetTotal   = 0
                    $targetHealthy = 0
                }

                $resultList.Add(@{
                    ServiceStatus  = $svcStatus
                    RootPath       = $root.Path
                    RootType       = $rootType
                    State          = $rootState
                    TargetCount    = $targetTotal
                    HealthyTargets = $targetHealthy
                    DfsnAvailable  = $true
                    QueryError     = $false
                })
            }

            return $resultList.ToArray()
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                $displayName = $machine.ToUpper()
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"
                $rawResults = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                foreach ($item in $rawResults) {
                    # Compute OverallHealth outside the scriptblock
                    $healthStatus = if ($item.ServiceStatus -eq 'NotFound') {
                        'RoleUnavailable'
                    }
                    elseif ($item.ServiceStatus -ne 'Running') {
                        'Critical'
                    }
                    elseif (-not $item.DfsnAvailable) {
                        'RoleUnavailable'
                    }
                    elseif ($item.QueryError) {
                        'Critical'
                    }
                    elseif ($item.RootPath -eq 'N/A') {
                        'Healthy'
                    }
                    elseif ($item.TargetCount -eq 0 -or $item.HealthyTargets -eq 0) {
                        'Critical'
                    }
                    elseif ($item.HealthyTargets -lt $item.TargetCount) {
                        'Degraded'
                    }
                    else {
                        'Healthy'
                    }

                    [PSCustomObject]@{
                        PSTypeName     = 'PSWinOps.DfsNamespaceHealth'
                        ComputerName   = $displayName
                        ServiceName    = 'Dfs'
                        ServiceStatus  = $item.ServiceStatus
                        RootPath       = $item.RootPath
                        RootType       = $item.RootType
                        State          = $item.State
                        TargetCount    = [int]$item.TargetCount
                        HealthyTargets = [int]$item.HealthyTargets
                        OverallHealth  = $healthStatus
                        Timestamp      = Get-Date -Format 'o'
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