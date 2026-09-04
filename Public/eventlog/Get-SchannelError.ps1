#Requires -Version 5.1

function Get-SchannelError {
    <#
    .SYNOPSIS
        Report Schannel TLS, certificate, and negotiation failures from the System log

    .DESCRIPTION
        Queries the Schannel provider in the Windows System event log for common TLS and
        certificate failures. Event XML is parsed for stable diagnostic fields so localized
        message text does not drive classification or extraction.

        Results classify each failure as Certificate, Protocol, Cipher, Alert, or Unknown,
        aggregate equivalent occurrences, and return newest events first. Missing XML fields
        remain empty, sensitive key and secret fields are never extracted, and a failure on one
        computer does not stop the remaining computers from being processed.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Days
        Look-back window in days. Valid values are 1 through 3650. Defaults to 7.

    .PARAMETER MaxEvents
        Maximum number of Schannel events read per machine. Valid values are 1 through
        10000. Defaults to 200.

    .PARAMETER EventId
        Optional Schannel event IDs to query. Defaults to 36870, 36871, 36874, and 36888.

    .PARAMETER RemoteHost
        Optional case-insensitive filter applied after XML parsing to the extracted peer name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for local
        machine queries.

    .EXAMPLE
        Get-SchannelError

        Returns Schannel errors from the local computer over the last seven days.

    .EXAMPLE
        Get-SchannelError -ComputerName 'SRV01' -Days 30 -RemoteHost 'api.example.com'

        Returns matching Schannel failures from SRV01 involving the specified peer.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-SchannelError -MaxEvents 500 -EventId 36888

        Returns generated fatal TLS alerts from multiple computers through pipeline input.

    .OUTPUTS
        PSWinOps.SchannelError
        One object per parsed Schannel event, newest first, with normalized classification,
        extracted XML fields, a FailureCount for equivalent events, and a safe message.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: Event Log Readers membership for remote or protected System log access
        Requires: WinRM enabled on target machines for remote queries

        Event IDs 36870, 36871, 36874, and 36888 are queried by default. Private keys,
        passwords, tokens, and secret fields are deliberately excluded from the output.

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.SchannelError')]
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
        [ValidateNotNullOrEmpty()]
        [int[]]$EventId = @(36870, 36871, 36874, 36888),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$RemoteHost = '',

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting Schannel error query"

        $startTime = (Get-Date).AddDays(-$Days)

        $scriptBlock = {
            param(
                [datetime]$ScanStartTime,
                [int]$MaxEvts,
                [int[]]$EventIdFilter,
                [string]$RemoteHostFilter
            )

            $filter = @{
                LogName      = 'System'
                ProviderName = 'Schannel'
                Id           = $EventIdFilter
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

                    return [PSCustomObject]@{
                        Parsed = $true
                        Data   = $map
                    }
                } catch {
                    Write-Verbose "Could not parse Schannel event $($Event.Id) as XML: $_"
                    return [PSCustomObject]@{
                        Parsed = $false
                        Data   = $map
                    }
                }
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

            function ConvertTo-SafeMessage {
                param(
                    [AllowEmptyString()]
                    [string]$Message
                )

                if ([string]::IsNullOrWhiteSpace($Message)) {
                    return ''
                }

                $safeMessage = [regex]::Replace(
                    $Message,
                    '(?is)-----BEGIN [^-]+-----.*?-----END [^-]+-----',
                    '[REDACTED-KEY]'
                )
                $safeMessage = [regex]::Replace(
                    $safeMessage,
                    '(?im)\b(password|passwd|secret|token|private\s*key)\s*[:=]\s*[^;\r\n]+',
                    '$1=[REDACTED]'
                )

                return $safeMessage
            }

            function Get-NormalizedRole {
                param(
                    [AllowEmptyString()]
                    [string]$Value
                )

                if ([string]::IsNullOrWhiteSpace($Value)) {
                    return ''
                }
                if ($Value -match '(?i)client') {
                    return 'Client'
                }
                if ($Value -match '(?i)server') {
                    return 'Server'
                }

                return $Value
            }

            function Get-Severity {
                param(
                    [Parameter(Mandatory = $true)]
                    [object]$Event
                )

                if (-not [string]::IsNullOrWhiteSpace([string]$Event.LevelDisplayName)) {
                    return [string]$Event.LevelDisplayName
                }

                switch ([int]$Event.Level) {
                    1 { return 'Critical' }
                    2 { return 'Error' }
                    3 { return 'Warning' }
                    4 { return 'Information' }
                    5 { return 'Verbose' }
                    default { return 'Error' }
                }
            }

            $rows = [System.Collections.Generic.List[psobject]]::new()
            foreach ($eventRecord in @($eventRecords | Sort-Object -Property TimeCreated -Descending)) {
                $parsedEvent = Get-EventDataMap -Event $eventRecord
                $data = $parsedEvent.Data
                $eventId = [int]$eventRecord.Id

                $protocol = Get-EventField -Data $data -Names @(
                    'Protocol', 'ProtocolVersion', 'TlsVersion', 'TLSVersion', 'SslVersion'
                )
                $alertDescription = Get-EventField -Data $data -Names @(
                    'AlertDescription', 'AlertDescriptionCode', 'Alert', 'AlertType'
                )
                $errorState = Get-EventField -Data $data -Names @(
                    'ErrorState', 'InternalErrorState', 'State', 'ErrorCode', 'Error'
                )
                $role = Get-NormalizedRole -Value (Get-EventField -Data $data -Names @(
                    'Role', 'ConnectionRole', 'EndpointRole', 'ClientServer', 'Direction'
                ))
                $remoteHostValue = Get-EventField -Data $data -Names @(
                    'RemoteHost', 'PeerName', 'PeerHost', 'TargetName', 'ServerName', 'ClientName'
                )
                $certificateSubject = Get-EventField -Data $data -Names @(
                    'CertificateSubject', 'SubjectName', 'CertificateName', 'Subject'
                )
                $cipherSuite = Get-EventField -Data $data -Names @(
                    'CipherSuite', 'Cipher', 'CipherAlgorithm', 'HashAlgorithm', 'ExchangeAlgorithm'
                )

                $errorType = 'Unknown'
                if ($parsedEvent.Parsed) {
                    if (-not [string]::IsNullOrWhiteSpace($cipherSuite)) {
                        $errorType = 'Cipher'
                    } elseif (-not [string]::IsNullOrWhiteSpace($alertDescription)) {
                        $errorType = 'Alert'
                    } elseif ($eventId -in @(36870, 36871)) {
                        $errorType = 'Certificate'
                    } elseif (-not [string]::IsNullOrWhiteSpace($protocol)) {
                        $errorType = 'Protocol'
                    } elseif ($eventId -in @(36874, 36888)) {
                        $errorType = 'Alert'
                    }
                }

                $eventTime = $eventRecord.TimeCreated
                $eventTimeValue = if ($null -eq $eventTime) { '' } else { $eventTime.ToString('o') }
                $rows.Add([PSCustomObject]@{
                    EventTime          = $eventTime
                    EventTimeValue     = $eventTimeValue
                    EventId            = $eventId
                    ErrorType          = $errorType
                    Severity           = Get-Severity -Event $eventRecord
                    Role               = $role
                    Protocol           = $protocol
                    AlertDescription   = $alertDescription
                    ErrorState         = $errorState
                    RemoteHost         = $remoteHostValue
                    CertificateSubject = $certificateSubject
                    CipherSuite        = $cipherSuite
                    Message            = ConvertTo-SafeMessage -Message ([string]$eventRecord.Message)
                })
            }

            $eventTally = @{}
            foreach ($row in $rows) {
                $key = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f `
                    $row.EventId,
                    $row.ErrorType,
                    $row.Role,
                    $row.Protocol,
                    $row.AlertDescription,
                    $row.ErrorState,
                    $row.RemoteHost,
                    $row.CertificateSubject,
                    $row.CipherSuite
                if ($eventTally.ContainsKey($key)) {
                    $eventTally[$key]++
                } else {
                    $eventTally[$key] = 1
                }
            }

            foreach ($row in ($rows | Sort-Object -Property EventTime -Descending)) {
                if (-not [string]::IsNullOrWhiteSpace($RemoteHostFilter) -and
                    ([string]$row.RemoteHost).IndexOf($RemoteHostFilter, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    continue
                }

                $key = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f `
                    $row.EventId,
                    $row.ErrorType,
                    $row.Role,
                    $row.Protocol,
                    $row.AlertDescription,
                    $row.ErrorState,
                    $row.RemoteHost,
                    $row.CertificateSubject,
                    $row.CipherSuite

                [PSCustomObject]@{
                    PSTypeName          = 'PSWinOps.SchannelError'
                    ComputerName        = $env:COMPUTERNAME
                    EventTime           = $row.EventTimeValue
                    EventId             = $row.EventId
                    ErrorType           = $row.ErrorType
                    Severity            = $row.Severity
                    Role                = $row.Role
                    Protocol            = $row.Protocol
                    AlertDescription    = $row.AlertDescription
                    ErrorState          = $row.ErrorState
                    RemoteHost          = $row.RemoteHost
                    CertificateSubject  = $row.CertificateSubject
                    FailureCount        = $eventTally[$key]
                    Message             = $row.Message
                    Timestamp           = Get-Date -Format 'o'
                }
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying Schannel errors on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($startTime, $MaxEvents, $EventId, $RemoteHost)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed Schannel error query"
    }
}
