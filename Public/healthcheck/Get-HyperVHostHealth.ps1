#Requires -Version 5.1
function Get-HyperVHostHealth {
    <#
        .SYNOPSIS
            Checks Hyper-V host health on Windows servers

        .DESCRIPTION
            Queries the Hyper-V Virtual Machine Management service and enumerates virtual machines
            to assess host resource utilization and VM health. Returns a typed health object per
            host with VM counts by state, memory utilization, and an overall health assessment.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-HyperVHostHealth

            Checks Hyper-V health on the local host.

        .EXAMPLE
            Get-HyperVHostHealth -ComputerName 'HV01'

            Checks Hyper-V health on a remote Hyper-V host.

        .EXAMPLE
            'HV01', 'HV02' | Get-HyperVHostHealth

            Checks Hyper-V health on multiple hosts via pipeline.

        .OUTPUTS
            PSWinOps.HyperVHostHealth
            Returns one object per target host containing service status, VM counts by state,
            memory utilization metrics, and an overall health assessment string.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: Hyper-V role
            Requires: Module Hyper-V (Hyper-V-PowerShell feature)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/hyper-v/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.HyperVHostHealth')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            $data = @{
                ServiceStatus       = 'NotFound'
                ModuleAvailable     = $false
                LogicalProcessors   = 0
                MemoryCapacityBytes = [long]0
                TotalVMs            = 0
                VMsRunning          = 0
                VMsOff              = 0
                VMsSaved            = 0
                VMsPaused           = 0
                VMsCritical         = 0
                AssignedMemoryBytes = [long]0
            }

            try {
                $svc = Get-Service -Name 'vmms' -ErrorAction Stop
                $data.ServiceStatus = $svc.Status.ToString()
            }
            catch {
                $data.ServiceStatus = 'NotFound'
            }

            $moduleCheck = Get-Module -Name 'Hyper-V' -ListAvailable -ErrorAction SilentlyContinue
            if ($moduleCheck) {
                $data.ModuleAvailable = $true
            }

            if ($data.ModuleAvailable -and $data.ServiceStatus -eq 'Running') {
                try {
                    $vmHost = Get-VMHost -ErrorAction Stop
                    $data.LogicalProcessors   = [int]$vmHost.LogicalProcessorCount
                    $data.MemoryCapacityBytes = [long]$vmHost.MemoryCapacity

                    $allVMs = @(Get-VM -ErrorAction Stop)
                    $data.TotalVMs   = $allVMs.Count
                    $data.VMsRunning = @($allVMs | Where-Object -FilterScript { $_.State -eq 'Running' }).Count
                    $data.VMsOff     = @($allVMs | Where-Object -FilterScript { $_.State -eq 'Off' }).Count
                    $data.VMsSaved   = @($allVMs | Where-Object -FilterScript { $_.State -eq 'Saved' }).Count
                    $data.VMsPaused  = @($allVMs | Where-Object -FilterScript { $_.State -eq 'Paused' }).Count
                    $data.VMsCritical = $data.TotalVMs - $data.VMsRunning - $data.VMsOff - $data.VMsSaved - $data.VMsPaused

                    $memMeasure = $allVMs | Measure-Object -Property 'MemoryAssigned' -Sum
                    if ($memMeasure.Sum) {
                        $data.AssignedMemoryBytes = [long]$memMeasure.Sum
                    }
                }
                catch {
                    Write-Warning -Message "Failed to query Hyper-V data: $_"
                }
            }

            $data
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $result = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                $totalMemoryGB    = [math]::Round($result.MemoryCapacityBytes / 1GB, 2)
                $assignedMemoryGB = [math]::Round($result.AssignedMemoryBytes / 1GB, 2)
                $memUsagePct      = if ($totalMemoryGB -gt 0) {
                    [math]::Round(($assignedMemoryGB / $totalMemoryGB) * 100, 2)
                }
                else { [decimal]0 }

                # Compute OverallHealth
                if (-not $result.ModuleAvailable) {
                    $healthStatus = 'RoleUnavailable'
                }
                elseif ($result.ServiceStatus -ne 'Running' -or $result.VMsCritical -gt 0) {
                    $healthStatus = 'Critical'
                }
                elseif ($memUsagePct -gt 90) {
                    $healthStatus = 'Degraded'
                }
                else {
                    $healthStatus = 'Healthy'
                }

                [PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.HyperVHostHealth'
                    ComputerName       = $displayName
                    ServiceName        = 'vmms'
                    ServiceStatus      = $result.ServiceStatus
                    LogicalProcessors  = [int]$result.LogicalProcessors
                    TotalMemoryGB      = [decimal]$totalMemoryGB
                    TotalVMs           = [int]$result.TotalVMs
                    VMsRunning         = [int]$result.VMsRunning
                    VMsOff             = [int]$result.VMsOff
                    VMsSaved           = [int]$result.VMsSaved
                    VMsPaused          = [int]$result.VMsPaused
                    VMsCritical        = [int]$result.VMsCritical
                    AssignedMemoryGB   = [decimal]$assignedMemoryGB
                    MemoryUsagePercent = [decimal]$memUsagePct
                    OverallHealth      = $healthStatus
                    Timestamp          = Get-Date -Format 'o'
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