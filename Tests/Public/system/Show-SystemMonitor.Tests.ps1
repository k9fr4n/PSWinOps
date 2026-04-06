#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Show-SystemMonitor' -Fixture {

    Context -Name 'Function availability' -Fixture {

        It -Name 'Should be exported from the module' -Test {
            Get-Command -Name 'Show-SystemMonitor' -Module 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have CmdletBinding' -Test {
            $cmd = Get-Command -Name 'Show-SystemMonitor'
            $cmd.CmdletBinding | Should -BeTrue
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should have RefreshInterval parameter with range 1-60' -Test {
            $param = (Get-Command -Name 'Show-SystemMonitor').Parameters['RefreshInterval']
            $param | Should -Not -BeNullOrEmpty
            $rangeAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $rangeAttr.MinRange | Should -Be 1
            $rangeAttr.MaxRange | Should -Be 60
        }

        It -Name 'Should have ProcessCount parameter with range 5-100' -Test {
            $param = (Get-Command -Name 'Show-SystemMonitor').Parameters['ProcessCount']
            $param | Should -Not -BeNullOrEmpty
            $rangeAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $rangeAttr.MinRange | Should -Be 5
            $rangeAttr.MaxRange | Should -Be 100
        }

        It -Name 'Should have NoColor switch parameter' -Test {
            $param = (Get-Command -Name 'Show-SystemMonitor').Parameters['NoColor']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It -Name 'Should default RefreshInterval to 2' -Test {
            $param = (Get-Command -Name 'Show-SystemMonitor').Parameters['RefreshInterval']
            $param.DefaultValue | Should -Be 2
        }

        It -Name 'Should default ProcessCount to 25' -Test {
            $param = (Get-Command -Name 'Show-SystemMonitor').Parameters['ProcessCount']
            $param.DefaultValue | Should -Be 25
        }
    }

    Context -Name 'Help documentation' -Fixture {

        BeforeAll {
            $script:help = Get-Help -Name 'Show-SystemMonitor' -Full
        }

        It -Name 'Should have a synopsis' -Test {
            $script:help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a description' -Test {
            $script:help.Description | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have at least 3 examples' -Test {
            @($script:help.Examples.Example).Count | Should -BeGreaterOrEqual 3
        }

        It -Name 'Should document all parameters' -Test {
            $paramNames = @($script:help.Parameters.Parameter | Select-Object -ExpandProperty 'Name')
            $paramNames | Should -Contain 'RefreshInterval'
            $paramNames | Should -Contain 'ProcessCount'
            $paramNames | Should -Contain 'NoColor'
        }
    }

    Context -Name 'ISE detection' -Tag 'Integration' -Fixture {

        It -Name 'Should write error when running in ISE' -Test {
            # Can only be tested when actually in ISE; skip in CI
            Set-ItResult -Skipped -Because 'Requires ISE host to test'
        }
    }
}
