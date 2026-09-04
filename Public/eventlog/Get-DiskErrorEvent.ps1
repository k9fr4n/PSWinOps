#Requires -Version 5.1

function Get-DiskErrorEvent {
    <#
    .SYNOPSIS
        Report disk, controller, NTFS, and storage errors from the System log

    .DESCRIPTION
        Queries the Windows System event log for known Disk, Ntfs, storahci, and storport
        error events over a configurable look-back window. Named EventData fields are
        parsed from event XML so localized message text does not drive classification.

        Results are classified from centralized provider and event-ID mappings, aggregated
        by provider, error type, and device, and returned newest first for each machine.
        Missing event fields remain empty or null, and remote failures do not stop other
        computers from being processed.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Days
        Look-back window in days. Valid values are 1 through 3650. Defaults to 7.

    .PARAMETER MaxEvents
        Maximum number of System log events read per machine. Valid values are 1 through
        10000. Defaults to 200.

    .PARAMETER DiskNumber
        Optional disk number filter. Events without a disk number are excluded when this
        filter is specified.

    .PARAMETER CriticalOnly
        Return only events classified as critical or likely to indicate hardware failure.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for local
        machine queries.

    .EXAMPLE
        Get-DiskErrorEvent

        Returns recognized disk and storage errors from the local computer over the last
        seven days.

    .EXAMPLE
        Get-DiskErrorEvent -ComputerName 'SRV01' -Days 30 -CriticalOnly

        Returns critical storage errors from SRV01 over the last 30 days.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-DiskErrorEvent -MaxEvents 500 -DiskNumber 0

        Returns disk-zero errors from multiple computers through pipeline input.

    .OUTPUTS
        PSWinOps.DiskErrorEvent
        One object per recognized storage event, newest first, with classification and
        an EventCount aggregated over the selected look-back window.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: Event Log Readers membership for remote or protected System log access
        Requires: WinRM enabled on target machines for remote queries

        IsCritical is deterministic: BadBlock, ControllerReset, and FileSystem are critical;
        IoTimeout is non-critical unless the event is mapped to a provider/ID marked critical;
        Unknown is non-critical. Localized Message text is never used for classification.

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.DiskErrorEvent')]
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
        [ValidateRange(0, 2147483647)]
        [Nullable[int]]$DiskNumber,

        [Parameter(Mandatory = $false)]
        [switch]$CriticalOnly,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting disk error event query"

        $startTime = (Get-Date).AddDays(-$Days)
        $diskFilter = if ($DiskNumber -ge 0) { $DiskNumber } else { $null }

        $scriptBlock = {
            param(
                [datetime]$ScanStartTime,
                [int]$MaxEvts,
                [Nullable[int]]$DiskNumberFilter,
                [bool]$CriticalOnlyFilter
            )

            $eventDefinitions = @{
                'disk|7'       = [PSCustomObject]@{ ErrorType = 'BadBlock';        IsCritical = $true  }
                'disk|51'      = [PSCustomObject]@{ ErrorType = 'IoTimeout';       IsCritical = $false }
                'disk|154'     = [PSCustomObject]@{ ErrorType = 'IoTimeout';       IsCritical = $true  }
                'ntfs|55'      = [PSCustomObject]@{ ErrorType = 'FileSystem';      IsCritical = $true  }
                'storahci|129' = [PSCustomObject]@{ ErrorType = 'ControllerReset'; IsCritical = $true  }
                'storahci|153' = [PSCustomObject]@{ ErrorType = 'IoTimeout';       IsCritical = $false }
                'storport|129' = [PSCustomObject]@{ ErrorType = 'ControllerReset'; IsCritical = $true  }
                'storport|153' = [PSCustomObject]@{ ErrorType = 'IoTimeout';       IsCritical = $false }
            }

            $filter = @{
                LogName      = 'System'
                ProviderName = @('Disk', 'Ntfs', 'storahci', 'storport')
                Id           = @(7, 51, 55, 129, 153, 154)
                StartTime    = $ScanStartTime
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

                        $map[$name] = [string]$node.InnerText
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
                    if ($Data.ContainsKey($name) -and -not [string]::IsNullOrWhiteSpace([string]$Data[$name])) {
                        return [string]$Data[$name]
                    }
                }

                return ''
            }

            function ConvertTo-DiskNumber {
                param(
                    [string]$Value
                )

                if ([string]::IsNullOrWhiteSpace($Value)) {
                    return $null
                }

                $match = [regex]::Match($Value, '^\s*(\d+)\s*$')
                if ($match.Success) {
                    return [int]$match.Groups[1].Value
                }

                $match = [regex]::Match($Value, '(?i)harddisk(\d+)')
                if ($match.Success) {
                    return [int]$match.Groups[1].Value
                }

                return $null
            }

            $rows = [System.Collections.Generic.List[psobject]]::new()
            foreach ($eventRecord in @($eventRecords | Sort-Object -Property TimeCreated -Descending)) {
                $providerName = [string]$eventRecord.ProviderName
                $eventId = [int]$eventRecord.Id
                $definitionKey = "$($providerName.ToLowerInvariant())|$eventId"
                if (-not $eventDefinitions.ContainsKey($definitionKey)) {
                    continue
                }

                $data = Get-EventDataMap -Event $eventRecord
                $deviceName = Get-EventField -Data $data -Names @('DeviceName', 'Device')
                $devicePath = Get-EventField -Data $data -Names @('DevicePath', 'TargetDevice', 'Path')
                $diskNumberValue = Get-EventField -Data $data -Names @('DiskNumber', 'DeviceNumber', 'TargetDeviceNumber')
                $diskNumberFromData = ConvertTo-DiskNumber -Value $diskNumberValue
                if ($null -eq $diskNumberFromData) {
                    $diskNumberFromData = ConvertTo-DiskNumber -Value $deviceName
                }
                if ($null -eq $diskNumberFromData) {
                    $diskNumberFromData = ConvertTo-DiskNumber -Value $devicePath
                }

                $definition = $eventDefinitions[$definitionKey]
                $errorType = $definition.ErrorType
                $isCritical = [bool]$definition.IsCritical
                if ($data.Count -eq 0) {
                    $errorType = 'Unknown'
                    $isCritical = $false
                }

                $rows.Add([PSCustomObject]@{
                    EventTime    = $eventRecord.TimeCreated
                    ProviderName = $providerName
                    EventId      = $eventId
                    ErrorType    = $errorType
                    IsCritical   = $isCritical
                    DiskNumber   = $diskNumberFromData
                    DeviceName   = $deviceName
                    DevicePath   = $devicePath
                    ErrorCode    = Get-EventField -Data $data -Names @('ErrorCode', 'Error', 'Status')
                    RetryCount   = ConvertTo-DiskNumber -Value (Get-EventField -Data $data -Names @('RetryCount', 'Retries'))
                    Message      = [string]$eventRecord.Message
                })
            }

            $eventTally = @{}
            foreach ($row in $rows) {
                $diskKey = if ($null -eq $row.DiskNumber) { '' } else { [string]$row.DiskNumber }
                $key = '{0}|{1}|{2}|{3}|{4}' -f $row.ProviderName.ToLowerInvariant(), $row.ErrorType, $diskKey, $row.DeviceName, $row.DevicePath
                if ($eventTally.ContainsKey($key)) {
                    $eventTally[$key]++
                } else {
                    $eventTally[$key] = 1
                }
            }

            foreach ($row in ($rows | Sort-Object -Property EventTime -Descending)) {
                if ($null -ne $DiskNumberFilter -and $row.DiskNumber -ne $DiskNumberFilter) {
                    continue
                }
                if ($CriticalOnlyFilter -and -not $row.IsCritical) {
                    continue
                }

                $diskKey = if ($null -eq $row.DiskNumber) { '' } else { [string]$row.DiskNumber }
                $key = '{0}|{1}|{2}|{3}|{4}' -f $row.ProviderName.ToLowerInvariant(), $row.ErrorType, $diskKey, $row.DeviceName, $row.DevicePath

                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.DiskErrorEvent'
                    ComputerName = $env:COMPUTERNAME
                    EventTime    = $row.EventTime.ToString('o')
                    ProviderName = $row.ProviderName
                    EventId      = $row.EventId
                    ErrorType    = $row.ErrorType
                    IsCritical   = $row.IsCritical
                    DiskNumber   = $row.DiskNumber
                    DeviceName   = $row.DeviceName
                    DevicePath   = $row.DevicePath
                    ErrorCode    = $row.ErrorCode
                    RetryCount   = $row.RetryCount
                    EventCount   = $eventTally[$key]
                    Message      = $row.Message
                    Timestamp    = Get-Date -Format 'o'
                }
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying disk error events on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($startTime, $MaxEvents, $diskFilter, [bool]$CriticalOnly)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed disk error event query"
    }
}
