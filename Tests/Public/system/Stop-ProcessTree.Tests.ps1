#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Stop-ProcessTree' {
    BeforeAll {
        # ---- Reusable process fixtures ----
        # 0/4  : protected system PIDs (no children in this fixture)
        # 1000 : root -> 2000 -> 3000 (three-level tree)
        # 5000 : standalone leaf, resolvable by -Name 'notepad'
        $script:mockProcessList = @(
            [PSCustomObject]@{ ProcessId = 0; ParentProcessId = 0; Name = 'System Idle Process' }
            [PSCustomObject]@{ ProcessId = 4; ParentProcessId = 0; Name = 'System' }
            [PSCustomObject]@{ ProcessId = 1000; ParentProcessId = 4; Name = 'parent.exe' }
            [PSCustomObject]@{ ProcessId = 2000; ParentProcessId = 1000; Name = 'child.exe' }
            [PSCustomObject]@{ ProcessId = 3000; ParentProcessId = 2000; Name = 'grandchild.exe' }
            [PSCustomObject]@{ ProcessId = 5000; ParentProcessId = 1; Name = 'notepad.exe' }
        )

        # Two processes whose ParentProcessId points at each other (recycled/looping PIDs).
        $script:cyclicProcessList = @(
            [PSCustomObject]@{ ProcessId = 8000; ParentProcessId = 8001; Name = 'cyclea.exe' }
            [PSCustomObject]@{ ProcessId = 8001; ParentProcessId = 8000; Name = 'cycleb.exe' }
        )

        function New-ChainProcessList {
            param(
                [int]$Count,
                [int]$StartPid = 10000
            )

            $list = [System.Collections.Generic.List[object]]::new()
            for ($i = 0; $i -lt $Count; $i++) {
                $currentPid = $StartPid + $i
                $parentPid = if ($i -eq 0) { 1 } else { $StartPid + $i - 1 }
                $list.Add([PSCustomObject]@{ ProcessId = $currentPid; ParentProcessId = $parentPid; Name = "chain$i.exe" })
            }
            return $list
        }
    }

    Context 'Local happy path by -Id: tree built, leaves terminated before root' {
        BeforeAll {
            $script:terminateOrder = [System.Collections.Generic.List[int]]::new()

            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    $targetPid = $ArgumentList[0]
                    $script:terminateOrder.Add($targetPid)
                    return [PSCustomObject]@{ ReturnValue = 0 }
                }

                return $script:mockProcessList
            }

            $script:idResult = Stop-ProcessTree -Id 1000 -Confirm:$false
        }

        It -Name 'Should return one row per node in the tree (root + 2 descendants)' -Test {
            $script:idResult | Should -HaveCount 3
        }

        It -Name 'Should terminate the deepest descendant first' -Test {
            $script:terminateOrder[0] | Should -Be 3000
        }

        It -Name 'Should terminate the root last' -Test {
            $script:terminateOrder[-1] | Should -Be 1000
        }

        It -Name 'Should mark every node as Killed' -Test {
            foreach ($row in $script:idResult) {
                $row.Killed | Should -BeTrue
            }
        }

        It -Name 'Should have PSTypeName PSWinOps.ProcessKillResult' -Test {
            $script:idResult[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ProcessKillResult'
        }

        It -Name 'Should set ComputerName to the local computer' -Test {
            $script:idResult[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should include a Depth of 0 for the root node' -Test {
            ($script:idResult | Where-Object -Property ProcessId -eq 1000).Depth | Should -Be 0
        }

        It -Name 'Should include a Depth of 2 for the grandchild node' -Test {
            ($script:idResult | Where-Object -Property ProcessId -eq 3000).Depth | Should -Be 2
        }

        It -Name 'Should format Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $script:idResult[0].Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
    }

    Context 'By -Name resolves root PID(s)' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    return [PSCustomObject]@{ ReturnValue = 0 }
                }

                return $script:mockProcessList
            }

            $script:nameResult = Stop-ProcessTree -Name 'notepad' -Confirm:$false
        }

        It -Name 'Should resolve the root PID from the process name' -Test {
            $script:nameResult | Should -HaveCount 1
            $script:nameResult[0].ProcessId | Should -Be 5000
        }

        It -Name 'Should terminate the resolved root' -Test {
            $script:nameResult[0].Killed | Should -BeTrue
        }

        It -Name 'Should return an unresolved row when the name does not match any process' -Test {
            $unresolved = Stop-ProcessTree -Name 'doesnotexist' -Confirm:$false
            $unresolved | Should -HaveCount 1
            $unresolved[0].Killed | Should -BeFalse
            $unresolved[0].Error | Should -Be 'Process not found'
        }
    }

    Context 'Explicit remote machine via -ComputerName' {
        BeforeAll {
            $script:remoteCalls = [System.Collections.Generic.List[object]]::new()

            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                $script:remoteCalls.Add([PSCustomObject]@{ ComputerName = $ComputerName; Credential = $Credential })

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    return [PSCustomObject]@{ ReturnValue = 0 }
                }

                return $script:mockProcessList
            }

            $script:cred = [System.Management.Automation.PSCredential]::new(
                'DOMAIN\svc', (ConvertTo-SecureString -String 'p@ssw0rd' -AsPlainText -Force)
            )
            $script:remoteResult = Stop-ProcessTree -Id 5000 -ComputerName 'SRV01' -Credential $script:cred -Confirm:$false
        }

        It -Name 'Should set ComputerName to the remote machine on the output rows' -Test {
            $script:remoteResult[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should call Invoke-RemoteOrLocal against the remote machine' -Test {
            $script:remoteCalls | Where-Object -Property ComputerName -eq 'SRV01' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should propagate the supplied Credential to Invoke-RemoteOrLocal' -Test {
            foreach ($call in $script:remoteCalls) {
                $call.Credential | Should -Be $script:cred
            }
        }

        It -Name 'Should call Invoke-RemoteOrLocal for the query and the terminate step' -Test {
            Stop-ProcessTree -Id 5000 -ComputerName 'SRV01' -Confirm:$false
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Pipeline of multiple machine names' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    return [PSCustomObject]@{ ReturnValue = 0 }
                }

                return $script:mockProcessList
            }

            $script:pipeResults = 'SRV01', 'SRV02' | Stop-ProcessTree -Id 5000 -Confirm:$false
        }

        It -Name 'Should process each computer from the pipeline' -Test {
            $script:pipeResults | Should -HaveCount 2
        }

        It -Name 'Should return correct ComputerName for the first server' -Test {
            $script:pipeResults[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return correct ComputerName for the second server' -Test {
            $script:pipeResults[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Per-machine failure: mock throws, function continues and writes error' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                if ($ComputerName -eq 'BADHOST') {
                    throw 'Connection failed'
                }

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    return [PSCustomObject]@{ ReturnValue = 0 }
                }

                return $script:mockProcessList
            }
        }

        It -Name 'Should write an error for the failing machine but still process the next one' -Test {
            $script:mixedResults = 'BADHOST', 'GOODHOST' |
                Stop-ProcessTree -Id 5000 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:capturedError

            $script:capturedError | Should -Not -BeNullOrEmpty
            $script:mixedResults | Should -HaveCount 1
            $script:mixedResults[0].ComputerName | Should -Be 'GOODHOST'
        }
    }

    Context 'Process gone between enum and kill: Killed=$false, Error set, continues' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    $targetPid = $ArgumentList[0]
                    if ($targetPid -eq 2000) {
                        throw "Process $targetPid no longer exists"
                    }
                    return [PSCustomObject]@{ ReturnValue = 0 }
                }

                return $script:mockProcessList
            }

            $script:raceResult = Stop-ProcessTree -Id 1000 -Confirm:$false
        }

        It -Name 'Should mark the vanished process as not killed with an Error message' -Test {
            $vanished = $script:raceResult | Where-Object -Property ProcessId -eq 2000
            $vanished.Killed | Should -BeFalse
            $vanished.Error | Should -BeLike '*no longer exists*'
        }

        It -Name 'Should still terminate the sibling nodes in the tree' -Test {
            ($script:raceResult | Where-Object -Property ProcessId -eq 3000).Killed | Should -BeTrue
            ($script:raceResult | Where-Object -Property ProcessId -eq 1000).Killed | Should -BeTrue
        }

        It -Name 'Should not throw and should return a row for every node' -Test {
            $script:raceResult | Should -HaveCount 3
        }
    }

    Context 'Protected PID 0/4 refused (never terminated)' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    $targetPid = $ArgumentList[0]
                    if ($targetPid -in @(0, 4)) {
                        throw 'Terminate must never be called on a protected PID'
                    }
                    return [PSCustomObject]@{ ReturnValue = 0 }
                }

                return $script:mockProcessList
            }
        }

        It -Name 'Should refuse to terminate PID 0 (System Idle Process)' -Test {
            $result = Stop-ProcessTree -Id 0 -Confirm:$false
            $result | Should -HaveCount 1
            $result[0].Killed | Should -BeFalse
            $result[0].Error | Should -Be 'Refused: protected system process'
        }

        It -Name 'Should refuse to terminate PID 4 (System)' -Test {
            $result = Stop-ProcessTree -Id 4 -Confirm:$false
            $result | Should -HaveCount 1
            $result[0].Killed | Should -BeFalse
            $result[0].Error | Should -Be 'Refused: protected system process'
        }
    }

    Context 'Loop/recycled PID guard: visited set prevents infinite walk on a cycle' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    return [PSCustomObject]@{ ReturnValue = 0 }
                }

                return $script:cyclicProcessList
            }

            $script:cyclicResult = Stop-ProcessTree -Id 8000 -Confirm:$false
        }

        It -Name 'Should visit each PID in the cycle exactly once and terminate' -Test {
            $script:cyclicResult | Should -HaveCount 2
        }

        It -Name 'Should not revisit the already-seen root PID as a child of its own child' -Test {
            ($script:cyclicResult | Select-Object -ExpandProperty ProcessId | Sort-Object -Unique) | Should -Be @(8000, 8001)
        }
    }

    Context 'Loop/recycled PID guard: hard depth bound stops runaway chains' {
        BeforeAll {
            $script:deepChain = New-ChainProcessList -Count 150 -StartPid 10000

            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    return [PSCustomObject]@{ ReturnValue = 0 }
                }

                return $script:deepChain
            }

            $script:chainResult = Stop-ProcessTree -Id 10000 -Confirm:$false
        }

        It -Name 'Should stop descending once the depth bound (100) is reached' -Test {
            $script:chainResult | Should -HaveCount 101
        }

        It -Name 'Should not produce a node with a Depth greater than 100' -Test {
            ($script:chainResult | Measure-Object -Property Depth -Maximum).Maximum | Should -Be 100
        }
    }

    Context '-WhatIf lists tree without calling Invoke-CimMethod Terminate' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $ArgumentList)

                if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                    throw 'Terminate must never be invoked under -WhatIf'
                }

                return $script:mockProcessList
            }
        }

        It -Name 'Should not throw and should not terminate anything with -WhatIf' -Test {
            { Stop-ProcessTree -Id 1000 -WhatIf } | Should -Not -Throw
        }

        It -Name 'Should not produce any Killed=$true rows with -WhatIf' -Test {
            $whatIfResult = Stop-ProcessTree -Id 1000 -WhatIf
            $whatIfResult | Where-Object -Property Killed -eq $true | Should -BeNullOrEmpty
        }

        It -Name 'Should call Invoke-RemoteOrLocal only for the read-only query, never for terminate' -Test {
            Stop-ProcessTree -Id 1000 -WhatIf
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Parameter set validation: -Id and -Name are mutually exclusive' {
        It -Name 'Should throw when both -Id and -Name are supplied' -Test {
            { Stop-ProcessTree -Id 1000 -Name 'notepad' -Confirm:$false } | Should -Throw
        }

        It -Name 'Should throw when -Id is an empty array' -Test {
            { Stop-ProcessTree -Id @() -Confirm:$false } | Should -Throw
        }

        It -Name 'Should throw when -Name is an empty string' -Test {
            { Stop-ProcessTree -Name '' -Confirm:$false } | Should -Throw
        }

        It -Name 'Should throw when neither -Id nor -Name is supplied' -Test {
            { Stop-ProcessTree -Confirm:$false } | Should -Throw
        }
    }
}
