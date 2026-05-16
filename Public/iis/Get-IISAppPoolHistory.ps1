#Requires -Version 5.1
function Get-IISAppPoolHistory {
    <#
        .SYNOPSIS
            Reconstructs the lifecycle history (recycles, rapid-fail shutdowns, crashes, start/stop, identity changes) of IIS application pools from Windows event logs.

        .DESCRIPTION
            Mines the System (Microsoft-Windows-WAS), Application (W3SVC-WP, WAS) and
            optionally the Microsoft-Windows-IIS-W3SVC-WP/Operational event logs on one
            or more servers, then classifies every relevant entry into a typed event
            object enriched with the owning application pool, worker PID and a
            normalised reason code. Provides the operational timeline IISAdministration
            does not expose, with server-side filtering via Get-WinEvent -FilterHashtable
            for performance.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name (aliases: CN, Server,
            MachineName). Use $env:COMPUTERNAME, localhost, or . for the local machine.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER AppPoolName
            Restrict results to events whose parsed application pool name matches one
            or more patterns. Wildcards accepted via -like. Applied as a post-filter
            after event parsing because not all event IDs expose the pool name in a
            single InsertionString slot.

        .PARAMETER After
            Return only events with TimeCreated on or after this value.
            Forwarded as StartTime in Get-WinEvent -FilterHashtable for server-side
            filtering.

        .PARAMETER Before
            Return only events with TimeCreated on or before this value.
            Forwarded as EndTime in Get-WinEvent -FilterHashtable for server-side
            filtering.

        .PARAMETER Category
            Restrict results to one or more event categories. Valid values:
            Recycle, RapidFail, Crash, Start, Stop, IdentityChange, ConfigChange,
            OrphanWP, Other. When combined with -EventId the two ID sets are unioned.

        .PARAMETER EventId
            Query specific event IDs instead of (or in addition to) the default set
            derived from -Category. IDs not present in the built-in map are routed to
            the Operational log channel when -IncludeOperationalLog is also specified.

        .PARAMETER IncludeOperationalLog
            Also query the Microsoft-Windows-IIS-W3SVC-WP/Operational channel.
            This admin-only log contains additional ISAPI / FastCGI crash detail.
            A warning is emitted and the channel is skipped if it is absent or
            disabled; no terminating error is thrown.

        .PARAMETER MaxEvents
            Maximum number of events to retrieve per log channel per target machine.
            Forwarded as -MaxEvents to each Get-WinEvent call. Default: 1000.

        .PARAMETER Tail
            Keep only the most recent N events (applied after merging all log channels
            and post-filtering). Results are still returned in chronological order
            (oldest first).

        .EXAMPLE
            Get-IISAppPoolHistory -After (Get-Date).AddHours(-24) -Category Recycle,RapidFail

            Returns all recycle and rapid-fail events from the last 24 hours on the
            local machine.

        .EXAMPLE
            'WEB01','WEB02' | Get-IISAppPoolHistory -AppPoolName 'api-*' -Tail 20

            Returns the 20 most recent history events for application pools matching
            'api-*' across two web servers.

        .EXAMPLE
            Get-IISHealth -ComputerName WEB01 | Get-IISAppPoolHistory -After (Get-Date).AddDays(-7)

            Pipeline from Get-IISHealth to retrieve a week of app pool history.

        .EXAMPLE
            Get-IISAppPoolHistory -ComputerName WEB01 -Category Crash -IncludeOperationalLog -After (Get-Date).AddDays(-1)

            Includes the admin Operational channel for additional ISAPI / FastCGI crash
            detail over the last 24 hours.

        .OUTPUTS
            PSCustomObject (PSTypeName='PSWinOps.IISAppPoolHistoryEvent')

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-05-16
            Requires: PowerShell 5.1+ / Windows only
            Requires: Web-Server (IIS) role

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/iis/manage/provisioning-and-managing-iis/troubleshooting-application-pool-issues
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.IISAppPoolHistoryEvent')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Server', 'MachineName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string[]]$AppPoolName,

        [Parameter(Mandatory = $false)]
        [datetime]$After,

        [Parameter(Mandatory = $false)]
        [datetime]$Before,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Recycle', 'RapidFail', 'Crash', 'Start', 'Stop', 'IdentityChange', 'ConfigChange', 'OrphanWP', 'Other')]
        [string[]]$Category,

        [Parameter(Mandatory = $false)]
        [int[]]$EventId,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeOperationalLog,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 2147483647)]
        [int]$MaxEvents = 1000,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 2147483647)]
        [int]$Tail
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # ── Static event-ID classification table ────────────────────────────
        # Passed via ArgumentList so the remote scriptblock classifies events
        # without any top-level module state.
        $eventIdMap = @{
            # ── WAS Recycle family (System log) ─────────────────────────────
            5074 = @{ Category = 'Recycle';        ReasonCode = 'ConfigChange';         Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            5076 = @{ Category = 'Recycle';        ReasonCode = 'ScheduleTime';         Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            5077 = @{ Category = 'Recycle';        ReasonCode = 'NumberOfRequests';     Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            5079 = @{ Category = 'Recycle';        ReasonCode = 'Memory';               Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            5080 = @{ Category = 'Recycle';        ReasonCode = 'PrivateMemory';        Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            # ── Rapid-fail protection (System log) ──────────────────────────
            5117 = @{ Category = 'RapidFail';      ReasonCode = 'RapidFailProtection';  Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            5021 = @{ Category = 'IdentityChange'; ReasonCode = 'IdentityChange';       Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            5022 = @{ Category = 'RapidFail';      ReasonCode = 'RapidFailProtection';  Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            # ── Worker-process crash (Application log) ───────────────────────
            5009 = @{ Category = 'Crash';          ReasonCode = 'ProcessTerminated';    Log = 'Application'; PoolIdx = 1; PidIdx = 0 }
            5010 = @{ Category = 'Crash';          ReasonCode = 'ISAPI';                Log = 'Application'; PoolIdx = 1; PidIdx = 0 }
            5011 = @{ Category = 'Crash';          ReasonCode = 'PingFailure';          Log = 'Application'; PoolIdx = 1; PidIdx = 0 }
            5013 = @{ Category = 'Crash';          ReasonCode = 'ShutdownTimeLimit';    Log = 'Application'; PoolIdx = 1; PidIdx = 0 }
            # ── Pool start / stop / orphan (System log) ──────────────────────
            5057 = @{ Category = 'Start';          ReasonCode = 'PoolStarted';          Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            5059 = @{ Category = 'Stop';           ReasonCode = 'PoolStopped';          Log = 'System';      PoolIdx = 0; PidIdx = -1 }
            5168 = @{ Category = 'OrphanWP';       ReasonCode = 'OrphanWorkerProcess';  Log = 'System';      PoolIdx = 0; PidIdx = 1  }
            5186 = @{ Category = 'Stop';           ReasonCode = 'OnDemandStop';         Log = 'System';      PoolIdx = 0; PidIdx = -1 }
        }

        # Category -> default EventId set
        $categoryEventIds = @{
            Recycle        = @(5074, 5076, 5077, 5079, 5080)
            RapidFail      = @(5117, 5022)
            Crash          = @(5009, 5010, 5011, 5013)
            Start          = @(5057)
            Stop           = @(5059, 5186)
            IdentityChange = @(5021)
            ConfigChange   = @(5074)
            OrphanWP       = @(5168)
            Other          = @()
        }

        $hasCategory = $PSBoundParameters.ContainsKey('Category')
        $hasEventId  = $PSBoundParameters.ContainsKey('EventId')

        # Resolve which EventIds to query from System / Application logs
        $resolvedIds = [System.Collections.Generic.HashSet[int]]::new()

        if ($hasCategory) {
            foreach ($cat in $Category) {
                foreach ($cid in $categoryEventIds[$cat]) {
                    $null = $resolvedIds.Add($cid)
                }
            }
        }
        if ($hasEventId) {
            foreach ($eid in $EventId) {
                if ($eventIdMap.ContainsKey($eid)) {
                    $null = $resolvedIds.Add($eid)
                }
            }
        }
        # Default: query all known IDs when neither -Category nor -EventId is supplied
        if ($resolvedIds.Count -eq 0 -and -not $hasCategory -and -not $hasEventId) {
            foreach ($eid in $eventIdMap.Keys) {
                $null = $resolvedIds.Add($eid)
            }
        }

        # Partition by log channel for server-side filtering
        $systemIds      = [int[]]@($resolvedIds | Where-Object { $eventIdMap[$_]['Log'] -eq 'System'      })
        $applicationIds = [int[]]@($resolvedIds | Where-Object { $eventIdMap[$_]['Log'] -eq 'Application' })

        # Operational channel: user-specified IDs not in the static map
        $operationalQueryIds = [int[]]@(
            if ($hasEventId) { $EventId | Where-Object { -not $eventIdMap.ContainsKey($_) } }
        )

        # ── Remote-capable scriptblock ────────────────────────────────────
        $scriptBlock = {
            param(
                [hashtable] $EventIdMap,
                [int[]]     $SysIds,
                [int[]]     $AppIds,
                [int[]]     $OpIds,
                [string[]]  $FilterAppPool,
                [datetime]  $FilterAfter,
                [bool]      $HasAfter,
                [datetime]  $FilterBefore,
                [bool]      $HasBefore,
                [bool]      $IncludeOp,
                [int]       $MaxEvt,
                [int]       $TailN
            )

            $rawEvents = @()

            # ── 1. Query System log ──────────────────────────────────────────
            if ($SysIds -and $SysIds.Count -gt 0) {
                $fht = @{ LogName = 'System'; Id = $SysIds }
                if ($HasAfter)  { $fht['StartTime'] = $FilterAfter  }
                if ($HasBefore) { $fht['EndTime']   = $FilterBefore }
                $gwp = @{ FilterHashtable = $fht; ErrorAction = 'Stop' }
                if ($MaxEvt -gt 0) { $gwp['MaxEvents'] = $MaxEvt }
                try {
                    $rawEvents += @(Get-WinEvent @gwp)
                }
                catch {
                    $errMsg = $_.Exception.Message
                    if ($errMsg -notmatch 'No events were found|There are no more files') {
                        Write-Warning "[$env:COMPUTERNAME] System log query failed: $errMsg"
                    }
                }
            }

            # ── 2. Query Application log ─────────────────────────────────────
            if ($AppIds -and $AppIds.Count -gt 0) {
                $fht = @{ LogName = 'Application'; Id = $AppIds }
                if ($HasAfter)  { $fht['StartTime'] = $FilterAfter  }
                if ($HasBefore) { $fht['EndTime']   = $FilterBefore }
                $gwp = @{ FilterHashtable = $fht; ErrorAction = 'Stop' }
                if ($MaxEvt -gt 0) { $gwp['MaxEvents'] = $MaxEvt }
                try {
                    $rawEvents += @(Get-WinEvent @gwp)
                }
                catch {
                    $errMsg = $_.Exception.Message
                    if ($errMsg -notmatch 'No events were found|There are no more files') {
                        Write-Warning "[$env:COMPUTERNAME] Application log query failed: $errMsg"
                    }
                }
            }

            # ── 3. Query Operational log (optional) ──────────────────────────
            if ($IncludeOp) {
                $opLog = 'Microsoft-Windows-IIS-W3SVC-WP/Operational'
                $fht   = @{ LogName = $opLog }
                if ($OpIds -and $OpIds.Count -gt 0) { $fht['Id'] = $OpIds }
                if ($HasAfter)  { $fht['StartTime'] = $FilterAfter  }
                if ($HasBefore) { $fht['EndTime']   = $FilterBefore }
                $gwp = @{ FilterHashtable = $fht; ErrorAction = 'Stop' }
                if ($MaxEvt -gt 0) { $gwp['MaxEvents'] = $MaxEvt }
                try {
                    $rawEvents += @(Get-WinEvent @gwp)
                }
                catch {
                    $errMsg = $_.Exception.Message
                    if ($errMsg -match 'channel .* is disabled|not found|does not exist|cannot be opened|The specified channel') {
                        Write-Warning "[$env:COMPUTERNAME] Operational log '$opLog' is unavailable or disabled. Skipping."
                    }
                    elseif ($errMsg -notmatch 'No events were found|There are no more files') {
                        Write-Warning "[$env:COMPUTERNAME] Operational log query failed: $errMsg"
                    }
                }
            }

            if ($rawEvents.Count -eq 0) { return }

            # ── 4. Parse events into typed rows ──────────────────────────────
            $parsed = [System.Collections.Generic.List[hashtable]]::new()

            foreach ($evt in $rawEvents) {
                $id   = [int]$evt.Id
                $meta = if ($EventIdMap.ContainsKey($id)) { $EventIdMap[$id] } else { $null }

                $poolName  = $null
                $workerPid = $null

                try {
                    $props = $evt.Properties
                    if ($meta) {
                        $poolIdx = [int]$meta['PoolIdx']
                        $pidIdx  = [int]$meta['PidIdx']

                        if ($poolIdx -ge 0 -and $props.Count -gt $poolIdx) {
                            $v = [string]$props[$poolIdx].Value
                            if (-not [string]::IsNullOrWhiteSpace($v)) { $poolName = $v }
                        }
                        if ($pidIdx -ge 0 -and $props.Count -gt $pidIdx) {
                            $pv = $props[$pidIdx].Value
                            if ($null -ne $pv) {
                                $intVal = 0
                                if ([int]::TryParse($pv.ToString(), [ref]$intVal)) { $workerPid = $intVal }
                            }
                        }
                    }
                    elseif ($props.Count -gt 0) {
                        $v = [string]$props[0].Value
                        if (-not [string]::IsNullOrWhiteSpace($v)) { $poolName = $v }
                    }
                }
                catch { $null = $_ }

                $category   = if ($meta) { [string]$meta['Category'] }  else { 'Other' }
                $reasonCode = if ($meta) { [string]$meta['ReasonCode'] } else { $null   }

                $reason = $null
                try {
                    $msgRaw = $evt.Message
                    if (-not [string]::IsNullOrWhiteSpace($msgRaw)) {
                        $reason = ($msgRaw -replace '\r?\n', ' ' -replace '\s{2,}', ' ').Trim()
                        if ($reason.Length -gt 200) { $reason = $reason.Substring(0, 200) + '...' }
                    }
                }
                catch { $null = $_ }

                $tcUtc   = [datetime]::SpecifyKind($evt.TimeCreated.ToUniversalTime(), [System.DateTimeKind]::Utc)
                $tcLocal = $evt.TimeCreated

                $parsed.Add(@{
                    TimeCreated      = $tcUtc
                    TimeCreatedLocal = $tcLocal
                    AppPoolName      = $poolName
                    Category         = $category
                    EventId          = $id
                    WorkerPid        = $workerPid
                    ReasonCode       = $reasonCode
                    Reason           = $reason
                    ProviderName     = $evt.ProviderName
                    LogName          = $evt.LogName
                    RecordId         = $evt.RecordId
                    MachineName      = $evt.MachineName
                })
            }

            # ── 5. Post-filter: AppPoolName wildcard ─────────────────────────
            if ($FilterAppPool -and $FilterAppPool.Count -gt 0) {
                $keep = [System.Collections.Generic.List[hashtable]]::new()
                foreach ($row in $parsed) {
                    $pool = $row['AppPoolName']
                    if ($null -ne $pool) {
                        foreach ($pat in $FilterAppPool) {
                            if ($pool -like $pat) { $keep.Add($row); break }
                        }
                    }
                }
                $parsed = $keep
            }

            if ($parsed.Count -eq 0) { return }

            # ── 6. Tail: keep most recent N, then output chronologically ──────
            if ($TailN -gt 0 -and $parsed.Count -gt $TailN) {
                $sorted = @($parsed | Sort-Object { [datetime]$_['TimeCreated'] } -Descending)
                $tail   = [System.Collections.Generic.List[hashtable]]::new()
                for ($i = 0; $i -lt $TailN -and $i -lt $sorted.Count; $i++) {
                    $tail.Add($sorted[$i])
                }
                $parsed = $tail
            }

            # ── 7. Chronological sort for final output ────────────────────────
            @($parsed | Sort-Object { [datetime]$_['TimeCreated'] })
        }
    }

    process {
        foreach ($cn in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '$cn'"

            try {
                $invokeParams = @{
                    ComputerName = $cn
                    ScriptBlock  = $scriptBlock
                    ArgumentList = @(
                        $eventIdMap,
                        $systemIds,
                        $applicationIds,
                        $operationalQueryIds,
                        $AppPoolName,
                        $(if ($PSBoundParameters.ContainsKey('After'))  { $After  } else { [datetime]::MinValue }),
                        $PSBoundParameters.ContainsKey('After'),
                        $(if ($PSBoundParameters.ContainsKey('Before')) { $Before } else { [datetime]::MaxValue }),
                        $PSBoundParameters.ContainsKey('Before'),
                        [bool]$IncludeOperationalLog.IsPresent,
                        [int]$MaxEvents,
                        $(if ($PSBoundParameters.ContainsKey('Tail')) { [int]$Tail } else { [int]0 })
                    )
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawResults = Invoke-RemoteOrLocal @invokeParams
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query '$cn': $($_.Exception.Message)"
                continue
            }

            if ($null -eq $rawResults) { continue }

            foreach ($row in $rawResults) {
                [PSCustomObject]@{
                    PSTypeName       = 'PSWinOps.IISAppPoolHistoryEvent'
                    TimeCreated      = $row['TimeCreated']
                    TimeCreatedLocal = $row['TimeCreatedLocal']
                    ComputerName     = $cn
                    AppPoolName      = $row['AppPoolName']
                    Category         = $row['Category']
                    EventId          = $row['EventId']
                    WorkerPid        = $row['WorkerPid']
                    ReasonCode       = $row['ReasonCode']
                    Reason           = $row['Reason']
                    ProviderName     = $row['ProviderName']
                    LogName          = $row['LogName']
                    RecordId         = $row['RecordId']
                    MachineName      = $row['MachineName']
                    Timestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Done"
    }
}
