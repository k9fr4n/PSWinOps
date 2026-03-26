#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockRegistryEntries = @(
        [PSCustomObject]@{
            DisplayName     = 'Visual Studio Code'
            DisplayVersion  = '1.87.0'
            Publisher        = 'Microsoft'
            InstallDate     = '20240301'
            InstallLocation = 'C:\Program Files\VSCode'
            UninstallString = 'uninstall.exe'
            EstimatedSize   = 307200
        },
        [PSCustomObject]@{
            DisplayName     = '7-Zip'
            DisplayVersion  = '23.01'
            Publisher        = 'Igor Pavlov'
            InstallDate     = '20240115'
            InstallLocation = 'C:\Program Files\7-Zip'
            UninstallString = 'uninstall.exe'
            EstimatedSize   = 5120
        },
        [PSCustomObject]@{
            DisplayName     = $null
            DisplayVersion  = $null
            Publisher        = $null
            InstallDate     = $null
            InstallLocation = $null
            UninstallString = $null
            EstimatedSize   = $null
        }
    )

    $script:mockRemoteEntries = @(
        [PSCustomObject]@{
            DisplayName     = 'SQL Server 2022'
            DisplayVersion  = '16.0'
            Publisher        = 'Microsoft'
            InstallDate     = '20240201'
            InstallLocation = 'C:\SQL'
            UninstallString = 'uninstall.exe'
            EstimatedSize   = 1048576
            Architecture    = '64-bit'
        }
    )
}

Describe 'Get-InstalledSoftware' {

    Context 'Happy path - local machine' {

        BeforeAll {
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockRegistryEntries
            } -ParameterFilter { $Path -like '*Uninstall*' -and $Path -notlike '*WOW6432*' }

            Mock -CommandName 'Get-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                return @()
            } -ParameterFilter { $Path -like '*WOW6432*' }

            $script:results = Get-InstalledSoftware
        }

        It -Name 'Should return results excluding null DisplayName entries' -Test {
            $script:results | Should -Not -BeNullOrEmpty
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should return results sorted by DisplayName' -Test {
            $script:results[0].DisplayName | Should -Be '7-Zip'
            $script:results[1].DisplayName | Should -Be 'Visual Studio Code'
        }

        It -Name 'Should set correct PSTypeName on each object' -Test {
            foreach ($script:item in $script:results) {
                $script:item.PSObject.TypeNames | Should -Contain 'PSWinOps.InstalledSoftware'
            }
        }

        It -Name 'Should convert InstallDate to datetime' -Test {
            $script:results[0].InstallDate | Should -BeOfType [datetime]
        }

        It -Name 'Should calculate EstimatedSizeMB from KB' -Test {
            $script:results[0].EstimatedSizeMB | Should -Be ([math]::Round(5120 / 1024, 2))
        }

        It -Name 'Should populate Publisher property' -Test {
            $script:results[0].Publisher | Should -Be 'Igor Pavlov'
            $script:results[1].Publisher | Should -Be 'Microsoft'
        }
    }

    Context 'Name filter with wildcard' {

        BeforeAll {
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockRegistryEntries
            } -ParameterFilter { $Path -like '*Uninstall*' -and $Path -notlike '*WOW6432*' }

            Mock -CommandName 'Get-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                return @()
            } -ParameterFilter { $Path -like '*WOW6432*' }

            $script:filteredResults = Get-InstalledSoftware -Name '7*'
        }

        It -Name 'Should return only matching entries' -Test {
            @($script:filteredResults).Count | Should -Be 1
        }

        It -Name 'Should return 7-Zip entry only' -Test {
            $script:filteredResults.DisplayName | Should -Be '7-Zip'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockRemoteEntries
            }

            $script:remoteResults = Get-InstalledSoftware -ComputerName 'SRV01'
        }

        It -Name 'Should use remote execution path for non-local target' -Test {
            $script:remoteResults | Should -Not -BeNullOrEmpty
            $script:remoteResults[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return remote results' -Test {
            $script:remoteResults | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:remoteResults[0].ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockRemoteEntries
            }

            $script:pipelineResults = 'SRV01', 'SRV02' | Get-InstalledSoftware
        }

        It -Name 'Should process each remote machine' -Test {
            @($script:pipelineResults).Count | Should -BeGreaterOrEqual 2
        }

        It -Name 'Should return results from all machines' -Test {
            @($script:pipelineResults).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Per-machine failure continues' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                throw 'Connection refused'
            }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-InstalledSoftware -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should not throw with default ErrorAction' -Test {
            { Get-InstalledSoftware -ComputerName 'BADHOST' -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-InstalledSoftware -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty string' -Test {
            { Get-InstalledSoftware -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-InstalledSoftware -ComputerName $null } | Should -Throw
        }

        It -Name 'Should throw when Name is empty string' -Test {
            { Get-InstalledSoftware -Name '' } | Should -Throw
        }

        It -Name 'Should accept CN alias for ComputerName' -Test {
            $script:paramMeta = (Get-Command -Name 'Get-InstalledSoftware').Parameters['ComputerName']
            $script:paramMeta.Aliases | Should -Contain 'CN'
        }

        It -Name 'Should accept DNSHostName alias for ComputerName' -Test {
            $script:paramMeta = (Get-Command -Name 'Get-InstalledSoftware').Parameters['ComputerName']
            $script:paramMeta.Aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should not have Name alias on ComputerName' -Test {
            $script:paramMeta = (Get-Command -Name 'Get-InstalledSoftware').Parameters['ComputerName']
            $script:paramMeta.Aliases | Should -Not -Contain 'Name'
        }
    }
}
