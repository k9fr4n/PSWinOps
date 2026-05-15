#Requires -Version 5.1
function Get-IISParsedLog {
    <#
        .SYNOPSIS
            Parses IIS W3C extended log files into structured PSWinOps.IISLogEntry objects with streaming, header re-detection, and optional filtering.

        .DESCRIPTION
            Streams one or more IIS W3C extended log files and emits one
            PSWinOps.IISLogEntry object per data line. The parser honours the
            #Fields directive (including mid-file changes after a log restart),
            normalises IIS "-" placeholders to $null, decodes the "+" space
            encoding used by IIS for User-Agent and Referer, and parses date+time
            into a UTC DateTime. Filtering parameters (-After/-Before/-Method/
            -Status/-UriLike/-ClientIP/-Tail) are applied during streaming so
            very large logs do not need to fit in memory.

        .PARAMETER Path
            One or more log file paths or wildcards
            (e.g. C:\inetpub\logs\LogFiles\W3SVC1\u_ex*.log).
            Aliases: FullName, LogFile.
            Accepts pipeline input by value and by property name (Get-ChildItem).

        .PARAMETER LiteralPath
            Literal path, no wildcard expansion. Alias: PSPath.
            Accepts pipeline input by property name.

        .PARAMETER After
            Inclusive lower bound on Timestamp (UTC).
            Entries whose Timestamp is strictly before this value are skipped.

        .PARAMETER Before
            Exclusive upper bound on Timestamp (UTC).
            Entries whose Timestamp is at or after this value are skipped.

        .PARAMETER Method
            Filter on cs-method (e.g. GET, POST). Case-insensitive, multi-valued OR.

        .PARAMETER Status
            Filter on sc-status (e.g. 500, 502, 503). Multi-valued OR.

        .PARAMETER UriLike
            Wildcard pattern matched against UriStem using the -like operator.

        .PARAMETER ClientIP
            Filter on c-ip. Exact match (case-insensitive), multi-valued OR.

        .PARAMETER Tail
            Return only the last N matching entries per file via a circular buffer.
            0 or not specified means no tail limit (default).

        .PARAMETER Encoding
            Text encoding for reading log files. Accepts PowerShell encoding names
            (UTF8, Unicode, ASCII) or .NET code page numbers.
            Defaults to UTF8 (IIS standard).

        .EXAMPLE
            Get-IISParsedLog -Path C:\inetpub\logs\LogFiles\W3SVC1\u_ex260514.log

            Streams all entries from a single IIS log file as PSWinOps.IISLogEntry objects.

        .EXAMPLE
            Get-ChildItem C:\inetpub\logs\LogFiles -Recurse -Filter u_ex*.log |
                Get-IISParsedLog -After (Get-Date).AddHours(-1) -Status 500,502,503,504

            Streams all 5xx entries from the last hour across all IIS sites.

        .EXAMPLE
            Get-IISParsedLog -Path .\u_ex260514.log -Method POST -UriLike '/api/*' |
                Where-Object TimeTaken -gt 2000

            Finds slow POST requests to the /api/* URI path.

        .EXAMPLE
            Get-IISParsedLog -Path .\u_ex260514.log -ClientIP 10.0.0.42 -Tail 100

            Returns the last 100 matching entries from a specific client IP address.

        .OUTPUTS
            PSCustomObject (PSTypeName='PSWinOps.IISLogEntry')
            One object per parsed data line. Properties absent from the active
            #Fields directive are emitted as $null.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-05-15
            Requires: PowerShell 5.1+ / Windows only

            IIS writes log files in UTC by default (unless LocalTimeRollover=true
            in applicationHost.config). Timestamps are always returned as UTC
            DateTime objects regardless of the local system timezone.

            The parser handles mid-file #Fields re-declarations that IIS emits
            after a log rotation or w3wp.exe recycle within a single log file.

        .LINK
            https://github.com/EvotecIT/IISParser
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('PSWinOps.IISLogEntry')]
    param(
        [Parameter(Mandatory = $true, Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'Path')]
        [Alias('FullName', 'LogFile')]
        [SupportsWildcards()]
        [string[]]$Path,

        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'LiteralPath')]
        [Alias('PSPath')]
        [string[]]$LiteralPath,

        [Parameter(Mandatory = $false)]
        [datetime]$After,

        [Parameter(Mandatory = $false)]
        [datetime]$Before,

        [Parameter(Mandatory = $false)]
        [string[]]$Method,

        [Parameter(Mandatory = $false)]
        [int[]]$Status,

        [Parameter(Mandatory = $false)]
        [string]$UriLike,

        [Parameter(Mandatory = $false)]
        [string[]]$ClientIP,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Tail = 0,

        [Parameter(Mandatory = $false)]
        [string]$Encoding = 'UTF8'
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # W3C field name -> output property name
        $fieldPropertyMap = @{
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

        # Properties requiring numeric coercion
        $intProps  = @('ServerPort', 'HttpStatus', 'HttpSubStatus', 'TimeTaken')
        $longProps = @('Win32Status', 'BytesSent', 'BytesReceived')

        # Map PowerShell encoding name to .NET Encoding
        $netEncoding = switch ($Encoding) {
            'UTF8'    { [System.Text.Encoding]::UTF8;    break }
            'UTF-8'   { [System.Text.Encoding]::UTF8;    break }
            'Unicode' { [System.Text.Encoding]::Unicode; break }
            'ASCII'   { [System.Text.Encoding]::ASCII;   break }
            default   {
                try   { [System.Text.Encoding]::GetEncoding($Encoding) }
                catch { [System.Text.Encoding]::UTF8 }
            }
        }
    }

    process {
        # --- Resolve concrete file paths ---
        $resolvedPaths = [System.Collections.Generic.List[string]]::new()

        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            foreach ($p in $Path) {
                $hits = @(Resolve-Path -Path $p -ErrorAction SilentlyContinue)
                if ($hits.Count -eq 0) {
                    Write-Error -Message "[$($MyInvocation.MyCommand)] Path not found: $p"
                    continue
                }
                foreach ($hit in $hits) { $resolvedPaths.Add($hit.ProviderPath) }
            }
        }
        else {
            foreach ($lp in $LiteralPath) {
                if (-not (Test-Path -LiteralPath $lp -PathType Leaf)) {
                    Write-Error -Message "[$($MyInvocation.MyCommand)] LiteralPath not found: $lp"
                    continue
                }
                $resolvedPaths.Add((Resolve-Path -LiteralPath $lp).ProviderPath)
            }
        }

        # --- Parse each file ---
        foreach ($filePath in $resolvedPaths) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Parsing: $filePath"

            # Column layout rebuilt on each #Fields directive
            $activeColumns  = @()
            $dataLineNumber = 0

            # Circular buffer for -Tail
            $tailBuffer = $null
            if ($Tail -gt 0) {
                $tailBuffer = [System.Collections.Generic.Queue[PSObject]]::new()
            }

            try {
                # detectEncodingFromByteOrderMarks = $true to skip any BOM in the log file itself
                $reader = [System.IO.StreamReader]::new($filePath, $netEncoding, $true)
                try {
                    while ($null -ne ($rawLine = $reader.ReadLine())) {

                        # ---- Directive / comment lines ----
                        if ($rawLine.StartsWith('#')) {
                            if ($rawLine.StartsWith('#Fields:')) {
                                $activeColumns = ($rawLine.Substring(8).Trim()) -split '\s+'
                                Write-Verbose -Message (
                                    "[$($MyInvocation.MyCommand)] #Fields re-detected " +
                                    "($($activeColumns.Count) columns): $($activeColumns -join ', ')")
                            }
                            else {
                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Directive: $rawLine"
                            }
                            continue
                        }

                        if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }

                        # ---- Data line ----
                        $dataLineNumber++

                        if ($activeColumns.Count -eq 0) {
                            Write-Warning -Message (
                                "[$($MyInvocation.MyCommand)] Data line encountered before any " +
                                "#Fields directive in '$filePath' (data line $dataLineNumber) — skipped.")
                            continue
                        }

                        $tokens = $rawLine -split '\s+'

                        # Seed all canonical output properties to $null
                        $props = [ordered]@{
                            PSTypeName    = 'PSWinOps.IISLogEntry'
                            Timestamp     = $null
                            LogFile       = $filePath
                            LineNumber    = $dataLineNumber
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

                        for ($i = 0; $i -lt $activeColumns.Count; $i++) {
                            $col = $activeColumns[$i]
                            $raw = if ($i -lt $tokens.Count) { $tokens[$i] } else { '-' }

                            # Date and time are combined into Timestamp later
                            if ($col -eq 'date') { $rawDate = $raw; continue }
                            if ($col -eq 'time') { $rawTime = $raw; continue }

                            if (-not $fieldPropertyMap.ContainsKey($col)) {
                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Unknown column '$col' in #Fields — ignored."
                                continue
                            }

                            $propName = $fieldPropertyMap[$col]

                            # IIS dash-normalisation: '-' means the field was not logged
                            if ($raw -eq '-') {
                                $props[$propName] = $null
                                continue
                            }

                            # Type coercion
                            if ($propName -in $intProps) {
                                $props[$propName] = [int]$raw
                            }
                            elseif ($propName -in $longProps) {
                                $props[$propName] = [long]$raw
                            }
                            elseif ($propName -eq 'UserAgent' -or $propName -eq 'Referer') {
                                # IIS encodes spaces as '+' in these fields — decode back
                                $props[$propName] = $raw -replace '\+', ' '
                            }
                            else {
                                $props[$propName] = $raw
                            }
                        }

                        # Build UTC Timestamp from date + time fields
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
                                Write-Warning -Message (
                                    "[$($MyInvocation.MyCommand)] Cannot parse timestamp " +
                                    "'$rawDate $rawTime' in '$filePath' (line $dataLineNumber) — Timestamp set to `$null.")
                            }
                        }

                        # ---- Apply streaming filters ----
                        $entryTs = $props['Timestamp']
                        if ($PSBoundParameters.ContainsKey('After') -and
                            $null -ne $entryTs -and $entryTs -lt $After) { continue }

                        if ($PSBoundParameters.ContainsKey('Before') -and
                            $null -ne $entryTs -and $entryTs -ge $Before) { continue }

                        if ($PSBoundParameters.ContainsKey('Method') -and
                            $null -ne $props['Method'] -and
                            ($Method -inotcontains $props['Method'])) { continue }

                        if ($PSBoundParameters.ContainsKey('Status') -and
                            $null -ne $props['HttpStatus'] -and
                            ($Status -notcontains $props['HttpStatus'])) { continue }

                        if ($PSBoundParameters.ContainsKey('UriLike') -and
                            $null -ne $props['UriStem'] -and
                            $props['UriStem'] -notlike $UriLike) { continue }

                        if ($PSBoundParameters.ContainsKey('ClientIP') -and
                            $null -ne $props['ClientIP'] -and
                            ($ClientIP -inotcontains $props['ClientIP'])) { continue }

                        # ---- Emit or buffer ----
                        $entry = [PSCustomObject]$props

                        if ($Tail -gt 0) {
                            $tailBuffer.Enqueue($entry)
                            if ($tailBuffer.Count -gt $Tail) {
                                [void]$tailBuffer.Dequeue()
                            }
                        }
                        else {
                            $entry
                        }
                    }
                }
                finally {
                    $reader.Dispose()
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to read '$filePath': $_"
                continue
            }

            # Flush tail circular buffer
            if ($Tail -gt 0 -and $null -ne $tailBuffer) {
                foreach ($tailEntry in $tailBuffer) { $tailEntry }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
