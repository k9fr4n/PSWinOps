#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-PendingReboot' {

    Context 'When local machine has no reboot pending' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $false }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*Session Manager*'
            } -MockWith {
                [PSCustomObject]@{ PendingFileRenameOperations = $null }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ActiveComputerName*'
            } -MockWith {
                [PSCustomObject]@{ ComputerName = 'TESTPC' }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ComputerName\ComputerName*'
            } -MockWith {
                [PSCustomObject]@{ ComputerName = 'TESTPC' }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-CimMethod' -MockWith {
                throw 'SCCM client not installed'
            }

            $script:result = Get-PendingReboot -ComputerName 'localhost'
        }

        It -Name 'Should return PSWinOps.PendingReboot type' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.PendingReboot'
        }

        It -Name 'Should report IsRebootPending as false' -Test {
            $script:result.IsRebootPending | Should -BeFalse
        }

        It -Name 'Should report CBS as false' -Test {
            $script:result.ComponentBasedServicing | Should -BeFalse
        }

        It -Name 'Should report WindowsUpdate as false' -Test {
            $script:result.WindowsUpdate | Should -BeFalse
        }

        It -Name 'Should report PendingFileRename as false' -Test {
            $script:result.PendingFileRename | Should -BeFalse
        }

        It -Name 'Should report PendingComputerRename as false' -Test {
            $script:result.PendingComputerRename | Should -BeFalse
        }

        It -Name 'Should report CCMClientSDK as null' -Test {
            $script:result.CCMClientSDK | Should -BeNullOrEmpty
        }

        It -Name 'Should set ComputerName to localhost' -Test {
            $script:result.ComputerName | Should -Be 'localhost'
        }

        It -Name 'Should include a Timestamp' -Test {
            $script:result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When local machine has CBS reboot pending' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*Component Based Servicing*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*WindowsUpdate*'
            } -MockWith { $false }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*Session Manager*'
            } -MockWith {
                [PSCustomObject]@{ PendingFileRenameOperations = $null }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ActiveComputerName*'
            } -MockWith {
                [PSCustomObject]@{ ComputerName = 'TESTPC' }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ComputerName\ComputerName*'
            } -MockWith {
                [PSCustomObject]@{ ComputerName = 'TESTPC' }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-CimMethod' -MockWith {
                throw 'SCCM client not installed'
            }

            $script:result = Get-PendingReboot -ComputerName 'localhost'
        }

        It -Name 'Should report IsRebootPending as true' -Test {
            $script:result.IsRebootPending | Should -BeTrue
        }

        It -Name 'Should report only CBS as true' -Test {
            $script:result.ComponentBasedServicing | Should -BeTrue
        }

        It -Name 'Should report WindowsUpdate as false' -Test {
            $script:result.WindowsUpdate | Should -BeFalse
        }

        It -Name 'Should report PendingFileRename as false' -Test {
            $script:result.PendingFileRename | Should -BeFalse
        }

        It -Name 'Should report PendingComputerRename as false' -Test {
            $script:result.PendingComputerRename | Should -BeFalse
        }

        It -Name 'Should report CCMClientSDK as null' -Test {
            $script:result.CCMClientSDK | Should -BeNullOrEmpty
        }
    }

    Context 'When local machine has all reboots pending' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*Component Based Servicing*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*WindowsUpdate*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*Session Manager*'
            } -MockWith {
                [PSCustomObject]@{
                    PendingFileRenameOperations = @(
                        '\??\C:\temp\old.dll',
                        '\??\C:\temp\new.dll'
                    )
                }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ActiveComputerName*'
            } -MockWith {
                [PSCustomObject]@{ ComputerName = 'OLDNAME' }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ComputerName\ComputerName*'
            } -MockWith {
                [PSCustomObject]@{ ComputerName = 'NEWNAME' }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-CimMethod' -MockWith {
                [PSCustomObject]@{
                    IsHardRebootPending = $true
                    RebootPending       = $true
                }
            }

            $script:result = Get-PendingReboot -ComputerName 'localhost'
        }

        It -Name 'Should report IsRebootPending as true' -Test {
            $script:result.IsRebootPending | Should -BeTrue
        }

        It -Name 'Should report CBS as true' -Test {
            $script:result.ComponentBasedServicing | Should -BeTrue
        }

        It -Name 'Should report WindowsUpdate as true' -Test {
            $script:result.WindowsUpdate | Should -BeTrue
        }

        It -Name 'Should report PendingFileRename as true' -Test {
            $script:result.PendingFileRename | Should -BeTrue
        }

        It -Name 'Should report PendingComputerRename as true' -Test {
            $script:result.PendingComputerRename | Should -BeTrue
        }

        It -Name 'Should report CCMClientSDK as true' -Test {
            $script:result.CCMClientSDK | Should -BeTrue
        }
    }

    Context 'When checking a single remote machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @{
                    ComponentBasedServicing = $false
                    WindowsUpdate           = $true
                    PendingFileRename       = $false
                    PendingComputerRename   = $false
                    CCMClientSDK            = $null
                }
            }

            $script:result = Get-PendingReboot -ComputerName 'SERVER01'
        }

        It -Name 'Should report IsRebootPending as true due to WU' -Test {
            $script:result.IsRebootPending | Should -BeTrue
        }

        It -Name 'Should report only WindowsUpdate as true' -Test {
            $script:result.WindowsUpdate | Should -BeTrue
            $script:result.ComponentBasedServicing | Should -BeFalse
        }

        It -Name 'Should set ComputerName to SERVER01' -Test {
            $script:result.ComputerName | Should -Be 'SERVER01'
        }

        It -Name 'Should return PSWinOps.PendingReboot type' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.PendingReboot'
        }

        It -Name 'Should return data matching mock not real machine' -Test {
            $script:result.CCMClientSDK | Should -BeNullOrEmpty
            $script:result.PendingFileRename | Should -BeFalse
            $script:result.PendingComputerRename | Should -BeFalse
        }
    }

    Context 'When checking multiple machines via pipeline' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @{
                    ComponentBasedServicing = $false
                    WindowsUpdate           = $false
                    PendingFileRename       = $false
                    PendingComputerRename   = $false
                    CCMClientSDK            = $null
                }
            }

            $script:results = @('SERVER01', 'SERVER02', 'SERVER03') | Get-PendingReboot
        }

        It -Name 'Should return one result per machine' -Test {
            @($script:results).Count | Should -Be 3
        }

        It -Name 'Should preserve computer names from pipeline' -Test {
            $script:results[0].ComputerName | Should -Be 'SERVER01'
            $script:results[1].ComputerName | Should -Be 'SERVER02'
            $script:results[2].ComputerName | Should -Be 'SERVER03'
        }

        It -Name 'Should report no reboot pending for all machines' -Test {
            $script:results | ForEach-Object -Process {
                $_.IsRebootPending | Should -BeFalse
            }
        }

        It -Name 'Should return typed objects for all machines' -Test {
            $script:results | ForEach-Object -Process {
                $_.PSObject.TypeNames | Should -Contain 'PSWinOps.PendingReboot'
            }
        }
    }

    Context 'When a remote machine fails with an error' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                throw 'WinRM connection failed'
            }
        }

        It -Name 'Should write a terminating error with ErrorAction Stop' -Test {
            { Get-PendingReboot -ComputerName 'BADSERVER' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADSERVER*'
        }

        It -Name 'Should not throw with default ErrorAction' -Test {
            { Get-PendingReboot -ComputerName 'BADSERVER' -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-PendingReboot -ComputerName 'BADSERVER' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'When SCCM client is unavailable on local machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*Component Based Servicing*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*WindowsUpdate*'
            } -MockWith { $false }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*Session Manager*'
            } -MockWith {
                [PSCustomObject]@{ PendingFileRenameOperations = $null }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ActiveComputerName*'
            } -MockWith {
                [PSCustomObject]@{ ComputerName = 'TESTPC' }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -ParameterFilter {
                $Path -like '*ComputerName\ComputerName*'
            } -MockWith {
                [PSCustomObject]@{ ComputerName = 'TESTPC' }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-CimMethod' -MockWith {
                throw 'Invalid namespace ROOT\ccm\ClientSDK'
            }

            $script:result = Get-PendingReboot -ComputerName 'localhost'
        }

        It -Name 'Should set CCMClientSDK to null when SCCM is unavailable' -Test {
            $script:result.CCMClientSDK | Should -BeNullOrEmpty
        }

        It -Name 'Should still report reboot pending from other sources' -Test {
            $script:result.IsRebootPending | Should -BeTrue
        }

        It -Name 'Should report CBS as the pending source' -Test {
            $script:result.ComponentBasedServicing | Should -BeTrue
        }

        It -Name 'Should not fail the overall check' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject empty string for ComputerName' -Test {
            { Get-PendingReboot -ComputerName '' } | Should -Throw
        }

        It -Name 'Should reject null for ComputerName' -Test {
            { Get-PendingReboot -ComputerName $null } | Should -Throw
        }

        It -Name 'Should have a Credential parameter' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-PendingReboot'
            $script:cmdInfo.Parameters.ContainsKey('Credential') | Should -BeTrue
        }

        It -Name 'Should have CmdletBinding attribute' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-PendingReboot'
            $script:cmdInfo.CmdletBinding | Should -BeTrue
        }

        It -Name 'Should accept pipeline input for ComputerName' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-PendingReboot'
            $script:paramAttr = $script:cmdInfo.Parameters['ComputerName'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] }
            $script:paramAttr.ValueFromPipeline | Should -BeTrue
        }

        It -Name 'Should accept pipeline input by property name for ComputerName' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-PendingReboot'
            $script:paramAttr = $script:cmdInfo.Parameters['ComputerName'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] }
            $script:paramAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }
    }
}
