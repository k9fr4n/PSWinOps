#Requires -Version 5.1

function Get-LogonFailure {
    <#
    .SYNOPSIS
        Aggregate and decode Windows Security 4625 failed-logon events

    .DESCRIPTION
        Queries the Windows Security event log for 4625 failed-logon events over a
        look-back window and decodes each into a correlated diagnostic row (account,
        domain, logon type, decoded failure reason, source IP, workstation and
        process). Local and remote targets are dispatched through Invoke-RemoteOrLocal;
        machines with no matching events return nothing and per-machine failures do not
        stop the remaining targets.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for
        local machine queries.

    .PARAMETER Days
        Look-back window in days used to bound the event log scan. StartTime is
        computed as (Get-Date).AddDays(-Days). Valid range is 1 to 3650. Defaults to 7.

    .PARAMETER MaxEvents
        Maximum number of 4625 events returned per machine, newest first. This value
        is forwarded to Get-WinEvent -MaxEvents and also caps the number of decoded
        rows emitted. Valid range is 1 to 10000. Defaults to 200.

    .PARAMETER UserName
        Optional filter on the decoded TargetUserName. Comparison is case-insensitive
        equality, applied after decoding (the 4625 TargetUserName lives in the event
        data, not a FilterHashtable key). Empty or absent means no filter.

    .EXAMPLE
        Get-LogonFailure -Days 1

        Returns decoded failed-logon events for the local machine over the last day.

    .EXAMPLE
        Get-LogonFailure -ComputerName SRV01 -UserName jdoe -Days 30

        Returns decoded failed-logon events for user 'jdoe' on SRV01 over the last
        30 days via WinRM.

    .EXAMPLE
        'SRV01','SRV02' | Get-LogonFailure -MaxEvents 500

        Returns up to 500 decoded failed-logon events per machine for SRV01 and
        SRV02 via pipeline.

    .OUTPUTS
        PSWinOps.LogonFailure
        One object per 4625 failed-logon event, newest first, with decoded account,
        domain, logon type, failure reason, source IP, workstation and process.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-07-06
        Requires: PowerShell 5.1+ / Windows only
        Requires: membership in the local Administrators / Event Log Readers group (Security log read access)
        Requires: WinRM enabled on target machines for remote queries

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        Source of truth: Windows Security event log (Event ID 4625, failed logon)
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.LogonFailure')]
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
        [string]$UserName = ''
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting logon failure query"

        $startTime = (Get-Date).AddDays(-$Days)

        $scriptBlock = {
            param(
                [datetime]$ScanStartTime,
                [int]$MaxEvts,
                [string]$UserNameFilter
            )

            $filter = @{
                LogName   = 'Security'
                Id        = 4625
                StartTime = $ScanStartTime
            }

            $events = @()
            try {
                $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvts -ErrorAction Stop)
            } catch {
                if ($_.Exception.Message -notmatch 'No events were found') {
                    throw
                }
            }

            $logonTypeMap = @{
                2  = 'Interactive'
                3  = 'Network'
                4  = 'Batch'
                5  = 'Service'
                7  = 'Unlock'
                8  = 'NetworkCleartext'
                9  = 'NewCredentials'
                10 = 'RemoteInteractive'
                11 = 'CachedInteractive'
            }

            $failureReasonMap = @{
                '0xC0000064' = 'Unknown user name'
                '0xC000006A' = 'Bad password'
                '0xC0000072' = 'Account disabled'
                '0xC0000234' = 'Account locked out'
                '0xC0000070' = 'Workstation restriction / logon time restriction'
                '0xC0000071' = 'Password expired'
                '0xC0000193' = 'Account expired'
                '0xC000015B' = 'Logon type not granted'
                '0xC0000224' = 'Password must change at next logon'
            }

            $results = [System.Collections.Generic.List[psobject]]::new()

            foreach ($evt in $events) {
                if ($results.Count -ge $MaxEvts) { break }

                $props = $evt.Properties

                $targetUserName = if ($props.Count -gt 5) { [string]$props[5].Value } else { '' }
                $targetDomain   = if ($props.Count -gt 6) { [string]$props[6].Value } else { '' }

                $statusHex = ''
                if ($props.Count -gt 7) {
                    try {
                        $statusHex = '0x{0:X8}' -f ([int64]$props[7].Value)
                    } catch {
                        $statusHex = [string]$props[7].Value
                    }
                }

                $subStatusHex = ''
                if ($props.Count -gt 9) {
                    try {
                        $subStatusHex = '0x{0:X8}' -f ([int64]$props[9].Value)
                    } catch {
                        $subStatusHex = [string]$props[9].Value
                    }
                }

                $logonType = 0
                if ($props.Count -gt 10) {
                    try {
                        $logonType = [int]$props[10].Value
                    } catch {
                        $logonType = 0
                    }
                }
                $logonTypeName = if ($logonTypeMap.ContainsKey($logonType)) { $logonTypeMap[$logonType] } else { 'Unknown' }

                $failureReason = if ($failureReasonMap.ContainsKey($subStatusHex)) { $failureReasonMap[$subStatusHex] } else { 'Other (see SubStatus)' }

                $workstationName = if ($props.Count -gt 13) { [string]$props[13].Value } else { '' }
                $processName     = if ($props.Count -gt 18) { [string]$props[18].Value } else { '' }
                $sourceIp        = if ($props.Count -gt 19) { [string]$props[19].Value } else { '' }

                if (-not [string]::IsNullOrWhiteSpace($UserNameFilter) -and $targetUserName -ne $UserNameFilter) {
                    continue
                }

                $results.Add([PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.LogonFailure'
                    ComputerName    = $env:COMPUTERNAME
                    EventTime       = $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                    TargetUserName  = $targetUserName
                    TargetDomain    = $targetDomain
                    LogonType       = $logonType
                    LogonTypeName   = $logonTypeName
                    FailureReason   = $failureReason
                    Status          = $statusHex
                    SubStatus       = $subStatusHex
                    WorkstationName = $workstationName
                    SourceIpAddress = $sourceIp
                    ProcessName     = $processName
                    Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                })
            }

            $results
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying logon failures on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($startTime, $MaxEvents, $UserName)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed logon failure query"
    }
}
