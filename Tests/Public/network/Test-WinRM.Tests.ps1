BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'

    # Stub Windows-only commands for cross-platform test execution
    if (-not (Get-Command -Name 'Test-WSMan' -ErrorAction SilentlyContinue)) {
        function global:Test-WSMan {
            param($ComputerName, $Credential, $UseSsl, $ErrorAction)
        }
    }

    # Helper: creates a mock TcpClient with configurable behavior
    function script:New-MockTcpClient {
        param ([switch]$Refuse)
        $mock = [PSCustomObject]@{}
        if ($Refuse) {
            $mock | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p); throw 'Connection refused'
            }
        } else {
            $mock | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p); return [System.Threading.Tasks.Task]::FromResult($true)
            }
        }
        $mock | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
        $mock | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
        return $mock
    }
}

Describe 'Test-WinRM' {

    Context 'Default behavior — tests both HTTP and HTTPS' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0.20348 SP: 0.0 Stack: 3.0' }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return 'SRV01'
            }
        }

        It 'Should return two rows per computer (HTTP + HTTPS)' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result.Count | Should -Be 2
            $result[0].Protocol | Should -Be 'HTTP'
            $result[1].Protocol | Should -Be 'HTTPS'
        }

        It 'Should test port 5985 for HTTP and 5986 for HTTPS' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result[0].Port | Should -Be 5985
            $result[1].Port | Should -Be 5986
        }

        It 'Should include PSTypeName PSWinOps.WinRMTestResult' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result | ForEach-Object {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.WinRMTestResult'
            }
        }

        It 'Should include Timestamp in ISO 8601 format' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $result | ForEach-Object {
                $_.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
            }
        }

        It 'Should include all expected properties' {
            $result = Test-WinRM -ComputerName 'SRV01'
            $expectedProperties = @('ComputerName', 'Port', 'Protocol', 'PortOpen',
                'WSManConnected', 'ExecutionOK', 'WSManVersion',
                'ErrorMessage', 'Timestamp')
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }

    Context '-Protocol HTTP — single protocol' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0.20348' }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return 'SRV01'
            }
        }

        It 'Should return only one row for HTTP' {
            $result = @(Test-WinRM -ComputerName 'SRV01' -Protocol HTTP)
            $result.Count | Should -Be 1
            $result[0].Protocol | Should -Be 'HTTP'
            $result[0].Port | Should -Be 5985
        }
    }

    Context '-Protocol HTTPS — single protocol' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0.20348' }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return 'SRV01'
            }
        }

        It 'Should return only one row for HTTPS' {
            $result = Test-WinRM -ComputerName 'SRV01' -Protocol HTTPS
            $result.Protocol | Should -Be 'HTTPS'
            $result.Port | Should -Be 5986
        }
    }

    Context 'Port open — WSMan OK — Execution OK' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0.20348 SP: 0.0 Stack: 3.0' }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return 'SRV01'
            }
        }

        It 'Should return all three checks passed' {
            $result = Test-WinRM -ComputerName 'SRV01' -Protocol HTTP
            $result.PortOpen | Should -Be $true
            $result.WSManConnected | Should -Be $true
            $result.ExecutionOK | Should -Be $true
        }

        It 'Should include WSMan version' {
            $result = Test-WinRM -ComputerName 'SRV01' -Protocol HTTP
            $result.WSManVersion | Should -Not -BeNullOrEmpty
        }

        It 'Should always call Invoke-Command when WSMan succeeds' {
            Test-WinRM -ComputerName 'SRV01' -Protocol HTTP
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Port open — WSMan fails' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                throw 'Access denied'
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return 'SRV01'
            }
        }

        It 'Should show port open but WSMan failed' {
            $result = Test-WinRM -ComputerName 'SRV01' -Protocol HTTP
            $result.PortOpen | Should -Be $true
            $result.WSManConnected | Should -Be $false
            $result.ErrorMessage | Should -Match 'WSMan failed'
        }

        It 'Should have null ExecutionOK when WSMan fails' {
            $result = Test-WinRM -ComputerName 'SRV01' -Protocol HTTP
            $result.ExecutionOK | Should -BeNullOrEmpty
        }

        It 'Should not call Invoke-Command when WSMan fails' {
            Test-WinRM -ComputerName 'SRV01' -Protocol HTTP
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    Context 'Port closed' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient -Refuse
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }
        }

        It 'Should report port closed and skip WSMan/Exec tests' {
            $result = Test-WinRM -ComputerName 'SRV01' -Protocol HTTP
            $result.PortOpen | Should -Be $false
            $result.WSManConnected | Should -Be $false
            $result.ExecutionOK | Should -BeNullOrEmpty
            $result.ErrorMessage | Should -Match 'not reachable'
        }
    }

    Context 'Execution fails (WSMan OK but Invoke-Command fails)' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0' }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                throw 'Access denied'
            }
        }

        It 'Should set ExecutionOK to False when Invoke-Command fails' {
            $result = Test-WinRM -ComputerName 'SRV01' -Protocol HTTP
            $result.WSManConnected | Should -Be $true
            $result.ExecutionOK | Should -Be $false
            $result.ErrorMessage | Should -Match 'Execution failed'
        }
    }

    Context 'Pipeline input' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient -Refuse
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }
        }

        It 'Should accept multiple computers via pipeline (2 rows each)' {
            $result = 'SRV01', 'SRV02', 'SRV03' | Test-WinRM
            $result.Count | Should -Be 6
        }

        It 'Should return N rows with -Protocol HTTP' {
            $result = 'SRV01', 'SRV02' | Test-WinRM -Protocol HTTP
            $result.Count | Should -Be 2
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Credential parameter' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0' }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return 'SRV01'
            }
        }

        It 'Should pass Credential to Test-WSMan when provided' {
            $cred = [PSCredential]::new('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            Test-WinRM -ComputerName 'SRV01' -Protocol HTTP -Credential $cred
            Should -Invoke -CommandName 'Test-WSMan' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Per-machine failure isolation' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                New-MockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-WSMan' -MockWith {
                [PSCustomObject]@{ ProductVersion = 'OS: 10.0' }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return 'SRV01'
            }
        }

        It 'Should return results for all machines' {
            $result = Test-WinRM -ComputerName 'SRV01', 'SRV02' -Protocol HTTP
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

        It 'Should reject invalid Protocol' {
            { Test-WinRM -ComputerName 'SRV01' -Protocol 'FTP' } | Should -Throw
        }
    }
}
