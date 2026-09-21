#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force
}

Describe -Name 'Get-PSWinOpsFunction' -Fixture {

    Context -Name 'Module integration' -Fixture {

        It -Name 'Should be available after module import' -Test {
            Get-Command -Name 'Get-PSWinOpsFunction' -Module 'PSWinOps' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have correct OutputType attribute' -Test {
            $command = Get-Command -Name 'Get-PSWinOpsFunction'
            $command.OutputType.Name | Should -Contain 'PSWinOps.ModuleFunction'
        }

        It -Name 'Should return one object per exported function' -Test {
            $expected = (Get-Command -Module 'PSWinOps' -CommandType Function).Count
            @(Get-PSWinOpsFunction).Count | Should -Be $expected
        }

        It -Name 'Should tag every object with the correct PSTypeName' -Test {
            $result = Get-PSWinOpsFunction
            $result | Where-Object { $_.PSObject.TypeNames[0] -ne 'PSWinOps.ModuleFunction' } | Should -BeNullOrEmpty
        }

        It -Name 'Should expose Name, Domain, Alias and Synopsis on every object' -Test {
            $result = Get-PSWinOpsFunction
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'Domain'
            $result[0].PSObject.Properties.Name | Should -Contain 'Alias'
            $result[0].PSObject.Properties.Name | Should -Contain 'Synopsis'
        }
    }

    Context -Name 'Domain resolution' -Fixture {

        It -Name 'Should map Get-ComputerUptime to the system domain' -Test {
            (Get-PSWinOpsFunction | Where-Object Name -eq 'Get-ComputerUptime').Domain | Should -Be 'system'
        }

        It -Name 'Should map Get-NTPConfiguration to the ntp domain' -Test {
            (Get-PSWinOpsFunction | Where-Object Name -eq 'Get-NTPConfiguration').Domain | Should -Be 'ntp'
        }

        It -Name 'Should assign a non-empty domain to every domain function' -Test {
            $missing = Get-PSWinOpsFunction | Where-Object { $_.Name -ne 'Get-PSWinOpsFunction' -and [string]::IsNullOrWhiteSpace($_.Domain) }
            $missing | Should -BeNullOrEmpty
        }

        It -Name 'Should leave the root-level meta-function without a domain' -Test {
            (Get-PSWinOpsFunction | Where-Object Name -eq 'Get-PSWinOpsFunction').Domain | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Alias resolution' -Fixture {

        It -Name 'Should resolve the short alias for Get-ComputerUptime' -Test {
            (Get-PSWinOpsFunction | Where-Object Name -eq 'Get-ComputerUptime').Alias | Should -Be 'gcu'
        }

        It -Name 'Should resolve its own short alias' -Test {
            (Get-PSWinOpsFunction | Where-Object Name -eq 'Get-PSWinOpsFunction').Alias | Should -Be 'gpwof'
        }
    }

    Context -Name 'Synopsis resolution' -Fixture {

        It -Name 'Should return a non-empty synopsis for Get-ComputerUptime' -Test {
            (Get-PSWinOpsFunction | Where-Object Name -eq 'Get-ComputerUptime').Synopsis | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Domain filtering' -Fixture {

        It -Name 'Should restrict results to the requested domain' -Test {
            $result = Get-PSWinOpsFunction -Domain 'ntp'
            @($result).Count | Should -Be 5
            $result | Where-Object { $_.Domain -ne 'ntp' } | Should -BeNullOrEmpty
        }

        It -Name 'Should accept pipeline input of domain names' -Test {
            $result = 'ntp', 'network' | Get-PSWinOpsFunction
            @($result).Count | Should -Be 30
            $result.Domain | Should -Contain 'ntp'
            $result.Domain | Should -Contain 'network'
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should reject an unknown domain name' -Test {
            { Get-PSWinOpsFunction -Domain 'nonexistent' } | Should -Throw
        }
    }
}

AfterAll {
    Remove-Module -Name 'PSWinOps' -Force -ErrorAction SilentlyContinue
}
