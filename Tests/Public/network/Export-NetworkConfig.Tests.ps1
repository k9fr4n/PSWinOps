BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Export-NetworkConfig' {

    Context 'Happy path - local machine' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith {
                @([PSCustomObject]@{ Name = 'Eth0'; InterfaceDescription = 'NIC'; Status = 'Up'; LinkSpeed = '1 Gbps'; MacAddress = 'AA:BB:CC:DD:EE:FF'; MtuSize = 1500; ifIndex = 5 })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @([PSCustomObject]@{ InterfaceAlias = 'Eth0'; IPAddress = '10.0.0.5'; PrefixLength = 24; AddressFamily = 2; PrefixOrigin = 'Dhcp' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith {
                @([PSCustomObject]@{ InterfaceAlias = 'Eth0'; ServerAddresses = @('10.0.0.1') })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClient' -MockWith {
                @([PSCustomObject]@{ ConnectionSpecificSuffix = 'corp.local' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                @([PSCustomObject]@{ DestinationPrefix = '0.0.0.0/0'; NextHop = '10.0.0.1'; RouteMetric = 0; InterfaceAlias = 'Eth0'; AddressFamily = 2 })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetFirewallProfile' -MockWith {
                @([PSCustomObject]@{ Name = 'Domain'; Enabled = $true; DefaultInboundAction = 'Block'; DefaultOutboundAction = 'Allow' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @([PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 80; OwningProcess = 4; State = 'Listen' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                @([PSCustomObject]@{ Id = 4; ProcessName = 'System' })
            }
        }

        It 'Should return a complete config object' {
            $result = Export-NetworkConfig
            $result | Should -Not -BeNullOrEmpty
            $result.Adapters | Should -Not -BeNullOrEmpty
            $result.IPAddresses | Should -Not -BeNullOrEmpty
        }

        It 'Should include PSTypeName PSWinOps.NetworkConfig' {
            $result = Export-NetworkConfig
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.NetworkConfig'
        }

        It 'Should include ComputerName and Timestamp' {
            $result = Export-NetworkConfig
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should include DNS, routes, and firewall data by default' {
            $result = Export-NetworkConfig
            $result.DnsServers | Should -Not -BeNullOrEmpty
            $result.Routes | Should -Not -BeNullOrEmpty
            $result.FirewallProfiles | Should -Not -BeNullOrEmpty
        }

        It 'Should exclude firewall data when -ExcludeFirewall is specified' {
            $result = Export-NetworkConfig -ExcludeFirewall
            $result.FirewallProfiles | Should -BeNullOrEmpty
        }

        It 'Should exclude listeners when -ExcludeListeners is specified' {
            $result = Export-NetworkConfig -ExcludeListeners
            $result.ListeningPorts | Should -BeNullOrEmpty
        }

        It 'Should support Name alias for ComputerName' {
            $cmd = Get-Command -Name 'Export-NetworkConfig'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }

    Context 'Export to JSON file' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClient' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetFirewallProfile' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Set-Content' -MockWith { }
        }

        It 'Should call Set-Content when -Path specified' {
            $result = Export-NetworkConfig -Path 'C:\temp\config.json'
            Should -Invoke -CommandName 'Set-Content' -ModuleName $script:ModuleName -Times 1
        }
    }

    Context 'Error handling' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith { throw 'Unreachable' }
        }

        It 'Should write error on remote failure' {
            Export-NetworkConfig -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty ComputerName' {
            { Export-NetworkConfig -ComputerName '' } | Should -Throw
        }
    }
}
