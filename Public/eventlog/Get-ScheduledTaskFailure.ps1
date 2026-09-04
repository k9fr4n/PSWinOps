#Requires -Version 5.1

function Get-ScheduledTaskFailure {
    <#
    .SYNOPSIS
        Report failed scheduled-task starts and actions from Task Scheduler

    .DESCRIPTION
        Queries the Microsoft-Windows-TaskScheduler/Operational event log for task-start
        and action-failure events over a configurable look-back window. Named EventData
        fields are parsed from event XML so localized message text does not drive extraction.

        Results retain the task path, action, user, raw and hexadecimal result codes, and
        the latest known run time. FailureCount is aggregated per task over the full window,
        results are newest first, and failures on one computer do not stop other targets.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Days
        Look-back window in days. Valid values are 1 through 3650. Defaults to 7.

    .PARAMETER MaxEvents
        Maximum number of Task Scheduler events read per machine. Valid values are 1 through
        10000. Defaults to 200.

    .PARAMETER TaskPath
        Optional case-insensitive filter on the extracted full task path.

    .PARAMETER TaskName
        Optional case-insensitive filter on the extracted task name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for local
        machine queries.

    .EXAMPLE
        Get-ScheduledTaskFailure

        Returns scheduled-task start and action failures from the local computer over the
        last seven days.

    .EXAMPLE
        Get-ScheduledTaskFailure -ComputerName 'SRV01' -Days 30 -TaskPath '\Backup\'

        Returns failures for tasks under the Backup path on SRV01 over the last 30 days.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-ScheduledTaskFailure -MaxEvents 500 -TaskName 'NightlyBackup'

        Returns failures for the named task from multiple computers through pipeline input.

    .OUTPUTS
        PSWinOps.ScheduledTaskFailure
        One object per recognized Task Scheduler failure event, newest first, with the
        number of failures for the task across the selected look-back window.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: Event Log Readers membership for remote or protected Task Scheduler log access
        Requires: WinRM enabled on target machines for remote queries

        Event IDs 101 and 103 represent task/action start failures; 202 and 203 represent
        action completion or launch failures. Classification uses the event ID and named XML
        fields, never localized message text.

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-2-0
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.ScheduledTaskFailure')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]$Days = 7,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10000)]
        [int]$MaxEvents = 200,

        [Parameter(Mandatory = $false)]
        [string]$TaskPath = '',

        [Parameter(Mandatory = $false)]
        [string]$TaskName = '',

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting scheduled task failure query"

        $startTime = (Get-Date).AddDays(-$Days)

        $scriptBlock = {
            param(
                [datetime]$ScanStartTime,
                [int]$MaxEvts,
                [string]$TaskPathFilter,
                [string]$TaskNameFilter
            )

            $failureDefinitions = @{
                101 = 'TaskStartFailure'
                103 = 'ActionStartFailure'
                202 = 'ActionFailure'
                203 = 'ActionLaunchFailure'
            }

            $filter = @{
                LogName   = 'Microsoft-Windows-TaskScheduler/Operational'
                Id        = @(101, 103, 202, 203)
                StartTime = $ScanStartTime
            }

            $eventRecords = @()
            try {
                $eventRecords = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvts -ErrorAction Stop)
            } catch {
                if ($_.Exception.Message -notmatch 'No events were found') {
                    throw
                }
            }

            if ($eventRecords.Count -eq 0) {
                return
            }

            function Get-EventDataMap {
                param(
                    [Parameter(Mandatory = $true)]
                    [object]$Event
                )

                $map = @{}
                try {
                    $xml = [xml]$Event.ToXml()
                    foreach ($node in @($xml.SelectNodes("//*[local-name()='Data']"))) {
                        $name = [string]$node.GetAttribute('Name')
                        if ([string]::IsNullOrWhiteSpace($name)) {
                            continue
                        }

                        $value = [string]$node.InnerText
                        if (-not $map.ContainsKey($name) -or [string]::IsNullOrEmpty([string]$map[$name])) {
                            $map[$name] = $value
                        }
                    }
                } catch {
                    Write-Verbose "Could not parse Task Scheduler event $($Event.Id) as XML: $_"
                }

                return $map
            }

            function Get-EventField {
                param(
                    [Parameter(Mandatory = $true)]
                    [hashtable]$Data,
                    [Parameter(Mandatory = $true)]
                    [string[]]$Names
                )

                foreach ($name in $Names) {
                    if ($Data.ContainsKey($name) -and -not [string]::IsNullOrWhiteSpace([string]$Data[$name])) {
                        return [string]$Data[$name]
                    }
                }

                return ''
            }

            function ConvertTo-ResultCodeHex {
                param(
                    [Parameter(Mandatory = $false)]
                    [string]$Value
                )

                if ([string]::IsNullOrWhiteSpace($Value)) {
                    return ''
                }

                $number = [uint32]0
                if ([uint32]::TryParse($Value.Trim(), [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
                    return ('0x{0:X8}' -f $number)
                }

                $hexValue = $Value.Trim()
                if ($hexValue.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $hexValue = $hexValue.Substring(2)
                }

                if ([uint32]::TryParse($hexValue, [Globalization.NumberStyles]::AllowHexSpecifier, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
                    return ('0x{0:X8}' -f $number)
                }

                return ''
            }

            function Resolve-TaskIdentity {
                param(
                    [Parameter(Mandatory = $true)]
                    [AllowEmptyString()]
                    [string]$RawTaskName,
                    [Parameter(Mandatory = $true)]
                    [AllowEmptyString()]
                    [string]$ExplicitTaskPath
                )

                $taskPathValue = $ExplicitTaskPath
                $taskNameValue = $RawTaskName
                if (-not [string]::IsNullOrWhiteSpace($RawTaskName)) {
                    $separatorIndex = $RawTaskName.LastIndexOf('\')
                    if ($separatorIndex -ge 0) {
                        $taskPathValue = $RawTaskName.Substring(0, $separatorIndex + 1)
                        $taskNameValue = $RawTaskName.Substring($separatorIndex + 1)
                    }
                }

                [PSCustomObject]@{
                    TaskName = $taskNameValue
                    TaskPath = $taskPathValue
                }
            }

            $rows = [System.Collections.Generic.List[psobject]]::new()
            foreach ($eventRecord in @($eventRecords | Sort-Object -Property TimeCreated -Descending)) {
                $eventId = [int]$eventRecord.Id
                if (-not $failureDefinitions.ContainsKey($eventId)) {
                    continue
                }

                $data = Get-EventDataMap -Event $eventRecord
                $rawTaskName = Get-EventField -Data $data -Names @('TaskName', 'Task')
                $explicitTaskPath = Get-EventField -Data $data -Names @('TaskPath', 'Path')
                $taskIdentity = Resolve-TaskIdentity -RawTaskName $rawTaskName -ExplicitTaskPath $explicitTaskPath
                $actionName = Get-EventField -Data $data -Names @('ActionName', 'Action', 'TaskAction', 'Command')
                $userName = Get-EventField -Data $data -Names @('UserName', 'User', 'UserContext', 'PrincipalName', 'AccountName')
                $resultCode = Get-EventField -Data $data -Names @('ResultCode', 'ErrorValue', 'ErrorCode', 'HRESULT', 'Status')
                $lastRunTimeValue = Get-EventField -Data $data -Names @('LastRunTime', 'RunTime', 'StartTime')
                $lastRunTime = $eventRecord.TimeCreated
                if (-not [string]::IsNullOrWhiteSpace($lastRunTimeValue)) {
                    $parsedLastRunTime = [datetime]::MinValue
                    if ([datetime]::TryParse($lastRunTimeValue, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsedLastRunTime)) {
                        $lastRunTime = $parsedLastRunTime
                    }
                }

                $rows.Add([PSCustomObject]@{
                    EventTime     = $eventRecord.TimeCreated
                    EventId       = $eventId
                    TaskName      = $taskIdentity.TaskName
                    TaskPath      = $taskIdentity.TaskPath
                    ActionName    = $actionName
                    UserName      = $userName
                    ResultCode    = $resultCode
                    ResultCodeHex = ConvertTo-ResultCodeHex -Value $resultCode
                    FailureReason = $failureDefinitions[$eventId]
                    LastRunTime   = $lastRunTime
                    Message       = [string]$eventRecord.Message
                })
            }

            $failureTally = @{}
            foreach ($row in $rows) {
                $taskKey = '{0}|{1}' -f ([string]$row.TaskPath).ToLowerInvariant(), ([string]$row.TaskName).ToLowerInvariant()
                if ($failureTally.ContainsKey($taskKey)) {
                    $failureTally[$taskKey]++
                } else {
                    $failureTally[$taskKey] = 1
                }
            }

            foreach ($row in ($rows | Sort-Object -Property EventTime -Descending)) {
                if (-not [string]::IsNullOrWhiteSpace($TaskPathFilter) -and $row.TaskPath -ine $TaskPathFilter) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($TaskNameFilter) -and $row.TaskName -ine $TaskNameFilter) {
                    continue
                }

                $taskKey = '{0}|{1}' -f ([string]$row.TaskPath).ToLowerInvariant(), ([string]$row.TaskName).ToLowerInvariant()
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.ScheduledTaskFailure'
                    ComputerName   = $env:COMPUTERNAME
                    EventTime      = $row.EventTime.ToString('o')
                    EventId        = $row.EventId
                    TaskName       = $row.TaskName
                    TaskPath       = $row.TaskPath
                    ActionName     = $row.ActionName
                    UserName       = $row.UserName
                    ResultCode     = $row.ResultCode
                    ResultCodeHex  = $row.ResultCodeHex
                    FailureReason  = $row.FailureReason
                    LastRunTime    = $row.LastRunTime.ToString('o')
                    FailureCount   = $failureTally[$taskKey]
                    Message        = $row.Message
                    Timestamp      = Get-Date -Format 'o'
                }
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying scheduled task failures on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($startTime, $MaxEvents, $TaskPath, $TaskName)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed scheduled task failure query"
    }
}
