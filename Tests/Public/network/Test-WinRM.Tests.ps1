BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'

    # Stub Windows-only commands for cross-platform test execution
    if (-not (Get-Command -Name 'Test-WSMan' -ErrorAction SilentlyContinue)) {
        function global:Test-WSMan { param($ComputerName, $Credential, $ErrorAction) }
    }
}

Describe 'Test-WinRM' {

    Context 'Happy path - port open and WSMan OK' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                return [System.Threading.Tasks.Task]::FromResult($true)
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0.20348 SP: 0.0 Stack: 3.0' }
            }
        }

        It 'Should return all three checks passed' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result.PortOpen | Should -Be $true
            $result.WSManConnected | Should -Be $true
            $result.Port | Should -Be 5985
        }

        It 'Should include PSTypeName PSWinOps.WinRMTestResult' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.WinRMTestResult'
        }

        It 'Should include WSMan version' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result.WSManVersion | Should -Not -BeNullOrEmpty
        }

        It 'Should default to HTTP protocol' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result.Protocol | Should -Be 'HTTP'
        }

        It 'Should include Timestamp' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Port open but WSMan fails' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                return [System.Threading.Tasks.Task]::FromResult($true)
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                throw 'Access denied'
            }
        }

        It 'Should show port open but WSMan failed' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result.PortOpen | Should -Be $true
            $result.WSManConnected | Should -Be $false
            $result.ErrorMessage | Should -Match 'WSMan failed'
        }
    }

    Context 'Port closed' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                throw 'Connection refused'
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }
        }

        It 'Should report port closed and skip WSMan test' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result.PortOpen | Should -Be $false
            $result.WSManConnected | Should -Be $false
            $result.ErrorMessage | Should -Match 'not reachable'
        }
    }

    Context 'UseSSL switch' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                return [System.Threading.Tasks.Task]::FromResult($true)
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0' }
            }
        }

        It 'Should test port 5986 with -UseSSL' {
            $result = Test-WinRM -ComputerName 'SRV01' -UseSSL
            $result.Port | Should -Be 5986
            $result.Protocol | Should -Be 'HTTPS'
        }
    }

    Context 'Pipeline input' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                throw 'refused'
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }
        }

        It 'Should accept multiple computers via pipeline' {
            $result = 'SRV01', 'SRV02', 'SRV03' | Test-WinRM
            $result.Count | Should -Be 3
        }
    }

    Context 'TestExecution - success' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                return [System.Threading.Tasks.Task]::FromResult($true)
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0.20348 SP: 0.0 Stack: 3.0' }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return 'SRV01'
            }
        }

        It 'Should set ExecutionOK to True when Invoke-Command succeeds' {
            $result = Test-WinRM -ComputerName 'SRV01' -TestExecution
            $result.ExecutionOK | Should -Be $true
            $result.PortOpen | Should -Be $true
            $result.WSManConnected | Should -Be $true
        }

        It 'Should call Invoke-Command when -TestExecution is specified' {
            Test-WinRM -ComputerName 'SRV01' -TestExecution
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should have null ExecutionOK when -TestExecution is not specified' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result.ExecutionOK | Should -BeNullOrEmpty
        }
    }

    Context 'TestExecution - failure' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                return [System.Threading.Tasks.Task]::FromResult($true)
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0' }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                throw 'Access denied'
            }
        }

        It 'Should set ExecutionOK to False when Invoke-Command fails' {
            $result = Test-WinRM -ComputerName 'SRV01' -TestExecution
            $result.ExecutionOK | Should -Be $false
            $result.ErrorMessage | Should -Match 'Execution failed'
        }

        It 'Should not skip execution test when WSMan succeeds' {
            $result = Test-WinRM -ComputerName 'SRV01' -TestExecution
            $result.WSManConnected | Should -Be $true
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Credential parameter' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                return [System.Threading.Tasks.Task]::FromResult($true)
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0' }
            }
        }

        It 'Should pass Credential to Test-WSMan when provided' {
            $cred = [PSCredential]::new('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            Test-WinRM -ComputerName 'SRV01' -Credential $cred
            Should -Invoke -CommandName 'Test-WSMan' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Per-machine failure isolation' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                return [System.Threading.Tasks.Task]::FromResult($true)
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0' }
            }
        }

        It 'Should return results for all machines even if none fail' {
            $result = Test-WinRM -ComputerName 'SRV01', 'SRV02'
            $result.Count | Should -Be 2
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty ComputerName' {
            { Test-WinRM -ComputerName '' } | Should -Throw
        }

        It 'Should reject TimeoutMs below 500' {
            { Test-WinRM -ComputerName 'SRV01' -TimeoutMs 100 } | Should -Throw
        }

        It 'Should reject TimeoutMs above 30000' {
            { Test-WinRM -ComputerName 'SRV01' -TimeoutMs 31000 } | Should -Throw
        }
    }
}
