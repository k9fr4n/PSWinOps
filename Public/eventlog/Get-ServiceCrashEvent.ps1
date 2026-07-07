#Requires -Version 5.1

function Get-ServiceCrashEvent {
    <#
    .SYNOPSIS
        Aggregate Service Control Manager crash events per service with counts and exit codes

    .DESCRIPTION
        Queries the Windows System event log for Service Control Manager crash/abnormal-stop
        events (IDs 7000, 7009, 7011, 7024, 7031, 7034) over a look-back window and reports one
        row per event with the resolved service name, display name, last exit code, configured
        recovery action, and a per-service crash count aggregated over the window. Local and
        remote targets are dispatched through Invoke-RemoteOrLocal; machines with no matching
        events return nothing and per-machine failures do not stop the remaining targets.

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
        Maximum number of Service Control Manager crash events returned per machine,
        newest first. This value is forwarded to Get-WinEvent -MaxEvents and also caps
        the number of rows emitted. Valid range is 1 to 10000. Defaults to 200.

    .PARAMETER ServiceName
        Optional filter on the resolved ServiceName. Comparison is case-insensitive
        equality, applied after decoding (the real service name lives in the event
        Properties, not a FilterHashtable key, so it cannot be pushed into the query).
        Empty or absent means no filter.

    .EXAMPLE
        Get-ServiceCrashEvent -Days 7

        Returns Service Control Manager crash events for the local machine over the
        last 7 days.

    .EXAMPLE
        Get-ServiceCrashEvent -ComputerName SRV01 -ServiceName Spooler -Days 30

        Returns crash events for the 'Spooler' service on SRV01 over the last 30
        days via WinRM.

    .EXAMPLE
        'SRV01','SRV02' | Get-ServiceCrashEvent -MaxEvents 100

        Returns up to 100 crash events per machine for SRV01 and SRV02 via pipeline.

    .OUTPUTS
        PSWinOps.ServiceCrashEvent
        One object per Service Control Manager crash event (7000, 7009, 7011, 7024,
        7031, 7034), newest first, with resolved service name, exit code, window-level
        crash count and configured recovery action.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-07-06
        Requires: PowerShell 5.1+ / Windows only
        Requires: WinRM enabled on target machines for remote queries

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        Source of truth: Windows System event log (provider 'Service Control Manager', IDs 7000/7009/7011/7024/7031/7034)
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.ServiceCrashEvent')]
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
        [string]$ServiceName = ''
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting service crash event query"

        $startTime = (Get-Date).AddDays(-$Days)

        $scriptBlock = {
            param(
                [datetime]$ScanStartTime,
                [int]$MaxEvts,
                [string]$ServiceNameFilter
            )

            $filter = @{
                LogName      = 'System'
                ProviderName = 'Service Control Manager'
                Id           = @(7000, 7009, 7011, 7024, 7031, 7034)
                StartTime    = $ScanStartTime
            }

            $events = @()
            try {
                $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvts -ErrorAction Stop)
            } catch {
                if ($_.Exception.Message -notmatch 'No events were found') {
                    throw
                }
            }

            $events = @($events | Sort-Object -Property TimeCreated -Descending)

            # Cache DisplayName -> ServiceName resolution once per invocation (best-effort)
            $serviceNameMap = @{}
            try {
                Get-CimInstance -ClassName Win32_Service -ErrorAction Stop | ForEach-Object {
                    if (-not [string]::IsNullOrEmpty($_.DisplayName)) {
                        $serviceNameMap[$_.DisplayName] = $_.Name
                    }
                }
            } catch {
                Write-Verbose "Could not enumerate Win32_Service for name resolution: $_"
            }

            $recoveryActionTypeMap = @{
                0 = 'TakeNoAction'
                1 = 'Restart'
                2 = 'Reboot'
                3 = 'RunProgram'
            }

            # Cache the configured SCM recovery action per distinct resolved ServiceName
            $recoveryActionCache = @{}

            # Resolve only the SCM-configured recovery action from the registry. This value
            # is per-service, so it is safe to cache by name. The per-event fallback code is
            # deliberately NOT handled here: caching it would let one event's (absent) code
            # poison a later event for the same service.
            function Get-ScmConfiguredRecoveryAction {
                param(
                    [string]$Name
                )

                if ([string]::IsNullOrEmpty($Name)) { return '' }
                if ($recoveryActionCache.ContainsKey($Name)) { return $recoveryActionCache[$Name] }

                $resolvedAction = ''
                try {
                    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
                    $bytes = (Get-ItemProperty -Path $regPath -Name 'FailureActions' -ErrorAction Stop).FailureActions
                    if ($bytes -and $bytes.Count -ge 20) {
                        $numActions = [System.BitConverter]::ToUInt32($bytes, 12)
                        if ($numActions -ge 1) {
                            $actionType = [int]([System.BitConverter]::ToUInt32($bytes, 16))
                            $resolvedAction = if ($recoveryActionTypeMap.ContainsKey($actionType)) { $recoveryActionTypeMap[$actionType] } else { "Unknown($actionType)" }
                        }
                    }
                } catch {
                    Write-Verbose "Could not resolve configured recovery action for '$Name': $_"
                }

                $recoveryActionCache[$Name] = $resolvedAction
                return $resolvedAction
            }

            # Combine the cached SCM-configured action with the per-event fallback code.
            function Get-ScmRecoveryAction {
                param(
                    [string]$Name,
                    [int]$FallbackCode
                )

                $resolvedAction = Get-ScmConfiguredRecoveryAction -Name $Name

                if ([string]::IsNullOrEmpty($resolvedAction) -and $FallbackCode -ge 0) {
                    $resolvedAction = if ($recoveryActionTypeMap.ContainsKey($FallbackCode)) { $recoveryActionTypeMap[$FallbackCode] } else { "Unknown($FallbackCode)" }
                }

                return $resolvedAction
            }

            $rows = [System.Collections.Generic.List[psobject]]::new()

            foreach ($evt in $events) {
                $props = $evt.Properties
                $displayName    = ''
                $exitCode       = ''
                $eventActionCode = -1

                switch ($evt.Id) {
                    7000 {
                        # Service failed to start; Properties[0]=display name, Properties[1] may carry an error code
                        $displayName = if ($props.Count -ge 1) { [string]$props[0].Value } else { '' }
                        if ($props.Count -ge 2) {
                            try { $exitCode = [string]([int64]$props[1].Value) } catch { $exitCode = '' }
                        }
                    }
                    7009 {
                        # Start timeout; property order for timeout ms / display name varies by build
                        if ($props.Count -ge 2) {
                            $val0 = [string]$props[0].Value
                            $val1 = [string]$props[1].Value
                            $displayName = if ($val0 -match '^\d+$') { $val1 } else { $val0 }
                        } elseif ($props.Count -ge 1) {
                            $displayName = [string]$props[0].Value
                        }
                    }
                    7011 {
                        # Transaction response timeout; Properties[0]=display name
                        $displayName = if ($props.Count -ge 1) { [string]$props[0].Value } else { '' }
                    }
                    7024 {
                        # Service-specific error / exit code; Properties[0]=display name, Properties[1]=exit code
                        $displayName = if ($props.Count -ge 1) { [string]$props[0].Value } else { '' }
                        if ($props.Count -ge 2) {
                            try { $exitCode = [string]([int64]$props[1].Value) } catch { $exitCode = [string]$props[1].Value }
                        }
                    }
                    7031 {
                        # Unexpected termination; Properties: [0]=display name, [1]=count, [2]=restart window,
                        # [3]=recovery action code, [4]=restart command
                        $displayName = if ($props.Count -ge 1) { [string]$props[0].Value } else { '' }
                        if ($props.Count -ge 4) {
                            try { $eventActionCode = [int]$props[3].Value } catch { $eventActionCode = -1 }
                        }
                    }
                    7034 {
                        # Unexpected termination; Properties: [0]=display name, [1]=count
                        $displayName = if ($props.Count -ge 1) { [string]$props[0].Value } else { '' }
                    }
                }

                $resolvedServiceName = if ($serviceNameMap.ContainsKey($displayName)) { $serviceNameMap[$displayName] } else { $displayName }
                $recoveryAction = Get-ScmRecoveryAction -Name $resolvedServiceName -FallbackCode $eventActionCode

                $rows.Add([PSCustomObject]@{
                    EventTime          = $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                    EventId            = $evt.Id
                    ServiceName        = $resolvedServiceName
                    ServiceDisplayName = $displayName
                    ExitCode           = $exitCode
                    RecoveryAction     = $recoveryAction
                    Message            = $evt.Message
                })
            }

            # Window-level CrashCount tally per distinct ServiceName, computed over ALL read events
            # before the -ServiceName filter is applied.
            $crashTally = @{}
            foreach ($row in $rows) {
                if ($crashTally.ContainsKey($row.ServiceName)) {
                    $crashTally[$row.ServiceName]++
                } else {
                    $crashTally[$row.ServiceName] = 1
                }
            }

            $results = [System.Collections.Generic.List[psobject]]::new()

            foreach ($row in $rows) {
                if ($results.Count -ge $MaxEvts) { break }

                if (-not [string]::IsNullOrWhiteSpace($ServiceNameFilter) -and $row.ServiceName -ne $ServiceNameFilter) {
                    continue
                }

                $results.Add([PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.ServiceCrashEvent'
                    ComputerName       = $env:COMPUTERNAME
                    EventTime          = $row.EventTime
                    EventId            = $row.EventId
                    ServiceName        = $row.ServiceName
                    ServiceDisplayName = $row.ServiceDisplayName
                    ExitCode           = $row.ExitCode
                    CrashCount         = $crashTally[$row.ServiceName]
                    RecoveryAction     = $row.RecoveryAction
                    Message            = $row.Message
                    Timestamp          = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                })
            }

            $results
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying service crash events on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($startTime, $MaxEvents, $ServiceName)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed service crash event query"
    }
}
