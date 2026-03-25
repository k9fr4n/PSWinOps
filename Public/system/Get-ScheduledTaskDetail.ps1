#Requires -Version 5.1
function Get-ScheduledTaskDetail {
    <#
        .SYNOPSIS
            Retrieves scheduled task details from local or remote computers

        .DESCRIPTION
            Queries the ScheduledTasks CIM namespace to enumerate scheduled tasks and their
            last/next run details. Returns typed PSWinOps.ScheduledTaskDetail objects with
            human-readable HRESULT translation. Microsoft built-in tasks are excluded by
            default to reduce noise.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER TaskPath
            Filter tasks by folder path. Defaults to all paths.
            Supports wildcards. Example: '\Backup\*'

        .PARAMETER TaskName
            Filter tasks by name using -like matching.
            Supports wildcards. Example: 'Backup*'

        .PARAMETER IncludeMicrosoftTasks
            Include tasks under the '\Microsoft\' path hierarchy.
            These are excluded by default as there are typically hundreds of built-in tasks.

        .PARAMETER Credential
            PSCredential object for remote authentication.
            Used when creating CimSessions to remote machines.

        .EXAMPLE
            Get-ScheduledTaskDetail

            Retrieves all non-Microsoft scheduled tasks from the local computer.

        .EXAMPLE
            Get-ScheduledTaskDetail -ComputerName 'SRV01' -TaskName 'Backup*' -Credential (Get-Credential)

            Retrieves scheduled tasks matching 'Backup*' on SRV01 with explicit credentials.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-ScheduledTaskDetail -TaskPath '\Maintenance\*' -IncludeMicrosoftTasks

            Queries multiple servers via pipeline for tasks in the Maintenance folder.

        .OUTPUTS
            PSWinOps.ScheduledTaskDetail
            Returns one object per scheduled task with ComputerName, TaskName, TaskPath,
            State, LastRunTime, LastTaskResult, LastResultMessage, NextRunTime, Author,
            Description, and Timestamp.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-25
            Requires: PowerShell 5.1+ / Windows only
            Requires: ScheduledTasks module (built-in on Windows 8+ / Server 2012+)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/get-scheduledtask
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ScheduledTaskDetail')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$TaskPath,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$TaskName,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeMicrosoftTasks,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
    }

    process {
        foreach ($machine in $ComputerName) {
            $cimSession = $null

            try {
                $isLocal = $localNames -contains $machine

                # --- Build or skip CimSession ---
                $taskParams = @{ ErrorAction = 'Stop' }

                if (-not $isLocal) {
                    $sessionParams = @{
                        ComputerName = $machine
                        ErrorAction  = 'Stop'
                    }
                    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                        $sessionParams['Credential'] = $Credential
                    }
                    $cimSession = New-CimSession @sessionParams
                    $taskParams['CimSession'] = $cimSession
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] CimSession established to '$machine'"
                }

                # --- Retrieve all scheduled tasks ---
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying scheduled tasks on '$machine'"
                $allTasks = @(Get-ScheduledTask @taskParams)

                # --- Filter by TaskPath ---
                if ($PSBoundParameters.ContainsKey('TaskPath')) {
                    $allTasks = @($allTasks | Where-Object -FilterScript {
                        $_.TaskPath -like $TaskPath
                    })
                }

                # --- Exclude Microsoft tasks unless requested ---
                if (-not $IncludeMicrosoftTasks) {
                    $allTasks = @($allTasks | Where-Object -FilterScript {
                        $_.TaskPath -notlike '\Microsoft\*'
                    })
                }

                # --- Filter by TaskName if specified ---
                if ($PSBoundParameters.ContainsKey('TaskName')) {
                    $allTasks = @($allTasks | Where-Object -FilterScript {
                        $_.TaskName -like $TaskName
                    })
                }

                if ($allTasks.Count -eq 0) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No matching tasks found on '$machine'"
                    continue
                }

                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Found $($allTasks.Count) task(s) on '$machine'"

                # --- Process each task ---
                foreach ($task in $allTasks) {
                    $runInfo = $null
                    try {
                        $infoParams = @{
                            TaskName    = $task.TaskName
                            TaskPath    = $task.TaskPath
                            ErrorAction = 'SilentlyContinue'
                        }
                        if ($cimSession) {
                            $infoParams['CimSession'] = $cimSession
                        }
                        # Module-qualified call to avoid recursion with our function name
                        $runInfo = ScheduledTasks\Get-ScheduledTaskInfo @infoParams
                    }
                    catch {
                        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Could not get run info for '$($task.TaskPath)$($task.TaskName)' on '$machine'"
                    }

                    $resultCode = if ($runInfo) { $runInfo.LastTaskResult } else { $null }
                    $resultMessage = ConvertTo-ScheduledTaskResultMessage -ResultCode $resultCode

                    [PSCustomObject]@{
                        PSTypeName        = 'PSWinOps.ScheduledTaskDetail'
                        ComputerName      = if ($isLocal) { $env:COMPUTERNAME } else { $machine }
                        TaskName          = $task.TaskName
                        TaskPath          = $task.TaskPath
                        State             = $task.State.ToString()
                        LastRunTime       = if ($runInfo) { $runInfo.LastRunTime } else { $null }
                        LastTaskResult    = $resultCode
                        LastResultMessage = $resultMessage
                        NextRunTime       = if ($runInfo) { $runInfo.NextRunTime } else { $null }
                        Author            = $task.Author
                        Description       = $task.Description
                        Timestamp         = Get-Date -Format 'o'
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                continue
            }
            finally {
                if ($cimSession) {
                    Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] CimSession closed for '$machine'"
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
