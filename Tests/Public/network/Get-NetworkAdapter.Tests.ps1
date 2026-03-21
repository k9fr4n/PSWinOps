BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-NetworkAdapter' {

    Context 'Happy path - local machine' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Ethernet'; InterfaceDescription = 'Intel I350'; Status = 'Up'
                    LinkSpeed = '1 Gbps'; MacAddress = 'AA-BB-CC-DD-EE-FF'; MtuSize = 1500
                    ifIndex = 5; MediaType = '802.3'; DriverVersion = '12.18.9.23'; VlanID = $null
                })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; IPAddress = '192.168.1.10'; PrefixLength = 24; AddressFamily = 2; PrefixOrigin = 'Dhcp' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; ServerAddresses = @('10.0.0.1', '8.8.8.8') })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; InterfaceAlias = 'Ethernet' })
            }
        }

        It 'Should return structured adapter info' {
            $result = Get-NetworkAdapter
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'Ethernet'
            $result.IPv4Address | Should -Be '192.168.1.10'
            $result.Gateway | Should -Be '192.168.1.1'
            $result.DnsServers | Should -Match '10.0.0.1'
        }

        It 'Should include PSTypeName PSWinOps.NetworkAdapterInfo' {
            $result = Get-NetworkAdapter
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.NetworkAdapterInfo'
        }

        It 'Should include ComputerName and Timestamp' {
            $result = Get-NetworkAdapter
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Remote machine' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Ethernet0'; Description = 'vmxnet3'; Status = 'Up'
                    Speed = '10 Gbps'; MacAddress = '00:50:56:C0:00:08'; IPv4Address = '10.0.0.5'
                    SubnetPrefix = '24'; IPv6Address = ''; Gateway = '10.0.0.1'; DnsServers = '10.0.0.1'
                    MTU = 1500; InterfaceIndex = 3; MediaType = '802.3'; DriverVersion = '1.8.0.0'; VlanID = $null
                })
            }
        }

        It 'Should query remote via Invoke-Command' {
            $result = Get-NetworkAdapter -ComputerName 'REMOTE01'
            $result.ComputerName | Should -Be 'REMOTE01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Pipeline and multiple hosts' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Eth0'; Description = 'NIC'; Status = 'Up'; Speed = '1 Gbps'
                    MacAddress = 'AA:BB:CC:DD:EE:FF'; IPv4Address = '10.0.0.5'; SubnetPrefix = '24'
                    IPv6Address = ''; Gateway = '10.0.0.1'; DnsServers = '10.0.0.1'
                    MTU = 1500; InterfaceIndex = 1; MediaType = '802.3'; DriverVersion = '1.0'; VlanID = $null
                })
            }
        }

        It 'Should accept pipeline input' {
            $result = 'SRV01', 'SRV02' | Get-NetworkAdapter
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    Context 'Error handling' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith { throw 'Access denied' }
        }

        It 'Should write error and continue on failure' {
            Get-NetworkAdapter -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty ComputerName' {
            { Get-NetworkAdapter -ComputerName '' } | Should -Throw
        }

        It 'Should have IncludeDisabled switch' {
            $cmd = Get-Command -Name 'Get-NetworkAdapter'
            $cmd.Parameters['IncludeDisabled'].SwitchParameter | Should -Be $true
        }
    }
}
