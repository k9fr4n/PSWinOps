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
    Version:       2.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+, Pester 5.x
    Permissions:   None (mocks CIM operations)
#>

    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop
}

Describe -Name 'Get-ActiveRdpSession' -Fixture {

    Context -Name 'When querying local computer with active sessions' -Fixture {

        BeforeEach {
            # Strategy: Do NOT mock New-CimSession - let it create a real local session
            # Mock only Get-CimInstance to return test data

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_LogonSession'
            } -MockWith {
                @(
                    [PSCustomObject]@{
                        LogonId               = '123456'
                        LogonType             = 10
                        StartTime             = (Get-Date).AddHours(-2)
                        AuthenticationPackage = 'Negotiate'
                    }
                )
            }

            Mock -CommandName 'Get-CimAssociatedInstance' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    Domain = 'TESTDOMAIN'
                    Name   = 'testuser'
                }
            }
        }

        It -Name 'Should return PSCustomObject with correct type name' -Test {
            $result = Get-ActiveRdpSession -ErrorAction SilentlyContinue
            $result.PSObject.TypeNames | Should -Contain 'PSWinOps.ActiveRdpSession'
        }

        It -Name 'Should include all required properties' -Test {
            $result = Get-ActiveRdpSession -ErrorAction SilentlyContinue
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'SessionID'
            $result.PSObject.Properties.Name | Should -Contain 'UserName'
            $result.PSObject.Properties.Name | Should -Contain 'LogonTime'
            $result.PSObject.Properties.Name | Should -Contain 'IdleTime'
        }

        It -Name 'Should format username as DOMAIN\User' -Test {
            $result = Get-ActiveRdpSession -ErrorAction SilentlyContinue
            $result.UserName | Should -Be 'TESTDOMAIN\testuser'
        }

        It -Name 'Should query Win32_LogonSession' -Test {
            Get-ActiveRdpSession -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ClassName -eq 'Win32_LogonSession'
            }
        }
    }

    Context -Name 'When no sessions are found' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_LogonSession'
            } -MockWith {
                @()
            }
        }

        It -Name 'Should return no output' -Test {
            $result = Get-ActiveRdpSession -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When access is denied' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                throw [System.UnauthorizedAccessException]::new('Access denied')
            }
        }

        It -Name 'Should write an error and not throw' -Test {
            { Get-ActiveRdpSession -ComputerName 'RemoteServer' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should not return any objects' -Test {
            $result = Get-ActiveRdpSession -ComputerName 'RemoteServer' -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When querying remote computer' -Fixture {

        BeforeEach {
            # For remote queries, we MUST mock New-CimSession
            # Return $null and verify error handling
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                # Simulate successful session creation
                $null
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                @()
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should attempt to create CimSession for remote computer' -Test {
            Get-ActiveRdpSession -ComputerName 'SRV01' -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should process multiple computers' -Test {
            @('SRV01', 'SRV02') | Get-ActiveRdpSession -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }
}
