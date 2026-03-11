#Requires -Version 5.1

BeforeAll {
    # Import module
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    $script:mockTsService = [PSCustomObject]@{
        Name = 'TerminalServices'
    }
}

Describe -Name 'Remove-RdpSession' -Fixture {
    Context -Name 'When removing a session successfully' -Fixture {
        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ReturnValue = 0 }
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should return success result object' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result.Success | Should -Be $true
            $result.ReturnCode | Should -Be 0
        }

        It -Name 'Should include Logoff action type' -Test {
            $result = Remove-RdpSession -SessionID 2 -Confirm:$false
            $result.Action | Should -Be 'Logoff'
        }

        It -Name 'Should invoke LogoffSession method' -Test {
            Remove-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-CimMethod' -Times 1 -Exactly
        }

        It -Name 'Should clean up CIM session' -Test {
            Remove-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Remove-CimSession' -Times 1 -Exactly
        }
    }

    Context -Name 'When Force parameter is used' -Fixture {
        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ReturnValue = 0 }
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should bypass confirmation when Force is specified' -Test {
            $result = Remove-RdpSession -SessionID 2 -Force
            $result.Success | Should -Be $true
        }
    }

    Context -Name 'When ShouldProcess is declined' -Fixture {
        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should not invoke logoff when WhatIf is specified' -Test {
            Remove-RdpSession -SessionID 2 -WhatIf
            Should -Invoke -CommandName 'Invoke-CimMethod' -Times 0 -Exactly
        }
    }

    Context -Name 'When processing pipeline input' -Fixture {
        BeforeEach {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ReturnValue = 0 }
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should process multiple sessions from pipeline' -Test {
            $result = 2, 3, 5 | Remove-RdpSession -Confirm:$false
            $result.Count | Should -Be 3
        }
    }
}
