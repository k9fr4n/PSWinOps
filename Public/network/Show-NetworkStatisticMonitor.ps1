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
                $timeStr      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $frameContent = Format-NetworkStatisticMonitorFrame `
                    -SortedConnections $sortedResults `
                    -ComputerList      $computerList `
                    -CurrentSortMode   $currentSortMode `
                    -SortDescending    $sortDescending `
                    -Paused            $paused `
                    -TimeStr           $timeStr `
                    -Width             $width `
                    -Height            $height `
                    -RefreshInterval   $RefreshInterval `
                    -NoColor:$NoColor

                [Console]::SetCursorPosition(0, 0)
                [Console]::Write($frameContent)
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
