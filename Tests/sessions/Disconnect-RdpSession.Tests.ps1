#Requires -Version 5.1

BeforeAll {
    # Import module
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    $script:mockTsService = [PSCustomObject]@{
        Name = 'TerminalServices'
    }
}

Describe -Name 'Disconnect-RdpSession' -Fixture {
    Context -Name 'When disconnecting a session successfully' -Fixture {
        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{ ReturnValue = 0 }
            }

            Mock -CommandName 'Remove-CimSession' -MockWith {}
        }

        It -Name 'Should return success result object' -Test {
            $result = Disconnect-RdpSession -SessionID 2 -Confirm:$false
            $result.Success | Should -Be $true
            $result.ReturnCode | Should -Be 0
        }

        It -Name 'Should include correct action type' -Test {
            $result = Disconnect-RdpSession -SessionID 2 -Confirm:$false
            $result.Action | Should -Be 'Disconnect'
        }

        It -Name 'Should invoke DisconnectSession method' -Test {
            Disconnect-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-CimMethod' -Times 1 -Exactly
        }

        It -Name 'Should clean up CIM session' -Test {
            Disconnect-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Remove-CimSession' -Times 1 -Exactly
        }
    }

    Context -Name 'When ShouldProcess is declined' -Fixture {
        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {}
            Mock -CommandName 'Invoke-CimMethod' -MockWith {}
        }

        It -Name 'Should not invoke disconnect when WhatIf is specified' -Test {
            Disconnect-RdpSession -SessionID 2 -WhatIf
            Should -Invoke -CommandName 'Invoke-CimMethod' -Times 0 -Exactly
        }

        It -Name 'Should not create CIM session when WhatIf is specified' -Test {
            Disconnect-RdpSession -SessionID 2 -WhatIf
            Should -Invoke -CommandName 'New-CimSession' -Times 0 -Exactly
        }
    }

    Context -Name 'When disconnecting multiple sessions' -Fixture {
        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -MockWith {
                return $script:mockTsService
            }

            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{ ReturnValue = 0 }
            }

            Mock -CommandName 'Remove-CimSession' -MockWith {}
        }

        It -Name 'Should process all session IDs' -Test {
            $result = Disconnect-RdpSession -SessionID 2, 3, 5 -Confirm:$false
            $result.Count | Should -Be 3
        }

        It -Name 'Should invoke method once per session' -Test {
            Disconnect-RdpSession -SessionID 2, 3 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-CimMethod' -Times 2 -Exactly
        }
    }

    Context -Name 'When access is denied' -Fixture {
        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                throw [System.UnauthorizedAccessException]::new('Access denied')
            }
        }

        It -Name 'Should write error and not throw' -Test {
            { Disconnect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
}
