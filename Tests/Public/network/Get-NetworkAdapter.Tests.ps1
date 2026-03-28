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

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'Output property completeness' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Ethernet'; InterfaceDescription = 'Intel I350'; Status = 'Up'
                    LinkSpeed = '1 Gbps'; MacAddress = 'AA-BB-CC-DD-EE-FF'; MtuSize = 1500
                    ifIndex = 5; MediaType = '802.3'; DriverVersion = '12.18.9.23'; VlanID = 100
                })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; IPAddress = '192.168.1.10'; PrefixLength = 24; AddressFamily = 2; PrefixOrigin = 'Dhcp' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; ServerAddresses = @('10.0.0.1') })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; InterfaceAlias = 'Ethernet' })
            }
        }

        It 'Should contain all expected properties' {
            $script:propResult = Get-NetworkAdapter
            $script:propertyNames = $script:propResult.PSObject.Properties.Name
            $script:expectedProps = @(
                'ComputerName', 'Name', 'Description', 'Status', 'Speed',
                'MacAddress', 'IPv4Address', 'SubnetPrefix', 'IPv6Address', 'Gateway',
                'DnsServers', 'MTU', 'InterfaceIndex', 'MediaType', 'DriverVersion',
                'VlanID', 'Timestamp'
            )
            foreach ($script:prop in $script:expectedProps) {
                $script:propertyNames | Should -Contain $script:prop
            }
        }

        It 'Should have PSTypeName PSWinOps.NetworkAdapterInfo' {
            $script:propResult = Get-NetworkAdapter
            $script:propResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.NetworkAdapterInfo'
        }
    }

    Context 'Timestamp ISO 8601 format' {

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
                @([PSCustomObject]@{ InterfaceIndex = 5; ServerAddresses = @('10.0.0.1') })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; InterfaceAlias = 'Ethernet' })
            }
        }

        It 'Should have Timestamp matching ISO 8601 pattern' {
            $script:tsResult = Get-NetworkAdapter
            $script:tsResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context 'IncludeDisabled switch behavior' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith {
                @(
                    [PSCustomObject]@{
                        Name = 'Ethernet'; InterfaceDescription = 'Intel I350'; Status = 'Up'
                        LinkSpeed = '1 Gbps'; MacAddress = 'AA-BB-CC-DD-EE-FF'; MtuSize = 1500
                        ifIndex = 5; MediaType = '802.3'; DriverVersion = '12.18.9.23'; VlanID = $null
                    },
                    [PSCustomObject]@{
                        Name = 'Wi-Fi'; InterfaceDescription = 'Wireless NIC'; Status = 'Disabled'
                        LinkSpeed = ''; MacAddress = '11-22-33-44-55-66'; MtuSize = 1500
                        ifIndex = 8; MediaType = ''; DriverVersion = '2.0.0'; VlanID = $null
                    }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; IPAddress = '192.168.1.10'; PrefixLength = 24; AddressFamily = 2; PrefixOrigin = 'Dhcp' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; ServerAddresses = @('10.0.0.1') })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; InterfaceAlias = 'Ethernet' })
            }
        }

        It 'Should return only Up adapters without IncludeDisabled' {
            $script:upOnly = Get-NetworkAdapter
            @($script:upOnly).Count | Should -Be 1
            $script:upOnly.Status | Should -Be 'Up'
        }

        It 'Should return both adapters with IncludeDisabled' {
            $script:allAdapters = Get-NetworkAdapter -IncludeDisabled
            @($script:allAdapters).Count | Should -Be 2
        }
    }

    Context 'InterfaceName filter' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith {
                @(
                    [PSCustomObject]@{
                        Name = 'Ethernet'; InterfaceDescription = 'Intel I350'; Status = 'Up'
                        LinkSpeed = '1 Gbps'; MacAddress = 'AA-BB-CC-DD-EE-FF'; MtuSize = 1500
                        ifIndex = 5; MediaType = '802.3'; DriverVersion = '12.18.9.23'; VlanID = $null
                    },
                    [PSCustomObject]@{
                        Name = 'Wi-Fi'; InterfaceDescription = 'Wireless NIC'; Status = 'Up'
                        LinkSpeed = '300 Mbps'; MacAddress = '11-22-33-44-55-66'; MtuSize = 1500
                        ifIndex = 8; MediaType = 'Native 802.11'; DriverVersion = '2.0.0'; VlanID = $null
                    }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @(
                    [PSCustomObject]@{ InterfaceIndex = 5; IPAddress = '192.168.1.10'; PrefixLength = 24; AddressFamily = 2; PrefixOrigin = 'Dhcp' },
                    [PSCustomObject]@{ InterfaceIndex = 8; IPAddress = '192.168.1.20'; PrefixLength = 24; AddressFamily = 2; PrefixOrigin = 'Dhcp' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith {
                @(
                    [PSCustomObject]@{ InterfaceIndex = 5; ServerAddresses = @('10.0.0.1') },
                    [PSCustomObject]@{ InterfaceIndex = 8; ServerAddresses = @('10.0.0.1') }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; InterfaceAlias = 'Ethernet' })
            }
        }

        It 'Should return only Ethernet when filtering with Eth*' {
            $script:filtered = Get-NetworkAdapter -InterfaceName 'Eth*'
            @($script:filtered).Count | Should -Be 1
            $script:filtered.Name | Should -Be 'Ethernet'
        }
    }

    Context 'Multiple adapters returned' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith {
                @(
                    [PSCustomObject]@{
                        Name = 'Ethernet'; InterfaceDescription = 'Intel I350'; Status = 'Up'
                        LinkSpeed = '1 Gbps'; MacAddress = 'AA-BB-CC-DD-EE-FF'; MtuSize = 1500
                        ifIndex = 5; MediaType = '802.3'; DriverVersion = '12.18.9.23'; VlanID = $null
                    },
                    [PSCustomObject]@{
                        Name = 'Ethernet2'; InterfaceDescription = 'Intel I350 #2'; Status = 'Up'
                        LinkSpeed = '1 Gbps'; MacAddress = 'FF-EE-DD-CC-BB-AA'; MtuSize = 1500
                        ifIndex = 6; MediaType = '802.3'; DriverVersion = '12.18.9.23'; VlanID = $null
                    }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith {
                @(
                    [PSCustomObject]@{ InterfaceIndex = 5; IPAddress = '192.168.1.10'; PrefixLength = 24; AddressFamily = 2; PrefixOrigin = 'Dhcp' },
                    [PSCustomObject]@{ InterfaceIndex = 6; IPAddress = '192.168.2.10'; PrefixLength = 24; AddressFamily = 2; PrefixOrigin = 'Dhcp' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith {
                @(
                    [PSCustomObject]@{ InterfaceIndex = 5; ServerAddresses = @('10.0.0.1') },
                    [PSCustomObject]@{ InterfaceIndex = 6; ServerAddresses = @('10.0.0.2') }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; InterfaceAlias = 'Ethernet' })
            }
        }

        It 'Should return 2 adapter results' {
            $script:multiResult = Get-NetworkAdapter
            @($script:multiResult).Count | Should -Be 2
        }
    }

    Context 'No adapters found' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith { @() }
        }

        It 'Should return empty result when no adapters exist' {
            $script:emptyResult = Get-NetworkAdapter
            $script:emptyResult | Should -BeNullOrEmpty
        }
    }

    Context 'Verbose output' {

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
                @([PSCustomObject]@{ InterfaceIndex = 5; ServerAddresses = @('10.0.0.1') })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                @([PSCustomObject]@{ InterfaceIndex = 5; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; InterfaceAlias = 'Ethernet' })
            }
        }

        It 'Should emit verbose messages containing function name' {
            $script:verboseOutput = Get-NetworkAdapter -Verbose 4>&1
            $script:verboseMessages = @($script:verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $script:verboseMessages.Count | Should -BeGreaterOrEqual 1
            $script:verboseText = $script:verboseMessages | ForEach-Object { $_.Message }
            $script:verboseText -join ' ' | Should -Match 'Get-NetworkAdapter'
        }
    }

    Context 'Credential parameter' {

        It 'Should have a Credential parameter of type PSCredential' {
            $script:cmdInfo = Get-Command -Name 'Get-NetworkAdapter'
            $script:cmdInfo.Parameters['Credential'] | Should -Not -BeNullOrEmpty
            $script:cmdInfo.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }

        It 'Should not require Credential as mandatory' {
            $script:cmdInfo = Get-Command -Name 'Get-NetworkAdapter'
            $script:isMandatory = $script:cmdInfo.Parameters['Credential'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
            $script:isMandatory | Should -Be $false
        }
    }
}
