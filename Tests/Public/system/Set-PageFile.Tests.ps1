#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Set-PageFile' {
    BeforeAll {
        # ---- Reusable mock objects ----
        $script:mockCompSystem = [PSCustomObject]@{
            TotalPhysicalMemory      = 17179869184  # 16 GB
            AutomaticManagedPagefile = $true
        }

        $script:mockCompSystem4GB = [PSCustomObject]@{
            TotalPhysicalMemory      = 4294967296  # 4 GB
            AutomaticManagedPagefile = $true
        }

        $script:mockCompSystem8GB = [PSCustomObject]@{
            TotalPhysicalMemory      = 8589934592  # 8 GB
            AutomaticManagedPagefile = $true
        }

        $script:mockCompSystem64GB = [PSCustomObject]@{
            TotalPhysicalMemory      = 68719476736  # 64 GB
            AutomaticManagedPagefile = $true
        }

        $script:mockPageFileSetting = [PSCustomObject]@{
            Name        = 'C:\pagefile.sys'
            InitialSize = 4096
            MaximumSize = 8192
        }

        # ---- Common mocks ----
        Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { $true }

        Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
            $ClassName -eq 'Win32_ComputerSystem'
        } -MockWith { $script:mockCompSystem }

        Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
            $ClassName -eq 'Win32_PageFileSetting'
        } -MockWith { $script:mockPageFileSetting }

        Mock -CommandName 'Set-CimInstance' -ModuleName 'PSWinOps' -MockWith { }
        Mock -CommandName 'Remove-CimInstance' -ModuleName 'PSWinOps' -MockWith { }
        Mock -CommandName 'New-CimInstance' -ModuleName 'PSWinOps' -MockWith { [PSCustomObject]@{} }
        Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith { }
        Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
            [PSCustomObject]@{ RamGB = 16 }
        }
    }

    Context 'AutoCalculate - local - 16 GB RAM' {
        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ComputerSystem'
            } -MockWith { $script:mockCompSystem }

            $script:result = Set-PageFile -AutoCalculate -Confirm:$false
        }

        It -Name 'Should return Configured status' -Test {
            $script:result.Status | Should -Be 'Configured'
        }

        It -Name 'Should set InitialSizeMB to 8192 for 16 GB RAM' -Test {
            $script:result.InitialSizeMB | Should -Be 8192
        }

        It -Name 'Should set MaximumSizeMB to 12288 for 16 GB RAM' -Test {
            $script:result.MaximumSizeMB | Should -Be 12288
        }

        It -Name 'Should set AutoManagedPagefile to false' -Test {
            $script:result.AutoManagedPagefile | Should -BeFalse
        }

        It -Name 'Should report RamTotalGB' -Test {
            $script:result.RamTotalGB | Should -Be 16
        }

        It -Name 'Should have PSTypeName PSWinOps.PageFileConfiguration' -Test {
            $script:result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.PageFileConfiguration'
        }
    }

    Context 'AutoCalculate - 4 GB RAM tier' {
        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ComputerSystem'
            } -MockWith { $script:mockCompSystem4GB }

            $script:result = Set-PageFile -AutoCalculate -Confirm:$false
        }

        It -Name 'Should set InitialSizeMB to 4096 for 4 GB RAM' -Test {
            $script:result.InitialSizeMB | Should -Be 4096
        }

        It -Name 'Should set MaximumSizeMB to 6144 for 4 GB RAM' -Test {
            $script:result.MaximumSizeMB | Should -Be 6144
        }
    }

    Context 'AutoCalculate - 8 GB RAM tier' {
        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ComputerSystem'
            } -MockWith { $script:mockCompSystem8GB }

            $script:result = Set-PageFile -AutoCalculate -Confirm:$false
        }

        It -Name 'Should set InitialSizeMB to 6144 for 8 GB RAM' -Test {
            $script:result.InitialSizeMB | Should -Be 6144
        }

        It -Name 'Should set MaximumSizeMB to 8192 for 8 GB RAM' -Test {
            $script:result.MaximumSizeMB | Should -Be 8192
        }
    }

    Context 'AutoCalculate - 64 GB RAM tier (> 16 GB)' {
        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ComputerSystem'
            } -MockWith { $script:mockCompSystem64GB }

            $script:result = Set-PageFile -AutoCalculate -Confirm:$false
        }

        It -Name 'Should set InitialSizeMB to 8192 for 64 GB RAM' -Test {
            $script:result.InitialSizeMB | Should -Be 8192
        }

        It -Name 'Should set MaximumSizeMB to 16384 for 64 GB RAM' -Test {
            $script:result.MaximumSizeMB | Should -Be 16384
        }
    }

    Context 'Manual explicit sizes' {
        BeforeAll {
            $script:result = Set-PageFile -InitialSizeMB 2048 -MaximumSizeMB 4096 -Confirm:$false
        }

        It -Name 'Should use explicit InitialSizeMB' -Test {
            $script:result.InitialSizeMB | Should -Be 2048
        }

        It -Name 'Should use explicit MaximumSizeMB' -Test {
            $script:result.MaximumSizeMB | Should -Be 4096
        }

        It -Name 'Should return Configured status' -Test {
            $script:result.Status | Should -Be 'Configured'
        }
    }

    Context 'Manual sizes - MaximumSizeMB less than InitialSizeMB' {
        It -Name 'Should throw a terminating error' -Test {
            { Set-PageFile -InitialSizeMB 8192 -MaximumSizeMB 4096 -Confirm:$false } |
                Should -Throw -ExpectedMessage '*must be greater than or equal*'
        }
    }

    Context 'RestoreAutoManaged - local' {
        BeforeAll {
            $script:result = Set-PageFile -RestoreAutoManaged -Confirm:$false
        }

        It -Name 'Should return RestoredAutoManaged status' -Test {
            $script:result.Status | Should -Be 'RestoredAutoManaged'
        }

        It -Name 'Should set AutoManagedPagefile to true' -Test {
            $script:result.AutoManagedPagefile | Should -BeTrue
        }

        It -Name 'Should set InitialSizeMB to 0' -Test {
            $script:result.InitialSizeMB | Should -Be 0
        }

        It -Name 'Should set MaximumSizeMB to 0' -Test {
            $script:result.MaximumSizeMB | Should -Be 0
        }

        It -Name 'Should set RestartRequired to true' -Test {
            $script:result.RestartRequired | Should -BeTrue
        }
    }

    Context 'EnsureCompleteDump with AutoCalculate - 16 GB RAM' {
        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ComputerSystem'
            } -MockWith { $script:mockCompSystem }

            $script:result = Set-PageFile -AutoCalculate -EnsureCompleteDump -Confirm:$false
        }

        It -Name 'Should increase InitialSizeMB to at least RAM + 257 MB' -Test {
            $script:result.InitialSizeMB | Should -BeGreaterOrEqual 16641
        }

        It -Name 'Should adjust MaximumSizeMB to be at least InitialSizeMB' -Test {
            $script:result.MaximumSizeMB | Should -BeGreaterOrEqual $script:result.InitialSizeMB
        }

        It -Name 'Should set EnsureCompleteDump to true in output' -Test {
            $script:result.EnsureCompleteDump | Should -BeTrue
        }
    }

    Context 'EnsureCompleteDump with Manual - sizes already sufficient' {
        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ComputerSystem'
            } -MockWith { $script:mockCompSystem }

            $script:result = Set-PageFile -InitialSizeMB 20000 -MaximumSizeMB 25000 -EnsureCompleteDump -Confirm:$false
        }

        It -Name 'Should keep InitialSizeMB as specified when already sufficient' -Test {
            $script:result.InitialSizeMB | Should -Be 20000
        }

        It -Name 'Should keep MaximumSizeMB as specified' -Test {
            $script:result.MaximumSizeMB | Should -Be 25000
        }
    }

    Context 'Remote computer via ComputerName parameter' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ RamGB = 16 }
            }
        }

        It -Name 'Should use Invoke-Command for remote target' -Test {
            Set-PageFile -ComputerName 'REMOTE01' -AutoCalculate -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Pipeline with multiple computers' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ RamGB = 16 }
            }

            $script:pipeResults = 'SRV01', 'SRV02' | Set-PageFile -AutoCalculate -Confirm:$false
        }

        It -Name 'Should process each computer from the pipeline' -Test {
            $script:pipeResults | Should -HaveCount 2
        }

        It -Name 'Should return correct ComputerName for first server' -Test {
            $script:pipeResults[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return correct ComputerName for second server' -Test {
            $script:pipeResults[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Per-machine failure continues to next machine' {
        BeforeAll {
            $script:callCount = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    throw 'Connection failed'
                }
                [PSCustomObject]@{ RamGB = 16 }
            }
        }

        It -Name 'Should write an error but not terminate the pipeline' -Test {
            $script:failResults = 'BADHOST', 'GOODHOST' |
                Set-PageFile -AutoCalculate -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:capturedError
            $script:capturedError | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Admin check fails' {
        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { $false }
        }

        It -Name 'Should throw a terminating error when not administrator' -Test {
            { Set-PageFile -AutoCalculate -Confirm:$false } |
                Should -Throw -ExpectedMessage '*administrator privileges*'
        }

        AfterAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { $true }
        }
    }

    Context 'Custom DriveLetter parameter' {
        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { $true }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ComputerSystem'
            } -MockWith { $script:mockCompSystem }

            $script:result = Set-PageFile -AutoCalculate -DriveLetter 'D:' -Confirm:$false
        }

        It -Name 'Should use the specified drive letter in the pagefile path' -Test {
            $script:result.PageFilePath | Should -Be 'D:\pagefile.sys'
        }

        It -Name 'Should store the drive letter in DriveLetter property' -Test {
            $script:result.DriveLetter | Should -Be 'D:'
        }
    }

    Context 'WhatIf support' {
        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { $true }
        }

        It -Name 'Should not make changes with -WhatIf' -Test {
            Set-PageFile -AutoCalculate -WhatIf
            Should -Invoke -CommandName 'New-CimInstance' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should not call Set-ItemProperty with -WhatIf' -Test {
            Set-PageFile -AutoCalculate -WhatIf
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Output object properties' {
        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { $true }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ComputerSystem'
            } -MockWith { $script:mockCompSystem }

            $script:result = Set-PageFile -AutoCalculate -Confirm:$false
        }

        It -Name 'Should include RestartRequired as true' -Test {
            $script:result.RestartRequired | Should -BeTrue
        }

        It -Name 'Should include a valid ISO 8601 Timestamp' -Test {
            { [datetime]::Parse($script:result.Timestamp) } | Should -Not -Throw
        }

        It -Name 'Should include default PageFilePath on C drive' -Test {
            $script:result.PageFilePath | Should -Be 'C:\pagefile.sys'
        }
    }
}
