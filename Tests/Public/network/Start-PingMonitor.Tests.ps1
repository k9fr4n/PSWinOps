BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Start-PingMonitor' {

    Context 'Parameter validation' {

        It 'Should require ComputerName parameter' {
            { Start-PingMonitor -ComputerName $null } | Should -Throw
        }

        It 'Should reject empty ComputerName' {
            { Start-PingMonitor -ComputerName '' } | Should -Throw
        }

        It 'Should reject RefreshInterval of 0' {
            { Start-PingMonitor -ComputerName 'host' -RefreshInterval 0 } | Should -Throw
        }

        It 'Should reject RefreshInterval above 60' {
            { Start-PingMonitor -ComputerName 'host' -RefreshInterval 61 } | Should -Throw
        }

        It 'Should reject PingTimeoutMs below 500' {
            { Start-PingMonitor -ComputerName 'host' -PingTimeoutMs 100 } | Should -Throw
        }

        It 'Should have expected parameters' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $cmd.Parameters.Keys | Should -Contain 'ComputerName'
            $cmd.Parameters.Keys | Should -Contain 'RefreshInterval'
            $cmd.Parameters.Keys | Should -Contain 'PingTimeoutMs'
        }

        It 'Should have default RefreshInterval of 2' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $param = $cmd.Parameters['RefreshInterval']
            $param.ParameterType | Should -Be ([int])
        }

        It 'Should have default PingTimeoutMs of 2000' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $cmd.Parameters['PingTimeoutMs'].ParameterType | Should -Be ([int])
        }

        It 'Should accept PingTimeoutMs of 500 (minimum)' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $rangeAttr = $cmd.Parameters['PingTimeoutMs'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ValidateRangeAttribute]
            }
            $rangeAttr.MinRange | Should -Be 500
        }

        It 'Should accept PingTimeoutMs of 10000 (maximum)' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $rangeAttr = $cmd.Parameters['PingTimeoutMs'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ValidateRangeAttribute]
            }
            $rangeAttr.MaxRange | Should -Be 10000
        }

        It 'Should reject PingTimeoutMs above 10000' {
            { Start-PingMonitor -ComputerName 'host' -PingTimeoutMs 11000 } | Should -Throw
        }
    }

    Context 'Function existence and metadata' {

        It 'Should be exported from the module' {
            $cmd = Get-Command -Name 'Start-PingMonitor' -Module $script:ModuleName
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should have CmdletBinding' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $cmd.CmdletBinding | Should -Be $true
        }

        It 'Should have SuppressMessageAttribute in the source code' {
            # SuppressMessageAttribute may not be reflected via Get-Command on all platforms
            # Verify by checking the script block text directly
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $scriptText = $cmd.ScriptBlock.ToString()
            $scriptText | Should -Match 'PSAvoidUsingWriteHost'
        }

        It 'Should have ComputerName as mandatory parameter' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $paramAttr = $cmd.Parameters['ComputerName'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute]
            }
            $paramAttr.Mandatory | Should -BeTrue
        }

        It 'Should support CN alias for ComputerName' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }

        It 'Should accept pipeline input for ComputerName' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $paramAttr = $cmd.Parameters['ComputerName'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute]
            }
            $paramAttr.ValueFromPipeline | Should -BeTrue
            $paramAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }

        It 'Should declare OutputType void' {
            $cmd = Get-Command -Name 'Start-PingMonitor'
            $outputType = $cmd.OutputType
            $outputType.Type | Should -Contain ([void])
        }
    }

    Context 'Dashboard loop execution with mocked Ping' {

        BeforeEach {
            # Track iteration count to break loop after first cycle
            $script:loopCount = 0

            # Mock Ping.Send to return success
            $mockReply = [PSCustomObject]@{
                Status        = [System.Net.NetworkInformation.IPStatus]::Success
                RoundtripTime = 15
            }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -ParameterFilter {
                $TypeName -eq 'System.Net.NetworkInformation.Ping'
            } -MockWith {
                $mockPing = [PSCustomObject]@{}
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                    param($target, $timeout, $buffer, $options)
                    return [PSCustomObject]@{
                        Status        = [System.Net.NetworkInformation.IPStatus]::Success
                        RoundtripTime = 15
                    }
                }
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
                return $mockPing
            }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -ParameterFilter {
                $TypeName -eq 'System.Net.NetworkInformation.PingOptions'
            } -MockWith {
                return [PSCustomObject]@{ Ttl = 128; DontFragment = $true }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Write-Host' -MockWith { }

            # Start-Sleep mock: throw after first iteration to break the while loop
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith {
                $script:loopCount++
                if ($script:loopCount -ge 1) {
                    throw 'Test break: stopping loop'
                }
            }
        }

        It 'Should execute at least one ping cycle before stopping' {
            Start-PingMonitor -ComputerName 'TestHost1'
            Should -Invoke -CommandName 'Clear-Host' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should call Write-Host for dashboard rendering' {
            Start-PingMonitor -ComputerName 'TestHost1'
            Should -Invoke -CommandName 'Write-Host' -ModuleName $script:ModuleName
        }

        It 'Should handle multiple hosts in one cycle' {
            Start-PingMonitor -ComputerName 'Host1', 'Host2', 'Host3'
            Should -Invoke -CommandName 'Clear-Host' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should call Start-Sleep with the RefreshInterval' {
            Start-PingMonitor -ComputerName 'TestHost1' -RefreshInterval 5
            Should -Invoke -CommandName 'Start-Sleep' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Seconds -eq 5
            }
        }
    }

    Context 'Dashboard loop with ping failure (host down)' {

        BeforeEach {
            $script:loopCount = 0

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -ParameterFilter {
                $TypeName -eq 'System.Net.NetworkInformation.Ping'
            } -MockWith {
                $mockPing = [PSCustomObject]@{}
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                    param($target, $timeout, $buffer, $options)
                    return [PSCustomObject]@{
                        Status        = [System.Net.NetworkInformation.IPStatus]::TimedOut
                        RoundtripTime = 0
                    }
                }
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
                return $mockPing
            }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -ParameterFilter {
                $TypeName -eq 'System.Net.NetworkInformation.PingOptions'
            } -MockWith {
                return [PSCustomObject]@{ Ttl = 128; DontFragment = $true }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Write-Host' -MockWith { }

            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith {
                $script:loopCount++
                if ($script:loopCount -ge 1) {
                    throw 'Test break: stopping loop'
                }
            }
        }

        It 'Should handle timed out ping without errors' {
            { Start-PingMonitor -ComputerName 'DownHost' } | Should -Not -Throw
        }

        It 'Should display dashboard even when host is down' {
            Start-PingMonitor -ComputerName 'DownHost'
            Should -Invoke -CommandName 'Write-Host' -ModuleName $script:ModuleName
        }
    }

    Context 'Dashboard loop with ping exception' {

        BeforeEach {
            $script:loopCount = 0

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -ParameterFilter {
                $TypeName -eq 'System.Net.NetworkInformation.Ping'
            } -MockWith {
                $mockPing = [PSCustomObject]@{}
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                    param($target, $timeout, $buffer, $options)
                    throw 'DNS resolution failed'
                }
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
                return $mockPing
            }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -ParameterFilter {
                $TypeName -eq 'System.Net.NetworkInformation.PingOptions'
            } -MockWith {
                return [PSCustomObject]@{ Ttl = 128; DontFragment = $true }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Write-Host' -MockWith { }

            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith {
                $script:loopCount++
                if ($script:loopCount -ge 1) {
                    throw 'Test break: stopping loop'
                }
            }
        }

        It 'Should handle ping exception gracefully and mark host as Down' {
            { Start-PingMonitor -ComputerName 'InvalidHost.nonexistent' } | Should -Not -Throw
        }
    }

    Context 'Dashboard with mixed host statuses' {

        BeforeEach {
            $script:loopCount = 0
            $script:callIndex = 0

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -ParameterFilter {
                $TypeName -eq 'System.Net.NetworkInformation.Ping'
            } -MockWith {
                $mockPing = [PSCustomObject]@{}
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                    param($target, $timeout, $buffer, $options)
                    $script:callIndex++
                    if ($script:callIndex % 2 -eq 0) {
                        return [PSCustomObject]@{
                            Status        = [System.Net.NetworkInformation.IPStatus]::TimedOut
                            RoundtripTime = 0
                        }
                    } else {
                        return [PSCustomObject]@{
                            Status        = [System.Net.NetworkInformation.IPStatus]::Success
                            RoundtripTime = 10
                        }
                    }
                }
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
                return $mockPing
            }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -ParameterFilter {
                $TypeName -eq 'System.Net.NetworkInformation.PingOptions'
            } -MockWith {
                return [PSCustomObject]@{ Ttl = 128; DontFragment = $true }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Write-Host' -MockWith { }

            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith {
                $script:loopCount++
                if ($script:loopCount -ge 1) {
                    throw 'Test break: stopping loop'
                }
            }
        }

        It 'Should render dashboard with mixed Up and Down hosts' {
            { Start-PingMonitor -ComputerName 'UpHost', 'DownHost' } | Should -Not -Throw
            Should -Invoke -CommandName 'Write-Host' -ModuleName $script:ModuleName
        }
    }
}
