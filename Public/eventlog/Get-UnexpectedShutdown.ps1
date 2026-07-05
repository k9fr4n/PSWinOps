#Requires -Version 5.1

function Get-UnexpectedShutdown {
    <#
    .SYNOPSIS
        Reports shutdown and restart events with cause, expectedness and initiator

    .DESCRIPTION
        Correlates Windows System event log entries (6008 dirty shutdown, Kernel-Power
        41 unexpected, 1074 planned shutdown/restart, 6006 clean shutdown, 1076 reason
        supplied) to report each shutdown or restart with its cause, whether it was
        expected or unexpected, the initiating process/user and the reason code.
        Local and remote targets are dispatched through Invoke-RemoteOrLocal; machines
        with no matching events return nothing.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for
        local machine queries.

    .PARAMETER MaxEvents
        Maximum number of shutdown/restart rows returned per machine, newest first.
        Valid range is 1 to 10000. Defaults to 50.

    .PARAMETER Days
        Look-back window in days used to bound the event log scan. StartTime is
        computed as (Get-Date).AddDays(-Days). Valid range is 1 to 3650. Defaults to 30.

    .EXAMPLE
        Get-UnexpectedShutdown

        Returns the most recent shutdown/restart events for the local machine over
        the last 30 days.

    .EXAMPLE
        Get-UnexpectedShutdown -ComputerName SRV01 -Days 90

        Returns shutdown/restart events from SRV01 over the last 90 days via WinRM.

    .EXAMPLE
        'SRV01','SRV02' | Get-UnexpectedShutdown -MaxEvents 20

        Returns up to 20 shutdown/restart events per machine for SRV01 and SRV02 via
        pipeline.

    .OUTPUTS
        PSWinOps.UnexpectedShutdown
        One object per shutdown/restart-related event (6008, 41, 1074, 6006, 1076),
        newest first, with cause, expectedness, initiator, reason code and comment.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-07-05
        Requires: PowerShell 5.1+ / Windows only
        Requires: WinRM enabled on target machines for remote queries

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        Source of truth: Windows System event log (provider EventLog for 6008/6006/1074/1076; provider Microsoft-Windows-Kernel-Power for 41)
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.UnexpectedShutdown')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10000)]
        [int]$MaxEvents = 50,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]$Days = 30
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting unexpected shutdown query"

        $startTime = (Get-Date).AddDays(-$Days)

        $scriptBlock = {
            param(
                [int]$MaxEvts,
                [datetime]$ScanStartTime
            )

            # Build filter for System log events (6008, 1074, 6006, 1076)
            $sysFilter = @{
                LogName   = 'System'
                Id        = @(6008, 1074, 6006, 1076)
                StartTime = $ScanStartTime
            }

            # Build filter for Kernel-Power 41 (crash / power loss)
            $kpFilter = @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-Kernel-Power'
                Id           = 41
                StartTime    = $ScanStartTime
            }

            $sysEvents = @(Get-WinEvent -FilterHashtable $sysFilter -ErrorAction SilentlyContinue)
            $kpEvents  = @(Get-WinEvent -FilterHashtable $kpFilter  -ErrorAction SilentlyContinue)
            $allEvents = @(($sysEvents + $kpEvents) | Sort-Object TimeCreated -Descending)

            $results = [System.Collections.Generic.List[psobject]]::new()

            foreach ($evt in $allEvents) {
                if ($results.Count -ge $MaxEvts) { break }

                $shutdownType = 'Unexpected'
                $isExpected   = $false
                $cause        = ''
                $reasonCode   = ''
                $initiator    = ''
                $comment      = ''

                switch ($evt.Id) {
                    6008 {
                        # Dirty/unexpected shutdown; no per-event cause available beyond the marker itself.
                        $shutdownType = 'Unexpected'
                        $isExpected   = $false
                    }
                    41 {
                        # Kernel-Power 41: BugcheckCode 0 => PowerLoss, non-zero => Crash
                        $isExpected = $false
                        try {
                            $bugcheck = [uint32]$evt.Properties[0].Value
                            if ($bugcheck -ne 0) {
                                $shutdownType = 'Crash'
                                $cause        = 'BugcheckCode: 0x{0:X8}' -f $bugcheck
                            } else {
                                $shutdownType = 'PowerLoss'
                            }
                        } catch {
                            $shutdownType = 'Crash'
                            Write-Verbose "Could not parse Kernel-Power 41 BugcheckCode: $_"
                        }
                    }
                    1074 {
                        # Planned shutdown/restart: reason text, reason code, initiator, comment
                        $shutdownType = 'Planned'
                        $isExpected   = $true
                        try {
                            $cause      = if ($evt.Properties.Count -ge 3) { [string]$evt.Properties[2].Value } else { '' }
                            $reasonCode = if ($evt.Properties.Count -ge 5) { [string]$evt.Properties[4].Value } else { '' }
                            $initiator  = if ($evt.Properties.Count -ge 7) { [string]$evt.Properties[6].Value } else { '' }
                            $comment    = if ($evt.Properties.Count -ge 9) { [string]$evt.Properties[8].Value } else { '' }
                        } catch { Write-Verbose "Could not parse 1074 properties: $_" }
                    }
                    6006 {
                        # Clean, service-controlled shutdown
                        $shutdownType = 'Clean'
                        $isExpected   = $true
                    }
                    1076 {
                        # Operator-supplied reason after a prior unexpected shutdown
                        $shutdownType = 'ReasonSupplied'
                        $isExpected   = $false
                        try {
                            $cause     = if ($evt.Properties.Count -ge 2) { [string]$evt.Properties[1].Value } else { '' }
                            $initiator = if ($evt.Properties.Count -ge 5) { [string]$evt.Properties[4].Value } else { '' }
                        } catch { Write-Verbose "Could not parse 1076 properties: $_" }
                    }
                }

                $results.Add([PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.UnexpectedShutdown'
                    ComputerName = $env:COMPUTERNAME
                    EventTime    = $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                    EventId      = $evt.Id
                    ShutdownType = $shutdownType
                    IsExpected   = $isExpected
                    Cause        = $cause
                    ReasonCode   = $reasonCode
                    Initiator    = $initiator
                    Comment      = $comment
                    Timestamp    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                })
            }

            $results
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying unexpected shutdowns on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($MaxEvents, $startTime)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed unexpected shutdown query"
    }
}
