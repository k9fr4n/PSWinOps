BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Measure-NetworkLatency' {

    Context 'Happy path - all pings succeed' {

        BeforeEach {
            $script:pingCount = 0
            $mockPingSender = [PSCustomObject]@{}
            $mockPingSender | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                param($target, $timeout, $buffer, $options)
                $script:pingCount++
                [PSCustomObject]@{
                    Status       = [System.Net.NetworkInformation.IPStatus]::Success
                    RoundtripTime = 10 + ($script:pingCount % 5)
                    Address      = [System.Net.IPAddress]::Parse('8.8.8.8')
                }
            }
            $mockPingSender | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockPingSender
            } -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith { }
        }

        It 'Should return latency statistics' {
            $result = Measure-NetworkLatency -ComputerName '8.8.8.8' -Count 5
            $result.Sent | Should -Be 5
            $result.Received | Should -Be 5
            $result.Lost | Should -Be 0
            $result.LossPercent | Should -Be 0.0
        }

        It 'Should include PSTypeName PSWinOps.NetworkLatency' {
            $result = Measure-NetworkLatency -ComputerName '8.8.8.8' -Count 3
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.NetworkLatency'
        }

        It 'Should compute min/max/avg values' {
            $result = Measure-NetworkLatency -ComputerName '8.8.8.8' -Count 5
            $result.MinMs | Should -Not -BeNullOrEmpty
            $result.MaxMs | Should -Not -BeNullOrEmpty
            $result.AvgMs | Should -Not -BeNullOrEmpty
            $result.MinMs | Should -BeLessOrEqual $result.MaxMs
        }

        It 'Should compute jitter (standard deviation)' {
            $result = Measure-NetworkLatency -ComputerName '8.8.8.8' -Count 5
            $result.JitterMs | Should -Not -BeNullOrEmpty
            $result.JitterMs | Should -BeGreaterOrEqual 0
        }

        It 'Should include resolved IP address' {
            $result = Measure-NetworkLatency -ComputerName '8.8.8.8' -Count 3
            $result.IPAddress | Should -Be '8.8.8.8'
        }

        It 'Should include ComputerName and Timestamp' {
            $result = Measure-NetworkLatency -ComputerName 'myhost' -Count 3
            $result.ComputerName | Should -Be 'myhost'
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'All pings fail (100% packet loss)' {

        BeforeEach {
            $mockPingSender = [PSCustomObject]@{}
            $mockPingSender | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                param($target, $timeout, $buffer, $options)
                [PSCustomObject]@{
                    Status        = [System.Net.NetworkInformation.IPStatus]::TimedOut
                    RoundtripTime = 0
                    Address       = $null
                }
            }
            $mockPingSender | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockPingSender
            } -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith { }
        }

        It 'Should report 100% packet loss' {
            $result = Measure-NetworkLatency -ComputerName 'unreachable' -Count 3
            $result.LossPercent | Should -Be 100.0
            $result.Received | Should -Be 0
            $result.Lost | Should -Be 3
        }

        It 'Should have null latency stats on total loss' {
            $result = Measure-NetworkLatency -ComputerName 'unreachable' -Count 3
            $result.MinMs | Should -BeNullOrEmpty
            $result.MaxMs | Should -BeNullOrEmpty
            $result.AvgMs | Should -BeNullOrEmpty
        }
    }

    Context 'Pipeline and multiple hosts' {

        BeforeEach {
            $mockPingSender = [PSCustomObject]@{}
            $mockPingSender | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                param($target, $timeout, $buffer, $options)
                [PSCustomObject]@{
                    Status        = [System.Net.NetworkInformation.IPStatus]::Success
                    RoundtripTime = 5
                    Address       = [System.Net.IPAddress]::Parse('1.1.1.1')
                }
            }
            $mockPingSender | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockPingSender
            } -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith { }
        }

        It 'Should return one result per host' {
            $result = Measure-NetworkLatency -ComputerName 'host1', 'host2' -Count 3
            $result.Count | Should -Be 2
        }

        It 'Should support pipeline input' {
            $result = 'host1', 'host2', 'host3' | Measure-NetworkLatency -Count 2
            $result.Count | Should -Be 3
        }
    }

    Context 'Parameter validation' {

        It 'Should reject Count of 0' {
            { Measure-NetworkLatency -ComputerName 'host' -Count 0 } | Should -Throw
        }

        It 'Should reject Count above 1000' {
            { Measure-NetworkLatency -ComputerName 'host' -Count 1001 } | Should -Throw
        }

        It 'Should reject empty ComputerName' {
            { Measure-NetworkLatency -ComputerName '' } | Should -Throw
        }

        It 'Should reject BufferSize of 0' {
            { Measure-NetworkLatency -ComputerName 'host' -BufferSize 0 } | Should -Throw
        }
    }

    Context 'Integration' -Tag 'Integration' {

        It 'Should ping localhost successfully' -Skip:(-not ($env:OS -eq 'Windows_NT')) {
            $result = Measure-NetworkLatency -ComputerName 'localhost' -Count 3 -DelayMs 100
            $result.Received | Should -BeGreaterThan 0
            $result.ComputerName | Should -Be 'localhost'
        }
    }
}
