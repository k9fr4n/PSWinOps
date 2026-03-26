#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-EnvironmentVariable' {

    BeforeAll {
        $script:mockRemoteEntries = @(
            [PSCustomObject]@{ Name = 'COMPUTERNAME'; Value = 'SRV01'; Scope = 'Machine' },
            [PSCustomObject]@{ Name = 'PATH'; Value = 'C:\Windows'; Scope = 'Machine' },
            [PSCustomObject]@{ Name = 'TEMP'; Value = 'C:\Windows\Temp'; Scope = 'Machine' }
        )
    }

    Context 'Remote - all scopes' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:results = Get-EnvironmentVariable -ComputerName 'SRV01'
        }

        It -Name 'Should return PSWinOps.EnvironmentVariable type' -Test {
            $script:results[0].PSObject.TypeNames | Should -Contain 'PSWinOps.EnvironmentVariable'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results | ForEach-Object -Process {
                $_.ComputerName | Should -Be 'SRV01'
            }
        }

        It -Name 'Should return results sorted by Name' -Test {
            $script:names = $script:results | Select-Object -ExpandProperty Name
            $script:expected = $script:names | Sort-Object
            $script:names | Should -Be $script:expected
        }
    }

    Context 'Remote - VariableName filter' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:results = Get-EnvironmentVariable -ComputerName 'SRV01' -VariableName 'PATH'
        }

        It -Name 'Should return only the PATH variable' -Test {
            $script:results | Should -HaveCount 1
            $script:results.Name | Should -Be 'PATH'
        }
    }

    Context 'Remote - Scope Machine only' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:scopeResults = Get-EnvironmentVariable -ComputerName 'SRV01' -Scope 'Machine'
        }

        It -Name 'Should return results from the remote machine' -Test {
            $script:scopeResults | Should -Not -BeNullOrEmpty
            $script:scopeResults[0].ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Process scope remote warning' {

        BeforeAll {
            $script:processResult = Get-EnvironmentVariable -ComputerName 'SRV01' -Scope 'Process' -WarningVariable warnVar 3>$null
            $script:warningMessages = $warnVar
        }

        It -Name 'Should write a warning about Process scope on remote' -Test {
            $script:warningMessages | Should -Not -BeNullOrEmpty
            "$($script:warningMessages[0])" | Should -BeLike '*Process scope*'
        }

        It -Name 'Should not return any results' -Test {
            $script:processResult | Should -BeNullOrEmpty
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:results = 'SRV01', 'SRV02' | Get-EnvironmentVariable
        }

        It -Name 'Should return results from multiple machines' -Test {
            @($script:results).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-EnvironmentVariable -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-EnvironmentVariable -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-EnvironmentVariable -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when VariableName is empty' -Test {
            { Get-EnvironmentVariable -VariableName '' } | Should -Throw
        }

        It -Name 'Should throw when Scope is invalid' -Test {
            { Get-EnvironmentVariable -Scope 'Invalid' } | Should -Throw
        }
    }
}
