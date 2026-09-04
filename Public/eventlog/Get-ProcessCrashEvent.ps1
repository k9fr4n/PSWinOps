#Requires -Version 5.1

function Get-ProcessCrashEvent {
    <#
    .SYNOPSIS
        Report application crashes and hangs from the Windows Application log

    .DESCRIPTION
        Queries the Application event log for Application Error, Windows Error Reporting,
        and optionally Application Hang events over a configurable look-back window. Named
        EventData fields are parsed from event XML so localized message text and unstable
        Properties indexes do not affect the core crash details.

        Windows Error Reporting events enrich crash correlation through their report ID but
        never produce a second output row. Results are aggregated by executable name before
        the optional process filter is applied, then returned newest first for each machine.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for
        local machine queries.

    .PARAMETER Days
        Look-back window in days. Valid values are 1 through 3650. Defaults to 7.

    .PARAMETER MaxEvents
        Maximum number of Application log events read per machine. The event query is
        newest first and may truncate the requested window when the limit is reached.
        Valid values are 1 through 10000. Defaults to 200.

    .PARAMETER ProcessName
        Optional executable name filter without a path. Matching is case-insensitive and
        is applied after CrashCount has been calculated over all parsed crash and hang rows.

    .PARAMETER IncludeHang
        Include Application Hang event 1002 rows in addition to Application Error 1000
        crash rows. Windows Error Reporting event 1001 is used only for correlation.

    .EXAMPLE
        Get-ProcessCrashEvent

        Returns application crash events for the local computer from the last seven days.

    .EXAMPLE
        Get-ProcessCrashEvent -ComputerName 'SRV01' -Days 30 -ProcessName 'w3wp.exe'

        Returns IIS worker-process crashes from SRV01 over the last 30 days.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-ProcessCrashEvent -MaxEvents 500 -IncludeHang

        Returns crash and hang events from multiple computers through pipeline input.

    .OUTPUTS
        PSWinOps.ProcessCrashEvent
        One object per Application Error 1000 crash and, when requested, Application Hang
        1002 event. Windows Error Reporting 1001 events are correlated and do not emit rows.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: Event Log Readers membership for remote or protected Application log access
        Requires: WinRM enabled on target machines for remote queries

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/windows/win32/eventlog/event-logging
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.ProcessCrashEvent')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]$Days = 7,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10000)]
        [int]$MaxEvents = 200,

        [Parameter(Mandatory = $false)]
        [string]$ProcessName = '',

        [Parameter(Mandatory = $false)]
        [switch]$IncludeHang
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting process crash event query"

        $startTime = (Get-Date).AddDays(-$Days)

        $scriptBlock = {
            param(
                [datetime]$ScanStartTime,
                [int]$MaxEvts,
                [string]$ProcessNameFilter,
                [bool]$IncludeHangEvents
            )

            $eventIds = @(1000, 1001)
            if ($IncludeHangEvents) {
                $eventIds += 1002
            }

            $filter = @{
                LogName   = 'Application'
                Id        = $eventIds
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

            $eventRecords = @($eventRecords | Sort-Object -Property TimeCreated -Descending)

            function Get-EventDataMap {
                param(
                    [Parameter(Mandatory = $true)]
                    [object]$Event
                )

                $map = @{}
                try {
                    $xml = [xml]$Event.ToXml()
                    $dataNodes = @($xml.SelectNodes("//*[local-name()='Data']"))
                    foreach ($node in $dataNodes) {
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
                    Write-Verbose "Could not parse event $($Event.Id) as XML: $_"
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
                    if ($Data.ContainsKey($name) -and -not [string]::IsNullOrEmpty([string]$Data[$name])) {
                        return [string]$Data[$name]
                    }
                }

                return ''
            }

            function Get-ExecutableName {
                param(
                    [Parameter(Mandatory = $true)]
                    [hashtable]$Data
                )

                $value = Get-EventField -Data $Data -Names @(
                    'AppName', 'ProcessName', 'ApplicationName', 'ExeFileName', 'Parameter1'
                )
                if ([string]::IsNullOrWhiteSpace($value)) {
                    return ''
                }

                try {
                    return [System.IO.Path]::GetFileName($value)
                } catch {
                    return $value
                }
            }

            function Get-UserName {
                param(
                    [Parameter(Mandatory = $true)]
                    [object]$Event,
                    [Parameter(Mandatory = $true)]
                    [hashtable]$Data
                )

                $userName = Get-EventField -Data $Data -Names @('UserName', 'User')
                if (-not [string]::IsNullOrEmpty($userName)) {
                    return $userName
                }

                if ($null -ne $Event.UserId) {
                    try {
                        return $Event.UserId.Translate([System.Security.Principal.NTAccount]).Value
                    } catch {
                        Write-Verbose "Could not translate event user SID: $_"
                    }
                }

                return ''
            }

            $werByReportId = @{}
            foreach ($eventRecord in $eventRecords) {
                if ([int]$eventRecord.Id -ne 1001) {
                    continue
                }

                $data = Get-EventDataMap -Event $eventRecord
                $reportId = Get-EventField -Data $data -Names @('ReportId', 'ReportID', 'IntegratorReportId')
                if (-not [string]::IsNullOrWhiteSpace($reportId)) {
                    $werByReportId[$reportId.ToLowerInvariant()] = [PSCustomObject]@{
                        ReportId    = $reportId
                        ProcessName = Get-ExecutableName -Data $data
                        TimeCreated = $eventRecord.TimeCreated
                    }
                }
            }

            $rows = [System.Collections.Generic.List[psobject]]::new()
            foreach ($eventRecord in $eventRecords) {
                $eventRecordId = [int]$eventRecord.Id
                if ($eventRecordId -eq 1001 -or ($eventRecordId -eq 1002 -and -not $IncludeHangEvents)) {
                    continue
                }

                $data = Get-EventDataMap -Event $eventRecord
                $eventRecordType = if ($eventRecordId -eq 1002) { 'Hang' } else { 'Crash' }
                $processName = Get-ExecutableName -Data $data
                $processPath = Get-EventField -Data $data -Names @('AppPath', 'ProcessPath', 'ExePath')
                $faultingModule = Get-EventField -Data $data -Names @('ModuleName', 'FaultingModule', 'FaultingModuleName')
                $exceptionCode = Get-EventField -Data $data -Names @('ExceptionCode', 'Exception')
                $faultingOffset = Get-EventField -Data $data -Names @('FaultingOffset', 'Offset')
                $reportId = Get-EventField -Data $data -Names @('IntegratorReportId', 'ReportId', 'ReportID')

                if (-not [string]::IsNullOrWhiteSpace($reportId) -and $werByReportId.ContainsKey($reportId.ToLowerInvariant())) {
                    $reportId = $werByReportId[$reportId.ToLowerInvariant()].ReportId
                }

                if ([string]::IsNullOrWhiteSpace($reportId)) {
                    $matchingWer = @($werByReportId.Values | Where-Object {
                        -not [string]::IsNullOrWhiteSpace($processName) -and
                        $_.ProcessName -ieq $processName -and
                        $null -ne $_.TimeCreated -and
                        $null -ne $eventRecord.TimeCreated -and
                        [math]::Abs(($_.TimeCreated - $eventRecord.TimeCreated).TotalMinutes) -le 5
                    } | Sort-Object -Property TimeCreated | Select-Object -First 1)
                    if ($matchingWer.Count -gt 0) {
                        $reportId = $matchingWer[0].ReportId
                    }
                }

                $rows.Add([PSCustomObject]@{
                    EventTime      = $eventRecord.TimeCreated
                    EventId        = $eventRecordId
                    EventType      = $eventRecordType
                    ProcessName    = $processName
                    ProcessPath    = $processPath
                    FaultingModule = $faultingModule
                    ExceptionCode  = $exceptionCode
                    FaultingOffset = $faultingOffset
                    ReportId       = $reportId
                    UserName       = Get-UserName -Event $eventRecord -Data $data
                    Message        = [string]$eventRecord.Message
                })
            }

            $crashTally = @{}
            foreach ($row in $rows) {
                $key = ([string]$row.ProcessName).ToLowerInvariant()
                if ($crashTally.ContainsKey($key)) {
                    $crashTally[$key]++
                } else {
                    $crashTally[$key] = 1
                }
            }

            foreach ($row in ($rows | Sort-Object -Property EventTime -Descending)) {
                if (-not [string]::IsNullOrWhiteSpace($ProcessNameFilter) -and $row.ProcessName -ine $ProcessNameFilter) {
                    continue
                }

                [PSCustomObject]@{
                    PSTypeName       = 'PSWinOps.ProcessCrashEvent'
                    ComputerName     = $env:COMPUTERNAME
                    EventTime        = $row.EventTime.ToString('o')
                    EventId          = $row.EventId
                    EventType        = $row.EventType
                    ProcessName      = $row.ProcessName
                    ProcessPath      = $row.ProcessPath
                    FaultingModule   = $row.FaultingModule
                    ExceptionCode    = $row.ExceptionCode
                    FaultingOffset   = $row.FaultingOffset
                    ReportId         = $row.ReportId
                    UserName         = $row.UserName
                    CrashCount       = $crashTally[([string]$row.ProcessName).ToLowerInvariant()]
                    Message          = $row.Message
                    Timestamp        = Get-Date -Format 'o'
                }
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying process crash events on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($startTime, $MaxEvents, $ProcessName, [bool]$IncludeHang)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed process crash event query"
    }
}
