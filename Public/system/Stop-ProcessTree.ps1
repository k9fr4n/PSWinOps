#Requires -Version 5.1
function Stop-ProcessTree {
    <#
    .SYNOPSIS
        Terminate a process and its entire descendant tree, leaves first

    .DESCRIPTION
        Builds the descendant tree of one or more root processes from
        Win32_Process ParentProcessId and terminates every node, killing leaves
        before the root. Select roots by -Id or -Name (mutually exclusive), target
        local or remote machines, and preview with -WhatIf. Termination is
        irreversible (ConfirmImpact High).

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional credential used to authenticate against remote computers.
        Ignored when the target is the local computer.

    .PARAMETER Id
        Root process ID(s) whose descendant tree is terminated.
        Mutually exclusive with -Name. Accepts pipeline input by property name.

    .PARAMETER Name
        Root process name(s), without the '.exe' extension.
        Mutually exclusive with -Id. Accepts pipeline input by property name.

    .EXAMPLE
        Stop-ProcessTree -Id 1234

        Terminates process 1234 and all of its descendants on the local computer.

    .EXAMPLE
        Stop-ProcessTree -Name 'chrome' -ComputerName 'SRV01'

        Terminates every 'chrome' process tree found on SRV01.

    .EXAMPLE
        'SRV01', 'SRV02' | Stop-ProcessTree -Name 'notepad' -WhatIf

        Previews termination of every 'notepad' process tree on SRV01 and SRV02
        without actually terminating anything.

    .OUTPUTS
        PSWinOps.ProcessKillResult
        Returns one object per process examined (root, descendant, or unresolved
        root), including whether it was killed and any error encountered.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-07-06
        Requires: PowerShell 5.1+ / Windows only
        Requires: Sufficient privileges to terminate the target processes

    .LINK
        https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    [OutputType('PSWinOps.ProcessKillResult')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $true, ParameterSetName = 'ById', ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [int[]]$Id,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByName', ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # --- Protected system PIDs never eligible for termination --------------
        $protectedPids = @(0, 4)
        $maxDepth = 100

        # --- Scriptblocks executed locally or remotely via Invoke-RemoteOrLocal
        $queryScriptBlock = {
            Get-CimInstance -ClassName 'Win32_Process' -ErrorAction Stop |
                Select-Object -Property ProcessId, ParentProcessId, Name
        }

        $terminateScriptBlock = {
            param($targetPid)

            $targetProcess = Get-CimInstance -ClassName 'Win32_Process' -Filter "ProcessId=$targetPid" -ErrorAction Stop
            if (-not $targetProcess) {
                throw "Process $targetPid no longer exists"
            }
            Invoke-CimMethod -InputObject $targetProcess -MethodName 'Terminate' -ErrorAction Stop
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing $targetComputer"

            try {
                $processList = Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential -ScriptBlock $queryScriptBlock

                # ===============================================================
                # RESOLVE ROOT PROCESSES
                # ===============================================================
                $rootProcesses = [System.Collections.Generic.List[object]]::new()
                $unresolvedRows = [System.Collections.Generic.List[object]]::new()

                if ($PSCmdlet.ParameterSetName -eq 'ById') {
                    foreach ($rootId in $Id) {
                        $match = $processList | Where-Object -Property ProcessId -eq $rootId
                        if ($match) {
                            $rootProcesses.Add($match)
                        } else {
                            $unresolvedRows.Add([PSCustomObject]@{
                                PSTypeName      = 'PSWinOps.ProcessKillResult'
                                ComputerName    = $targetComputer
                                ProcessId       = $rootId
                                Name            = $null
                                ParentProcessId = $null
                                Depth           = 0
                                Killed          = $false
                                Error           = 'Process not found'
                                Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            })
                        }
                    }
                } else {
                    foreach ($rootName in $Name) {
                        $expectedName = if ($rootName -like '*.exe') { $rootName } else { "$rootName.exe" }
                        $nameMatches = $processList | Where-Object -Property Name -eq $expectedName
                        if ($nameMatches) {
                            foreach ($match in $nameMatches) {
                                $rootProcesses.Add($match)
                            }
                        } else {
                            $unresolvedRows.Add([PSCustomObject]@{
                                PSTypeName      = 'PSWinOps.ProcessKillResult'
                                ComputerName    = $targetComputer
                                ProcessId       = $null
                                Name            = $rootName
                                ParentProcessId = $null
                                Depth           = 0
                                Killed          = $false
                                Error           = 'Process not found'
                                Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            })
                        }
                    }
                }

                foreach ($unresolvedRow in $unresolvedRows) {
                    $unresolvedRow
                }

                # ===============================================================
                # BUILD DESCENDANT TREE (breadth-first) AND KILL LEAVES FIRST
                # ===============================================================
                foreach ($rootProcess in $rootProcesses) {
                    $treeNodes = [System.Collections.Generic.List[object]]::new()
                    $visitedPids = [System.Collections.Generic.HashSet[int]]::new()
                    $queue = [System.Collections.Generic.Queue[object]]::new()

                    $null = $visitedPids.Add([int]$rootProcess.ProcessId)
                    $queue.Enqueue([PSCustomObject]@{ Process = $rootProcess; Depth = 0 })

                    while ($queue.Count -gt 0) {
                        $current = $queue.Dequeue()
                        $treeNodes.Add($current)

                        if ($current.Depth -ge $maxDepth) {
                            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Depth bound ($maxDepth) reached at PID $($current.Process.ProcessId), stopping descent"
                            continue
                        }

                        $children = $processList | Where-Object -Property ParentProcessId -eq $current.Process.ProcessId
                        foreach ($child in $children) {
                            $childPid = [int]$child.ProcessId
                            if (-not $visitedPids.Contains($childPid)) {
                                $null = $visitedPids.Add($childPid)
                                $queue.Enqueue([PSCustomObject]@{ Process = $child; Depth = $current.Depth + 1 })
                            }
                        }
                    }

                    # Leaves first: deepest nodes terminated before their ancestors.
                    $killOrder = $treeNodes | Sort-Object -Property Depth -Descending

                    foreach ($node in $killOrder) {
                        $nodePid = [int]$node.Process.ProcessId
                        $nodeName = $node.Process.Name
                        $nodeParentPid = $node.Process.ParentProcessId

                        if ($nodePid -in $protectedPids) {
                            [PSCustomObject]@{
                                PSTypeName      = 'PSWinOps.ProcessKillResult'
                                ComputerName    = $targetComputer
                                ProcessId       = $nodePid
                                Name            = $nodeName
                                ParentProcessId = $nodeParentPid
                                Depth           = $node.Depth
                                Killed          = $false
                                Error           = 'Refused: protected system process'
                                Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                            continue
                        }

                        if ($PSCmdlet.ShouldProcess("$targetComputer PID $nodePid ($nodeName)", 'Terminate process')) {
                            $killed = $false
                            $killError = $null

                            try {
                                $terminateResult = Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential -ScriptBlock $terminateScriptBlock -ArgumentList @($nodePid)
                                if ($terminateResult.ReturnValue -eq 0) {
                                    $killed = $true
                                } else {
                                    $killError = "Terminate returned code $($terminateResult.ReturnValue)"
                                }
                            } catch {
                                $killError = $_.Exception.Message
                            }

                            [PSCustomObject]@{
                                PSTypeName      = 'PSWinOps.ProcessKillResult'
                                ComputerName    = $targetComputer
                                ProcessId       = $nodePid
                                Name            = $nodeName
                                ParentProcessId = $nodeParentPid
                                Depth           = $node.Depth
                                Killed          = $killed
                                Error           = $killError
                                Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                        }
                    }
                }
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
