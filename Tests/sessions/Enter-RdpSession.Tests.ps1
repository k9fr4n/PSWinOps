#Requires -Version 5.1

BeforeAll {
    # Import module
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    $script:mockTsService = [PSCustomObject]@{
        Name = 'TerminalServices'
    }

    $script:mockLogonSession = [PSCustomObject]@{
        LogonId = '12345'
    }
}

Describe -Name 'Enter-RdpSession' -Fixture {

    Context -Name 'When entering a session successfully in Control mode' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -MockWith {
                if ($ClassName -eq 'Win32_LogonSession') {
                    return $script:mockLogonSession
                } elseif ($ClassName -eq 'Win32_TerminalService') {
                    return $script:mockTsService
                }
            }

            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{ ReturnValue = 0 }
            }

            Mock -CommandName 'Remove-CimSession' -MockWith {}
        }

        It -Name 'Should return success result object' -Test {
            $result = Enter-RdpSession -SessionID 2 -Confirm:$false
            $result.Success | Should -Be $true
            $result.ReturnCode | Should -Be 0
        }

        It -Name 'Should include RemoteControl action type' -Test {
            $result = Enter-RdpSession -SessionID 2 -Confirm:$false
            $result.Action | Should -Be 'RemoteControl'
        }

        It -Name 'Should default to Control mode' -Test {
            $result = Enter-RdpSession -SessionID 2 -Confirm:$false
            $result.ControlMode | Should -Be 'Control'
        }

        It -Name 'Should invoke RemoteControl method' -Test {
            Enter-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-CimMethod' -Times 1 -Exactly
        }

        It -Name 'Should verify target session exists before attempting shadow' -Test {
            Enter-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Get-CimInstance' -Times 2 -Exactly
        }

        It -Name 'Should clean up CIM session' -Test {
            Enter-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Remove-CimSession' -Times 1 -Exactly
        }
    }

    Context -Name 'When entering a session in View mode' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -MockWith {
                if ($ClassName -eq 'Win32_LogonSession') {
                    return $script:mockLogonSession
                } elseif ($ClassName -eq 'Win32_TerminalService') {
                    return $script:mockTsService
                }
            }

            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{ ReturnValue = 0 }
            }

            Mock -CommandName 'Remove-CimSession' -MockWith {}
        }

        It -Name 'Should set ControlMode to View' -Test {
            $result = Enter-RdpSession -SessionID 2 -ControlMode View -Confirm:$false
            $result.ControlMode | Should -Be 'View'
        }
    }

    Context -Name 'When target session does not exist' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -MockWith {
                if ($ClassName -eq 'Win32_LogonSession') {
                    return $null
                } elseif ($ClassName -eq 'Win32_TerminalService') {
                    return $script:mockTsService
                }
            }

            Mock -CommandName 'Invoke-CimMethod' -MockWith {}

            Mock -CommandName 'Remove-CimSession' -MockWith {}
        }

        It -Name 'Should write error and not attempt shadow connection' -Test {
            Enter-RdpSession -SessionID 999 -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Invoke-CimMethod' -Times 0 -Exactly
        }

        It -Name 'Should return no output when session not found' -Test {
            $result = Enter-RdpSession -SessionID 999 -Confirm:$false -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When ShouldProcess is declined' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {}

            Mock -CommandName 'Invoke-CimMethod' -MockWith {}
        }

        It -Name 'Should not invoke shadow connection when WhatIf is specified' -Test {
            Enter-RdpSession -SessionID 2 -WhatIf
            Should -Invoke -CommandName 'Invoke-CimMethod' -Times 0 -Exactly
        }

        It -Name 'Should not create CIM session when WhatIf is specified' -Test {
            Enter-RdpSession -SessionID 2 -WhatIf
            Should -Invoke -CommandName 'New-CimSession' -Times 0 -Exactly
        }
    }

    Context -Name 'When user rejects the connection request' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -MockWith {
                if ($ClassName -eq 'Win32_LogonSession') {
                    return $script:mockLogonSession
                } elseif ($ClassName -eq 'Win32_TerminalService') {
                    return $script:mockTsService
                }
            }

            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{ ReturnValue = 10 }
            }

            Mock -CommandName 'Remove-CimSession' -MockWith {}
        }

        It -Name 'Should return failure with return code 10' -Test {
            $result = Enter-RdpSession -SessionID 2 -Confirm:$false
            $result.Success | Should -Be $false
            $result.ReturnCode | Should -Be 10
        }

        It -Name 'Should include descriptive error message' -Test {
            $result = Enter-RdpSession -SessionID 2 -Confirm:$false
            $result.Message | Should -BeLike '*User rejected*'
        }
    }

    Context -Name 'When shadow is disabled by Group Policy' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -MockWith {
                if ($ClassName -eq 'Win32_LogonSession') {
                    return $script:mockLogonSession
                } elseif ($ClassName -eq 'Win32_TerminalService') {
                    return $script:mockTsService
                }
            }

            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{ ReturnValue = 11 }
            }

            Mock -CommandName 'Remove-CimSession' -MockWith {}
        }

        It -Name 'Should return failure with return code 11' -Test {
            $result = Enter-RdpSession -SessionID 2 -Confirm:$false
            $result.Success | Should -Be $false
            $result.ReturnCode | Should -Be 11
        }

        It -Name 'Should indicate Group Policy restriction' -Test {
            $result = Enter-RdpSession -SessionID 2 -Confirm:$false
            $result.Message | Should -BeLike '*Group Policy*'
        }
    }

    Context -Name 'When processing pipeline input from Get-ActiveRdpSession' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                [PSCustomObject]@{ ComputerName = $ComputerName }
            }

            Mock -CommandName 'Get-CimInstance' -MockWith {
                if ($ClassName -eq 'Win32_LogonSession') {
                    return $script:mockLogonSession
                } elseif ($ClassName -eq 'Win32_TerminalService') {
                    return $script:mockTsService
                }
            }

            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{ ReturnValue = 0 }
            }

            Mock -CommandName 'Remove-CimSession' -MockWith {}
        }

        It -Name 'Should accept SessionID from pipeline' -Test {
            $mockSession = [PSCustomObject]@{ SessionID = 3; ComputerName = 'SRV01' }
            $result = $mockSession | Enter-RdpSession -Confirm:$false
            $result.SessionID | Should -Be 3
        }
    }

    Context -Name 'When NoUserPrompt switch is specified' -Fixture {

        BeforeEach {
            Mock -CommandName 'New-CimSession' -MockWith {
                [PSCustomObject]@{ ComputerName = 'localhost' }
            }

            Mock -CommandName 'Get-CimInstance' -MockWith {
                if ($ClassName -eq 'Win32_LogonSession') {
                    return $script:mockLogonSession
                } elseif ($ClassName -eq 'Win32_TerminalService') {
                    return $script:mockTsService
                }
            }

            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{ ReturnValue = 0 }
            }

            Mock -CommandName 'Remove-CimSession' -MockWith {}
        }

        It -Name 'Should complete successfully when policy allows silent shadow' -Test {
            $result = Enter-RdpSession -SessionID 2 -NoUserPrompt -Confirm:$false
            $result.Success | Should -Be $true
        }
    }
}
