#Requires -Version 5.1

BeforeAll {
    # Import module - FIXED: corrected path
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    # Mock test data
    $script:mockLogonSession = [PSCustomObject]@{
        LogonId               = '123456'
        LogonType             = 10
        StartTime             = (Get-Date).AddHours(-2)
        AuthenticationPackage = 'Negotiate'
    }

    $script:mockUser = [PSCustomObject]@{
        Domain = 'TESTDOMAIN'
        Name   = 'testuser'
    }
}

Describe -Name 'Get-ActiveRdpSession' -Fixture {

    Context -Name 'When querying local computer with active sessions' -Fixture {

        BeforeEach {
            # FIXED: Removed unused parameters from all mocks
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    ComputerName         = 'localhost'
                    CimSessionInstanceId = [guid]::NewGuid()
                }
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockLogonSession
            }

            Mock -CommandName 'Get-CimAssociatedInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should return PSCustomObject with correct type name' -Test {
            $result = Get-ActiveRdpSession
            $result.PSTypeName | Should -Be 'PSWinOps.ActiveRdpSession'
        }

        It -Name 'Should include all required properties' -Test {
            $result = Get-ActiveRdpSession
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'SessionID'
            $result.PSObject.Properties.Name | Should -Contain 'UserName'
            $result.PSObject.Properties.Name | Should -Contain 'LogonTime'
            $result.PSObject.Properties.Name | Should -Contain 'IdleTime'
        }

        It -Name 'Should format username as DOMAIN\User' -Test {
            $result = Get-ActiveRdpSession
            $result.UserName | Should -Be 'TESTDOMAIN\testuser'
        }

        It -Name 'Should invoke New-CimSession exactly once' -Test {
            Get-ActiveRdpSession
            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should invoke Remove-CimSession to clean up' -Test {
            Get-ActiveRdpSession
            Should -Invoke -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'When no sessions are found' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    ComputerName         = 'localhost'
                    CimSessionInstanceId = [guid]::NewGuid()
                }
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $null
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should return no output' -Test {
            $result = Get-ActiveRdpSession
            $result | Should -BeNullOrEmpty
        }

        It -Name 'Should still clean up CIM session' -Test {
            Get-ActiveRdpSession
            Should -Invoke -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'When access is denied' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                throw [System.UnauthorizedAccessException]::new('Access denied')
            }
        }

        It -Name 'Should write an error and not throw' -Test {
            { Get-ActiveRdpSession -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should not return any objects' -Test {
            $result = Get-ActiveRdpSession -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When querying multiple computers via pipeline' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    ComputerName         = 'MockedServer'
                    CimSessionInstanceId = [guid]::NewGuid()
                }
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockLogonSession
            }

            Mock -CommandName 'Get-CimAssociatedInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should process all computers in pipeline' -Test {
            $computers = @('SRV01', 'SRV02', 'SRV03')
            $result = $computers | Get-ActiveRdpSession
            $result.Count | Should -Be 3
        }

        It -Name 'Should invoke New-CimSession once per computer' -Test {
            @('SRV01', 'SRV02') | Get-ActiveRdpSession
            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }
}
