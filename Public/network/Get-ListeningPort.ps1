#Requires -Version 5.1

function Get-ListeningPort {
    <#
        .SYNOPSIS
            Shows which processes are listening on which ports

        .DESCRIPTION
            Retrieves TCP listening sockets and UDP bound endpoints, resolves the owning
            process name, and returns a consolidated view. Similar to 'netstat -tlnp'
            on Linux or the listening ports view in System Informer.

            For remote computers, the query is executed via Invoke-Command.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input.

        .PARAMETER Credential
            Optional credential for remote computer connections.

        .PARAMETER Protocol
            Filter by protocol: TCP, UDP, or both. Default: @('TCP', 'UDP').
            Accepts multiple values.

        .PARAMETER Port
            Filter by specific port number.

        .PARAMETER ProcessName
            Filter by process name. Supports wildcards.

        .EXAMPLE
            Get-ListeningPort

            Returns all listening TCP and bound UDP ports with process info.

        .EXAMPLE
            Get-ListeningPort -Protocol TCP -Port 443

            Shows which process is listening on TCP port 443.

        .EXAMPLE
            Get-ListeningPort -ProcessName 'httpd*'

            Shows all ports where Apache is listening.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-ListeningPort -Protocol TCP

            Shows listening TCP ports on two remote servers.

        .OUTPUTS
            PSWinOps.ListeningPort

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   Admin recommended for full process name resolution

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ListeningPort')]
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
        [ValidateSet('TCP', 'UDP')]
        [string[]]$Protocol = @('TCP', 'UDP'),

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$ProcessName
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting listening port query"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
        $hasCredential = $PSBoundParameters.ContainsKey('Credential')

        $queryScriptBlock = {
            param([string[]]$FilterProtocols, [int]$FilterPort, [string]$FilterProcess)

            # Build process cache (cast to [int] — OwningProcess is UInt32,
            # Process.Id is Int32; mismatched key types cause lookup failures)
            $processCache = @{}
            Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
                $pidKey = [int]$_.Id
                if (-not $processCache.ContainsKey($pidKey)) {
                    $processCache[$pidKey] = $_.ProcessName
                }
            }

            $results = [System.Collections.Generic.List[PSObject]]::new()

            # TCP listeners
            if ($FilterProtocols -contains 'TCP') {
                $listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
                foreach ($conn in $listeners) {
                    if ($FilterPort -gt 0 -and $conn.LocalPort -ne $FilterPort) {
                        continue
                    }

                    $ownerPid = [int]$conn.OwningProcess
                    $pName = if ($processCache.ContainsKey($ownerPid)) {
                        $processCache[$ownerPid]
                    } elseif ($ownerPid -eq 0) {
                        'System Idle'
                    } elseif ($ownerPid -eq 4) {
                        'System'
                    } else {
                        '[Unknown]'
                    }

                    if ($FilterProcess -and $pName -notlike $FilterProcess) {
                        continue
                    }

                    $results.Add([PSCustomObject]@{
                            Protocol     = 'TCP'
                            LocalAddress = $conn.LocalAddress
                            LocalPort    = $conn.LocalPort
                            ProcessId    = $conn.OwningProcess
                            ProcessName  = $pName
                        })
                }
            }

            # UDP endpoints
            if ($FilterProtocols -contains 'UDP') {
                $endpoints = Get-NetUDPEndpoint -ErrorAction SilentlyContinue
                foreach ($ep in $endpoints) {
                    if ($FilterPort -gt 0 -and $ep.LocalPort -ne $FilterPort) {
                        continue
                    }

                    $ownerPid = [int]$ep.OwningProcess
                    $pName = if ($processCache.ContainsKey($ownerPid)) {
                        $processCache[$ownerPid]
                    } elseif ($ownerPid -eq 0) {
                        'System Idle'
                    } elseif ($ownerPid -eq 4) {
                        'System'
                    } else {
                        '[Unknown]'
                    }

                    if ($FilterProcess -and $pName -notlike $FilterProcess) {
                        continue
                    }

                    $results.Add([PSCustomObject]@{
                            Protocol     = 'UDP'
                            LocalAddress = $ep.LocalAddress
                            LocalPort    = $ep.LocalPort
                            ProcessId    = $ep.OwningProcess
                            ProcessName  = $pName
                        })
                }
            }

            return $results
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $isLocal = $localNames -contains $targetComputer
                $timestamp = Get-Date -Format 'o'

                Write-Verbose "[$($MyInvocation.MyCommand)] Querying listening ports on '$targetComputer'"

                $queryArgs = @(
                    , $Protocol
                    $(if ($PSBoundParameters.ContainsKey('Port')) {
                            $Port
                        } else {
                            0
                        })
                    $(if ($ProcessName) {
                            $ProcessName
                        } else {
                            $null
                        })
                )

                if ($isLocal) {
                    $rawResults = & $queryScriptBlock @queryArgs
                } else {
                    $invokeParams = @{
                        ComputerName = $targetComputer
                        ScriptBlock  = $queryScriptBlock
                        ArgumentList = $queryArgs
                        ErrorAction  = 'Stop'
                    }
                    if ($hasCredential) {
                        $invokeParams['Credential'] = $Credential
                    }
                    $rawResults = Invoke-Command @invokeParams
                }

                foreach ($entry in $rawResults) {
                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.ListeningPort'
                        ComputerName = $targetComputer
                        Protocol     = $entry.Protocol
                        LocalAddress = $entry.LocalAddress
                        LocalPort    = $entry.LocalPort
                        ProcessId    = $entry.ProcessId
                        ProcessName  = $entry.ProcessName
                        Timestamp    = $timestamp
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed listening port query"
    }
}
