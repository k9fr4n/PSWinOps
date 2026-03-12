#Requires -Version 5.1

function Test-NTPSync {
    <#
    .SYNOPSIS
        Tests NTP synchronization status on Windows machines
    .DESCRIPTION
        Queries the Windows Time Service (w32tm) to determine whether NTP
        synchronization is healthy on one or more machines. Parses the output
        of 'w32tm /query /status' to extract source, stratum, phase offset,
        last sync time, leap indicator, and poll interval.

        Supports both English and French locale w32tm output via locale-agnostic
        regex patterns. Uses Invoke-Command for both local and remote execution,
        enabling uniform testability and consistent error handling across targets.
    .PARAMETER ComputerName
        One or more computer names to test. Accepts pipeline input by value and
        by property name. Defaults to the local machine ($env:COMPUTERNAME).
    .PARAMETER MaxOffsetMs
        Maximum acceptable time offset in milliseconds. If the absolute parsed
        offset exceeds this value, IsSynced is set to $false. Must be at least 1.
        Defaults to 1000.
    .EXAMPLE
        Test-NTPSync

        Tests NTP sync status on the local machine with the default 1000ms threshold.
    .EXAMPLE
        Test-NTPSync -ComputerName 'DC01' -MaxOffsetMs 500

        Tests NTP sync on remote server DC01 with a 500ms offset threshold.
    .EXAMPLE
        'DC01', 'DC02', 'WEB01' | Test-NTPSync -MaxOffsetMs 2000

        Pipeline example: tests NTP sync on multiple machines with a 2-second threshold.
    .NOTES
        Author:        Ecritel IT Team
        Version:       1.0.0
        Last Modified: 2026-03-12
        Requires:      PowerShell 5.1+ / Windows only
        Permissions:   Admin rights required for remote queries (WinRM access)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 2147483647)]
        [int]$MaxOffsetMs = 1000
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        # ScriptBlock executed on each target via Invoke-Command
        $w32tmScriptBlock = {
            $w32tmExe = Join-Path -Path $env:SystemRoot -ChildPath 'System32\w32tm.exe'
            if (-not (Test-Path -Path $w32tmExe)) {
                throw "[ERROR] w32tm.exe not found at '$w32tmExe'"
            }
            $w32tmOutput = & $w32tmExe /query /status 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "[ERROR] w32tm exited with code $LASTEXITCODE : $($w32tmOutput -join ' ')"
            }
            $w32tmOutput
        }

        # Locale-agnostic regex patterns (EN + FR)
        $rxSource = '(?i)^Source\s*:\s*(.+)$'
        $rxStratum = '(?i)(?:Stratum|Strate)\s*:\s*(\d+)'
        $rxLeap = '(?i)(?:Leap Indicator|Indicateur de saut)\s*:\s*(.+)$'
        $rxLastSync = '(?i)(?:Last Successful Sync Time|Heure de la derni.re synchronisation r.ussie)\s*:\s*(.+)$'
        $rxPoll = '(?i)(?:Poll Interval|Intervalle d.interrogation)\s*:\s*(\d+)'
        $rxOffset = '(?i)(?:Phase Offset|D.calage de phase|Offset)\s*:\s*([+-]?\d+[\.,]\d+)s'

        # Sources indicating the clock is NOT synced to an external reference
        $unsyncedSourcePatterns = @(
            'Free-Running System Clock'
            'Local CMOS Clock'
            'Horloge .* roue libre'
        )
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Querying NTP status on '$targetComputer'"

            try {
                # Determine if target is the local machine
                $isLocal = ($targetComputer -eq $env:COMPUTERNAME) -or
                ($targetComputer -eq 'localhost') -or
                ($targetComputer -eq '.')

                if ($isLocal) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Local execution (no -ComputerName)"
                    $rawOutput = Invoke-Command -ScriptBlock $w32tmScriptBlock
                } else {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Remote execution on '$targetComputer'"
                    $rawOutput = Invoke-Command -ComputerName $targetComputer -ScriptBlock $w32tmScriptBlock
                }

                # Normalize output to trimmed string array
                $lines = @($rawOutput | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })

                # --- Parse Source ---
                $sourceValue = 'Unknown'
                foreach ($outputLine in $lines) {
                    if ($outputLine -match $rxSource) {
                        $sourceValue = $Matches[1].Trim()
                        break
                    }
                }

                # --- Parse Stratum ---
                $stratumValue = 0
                foreach ($outputLine in $lines) {
                    if ($outputLine -match $rxStratum) {
                        $stratumValue = [int]$Matches[1]
                        break
                    }
                }

                # --- Parse Leap Indicator ---
                $leapValue = 'Unknown'
                foreach ($outputLine in $lines) {
                    if ($outputLine -match $rxLeap) {
                        $leapValue = $Matches[1].Trim()
                        break
                    }
                }

                # --- Parse Last Successful Sync Time ---
                $lastSyncValue = $null
                foreach ($outputLine in $lines) {
                    if ($outputLine -match $rxLastSync) {
                        $rawSyncTime = $Matches[1].Trim()
                        try {
                            $lastSyncValue = [datetime]::Parse($rawSyncTime)
                        } catch {
                            Write-Verbose "[$($MyInvocation.MyCommand)] Could not parse sync time: '$rawSyncTime'"
                        }
                        break
                    }
                }

                # --- Parse Poll Interval ---
                $pollValue = $null
                foreach ($outputLine in $lines) {
                    if ($outputLine -match $rxPoll) {
                        $pollValue = [int]$Matches[1]
                        break
                    }
                }

                # --- Parse Phase Offset (seconds -> milliseconds) ---
                $offsetMs = 0.0
                foreach ($outputLine in $lines) {
                    if ($outputLine -match $rxOffset) {
                        $offsetNumeric = $Matches[1] -replace ',', '.'
                        $offsetMs = [math]::Abs([double]$offsetNumeric) * 1000.0
                        break
                    }
                }

                # --- Determine IsSynced ---
                $isUnsyncedSource = $false
                foreach ($srcPattern in $unsyncedSourcePatterns) {
                    if ($sourceValue -match $srcPattern) {
                        $isUnsyncedSource = $true
                        break
                    }
                }

                $isSynced = (-not $isUnsyncedSource) -and ($offsetMs -le $MaxOffsetMs)

                # --- Emit result object ---
                [PSCustomObject]@{
                    PSTypeName    = 'PSWinOps.NTPSyncStatus'
                    ComputerName  = $targetComputer
                    IsSynced      = $isSynced
                    Source        = $sourceValue
                    Stratum       = $stratumValue
                    OffsetMs      = [math]::Round($offsetMs, 4)
                    MaxOffsetMs   = $MaxOffsetMs
                    LastSyncTime  = $lastSyncValue
                    LeapIndicator = $leapValue
                    PollInterval  = $pollValue
                    Timestamp     = (Get-Date -Format 'o')
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] '$targetComputer' - Synced: $isSynced, Source: $sourceValue, Offset: ${offsetMs}ms"
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query NTP status on '${targetComputer}': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
