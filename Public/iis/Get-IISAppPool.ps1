#Requires -Version 5.1
function Get-IISAppPool {
    <#
        .SYNOPSIS
            Inventory IIS application pool configuration across one or more servers

        .DESCRIPTION
            Enumerates every IIS application pool on each target server and returns its
            current configuration as typed objects: state, .NET CLR version, managed
            pipeline mode, process identity, auto-start / start mode, request queue
            length, idle timeout, recycling settings (periodic, scheduled, memory
            thresholds) and CPU limits. Read-only; targets remote machines via
            Invoke-RemoteOrLocal and isolates failures per machine so one unreachable
            server never aborts the batch.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name (aliases: CN, Server,
            MachineName). Use $env:COMPUTERNAME, localhost, or . for the local machine.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER Name
            Restrict results to application pools whose Name matches one or more -like
            patterns (alias: AppPoolName). Wildcards accepted. Omit to return all pools.
            Accepts input by property name.

        .EXAMPLE
            Get-IISAppPool

            Returns the configuration of every application pool on the local server.

        .EXAMPLE
            Get-IISAppPool -ComputerName 'WEB01' -Name 'api-*'

            Returns only the application pools whose name starts with 'api-' on WEB01.

        .EXAMPLE
            'WEB01', 'WEB02' | Get-IISAppPool

            Pipes a list of servers and returns every application pool on each.

        .OUTPUTS
            PSWinOps.IISAppPool
            One object per application pool found on each target machine.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-06-22
            Requires: PowerShell 5.1+ / Windows only
            Requires: Web-Server (IIS) role (WebAdministration / IISAdministration module)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/iis/configuration/system.applicationHost/applicationPools/
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.IISAppPool')]
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
        [Alias('AppPoolName')]
        [string[]]$Name
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # ── Remote-capable scriptblock ───────────────────────────────────────
        # Enumerates application pools with the IISAdministration module first,
        # then WebAdministration (IIS:\AppPools\*), then appcmd.exe; throws when
        # no IIS provider is available so the caller can isolate the failure.
        $scriptBlock = {
            param(
                [string[]] $NameFilter
            )

            # ── Local helpers (approved verbs; no top-level module state) ─────
            $toMinutes = {
                param($value)
                if ($null -eq $value) { return 0 }
                if ($value -is [timespan]) { return [int]$value.TotalMinutes }
                $ts = [timespan]::Zero
                if ([timespan]::TryParse([string]$value, [ref]$ts)) { return [int]$ts.TotalMinutes }
                return 0
            }

            $toLong = {
                param($value)
                if ($null -eq $value) { return [long]0 }
                $l = [long]0
                if ([long]::TryParse([string]$value, [ref]$l)) { return $l }
                return [long]0
            }

            $toSchedule = {
                param($collection)
                $result = New-Object 'System.Collections.Generic.List[string]'
                if ($null -ne $collection) {
                    foreach ($entry in $collection) {
                        $t = $entry
                        if ($null -ne $entry -and $entry.PSObject.Properties['Time']) { $t = $entry.Time }
                        if ($t -is [timespan]) {
                            $result.Add($t.ToString('hh\:mm'))
                        }
                        elseif ($null -ne $t) {
                            $ts = [timespan]::Zero
                            if ([timespan]::TryParse([string]$t, [ref]$ts)) { $result.Add($ts.ToString('hh\:mm')) }
                        }
                    }
                }
                return , ([string[]]$result.ToArray())
            }

            # Build a normalised row hashtable from a rich app-pool object
            # (Microsoft.Web.Administration.ApplicationPool, as returned by both
            # IISAdministration's Get-IISAppPool and WebAdministration's Get-Item).
            $toRow = {
                param($pool)

                $cpuLimitRaw = & $toLong $pool.Cpu.Limit
                $cpuPercent  = [int]([math]::Floor($cpuLimitRaw / 1000))

                $identityType = ''
                if ($null -ne $pool.ProcessModel -and $null -ne $pool.ProcessModel.IdentityType) {
                    $identityType = [string]$pool.ProcessModel.IdentityType
                }

                $userName = ''
                if ($identityType -eq 'SpecificUser' -and $null -ne $pool.ProcessModel) {
                    $userName = [string]$pool.ProcessModel.UserName
                }

                @{
                    Name                     = [string]$pool.Name
                    State                    = if ($null -ne $pool.State) { [string]$pool.State } else { 'Unknown' }
                    ManagedRuntimeVersion    = [string]$pool.ManagedRuntimeVersion
                    ManagedPipelineMode      = [string]$pool.ManagedPipelineMode
                    IdentityType             = $identityType
                    Username                 = $userName
                    AutoStart                = [bool]$pool.AutoStart
                    StartMode                = [string]$pool.StartMode
                    QueueLength              = [int](& $toLong $pool.QueueLength)
                    IdleTimeoutMinutes       = & $toMinutes $pool.ProcessModel.IdleTimeout
                    RecyclingPeriodicMinutes = & $toMinutes $pool.Recycling.PeriodicRestart.Time
                    RecyclingScheduledTimes  = & $toSchedule $pool.Recycling.PeriodicRestart.Schedule
                    RecyclingMemoryLimitKB   = & $toLong $pool.Recycling.PeriodicRestart.Memory
                    RecyclingPrivateMemoryKB = & $toLong $pool.Recycling.PeriodicRestart.PrivateMemory
                    CpuLimitPercent          = $cpuPercent
                    CpuLimitAction           = if ($null -ne $pool.Cpu -and $null -ne $pool.Cpu.Action) { [string]$pool.Cpu.Action } else { 'NoAction' }
                }
            }

            # ── 1. Collect raw pool objects via the best available provider ──
            $rawPools  = $null
            $iisLoaded = $false

            if (Get-Module -Name 'IISAdministration' -ListAvailable -ErrorAction SilentlyContinue) {
                try {
                    Import-Module -Name 'IISAdministration' -ErrorAction Stop
                    $rawPools  = @(Get-IISAppPool -ErrorAction Stop)
                    $iisLoaded = $true
                }
                catch {
                    Write-Warning "[$env:COMPUTERNAME] IISAdministration enumeration failed: $($_.Exception.Message)"
                }
            }

            if (-not $iisLoaded -and (Get-Module -Name 'WebAdministration' -ListAvailable -ErrorAction SilentlyContinue)) {
                try {
                    Import-Module -Name 'WebAdministration' -ErrorAction Stop
                    $rawPools  = @(Get-Item -Path 'IIS:\AppPools\*' -ErrorAction Stop)
                    $iisLoaded = $true
                }
                catch {
                    Write-Warning "[$env:COMPUTERNAME] WebAdministration enumeration failed: $($_.Exception.Message)"
                }
            }

            if (-not $iisLoaded) {
                $appcmd = Join-Path -Path $env:windir -ChildPath 'system32\inetsrv\appcmd.exe'
                if (Test-Path -LiteralPath $appcmd -PathType Leaf) {
                    $rawXml = & $appcmd list apppool /config:* /xml 2>$null
                    if ($LASTEXITCODE -eq 0 -and $rawXml) {
                        try {
                            [xml]$doc = $rawXml
                            $rows = New-Object 'System.Collections.Generic.List[hashtable]'
                            foreach ($node in @($doc.appcmd.APPPOOL)) {
                                $add  = $node.add
                                $pm   = $add.processModel
                                $rec  = $add.recycling.periodicRestart
                                $cpu  = $add.cpu
                                $idle = if ($pm) { $pm.idleTimeout } else { $null }
                                $cpuLimitRaw = & $toLong ($(if ($cpu) { $cpu.limit } else { 0 }))
                                $idt = if ($pm) { [string]$pm.identityType } else { '' }
                                $rows.Add(@{
                                    Name                     = [string]$node.'APPPOOL.NAME'
                                    State                    = if ($node.state) { [string]$node.state } else { 'Unknown' }
                                    ManagedRuntimeVersion    = [string]$add.managedRuntimeVersion
                                    ManagedPipelineMode      = [string]$add.managedPipelineMode
                                    IdentityType             = $idt
                                    Username                 = if ($idt -eq 'SpecificUser' -and $pm) { [string]$pm.userName } else { '' }
                                    AutoStart                = ([string]$add.autoStart -eq 'true')
                                    StartMode                = [string]$add.startMode
                                    QueueLength              = [int](& $toLong $add.queueLength)
                                    IdleTimeoutMinutes       = & $toMinutes $idle
                                    RecyclingPeriodicMinutes = & $toMinutes $(if ($rec) { $rec.time } else { $null })
                                    RecyclingScheduledTimes  = & $toSchedule $(if ($rec) { $rec.schedule.add.value } else { $null })
                                    RecyclingMemoryLimitKB   = & $toLong $(if ($rec) { $rec.memory } else { 0 })
                                    RecyclingPrivateMemoryKB = & $toLong $(if ($rec) { $rec.privateMemory } else { 0 })
                                    CpuLimitPercent          = [int]([math]::Floor($cpuLimitRaw / 1000))
                                    CpuLimitAction           = if ($cpu -and $cpu.action) { [string]$cpu.action } else { 'NoAction' }
                                })
                            }
                            $iisLoaded = $true
                            # Apply name filter and emit appcmd rows directly.
                            foreach ($row in $rows) {
                                if ($NameFilter -and $NameFilter.Count -gt 0) {
                                    $match = $false
                                    foreach ($pat in $NameFilter) { if ($row['Name'] -like $pat) { $match = $true; break } }
                                    if (-not $match) { continue }
                                }
                                $row
                            }
                            return
                        }
                        catch {
                            Write-Warning "[$env:COMPUTERNAME] appcmd parse failed: $($_.Exception.Message)"
                        }
                    }
                }
            }

            if (-not $iisLoaded) {
                throw "IIS is not available on '$env:COMPUTERNAME' (no IISAdministration / WebAdministration module and no appcmd.exe). Is the Web-Server (IIS) role installed?"
            }

            # ── 2. Normalise rich objects, apply -Name filter, emit rows ─────
            foreach ($pool in $rawPools) {
                $row = & $toRow $pool
                if ($NameFilter -and $NameFilter.Count -gt 0) {
                    $match = $false
                    foreach ($pat in $NameFilter) { if ($row['Name'] -like $pat) { $match = $true; break } }
                    if (-not $match) { continue }
                }
                $row
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '$targetComputer'"

            try {
                $invokeParams = @{
                    ComputerName = $targetComputer
                    ScriptBlock  = $scriptBlock
                    ArgumentList = @(, $Name)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawResults = Invoke-RemoteOrLocal @invokeParams
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query '$targetComputer': $($_.Exception.Message)"
                continue
            }

            if ($null -eq $rawResults) { continue }

            foreach ($row in $rawResults) {
                [PSCustomObject]@{
                    PSTypeName               = 'PSWinOps.IISAppPool'
                    ComputerName             = $targetComputer
                    Name                     = $row['Name']
                    State                    = $row['State']
                    ManagedRuntimeVersion    = $row['ManagedRuntimeVersion']
                    ManagedPipelineMode      = $row['ManagedPipelineMode']
                    IdentityType             = $row['IdentityType']
                    Username                 = $row['Username']
                    AutoStart                = $row['AutoStart']
                    StartMode                = $row['StartMode']
                    QueueLength              = $row['QueueLength']
                    IdleTimeoutMinutes       = $row['IdleTimeoutMinutes']
                    RecyclingPeriodicMinutes = $row['RecyclingPeriodicMinutes']
                    RecyclingScheduledTimes  = $row['RecyclingScheduledTimes']
                    RecyclingMemoryLimitKB   = $row['RecyclingMemoryLimitKB']
                    RecyclingPrivateMemoryKB = $row['RecyclingPrivateMemoryKB']
                    CpuLimitPercent          = $row['CpuLimitPercent']
                    CpuLimitAction           = $row['CpuLimitAction']
                    Timestamp                = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Done"
    }
}
