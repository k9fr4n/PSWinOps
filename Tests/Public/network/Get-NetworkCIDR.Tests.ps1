BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-NetworkCIDR' {

    Context 'Happy path - local machine (IPv4)' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Ethernet'; InterfaceDescription = 'Intel I350'; Status = 'Up'
                    ifIndex = 5; Virtual = $false
                })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @(
                    [PSCustomObject]@{
                        InterfaceIndex = 5; InterfaceAlias = 'Ethernet'
                        IPAddress = '192.168.1.10'; PrefixLength = 24
                        AddressFamily = 2; PrefixOrigin = 'Dhcp'; SuffixOrigin = 'Dhcp'
                    },
                    [PSCustomObject]@{
                        InterfaceIndex = 5; InterfaceAlias = 'Ethernet'
                        IPAddress = 'fe80::abc:def:1234:5678'; PrefixLength = 64
                        AddressFamily = 23; PrefixOrigin = 'WellKnown'; SuffixOrigin = 'Link'
                    }
                )
            }
        }

        It 'Should return structured CIDR info' {
            $result = @(Get-NetworkCIDR)
            $result | Should -Not -BeNullOrEmpty
            $result[0].CIDR | Should -Be '192.168.1.10/24'
        }

        It 'Should include PSTypeName PSWinOps.NetworkCIDR' {
            $result = @(Get-NetworkCIDR)
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.NetworkCIDR'
        }

        It 'Should include ComputerName and Timestamp' {
            $result = @(Get-NetworkCIDR)
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
            $result[0].Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should calculate correct SubnetMask for /24' {
            $result = @(Get-NetworkCIDR -AddressFamily IPv4)
            $result[0].SubnetMask | Should -Be '255.255.255.0'
        }

        It 'Should calculate correct NetworkAddress for /24' {
            $result = @(Get-NetworkCIDR -AddressFamily IPv4)
            $result[0].NetworkAddress | Should -Be '192.168.1.0'
        }

        It 'Should calculate correct NetworkCIDR for /24' {
            $result = @(Get-NetworkCIDR -AddressFamily IPv4)
            $result[0].NetworkCIDR | Should -Be '192.168.1.0/24'
        }

        It 'Should return null SubnetMask for IPv6 addresses' {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @(
                    [PSCustomObject]@{
                        InterfaceIndex = 5; InterfaceAlias = 'Ethernet'
                        IPAddress = 'fe80::abc:def:1234:5678'; PrefixLength = 64
                        AddressFamily = 23; PrefixOrigin = 'WellKnown'; SuffixOrigin = 'Link'
                    }
                )
            }
            $result = @(Get-NetworkCIDR -AddressFamily IPv6)
            $result[0].SubnetMask | Should -BeNullOrEmpty
        }

        It 'Should return null NetworkCIDR for IPv6 addresses' {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @(
                    [PSCustomObject]@{
                        InterfaceIndex = 5; InterfaceAlias = 'Ethernet'
                        IPAddress = 'fe80::abc:def:1234:5678'; PrefixLength = 64
                        AddressFamily = 23; PrefixOrigin = 'WellKnown'; SuffixOrigin = 'Link'
                    }
                )
            }
            $result = @(Get-NetworkCIDR -AddressFamily IPv6)
            $result[0].NetworkCIDR | Should -BeNullOrEmpty
        }

        It 'Should include InterfaceName property' {
            $result = @(Get-NetworkCIDR)
            $result[0].InterfaceName | Should -Be 'Ethernet'
        }

        It 'Should include AddressFamily property' {
            $result = @(Get-NetworkCIDR -AddressFamily IPv4)
            $result[0].AddressFamily | Should -Be 'IPv4'
        }
    }

    Context 'Happy path - various prefix lengths' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith {
                @([PSCustomObject]@{ Name = 'Ethernet'; ifIndex = 5; Virtual = $false; Status = 'Up' })
            }
        }

        It 'Should calculate correct SubnetMask for /8' {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @([PSCustomObject]@{
                    InterfaceIndex = 5; InterfaceAlias = 'Ethernet'
                    IPAddress = '10.1.2.3'; PrefixLength = 8
                    AddressFamily = 2; PrefixOrigin = 'Manual'; SuffixOrigin = 'Manual'
                })
            }
            $result = @(Get-NetworkCIDR -AddressFamily IPv4)
            $result[0].SubnetMask | Should -Be '255.0.0.0'
            $result[0].NetworkAddress | Should -Be '10.0.0.0'
            $result[0].NetworkCIDR | Should -Be '10.0.0.0/8'
            $result[0].CIDR | Should -Be '10.1.2.3/8'
        }

        It 'Should calculate correct SubnetMask for /16' {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @([PSCustomObject]@{
                    InterfaceIndex = 5; InterfaceAlias = 'Ethernet'
                    IPAddress = '172.16.5.10'; PrefixLength = 16
                    AddressFamily = 2; PrefixOrigin = 'Manual'; SuffixOrigin = 'Manual'
                })
            }
            $result = @(Get-NetworkCIDR -AddressFamily IPv4)
            $result[0].SubnetMask | Should -Be '255.255.0.0'
            $result[0].NetworkAddress | Should -Be '172.16.0.0'
            $result[0].NetworkCIDR | Should -Be '172.16.0.0/16'
        }

        It 'Should calculate correct SubnetMask for /32' {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @([PSCustomObject]@{
                    InterfaceIndex = 5; InterfaceAlias = 'Ethernet'
                    IPAddress = '192.168.1.1'; PrefixLength = 32
                    AddressFamily = 2; PrefixOrigin = 'Manual'; SuffixOrigin = 'Manual'
                })
            }
            $result = @(Get-NetworkCIDR -AddressFamily IPv4)
            $result[0].SubnetMask | Should -Be '255.255.255.255'
            $result[0].NetworkAddress | Should -Be '192.168.1.1'
            $result[0].NetworkCIDR | Should -Be '192.168.1.1/32'
        }
    }

    Context 'Happy path - explicit remote machine' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{
                    InterfaceName = 'Ethernet0'; InterfaceIndex = 3
                    AddressFamily = 'IPv4'; IPAddress = '10.0.0.5'; PrefixLength = 16
                    CIDR = '10.0.0.5/16'; SubnetMask = '255.255.0.0'
                    NetworkAddress = '10.0.0.0'; NetworkCIDR = '10.0.0.0/16'
                    PrefixOrigin = 'Manual'; SuffixOrigin = 'Manual'; AdapterStatus = 'Up'
                })
            }
        }

        It 'Should query remote via Invoke-Command' {
            $result = Get-NetworkCIDR -ComputerName 'REMOTE01'
            $result.ComputerName | Should -Be 'REMOTE01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return correct CIDR from remote host' {
            $result = Get-NetworkCIDR -ComputerName 'REMOTE01'
            $result.CIDR | Should -Be '10.0.0.5/16'
            $result.SubnetMask | Should -Be '255.255.0.0'
        }
    }

    Context 'Pipeline - multiple hosts' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{
                    InterfaceName = 'Eth0'; InterfaceIndex = 1
                    AddressFamily = 'IPv4'; IPAddress = '10.0.0.5'; PrefixLength = 24
                    CIDR = '10.0.0.5/24'; SubnetMask = '255.255.255.0'
                    NetworkAddress = '10.0.0.0'; NetworkCIDR = '10.0.0.0/24'
                    PrefixOrigin = 'Dhcp'; SuffixOrigin = 'Dhcp'; AdapterStatus = 'Up'
                })
            }
        }

        It 'Should accept pipeline input for multiple hosts' {
            'SRV01', 'SRV02' | Get-NetworkCIDR
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should return results for each piped host' {
            $result = @('SRV01', 'SRV02' | Get-NetworkCIDR)
            $result.Count | Should -Be 2
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Per-machine failure handling' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith { throw 'Access denied' }
        }

        It 'Should write error and continue on failure' {
            Get-NetworkCIDR -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            "$($err[0])" | Should -Match 'BADHOST'
        }

        It 'Should not throw terminating error on per-machine failure' {
            { Get-NetworkCIDR -ComputerName 'BADHOST' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty ComputerName' {
            { Get-NetworkCIDR -ComputerName '' } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            { Get-NetworkCIDR -ComputerName $null } | Should -Throw
        }

        It 'Should reject invalid AddressFamily value' {
            { Get-NetworkCIDR -AddressFamily 'IPX' } | Should -Throw
        }

        It 'Should have IncludeVirtual switch parameter' {
            $cmd = Get-Command -Name 'Get-NetworkCIDR'
            $cmd.Parameters['IncludeVirtual'].SwitchParameter | Should -Be $true
        }

        It 'Should accept IPv4 AddressFamily' {
            $cmd = Get-Command -Name 'Get-NetworkCIDR'
            $cmd.Parameters['AddressFamily'].Attributes.ValidValues | Should -Contain 'IPv4'
        }

        It 'Should accept IPv6 AddressFamily' {
            $cmd = Get-Command -Name 'Get-NetworkCIDR'
            $cmd.Parameters['AddressFamily'].Attributes.ValidValues | Should -Contain 'IPv6'
        }

        It 'Should accept All AddressFamily' {
            $cmd = Get-Command -Name 'Get-NetworkCIDR'
            $cmd.Parameters['AddressFamily'].Attributes.ValidValues | Should -Contain 'All'
        }

        It 'Should support Credential parameter' {
            $cmd = Get-Command -Name 'Get-NetworkCIDR'
            $cmd.Parameters.Keys | Should -Contain 'Credential'
        }
    }
}
