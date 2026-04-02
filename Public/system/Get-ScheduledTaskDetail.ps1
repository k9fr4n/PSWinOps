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
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            param($FilterTaskPath, $FilterTaskName, $InclMicrosoft)

            $allTasks = @(Get-ScheduledTask -ErrorAction Stop)

            if ($FilterTaskPath) {
                $allTasks = @($allTasks | Where-Object -FilterScript { $_.TaskPath -like $FilterTaskPath })
            }
            if (-not $InclMicrosoft) {
                $allTasks = @($allTasks | Where-Object -FilterScript { $_.TaskPath -notlike '\Microsoft\*' })
            }
            if ($FilterTaskName) {
                $allTasks = @($allTasks | Where-Object -FilterScript { $_.TaskName -like $FilterTaskName })
            }

            foreach ($task in $allTasks) {
                $runInfo = $null
                try {
                    $runInfo = ScheduledTasks\Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
                } catch {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Could not retrieve run info for '$($task.TaskPath)$($task.TaskName)': $_"
                }

                [PSCustomObject]@{
                    TaskName       = $task.TaskName
                    TaskPath       = $task.TaskPath
                    State          = $task.State.ToString()
                    LastRunTime    = if ($runInfo) { $runInfo.LastRunTime } else { $null }
                    LastTaskResult = if ($runInfo) { $runInfo.LastTaskResult } else { $null }
                    NextRunTime    = if ($runInfo) { $runInfo.NextRunTime } else { $null }
                    Author         = $task.Author
                    Description    = $task.Description
                }
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying scheduled tasks on '$machine'"

                $argList = @(
                    $(if ($PSBoundParameters.ContainsKey('TaskPath')) { $TaskPath } else { $null }),
                    $(if ($PSBoundParameters.ContainsKey('TaskName')) { $TaskName } else { $null }),
                    $IncludeMicrosoftTasks.IsPresent
                )

                $rawTasks = @(Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -ArgumentList $argList -Credential $Credential)

                if ($rawTasks.Count -eq 0) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No matching tasks found on '$machine'"
                    continue
                }

                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Found $($rawTasks.Count) task(s) on '$machine'"

                foreach ($task in $rawTasks) {
                    $resultMessage = ConvertTo-ScheduledTaskResultMessage -ResultCode $task.LastTaskResult

                    [PSCustomObject]@{
                        PSTypeName        = 'PSWinOps.ScheduledTaskDetail'
                        ComputerName      = $machine
                        TaskName          = $task.TaskName
                        TaskPath          = $task.TaskPath
                        State             = $task.State
                        LastRunTime       = $task.LastRunTime
                        LastTaskResult    = $task.LastTaskResult
                        LastResultMessage = $resultMessage
                        NextRunTime       = $task.NextRunTime
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
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
