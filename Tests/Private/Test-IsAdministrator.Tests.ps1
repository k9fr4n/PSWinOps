#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe -Name 'Test-IsAdministrator' -Fixture {

    Context -Name 'When running as Administrator' -Fixture {

        BeforeAll {
            # Call private function via module scope
            $script:result = & (Get-Module -Name 'PSWinOps') { Test-IsAdministrator }
        }

        It -Name 'Should return a boolean value' -Test {
            $script:result | Should -BeOfType [bool]
        }
    }

    Context -Name 'Integration - matches .NET principal check' -Tag 'Integration' -Fixture {

        It -Name 'Should return the same value as a direct .NET check' -Test {
            $expected = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator
            )
            $actual = & (Get-Module -Name 'PSWinOps') { Test-IsAdministrator }
            $actual | Should -Be $expected
        }
    }
}
