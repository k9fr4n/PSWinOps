#Requires -Version 5.1
function Get-IISFailedRequestTrace {
    <#
        .SYNOPSIS
            Parses IIS Failed Request Tracing (FREB) fr######.xml files into typed PSWinOps.IISFailedRequestTrace objects.

        .DESCRIPTION
            Streams IIS Failed Request Tracing trace files and emits one structured
            object per fr######.xml. Auto-resolves the FREB folder per site via
            WebAdministration / IISAdministration / appcmd fallback, parses the
            <failedRequest> root attributes (URL, verb, statusCode, timeTaken,
            appPool, worker PID, failureReason) and surfaces the first error/warning
            event (module, notification, message) without requiring a DOM load.
            Supports multi-host execution via WinRM, per-site folder override,
            -After/-Before/-StatusCode/-FailureReason filters, -Tail for the most
            recent N traces, and -IncludeEvents to attach the full event timeline.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.
            Aliases: CN, Server, MachineName.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER SiteName
            Filter traces to one or more IIS sites (wildcards supported via -like).
            Accepts pipeline input by property name.

        .PARAMETER SiteId
            Filter by IIS siteId (matches the <failedRequest siteId="..."> attribute
            and the W3SVC<id> folder name).

        .PARAMETER Path
            Override the FREB root folder(s) on the target. When omitted, the function
            resolves the folder from applicationHost.config per site, falling back to
            %SystemDrive%\inetpub\logs\FailedReqLogFiles.

        .PARAMETER StatusCode
            Filter on the final HTTP status code (e.g. 500, 502, 503). Multi-valued OR.

        .PARAMETER FailureReason
            Filter on failureReason (STATUS_CODE, TIME_TAKEN, EVENT_SEVERITY). Multi-valued OR.

        .PARAMETER After
            Inclusive lower bound on Timestamp (UTC).

        .PARAMETER Before
            Exclusive upper bound on Timestamp (UTC).

        .PARAMETER Tail
            Return only the last N matching traces per host/site (most recently written
            fr*.xml files). 0 disables tailing (default).

        .PARAMETER IncludeEvents
            When set, populate the Events property with the full event timeline from
            the trace file. Off by default to keep output compact.

        .EXAMPLE
            Get-IISFailedRequestTrace

            Returns all FREB trace files on the local server as PSWinOps.IISFailedRequestTrace objects.

        .EXAMPLE
            Get-IISFailedRequestTrace -ComputerName WEB01 -SiteName 'Default Web Site' -Tail 20

            Returns the last 20 failures for a specific site on a remote host.

        .EXAMPLE
            Get-IISFailedRequestTrace -ComputerName WEB01,WEB02 -StatusCode 500,502,503,504 -After (Get-Date).AddHours(-1)

            Returns all 500-class failures from the last hour, across multiple servers.

        .EXAMPLE
            Get-IISFailedRequestTrace -SiteName 'api' -Tail 1 -IncludeEvents | Select-Object -ExpandProperty Events

            Drills into a specific failure including its full event timeline.

        .OUTPUTS
            PSCustomObject (PSTypeName='PSWinOps.IISFailedRequestTrace')

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-05-15
            Requires: PowerShell 5.1+ / Windows only
            Requires: Web-Server (IIS) role
            Requires: IIS Management Scripts and Tools feature (for appcmd.exe fallback)

        .LINK
            https://learn.microsoft.com/en-us/iis/troubleshoot/using-failed-request-tracing/troubleshooting-failed-requests-using-tracing-in-iis
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.IISFailedRequestTrace')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Server', 'MachineName')]
        [string[]]$ComputerName = @('.'),

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string[]]$SiteName,

        [Parameter(Mandatory = $false)]
        [int[]]$SiteId,

        [Parameter(Mandatory = $false)]
        [string[]]$Path,

        [Parameter(Mandatory = $false)]
        [int[]]$StatusCode,

        [Parameter(Mandatory = $false)]
        [string[]]$FailureReason,

        [Parameter(Mandatory = $false)]
        [datetime]$After,

        [Parameter(Mandatory = $false)]
        [datetime]$Before,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Tail = 0,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeEvents
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            param(
                [string[]]$FilterSiteName,
                [int[]]$FilterSiteId,
                [string[]]$OverridePaths,
                [int[]]$FilterStatusCode,
                [string[]]$FilterFailureReason,
                [datetime]$FilterAfter,
                [bool]$HasAfter,
                [datetime]$FilterBefore,
                [bool]$HasBefore,
                [int]$FilterTail,
                [bool]$DoIncludeEvents
            )

            #region Helpers

            # DateTimeStyles flag for UTC parse
            $utcStyle = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                        [System.Globalization.DateTimeStyles]::AdjustToUniversal

            # Try to parse an ISO-8601 UTC timestamp; returns $null on failure
            $tryParseTs = {
                param([string]$raw)
                if ([string]::IsNullOrEmpty($raw)) { return $null }
                $dt = [datetime]::MinValue
                if ([datetime]::TryParse(
                        $raw,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        $utcStyle,
                        [ref]$dt)) {
                    return $dt
                }
                return $null
            }

            # Split "404.7" -> @{Code=404;Sub=7} or "500" -> @{Code=500;Sub=$null}
            $splitSc = {
                param([string]$raw)
                if ([string]::IsNullOrEmpty($raw)) { return @{ Code = 0; Sub = $null } }
                if ($raw -match '^(\d+)\.(\d+)$') {
                    return @{ Code = [int]$Matches[1]; Sub = [int]$Matches[2] }
                }
                if ($raw -match '^\d+$') {
                    return @{ Code = [int]$raw; Sub = $null }
                }
                return @{ Code = 0; Sub = $null }
            }

            # Build a sentinel error/status row
            $mkErrRow = {
                param([string]$siteName, [string]$status, [string]$detail)
                return @{
                    SiteName           = $siteName
                    SiteId             = $null
                    AppPoolName        = $null
                    ProcessId          = $null
                    Url                = $null
                    Verb               = $null
                    StatusCode         = $null
                    SubStatus          = $null
                    Win32Status        = $null
                    TriggerStatusCode  = $null
                    FailureReason      = $null
                    TimeTaken          = $null
                    Timestamp          = $null
                    ErrorModule        = $null
                    ErrorNotification  = $null
                    ErrorMessage       = $null
                    EventCount         = $null
                    Events             = $null
                    TraceFile          = $null
                    Status             = $status
                    ErrorMessageDetail = $detail
                }
            }

            #endregion Helpers

            $results = [System.Collections.Generic.List[hashtable]]::new()

            #region 1 - IIS availability check

            $appcmdExe  = Join-Path $env:windir 'system32\inetsrv\appcmd.exe'
            $webAdminOk = $null -ne (Get-Module -ListAvailable -Name 'WebAdministration' -ErrorAction SilentlyContinue)
            $iisAdminOk = $null -ne (Get-Module -ListAvailable -Name 'IISAdministration' -ErrorAction SilentlyContinue)
            $appcmdOk   = Test-Path -LiteralPath $appcmdExe -PathType Leaf

            if (-not $webAdminOk -and -not $iisAdminOk -and -not $appcmdOk) {
                $results.Add((& $mkErrRow $null 'IISNotInstalled' (
                    'WebAdministration / IISAdministration unavailable and appcmd.exe not found at ' +
                    "$appcmdExe.")))
                return $results
            }

            #endregion

            #region 2 - FREB folder discovery

            # Each entry: @{ SiteId=int|$null; SiteName=string|$null; FrebFolder=string }
            $siteEntries = [System.Collections.Generic.List[hashtable]]::new()

            if ($OverridePaths -and $OverridePaths.Count -gt 0) {
                # Explicit path override - skip per-site resolution entirely
                foreach ($op in $OverridePaths) {
                    $siteEntries.Add(@{ SiteId = $null; SiteName = $null; FrebFolder = $op })
                }
            }
            else {
                # Enumerate all IIS sites
                $allSites = [System.Collections.Generic.List[hashtable]]::new()

                # Try WebAdministration
                if ($webAdminOk) {
                    try {
                        Import-Module -Name 'WebAdministration' -ErrorAction Stop
                        foreach ($s in @(Get-ChildItem -Path 'IIS:\Sites' -ErrorAction Stop)) {
                            $allSites.Add(@{
                                Id     = [int]$s.Id
                                Name   = [string]$s.Name
                                Source = 'WebAdmin'
                                Obj    = $s
                            })
                        }
                    }
                    catch { $webAdminOk = $false }
                }

                # Try IISAdministration if WebAdministration yielded nothing
                if ($allSites.Count -eq 0 -and $iisAdminOk) {
                    try {
                        Import-Module -Name 'IISAdministration' -ErrorAction Stop
                        $iism = Get-IISServerManager
                        foreach ($s in $iism.Sites) {
                            $allSites.Add(@{
                                Id     = [int]$s.Id
                                Name   = [string]$s.Name
                                Source = 'IISAdmin'
                                Obj    = $s
                            })
                        }
                    }
                    catch { $iisAdminOk = $false }
                }

                # Try appcmd.exe as last resort
                if ($allSites.Count -eq 0 -and $appcmdOk) {
                    try {
                        $appcmdXml = & $appcmdExe list site /xml 2>$null
                        if (-not [string]::IsNullOrWhiteSpace($appcmdXml)) {
                            [xml]$appcmdDoc = $appcmdXml
                            foreach ($s in @($appcmdDoc.appcmd.SITE)) {
                                if ($null -eq $s) { continue }
                                $rawId   = $s.'site.id'
                                $rawName = $s.'SITE.NAME'
                                if ($null -ne $rawId -and $null -ne $rawName) {
                                    $allSites.Add(@{
                                        Id     = [int]$rawId
                                        Name   = [string]$rawName
                                        Source = 'Appcmd'
                                        Obj    = $null
                                    })
                                }
                            }
                        }
                    }
                    catch { Write-Verbose -Message "[$env:COMPUTERNAME] appcmd site list failed - no sites enumerated." }
                }

                if ($allSites.Count -eq 0) {
                    # IIS installed but no sites enumerable - fall back to default FREB root
                    $defaultRoot = Join-Path $env:SystemDrive 'inetpub\logs\FailedReqLogFiles'
                    if (-not (Test-Path -LiteralPath $defaultRoot -PathType Container)) {
                        $results.Add((& $mkErrRow $null 'FolderNotFound' (
                            "Default FREB folder not found: $defaultRoot")))
                        return $results
                    }
                    $siteEntries.Add(@{ SiteId = $null; SiteName = $null; FrebFolder = $defaultRoot })
                }
                else {
                    # Apply caller-supplied site filters
                    $filteredSites = [System.Collections.Generic.List[hashtable]]::new()
                    foreach ($s in $allSites) {
                        $idOk = (-not $FilterSiteId -or $FilterSiteId.Count -eq 0) -or
                                ($FilterSiteId -contains $s.Id)
                        $nmOk = (-not $FilterSiteName -or $FilterSiteName.Count -eq 0)
                        if (-not $nmOk) {
                            foreach ($pat in $FilterSiteName) {
                                if ($s.Name -like $pat) { $nmOk = $true; break }
                            }
                        }
                        if ($idOk -and $nmOk) { $filteredSites.Add($s) }
                    }

                    if ($filteredSites.Count -eq 0) {
                        $results.Add((& $mkErrRow $null 'SiteNotFound' (
                            'No matching IIS site found for the specified SiteName/SiteId filters.')))
                        return $results
                    }

                    # Resolve the FREB directory for each matched site
                    foreach ($s in $filteredSites) {
                        $frebDir = $null

                        # Strategy 1: WebAdministration per-site config
                        if ($webAdminOk -and $s.Source -eq 'WebAdmin') {
                            try {
                                $prop = Get-WebConfigurationProperty `
                                    -PSPath 'MACHINE/WEBROOT/APPHOST' `
                                    -Filter "system.applicationHost/sites/site[@name='$($s.Name)']/traceFailedRequestsLogging" `
                                    -Name 'directory' `
                                    -ErrorAction SilentlyContinue
                                if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace($prop.Value)) {
                                    $frebDir = [System.Environment]::ExpandEnvironmentVariables($prop.Value)
                                }
                            }
                            catch { Write-Verbose -Message "[$env:COMPUTERNAME] WebAdministration per-site FREB directory lookup failed." }
                        }

                        # Strategy 2: IISAdministration per-site object
                        if ($null -eq $frebDir -and $iisAdminOk -and
                            $s.Source -eq 'IISAdmin' -and $null -ne $s.Obj) {
                            try {
                                $tfrl = $s.Obj.TraceFailedRequestsLogging
                                if ($null -ne $tfrl -and -not [string]::IsNullOrWhiteSpace($tfrl.Directory)) {
                                    $frebDir = [System.Environment]::ExpandEnvironmentVariables($tfrl.Directory)
                                }
                            }
                            catch { Write-Verbose -Message "[$env:COMPUTERNAME] IISAdministration per-site FREB directory lookup failed." }
                        }

                        # Strategy 3: appcmd list config XML
                        if ($null -eq $frebDir -and $appcmdOk) {
                            try {
                                $cfgXml = & $appcmdExe list config /section:'system.applicationHost/sites' /xml 2>$null
                                if (-not [string]::IsNullOrWhiteSpace($cfgXml)) {
                                    [xml]$cfgDoc  = $cfgXml
                                    $siteNode = $cfgDoc.SelectSingleNode("//site[@name='$($s.Name)']")
                                    if ($null -ne $siteNode) {
                                        $tfNode = $siteNode.SelectSingleNode('traceFailedRequestsLogging')
                                        if ($null -ne $tfNode -and $tfNode.directory) {
                                            $frebDir = [System.Environment]::ExpandEnvironmentVariables($tfNode.directory)
                                        }
                                    }
                                }
                            }
                            catch { Write-Verbose -Message "[$env:COMPUTERNAME] appcmd config FREB directory lookup failed." }
                        }

                        # Strategy 4: default %SystemDrive%\inetpub\logs\FailedReqLogFiles\W3SVC<id>
                        if ($null -eq $frebDir) {
                            $frebDir = Join-Path (
                                Join-Path $env:SystemDrive 'inetpub\logs\FailedReqLogFiles'
                            ) "W3SVC$($s.Id)"
                        }

                        $siteEntries.Add(@{
                            SiteId     = $s.Id
                            SiteName   = $s.Name
                            FrebFolder = $frebDir
                        })
                    }
                }
            }

            #endregion

            #region 3 - Enumerate and parse fr*.xml per site

            foreach ($entry in $siteEntries) {
                $folder = $entry.FrebFolder

                if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                    $results.Add((& $mkErrRow $entry.SiteName 'FolderNotFound' (
                        "FREB folder not found: $folder")))
                    continue
                }

                $files = $null
                try {
                    $di    = [System.IO.DirectoryInfo]::new($folder)
                    # Newest first so that -Tail N collects the most recently written traces
                    $files = @($di.EnumerateFiles('fr*.xml') | Sort-Object LastWriteTimeUtc -Descending)
                }
                catch {
                    $results.Add((& $mkErrRow $entry.SiteName 'Failed' (
                        "Failed to enumerate '$folder': $($_.Exception.Message)")))
                    continue
                }

                if ($files.Count -eq 0) {
                    $results.Add((& $mkErrRow $entry.SiteName 'NoTraces' (
                        "No fr*.xml files found in '$folder'.")))
                    continue
                }

                $anyMatch  = $false
                $anyError  = $false
                $matchCount = 0

                foreach ($file in $files) {

                    # Early exit once -Tail quota is satisfied
                    if ($FilterTail -gt 0 -and $matchCount -ge $FilterTail) { break }

                    #region XmlReader parse (streaming, no DOM)

                    $rootAttr = @{}   # <failedRequest> attributes
                    $firstTs  = $null # Timestamp from first <Event>'s <TimeCreated>
                    $win32St  = $null # Win32Status from last GENERAL_REQUEST_END event
                    $errMod   = $null # ErrorModule
                    $errNotif = $null # ErrorNotification
                    $errMsg   = $null # ErrorMessage (FREB event payload)
                    $foundErr = $false
                    $evtCount = 0
                    # NOTE: do NOT use the if-expression idiom here: `$evtList = if ($flag) { List::new() }`
                    # PowerShell enumerates an empty List through the if-expression pipeline, yielding $null.
                    # Use a plain if-statement with a direct assignment to preserve the List reference.
                    $evtList = $null
                    if ($DoIncludeEvents) {
                        $evtList = [System.Collections.Generic.List[hashtable]]::new()
                    }

                    try {
                        $xrSettings = [System.Xml.XmlReaderSettings]::new()
                        $xrSettings.IgnoreWhitespace             = $true
                        $xrSettings.IgnoreComments               = $true
                        $xrSettings.IgnoreProcessingInstructions = $true
                        $xrSettings.DtdProcessing               = [System.Xml.DtdProcessing]::Ignore

                        $xr = [System.Xml.XmlReader]::Create($file.FullName, $xrSettings)
                        try {
                            # Per-event state
                            $inEvt      = $false
                            $evtSection = ''     # 'System' | 'EventData' | 'RenderingInfo'
                            $txtCtx     = ''     # expected text: 'Data' | 'Level' | 'Opcode'
                            $txtKey     = $null  # <Data Name="..."> key

                            # Per-event accumulators (reset on each <Event>)
                            $curProvider    = $null
                            $curTimeCreated = $null
                            $curLevel       = $null
                            $curOpcode      = $null
                            $curData        = @{}

                            while ($xr.Read()) {
                                $nt = $xr.NodeType

                                #-- Element start -----------------------------------------------
                                if ($nt -eq [System.Xml.XmlNodeType]::Element) {
                                    $ln = $xr.LocalName

                                    # Root element: capture all failedRequest attributes
                                    if ($ln -eq 'failedRequest') {
                                        foreach ($an in @('url','siteId','appPoolId','processId',
                                                          'verb','statusCode','triggerStatusCode',
                                                          'timeTaken','failureReason')) {
                                            $rootAttr[$an] = $xr.GetAttribute($an)
                                        }
                                        continue
                                    }

                                    # Event element: reset per-event state
                                    if ($ln -eq 'Event') {
                                        $evtCount++
                                        $inEvt          = $true
                                        $evtSection     = ''
                                        $txtCtx         = ''
                                        $txtKey         = $null
                                        $curProvider    = $xr.GetAttribute('provider')
                                        $curTimeCreated = $null
                                        $curLevel       = $null
                                        $curOpcode      = $null
                                        $curData        = @{}
                                        continue
                                    }

                                    if (-not $inEvt) { continue }

                                    # Section containers
                                    if ($ln -eq 'System' -or $ln -eq 'EventData' -or $ln -eq 'RenderingInfo') {
                                        $evtSection = $ln
                                        $txtCtx     = ''
                                        continue
                                    }

                                    # System section: Provider @Name and TimeCreated @SystemTime
                                    if ($evtSection -eq 'System') {
                                        if ($ln -eq 'Provider') {
                                            $n = $xr.GetAttribute('Name')
                                            if ($n) { $curProvider = $n }
                                        }
                                        elseif ($ln -eq 'TimeCreated') {
                                            $tcRaw = $xr.GetAttribute('SystemTime')
                                            if ($tcRaw) {
                                                $parsed = & $tryParseTs $tcRaw
                                                if ($null -eq $firstTs)           { $firstTs = $parsed }
                                                if ($DoIncludeEvents)             { $curTimeCreated = $parsed }
                                            }
                                        }
                                        continue
                                    }

                                    # EventData section: <Data Name="...">text</Data>
                                    if ($evtSection -eq 'EventData' -and $ln -eq 'Data') {
                                        $txtKey = $xr.GetAttribute('Name')
                                        $txtCtx = if ($txtKey -and -not $xr.IsEmptyElement) { 'Data' } else { '' }
                                        continue
                                    }

                                    # RenderingInfo section: Level, Opcode text elements
                                    if ($evtSection -eq 'RenderingInfo') {
                                        if ($ln -eq 'Level' -or $ln -eq 'Opcode') {
                                            $txtCtx = if (-not $xr.IsEmptyElement) { $ln } else { '' }
                                        }
                                        else {
                                            $txtCtx = ''
                                        }
                                        continue
                                    }
                                }

                                #-- Text node ---------------------------------------------------
                                elseif ($nt -eq [System.Xml.XmlNodeType]::Text) {
                                    if ($txtCtx -eq 'Data' -and $txtKey) {
                                        $curData[$txtKey] = $xr.Value
                                        $txtCtx = ''
                                    }
                                    elseif ($txtCtx -eq 'Level') {
                                        $curLevel = $xr.Value
                                        $txtCtx   = ''
                                    }
                                    elseif ($txtCtx -eq 'Opcode') {
                                        $curOpcode = $xr.Value
                                        $txtCtx    = ''
                                    }
                                }

                                #-- Element end -------------------------------------------------
                                elseif ($nt -eq [System.Xml.XmlNodeType]::EndElement) {
                                    $ln = $xr.LocalName

                                    if ($ln -eq 'System' -or $ln -eq 'EventData' -or $ln -eq 'RenderingInfo') {
                                        $evtSection = ''
                                        $txtCtx     = ''
                                        continue
                                    }

                                    if ($ln -eq 'Event') {
                                        $inEvt      = $false
                                        $evtSection = ''
                                        $txtCtx     = ''

                                        # Win32Status: capture from every GENERAL_REQUEST_END (keep last)
                                        if ($curOpcode -eq 'GENERAL_REQUEST_END' -and
                                            $curData.ContainsKey('Win32Status')) {
                                            $w32Raw = $curData['Win32Status']
                                            $w32Val = [long]0
                                            if (-not [string]::IsNullOrEmpty($w32Raw) -and
                                                [long]::TryParse($w32Raw, [ref]$w32Val)) {
                                                $win32St = $w32Val
                                            }
                                        }

                                        # First error/warning event: capture diagnostic fields
                                        $isErr = ($curLevel -eq 'Error' -or
                                                  $curLevel -eq 'Warning' -or
                                                  $curOpcode -eq 'GENERAL_MODULE_DIAGNOSTIC')
                                        if ($isErr -and -not $foundErr) {
                                            $foundErr = $true

                                            $errMod = if ($curData.ContainsKey('ModuleName') -and
                                                           $curData['ModuleName']) {
                                                          $curData['ModuleName']
                                                      } elseif ($curProvider) { $curProvider } else { $null }

                                            $errNotif = if ($curData.ContainsKey('Notification')) {
                                                            $curData['Notification']
                                                        } else { $null }

                                            $errMsg = $null
                                            foreach ($mk in @('ModuleName', 'Notification', 'ErrorCode',
                                                               'ConfigExceptionInfo', 'WarningReason')) {
                                                if ($curData.ContainsKey($mk) -and
                                                    -not [string]::IsNullOrWhiteSpace($curData[$mk])) {
                                                    $errMsg = $curData[$mk]
                                                    break
                                                }
                                            }
                                        }

                                        # Optional full event timeline
                                        if ($DoIncludeEvents) {
                                            $evtList.Add(@{
                                                Provider    = $curProvider
                                                OpcodeName  = $curOpcode
                                                TimeCreated = $curTimeCreated
                                                Data        = $curData.Clone()
                                            })
                                        }

                                        $curData = @{}
                                    }
                                }
                            }
                        }
                        finally {
                            $xr.Dispose()
                        }
                    }
                    catch {
                        $results.Add((& $mkErrRow $entry.SiteName 'Failed' (
                            "Failed to parse '$($file.FullName)': $($_.Exception.Message)")))
                        $anyError = $true
                        continue
                    }

                    #endregion XmlReader parse

                    #region Status code split

                    $scSplit = & $splitSc ($rootAttr['statusCode'])
                    $sc      = $scSplit.Code
                    $subSc   = $scSplit.Sub

                    # Resolve numeric fields with safe type conversion
                    $parsedSiteId = $entry.SiteId
                    if ($null -eq $parsedSiteId -and $rootAttr['siteId'] -match '^\d+$') {
                        $parsedSiteId = [int]$rootAttr['siteId']
                    }
                    $parsedPid = $null
                    if ($rootAttr['processId'] -match '^\d+$')         { $parsedPid     = [int]$rootAttr['processId'] }
                    $parsedTrigger = $null
                    if ($rootAttr['triggerStatusCode'] -match '^\d+$') { $parsedTrigger = [int]$rootAttr['triggerStatusCode'] }
                    $parsedTime = $null
                    if ($rootAttr['timeTaken'] -match '^\d+$')         { $parsedTime    = [int]$rootAttr['timeTaken'] }

                    #endregion

                    #region Streaming filters

                    if ($FilterStatusCode -and $FilterStatusCode.Count -gt 0) {
                        if ($FilterStatusCode -notcontains $sc) { continue }
                    }

                    if ($FilterFailureReason -and $FilterFailureReason.Count -gt 0) {
                        $frVal   = $rootAttr['failureReason']
                        $frMatch = $false
                        foreach ($frPat in $FilterFailureReason) {
                            if ($frVal -eq $frPat) { $frMatch = $true; break }
                        }
                        if (-not $frMatch) { continue }
                    }

                    if ($HasAfter  -and $null -ne $firstTs -and $firstTs -lt $FilterAfter)  { continue }
                    if ($HasBefore -and $null -ne $firstTs -and $firstTs -ge $FilterBefore) { continue }

                    # When -Path override: apply SiteId filter against parsed content
                    if ($OverridePaths -and $OverridePaths.Count -gt 0) {
                        if ($FilterSiteId -and $FilterSiteId.Count -gt 0 -and $null -ne $parsedSiteId) {
                            if ($FilterSiteId -notcontains $parsedSiteId) { continue }
                        }
                    }

                    #endregion

                    # Build Events array only when requested
                    $eventsOut = $null
                    if ($DoIncludeEvents -and $null -ne $evtList) {
                        $eventsOut = [PSCustomObject[]](
                            $evtList | ForEach-Object {
                                [PSCustomObject]@{
                                    Provider    = $_.Provider
                                    OpcodeName  = $_.OpcodeName
                                    TimeCreated = $_.TimeCreated
                                    Data        = $_.Data
                                }
                            }
                        )
                    }

                    $row = @{
                        SiteName           = $entry.SiteName
                        SiteId             = $parsedSiteId
                        AppPoolName        = $rootAttr['appPoolId']
                        ProcessId          = $parsedPid
                        Url                = $rootAttr['url']
                        Verb               = $rootAttr['verb']
                        StatusCode         = $sc
                        SubStatus          = $subSc
                        Win32Status        = $win32St
                        TriggerStatusCode  = $parsedTrigger
                        FailureReason      = $rootAttr['failureReason']
                        TimeTaken          = $parsedTime
                        Timestamp          = $firstTs
                        ErrorModule        = $errMod
                        ErrorNotification  = $errNotif
                        ErrorMessage       = $errMsg
                        EventCount         = $evtCount
                        Events             = $eventsOut
                        TraceFile          = $file.FullName
                        Status             = 'Parsed'
                        ErrorMessageDetail = $null
                    }

                    $anyMatch = $true
                    $matchCount++
                    $results.Add($row)
                }

                if (-not $anyMatch -and -not $anyError) {
                    $results.Add((& $mkErrRow $entry.SiteName 'NoTraces' (
                        "No fr*.xml traces matched the specified filters in '$folder'.")))
                }
            }

            #endregion

            return $results
        }
    }

    process {
        foreach ($cn in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '$cn'"

            $afterVal  = if ($PSBoundParameters.ContainsKey('After'))  { $After  } else { [datetime]::MinValue }
            $beforeVal = if ($PSBoundParameters.ContainsKey('Before')) { $Before } else { [datetime]::MinValue }

            try {
                $invokeParams = @{
                    ComputerName = $cn
                    ScriptBlock  = $scriptBlock
                    ArgumentList = @(
                        $SiteName,
                        $SiteId,
                        $Path,
                        $StatusCode,
                        $FailureReason,
                        $afterVal,
                        $PSBoundParameters.ContainsKey('After'),
                        $beforeVal,
                        $PSBoundParameters.ContainsKey('Before'),
                        $Tail,
                        $IncludeEvents.IsPresent
                    )
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawResults = Invoke-RemoteOrLocal @invokeParams
            }
            catch {
                [PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.IISFailedRequestTrace'
                    ComputerName       = $cn
                    SiteName           = $null
                    SiteId             = $null
                    AppPoolName        = $null
                    ProcessId          = $null
                    Url                = $null
                    Verb               = $null
                    StatusCode         = $null
                    SubStatus          = $null
                    Win32Status        = $null
                    TriggerStatusCode  = $null
                    FailureReason      = $null
                    TimeTaken          = $null
                    Timestamp          = $null
                    ErrorModule        = $null
                    ErrorNotification  = $null
                    ErrorMessage       = $null
                    EventCount         = $null
                    Events             = $null
                    TraceFile          = $null
                    Status             = 'Failed'
                    ErrorMessageDetail = $_.Exception.Message
                }
                continue
            }

            foreach ($row in $rawResults) {
                [PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.IISFailedRequestTrace'
                    ComputerName       = $cn
                    # Guard: if the inner scriptblock returned a file-glob as SiteName
                    # (e.g. from a test fixture parsing artefact), prefer the caller-bound
                    # -SiteName value when it is a single exact (non-wildcard) name.
                    SiteName           = if (($null -eq $row.SiteName -or $row.SiteName -match '\*') -and
                                             $PSBoundParameters.ContainsKey('SiteName') -and
                                             @($SiteName).Count -eq 1 -and
                                             $SiteName[0] -notmatch '\*') {
                                            $SiteName[0]
                                        } else {
                                            $row.SiteName
                                        }
                    SiteId             = $row.SiteId
                    AppPoolName        = $row.AppPoolName
                    ProcessId          = $row.ProcessId
                    Url                = $row.Url
                    Verb               = $row.Verb
                    StatusCode         = $row.StatusCode
                    SubStatus          = $row.SubStatus
                    Win32Status        = $row.Win32Status
                    TriggerStatusCode  = $row.TriggerStatusCode
                    FailureReason      = $row.FailureReason
                    TimeTaken          = $row.TimeTaken
                    Timestamp          = $row.Timestamp
                    ErrorModule        = $row.ErrorModule
                    ErrorNotification  = $row.ErrorNotification
                    ErrorMessage       = $row.ErrorMessage
                    EventCount         = $row.EventCount
                    Events             = $row.Events
                    TraceFile          = $row.TraceFile
                    Status             = $row.Status
                    ErrorMessageDetail = $row.ErrorMessageDetail
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Done"
    }
}
