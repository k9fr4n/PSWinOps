#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-NetworkStatistic' {

    Context 'Parameter validation' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should have ComputerName parameter with pipeline support' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $param = $cmd.Parameters['ComputerName']
            $param | Should -Not -BeNullOrEmpty
            $pAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pAttr.ValueFromPipeline | Should -BeTrue
        }

        It 'Should have Protocol parameter with ValidateSet' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $vs = $cmd.Parameters['Protocol'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $vs.ValidValues | Should -Contain 'TCP'
            $vs.ValidValues | Should -Contain 'UDP'
        }

        It 'Should NOT have LocalAddress, LocalPort, RemoteAddress, RemotePort params' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $cmd.Parameters.ContainsKey('LocalAddress') | Should -BeFalse
            $cmd.Parameters.ContainsKey('LocalPort') | Should -BeFalse
            $cmd.Parameters.ContainsKey('RemoteAddress') | Should -BeFalse
            $cmd.Parameters.ContainsKey('RemotePort') | Should -BeFalse
        }

        It 'Should reject empty ComputerName' {
            { Get-NetworkStatistic -ComputerName '' } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            { Get-NetworkStatistic -ComputerName $null } | Should -Throw
        }
    }

    Context 'Happy path - local machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetworkConnection' -MockWith {
                @(
                    [PSCustomObject]@{ PSTypeName = 'PSWinOps.NetworkConnection'; ComputerName = $env:COMPUTERNAME; Protocol = 'TCP'; LocalAddress = '127.0.0.1'; LocalPort = 80; RemoteAddress = '10.0.0.1'; RemotePort = 54321; State = 'Established'; ProcessId = 1000; ProcessName = 'nginx'; Timestamp = (Get-Date -Format 'o') },
                    [PSCustomObject]@{ PSTypeName = 'PSWinOps.NetworkConnection'; ComputerName = $env:COMPUTERNAME; Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 443; RemoteAddress = '0.0.0.0'; RemotePort = 0; State = 'Listen'; ProcessId = 1000; ProcessName = 'nginx'; Timestamp = (Get-Date -Format 'o') },
                    [PSCustomObject]@{ PSTypeName = 'PSWinOps.NetworkConnection'; ComputerName = $env:COMPUTERNAME; Protocol = 'UDP'; LocalAddress = '0.0.0.0'; LocalPort = 53; RemoteAddress = '*'; RemotePort = 0; State = 'Stateless'; ProcessId = 2000; ProcessName = 'dns'; Timestamp = (Get-Date -Format 'o') }
                )
            }
        }

        It 'Should call Get-NetworkConnection' {
            $null = Get-NetworkStatistic
            Should -Invoke -CommandName 'Get-NetworkConnection' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return PSWinOps.NetworkStatistic typed objects' {
            $results = Get-NetworkStatistic
            $results | ForEach-Object { $_.PSTypeNames[0] | Should -Be 'PSWinOps.NetworkStatistic' }
        }

        It 'Should group by ProcessName and ProcessId' {
            $results = @(Get-NetworkStatistic)
            $results.Count | Should -Be 2  # nginx (PID 1000) + dns (PID 2000)
        }

        It 'Should count TcpEstablished correctly' {
            $results = @(Get-NetworkStatistic)
            $nginx = $results | Where-Object { $_.ProcessName -eq 'nginx' }
            $nginx.TcpEstablished | Should -Be 1
        }

        It 'Should count TcpListening correctly' {
            $results = @(Get-NetworkStatistic)
            $nginx = $results | Where-Object { $_.ProcessName -eq 'nginx' }
            $nginx.TcpListening | Should -Be 1
        }

        It 'Should count UdpEndpoints correctly' {
            $results = @(Get-NetworkStatistic)
            $dns = $results | Where-Object { $_.ProcessName -eq 'dns' }
            $dns.UdpEndpoints | Should -Be 1
        }

        It 'Should count TotalConnections correctly' {
            $results = @(Get-NetworkStatistic)
            $nginx = $results | Where-Object { $_.ProcessName -eq 'nginx' }
            $nginx.TotalConnections | Should -Be 2
        }

        It 'Should include ComputerName and Timestamp' {
            $results = @(Get-NetworkStatistic)
            $results[0].ComputerName | Should -Not -BeNullOrEmpty
            $results[0].Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Happy path - remote machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetworkConnection' -MockWith {
                @(
                    [PSCustomObject]@{ PSTypeName = 'PSWinOps.NetworkConnection'; ComputerName = 'REMOTE01'; Protocol = 'TCP'; LocalAddress = '10.0.0.5'; LocalPort = 80; RemoteAddress = '10.0.0.100'; RemotePort = 49152; State = 'Established'; ProcessId = 100; ProcessName = 'w3wp'; Timestamp = (Get-Date -Format 'o') }
                )
            }
        }

        It 'Should forward ComputerName to Get-NetworkConnection' {
            $null = Get-NetworkStatistic -ComputerName 'REMOTE01'
            Should -Invoke -CommandName 'Get-NetworkConnection' -ModuleName $script:ModuleName -ParameterFilter {
                $ComputerName -eq 'REMOTE01'
            }
        }
    }

    Context 'Pipeline - multiple machines' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetworkConnection' -MockWith {
                @(
                    [PSCustomObject]@{ PSTypeName = 'PSWinOps.NetworkConnection'; ComputerName = $ComputerName; Protocol = 'TCP'; LocalAddress = '10.0.0.5'; LocalPort = 80; RemoteAddress = '10.0.0.100'; RemotePort = 49152; State = 'Established'; ProcessId = 100; ProcessName = 'w3wp'; Timestamp = (Get-Date -Format 'o') }
                )
            }
        }

        It 'Should process each piped computer' {
            $null = 'SRV01', 'SRV02' | Get-NetworkStatistic
            Should -Invoke -CommandName 'Get-NetworkConnection' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetworkConnection' -MockWith {
                throw 'Connection failed'
            }
        }

        It 'Should write error and continue' {
            { Get-NetworkStatistic -ComputerName 'BADHOST' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'No connections found' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetworkConnection' -MockWith {
                return @()
            }
        }

        It 'Should return nothing when no connections' {
            $results = @(Get-NetworkStatistic)
            $results.Count | Should -Be 0
        }
    }
}
