#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables are used across Pester scopes via script: prefix'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Show-DnsQueryMonitor' {

    Context 'Parameter validation' {
        BeforeAll {
            $script:commandInfo = Get-Command -Name 'Show-DnsQueryMonitor' -Module $script:ModuleName
        }

        It -Name 'Should have CmdletBinding' -Test {
            $script:commandInfo.CmdletBinding | Should -BeTrue
        }

        It -Name 'Should have OutputType void' -Test {
            $script:commandInfo.OutputType.Name | Should -Contain 'Void'
        }

        It -Name 'Should have RefreshInterval with ValidateRange 1-30' -Test {
            $param = $script:commandInfo.Parameters['RefreshInterval']
            $param | Should -Not -BeNullOrEmpty
            $range = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $range.MinRange | Should -Be 1
            $range.MaxRange | Should -Be 30
        }

        It -Name 'Should have DomainFilter parameter' -Test {
            $script:commandInfo.Parameters['DomainFilter'] | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have MaxLines with ValidateRange 10-500' -Test {
            $param = $script:commandInfo.Parameters['MaxLines']
            $param | Should -Not -BeNullOrEmpty
            $range = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $range.MinRange | Should -Be 10
            $range.MaxRange | Should -Be 500
        }

        It -Name 'Should have NoClear switch' -Test {
            $param = $script:commandInfo.Parameters['NoClear']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -BeTrue
        }

        It -Name 'Should have NoColor switch' -Test {
            $param = $script:commandInfo.Parameters['NoColor']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -BeTrue
        }

        It -Name 'Should reject RefreshInterval of 0' -Test {
            { Show-DnsQueryMonitor -RefreshInterval 0 } | Should -Throw
        }

        It -Name 'Should reject MaxLines below 10' -Test {
            { Show-DnsQueryMonitor -MaxLines 5 } | Should -Throw
        }
    }

    Context 'Comment-based help' {
        BeforeAll {
            $script:helpInfo = Get-Help -Name 'Show-DnsQueryMonitor' -Full
        }

        It -Name 'Should have a synopsis' -Test {
            $script:helpInfo.Synopsis.Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a description' -Test {
            ($script:helpInfo.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have at least 3 examples' -Test {
            $script:helpInfo.Examples.Example.Count | Should -BeGreaterOrEqual 3
        }

        It -Name 'Should have Author in NOTES' -Test {
            ($script:helpInfo.alertSet | Out-String) | Should -Match 'Franck SALLET'
        }

        It -Name 'Should document all parameters' -Test {
            $expected = @('RefreshInterval', 'DomainFilter', 'MaxLines', 'NoClear', 'NoColor')
            foreach ($paramName in $expected) {
                $script:helpInfo.Parameters.Parameter |
                    Where-Object { $_.Name -eq $paramName } |
                    Should -Not -BeNullOrEmpty -Because "Parameter '$paramName' should be documented"
            }
        }
    }

    Context 'Interactive controls — function source inspection' {
        BeforeAll {
            $script:funcBody = (Get-Command -Name 'Show-DnsQueryMonitor' -Module $script:ModuleName).ScriptBlock.ToString()
        }

        It -Name 'Should contain Q/Escape quit handling' -Test {
            $script:funcBody | Should -Match "'Escape'"
            $script:funcBody | Should -Match "'Q'"
        }

        It -Name 'Should contain Pause toggle' -Test {
            $script:funcBody | Should -Match "'P'"
        }

        It -Name 'Should contain Clear handler' -Test {
            $script:funcBody | Should -Match "'C'"
        }

        It -Name 'Should contain Sort cycling' -Test {
            $script:funcBody | Should -Match "'S'"
        }

        It -Name 'Should contain Type filter cycling' -Test {
            $script:funcBody | Should -Match "'T'"
        }

        It -Name 'Should contain Filter input' -Test {
            $script:funcBody | Should -Match "'F'"
        }

        It -Name 'Should contain DNS Client log name' -Test {
            $script:funcBody | Should -Match 'Microsoft-Windows-DNS-Client/Operational'
        }

        It -Name 'Should contain ANSI escape sequences' -Test {
            $script:funcBody | Should -Match '\[char\]27'
        }

        It -Name 'Should restore console state in finally block' -Test {
            $script:funcBody | Should -Match 'CursorVisible'
            $script:funcBody | Should -Match 'TreatControlCAsInput'
        }
    }
}