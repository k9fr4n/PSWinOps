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
            Mock -CommandName 'Invoke-Command' -MockWith { return $script:mockRemoteEntries }
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
            Mock -CommandName 'Invoke-Command' -MockWith { return $script:mockRemoteEntries }
            $script:results = Get-EnvironmentVariable -ComputerName 'SRV01' -VariableName 'PATH'
        }

        It -Name 'Should return only the PATH variable' -Test {
            $script:results | Should -HaveCount 1
            $script:results.Name | Should -Be 'PATH'
        }
    }

    Context 'Remote - Scope Machine only' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith { return $script:mockRemoteEntries }
            Get-EnvironmentVariable -ComputerName 'SRV01' -Scope 'Machine'
        }

        It -Name 'Should call Invoke-Command' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -Times 1 -Exactly
        }
    }

    Context 'Process scope remote warning' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {}
            Mock -CommandName 'Write-Warning' -MockWith {}
            Get-EnvironmentVariable -ComputerName 'SRV01' -Scope 'Process'
        }

        It -Name 'Should write a warning about Process scope on remote' -Test {
            Should -Invoke -CommandName 'Write-Warning' -Times 1 -Exactly
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith { return $script:mockRemoteEntries }
            $script:results = 'SRV01', 'SRV02' | Get-EnvironmentVariable
        }

        It -Name 'Should call Invoke-Command twice' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith { throw 'Connection failed' }
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
