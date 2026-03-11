#Requires -Version 5.1

BeforeAll {
    <#
.SYNOPSIS
    Pester v5 tests for Remove-RdpSession

.DESCRIPTION
    Unit tests covering session removal functionality, pipeline input,
    ShouldProcess support, and error handling.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+, Pester 5.x
    Permissions:   None -- all external dependencies are mocked
#>

    # Import the module under test
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    # Mock data -- shared across all tests
    $script:mockCimSession = [PSCustomObject]@{
        PSTypeName   = 'Microsoft.Management.Infrastructure.CimSession'
        ComputerName = 'localhost'
        InstanceId   = [guid]::NewGuid()
    }

    $script:mockTsService = [PSCustomObject]@{
        PSTypeName = 'Microsoft.Management.Infrastructure.CimInstance#root/cimv2/TerminalServices/Win32_TerminalService'
        Name       = 'TerminalServices'
        Caption    = 'Terminal Services'
    }

    $script:mockSuccessResult = [PSCustomObject]@{
        PSTypeName  = 'Microsoft.Management.Infrastructure.CimMethodResult'
        ReturnValue = 0
    }

    $script:mockFailureResult = [PSCustomObject]@{
        PSTypeName  = 'Microsoft.Management.Infrastructure.CimMethodResult'
        ReturnValue = 1
    }
}

Describe -Name 'Remove-RdpSession' -Fixture {

    Context -Name 'When removing a session successfully' -Fixture {

        BeforeEach {
            # Module-scoped mocks -- critical for intercepting calls from within the module
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
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.ReturnCode | Should -Be 0
        }

        It -Name 'Should include Logoff action type' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false

            $result.Action | Should -Be 'Logoff'
        }

        It -Name 'Should include expected output properties' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false

            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'SessionID'
            $result.PSObject.Properties.Name | Should -Contain 'Action'
            $result.PSObject.Properties.Name | Should -Contain 'Success'
            $result.PSObject.Properties.Name | Should -Contain 'ReturnCode'
            $result.PSObject.Properties.Name | Should -Contain 'Timestamp'
        }

        It -Name 'Should invoke LogoffSession method with correct session ID' -Test {
            Remove-RdpSession -SessionID 2 -Confirm:$false

            Should -Invoke -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $MethodName -eq 'LogoffSession' -and $Arguments.SessionId -eq 2
            }
        }

        It -Name 'Should clean up CIM session' -Test {
            Remove-RdpSession -SessionID 2 -Confirm:$false

            Should -Invoke -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should create CIM session to correct computer' -Test {
            Remove-RdpSession -SessionID 2 -ComputerName 'SRV01' -Confirm:$false

            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'SRV01'
            }
        }

        It -Name 'Should query Terminal Services namespace' -Test {
            Remove-RdpSession -SessionID 2 -Confirm:$false

            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ClassName -eq 'Win32_TerminalService' -and $Namespace -eq 'root\cimv2\TerminalServices'
            }
        }
    }

    Context -Name 'When Force parameter is used' -Fixture {

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

        It -Name 'Should bypass confirmation when Force is specified' -Test {
            $result = Remove-RdpSession -SessionID 2 -Force

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
        }

        It -Name 'Should invoke logoff method when Force is used' -Test {
            Remove-RdpSession -SessionID 2 -Force

            Should -Invoke -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'When ShouldProcess is declined' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                throw 'New-CimSession should not be called when WhatIf is active'
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                throw 'Invoke-CimMethod should not be called when WhatIf is active'
            }
        }

        It -Name 'Should not invoke logoff when WhatIf is specified' -Test {
            Remove-RdpSession -SessionID 2 -WhatIf

            Should -Invoke -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should not create CIM session when WhatIf is specified' -Test {
            Remove-RdpSession -SessionID 2 -WhatIf

            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context -Name 'When processing pipeline input' -Fixture {

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

        It -Name 'Should process multiple sessions from pipeline' -Test {
            $result = 2, 3, 5 | Remove-RdpSession -Confirm:$false

            $result.Count | Should -Be 3
            $result[0].SessionID | Should -Be 2
            $result[1].SessionID | Should -Be 3
            $result[2].SessionID | Should -Be 5
        }

        It -Name 'Should invoke logoff for each session' -Test {
            2, 3, 5 | Remove-RdpSession -Confirm:$false

            Should -Invoke -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -Times 3 -Exactly
        }

        It -Name 'Should accept pipeline input by property name' -Test {
            $inputObject = [PSCustomObject]@{
                ComputerName = 'SRV01'
                SessionID    = 10
            }

            $result = $inputObject | Remove-RdpSession -Confirm:$false

            $result.ComputerName | Should -Be 'SRV01'
            $result.SessionID | Should -Be 10
        }
    }

    Context -Name 'When Credential parameter is provided' -Fixture {

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

            # Create a mock credential object for testing
            $script:testCredential = [PSCredential]::new(
                'DOMAIN\TestUser',
                [securestring]::new()
            )
        }

        It -Name 'Should pass credential to CIM session' -Test {
            Remove-RdpSession -SessionID 2 -Credential $script:testCredential -Confirm:$false

            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential -and $Credential.UserName -eq 'DOMAIN\TestUser'
            }
        }
    }

    Context -Name 'When logoff operation fails' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCimSession
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockFailureResult
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should return failure result when ReturnValue is non-zero' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false -WarningAction SilentlyContinue

            $result.Success | Should -Be $false
            $result.ReturnCode | Should -Be 1
        }
    }

    Context -Name 'When CIM errors occur' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCimSession
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                $exception = [Microsoft.Management.Infrastructure.CimException]::new('Access denied')
                throw $exception
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should handle CIM exceptions gracefully' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }

        It -Name 'Should clean up CIM session even after error' -Test {
            Remove-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue

            Should -Invoke -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'When access is denied' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                throw [System.UnauthorizedAccessException]::new('Access denied')
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should handle UnauthorizedAccessException' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }
    }
}
