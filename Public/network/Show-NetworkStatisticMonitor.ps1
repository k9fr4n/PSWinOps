#Requires -Version 5.1

function Show-NetworkStatisticMonitor {
    <#
        .SYNOPSIS
            Interactive real-time monitor for TCP/UDP network connections

        .DESCRIPTION
            Renders a full-screen terminal UI showing active network connections with
            ANSI-colored protocol and state indicators, sortable columns, and interactive
            keyboard controls. Internally calls Get-NetworkConnection at each refresh
            interval and builds the display frame via StringBuilder for flicker-free
            rendering. Press Q to quit, S to cycle sort column, R to reverse sort order,
            or P to pause/resume data collection.

        .PARAMETER ComputerName
            One or more computer names to monitor. Accepts pipeline input by value and
            by property name. Defaults to the local machine ($env:COMPUTERNAME).

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote machines via WinRM.
            Ignored for local machine queries.

        .PARAMETER Protocol
            Filter by protocol. Valid values: TCP, UDP. By default both are shown.

        .PARAMETER State
            Filter TCP connections by state (e.g. Established, Listen, TimeWait).
            Ignored for UDP endpoints (UDP is stateless).

        .PARAMETER LocalAddress
            Filter by local IP address. Supports wildcards.

        .PARAMETER LocalPort
            Filter by local port number.

        .PARAMETER RemoteAddress
            Filter by remote IP address. Supports wildcards.

        .PARAMETER RemotePort
            Filter by remote port number.

        .PARAMETER ProcessName
            Filter by owning process name. Supports wildcards.

        .PARAMETER RefreshInterval
            Refresh interval in seconds. Default: 2. Valid range: 1-300 seconds.

        .PARAMETER NoClear
            Suppresses the console clear on exit so the final frame remains visible
            in the scrollback buffer.

        .PARAMETER NoColor
            Disables ANSI color output for terminals that do not support escape sequences.

        .EXAMPLE
            Show-NetworkStatisticMonitor

            Starts real-time monitoring of all network connections on the local machine.
            Press Q to quit, S to cycle sort, R to reverse, P to pause.

        .EXAMPLE
            Show-NetworkStatisticMonitor -Protocol TCP -State Established -RefreshInterval 5

            Monitors only established TCP connections with a 5-second refresh interval.

        .EXAMPLE
            'SRV01', 'SRV02' | Show-NetworkStatisticMonitor -Protocol TCP -NoColor

            Monitors TCP connections on two remote servers without ANSI colors.

        .OUTPUTS
            None
            This function renders an interactive TUI and does not produce pipeline output.

        .NOTES
            Author: Franck SALLET
            Version: 2.0.0
            Last Modified: 2026-04-11
            Requires: PowerShell 5.1+ / Windows only
            Requires: Interactive console (not ISE or redirected output)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-nettcpconnection
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateSet('TCP', 'UDP')]
        [string[]]$Protocol = @('TCP', 'UDP'),

        [Parameter(Mandatory = $false)]
        [ValidateSet('Bound', 'Closed', 'CloseWait', 'Closing', 'DeleteTCB',
            'Established', 'FinWait1', 'FinWait2', 'LastAck', 'Listen',
            'SynReceived', 'SynSent', 'TimeWait')]
        [string[]]$State,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$LocalAddress,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$LocalPort,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$RemoteAddress,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$RemotePort,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$ProcessName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$RefreshInterval = 2,

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

        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network statistics monitor"

        $allComputers = [System.Collections.Generic.List[string]]::new()

        $getStatParams = @{}
        if ($PSBoundParameters.ContainsKey('Credential'))    { $getStatParams['Credential']    = $Credential }
        if ($PSBoundParameters.ContainsKey('Protocol'))      { $getStatParams['Protocol']      = $Protocol }
        if ($PSBoundParameters.ContainsKey('State'))         { $getStatParams['State']         = $State }
        if ($PSBoundParameters.ContainsKey('LocalAddress'))  { $getStatParams['LocalAddress']  = $LocalAddress }
        if ($PSBoundParameters.ContainsKey('LocalPort'))     { $getStatParams['LocalPort']     = $LocalPort }
        if ($PSBoundParameters.ContainsKey('RemoteAddress')) { $getStatParams['RemoteAddress'] = $RemoteAddress }
        if ($PSBoundParameters.ContainsKey('RemotePort'))    { $getStatParams['RemotePort']    = $RemotePort }
        if ($PSBoundParameters.ContainsKey('ProcessName'))   { $getStatParams['ProcessName']   = $ProcessName }

        # ---- ANSI helpers ----
        $esc      = [char]27
        $useColor = -not $NoColor

        $dim       = if ($useColor) { "${esc}[90m" }  else { '' }
        $reset     = if ($useColor) { "${esc}[0m" }   else { '' }
        $bold      = if ($useColor) { "${esc}[1m" }   else { '' }
        $cyan      = if ($useColor) { "${esc}[96m" }  else { '' }
        $white     = if ($useColor) { "${esc}[97m" }  else { '' }
        $yellow    = if ($useColor) { "${esc}[93m" }  else { '' }
        $green     = if ($useColor) { "${esc}[92m" }  else { '' }
        $red       = if ($useColor) { "${esc}[91m" }  else { '' }
        $underline = if ($useColor) { "${esc}[4m" }   else { '' }

        function Get-VisualWidth {
            param([string]$Text)
            ($Text -replace "$([char]27)\[\d+(?:;\d+)*m", '').Length
        }

        function ConvertTo-PaddedLine {
            param([string]$Text, [int]$TargetWidth)
            $visual = Get-VisualWidth -Text $Text
            $needed = $TargetWidth - $visual
            if ($needed -gt 0) { return $Text + [string]::new(' ', $needed) }
            return $Text
        }

        function Get-ProtocolColor {
            param([string]$Proto)
            if (-not $script:useColor) { return '' }
            if ($Proto -eq 'TCP') { return $script:cyan }
            if ($Proto -eq 'UDP') { return $script:yellow }
            return ''
        }

        function Get-StateColor {
            param([string]$ConnState)
            if (-not $script:useColor) { return '' }
            switch ($ConnState) {
                'Established' { return $script:green }
                'Listen'      { return "$($script:white)$($script:bold)" }
                'TimeWait'    { return $script:dim }
                'CloseWait'   { return $script:red }
                'Closing'     { return $script:red }
                'LastAck'     { return $script:red }
                default       { return '' }
            }
        }

        $sortModes     = @('Process', 'Protocol', 'State', 'LocalPort', 'RemoteAddr')
        $sortModeIndex = 0
        $sortDescending = $false
        $paused  = $false
        $running = $true
        $lastResults = @()
    }

    process {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') { return }
        foreach ($computer in $ComputerName) {
            $allComputers.Add($computer)
        }
    }

    end {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') { return }

        $previousCtrlC         = [Console]::TreatControlCAsInput
        $previousCursorVisible = [Console]::CursorVisible

        try {
            [Console]::TreatControlCAsInput = $true
            [Console]::CursorVisible        = $false
            [Console]::Clear()

            while ($running) {
                $frameStart = [Diagnostics.Stopwatch]::StartNew()
                $currentSortMode = $sortModes[$sortModeIndex]

                # ---- Data gathering (skip when paused) ----
                if (-not $paused) {
                    $lastResults = @(Get-NetworkConnection -ComputerName $allComputers.ToArray() @getStatParams -ErrorAction SilentlyContinue)
                }

                $connectionCount = $lastResults.Count
                $width  = [math]::Max(80, [Console]::WindowWidth)
                $height = [math]::Max(24, [Console]::WindowHeight)
                $computerList = $allComputers -join ', '

                # ---- Sort data ----
                $sortProperty = switch ($currentSortMode) {
                    'Process'    { 'ProcessName' }
                    'Protocol'   { 'Protocol' }
                    'State'      { 'State' }
                    'LocalPort'  { 'LocalPort' }
                    'RemoteAddr' { 'RemoteAddress' }
                }
                $sortedResults = if ($connectionCount -gt 0) {
                    $lastResults | Sort-Object -Property $sortProperty -Descending:$sortDescending
                } else { @() }

                # ---- Build frame ----
                $frame = [System.Text.StringBuilder]::new(4096)
                $lineCount  = 0
                $separator  = [string]::new('-', [math]::Min($width - 4, 120))

                # Header
                $timeStr = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $pauseIndicator = if ($paused) { " ${red}${bold}(PAUSED)${reset}" } else { '' }
                $headerLine = "  ${bold}${cyan}Network Monitor${reset} ${dim}-${reset} ${bold}${white}${computerList}${reset}${pauseIndicator} ${dim}|${reset} ${dim}${timeStr}${reset}"
                [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $headerLine -TargetWidth $width))
                $lineCount++
                [void]$frame.AppendLine((ConvertTo-PaddedLine -Text "  ${dim}${separator}${reset}" -TargetWidth $width))
                $lineCount++

                # Column widths
                $colProto = 7;  $colLAddr = 23; $colLPort = 12
                $colRAddr = 23; $colRPort = 13; $colState = 14; $colProc = 20

                # Sort direction arrow
                $sortArrow = if ($sortDescending) {
                    if ($useColor) { "${cyan}v${reset}" } else { 'v' }
                } else {
                    if ($useColor) { "${cyan}^${reset}" } else { '^' }
                }

                # Table header with active sort highlighted
                $protoH = if ($currentSortMode -eq 'Protocol')   { "${cyan}${underline}PROTO${reset}" }          else { "${dim}PROTO${reset}" }
                $lAddrH = "${dim}LOCAL ADDRESS${reset}"
                $lPortH = if ($currentSortMode -eq 'LocalPort')  { "${cyan}${underline}LOCAL PORT${reset}" }     else { "${dim}LOCAL PORT${reset}" }
                $rAddrH = if ($currentSortMode -eq 'RemoteAddr') { "${cyan}${underline}REMOTE ADDRESS${reset}" } else { "${dim}REMOTE ADDRESS${reset}" }
                $rPortH = "${dim}REMOTE PORT${reset}"
                $stateH = if ($currentSortMode -eq 'State')      { "${cyan}${underline}STATE${reset}" }          else { "${dim}STATE${reset}" }
                $procH  = if ($currentSortMode -eq 'Process')    { "${cyan}${underline}PROCESS${reset}" }        else { "${dim}PROCESS${reset}" }

                $headerRow = '  {0}{1}{2}{3}{4}{5}{6}' -f `
                    (ConvertTo-PaddedLine -Text $protoH  -TargetWidth $colProto),
                    (ConvertTo-PaddedLine -Text $lAddrH  -TargetWidth $colLAddr),
                    (ConvertTo-PaddedLine -Text $lPortH  -TargetWidth $colLPort),
                    (ConvertTo-PaddedLine -Text $rAddrH  -TargetWidth $colRAddr),
                    (ConvertTo-PaddedLine -Text $rPortH  -TargetWidth $colRPort),
                    (ConvertTo-PaddedLine -Text $stateH  -TargetWidth $colState),
                    $procH
                [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $headerRow -TargetWidth $width))
                $lineCount++

                $dashRow = "  ${dim}{0}{1}{2}{3}{4}{5}{6}${reset}" -f `
                    ('{0,-7}'  -f '-----'),
                    ('{0,-23}' -f '-------------'),
                    ('{0,-12}' -f '----------'),
                    ('{0,-23}' -f '--------------'),
                    ('{0,-13}' -f '-----------'),
                    ('{0,-14}' -f '-----'),
                    '-------'
                [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $dashRow -TargetWidth $width))
                $lineCount++

                # Data rows
                $availableRows = $height - $lineCount - 4
                if ($connectionCount -gt 0) {
                    $displayCount = [math]::Min($sortedResults.Count, [math]::Max(5, $availableRows))
                    for ($i = 0; $i -lt $displayCount; $i++) {
                        $conn = $sortedResults[$i]
                        $protoColor = Get-ProtocolColor -Proto $conn.Protocol
                        $stateColor = Get-StateColor -ConnState $conn.State

                        $dataRow = '  {0}  {1}  {2}  {3}  {4}  {5}  {6}' -f `
                            "${protoColor}$('{0,-5}' -f $conn.Protocol)${reset}",
                            ('{0,-21}' -f $conn.LocalAddress),
                            ('{0,-10}' -f $conn.LocalPort),
                            ('{0,-21}' -f $conn.RemoteAddress),
                            ('{0,-11}' -f $conn.RemotePort),
                            "${stateColor}$('{0,-12}' -f $conn.State)${reset}",
                            "${white}$($conn.ProcessName)${reset}"

                        [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $dataRow -TargetWidth $width))
                        $lineCount++
                    }
                }
                else {
                    [void]$frame.AppendLine((ConvertTo-PaddedLine -Text "  ${yellow}(No matching connections found)${reset}" -TargetWidth $width))
                    $lineCount++
                }

                # Footer
                [void]$frame.AppendLine('')
                $lineCount++
                [void]$frame.AppendLine((ConvertTo-PaddedLine -Text "  ${dim}${separator}${reset}" -TargetWidth $width))
                $lineCount++

                $footerLine = "  ${bold}[${cyan}Q${reset}${bold}]${reset}uit  ${bold}[${cyan}S${reset}${bold}]${reset}ort  ${bold}[${cyan}R${reset}${bold}]${reset}everse  ${bold}[${cyan}P${reset}${bold}]${reset}ause  ${dim}|${reset}  Refresh: ${yellow}${RefreshInterval}s${reset}  ${dim}|${reset}  Sort: ${cyan}${bold}${currentSortMode}${reset} ${sortArrow}  ${dim}|${reset}  Connections: ${white}${connectionCount}${reset}"
                [void]$frame.AppendLine((ConvertTo-PaddedLine -Text $footerLine -TargetWidth $width))
                $lineCount++

                # Erase trailing lines
                $remainingRows = $height - $lineCount
                for ($r = 0; $r -lt $remainingRows; $r++) {
                    [void]$frame.AppendLine("${esc}[2K")
                }

                # Single write
                [Console]::SetCursorPosition(0, 0)
                [Console]::Write($frame.ToString())
                $frameStart.Stop()

                # ---- Input handling ----
                $sleepMs    = [math]::Max(100, ($RefreshInterval * 1000) - $frameStart.ElapsedMilliseconds)
                $inputTimer = [Diagnostics.Stopwatch]::StartNew()

                while ($inputTimer.ElapsedMilliseconds -lt $sleepMs) {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)

                        # Ctrl+C always wins
                        if ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                            $running = $false
                            break
                        }

                        if     ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') { $running = $false }
                        elseif ($key.Key -eq 'S') { $sortModeIndex = ($sortModeIndex + 1) % $sortModes.Count }
                        elseif ($key.Key -eq 'P') { $paused = -not $paused }
                        elseif ($key.Key -eq 'R') { $sortDescending = -not $sortDescending }

                        if (-not $running) { break }
                    }
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        finally {
            [Console]::CursorVisible        = $previousCursorVisible
            [Console]::TreatControlCAsInput = $previousCtrlC
            if (-not $NoClear) {
                [Console]::Clear()
            }
            Write-Information -MessageData 'Network Statistics Monitor stopped.' -InformationAction Continue
        }
    }
}
