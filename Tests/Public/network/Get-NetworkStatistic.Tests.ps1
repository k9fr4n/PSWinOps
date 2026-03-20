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

        It 'Should have OutputType PSWinOps.NetworkStatistic' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $cmd.OutputType.Name | Should -Contain 'PSWinOps.NetworkStatistic'
        }

        It 'Should have ComputerName parameter with pipeline support' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $param = $cmd.Parameters['ComputerName']
            $param | Should -Not -BeNullOrEmpty
            $pAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pAttr.ValueFromPipeline | Should -BeTrue
            $pAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }

        It 'Should have Protocol parameter with ValidateSet TCP/UDP' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $param = $cmd.Parameters['Protocol']
            $param | Should -Not -BeNullOrEmpty
            $vs = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $vs.ValidValues | Should -Contain 'TCP'
            $vs.ValidValues | Should -Contain 'UDP'
        }

        It 'Should have State parameter with ValidateSet' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $param = $cmd.Parameters['State']
            $param | Should -Not -BeNullOrEmpty
            $vs = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $vs.ValidValues | Should -Contain 'Established'
            $vs.ValidValues | Should -Contain 'Listen'
        }

        It 'Should have LocalPort parameter with ValidateRange 1-65535' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $param = $cmd.Parameters['LocalPort']
            $param | Should -Not -BeNullOrEmpty
            $vr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $vr | Should -Not -BeNullOrEmpty
        }

        It 'Should have RemotePort parameter with ValidateRange 1-65535' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $param = $cmd.Parameters['RemotePort']
            $param | Should -Not -BeNullOrEmpty
            $vr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $vr | Should -Not -BeNullOrEmpty
        }

        It 'Should have Credential parameter of type PSCredential' {
            $cmd = Get-Command -Name 'Get-NetworkStatistic'
            $param = $cmd.Parameters['Credential']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'PSCredential'
        }

        It 'Should reject invalid Protocol value' {
            { Get-NetworkStatistic -Protocol 'ICMP' } | Should -Throw
        }

        It 'Should reject invalid State value' {
            { Get-NetworkStatistic -State 'InvalidState' } | Should -Throw
        }

        It 'Should reject LocalPort out of range' {
            { Get-NetworkStatistic -LocalPort 0 } | Should -Throw
            { Get-NetworkStatistic -LocalPort 70000 } | Should -Throw
        }

        It 'Should reject empty ComputerName' {
            { Get-NetworkStatistic -ComputerName '' } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            { Get-NetworkStatistic -ComputerName $null } | Should -Throw
        }
    }

    Context 'Happy path - local machine with TCP only' {
        BeforeAll {
            $script:mockTcpConnections = @(
                [PSCustomObject]@{
                    LocalAddress  = '127.0.0.1'
                    LocalPort     = 80
                    RemoteAddress = '10.0.0.1'
                    RemotePort    = 54321
                    State         = 'Established'
                    OwningProcess = 1234
                },
                [PSCustomObject]@{
                    LocalAddress  = '0.0.0.0'
                    LocalPort     = 443
                    RemoteAddress = '0.0.0.0'
                    RemotePort    = 0
                    State         = 'Listen'
                    OwningProcess = 4
                }
            )

            $script:mockProcesses = @(
                [PSCustomObject]@{ Id = 1234; ProcessName = 'nginx' },
                [PSCustomObject]@{ Id = 4; ProcessName = 'System' }
            )

            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                return $script:mockTcpConnections
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                return $script:mockProcesses
            }
        }

        It 'Should return objects with PSTypeName PSWinOps.NetworkStatistic' {
            $results = Get-NetworkStatistic -Protocol TCP
            $results | ForEach-Object {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.NetworkStatistic'
            }
        }

        It 'Should return correct number of TCP connections' {
            $results = Get-NetworkStatistic -Protocol TCP
            $results | Should -HaveCount 2
        }

        It 'Should include ComputerName on each result' {
            $results = Get-NetworkStatistic -Protocol TCP
            $results | ForEach-Object {
                $_.ComputerName | Should -Be $env:COMPUTERNAME
            }
        }

        It 'Should include Timestamp on each result' {
            $results = Get-NetworkStatistic -Protocol TCP
            $results | ForEach-Object {
                $_.Timestamp | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should resolve process names correctly' {
            $results = Get-NetworkStatistic -Protocol TCP
            ($results | Where-Object { $_.ProcessId -eq 1234 }).ProcessName | Should -Be 'nginx'
            ($results | Where-Object { $_.ProcessId -eq 4 }).ProcessName | Should -Be 'System'
        }

        It 'Should set Protocol to TCP for all entries' {
            $results = Get-NetworkStatistic -Protocol TCP
            $results | ForEach-Object {
                $_.Protocol | Should -Be 'TCP'
            }
        }
    }

    Context 'Happy path - local machine with UDP only' {
        BeforeAll {
            $script:mockUdpEndpoints = @(
                [PSCustomObject]@{
                    LocalAddress  = '0.0.0.0'
                    LocalPort     = 53
                    OwningProcess = 5678
                }
            )

            $script:mockProcesses = @(
                [PSCustomObject]@{ Id = 5678; ProcessName = 'dns' }
            )

            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith {
                return $script:mockUdpEndpoints
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                return $script:mockProcesses
            }
        }

        It 'Should return UDP entries with State Stateless' {
            $results = Get-NetworkStatistic -Protocol UDP
            $results | Should -HaveCount 1
            $results[0].State | Should -Be 'Stateless'
        }

        It 'Should set RemoteAddress to * for UDP' {
            $results = Get-NetworkStatistic -Protocol UDP
            $results[0].RemoteAddress | Should -Be '*'
        }

        It 'Should set RemotePort to 0 for UDP' {
            $results = Get-NetworkStatistic -Protocol UDP
            $results[0].RemotePort | Should -Be 0
        }
    }

    Context 'Happy path - explicit remote machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return @(
                    [PSCustomObject]@{
                        Protocol      = 'TCP'
                        LocalAddress  = '10.0.0.5'
                        LocalPort     = 3389
                        RemoteAddress = '10.0.0.100'
                        RemotePort    = 49152
                        State         = 'Established'
                        ProcessId     = 1000
                        ProcessName   = 'svchost'
                    }
                )
            }
        }

        It 'Should use Invoke-Command for remote machine' {
            $results = Get-NetworkStatistic -ComputerName 'REMOTESRV01' -Protocol TCP
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set ComputerName to the remote machine name' {
            $results = Get-NetworkStatistic -ComputerName 'REMOTESRV01' -Protocol TCP
            $results[0].ComputerName | Should -Be 'REMOTESRV01'
        }

        It 'Should return results from remote machine' {
            $results = Get-NetworkStatistic -ComputerName 'REMOTESRV01' -Protocol TCP
            $results | Should -HaveCount 1
            $results[0].LocalPort | Should -Be 3389
        }
    }

    Context 'Pipeline - multiple machine names' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return @(
                    [PSCustomObject]@{
                        Protocol      = 'TCP'
                        LocalAddress  = '10.0.0.5'
                        LocalPort     = 80
                        RemoteAddress = '10.0.0.100'
                        RemotePort    = 49152
                        State         = 'Established'
                        ProcessId     = 100
                        ProcessName   = 'w3wp'
                    }
                )
            }
        }

        It 'Should accept multiple computers via pipeline' {
            $results = 'REMOTE01', 'REMOTE02' | Get-NetworkStatistic -Protocol TCP
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should return results from each machine' {
            $results = 'REMOTE01', 'REMOTE02' | Get-NetworkStatistic -Protocol TCP
            $results | Should -HaveCount 2
            ($results | Where-Object { $_.ComputerName -eq 'REMOTE01' }) | Should -Not -BeNullOrEmpty
            ($results | Where-Object { $_.ComputerName -eq 'REMOTE02' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Per-machine failure - continues and writes error' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                throw 'WinRM connection failed'
            }
        }

        It 'Should write error for failed machine but not throw' {
            $results = Get-NetworkStatistic -ComputerName 'BADSRV01' -Protocol TCP -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like "*Failed on 'BADSRV01'*") | Should -Not -BeNullOrEmpty
        }

        It 'Should continue processing remaining machines after failure' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                param($ComputerName)
                if ($ComputerName -eq 'BADSRV') {
                    throw 'Connection refused'
                }
                return @(
                    [PSCustomObject]@{
                        Protocol = 'TCP'; LocalAddress = '10.0.0.1'; LocalPort = 80
                        RemoteAddress = '0.0.0.0'; RemotePort = 0; State = 'Listen'
                        ProcessId = 4; ProcessName = 'System'
                    }
                )
            }

            $results = Get-NetworkStatistic -ComputerName 'BADSRV', 'GOODSRV' -Protocol TCP -ErrorAction SilentlyContinue
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Filtering - State parameter' {
        BeforeAll {
            $script:mockTcpAll = @(
                [PSCustomObject]@{
                    LocalAddress = '127.0.0.1'; LocalPort = 80
                    RemoteAddress = '10.0.0.1'; RemotePort = 54321
                    State = 'Established'; OwningProcess = 100
                },
                [PSCustomObject]@{
                    LocalAddress = '0.0.0.0'; LocalPort = 443
                    RemoteAddress = '0.0.0.0'; RemotePort = 0
                    State = 'Listen'; OwningProcess = 4
                }
            )

            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                return @(
                    [PSCustomObject]@{ Id = 100; ProcessName = 'nginx' },
                    [PSCustomObject]@{ Id = 4; ProcessName = 'System' }
                )
            }
        }

        It 'Should pass State to Get-NetTCPConnection' {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -ParameterFilter {
                $State -contains 'Established'
            } -MockWith {
                return @($script:mockTcpAll | Where-Object { $_.State -eq 'Established' })
            }

            $results = Get-NetworkStatistic -Protocol TCP -State Established
            $results | Should -HaveCount 1
            $results[0].State | Should -Be 'Established'
        }
    }

    Context 'Filtering - ProcessName parameter' {
        BeforeAll {
            $script:mockTcpConn = @(
                [PSCustomObject]@{
                    LocalAddress = '127.0.0.1'; LocalPort = 80
                    RemoteAddress = '10.0.0.1'; RemotePort = 54321
                    State = 'Established'; OwningProcess = 100
                },
                [PSCustomObject]@{
                    LocalAddress = '0.0.0.0'; LocalPort = 443
                    RemoteAddress = '0.0.0.0'; RemotePort = 0
                    State = 'Listen'; OwningProcess = 200
                }
            )

            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                return $script:mockTcpConn
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                return @(
                    [PSCustomObject]@{ Id = 100; ProcessName = 'nginx' },
                    [PSCustomObject]@{ Id = 200; ProcessName = 'svchost' }
                )
            }
        }

        It 'Should filter by exact process name' {
            $results = Get-NetworkStatistic -Protocol TCP -ProcessName 'nginx'
            $results | Should -HaveCount 1
            $results[0].ProcessName | Should -Be 'nginx'
        }

        It 'Should filter by wildcard process name' {
            $results = Get-NetworkStatistic -Protocol TCP -ProcessName 'svc*'
            $results | Should -HaveCount 1
            $results[0].ProcessName | Should -Be 'svchost'
        }
    }

    Context 'Filtering - LocalPort parameter' {
        BeforeAll {
            $script:mockTcpConn = @(
                [PSCustomObject]@{
                    LocalAddress = '127.0.0.1'; LocalPort = 80
                    RemoteAddress = '10.0.0.1'; RemotePort = 54321
                    State = 'Established'; OwningProcess = 100
                },
                [PSCustomObject]@{
                    LocalAddress = '0.0.0.0'; LocalPort = 443
                    RemoteAddress = '0.0.0.0'; RemotePort = 0
                    State = 'Listen'; OwningProcess = 200
                }
            )

            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                return $script:mockTcpConn
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                return @(
                    [PSCustomObject]@{ Id = 100; ProcessName = 'nginx' },
                    [PSCustomObject]@{ Id = 200; ProcessName = 'svchost' }
                )
            }
        }

        It 'Should filter by local port' {
            $results = Get-NetworkStatistic -Protocol TCP -LocalPort 443
            $results | Should -HaveCount 1
            $results[0].LocalPort | Should -Be 443
        }
    }

    Context 'Output object shape' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                return @(
                    [PSCustomObject]@{
                        LocalAddress = '127.0.0.1'; LocalPort = 80
                        RemoteAddress = '10.0.0.1'; RemotePort = 54321
                        State = 'Established'; OwningProcess = 100
                    }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                return @([PSCustomObject]@{ Id = 100; ProcessName = 'nginx' })
            }
        }

        It 'Should have all expected properties' {
            $result = Get-NetworkStatistic -Protocol TCP | Select-Object -First 1
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'Protocol'
            $result.PSObject.Properties.Name | Should -Contain 'LocalAddress'
            $result.PSObject.Properties.Name | Should -Contain 'LocalPort'
            $result.PSObject.Properties.Name | Should -Contain 'RemoteAddress'
            $result.PSObject.Properties.Name | Should -Contain 'RemotePort'
            $result.PSObject.Properties.Name | Should -Contain 'State'
            $result.PSObject.Properties.Name | Should -Contain 'ProcessId'
            $result.PSObject.Properties.Name | Should -Contain 'ProcessName'
            $result.PSObject.Properties.Name | Should -Contain 'Timestamp'
        }
    }

    Context 'Integration' -Tag 'Integration' {
        It 'Should return real TCP connections on a Windows machine' -Skip:(-not ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')) {
            $results = Get-NetworkStatistic -Protocol TCP
            $results | Should -Not -BeNullOrEmpty
            $results[0].Protocol | Should -Be 'TCP'
        }
    }
}
