#Requires -Version 5.1

function Get-NTPPeer {
    <#
        .SYNOPSIS
            Retrieves NTP peer information from the Windows Time service

        .DESCRIPTION
            Parses the output of 'w32tm /query /peers' to return structured NTP peer objects.
            Supports both modern and legacy w32tm output formats, including French-locale output.
            Uses block-based parsing: raw output is split on blank lines, the header block is
            skipped, and each subsequent block is parsed as one peer entry.

            Note: LastSyncTime is not available from /query /peers. Use Get-NTPConfiguration
            (which queries /query /status) for last synchronization information.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.

        .EXAMPLE
            Get-NTPPeer
            Returns NTP peer information for the local computer.

        .EXAMPLE
            Get-NTPPeer -ComputerName 'SRV01', 'SRV02'
            Returns NTP peer information for two remote servers.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-NTPPeer
            Pipeline usage: queries NTP peers on both servers.

        .OUTPUTS
            PSWinOps.NtpPeer
            NTP peer status including stratum, delay, and offset.

        .NOTES
            Author: Franck SALLET
            Version: 1.2.0
            Last Modified: 2026-03-20
            Requires: PowerShell 5.1+, Windows Time service (w32time)
            Permissions: Local user for local queries; remote admin for Invoke-Command remoting

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.NtpPeer')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting"

        # Script block used for REMOTE execution only (Invoke-Command).
        # Uses full path to w32tm.exe because remote sessions don't inherit local mock context.
        $w32tmRemoteScriptBlock = {
            $w32tmPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\w32tm.exe'
            if (-not (Test-Path -Path $w32tmPath)) {
                throw "w32tm.exe not found at '$w32tmPath'"
            }
            $peerOutput = & $w32tmPath /query /peers 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "w32tm /query /peers failed (exit code $LASTEXITCODE): $($peerOutput -join ' ')"
            }
            $peerOutput
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Querying '$targetComputer'"

            try {
                $isLocal = ($targetComputer -eq $env:COMPUTERNAME) -or
                ($targetComputer -eq 'localhost') -or
                ($targetComputer -eq '.')

                if ($isLocal) {
                    # Local execution: call by bare name so Pester can mock it
                    $rawOutput = w32tm /query /peers 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "w32tm /query /peers failed (exit code $LASTEXITCODE): $($rawOutput -join ' ')"
                    }
                } else {
                    $rawOutput = Invoke-Command -ComputerName $targetComputer `
                        -ScriptBlock $w32tmRemoteScriptBlock -ErrorAction Stop
                }

                # Convert to string array and normalize
                $lines = @($rawOutput | ForEach-Object { "$_" })

                # Split into blocks on blank lines
                $blocks = [System.Collections.Generic.List[System.Collections.Generic.List[string]]]::new()
                $currentBlock = [System.Collections.Generic.List[string]]::new()

                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) {
                        if ($currentBlock.Count -gt 0) {
                            $blocks.Add($currentBlock)
                            $currentBlock = [System.Collections.Generic.List[string]]::new()
                        }
                    } else {
                        $currentBlock.Add($line.Trim())
                    }
                }
                if ($currentBlock.Count -gt 0) {
                    $blocks.Add($currentBlock)
                }

                # First block is the header (#Peers: N) -- skip it
                if ($blocks.Count -le 1) {
                    Write-Warning "[$($MyInvocation.MyCommand)] No NTP peers found on '$targetComputer'"
                    continue
                }

                $peerBlocks = $blocks.GetRange(1, $blocks.Count - 1)

                foreach ($peerBlock in $peerBlocks) {
                    # First line is the Peer line
                    $peerLine = $peerBlock[0]
                    $peerName = $null
                    $peerFlags = $null

                    if ($peerLine -match '^Peer:\s*(.+)$') {
                        $peerValue = $Matches[1].Trim()
                        if ($peerValue -match '^(.+?),\s*(.+)$') {
                            $peerName = $Matches[1].Trim()
                            $peerFlags = $Matches[2].Trim()
                        } else {
                            $peerName = $peerValue
                        }
                    }

                    # Parse remaining lines as key:value
                    $peerState = $null
                    $timeRemaining = [double]0
                    $peerMode = $null
                    $peerStratum = $null
                    $peerPollInterval = $null
                    $hostPollInterval = $null

                    for ($i = 1; $i -lt $peerBlock.Count; $i++) {
                        $kvLine = $peerBlock[$i]
                        $label = ''
                        $kvValue = ''

                        if ($kvLine -match '^([^:]+):\s*(.*)$') {
                            $label = $Matches[1].Trim()
                            $kvValue = $Matches[2].Trim()
                        }

                        # State
                        if ($label -match 'State|tat') {
                            $peerState = $kvValue
                        }
                        # Time Remaining / Temps restant
                        elseif ($label -match 'Time Remaining|restant') {
                            if ($kvValue -match '([\d,\.]+)\s*s') {
                                $numStr = $Matches[1] -replace ',', '.'
                                $timeRemaining = [double]$numStr
                            }
                        }
                        # Mode
                        elseif ($label -match '^Mode') {
                            $peerMode = $kvValue
                        }
                        # Stratum
                        elseif ($label -match 'Strat') {
                            $peerStratum = $kvValue
                        }
                        # PeerPoll Interval
                        elseif ($label -match 'PeerPoll') {
                            if ($kvValue -match '(\d+)') {
                                $peerPollInterval = [int]$Matches[1]
                            }
                        }
                        # HostPoll Interval
                        elseif ($label -match 'HostPoll') {
                            if ($kvValue -match '(\d+)') {
                                $hostPollInterval = [int]$Matches[1]
                            }
                        }
                    }

                    [PSCustomObject]@{
                        PSTypeName       = 'PSWinOps.NtpPeer'
                        ComputerName     = $targetComputer
                        PeerName         = $peerName
                        PeerFlags        = $peerFlags
                        State            = $peerState
                        TimeRemaining    = $timeRemaining
                        Mode             = $peerMode
                        Stratum          = $peerStratum
                        PeerPollInterval = $peerPollInterval
                        HostPollInterval = $hostPollInterval
                        Timestamp        = Get-Date -Format 'o'
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query '$targetComputer': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
