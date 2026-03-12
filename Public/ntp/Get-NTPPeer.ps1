#Requires -Version 5.1

function Get-NTPPeer {
    <#
    .SYNOPSIS
        Lists configured NTP peers on one or more Windows machines

    .DESCRIPTION
        Queries the Windows Time Service using w32tm /query /peers on local or remote
        machines and returns structured objects for each configured NTP peer. Supports
        both English and French locale output from w32tm by using locale-agnostic
        value-pattern-based parsing (no locale-specific label matching).

        Accepts pipeline input for ComputerName, enabling bulk queries across a fleet.
        Each machine is queried independently with per-machine error isolation: if one
        machine fails, the function continues to the next and writes a non-terminating
        error for the failed machine.

        Uses Invoke-Command for both local and remote execution to provide a uniform
        code path and simplify testability.

    .PARAMETER ComputerName
        One or more computer names to query. Accepts pipeline input. Defaults to the
        local machine ($env:COMPUTERNAME). Values 'localhost' and '.' are treated as
        local. Must be a non-empty string or array of non-empty strings.

    .EXAMPLE
        Get-NTPPeer

        Lists all NTP peers configured on the local machine.

    .EXAMPLE
        Get-NTPPeer -ComputerName 'SRV-DC01' -Verbose

        Queries NTP peers on a remote server with verbose logging enabled.

    .EXAMPLE
        'SRV-DC01', 'SRV-DC02', 'SRV-WEB01' | Get-NTPPeer | Format-Table -AutoSize

        Queries NTP peers on multiple machines via pipeline and formats as a table.

    .NOTES
        Author:        Franck SALLET (k9fr4n)
        Version:       1.0.0
        Last Modified: 2026-03-12
        Requires:      PowerShell 5.1+ / Windows only
        Permissions:   Standard user for local queries; remote queries require
                       WinRM access to the target machine
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        $w32tmScriptBlock = {
            $w32tmPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\w32tm.exe'
            if (-not (Test-Path -Path $w32tmPath)) {
                throw "[ERROR] w32tm.exe not found at '$w32tmPath'"
            }
            $peerOutput = & $w32tmPath /query /peers 2>&1
            if ($LASTEXITCODE -ne 0) {
                $outputText = $peerOutput -join ' '
                throw "[ERROR] w32tm /query /peers failed with exit code ${LASTEXITCODE}: $outputText"
            }
            $peerOutput
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Querying NTP peers on '$targetComputer'"

            try {
                $isLocal = ($targetComputer -eq $env:COMPUTERNAME) -or
                ($targetComputer -eq 'localhost') -or
                ($targetComputer -eq '.')

                if ($isLocal) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Executing locally (no -ComputerName)"
                    $rawOutput = Invoke-Command -ScriptBlock $w32tmScriptBlock -ErrorAction Stop
                } else {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Executing remotely on '$targetComputer'"
                    $rawOutput = Invoke-Command -ComputerName $targetComputer -ScriptBlock $w32tmScriptBlock -ErrorAction Stop
                }

                if (-not $rawOutput) {
                    Write-Warning "[$($MyInvocation.MyCommand)] No output from w32tm on '$targetComputer'"
                    continue
                }

                # --- Parse peer count from header line (#Peers: N / #Homologues : N) ---
                $peerCount = 0
                foreach ($headerLine in $rawOutput) {
                    $headerText = $headerLine.ToString().Trim()
                    if ($headerText -match '^\s*#\w+') {
                        if ($headerText -match ':\s*(\d+)') {
                            $peerCount = [int]$Matches[1]
                        }
                        break
                    }
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Reported $peerCount peer(s) on '$targetComputer'"

                if ($peerCount -eq 0) {
                    Write-Warning "[$($MyInvocation.MyCommand)] No NTP peers configured on '$targetComputer'"
                    continue
                }

                # --- Parse peer blocks using locale-agnostic value patterns ---
                $peerBlocks = [System.Collections.Generic.List[hashtable]]::new()
                $currentBlock = $null

                foreach ($outputLine in $rawOutput) {
                    $lineText = $outputLine.ToString().Trim()
                    if ([string]::IsNullOrWhiteSpace($lineText)) {
                        continue
                    }

                    # Peer line detection: label : hostname,0xFlags
                    if ($lineText -match '^[^:]+:\s*(.+),(0x[0-9a-fA-F]+)\s*$') {
                        if ($currentBlock) {
                            $peerBlocks.Add($currentBlock)
                        }
                        $currentBlock = @{
                            PeerName      = $Matches[1].Trim()
                            PeerFlags     = $Matches[2]
                            State         = $null
                            TimeRemaining = [double]0
                            LastSyncTime  = $null
                            PollInterval  = [int]0
                        }
                        continue
                    }

                    if (-not $currentBlock) {
                        continue
                    }

                    # Time remaining: value ends with digits/decimal + 's'
                    if ($lineText -match ':\s*([\d.]+)\s*s\s*$') {
                        $currentBlock['TimeRemaining'] = [double]$Matches[1]
                    }
                    # Poll interval: digits followed by space and '('
                    elseif ($lineText -match ':\s*(\d+)\s*\(') {
                        $currentBlock['PollInterval'] = [int]$Matches[1]
                    }
                    # Last sync time: date pattern (digits separated by / . or -)
                    elseif ($lineText -match ':\s*(\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}\s+.+)$') {
                        $syncTimeString = $Matches[1].Trim()
                        try {
                            $currentBlock['LastSyncTime'] = [datetime]::Parse($syncTimeString)
                        } catch {
                            Write-Verbose "[$($MyInvocation.MyCommand)] Could not parse sync time: '$syncTimeString'"
                            $currentBlock['LastSyncTime'] = $null
                        }
                    }
                    # State: first unmatched key:value line after the peer line
                    elseif ($null -eq $currentBlock['State'] -and $lineText -match ':\s*(.+)$') {
                        $currentBlock['State'] = $Matches[1].Trim()
                    }
                }

                # Add the last block
                if ($currentBlock) {
                    $peerBlocks.Add($currentBlock)
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Parsed $($peerBlocks.Count) peer block(s) on '$targetComputer'"

                # --- Emit one object per peer ---
                foreach ($block in $peerBlocks) {
                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.NTPPeer'
                        ComputerName  = $targetComputer
                        PeerName      = $block['PeerName']
                        PeerFlags     = $block['PeerFlags']
                        State         = $block['State']
                        TimeRemaining = $block['TimeRemaining']
                        LastSyncTime  = $block['LastSyncTime']
                        PollInterval  = $block['PollInterval']
                        Timestamp     = Get-Date -Format 'o'
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query NTP peers on '${targetComputer}': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
