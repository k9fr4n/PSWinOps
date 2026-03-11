#Requires -Version 5.1

#Requires -Version 5.1

BeforeAll {
    # Import module
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    # Mock objects shared across tests
    $script:mockCimSession = [PSCustomObject]@{
        ComputerName = 'localhost'
        Id           = 1
    }

    $script:mockTsService = [PSCustomObject]@{
        Name    = 'TerminalServices'
        __CLASS = 'Win32_TerminalService'
        __PATH  = '\\localhost\root\cimv2\TerminalServices:Win32_TerminalService=@'
    }

    $script:mockSuccessResult = [PSCustomObject]@{
        ReturnValue = 0
    }
}

Describe -Name 'Disconnect-RdpSession' -Fixture {

    Context -Name 'When disconnecting a session successfully' -Fixture {

        BeforeEach {
            # Module-scoped mocks - critical for proper interception
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCimSession
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should return success result object' -Test {
            $result = Disconnect-RdpSession -SessionID 2 -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.ReturnCode | Should -Be 0
            $result.SessionID | Should -Be 2
        }

        It -Name 'Should include correct action type' -Test {
            $result = Disconnect-RdpSession -SessionID 2 -Confirm:$false

            $result.Action | Should -Be 'Disconnect'
        }

        It -Name 'Should invoke DisconnectSession method with correct parameters' -Test {
            Disconnect-RdpSession -SessionID 2 -Confirm:$false

            Should -Invoke -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $MethodName -eq 'DisconnectSession' -and
                $Arguments.SessionId -eq 2
            }
        }

        It -Name 'Should clean up CIM session' -Test {
            Disconnect-RdpSession -SessionID 2 -Confirm:$false

            Should -Invoke -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should include timestamp in result' -Test {
            $beforeTime = Get-Date
            $result = Disconnect-RdpSession -SessionID 2 -Confirm:$false
            $afterTime = Get-Date

            $result.Timestamp | Should -BeOfType ([datetime])
            $result.Timestamp | Should -BeGreaterOrEqual $beforeTime
            $result.Timestamp | Should -BeLessOrEqual $afterTime
        }
    }

    Context -Name 'When ShouldProcess is declined' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCimSession
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should not invoke disconnect when WhatIf is specified' -Test {
            Disconnect-RdpSession -SessionID 2 -WhatIf

            Should -Invoke -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should not create CIM session when WhatIf is specified' -Test {
            Disconnect-RdpSession -SessionID 2 -WhatIf

            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should not return any result when WhatIf is specified' -Test {
            $result = Disconnect-RdpSession -SessionID 2 -WhatIf

            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When disconnecting multiple sessions' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCimSession
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should process all session IDs' -Test {
            $result = Disconnect-RdpSession -SessionID 2, 3, 5 -Confirm:$false

            $result.Count | Should -Be 3
            $result[0].SessionID | Should -Be 2
            $result[1].SessionID | Should -Be 3
            $result[2].SessionID | Should -Be 5
        }

        It -Name 'Should invoke method once per session' -Test {
            Disconnect-RdpSession -SessionID 2, 3 -Confirm:$false

            Should -Invoke -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }

        It -Name 'Should create and clean up CIM session once for all sessions' -Test {
            Disconnect-RdpSession -SessionID 2, 3, 5 -Confirm:$false

            # CIM session should be created/cleaned once per session due to process block
            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 3 -Exactly
            Should -Invoke -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -Times 3 -Exactly
        }
    }

    Context -Name 'When CIM operation fails' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCimSession
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                $exception = [Microsoft.Management.Infrastructure.CimException]::new('The WS-Management service cannot process the request.')
                throw $exception
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should write error and not throw' -Test {
            { Disconnect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should clean up CIM session even when Get-CimInstance fails' -Test {
            Disconnect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue

            Should -Invoke -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should not return result object when CIM operation fails' -Test {
            $result = Disconnect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When access is denied' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                throw [System.UnauthorizedAccessException]::new('Access denied')
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should write error and not throw' -Test {
            { Disconnect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should not invoke Get-CimInstance when session creation fails' -Test {
            Disconnect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue

            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should not return result object when access is denied' -Test {
            $result = Disconnect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When using custom credential' -Fixture {

        BeforeEach {
            # Create a mock credential for testing without exposing plaintext
            $secureString = New-Object System.Security.SecureString
            $script:testCredential = [PSCredential]::new('TestUser', $secureString)

            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCimSession
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should pass credential to New-CimSession' -Test {
            Disconnect-RdpSession -SessionID 2 -ComputerName 'RemoteServer' -Credential $script:testCredential -Confirm:$false

            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $script:testCredential -and
                $ComputerName -eq 'RemoteServer'
            }
        }
    }

    Context -Name 'When disconnect operation returns failure code' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCimSession
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ ReturnValue = 1 }
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should return result with Success set to false' -Test {
            $result = Disconnect-RdpSession -SessionID 2 -Confirm:$false

            $result.Success | Should -Be $false
            $result.ReturnCode | Should -Be 1
        }

        It -Name 'Should still clean up CIM session after failure' -Test {
            Disconnect-RdpSession -SessionID 2 -Confirm:$false

            Should -Invoke -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }
}
