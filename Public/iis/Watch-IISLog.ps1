#Requires -Version 5.1
function Watch-IISLog {
    <#
        .SYNOPSIS
            Streams new entries from a live IIS site log in real time (tail -f), parsing each line into a PSWinOps.IISLogEntry object as it is written.

        .DESCRIPTION
            Resolves the active W3C log file of a given IIS site from its configuration
            (WebAdministration provider, falling back to Microsoft.Web.Administration or
            appcmd.exe), opens it with FileShare.ReadWrite|Delete so as not to disturb
            IIS, and emits each new data line as a structured PSWinOps.IISLogEntry,
            the same shape produced by Get-IISParsedLog. Honours mid-file #Fields
            re-detection (post-recycle) and optionally follows daily log rollover via
            -FollowRollover. Filtering parameters (-Method/-Status/-UriLike/-ClientIP/
            -MinStatus) are applied during streaming. Use -InitialLines to replay the
            last N entries before entering follow mode, and -Duration/-MaxEntries to
            bound a run (recommended for remote sessions).

        .PARAMETER ComputerName
            One or more computer names to tail. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER SiteName
            IIS site whose active log file is to be followed. Resolved via the
            WebAdministration provider, Microsoft.Web.Administration, or appcmd.exe.

        .PARAMETER LogFormat
            Log format in use. Only W3C is supported. IIS, NCSA and Custom formats
            are rejected with a clear error message.

        .PARAMETER InitialLines
            Replay the last N matching data lines from the current log file before
            entering follow mode (tail -n N -f semantics). 0 means pure follow mode:
            only entries written after the cmdlet starts are emitted.

        .PARAMETER FollowRollover
            Detect the daily log rotation (IIS rolls u_exYYMMDD.log) and reopen the
            new file once it appears. Without this switch the cmdlet exits cleanly
            when the current file is rotated away.

        .PARAMETER PollIntervalMs
            Sleep interval in milliseconds between read attempts when at end of stream.
            Defaults to 1000 ms (matching IIS default flush cadence).

        .PARAMETER Duration
            Maximum wall-clock duration of the tail. Whichever cap hits first
            (-Duration or -MaxEntries) ends the stream.

        .PARAMETER MaxEntries
            Hard cap on the number of emitted entries (after filtering). Pairs with
            -Duration to bound remote runs safely.

        .PARAMETER Method
            Filter on cs-method (e.g. GET, POST). Case-insensitive, multi-valued OR.

        .PARAMETER Status
            Filter on sc-status (e.g. 500, 502). Multi-valued OR.

        .PARAMETER UriLike
            Wildcard pattern matched against UriStem via -like.

        .PARAMETER ClientIP
            Filter on c-ip. Exact match, case-insensitive, multi-valued OR.

        .PARAMETER MinStatus
            Emit only entries with sc-status >= N (e.g. 400 to surface all errors).

        .EXAMPLE
            Watch-IISLog -SiteName 'Default Web Site'

            Tails the Default Web Site log in real time, emitting parsed entries.

        .EXAMPLE
            Watch-IISLog -SiteName 'Default Web Site' -InitialLines 50 -MinStatus 400

            Replays the last 50 error-or-worse entries then follows for new ones.

        .EXAMPLE
            Watch-IISLog -SiteName 'www.contoso.com' -FollowRollover -Duration (New-TimeSpan -Hours 1)

            Follows the site log including daily rollover for one hour.

        .EXAMPLE
            'WEB01' | Watch-IISLog -SiteName 'api' -Credential (Get-Credential) -MaxEntries 1000

            Remote tail with credentials, capped at 1000 entries.

        .EXAMPLE
            Watch-IISLog -SiteName 'api' -Method POST -UriLike '/api/*' | Where-Object TimeTaken -gt 2000

            Streams slow POST requests to the /api/* path in real time.

        .OUTPUTS
            PSCustomObject (PSTypeName='PSWinOps.IISLogEntry')
            One object per parsed data line. Properties absent from the active
            #Fields directive are emitted as $null.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-05-15
            Requires: PowerShell 5.1+ / Windows only
            Requires: Web-Server (IIS) role
            Requires: WebAdministration module, Microsoft.Web.Administration, or appcmd.exe

            IIS writes log files in UTC by default. Timestamps are always returned
            as UTC DateTime objects regardless of the local system timezone.

            The parser handles mid-file #Fields re-declarations that IIS emits after
            a log rotation or w3wp.exe recycle within a single file.

            For remote sessions, always supply -Duration or -MaxEntries to bound
            execution; otherwise Ctrl-C is the only way to stop the remote stream.

        .LINK
            https://learn.microsoft.com/en-us/iis/manage/provisioning-and-managing-iis/configure-logging-in-iis
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.IISLogEntry')]
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

        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('W3C')]
        [string]$LogFormat = 'W3C',

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 1000000)]
        [int]$InitialLines = 0,

        [Parameter(Mandatory = $false)]
        [switch]$FollowRollover,

        [Parameter(Mandatory = $false)]
        [ValidateRange(100, 60000)]
        [int]$PollIntervalMs = 1000,

        [Parameter(Mandatory = $false)]
        [timespan]$Duration,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 2147483647)]
        [int]$MaxEntries,

        [Parameter(Mandatory = $false)]
        [string[]]$Method,

        [Parameter(Mandatory = $false)]
        [int[]]$Status,

        [Parameter(Mandatory = $false)]
        [string]$UriLike,

        [Parameter(Mandatory = $false)]
        [string[]]$ClientIP,

        [Parameter(Mandatory = $false)]
        [int]$MinStatus
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # Capture bound-parameter flags in begin{} so process{} can reference them
        # without re-calling ContainsKey on every loop iteration.
        $hasDuration   = $PSBoundParameters.ContainsKey('Duration')
        $hasMaxEntries = $PSBoundParameters.ContainsKey('MaxEntries')
        $hasMethod     = $PSBoundParameters.ContainsKey('Method')
        $hasStatus     = $PSBoundParameters.ContainsKey('Status')
        $hasUriLike    = $PSBoundParameters.ContainsKey('UriLike')
        $hasClientIP   = $PSBoundParameters.ContainsKey('ClientIP')
        $hasMinStatus  = $PSBoundParameters.ContainsKey('MinStatus')

        # =====================================================================
        # Remote scriptblock -- MUST be self-contained (no PSWinOps helpers).
        # Dispatched via Invoke-RemoteOrLocal with an ArgumentList bundle.
        # =====================================================================
        $scriptBlock = {
            param(
                [string]   $ArgSiteName,
                [int]      $ArgInitialLines,
                [bool]     $ArgFollowRollover,
                [int]      $ArgPollIntervalMs,
                [object]   $ArgDuration,        # [timespan] or $null
                [object]   $ArgMaxEntries,      # [int] or $null
                [string[]] $ArgFilterMethod,
                [int[]]    $ArgFilterStatus,
                [object]   $ArgFilterUriLike,   # [string] or $null
                [string[]] $ArgFilterClientIP,
                [object]   $ArgFilterMinStatus  # [int] or $null
            )

            # -----------------------------------------------------------------
            # W3C field name -> output property name (mirrors Get-IISParsedLog)
            # -----------------------------------------------------------------
            $fieldMap = @{
                's-sitename'      = 'SiteName'
                's-computername'  = 'ServerName'
                's-ip'            = 'ServerIP'
                'cs-method'       = 'Method'
                'cs-uri-stem'     = 'UriStem'
                'cs-uri-query'    = 'UriQuery'
                's-port'          = 'ServerPort'
                'cs-username'     = 'UserName'
                'c-ip'            = 'ClientIP'
                'cs(User-Agent)'  = 'UserAgent'
                'cs(Referer)'     = 'Referer'
                'sc-status'       = 'HttpStatus'
                'sc-substatus'    = 'HttpSubStatus'
                'sc-win32-status' = 'Win32Status'
                'sc-bytes'        = 'BytesSent'
                'cs-bytes'        = 'BytesReceived'
                'time-taken'      = 'TimeTaken'
            }

            $intProps = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@('ServerPort', 'HttpStatus', 'HttpSubStatus', 'TimeTaken'),
                [System.StringComparer]::Ordinal
            )
            $longProps = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@('Win32Status', 'BytesSent', 'BytesReceived'),
                [System.StringComparer]::Ordinal
            )

            # -----------------------------------------------------------------
            # Helper: parse one W3C data line -> PSWinOps.IISLogEntry
            # -----------------------------------------------------------------
            function ConvertFrom-IISW3CLine {
                param(
                    [string]   $RawLine,
                    [string[]] $ActiveColumns,
                    [hashtable]$FieldPropertyMap,
                    [System.Collections.Generic.HashSet[string]]$IntPropNames,
                    [System.Collections.Generic.HashSet[string]]$LongPropNames,
                    [string]   $FilePath,
                    [int]      $LineNum
                )
                $tokens = $RawLine -split '\s+'
                $props  = [ordered]@{
                    PSTypeName    = 'PSWinOps.IISLogEntry'
                    Timestamp     = $null
                    LogFile       = $FilePath
                    LineNumber    = $LineNum
                    ComputerName  = $env:COMPUTERNAME
                    SiteName      = $null
                    ServerName    = $null
                    ServerIP      = $null
                    ServerPort    = $null
                    Method        = $null
                    UriStem       = $null
                    UriQuery      = $null
                    UserName      = $null
                    ClientIP      = $null
                    UserAgent     = $null
                    Referer       = $null
                    HttpStatus    = $null
                    HttpSubStatus = $null
                    Win32Status   = $null
                    BytesSent     = $null
                    BytesReceived = $null
                    TimeTaken     = $null
                }
                $rawDate = $null
                $rawTime = $null

                for ($i = 0; $i -lt $ActiveColumns.Count; $i++) {
                    $col = $ActiveColumns[$i]
                    $raw = if ($i -lt $tokens.Count) { $tokens[$i] } else { '-' }

                    if ($col -eq 'date') { $rawDate = $raw; continue }
                    if ($col -eq 'time') { $rawTime = $raw; continue }
                    if (-not $FieldPropertyMap.ContainsKey($col)) { continue }

                    $propName = $FieldPropertyMap[$col]
                    if ($raw -eq '-') { $props[$propName] = $null; continue }

                    if ($IntPropNames.Contains($propName)) {
                        $intVal = 0
                        $props[$propName] = if ([int]::TryParse($raw, [ref]$intVal)) { $intVal } else { $null }
                    }
                    elseif ($LongPropNames.Contains($propName)) {
                        $longVal = [long]0
                        $props[$propName] = if ([long]::TryParse($raw, [ref]$longVal)) { $longVal } else { $null }
                    }
                    elseif ($propName -eq 'UserAgent' -or $propName -eq 'Referer') {
                        $props[$propName] = $raw -replace '\+', ' '
                    }
                    else {
                        $props[$propName] = $raw
                    }
                }

                if ($null -ne $rawDate -and $null -ne $rawTime -and
                    $rawDate -ne '-'    -and $rawTime -ne '-') {
                    try {
                        $props['Timestamp'] = [datetime]::ParseExact(
                            "$rawDate $rawTime",
                            'yyyy-MM-dd HH:mm:ss',
                            [System.Globalization.CultureInfo]::InvariantCulture,
                            ([System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                             [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                        )
                    }
                    catch {
                        Write-Verbose -Message "Watch-IISLog: could not parse timestamp '$rawDate $rawTime' -- Timestamp set to null."
                    }
                }

                return [PSCustomObject]$props
            }

            # -----------------------------------------------------------------
            # Helper: locate the lexicographically latest u_ex*.log in a folder
            # -----------------------------------------------------------------
            function Find-LatestIISLogFile {
                param([string]$Directory)
                if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return $null }
                $found = Get-ChildItem -LiteralPath $Directory -Filter 'u_ex*.log' -File `
                    -ErrorAction SilentlyContinue |
                    Sort-Object -Property Name -Descending |
                    Select-Object -First 1
                return if ($found) { $found.FullName } else { $null }
            }

            # -----------------------------------------------------------------
            # Helper: test whether an entry passes the streaming filters.
            # Filter parameters are passed explicitly so that PSScriptAnalyzer
            # can resolve usage of the outer scriptblock Arg* variables.
            # -----------------------------------------------------------------
            function Test-IISLogEntryFilter {
                param(
                    [PSObject] $Entry,
                    [string[]] $FilterMethod,
                    [int[]]    $FilterStatus,
                    [object]   $FilterUriLike,   # [string] or $null
                    [string[]] $FilterClientIP,
                    [object]   $FilterMinStatus  # [int] or $null
                )
                if ($FilterMethod -and $FilterMethod.Count -gt 0 -and
                    $null -ne $Entry.Method -and
                    ($FilterMethod -inotcontains $Entry.Method)) { return $false }

                if ($FilterStatus -and $FilterStatus.Count -gt 0 -and
                    $null -ne $Entry.HttpStatus -and
                    ($FilterStatus -notcontains $Entry.HttpStatus)) { return $false }

                if ($null -ne $FilterUriLike -and
                    $null -ne $Entry.UriStem -and
                    $Entry.UriStem -notlike $FilterUriLike) { return $false }

                if ($FilterClientIP -and $FilterClientIP.Count -gt 0 -and
                    $null -ne $Entry.ClientIP -and
                    ($FilterClientIP -inotcontains $Entry.ClientIP)) { return $false }

                if ($null -ne $FilterMinStatus -and
                    $null -ne $Entry.HttpStatus -and
                    $Entry.HttpStatus -lt $FilterMinStatus) { return $false }

                return $true
            }

            # -----------------------------------------------------------------
            # Resolve the IIS log directory for $ArgSiteName
            # Priority: WebAdministration -> Microsoft.Web.Administration -> appcmd.exe
            # -----------------------------------------------------------------
            $logDir    = $null
            $resolveOk = $false

            # Method 1: WebAdministration PS provider
            if (-not $resolveOk) {
                try {
                    if (Get-Module -Name WebAdministration -ListAvailable -ErrorAction SilentlyContinue) {
                        Import-Module -Name WebAdministration -ErrorAction Stop
                        $iisItem = Get-Item -Path "IIS:\Sites\$ArgSiteName" -ErrorAction Stop
                        $logFmt  = $iisItem.logFile.logFormat
                        if ($logFmt -ne 'W3C') {
                            Write-Error -Message (
                                "Watch-IISLog: site '$ArgSiteName' uses log format '$logFmt', not W3C. " +
                                'Enable W3C logging in IIS Manager.') -ErrorAction Continue
                            return
                        }
                        $rawDir    = [System.Environment]::ExpandEnvironmentVariables($iisItem.logFile.directory)
                        $siteId    = $iisItem.id
                        $logDir    = Join-Path -Path $rawDir -ChildPath "W3SVC$siteId"
                        $resolveOk = $true
                    }
                }
                catch [System.Management.Automation.ItemNotFoundException] {
                    Write-Error -Message "Watch-IISLog: site '$ArgSiteName' not found in IIS configuration." -ErrorAction Continue
                    return
                }
                catch {
                    Write-Verbose -Message "Watch-IISLog: WebAdministration provider unavailable -- $($_.Exception.Message)"
                }
            }

            # Method 2: Microsoft.Web.Administration assembly
            if (-not $resolveOk) {
                try {
                    $mwaPath = Join-Path -Path $env:SystemRoot -ChildPath 'system32\inetsrv\Microsoft.Web.Administration.dll'
                    if (Test-Path -LiteralPath $mwaPath -PathType Leaf) {
                        if (-not ('Microsoft.Web.Administration.ServerManager' -as [type])) {
                            Add-Type -LiteralPath $mwaPath -ErrorAction Stop
                        }
                        $serverMgr = [Microsoft.Web.Administration.ServerManager]::new()
                        $mwaSite   = $serverMgr.Sites |
                            Where-Object { $_.Name -eq $ArgSiteName } |
                            Select-Object -First 1

                        if ($null -eq $mwaSite) {
                            $serverMgr.Dispose()
                            Write-Error -Message "Watch-IISLog: site '$ArgSiteName' not found in IIS configuration." -ErrorAction Continue
                            return
                        }
                        $logFmt = $mwaSite.LogFile.LogFormat.ToString()
                        if ($logFmt -ne 'W3C') {
                            $serverMgr.Dispose()
                            Write-Error -Message (
                                "Watch-IISLog: site '$ArgSiteName' uses log format '$logFmt', not W3C. " +
                                'Enable W3C logging in IIS Manager.') -ErrorAction Continue
                            return
                        }
                        $rawDir    = [System.Environment]::ExpandEnvironmentVariables($mwaSite.LogFile.Directory)
                        $siteId    = $mwaSite.Id
                        $serverMgr.Dispose()
                        $logDir    = Join-Path -Path $rawDir -ChildPath "W3SVC$siteId"
                        $resolveOk = $true
                    }
                }
                catch {
                    Write-Verbose -Message "Watch-IISLog: Microsoft.Web.Administration assembly unavailable -- $($_.Exception.Message)"
                }
            }

            # Method 3: appcmd.exe
            if (-not $resolveOk) {
                $appcmdPath = Join-Path -Path $env:SystemRoot -ChildPath 'system32\inetsrv\appcmd.exe'
                if (-not (Test-Path -LiteralPath $appcmdPath -PathType Leaf)) {
                    Write-Error -Message (
                        "Watch-IISLog: IIS management tools not found on '$env:COMPUTERNAME'. " +
                        "Install the 'IIS Management Scripts and Tools' Windows feature " +
                        'or the WebAdministration module.') -ErrorAction Continue
                    return
                }
                try {
                    $appcmdRaw = & $appcmdPath list site $ArgSiteName /config:* /xml 2>$null
                    if ([string]::IsNullOrWhiteSpace($appcmdRaw)) {
                        Write-Error -Message "Watch-IISLog: site '$ArgSiteName' not found via appcmd.exe." -ErrorAction Continue
                        return
                    }
                    [xml]$appcmdXml = $appcmdRaw
                    $siteNode = $appcmdXml.appcmd.SITE
                    if ($null -eq $siteNode) {
                        Write-Error -Message "Watch-IISLog: site '$ArgSiteName' not found via appcmd.exe." -ErrorAction Continue
                        return
                    }
                    $logFileNode = $siteNode.site.logFile
                    $logFmt = $logFileNode.logFormat
                    if ($logFmt -ne 'W3C') {
                        Write-Error -Message (
                            "Watch-IISLog: site '$ArgSiteName' uses log format '$logFmt', not W3C.") -ErrorAction Continue
                        return
                    }
                    $rawDir    = [System.Environment]::ExpandEnvironmentVariables($logFileNode.directory)
                    $siteId    = $siteNode.id
                    $logDir    = Join-Path -Path $rawDir -ChildPath "W3SVC$siteId"
                    $resolveOk = $true
                }
                catch {
                    Write-Error -Message (
                        "Watch-IISLog: unable to resolve log directory for site '$ArgSiteName': " +
                        $_.Exception.Message) -ErrorAction Continue
                    return
                }
            }

            if (-not $resolveOk -or [string]::IsNullOrEmpty($logDir)) {
                Write-Error -Message (
                    "Watch-IISLog: unable to resolve IIS log directory for site '$ArgSiteName'. " +
                    "Install the 'IIS Management Scripts and Tools' feature or the WebAdministration module.") `
                    -ErrorAction Continue
                return
            }

            # -----------------------------------------------------------------
            # Wait for the first log file to appear (site may have no traffic yet)
            # -----------------------------------------------------------------
            $startTime      = [datetime]::UtcNow
            $currentLogFile = Find-LatestIISLogFile -Directory $logDir

            while ($null -eq $currentLogFile) {
                if ($null -ne $ArgDuration -and (([datetime]::UtcNow - $startTime) -ge $ArgDuration)) {
                    Write-Verbose -Message "Watch-IISLog: duration elapsed before any log file appeared in '$logDir'."
                    return
                }
                Start-Sleep -Milliseconds $ArgPollIntervalMs
                $currentLogFile = Find-LatestIISLogFile -Directory $logDir
            }

            # -----------------------------------------------------------------
            # Open the active log file with FileShare.ReadWrite|Delete so that
            # IIS (which holds an exclusive write lock) can continue appending.
            # -----------------------------------------------------------------
            $emittedCount  = 0
            $activeColumns = [string[]]@()
            $dataLineCount = 0
            $fileStream    = $null
            $streamReader  = $null

            try {
                $fileStream = [System.IO.FileStream]::new(
                    $currentLogFile,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
                )
                $streamReader = [System.IO.StreamReader]::new(
                    $fileStream,
                    [System.Text.Encoding]::UTF8,
                    $true   # detectEncodingFromByteOrderMarks
                )

                # -------------------------------------------------------------
                # Phase 1: scan existing content to EOF
                #   - track every #Fields directive (header re-detection support)
                #   - when InitialLines > 0: buffer the last N matching entries
                # -------------------------------------------------------------
                $tailQueue = $null
                if ($ArgInitialLines -gt 0) {
                    $tailQueue = [System.Collections.Generic.Queue[PSObject]]::new()
                }

                while ($null -ne ($scanLine = $streamReader.ReadLine())) {
                    if ($scanLine.StartsWith('#Fields:')) {
                        $activeColumns = ($scanLine.Substring(8).Trim()) -split '\s+'
                        continue
                    }
                    if ($scanLine.StartsWith('#') -or [string]::IsNullOrWhiteSpace($scanLine)) { continue }

                    $dataLineCount++

                    if ($null -eq $tailQueue -or $activeColumns.Count -eq 0) { continue }

                    try {
                        $scannedEntry = ConvertFrom-IISW3CLine `
                            -RawLine $scanLine -ActiveColumns $activeColumns `
                            -FieldPropertyMap $fieldMap -IntPropNames $intProps `
                            -LongPropNames $longProps `
                            -FilePath $currentLogFile -LineNum $dataLineCount

                        if (Test-IISLogEntryFilter -Entry $scannedEntry `
                                -FilterMethod    $ArgFilterMethod `
                                -FilterStatus    $ArgFilterStatus `
                                -FilterUriLike   $ArgFilterUriLike `
                                -FilterClientIP  $ArgFilterClientIP `
                                -FilterMinStatus $ArgFilterMinStatus) {
                            $tailQueue.Enqueue($scannedEntry)
                            if ($tailQueue.Count -gt $ArgInitialLines) { [void]$tailQueue.Dequeue() }
                        }
                    }
                    catch {
                        Write-Warning -Message "Watch-IISLog: failed to parse line $dataLineCount in '$currentLogFile': $_"
                    }
                }

                # Emit the tail buffer before entering follow mode
                if ($null -ne $tailQueue) {
                    foreach ($initialEntry in $tailQueue) {
                        $initialEntry
                        $emittedCount++
                        if ($null -ne $ArgMaxEntries -and $emittedCount -ge $ArgMaxEntries) { return }
                    }
                    $tailQueue = $null
                }

                # -------------------------------------------------------------
                # Phase 2: follow loop -- positioned at EOF after Phase 1
                # -------------------------------------------------------------
                while ($true) {
                    if ($null -ne $ArgDuration -and (([datetime]::UtcNow - $startTime) -ge $ArgDuration)) { break }
                    if ($null -ne $ArgMaxEntries -and $emittedCount -ge $ArgMaxEntries) { break }

                    $followLine = $streamReader.ReadLine()

                    if ($null -eq $followLine) {
                        # EOF -- check for log rollover when requested
                        if ($ArgFollowRollover) {
                            $newerFile = Find-LatestIISLogFile -Directory $logDir
                            if ($null -ne $newerFile -and $newerFile -ne $currentLogFile) {
                                $streamReader.Dispose()
                                $fileStream.Dispose()
                                $fileStream   = $null
                                $streamReader = $null

                                $currentLogFile = $newerFile
                                $dataLineCount  = 0
                                $activeColumns  = [string[]]@()

                                $fileStream = [System.IO.FileStream]::new(
                                    $currentLogFile,
                                    [System.IO.FileMode]::Open,
                                    [System.IO.FileAccess]::Read,
                                    ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
                                )
                                $streamReader = [System.IO.StreamReader]::new(
                                    $fileStream,
                                    [System.Text.Encoding]::UTF8,
                                    $true
                                )
                                continue
                            }
                        }
                        Start-Sleep -Milliseconds $ArgPollIntervalMs
                        continue
                    }

                    # Handle directive lines -- mid-stream #Fields re-detection
                    if ($followLine.StartsWith('#Fields:')) {
                        $activeColumns = ($followLine.Substring(8).Trim()) -split '\s+'
                        continue
                    }
                    if ($followLine.StartsWith('#') -or [string]::IsNullOrWhiteSpace($followLine)) { continue }

                    $dataLineCount++

                    if ($activeColumns.Count -eq 0) {
                        Write-Warning -Message (
                            "Watch-IISLog: data line $dataLineCount before any #Fields directive " +
                            "in '$currentLogFile' -- skipped.")
                        continue
                    }

                    try {
                        $liveEntry = ConvertFrom-IISW3CLine `
                            -RawLine $followLine -ActiveColumns $activeColumns `
                            -FieldPropertyMap $fieldMap -IntPropNames $intProps `
                            -LongPropNames $longProps `
                            -FilePath $currentLogFile -LineNum $dataLineCount

                        if (Test-IISLogEntryFilter -Entry $liveEntry `
                                -FilterMethod    $ArgFilterMethod `
                                -FilterStatus    $ArgFilterStatus `
                                -FilterUriLike   $ArgFilterUriLike `
                                -FilterClientIP  $ArgFilterClientIP `
                                -FilterMinStatus $ArgFilterMinStatus) {
                            $liveEntry
                            $emittedCount++
                        }
                    }
                    catch {
                        Write-Warning -Message "Watch-IISLog: failed to parse line $dataLineCount in '$currentLogFile': $_"
                    }
                }
            }
            finally {
                if ($null -ne $streamReader) {
                    try   { $streamReader.Dispose() }
                    catch { Write-Verbose -Message "Watch-IISLog: error disposing streamReader -- $($_.Exception.Message)" }
                }
                if ($null -ne $fileStream) {
                    try   { $fileStream.Dispose() }
                    catch { Write-Verbose -Message "Watch-IISLog: error disposing fileStream -- $($_.Exception.Message)" }
                }
            }
        }
    }

    process {
        foreach ($cn in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Tailing IIS log for site '$SiteName' on '$cn'"

            try {
                $invokeParams = @{
                    ComputerName = $cn
                    ScriptBlock  = $scriptBlock
                    ArgumentList = @(
                        $SiteName,
                        $InitialLines,
                        $FollowRollover.IsPresent,
                        $PollIntervalMs,
                        $(if ($hasDuration)   { $Duration   } else { $null }),
                        $(if ($hasMaxEntries) { $MaxEntries } else { $null }),
                        $(if ($hasMethod)     { $Method     } else { [string[]]@() }),
                        $(if ($hasStatus)     { $Status     } else { [int[]]@() }),
                        $(if ($hasUriLike)    { $UriLike    } else { $null }),
                        $(if ($hasClientIP)   { $ClientIP   } else { [string[]]@() }),
                        $(if ($hasMinStatus)  { $MinStatus  } else { $null })
                    )
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }
                Invoke-RemoteOrLocal @invokeParams
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to tail IIS log on '$cn': $($_.Exception.Message)"
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
