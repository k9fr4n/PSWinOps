#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Invoke-NativeCommand' {

    Context 'Parameter validation' {
        It 'Should have a mandatory FilePath parameter' {
            $cmd = & (Get-Module -Name $script:ModuleName) { Get-Command -Name 'Invoke-NativeCommand' }
            $param = $cmd.Parameters['FilePath']
            $param | Should -Not -BeNullOrEmpty
            $attr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attr.Mandatory | Should -BeTrue
        }

        It 'Should have an optional ArgumentList parameter' {
            $cmd = & (Get-Module -Name $script:ModuleName) { Get-Command -Name 'Invoke-NativeCommand' }
            $param = $cmd.Parameters['ArgumentList']
            $param | Should -Not -BeNullOrEmpty
            $attr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attr.Mandatory | Should -BeFalse
        }
    }

    Context 'Output structure' {
        It 'Should return an object with Output and ExitCode properties' -Tag 'Integration' -Skip:(-not (Test-Path "$env:SystemRoot\System32\cmd.exe")) {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-NativeCommand -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @('/c', 'echo hello')
            }
            $result.PSObject.Properties.Name | Should -Contain 'Output'
            $result.PSObject.Properties.Name | Should -Contain 'ExitCode'
        }

        It 'Should capture exit code 0 for successful commands' -Tag 'Integration' -Skip:(-not (Test-Path "$env:SystemRoot\System32\cmd.exe")) {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-NativeCommand -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @('/c', 'echo hello')
            }
            $result.ExitCode | Should -Be 0
        }

        It 'Should capture non-zero exit code for failing commands' -Tag 'Integration' -Skip:(-not (Test-Path "$env:SystemRoot\System32\cmd.exe")) {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-NativeCommand -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @('/c', 'exit 42')
            }
            $result.ExitCode | Should -Be 42
        }

        It 'Should capture stdout text in Output' -Tag 'Integration' -Skip:(-not (Test-Path "$env:SystemRoot\System32\cmd.exe")) {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-NativeCommand -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @('/c', 'echo TestOutput123')
            }
            $result.Output | Should -BeLike '*TestOutput123*'
        }
    }
}
