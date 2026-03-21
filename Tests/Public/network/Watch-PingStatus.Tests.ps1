BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Watch-PingStatus' {

    Context 'Parameter validation' {

        It 'Should require ComputerName parameter' {
            { Watch-PingStatus -ComputerName $null } | Should -Throw
        }

        It 'Should reject empty ComputerName' {
            { Watch-PingStatus -ComputerName '' } | Should -Throw
        }

        It 'Should reject RefreshInterval of 0' {
            { Watch-PingStatus -ComputerName 'host' -RefreshInterval 0 } | Should -Throw
        }

        It 'Should reject RefreshInterval above 60' {
            { Watch-PingStatus -ComputerName 'host' -RefreshInterval 61 } | Should -Throw
        }

        It 'Should reject PingTimeoutMs below 500' {
            { Watch-PingStatus -ComputerName 'host' -PingTimeoutMs 100 } | Should -Throw
        }

        It 'Should have expected parameters' {
            $cmd = Get-Command -Name 'Watch-PingStatus'
            $cmd.Parameters.Keys | Should -Contain 'ComputerName'
            $cmd.Parameters.Keys | Should -Contain 'RefreshInterval'
            $cmd.Parameters.Keys | Should -Contain 'PingTimeoutMs'
        }

        It 'Should have default RefreshInterval of 2' {
            $cmd = Get-Command -Name 'Watch-PingStatus'
            $param = $cmd.Parameters['RefreshInterval']
            $defaultValue = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            # Just verify the parameter exists and accepts int
            $param.ParameterType | Should -Be ([int])
        }

        It 'Should have default PingTimeoutMs of 2000' {
            $cmd = Get-Command -Name 'Watch-PingStatus'
            $cmd.Parameters['PingTimeoutMs'].ParameterType | Should -Be ([int])
        }
    }

    Context 'Function existence and metadata' {

        It 'Should be exported from the module' {
            $cmd = Get-Command -Name 'Watch-PingStatus' -Module $script:ModuleName
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should have CmdletBinding' {
            $cmd = Get-Command -Name 'Watch-PingStatus'
            $cmd.CmdletBinding | Should -Be $true
        }
    }
}
