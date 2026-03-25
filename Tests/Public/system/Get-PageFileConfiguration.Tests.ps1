#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockCompSystem = [PSCustomObject]@{
        TotalPhysicalMemory      = 17179869184
        AutomaticManagedPagefile = $false
    }

    $script:mockCompSystemAutoManaged = [PSCustomObject]@{
        TotalPhysicalMemory      = 17179869184
        AutomaticManagedPagefile = $true
    }

    $script:mockPageFileSetting = [PSCustomObject]@{
        Name        = 'C:\pagefile.sys'
        InitialSize = 4096
        MaximumSize = 8192
    }

    $script:mockPageFileUsage = [PSCustomObject]@{
        Name              = 'C:\pagefile.sys'
        CurrentUsage      = 512
        AllocatedBaseSize = 4096
        PeakUsage         = 1024
    }

    # CimSession mock created inline via New-MockObject
}

Describe 'Get-PageFileConfiguration' {

    Context 'Happy path - local with custom pagefile' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCompSystem
            } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockPageFileSetting
            } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockPageFileUsage
            } -ParameterFilter { $ClassName -eq 'Win32_PageFileUsage' }

            $script:result = Get-PageFileConfiguration
        }

        It -Name 'Should return PSWinOps.PageFileConfiguration type' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.PageFileConfiguration'
        }

        It -Name 'Should set ComputerName to the local machine' -Test {
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should set DriveLetter to C:' -Test {
            $script:result.DriveLetter | Should -Be 'C:'
        }

        It -Name 'Should set InitialSizeMB to 4096' -Test {
            $script:result.InitialSizeMB | Should -Be 4096
        }

        It -Name 'Should set MaximumSizeMB to 8192' -Test {
            $script:result.MaximumSizeMB | Should -Be 8192
        }

        It -Name 'Should set CurrentUsageMB to 512' -Test {
            $script:result.CurrentUsageMB | Should -Be 512
        }

        It -Name 'Should set PeakUsageMB to 1024' -Test {
            $script:result.PeakUsageMB | Should -Be 1024
        }

        It -Name 'Should set AutoManagedPagefile to false' -Test {
            $script:result.AutoManagedPagefile | Should -BeFalse
        }

        It -Name 'Should set Status to Current' -Test {
            $script:result.Status | Should -Be 'Current'
        }

        It -Name 'Should include a valid Timestamp' -Test {
            $script:result.Timestamp | Should -Not -BeNullOrEmpty
            { [datetime]::Parse($script:result.Timestamp) } | Should -Not -Throw
        }
    }

    Context 'Happy path - local auto-managed pagefile' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCompSystemAutoManaged
            } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                # Return nothing - empty pipeline output, so @() wrapper yields Count=0
            } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockPageFileUsage
            } -ParameterFilter { $ClassName -eq 'Win32_PageFileUsage' }

            $script:result = Get-PageFileConfiguration
        }

        It -Name 'Should set PageFilePath to System Managed' -Test {
            $script:result.PageFilePath | Should -Be 'System Managed'
        }

        It -Name 'Should set DriveLetter to N/A' -Test {
            $script:result.DriveLetter | Should -Be 'N/A'
        }

        It -Name 'Should set InitialSizeMB to 0' -Test {
            $script:result.InitialSizeMB | Should -Be 0
        }

        It -Name 'Should set MaximumSizeMB to 0' -Test {
            $script:result.MaximumSizeMB | Should -Be 0
        }

        It -Name 'Should set CurrentUsageMB from usage data' -Test {
            $script:result.CurrentUsageMB | Should -Be 512
        }

        It -Name 'Should set AutoManagedPagefile to true' -Test {
            $script:result.AutoManagedPagefile | Should -BeTrue
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCompSystem
            } -ParameterFilter { $null -ne $CimSession -and $ClassName -eq 'Win32_ComputerSystem' }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockPageFileSetting
            } -ParameterFilter { $null -ne $CimSession -and $ClassName -eq 'Win32_PageFileSetting' }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockPageFileUsage
            } -ParameterFilter { $null -ne $CimSession -and $ClassName -eq 'Win32_PageFileUsage' }

            $script:result = Get-PageFileConfiguration -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return PSWinOps.PageFileConfiguration type' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.PageFileConfiguration'
        }

        It -Name 'Should query Get-CimInstance for remote machine' -Test {
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
            }

            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCompSystem
            } -ParameterFilter { $null -ne $CimSession -and $ClassName -eq 'Win32_ComputerSystem' }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockPageFileSetting
            } -ParameterFilter { $null -ne $CimSession -and $ClassName -eq 'Win32_PageFileSetting' }

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockPageFileUsage
            } -ParameterFilter { $null -ne $CimSession -and $ClassName -eq 'Win32_PageFileUsage' }

            $script:results = 'SRV01', 'SRV02' | Get-PageFileConfiguration
        }

        It -Name 'Should return 2 results' -Test {
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should set ComputerName to SRV01 on first result' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV02 on second result' -Test {
            $script:results[1].ComputerName | Should -Be 'SRV02'
        }

        It -Name 'Should query Get-CimInstance for each machine' -Test {
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -Times 2 -Exactly -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        }
    }

    Context 'Per-machine failure continues' {

        BeforeAll {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                throw 'RPC server is unavailable'
            }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-PageFileConfiguration -ComputerName 'DEADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*DEADHOST*'
        }

        It -Name 'Should not throw with default ErrorAction' -Test {
            { Get-PageFileConfiguration -ComputerName 'DEADHOST' -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-PageFileConfiguration -ComputerName 'DEADHOST' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty string' -Test {
            { Get-PageFileConfiguration -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-PageFileConfiguration -ComputerName $null } | Should -Throw
        }

        It -Name 'Should accept pipeline input for ComputerName' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-PageFileConfiguration'
            $script:paramAttr = $script:cmdInfo.Parameters['ComputerName'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] }
            $script:paramAttr.ValueFromPipeline | Should -BeTrue
        }

        It -Name 'Should accept pipeline by property name for ComputerName' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-PageFileConfiguration'
            $script:paramAttr = $script:cmdInfo.Parameters['ComputerName'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] }
            $script:paramAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }
    }
}
