#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force
}

Describe 'Get-PendingReboot' {

    Context 'Local machine with no reboot pending' {
        BeforeAll {
            Mock -CommandName 'Test-Path' -MockWith { $false }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Name -eq 'PendingFileRenameOperations'
            } -MockWith { $null }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ActiveComputerName*'
            } -MockWith { [PSCustomObject]@{ ComputerName = $env:COMPUTERNAME } }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ComputerName\ComputerName'
            } -MockWith { [PSCustomObject]@{ ComputerName = $env:COMPUTERNAME } }
            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{
                    IsHardRebootPending = $false
                    RebootPending       = $false
                }
            }

            $script:result = Get-PendingReboot
        }

        It -Name 'Returns a PSCustomObject' -Test {
            $script:result | Should -BeOfType [PSCustomObject]
        }

        It -Name 'Returns IsRebootPending as false' -Test {
            $script:result.IsRebootPending | Should -BeFalse
        }

        It -Name 'Returns ComponentBasedServicing as false' -Test {
            $script:result.ComponentBasedServicing | Should -BeFalse
        }

        It -Name 'Returns WindowsUpdate as false' -Test {
            $script:result.WindowsUpdate | Should -BeFalse
        }

        It -Name 'Returns PendingFileRename as false' -Test {
            $script:result.PendingFileRename | Should -BeFalse
        }

        It -Name 'Returns PendingComputerRename as false' -Test {
            $script:result.PendingComputerRename | Should -BeFalse
        }

        It -Name 'Returns CCMClientSDK as false' -Test {
            $script:result.CCMClientSDK | Should -BeFalse
        }

        It -Name 'Returns the local computer name' -Test {
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Returns a valid ISO 8601 Timestamp' -Test {
            $script:result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Local machine with CBS reboot pending' {
        BeforeAll {
            Mock -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*Component Based Servicing*'
            } -MockWith { $true }
            Mock -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*Auto Update*'
            } -MockWith { $false }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Name -eq 'PendingFileRenameOperations'
            } -MockWith { $null }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ActiveComputerName*'
            } -MockWith { [PSCustomObject]@{ ComputerName = $env:COMPUTERNAME } }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ComputerName\ComputerName'
            } -MockWith { [PSCustomObject]@{ ComputerName = $env:COMPUTERNAME } }
            Mock -CommandName 'Invoke-CimMethod' -MockWith { throw 'SCCM not installed' }

            $script:result = Get-PendingReboot
        }

        It -Name 'Returns IsRebootPending as true' -Test {
            $script:result.IsRebootPending | Should -BeTrue
        }

        It -Name 'Returns ComponentBasedServicing as true' -Test {
            $script:result.ComponentBasedServicing | Should -BeTrue
        }

        It -Name 'Returns other registry checks as false' -Test {
            $script:result.WindowsUpdate | Should -BeFalse
            $script:result.PendingFileRename | Should -BeFalse
            $script:result.PendingComputerRename | Should -BeFalse
        }

        It -Name 'Returns CCMClientSDK as null when SCCM unavailable' -Test {
            $script:result.CCMClientSDK | Should -BeNullOrEmpty
        }
    }

    Context 'Local machine with multiple sources pending' {
        BeforeAll {
            Mock -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*Component Based Servicing*'
            } -MockWith { $true }
            Mock -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*Auto Update*'
            } -MockWith { $true }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Name -eq 'PendingFileRenameOperations'
            } -MockWith {
                [PSCustomObject]@{
                    PendingFileRenameOperations = @('\??\C:\old.dll', '\??\C:\new.dll')
                }
            }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ActiveComputerName*'
            } -MockWith { [PSCustomObject]@{ ComputerName = 'OLDNAME' } }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ComputerName\ComputerName'
            } -MockWith { [PSCustomObject]@{ ComputerName = 'NEWNAME' } }
            Mock -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{
                    IsHardRebootPending = $true
                    RebootPending       = $false
                }
            }

            $script:result = Get-PendingReboot
        }

        It -Name 'Returns IsRebootPending as true' -Test {
            $script:result.IsRebootPending | Should -BeTrue
        }

        It -Name 'Returns all individual sources as true' -Test {
            $script:result.ComponentBasedServicing | Should -BeTrue
            $script:result.WindowsUpdate | Should -BeTrue
            $script:result.PendingFileRename | Should -BeTrue
            $script:result.PendingComputerRename | Should -BeTrue
            $script:result.CCMClientSDK | Should -BeTrue
        }
    }

    Context 'Remote single machine' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                @{
                    ComponentBasedServicing = $true
                    WindowsUpdate           = $false
                    PendingFileRename       = $false
                    PendingComputerRename   = $false
                    CCMClientSDK            = $false
                }
            }

            $script:result = Get-PendingReboot -ComputerName 'REMOTE01'
        }

        It -Name 'Returns the correct remote computer name' -Test {
            $script:result.ComputerName | Should -Be 'REMOTE01'
        }

        It -Name 'Returns correct reboot status from remote data' -Test {
            $script:result.IsRebootPending | Should -BeTrue
            $script:result.ComponentBasedServicing | Should -BeTrue
            $script:result.WindowsUpdate | Should -BeFalse
        }

        It -Name 'Calls Invoke-Command exactly once' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -Times 1 -Exactly
        }
    }

    Context 'Pipeline with multiple remote machines' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                @{
                    ComponentBasedServicing = $false
                    WindowsUpdate           = $false
                    PendingFileRename       = $false
                    PendingComputerRename   = $false
                    CCMClientSDK            = $null
                }
            }

            $script:results = 'SERVER01', 'SERVER02', 'SERVER03' | Get-PendingReboot
        }

        It -Name 'Returns a result for each piped machine' -Test {
            $script:results | Should -HaveCount 3
        }

        It -Name 'Preserves correct computer names from pipeline' -Test {
            $script:results[0].ComputerName | Should -Be 'SERVER01'
            $script:results[1].ComputerName | Should -Be 'SERVER02'
            $script:results[2].ComputerName | Should -Be 'SERVER03'
        }

        It -Name 'Calls Invoke-Command once per piped machine' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -Times 3 -Exactly
        }
    }

    Context 'Per-machine failure isolation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ParameterFilter {
                $ComputerName -eq 'GOODSERVER'
            } -MockWith {
                @{
                    ComponentBasedServicing = $false
                    WindowsUpdate           = $false
                    PendingFileRename       = $false
                    PendingComputerRename   = $false
                    CCMClientSDK            = $null
                }
            }
            Mock -CommandName 'Invoke-Command' -ParameterFilter {
                $ComputerName -eq 'BADSERVER'
            } -MockWith { throw 'Connection refused' }

            $script:results = Get-PendingReboot -ComputerName 'GOODSERVER', 'BADSERVER' -ErrorAction SilentlyContinue
        }

        It -Name 'Returns result only for the successful machine' -Test {
            $script:results | Should -HaveCount 1
        }

        It -Name 'Returns the correct computer name for the successful result' -Test {
            $script:results.ComputerName | Should -Be 'GOODSERVER'
        }

        It -Name 'Attempts connection to both machines' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -Times 2 -Exactly
        }
    }

    Context 'SCCM client not available' {
        BeforeAll {
            Mock -CommandName 'Test-Path' -MockWith { $false }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Name -eq 'PendingFileRenameOperations'
            } -MockWith { $null }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ActiveComputerName*'
            } -MockWith { [PSCustomObject]@{ ComputerName = $env:COMPUTERNAME } }
            Mock -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ComputerName\ComputerName'
            } -MockWith { [PSCustomObject]@{ ComputerName = $env:COMPUTERNAME } }
            Mock -CommandName 'Invoke-CimMethod' -MockWith { throw 'Invalid namespace ROOT\ccm\ClientSDK' }

            $script:result = Get-PendingReboot
        }

        It -Name 'Returns CCMClientSDK as null when SCCM is missing' -Test {
            $script:result.CCMClientSDK | Should -BeNullOrEmpty
        }

        It -Name 'Does not flag IsRebootPending from SCCM failure alone' -Test {
            $script:result.IsRebootPending | Should -BeFalse
        }

        It -Name 'Completes without throwing an error' -Test {
            { Get-PendingReboot } | Should -Not -Throw
        }
    }

    Context 'Parameter validation' {
        It -Name 'Throws when ComputerName is an empty string' -Test {
            { Get-PendingReboot -ComputerName '' } | Should -Throw
        }

        It -Name 'Throws when ComputerName is null' -Test {
            { Get-PendingReboot -ComputerName $null } | Should -Throw
        }
    }
}
