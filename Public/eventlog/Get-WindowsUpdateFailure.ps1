#Requires -Version 5.1

function Get-WindowsUpdateFailure {
    <#
    .SYNOPSIS
        Report Windows Update failures and restart requirements from the System log

    .DESCRIPTION
        Queries the Microsoft-Windows-WindowsUpdateClient provider in the System event log
        for failed installations, required restarts, and optionally successful installations.
        Named XML EventData fields are parsed so localized event message text does not drive
        classification or extraction.

        Results include the update identity, KB article, raw and hexadecimal error codes,
        restart status, and event message. Results are newest first, and an error on one
        computer does not stop the remaining computers from being processed.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Days
        Look-back window in days. Valid values are 1 through 3650. Defaults to 30.

    .PARAMETER MaxEvents
        Maximum number of Windows Update events read per machine. Valid values are 1 through
        10000. Defaults to 200. The most recent events are prioritized when the log is larger.

    .PARAMETER KBArticle
        Optional case-insensitive filter for the extracted KB article, such as KB5030211.

    .PARAMETER UpdateTitle
        Optional case-insensitive substring filter for the update title.

    .PARAMETER IncludeSuccess
        Includes event ID 19 successful installations in addition to failures and required
        restart events.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for local
        machine queries.

    .EXAMPLE
        Get-WindowsUpdateFailure

        Returns failed Windows Update installations and required restarts from the local
        computer over the last 30 days.

    .EXAMPLE
        Get-WindowsUpdateFailure -ComputerName 'SRV01' -Days 90 -KBArticle 'KB5030211'

        Returns matching Windows Update events from SRV01 over the last 90 days.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-WindowsUpdateFailure -MaxEvents 500 -IncludeSuccess

        Returns failures, required restarts, and successful installations from multiple
        computers through pipeline input.

    .OUTPUTS
        PSWinOps.WindowsUpdateFailure
        One object per recognized Windows Update event, newest first, with status, update
        identity, error information, restart state, and the raw event message.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: Event Log Readers membership for remote or protected System log access
        Requires: WinRM enabled on target machines for remote queries

        Event IDs 20, 21, and 19 represent installation failure, restart required, and
        installation success respectively. EventData XML is used for extraction; localized
        Message text is retained for context only and is never used for classification.

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.WindowsUpdateFailure')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]$Days = 30,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10000)]
        [int]$MaxEvents = 200,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$KBArticle = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$UpdateTitle = '',

        [Parameter(Mandatory = $false)]
        [switch]$IncludeSuccess,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting Windows Update failure query"

        $startTime = (Get-Date).AddDays(-$Days)

        $scriptBlock = {
            param(
                [datetime]$ScanStartTime,
                [int]$MaxEvts,
                [bool]$IncludeSuccessFilter,
                [string]$KBArticleFilter,
                [string]$UpdateTitleFilter
            )

            $eventIds = @(20, 21)
            if ($IncludeSuccessFilter) {
                $eventIds += 19
            }

            $filter = @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
                Id           = $eventIds
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
                    Write-Verbose "Could not parse Windows Update event $($Event.Id) as XML: $_"
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

            function ConvertTo-ErrorCodeHex {
                param(
                    [Parameter(Mandatory = $false)]
                    [string]$Value
                )

                if ([string]::IsNullOrWhiteSpace($Value)) {
                    return ''
                }

                $rawValue = $Value.Trim()
                $signedNumber = [int64]0
                if ([int64]::TryParse(
                        $rawValue,
                        [Globalization.NumberStyles]::Integer,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$signedNumber)) {
                    $unsignedValue = $signedNumber
                    if ($signedNumber -lt 0) {
                        $unsignedValue += 4294967296
                    }
                    return ('0x{0:X8}' -f $unsignedValue)
                }

                $hexValue = $rawValue -replace '^0x', ''
                $unsignedNumber = [uint32]0
                if ([uint32]::TryParse(
                        $hexValue,
                        [Globalization.NumberStyles]::AllowHexSpecifier,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$unsignedNumber)) {
                    return ('0x{0:X8}' -f $unsignedNumber)
                }

                return ''
            }

            $rows = [System.Collections.Generic.List[psobject]]::new()
            foreach ($eventRecord in @($eventRecords | Sort-Object -Property TimeCreated -Descending)) {
                $eventId = [int]$eventRecord.Id
                if ($eventId -eq 19 -and -not $IncludeSuccessFilter) {
                    continue
                }

                $status = switch ($eventId) {
                    19 { 'Succeeded' }
                    20 { 'Failed' }
                    21 { 'RebootRequired' }
                    default { continue }
                }

                $data = Get-EventDataMap -Event $eventRecord
                $updateTitleValue = Get-EventField -Data $data -Names @('UpdateTitle', 'Title', 'UpdateName')
                $updateIdValue = Get-EventField -Data $data -Names @('UpdateId', 'UpdateGUID', 'UpdateGuid', 'UpdateIdentity')
                $kbArticleValue = Get-EventField -Data $data -Names @('KBArticle', 'KBNumber', 'KB')
                if ([string]::IsNullOrWhiteSpace($kbArticleValue) -and -not [string]::IsNullOrWhiteSpace($updateTitleValue)) {
                    $kbMatch = [regex]::Match($updateTitleValue, '(?i)\bKB\d+\b')
                    if ($kbMatch.Success) {
                        $kbArticleValue = $kbMatch.Value
                    }
                }

                $errorCodeValue = Get-EventField -Data $data -Names @('ErrorCode', 'HResult', 'HRESULT', 'ResultCode', 'Error')
                $failureReasonValue = Get-EventField -Data $data -Names @('FailureReason', 'ErrorDescription', 'Reason')
                if ([string]::IsNullOrWhiteSpace($failureReasonValue)) {
                    $failureReasonValue = switch ($eventId) {
                        20 { 'InstallationFailure' }
                        21 { 'RestartRequired' }
                        default { '' }
                    }
                }

                $rows.Add([PSCustomObject]@{
                    EventTime       = $eventRecord.TimeCreated
                    EventId         = $eventId
                    Status          = $status
                    KBArticle       = $kbArticleValue
                    UpdateTitle     = $updateTitleValue
                    UpdateId        = $updateIdValue
                    ErrorCode       = $errorCodeValue
                    ErrorCodeHex    = ConvertTo-ErrorCodeHex -Value $errorCodeValue
                    RebootRequired  = ($eventId -eq 21)
                    FailureReason   = $failureReasonValue
                    Message         = [string]$eventRecord.Message
                })
            }

            foreach ($row in ($rows | Sort-Object -Property EventTime -Descending)) {
                if (-not [string]::IsNullOrWhiteSpace($KBArticleFilter) -and
                    ([string]$row.KBArticle).IndexOf($KBArticleFilter, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($UpdateTitleFilter) -and
                    ([string]$row.UpdateTitle).IndexOf($UpdateTitleFilter, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    continue
                }

                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.WindowsUpdateFailure'
                    ComputerName    = $env:COMPUTERNAME
                    EventTime       = $row.EventTime.ToString('o')
                    EventId         = $row.EventId
                    Status          = $row.Status
                    KBArticle       = $row.KBArticle
                    UpdateTitle     = $row.UpdateTitle
                    UpdateId        = $row.UpdateId
                    ErrorCode       = $row.ErrorCode
                    ErrorCodeHex    = $row.ErrorCodeHex
                    RebootRequired  = $row.RebootRequired
                    FailureReason   = $row.FailureReason
                    Message         = $row.Message
                    Timestamp       = Get-Date -Format 'o'
                }
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying Windows Update failures on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($startTime, $MaxEvents, $IncludeSuccess.IsPresent, $KBArticle, $UpdateTitle)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed Windows Update failure query"
    }
}
