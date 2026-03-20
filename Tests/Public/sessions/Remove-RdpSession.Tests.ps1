#Requires -Version 5.1

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe -Name 'Remove-RdpSession' -Fixture {

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should require SessionID parameter' -Test {
            { Remove-RdpSession -Confirm:$false } | Should -Throw
        }

        It -Name 'Should reject negative SessionID' -Test {
            { Remove-RdpSession -SessionID -1 -Confirm:$false } | Should -Throw
        }

        It -Name 'Should reject SessionID above 65536' -Test {
            { Remove-RdpSession -SessionID 65537 -Confirm:$false } | Should -Throw
        }

        It -Name 'Should reject empty ComputerName' -Test {
            { Remove-RdpSession -ComputerName '' -SessionID 2 -Confirm:$false } | Should -Throw
        }

        It -Name 'Should reject null ComputerName' -Test {
            { Remove-RdpSession -ComputerName $null -SessionID 2 -Confirm:$false } | Should -Throw
        }
    }

    Context -Name 'Binary availability check' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith { $null }
        }

        It -Name 'Should throw terminating error when logoff.exe is not found' -Test {
            { Remove-RdpSession -SessionID 2 -Confirm:$false } | Should -Throw '*logoff.exe*'
        }
    }

    Context -Name 'When removing a local session successfully' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Source = 'C:\Windows\System32\logoff.exe' }
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { 0 }
        }

        It -Name 'Should return success result object' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result.Success | Should -BeTrue
        }

        It -Name 'Should include Logoff action type' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result.Action | Should -Be 'Logoff'
        }

        It -Name 'Should include PSTypeName' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result.PSObject.TypeNames | Should -Contain 'PSWinOps.RdpSessionAction'
        }

        It -Name 'Should include ComputerName in output' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should include SessionID in output' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result.SessionID | Should -Be 2
        }

        It -Name 'Should include ISO 8601 Timestamp' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It -Name 'Should invoke logoff via Invoke-Command' -Test {
            Remove-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should not pass ComputerName to Invoke-Command for local execution' -Test {
            Remove-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                -not $ComputerName
            }
        }
    }

    Context -Name 'When removing a remote session successfully' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Source = 'C:\Windows\System32\logoff.exe' }
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { 0 }
        }

        It -Name 'Should return success for explicit remote machine' -Test {
            $result = Remove-RdpSession -ComputerName 'REMOTE-SRV01' -SessionID 3 -Confirm:$false
            $result.Success | Should -BeTrue
            $result.ComputerName | Should -Be 'REMOTE-SRV01'
        }

        It -Name 'Should pass ComputerName to Invoke-Command for remote execution' -Test {
            Remove-RdpSession -ComputerName 'REMOTE-SRV01' -SessionID 3 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'REMOTE-SRV01'
            }
        }

        It -Name 'Should pass Credential to Invoke-Command when specified' -Test {
            $testCred = [System.Management.Automation.PSCredential]::new(
                'TestUser', (ConvertTo-SecureString -String 'P@ss' -AsPlainText -Force)
            )
            Remove-RdpSession -ComputerName 'REMOTE-SRV01' -SessionID 3 -Credential $testCred -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }
    }

    Context -Name 'When logoff.exe returns a non-zero exit code' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Source = 'C:\Windows\System32\logoff.exe' }
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { 1 }
        }

        It -Name 'Should return Success = $false on non-zero exit code' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result.Success | Should -BeFalse
        }

        It -Name 'Should still emit a result object on failure' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Logoff'
        }
    }

    Context -Name 'When Invoke-Command throws (per-machine failure)' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Source = 'C:\Windows\System32\logoff.exe' }
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                throw 'Connection failed'
            }
        }

        It -Name 'Should write an error and return result with Success = $false' -Test {
            $result = Remove-RdpSession -ComputerName 'DEAD-SRV' -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue
            $result.Success | Should -BeFalse
        }

        It -Name 'Should continue processing remaining machines after failure' -Test {
            $mockCallCount = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $script:mockCallCount++
                if ($script:mockCallCount -eq 1) { throw 'Connection failed' }
                return 0
            }
            $results = 2, 3 | Remove-RdpSession -Confirm:$false -ErrorAction SilentlyContinue
            $results.Count | Should -Be 2
        }
    }

    Context -Name 'When Force parameter is used' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Source = 'C:\Windows\System32\logoff.exe' }
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { 0 }
        }

        It -Name 'Should bypass confirmation when Force is specified' -Test {
            $result = Remove-RdpSession -SessionID 2 -Force
            $result.Success | Should -BeTrue
        }
    }

    Context -Name 'When ShouldProcess is declined' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Source = 'C:\Windows\System32\logoff.exe' }
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { 0 }
        }

        It -Name 'Should not invoke logoff when WhatIf is specified' -Test {
            Remove-RdpSession -SessionID 2 -WhatIf
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should not emit any output when WhatIf is specified' -Test {
            $result = Remove-RdpSession -SessionID 2 -WhatIf
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When processing pipeline input' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Source = 'C:\Windows\System32\logoff.exe' }
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { 0 }
        }

        It -Name 'Should process multiple sessions from pipeline' -Test {
            $results = 2, 3, 5 | Remove-RdpSession -Confirm:$false
            $results.Count | Should -Be 3
        }

        It -Name 'Should accept pipeline input from Get-RdpSession output shape' -Test {
            $fakeSession = [PSCustomObject]@{
                PSTypeName   = 'PSWinOps.ActiveRdpSession'
                ComputerName = 'SRV01'
                SessionID    = 7
                UserName     = 'TestUser'
                State        = 'Active'
            }
            $result = $fakeSession | Remove-RdpSession -Confirm:$false
            $result.ComputerName | Should -Be 'SRV01'
            $result.SessionID | Should -Be 7
        }

        It -Name 'Should process multiple sessions on same machine' -Test {
            $results = Remove-RdpSession -SessionID 2, 3, 5 -Confirm:$false
            $results.Count | Should -Be 3
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 3 -Exactly
        }
    }
}
