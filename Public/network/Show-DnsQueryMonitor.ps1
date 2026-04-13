#Requires -Version 5.1

function Show-DnsQueryMonitor {
    <#
        .SYNOPSIS
            Interactive real-time DNS query monitor with ANSI-colored console display

        .DESCRIPTION
            Continuously polls the Windows DNS Client ETW operational log and displays
            live DNS queries in an interactive console interface with color-coded status.
            Supports keyboard controls for filtering, pausing, clearing, and quitting.
            Press Q to quit, P to pause/resume, C to clear, F to set a domain filter,
            T to cycle query type filter, S to cycle sort mode.
            The DNS Client operational log is automatically enabled if not already active.

        .PARAMETER RefreshInterval
            Refresh interval in seconds. Default: 1. Valid range: 1-30.

        .PARAMETER DomainFilter
            Initial domain filter. Supports wildcards (e.g. '*.google.com').
            Can be changed interactively by pressing F.

        .PARAMETER MaxLines
            Maximum number of DNS events to display. Default: 50. Valid range: 10-500.

        .PARAMETER NoClear
            Suppresses the console clear on exit so the final frame remains visible
            in the scrollback buffer.

        .PARAMETER NoColor
            Disables ANSI color output for terminals that do not support escape sequences.

        .EXAMPLE
            Show-DnsQueryMonitor

            Starts the DNS query monitor with default settings. Press Q to quit.

        .EXAMPLE
            Show-DnsQueryMonitor -DomainFilter '*.microsoft.com' -RefreshInterval 2

            Monitors only Microsoft domain queries with a 2-second refresh.

        .EXAMPLE
            Show-DnsQueryMonitor -MaxLines 100 -NoColor

            Shows up to 100 DNS events without ANSI colors.

        .OUTPUTS
            None
            This function renders an interactive TUI and does not produce pipeline output.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-13
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges (to enable and read DNS Client log)
            Requires: Interactive console (not ISE or redirected output)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/etw/event-tracing-portal
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 30)]
        [int]$RefreshInterval = 1,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$DomainFilter = '',

        [Parameter(Mandatory = $false)]
        [ValidateRange(10, 500)]
        [int]$MaxLines = 50,

        [Parameter(Mandatory = $false)]
        [switch]$NoClear,

        [Parameter(Mandatory = $false)]
        [switch]$NoColor
    )

    begin {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ISE is not supported. Use Windows Terminal, ConHost, or a remote SSH session."
            return
        }
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"
    }

    process {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') { return }

        $dnsLogName = 'Microsoft-Windows-DNS-Client/Operational'

        # Ensure DNS Client log is enabled
        try {
            $log = Get-WinEvent -ListLog $dnsLogName -ErrorAction Stop
            if (-not $log.IsEnabled) {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Enabling DNS Client operational log"
                $log.IsEnabled = $true
                $log.SaveChanges()
            }
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Cannot access DNS Client log: $_. Run as Administrator."
            return
        }

        # DNS record type mapping
        $queryTypeMap = @{
            1 = 'A'; 2 = 'NS'; 5 = 'CNAME'; 6 = 'SOA'; 12 = 'PTR'
            15 = 'MX'; 16 = 'TXT'; 28 = 'AAAA'; 33 = 'SRV'
            64 = 'SVCB'; 65 = 'HTTPS'; 255 = 'ANY'
        }

        # ANSI setup
        $esc      = [char]27
        $useColor = -not $NoColor
        $bold   = if ($useColor) { "${esc}[1m" }  else { '' }
        $dim    = if ($useColor) { "${esc}[90m" } else { '' }
        $reset  = if ($useColor) { "${esc}[0m" }  else { '' }
        $cyan   = if ($useColor) { "${esc}[96m" } else { '' }
        $white  = if ($useColor) { "${esc}[97m" } else { '' }
        $green  = if ($useColor) { "${esc}[92m" } else { '' }
        $red    = if ($useColor) { "${esc}[91m" } else { '' }
        $yellow = if ($useColor) { "${esc}[93m" } else { '' }

        # State
        $eventBuffer    = [System.Collections.Generic.List[PSCustomObject]]::new()
        $lastEventTime  = (Get-Date)
        $running        = $true
        $paused         = $false
        $monitorStart   = Get-Date
        $totalQueries   = 0
        $currentFilter  = $DomainFilter
        $typeFilters    = @('ALL', 'A', 'AAAA', 'CNAME', 'MX', 'PTR', 'SRV', 'TXT')
        $typeIndex      = 0
        $currentType    = 'ALL'
        $sortModes      = @('Time', 'Domain', 'Type', 'Process')
        $sortIndex      = 0
        $sortMode       = 'Time'

        $previousCtrlC         = [Console]::TreatControlCAsInput
        $previousCursorVisible = [Console]::CursorVisible

        try {
            [Console]::TreatControlCAsInput = $true
            [Console]::CursorVisible        = $false
            [Console]::Clear()

            while ($running) {
                $frameStart = [Diagnostics.Stopwatch]::StartNew()

                # ---- Poll new DNS events ----
                if (-not $paused) {
                    try {
                        $filterHash = @{
                            LogName   = $dnsLogName
                            Id        = @(3008, 3020)
                            StartTime = $lastEventTime
                        }
                        $newEvents = @(Get-WinEvent -FilterHashtable $filterHash -MaxEvents 200 -ErrorAction SilentlyContinue)

                        if ($newEvents.Count -gt 0) {
                            $lastEventTime = $newEvents[0].TimeCreated.AddMilliseconds(1)

                            foreach ($evt in $newEvents) {
                                $xml = [xml]$evt.ToXml()
                                $eventData = @{}
                                foreach ($data in $xml.Event.EventData.Data) {
                                    $eventData[$data.Name] = $data.'#text'
                                }

                                $queryName = $eventData['QueryName']
                                if ([string]::IsNullOrWhiteSpace($queryName)) { continue }
                                $queryName = $queryName.TrimEnd('.')

                                $typeId   = if ($eventData['QueryType']) { [int]$eventData['QueryType'] } else { 0 }
                                $typeName = if ($queryTypeMap.ContainsKey($typeId)) { $queryTypeMap[$typeId] } else { "TYPE$typeId" }

                                $resultStr = if ($eventData['QueryResults']) {
                                    ($eventData['QueryResults'] -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) -join ', '
                                } else { '' }

                                $statusCode = if ($eventData['QueryStatus']) { [int]$eventData['QueryStatus'] } else { -1 }
                                $status = switch ($statusCode) {
                                    0       { 'OK' }
                                    9003    { 'NXDOMAIN' }
                                    9501    { 'TIMEOUT' }
                                    1460    { 'TIMEOUT' }
                                    default { if ($statusCode -gt 0) { "ERR$statusCode" } else { '?' } }
                                }

                                $processId = 0
                                $execNode = $xml.Event.System.Execution
                                if ($execNode -and $execNode.ProcessID) {
                                    $processId = [int]$execNode.ProcessID
                                }
                                $processName = ''
                                if ($processId -gt 0) {
                                    try {
                                        $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
                                        if ($proc) { $processName = $proc.ProcessName }
                                    } catch { }
                                }

                                $totalQueries++
                                $eventBuffer.Add([PSCustomObject]@{
                                    Time        = $evt.TimeCreated
                                    QueryName   = $queryName
                                    QueryType   = $typeName
                                    Result      = $resultStr
                                    Status      = $status
                                    ProcessName = $processName
                                    ProcessId   = $processId
                                })
                            }
                        }
                    }
                    catch { }

                    # Trim buffer
                    while ($eventBuffer.Count -gt 500) {
                        $eventBuffer.RemoveAt(0)
                    }
                }

                # ---- Apply filters ----
                $filtered = $eventBuffer
                if ($currentFilter -ne '') {
                    $filtered = @($filtered | Where-Object { $_.QueryName -like $currentFilter })
                }
                if ($currentType -ne 'ALL') {
                    $filtered = @($filtered | Where-Object { $_.QueryType -eq $currentType })
                }

                # ---- Sort ----
                $sorted = switch ($sortMode) {
                    'Time'    { $filtered | Sort-Object -Property Time -Descending }
                    'Domain'  { $filtered | Sort-Object -Property QueryName }
                    'Type'    { $filtered | Sort-Object -Property QueryType, QueryName }
                    'Process' { $filtered | Sort-Object -Property ProcessName, QueryName }
                }

                $displayItems = @($sorted | Select-Object -First $MaxLines)

                # ---- Build frame ----
                $fb = [System.Text.StringBuilder]::new(8192)
                $elapsed    = (Get-Date) - $monitorStart
                $elapsedStr = '{0:00}:{1:00}:{2:00}' -f [math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds

                $pauseLabel  = if ($paused) { " ${yellow}(PAUSED)${reset}" } else { '' }
                $filterLabel = if ($currentFilter -ne '') { " ${yellow}Filter: $currentFilter${reset}" } else { '' }
                $typeLabel   = if ($currentType -ne 'ALL') { " ${yellow}Type: $currentType${reset}" } else { '' }

                [void]$fb.AppendLine("${bold}${cyan}=== DNS QUERY MONITOR ===${reset}${pauseLabel}    ${dim}Elapsed: ${elapsedStr}  |  Queries: ${totalQueries}${reset}")
                [void]$fb.AppendLine("${filterLabel}${typeLabel}")

                # Column headers
                $hTime    = if ($sortMode -eq 'Time')    { "${cyan}${bold}" } else { $bold }
                $hDomain  = if ($sortMode -eq 'Domain')  { "${cyan}${bold}" } else { $bold }
                $hType    = if ($sortMode -eq 'Type')    { "${cyan}${bold}" } else { $bold }
                $hProcess = if ($sortMode -eq 'Process') { "${cyan}${bold}" } else { $bold }
                $header = "  ${hTime}$('TIME'.PadRight(12))${reset} ${hType}$('TYPE'.PadRight(6))${reset} ${bold}$('STATUS'.PadRight(10))${reset} ${hProcess}$('PROCESS'.PadRight(18))${reset} ${hDomain}DOMAIN / RESULT${reset}"
                [void]$fb.AppendLine($header)
                [void]$fb.AppendLine("  ${dim}$('-' * 12) $('-' * 6) $('-' * 10) $('-' * 18) $('-' * 40)${reset}")

                # Rows
                foreach ($item in $displayItems) {
                    $timeStr     = $item.Time.ToString('HH:mm:ss.ff')
                    $typeStr     = $item.QueryType.PadRight(6)
                    $processStr  = if ($item.ProcessName) { $item.ProcessName.PadRight(18) } else { "PID:$($item.ProcessId)".PadRight(18) }

                    $statusColor = switch ($item.Status) {
                        'OK'       { $green }
                        'NXDOMAIN' { $red }
                        'TIMEOUT'  { $yellow }
                        default    { $red }
                    }
                    if ($item.Status -eq '?') { $statusColor = $dim }
                    $statusStr = "$statusColor$($item.Status.PadRight(10))${reset}"

                    $resultLine = if ($item.Result -and $item.Result.Length -gt 0) {
                        " ${dim}-> $($item.Result)${reset}"
                    } else { '' }

                    $row = "  ${white}${timeStr}${reset} ${cyan}${typeStr}${reset} ${statusStr} ${dim}${processStr}${reset} ${white}$($item.QueryName)${reset}${resultLine}"
                    [void]$fb.AppendLine($row)
                }

                # Footer
                [void]$fb.AppendLine('')
                [void]$fb.AppendLine("  ${dim}Showing $($displayItems.Count) / $($filtered.Count) events (buffer: $($eventBuffer.Count))${reset}")
                [void]$fb.AppendLine("  ${bold}[${cyan}Q${reset}${bold}]${reset}uit  ${bold}[${cyan}S${reset}${bold}]${reset}ort  ${bold}[${cyan}C${reset}${bold}]${reset}lear  ${bold}[${cyan}P${reset}${bold}]${reset}ause  ${bold}[${cyan}F${reset}${bold}]${reset}ilter  ${bold}[${cyan}T${reset}${bold}]${reset}ype  ${dim}|${reset}  Sort: ${yellow}${sortMode}${reset}  ${dim}|${reset}  Type: ${yellow}${currentType}${reset}")

                # Erase trailing lines
                $height = [math]::Max(24, [Console]::WindowHeight)
                $currentLines = $fb.ToString().Split("`n").Count
                for ($r = $currentLines; $r -lt $height; $r++) {
                    [void]$fb.AppendLine("${esc}[2K")
                }

                [Console]::SetCursorPosition(0, 0)
                [Console]::Write($fb.ToString())
                $frameStart.Stop()

                # ---- Input handling ----
                $sleepMs    = [math]::Max(100, ($RefreshInterval * 1000) - $frameStart.ElapsedMilliseconds)
                $inputTimer = [Diagnostics.Stopwatch]::StartNew()

                while ($inputTimer.ElapsedMilliseconds -lt $sleepMs) {
                    if ([Console]::KeyAvailable) {
                        $keyInfo = [Console]::ReadKey($true)

                        if (($keyInfo.Key -eq 'C') -and (($keyInfo.Modifiers -band [ConsoleModifiers]::Control) -eq [ConsoleModifiers]::Control)) {
                            $running = $false
                            break
                        }

                        switch ($keyInfo.Key) {
                            'Q'      { $running = $false }
                            'Escape' { $running = $false }
                            'S'      { $sortIndex = ($sortIndex + 1) % $sortModes.Count; $sortMode = $sortModes[$sortIndex] }
                            'T'      { $typeIndex = ($typeIndex + 1) % $typeFilters.Count; $currentType = $typeFilters[$typeIndex] }
                            'C'      { $eventBuffer.Clear(); $totalQueries = 0; $monitorStart = Get-Date }
                            'P'      { $paused = -not $paused }
                            'F'      {
                                # Inline filter input
                                [Console]::CursorVisible = $true
                                [Console]::SetCursorPosition(0, 1)
                                [Console]::Write("${esc}[2K  ${bold}Domain filter (blank=all): ${reset}")
                                $input = [Console]::ReadLine()
                                $currentFilter = if ($null -eq $input -or $input.Trim() -eq '') { '' } else { $input.Trim() }
                                [Console]::CursorVisible = $false
                            }
                        }
                        if (-not $running) { break }
                    }
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        finally {
            [Console]::CursorVisible        = $previousCursorVisible
            [Console]::TreatControlCAsInput = $previousCtrlC
            if (-not $NoClear) { [Console]::Clear() }
            Write-Information -MessageData 'DNS Query Monitor stopped.' -InformationAction Continue
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}