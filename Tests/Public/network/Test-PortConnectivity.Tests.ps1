BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Test-PortConnectivity' {

    Context 'Happy path - port open' {

        BeforeEach {
            $mockTcpClient = [PSCustomObject]@{}
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                param($h, $p)
                $task = [System.Threading.Tasks.Task]::FromResult($true)
                return $task
            }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { }
            $mockTcpClient | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }

            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                return $mockTcpClient
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }
        }

        It 'Should return Open=True for a reachable port' {
            $result = Test-PortConnectivity -ComputerName 'SRV01' -Port 443
            $result.Open | Should -Be $true
            $result.ComputerName | Should -Be 'SRV01'
            $result.Port | Should -Be 443
        }

        It 'Should include PSTypeName PSWinOps.PortConnectivity' {
            $result = Test-PortConnectivity -ComputerName 'SRV01' -Port 80
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.PortConnectivity'
        }

        It 'Should include Timestamp' {
            $result = Test-PortConnectivity -ComputerName 'SRV01' -Port 80
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should include ResponseTimeMs when port is open' {
            $result = Test-PortConnectivity -ComputerName 'SRV01' -Port 80
            $result.ResponseTimeMs | Should -Not -BeNullOrEmpty
        }

        It 'Should always set Protocol to TCP' {
            $result = Test-PortConnectivity -ComputerName 'SRV01' -Port 22
            $result.Protocol | Should -Be 'TCP'
        }
    }

    Context 'Port closed or unreachable' {

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

        It 'Should return Open=False for a closed port' {
            $result = Test-PortConnectivity -ComputerName 'SRV01' -Port 9999
            $result.Open | Should -Be $false
        }

        It 'Should have null ResponseTimeMs for closed port' {
            $result = Test-PortConnectivity -ComputerName 'SRV01' -Port 9999
            $result.ResponseTimeMs | Should -BeNullOrEmpty
        }
    }

    Context 'Multiple hosts and ports' {

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
        }

        It 'Should return one result per host-port combination' {
            $result = Test-PortConnectivity -ComputerName 'SRV01', 'SRV02' -Port 80, 443
            $result.Count | Should -Be 4
        }

        It 'Should support pipeline input' {
            $result = 'SRV01', 'SRV02', 'SRV03' | Test-PortConnectivity -Port 443
            $result.Count | Should -Be 3
        }
    }

    Context 'Parameter validation' {

        It 'Should reject port 0' {
            { Test-PortConnectivity -ComputerName 'SRV01' -Port 0 } | Should -Throw
        }

        It 'Should reject port above 65535' {
            { Test-PortConnectivity -ComputerName 'SRV01' -Port 70000 } | Should -Throw
        }

        It 'Should reject TimeoutMs below 100' {
            { Test-PortConnectivity -ComputerName 'SRV01' -Port 80 -TimeoutMs 50 } | Should -Throw
        }

        It 'Should reject empty ComputerName' {
            { Test-PortConnectivity -ComputerName '' -Port 80 } | Should -Throw
        }
    }

    Context 'Integration' -Tag 'Integration' {

        It 'Should detect an open port on localhost' -Skip:(-not ($env:OS -eq 'Windows_NT')) {
            # Port 135 (RPC) is typically open on Windows
            $result = Test-PortConnectivity -ComputerName 'localhost' -Port 135 -TimeoutMs 2000
            $result.ComputerName | Should -Be 'localhost'
            $result.Port | Should -Be 135
        }
    }
}
