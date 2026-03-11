#Requires -Version 5.1

BeforeAll {
    <#
.SYNOPSIS
    Test suite for Get-ActiveRdpSession

.DESCRIPTION
    Validates Get-ActiveRdpSession behavior: session enumeration, CIM session lifecycle,
    pipeline input, error handling, and cross-computer queries.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.1
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+, Pester 5.x
    Permissions:   None (mocks CIM operations)
#>

    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop
}

Describe -Name 'Get-ActiveRdpSession' -Fixture {

    Context -Name 'When querying local computer with active sessions' -Fixture {
        BeforeEach {
            # Mock CimSession object -- returns a mock CimSession instance
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
            }

            # FIX: Mock CimInstance object with required properties
            # Use New-MockObject to create a real CimInstance mock
            $mockCimInstance = New-MockObject -Type 'Microsoft.Management.Infrastructure.CimInstance'

            # Add mock properties using Add-Member (Pester mocks don't have actual CIM properties)
            $mockCimInstance | Add-Member -MemberType NoteProperty -Name 'LogonId' -Value '123456' -Force
            $mockCimInstance | Add-Member -MemberType NoteProperty -Name 'LogonType' -Value 10 -Force
            $mockCimInstance | Add-Member -MemberType NoteProperty -Name 'StartTime' -Value (Get-Date).AddHours(-2) -Force
            $mockCimInstance | Add-Member -MemberType NoteProperty -Name 'AuthenticationPackage' -Value 'Negotiate' -Force

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $mockCimInstance
            }

            # Mock the associated user object
            $mockUserInstance = New-MockObject -Type 'Microsoft.Management.Infrastructure.CimInstance'
            $mockUserInstance | Add-Member -MemberType NoteProperty -Name 'Domain' -Value 'TESTDOMAIN' -Force
            $mockUserInstance | Add-Member -MemberType NoteProperty -Name 'Name' -Value 'testuser' -Force

            Mock -CommandName 'Get-CimAssociatedInstance' -ModuleName 'PSWinOps' -MockWith {
                return $mockUserInstance
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
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
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
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
            }

            # Create mock CimInstance with properties
            $mockCimInstance = New-MockObject -Type 'Microsoft.Management.Infrastructure.CimInstance'
            $mockCimInstance | Add-Member -MemberType NoteProperty -Name 'LogonId' -Value '123456' -Force
            $mockCimInstance | Add-Member -MemberType NoteProperty -Name 'LogonType' -Value 10 -Force
            $mockCimInstance | Add-Member -MemberType NoteProperty -Name 'StartTime' -Value (Get-Date).AddHours(-2) -Force
            $mockCimInstance | Add-Member -MemberType NoteProperty -Name 'AuthenticationPackage' -Value 'Negotiate' -Force

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $mockCimInstance
            }

            $mockUserInstance = New-MockObject -Type 'Microsoft.Management.Infrastructure.CimInstance'
            $mockUserInstance | Add-Member -MemberType NoteProperty -Name 'Domain' -Value 'TESTDOMAIN' -Force
            $mockUserInstance | Add-Member -MemberType NoteProperty -Name 'Name' -Value 'testuser' -Force

            Mock -CommandName 'Get-CimAssociatedInstance' -ModuleName 'PSWinOps' -MockWith {
                return $mockUserInstance
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
