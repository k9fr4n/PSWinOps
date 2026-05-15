#Requires -Version 5.1
function Get-IISWorkerProcess {
    <#
        .SYNOPSIS
            Inventories IIS worker processes (w3wp.exe) enriched with app pool, sites, identity, and resource metrics.

        .DESCRIPTION
            Enumerates every w3wp.exe process on one or more target servers and joins
            it with IIS configuration so each row carries the owning application pool,
            the sites and applications it serves, its identity, PID, uptime, CPU time,
            memory footprint (working set / private / virtual), thread count and handle
            count. Provides the operational overview that the native IISAdministration
            module does not expose in a single cmdlet. Falls back gracefully from
            WebAdministration to IISAdministration to appcmd/CIM when modules are
            missing, and from Get-Process to CIM Win32_Process when needed.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER AppPoolName
            Restrict the inventory to w3wp processes belonging to one or more named
            application pools. Wildcards accepted via -like.

        .PARAMETER ProcessId
            Filter to specific worker process PIDs (useful when correlating with
            Get-Process / event logs).

        .EXAMPLE
            Get-IISWorkerProcess

            Returns all running w3wp.exe processes on the local machine enriched with
            app pool, site, identity and resource data.

        .EXAMPLE
            Get-IISWorkerProcess -ComputerName 'WEB01'

            Returns IIS worker process inventory from a single remote server.

        .EXAMPLE
            'WEB01','WEB02' | Get-IISWorkerProcess -Credential (Get-Credential)

            Queries multiple remote servers via pipeline with alternate credentials.

        .EXAMPLE
            Get-IISWorkerProcess -AppPoolName 'DefaultAppPool','API*'

            Returns only worker processes belonging to DefaultAppPool or any pool
            whose name matches API*.

        .EXAMPLE
            Get-IISWorkerProcess | Sort-Object WorkingSetMB -Descending | Select-Object -First 5

            Returns the top 5 worker processes by working set memory.

        .OUTPUTS
            PSCustomObject (PSTypeName='PSWinOps.IISWorkerProcess')

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-05-15
            Requires: PowerShell 5.1+ / Windows only
            Requires: Web-Server (IIS) role
            Optional: Module WebAdministration or IISAdministration (falls back to appcmd)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/iis/get-started/planning-your-iis-architecture/introduction-to-iis-architecture#worker-processes
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.IISWorkerProcess')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory = $false)]
        [string[]]$AppPoolName,

        [Parameter(Mandatory = $false)]
        [int[]]$ProcessId
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            param(
                [string[]]$FilterAppPool,
                [int[]]$FilterPid
            )

            $results = [System.Collections.Generic.List[hashtable]]::new()

            # ── 1. Verify IIS (W3SVC) presence ───────────────────────────────
            try {
                $null = Get-Service -Name 'W3SVC' -ErrorAction Stop
            }
            catch {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    Sites           = @()
                    Applications    = @()
                    Identity        = $null
                    IdentityType    = $null
                    StartTime       = $null
                    UptimeSeconds   = $null
                    CPUSeconds      = $null
                    WorkingSetMB    = $null
                    PrivateMemoryMB = $null
                    VirtualMemoryMB = $null
                    ThreadCount     = $null
                    HandleCount     = $null
                    CommandLine     = $null
                    Status          = 'IISNotInstalled'
                    ErrorMessage    = "W3SVC service not found: $($_.Exception.Message)"
                })
                return $results
            }

            # ── 2. Collect w3wp.exe process data ─────────────────────────────
            # Primary path: Get-Process (gives CPU/memory/threads/handles/starttime)
            $procMap    = @{}   # int PID -> System.Diagnostics.Process
            $cimProcMap = @{}   # int PID -> CIM Win32_Process (for CommandLine + fallback)

            try {
                foreach ($p in @(Get-Process -Name 'w3wp' -ErrorAction Stop)) {
                    $procMap[[int]$p.Id] = $p
                }
            }
            catch {
                Write-Verbose -Message '[Get-IISWorkerProcess] Get-Process w3wp returned no results; using CIM fallback.'
            }

            # CIM is always queried for CommandLine (not exposed by Get-Process)
            try {
                $cimInstances = @(Get-CimInstance -ClassName 'Win32_Process' `
                    -Filter "Name='w3wp.exe'" -ErrorAction Stop)
                foreach ($cp in $cimInstances) {
                    $cpid = [int]$cp.ProcessId
                    $cimProcMap[$cpid] = $cp
                    if (-not $procMap.ContainsKey($cpid)) {
                        $procMap[$cpid] = $null
                    }
                }
            }
            catch {
                Write-Verbose -Message '[Get-IISWorkerProcess] CIM Win32_Process query failed.'
            }

            if ($procMap.Count -eq 0) {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    Sites           = @()
                    Applications    = @()
                    Identity        = $null
                    IdentityType    = $null
                    StartTime       = $null
                    UptimeSeconds   = $null
                    CPUSeconds      = $null
                    WorkingSetMB    = $null
                    PrivateMemoryMB = $null
                    VirtualMemoryMB = $null
                    ThreadCount     = $null
                    HandleCount     = $null
                    CommandLine     = $null
                    Status          = 'NoWorkerProcess'
                    ErrorMessage    = $null
                })
                return $results
            }

            # ── 3. PID -> AppPool mapping via appcmd ─────────────────────────
            $pidToPool = @{}
            $appcmdExe = Join-Path -Path $env:windir -ChildPath 'system32\inetsrv\appcmd.exe'

            if (Test-Path -LiteralPath $appcmdExe -PathType Leaf) {
                try {
                    $wpRaw = & $appcmdExe list wp /xml 2>$null
                    if (-not [string]::IsNullOrWhiteSpace($wpRaw)) {
                        [xml]$wpXml = $wpRaw
                        foreach ($wpNode in @($wpXml.appcmd.WP)) {
                            if ($null -ne $wpNode) {
                                $pidToPool[[int]$wpNode.PID] = $wpNode.'APPPOOL.NAME'
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose -Message "[Get-IISWorkerProcess] appcmd list wp failed: $($_.Exception.Message)"
                }
            }

            # ── 4. AppPool identity + Sites/Apps via IIS module or appcmd ────
            $poolIdentityMap = @{}
            $poolToSites     = @{}
            $poolToApps      = @{}
            $iisLoaded       = $false

            # -- WebAdministration path --
            if (-not $iisLoaded -and
                (Get-Module -Name 'WebAdministration' -ListAvailable -ErrorAction SilentlyContinue)) {
                try {
                    Import-Module -Name 'WebAdministration' -ErrorAction Stop

                    foreach ($pool in @(Get-ChildItem -Path 'IIS:\AppPools' `
                            -ErrorAction SilentlyContinue)) {
                        $pm           = $pool.processModel
                        $rawIdType    = [string]$pm.identityType
                        $identityType = switch ($rawIdType) {
                            'ApplicationPoolIdentity' { 'ApplicationPoolIdentity' }
                            'LocalSystem'             { 'LocalSystem'             }
                            'LocalService'            { 'LocalService'            }
                            'NetworkService'          { 'NetworkService'          }
                            'SpecificUser'            { 'SpecificUser'            }
                            default                   { 'Unknown'                 }
                        }
                        $identity = if ($identityType -eq 'SpecificUser') {
                            [string]$pm.userName
                        }
                        else { $identityType }
                        $poolIdentityMap[$pool.Name] = @{
                            Identity     = $identity
                            IdentityType = $identityType
                        }
                    }

                    foreach ($site in @(Get-Website -ErrorAction SilentlyContinue)) {
                        $pn = [string]$site.applicationPool
                        if (-not $poolToSites.ContainsKey($pn)) {
                            $poolToSites[$pn] = [System.Collections.Generic.List[string]]::new()
                        }
                        if (-not $poolToSites[$pn].Contains($site.Name)) {
                            $poolToSites[$pn].Add($site.Name)
                        }
                    }

                    foreach ($app in @(Get-WebApplication -ErrorAction SilentlyContinue)) {
                        $pn       = [string]$app.applicationPool
                        $siteName = $app.PSParentPath -replace '^.*\\Sites\\', ''
                        if (-not $poolToApps.ContainsKey($pn)) {
                            $poolToApps[$pn] = [System.Collections.Generic.List[string]]::new()
                        }
                        $poolToApps[$pn].Add("$siteName$($app.Path)")
                    }

                    $iisLoaded = $true
                }
                catch {
                    Write-Verbose -Message "[Get-IISWorkerProcess] WebAdministration failed: $($_.Exception.Message)"
                }
            }

            # -- IISAdministration path --
            if (-not $iisLoaded -and
                (Get-Module -Name 'IISAdministration' -ListAvailable -ErrorAction SilentlyContinue)) {
                try {
                    Import-Module -Name 'IISAdministration' -ErrorAction Stop

                    foreach ($pool in @(Get-IISAppPool -ErrorAction Stop)) {
                        $rawIdType    = $pool.ProcessModel.IdentityType.ToString()
                        $identityType = switch ($rawIdType) {
                            'ApplicationPoolIdentity' { 'ApplicationPoolIdentity' }
                            'LocalSystem'             { 'LocalSystem'             }
                            'LocalService'            { 'LocalService'            }
                            'NetworkService'          { 'NetworkService'          }
                            'SpecificUser'            { 'SpecificUser'            }
                            default                   { 'Unknown'                 }
                        }
                        $identity = if ($identityType -eq 'SpecificUser') {
                            [string]$pool.ProcessModel.UserName
                        }
                        else { $identityType }
                        $poolIdentityMap[$pool.Name] = @{
                            Identity     = $identity
                            IdentityType = $identityType
                        }
                    }

                    foreach ($site in @(Get-IISSite -ErrorAction Stop)) {
                        foreach ($app in $site.Applications) {
                            $pn = [string]$app.ApplicationPoolName
                            if ($app.Path -eq '/') {
                                if (-not $poolToSites.ContainsKey($pn)) {
                                    $poolToSites[$pn] = [System.Collections.Generic.List[string]]::new()
                                }
                                if (-not $poolToSites[$pn].Contains($site.Name)) {
                                    $poolToSites[$pn].Add($site.Name)
                                }
                            }
                            else {
                                if (-not $poolToApps.ContainsKey($pn)) {
                                    $poolToApps[$pn] = [System.Collections.Generic.List[string]]::new()
                                }
                                $poolToApps[$pn].Add("$($site.Name)$($app.Path)")
                            }
                        }
                    }

                    $iisLoaded = $true
                }
                catch {
                    Write-Verbose -Message "[Get-IISWorkerProcess] IISAdministration failed: $($_.Exception.Message)"
                }
            }

            # -- appcmd fallback for identity + site/app mapping --
            if (-not $iisLoaded -and (Test-Path -LiteralPath $appcmdExe -PathType Leaf)) {
                try {
                    $rawPools = & $appcmdExe list apppool /xml /config:* 2>$null
                    if (-not [string]::IsNullOrWhiteSpace($rawPools)) {
                        [xml]$poolXml = $rawPools
                        foreach ($poolNode in @($poolXml.appcmd.APPPOOL)) {
                            if ($null -eq $poolNode) { continue }
                            $addNode      = $poolNode.add
                            $rawIdType    = [string]$addNode.processModel.identityType
                            $identityType = switch ($rawIdType) {
                                'ApplicationPoolIdentity' { 'ApplicationPoolIdentity' }
                                'LocalSystem'             { 'LocalSystem'             }
                                'LocalService'            { 'LocalService'            }
                                'NetworkService'          { 'NetworkService'          }
                                'SpecificUser'            { 'SpecificUser'            }
                                default                   { 'Unknown'                 }
                            }
                            $identity = if ($identityType -eq 'SpecificUser') {
                                [string]$addNode.processModel.userName
                            }
                            else { $identityType }
                            $poolIdentityMap[$poolNode.'APPPOOL.NAME'] = @{
                                Identity     = $identity
                                IdentityType = $identityType
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose -Message "[Get-IISWorkerProcess] appcmd list apppool failed: $($_.Exception.Message)"
                }

                try {
                    $rawApps = & $appcmdExe list app /xml 2>$null
                    if (-not [string]::IsNullOrWhiteSpace($rawApps)) {
                        [xml]$appXml = $rawApps
                        foreach ($appNode in @($appXml.appcmd.APP)) {
                            if ($null -eq $appNode) { continue }
                            $pn      = [string]$appNode.'APPPOOL.NAME'
                            $appName = [string]$appNode.'APP.NAME'
                            $parts   = $appName -split '/', 2
                            $sn      = $parts[0]
                            $vPath   = if ($parts.Count -gt 1) { '/' + $parts[1] } else { '/' }

                            if ($vPath -eq '/') {
                                if (-not $poolToSites.ContainsKey($pn)) {
                                    $poolToSites[$pn] = [System.Collections.Generic.List[string]]::new()
                                }
                                if (-not $poolToSites[$pn].Contains($sn)) {
                                    $poolToSites[$pn].Add($sn)
                                }
                            }
                            else {
                                if (-not $poolToApps.ContainsKey($pn)) {
                                    $poolToApps[$pn] = [System.Collections.Generic.List[string]]::new()
                                }
                                $poolToApps[$pn].Add("$sn$vPath")
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose -Message "[Get-IISWorkerProcess] appcmd list app failed: $($_.Exception.Message)"
                }
            }

            # ── 5. Build result objects ───────────────────────────────────────
            foreach ($workerPid in ($procMap.Keys | Sort-Object)) {
                $pool = if ($pidToPool.ContainsKey($workerPid)) {
                    $pidToPool[$workerPid]
                }
                else { '' }

                # Apply business filters
                if ($FilterPid.Count -gt 0 -and ($FilterPid -notcontains $workerPid)) { continue }

                if ($FilterAppPool.Count -gt 0) {
                    $poolMatched = $false
                    foreach ($fp in $FilterAppPool) {
                        if ($pool -like $fp) { $poolMatched = $true; break }
                    }
                    if (-not $poolMatched) { continue }
                }

                # Identity
                $identity     = if ($poolIdentityMap.ContainsKey($pool)) {
                    $poolIdentityMap[$pool].Identity
                }
                else { '' }
                $identityType = if ($poolIdentityMap.ContainsKey($pool)) {
                    $poolIdentityMap[$pool].IdentityType
                }
                else { 'Unknown' }

                # Sites / Applications
                $sites = if ($poolToSites.ContainsKey($pool)) {
                    @($poolToSites[$pool])
                }
                else { @() }
                $apps  = if ($poolToApps.ContainsKey($pool)) {
                    @($poolToApps[$pool])
                }
                else { @() }

                # Status
                $status = if ([string]::IsNullOrEmpty($pool)) { 'Orphaned' } else { 'Running' }

                # Process metrics
                $procObj      = $procMap[$workerPid]
                $cimObj       = if ($cimProcMap.ContainsKey($workerPid)) {
                    $cimProcMap[$workerPid]
                }
                else { $null }
                $startTime    = $null
                $uptimeSecs   = [long]0
                $cpuSecs      = [double]0
                $workingSetMB = [long]0
                $privateMemMB = [long]0
                $virtualMemMB = [long]0
                $threadCount  = 0
                $handleCount  = 0
                $commandLine  = ''

                if ($null -ne $procObj -and $procObj -is [System.Diagnostics.Process]) {
                    try {
                        $startTime = $procObj.StartTime
                    }
                    catch {
                        Write-Verbose -Message "[Get-IISWorkerProcess] Cannot read StartTime for PID $workerPid."
                    }
                    if ($null -ne $startTime) {
                        $uptimeSecs = [long]([datetime]::Now - $startTime).TotalSeconds
                    }
                    try {
                        $cpuSecs = [Math]::Round($procObj.TotalProcessorTime.TotalSeconds, 2)
                    }
                    catch {
                        Write-Verbose -Message "[Get-IISWorkerProcess] Cannot read CPU time for PID $workerPid."
                    }
                    $workingSetMB = [long]($procObj.WorkingSet64       / 1MB)
                    $privateMemMB = [long]($procObj.PrivateMemorySize64 / 1MB)
                    $virtualMemMB = [long]($procObj.VirtualMemorySize64 / 1MB)
                    try {
                        $threadCount = $procObj.Threads.Count
                    }
                    catch {
                        Write-Verbose -Message "[Get-IISWorkerProcess] Cannot read thread count for PID $workerPid."
                    }
                    try {
                        $handleCount = $procObj.HandleCount
                    }
                    catch {
                        Write-Verbose -Message "[Get-IISWorkerProcess] Cannot read handle count for PID $workerPid."
                    }
                }
                elseif ($null -ne $cimObj) {
                    $startTime = $cimObj.CreationDate
                    if ($null -ne $startTime) {
                        $uptimeSecs = [long]([datetime]::Now - $startTime).TotalSeconds
                    }
                    $workingSetMB = [long]($cimObj.WorkingSetSize / 1MB)
                    $threadCount  = [int]$cimObj.ThreadCount
                    $handleCount  = [int]$cimObj.HandleCount
                }

                if ($null -ne $cimObj) {
                    $commandLine = [string]$cimObj.CommandLine
                }

                $results.Add(@{
                    ProcessId       = $workerPid
                    AppPoolName     = $pool
                    Sites           = $sites
                    Applications    = $apps
                    Identity        = $identity
                    IdentityType    = $identityType
                    StartTime       = $startTime
                    UptimeSeconds   = $uptimeSecs
                    CPUSeconds      = $cpuSecs
                    WorkingSetMB    = $workingSetMB
                    PrivateMemoryMB = $privateMemMB
                    VirtualMemoryMB = $virtualMemMB
                    ThreadCount     = $threadCount
                    HandleCount     = $handleCount
                    CommandLine     = $commandLine
                    Status          = $status
                    ErrorMessage    = $null
                })
            }

            if ($results.Count -eq 0) {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    Sites           = @()
                    Applications    = @()
                    Identity        = $null
                    IdentityType    = $null
                    StartTime       = $null
                    UptimeSeconds   = $null
                    CPUSeconds      = $null
                    WorkingSetMB    = $null
                    PrivateMemoryMB = $null
                    VirtualMemoryMB = $null
                    ThreadCount     = $null
                    HandleCount     = $null
                    CommandLine     = $null
                    Status          = 'NoWorkerProcess'
                    ErrorMessage    = $null
                })
            }

            return $results
        }
    }

    process {
        $filterPoolArg = if ($PSBoundParameters.ContainsKey('AppPoolName')) { $AppPoolName } else { @() }
        $filterPidArg  = if ($PSBoundParameters.ContainsKey('ProcessId'))   { $ProcessId  } else { @() }

        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '$machine'"

            try {
                $rawResults = Invoke-RemoteOrLocal `
                    -ComputerName $machine `
                    -Credential   $Credential `
                    -ScriptBlock  $scriptBlock `
                    -ArgumentList @($filterPoolArg, $filterPidArg)

                foreach ($entry in $rawResults) {
                    [PSCustomObject]@{
                        PSTypeName      = 'PSWinOps.IISWorkerProcess'
                        ComputerName    = $displayName
                        ProcessId       = $entry.ProcessId
                        AppPoolName     = $entry.AppPoolName
                        Sites           = $entry.Sites
                        Applications    = $entry.Applications
                        Identity        = $entry.Identity
                        IdentityType    = $entry.IdentityType
                        StartTime       = $entry.StartTime
                        UptimeSeconds   = $entry.UptimeSeconds
                        CPUSeconds      = $entry.CPUSeconds
                        WorkingSetMB    = $entry.WorkingSetMB
                        PrivateMemoryMB = $entry.PrivateMemoryMB
                        VirtualMemoryMB = $entry.VirtualMemoryMB
                        ThreadCount     = $entry.ThreadCount
                        HandleCount     = $entry.HandleCount
                        CommandLine     = $entry.CommandLine
                        Status          = $entry.Status
                        ErrorMessage    = $entry.ErrorMessage
                        Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '$machine': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
