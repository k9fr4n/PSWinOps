#Requires -Version 5.1

function Get-RebootHistory {
    <#
    .SYNOPSIS
        Reconstructs reboot and shutdown history from the Windows System event log

    .DESCRIPTION
        Correlates Windows System event log entries (1074, 1076, 6005, 6006, 6008 and
        Kernel-Power 41) to rebuild each reboot or shutdown for one or more computers.
        Each event is classified as Planned, Unexpected, Crash, PowerLoss or Unknown,
        with its cause, initiator and comment, and the downtime duration between a clean
        stop and the following boot. Local and remote targets are dispatched through
        Invoke-RemoteOrLocal.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for
        local machine queries.

    .PARAMETER MaxEvents
        Number of reboot/shutdown events to return, newest first. Valid range is 1
        to 10000. Defaults to 50.

    .PARAMETER After
        Only return events at or after this datetime. When omitted, no lower bound is
        applied to the query.

    .PARAMETER Before
        Only return events at or before this datetime. When omitted, no upper bound is
        applied to the query.

    .EXAMPLE
        Get-RebootHistory

        Returns the 50 most recent reboot and shutdown records for the local machine.

    .EXAMPLE
        Get-RebootHistory -ComputerName 'SRV01' -MaxEvents 20

        Returns the 20 most recent reboot records for SRV01 via WinRM.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-RebootHistory -After (Get-Date).AddDays(-30)

        Returns all reboots in the last 30 days for SRV01 and SRV02 via pipeline.

    .OUTPUTS
        PSWinOps.RebootHistory
        One object per boot event, enriched with shutdown type, cause, initiator,
        comment and downtime duration.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-06-23
        Requires: PowerShell 5.1+ / Windows only
        Requires: WinRM enabled on target machines for remote queries

    .LINK
        https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.RebootHistory')]
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
        [datetime]$After,

        [Parameter(Mandatory = $false)]
        [datetime]$Before
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting reboot history query"

        $hasAfter  = $PSBoundParameters.ContainsKey('After')
        $hasBefore = $PSBoundParameters.ContainsKey('Before')
        $afterVal  = if ($hasAfter)  { $After }  else { [datetime]::MinValue }
        $beforeVal = if ($hasBefore) { $Before } else { [datetime]::MaxValue }

        $scriptBlock = {
            param(
                [int]$MaxEvts,
                [datetime]$AfterDate,
                [datetime]$BeforeDate,
                [bool]$HasAfter,
                [bool]$HasBefore
            )

            # Build filter for System log events (1074, 1076, 6005, 6006, 6008)
            $sysFilter = @{
                LogName = 'System'
                Id      = @(1074, 1076, 6005, 6006, 6008)
            }
            if ($HasAfter)  { $sysFilter['StartTime'] = $AfterDate }
            if ($HasBefore) { $sysFilter['EndTime']   = $BeforeDate }

            # Build filter for Kernel-Power 41 (crash / power loss)
            $kpFilter = @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-Kernel-Power'
                Id           = 41
            }
            if ($HasAfter)  { $kpFilter['StartTime'] = $AfterDate }
            if ($HasBefore) { $kpFilter['EndTime']   = $BeforeDate }

            $sysEvents = @(Get-WinEvent -FilterHashtable $sysFilter -ErrorAction SilentlyContinue)
            $kpEvents  = @(Get-WinEvent -FilterHashtable $kpFilter  -ErrorAction SilentlyContinue)
            $allEvents = ($sysEvents + $kpEvents) | Sort-Object TimeCreated

            $bootEvents   = @($allEvents | Where-Object { $_.Id -eq 6005 })
            $cleanStops   = @($allEvents | Where-Object { $_.Id -eq 6006 })
            $dirtyStops   = @($allEvents | Where-Object { $_.Id -eq 6008 })
            $crashEvents  = @($allEvents | Where-Object { $_.Id -eq 41   })
            $plannedShuts = @($allEvents | Where-Object { $_.Id -eq 1074 })
            $reasonRecs   = @($allEvents | Where-Object { $_.Id -eq 1076 })

            $results = [System.Collections.Generic.List[psobject]]::new()

            foreach ($boot in ($bootEvents | Sort-Object TimeCreated -Descending)) {
                if ($results.Count -ge $MaxEvts) { break }

                $bootTime        = $boot.TimeCreated
                $shutdownTime    = $null
                $downtimeMinutes = $null
                $type            = 'Unknown'
                $cause           = ''
                $initiator       = ''
                $comment         = ''
                $eventId         = 6005

                # Determine the search window lower bound: after the previous boot
                $prevBoot = $bootEvents | Where-Object { $_.TimeCreated -lt $bootTime } |
                            Sort-Object TimeCreated -Descending | Select-Object -First 1
                $windowStart = if ($null -ne $prevBoot) {
                    $prevBoot.TimeCreated
                } else {
                    $bootTime.AddDays(-365)
                }

                # Check for 6008 (dirty shutdown marker logged at boot time)
                $dirty6008 = $dirtyStops | Where-Object {
                    [math]::Abs(($_.TimeCreated - $bootTime).TotalMinutes) -le 5
                } | Sort-Object TimeCreated | Select-Object -First 1

                # Look for a Kernel-Power 41 just before this boot
                $precedingCrash = $crashEvents | Where-Object {
                    $_.TimeCreated -lt $bootTime -and $_.TimeCreated -gt $windowStart
                } | Sort-Object TimeCreated -Descending | Select-Object -First 1

                # Look for a clean shutdown (6006) just before this boot
                $precedingClean = $cleanStops | Where-Object {
                    $_.TimeCreated -lt $bootTime -and $_.TimeCreated -gt $windowStart
                } | Sort-Object TimeCreated -Descending | Select-Object -First 1

                if ($null -ne $dirty6008) {
                    # Unexpected shutdown recorded at boot time by 6008
                    $type    = 'Unexpected'
                    $eventId = 6008

                    # 6008 Properties[0] = time string, Properties[1] = date string
                    try {
                        if ($dirty6008.Properties.Count -ge 2) {
                            $timeStr = [string]$dirty6008.Properties[0].Value
                            $dateStr = [string]$dirty6008.Properties[1].Value
                            $parsed  = [datetime]::Parse("$dateStr $timeStr")
                            $shutdownTime    = $parsed
                            $downtimeMinutes = [math]::Round(($bootTime - $shutdownTime).TotalMinutes, 2)
                        }
                    } catch { Write-Verbose "Could not parse 6008 shutdown time: $_" }

                    # Look for 1076 (operator-supplied reason recorded after this boot)
                    $reason1076 = $reasonRecs | Where-Object {
                        $_.TimeCreated -ge $bootTime -and
                        $_.TimeCreated -le $bootTime.AddHours(2)
                    } | Sort-Object TimeCreated | Select-Object -First 1

                    if ($null -ne $reason1076) {
                        try {
                            $cause     = if ($reason1076.Properties.Count -ge 2) { [string]$reason1076.Properties[1].Value } else { '' }
                            $initiator = if ($reason1076.Properties.Count -ge 5) { [string]$reason1076.Properties[4].Value } else { '' }
                            $comment   = if ($reason1076.Properties.Count -ge 7) { [string]$reason1076.Properties[6].Value } else { '' }
                        } catch { Write-Verbose "Could not parse 1076 properties: $_" }
                    }

                } elseif ($null -ne $precedingCrash) {
                    # Kernel-Power 41: crash (BugcheckCode != 0) or power loss (== 0)
                    $shutdownTime    = $precedingCrash.TimeCreated
                    $downtimeMinutes = [math]::Round(($bootTime - $shutdownTime).TotalMinutes, 2)
                    $eventId         = 41

                    try {
                        $bugcheck = [uint32]$precedingCrash.Properties[0].Value
                        if ($bugcheck -ne 0) {
                            $type  = 'Crash'
                            $cause = 'BugcheckCode: 0x{0:X8}' -f $bugcheck
                        } else {
                            $type = 'PowerLoss'
                        }
                    } catch {
                        $type = 'Crash'
                    }

                } elseif ($null -ne $precedingClean) {
                    # Clean shutdown (6006), classified as Planned
                    $shutdownTime    = $precedingClean.TimeCreated
                    $downtimeMinutes = [math]::Round(($bootTime - $shutdownTime).TotalMinutes, 2)
                    $type            = 'Planned'
                    $eventId         = 6006

                    # Enrich from 1074 near the 6006 time
                    $plan1074 = $plannedShuts | Where-Object {
                        $_.TimeCreated -le $shutdownTime.AddMinutes(2) -and
                        $_.TimeCreated -ge $shutdownTime.AddMinutes(-10)
                    } | Sort-Object TimeCreated -Descending | Select-Object -First 1

                    if ($null -ne $plan1074) {
                        $eventId = 1074
                        try {
                            $initiator = if ($plan1074.Properties.Count -ge 7) { [string]$plan1074.Properties[6].Value } else { '' }
                            $cause     = if ($plan1074.Properties.Count -ge 3) { [string]$plan1074.Properties[2].Value } else { '' }
                            $comment   = if ($plan1074.Properties.Count -ge 9) { [string]$plan1074.Properties[8].Value } else { '' }
                        } catch { Write-Verbose "Could not parse 1074 properties: $_" }
                    }
                }

                $results.Add([PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $env:COMPUTERNAME
                    ShutdownTime    = if ($null -ne $shutdownTime) { $shutdownTime.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
                    BootTime        = $bootTime.ToString('yyyy-MM-dd HH:mm:ss')
                    DowntimeMinutes = $downtimeMinutes
                    Type            = $type
                    Cause           = $cause
                    Initiator       = $initiator
                    Comment         = $comment
                    EventId         = $eventId
                    Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                })
            }

            $results
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying reboot history on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($MaxEvents, $afterVal, $beforeVal, $hasAfter, $hasBefore)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed reboot history query"
    }
}
