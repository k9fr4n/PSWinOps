#Requires -Version 5.1

function Get-ProcessByPort {
    <#
        .SYNOPSIS
            Correlate TCP/UDP endpoints with their owning process details

        .DESCRIPTION
            Joins listening and established TCP/UDP endpoints with the details of their
            owning process (name, executable path, command line) in a single command.
            Correlates each endpoint's OwningProcess with Win32_Process via CIM and works
            against local or remote computers.

            For remote computers, the query is executed via Invoke-Command.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional credential for remote computer connections.

        .PARAMETER Port
            Filter on LocalPort. Accepts multiple values. When omitted, all Listen
            and Established endpoints are returned.

        .PARAMETER State
            Filter TCP connections by state (Listen or Established). UDP endpoints
            are excluded from the results when State is specified, since UDP is
            stateless.

        .EXAMPLE
            Get-ProcessByPort

            Returns all TCP/UDP endpoints on the local machine with owning process details.

        .EXAMPLE
            Get-ProcessByPort -Port 443 -State Listen

            Shows which process is listening on TCP port 443 locally.

        .EXAMPLE
            Get-ProcessByPort -ComputerName 'SRV01' -Credential $cred

            Shows all endpoints and owning processes on a remote server.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-ProcessByPort -State Established

            Shows established TCP connections and owning processes on two remote servers.

        .OUTPUTS
            PSWinOps.ProcessPort
            One object per TCP/UDP endpoint, joined with owning process details.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-07-06
            Requires: PowerShell 5.1+ / Windows only
            Requires: Admin recommended for full process path/command line resolution

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ProcessPort')]
    param (
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int[]]$Port,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Listen', 'Established')]
        [string]$State
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting process-by-port query"

        $queryScriptBlock = {
            param([int[]]$FilterPorts, [string]$FilterState)

            # Build process cache (cast to [int] — OwningProcess is UInt32,
            # Win32_Process.ProcessId is UInt32; normalize before hashtable lookup)
            $processCache = @{}
            Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
                $pidKey = [int]$_.ProcessId
                if (-not $processCache.ContainsKey($pidKey)) {
                    $processCache[$pidKey] = [PSCustomObject]@{
                        ProcessName = $_.Name
                        ProcessPath = $_.ExecutablePath
                        CommandLine = $_.CommandLine
                    }
                }
            }

            $results = [System.Collections.Generic.List[PSObject]]::new()

            # TCP connections (Listen + Established, optionally narrowed by -State)
            if (-not $FilterState -or $FilterState -in @('Listen', 'Established')) {
                $tcpParams = @{ ErrorAction = 'SilentlyContinue' }
                if ($FilterState) {
                    $tcpParams['State'] = $FilterState
                }

                $tcpConnections = Get-NetTCPConnection @tcpParams | Where-Object {
                    $_.State -in @('Listen', 'Established') -and (-not $FilterState -or $_.State.ToString() -eq $FilterState)
                }

                foreach ($conn in $tcpConnections) {
                    if ($FilterPorts -and $FilterPorts.Count -gt 0 -and $conn.LocalPort -notin $FilterPorts) {
                        continue
                    }

                    $ownerPid = [int]$conn.OwningProcess
                    $procInfo = $processCache[$ownerPid]

                    $results.Add([PSCustomObject]@{
                            Protocol      = 'TCP'
                            LocalAddress  = $conn.LocalAddress
                            LocalPort     = $conn.LocalPort
                            RemoteAddress = $conn.RemoteAddress
                            RemotePort    = $conn.RemotePort
                            State         = $conn.State.ToString()
                            ProcessId     = $ownerPid
                            ProcessName   = if ($procInfo) {
                                $procInfo.ProcessName
                            } else {
                                $null
                            }
                            ProcessPath   = if ($procInfo) {
                                $procInfo.ProcessPath
                            } else {
                                $null
                            }
                            CommandLine   = if ($procInfo) {
                                $procInfo.CommandLine
                            } else {
                                $null
                            }
                        })
                }
            }

            # UDP endpoints (stateless — excluded entirely when -State is specified)
            if (-not $FilterState) {
                $udpEndpoints = Get-NetUDPEndpoint -ErrorAction SilentlyContinue

                foreach ($ep in $udpEndpoints) {
                    if ($FilterPorts -and $FilterPorts.Count -gt 0 -and $ep.LocalPort -notin $FilterPorts) {
                        continue
                    }

                    $ownerPid = [int]$ep.OwningProcess
                    $procInfo = $processCache[$ownerPid]

                    $results.Add([PSCustomObject]@{
                            Protocol      = 'UDP'
                            LocalAddress  = $ep.LocalAddress
                            LocalPort     = $ep.LocalPort
                            RemoteAddress = $null
                            RemotePort    = $null
                            State         = $null
                            ProcessId     = $ownerPid
                            ProcessName   = if ($procInfo) {
                                $procInfo.ProcessName
                            } else {
                                $null
                            }
                            ProcessPath   = if ($procInfo) {
                                $procInfo.ProcessPath
                            } else {
                                $null
                            }
                            CommandLine   = if ($procInfo) {
                                $procInfo.CommandLine
                            } else {
                                $null
                            }
                        })
                }
            }

            return $results
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

                Write-Verbose "[$($MyInvocation.MyCommand)] Querying process-by-port on '$targetComputer'"

                $queryArgs = @(
                    , $Port
                    $(if ($PSBoundParameters.ContainsKey('State')) {
                            $State
                        } else {
                            $null
                        })
                )

                $rawResults = Invoke-RemoteOrLocal -ComputerName $targetComputer -ScriptBlock $queryScriptBlock -ArgumentList $queryArgs -Credential $Credential

                foreach ($entry in $rawResults) {
                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.ProcessPort'
                        ComputerName  = $targetComputer
                        Protocol      = $entry.Protocol
                        LocalAddress  = $entry.LocalAddress
                        LocalPort     = $entry.LocalPort
                        RemoteAddress = $entry.RemoteAddress
                        RemotePort    = $entry.RemotePort
                        State         = $entry.State
                        ProcessId     = $entry.ProcessId
                        ProcessName   = $entry.ProcessName
                        ProcessPath   = $entry.ProcessPath
                        CommandLine   = $entry.CommandLine
                        Timestamp     = $timestamp
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed process-by-port query"
    }
}
