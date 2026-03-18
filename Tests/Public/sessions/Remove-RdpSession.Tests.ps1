#Requires -Version 5.1

BeforeAll {
    # FIX: chemin corrigé (... → ..\..)
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force
    # NOTE: mockTsService supprimé - remplacé par New-MockObject directement dans les mocks
}

Describe -Name 'Remove-RdpSession' -Fixture {

    Context -Name 'When removing a session successfully' -Fixture {
        BeforeEach {
            # FIX: New-MockObject à la place de PSCustomObject
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                # FIX: CimInstance requis car passé à Invoke-CimMethod -InputObject
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimInstance'
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
            # FIX: -ModuleName ajouté
            Should -Invoke -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should clean up CIM session' -Test {
            Remove-RdpSession -SessionID 2 -Confirm:$false
            # FIX: -ModuleName ajouté
            Should -Invoke -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'When Force parameter is used' -Fixture {
        BeforeEach {
            # FIX: New-MockObject à la place de PSCustomObject
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimInstance'
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
            # FIX: -ModuleName ajouté
            Should -Invoke -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context -Name 'When processing pipeline input' -Fixture {
        BeforeEach {
            # FIX: New-MockObject à la place de PSCustomObject
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimInstance'
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
