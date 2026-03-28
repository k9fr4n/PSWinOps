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

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'Output property completeness' {

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

        It 'Should contain all 12 expected properties' {
            $script:propResult = Export-NetworkConfig
            $script:propertyNames = $script:propResult.PSObject.Properties.Name
            $script:expectedProps = @(
                'PSTypeName', 'ComputerName', 'Hostname', 'Adapters', 'IPAddresses',
                'DnsServers', 'DnsSuffix', 'Routes', 'FirewallProfiles',
                'ListeningPorts', 'ARPCache', 'Timestamp'
            )
            foreach ($script:prop in $script:expectedProps) {
                $script:propertyNames | Should -Contain $script:prop
            }
        }
    }

    Context 'Timestamp ISO 8601 format' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClient' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetFirewallProfile' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith { @() }
        }

        It 'Should have Timestamp matching ISO 8601 pattern' {
            $script:tsResult = Export-NetworkConfig
            $script:tsResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context 'IncludeARP switch behavior' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClient' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetFirewallProfile' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetNeighbor' -MockWith {
                @([PSCustomObject]@{ IPAddress = '10.0.0.1'; LinkLayerAddress = 'AA-BB-CC-DD-EE-FF'; State = 'Reachable' })
            }
        }

        It 'Should have ARPCache populated when -IncludeARP is specified' {
            $script:arpResult = Export-NetworkConfig -IncludeARP
            $script:arpResult.ARPCache | Should -Not -BeNullOrEmpty
        }

        It 'Should have ARPCache empty when -IncludeARP is not specified' {
            $script:noArpResult = Export-NetworkConfig
            $script:noArpResult.ARPCache | Should -BeNullOrEmpty
        }
    }

    Context 'DnsSuffix populated' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClient' -MockWith {
                @([PSCustomObject]@{ ConnectionSpecificSuffix = 'corp.local' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetFirewallProfile' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith { @() }
        }

        It 'Should populate DnsSuffix from Get-DnsClient' {
            $script:dnsResult = Export-NetworkConfig
            $script:dnsResult.DnsSuffix | Should -Be 'corp.local'
        }
    }

    Context 'ListeningPorts populated by default' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClient' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetFirewallProfile' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @([PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 443; OwningProcess = 4; State = 'Listen' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                @([PSCustomObject]@{ Id = 4; ProcessName = 'System' })
            }
        }

        It 'Should include ListeningPorts by default' {
            $script:listenResult = Export-NetworkConfig
            $script:listenResult.ListeningPorts | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @{
                    Hostname = 'MOCK-HOST'; Adapters = @(); IPAddresses = @()
                    DnsServers = @(); DnsSuffix = $null; Routes = @()
                    FirewallProfiles = @(); ListeningPorts = @(); ARPCache = $null
                }
            }
        }

        It 'Should return 2 results for 2 piped machines' {
            $script:pipeResult = 'SRV01', 'SRV02' | Export-NetworkConfig
            @($script:pipeResult).Count | Should -Be 2
        }

        It 'Should have distinct ComputerName values' {
            $script:pipeResult = 'SRV01', 'SRV02' | Export-NetworkConfig
            $script:computerNames = $script:pipeResult | Select-Object -ExpandProperty ComputerName -Unique
            $script:computerNames | Should -Contain 'SRV01'
            $script:computerNames | Should -Contain 'SRV02'
        }
    }

    Context 'Verbose output' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetIPAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClientServerAddress' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-DnsClient' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetFirewallProfile' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith { @() }
        }

        It 'Should emit verbose messages containing function name' {
            $script:verboseOutput = Export-NetworkConfig -Verbose 4>&1
            $script:verboseMessages = @($script:verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $script:verboseMessages.Count | Should -BeGreaterOrEqual 1
            $script:verboseText = $script:verboseMessages | ForEach-Object { $_.Message }
            $script:verboseText -join ' ' | Should -Match 'Export-NetworkConfig'
        }
    }

    Context 'Credential parameter' {

        It 'Should have a Credential parameter of type PSCredential' {
            $script:cmdInfo = Get-Command -Name 'Export-NetworkConfig'
            $script:cmdInfo.Parameters['Credential'] | Should -Not -BeNullOrEmpty
            $script:cmdInfo.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }

        It 'Should not require Credential as mandatory' {
            $script:cmdInfo = Get-Command -Name 'Export-NetworkConfig'
            $script:isMandatory = $script:cmdInfo.Parameters['Credential'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
            $script:isMandatory | Should -Be $false
        }
    }

    Context 'Multi-machine export with Path' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @{
                    Hostname = 'MOCK-HOST'; Adapters = @(); IPAddresses = @()
                    DnsServers = @(); DnsSuffix = $null; Routes = @()
                    FirewallProfiles = @(); ListeningPorts = @(); ARPCache = $null
                }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Set-Content' -MockWith { }
        }

        It 'Should call Set-Content for each machine when using Path' {
            'SRV01', 'SRV02' | Export-NetworkConfig -Path 'C:\temp\netconfig.json'
            Should -Invoke -CommandName 'Set-Content' -ModuleName $script:ModuleName -Times 2
        }
    }
}
