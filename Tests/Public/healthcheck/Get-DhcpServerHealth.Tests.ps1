#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-DhcpServerHealth' {

    BeforeAll {
        $script:mockRemoteData = @(
            @{
                ServiceStatus   = 'Running'
                ModuleAvailable = $true
                ScopeId         = '10.0.1.0'
                ScopeName       = 'LAN Scope'
                ScopeState      = 'Active'
                AddressesTotal  = 200
                AddressesInUse  = 100
                AddressesFree   = 100
                PercentInUse    = [decimal]50
                FailoverPartner = 'None'
                FailoverState   = 'None'
            }
        )

        $script:mockDhcpService = [PSCustomObject]@{
            Name   = 'DHCPServer'
            Status = 'Running'
        }

        $script:mockDhcpModule = [PSCustomObject]@{
            Name    = 'DhcpServer'
            Version = [version]'2.0.0.0'
        }

        $script:mockScope = [PSCustomObject]@{
            ScopeId = '10.0.1.0'
            Name    = 'LAN Scope'
            State   = 'Active'
        }

        $script:mockScopeStats = [PSCustomObject]@{
            AddressesFree   = 100
            AddressesInUse  = 100
            PercentageInUse = [decimal]50
        }
    }

    Context 'RoleUnavailable - DhcpServer module not available' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockDhcpService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:results = Get-DhcpServerHealth
        }

        It -Name 'Should return a result object' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should set OverallHealth to RoleUnavailable' -Test {
            $script:results.OverallHealth | Should -Be 'RoleUnavailable'
        }

        It -Name 'Should set ServiceName to DHCPServer' -Test {
            $script:results.ServiceName | Should -Be 'DHCPServer'
        }
    }

    Context 'Healthy - One scope at 50 percent usage' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockDhcpService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDhcpModule }
            Mock -CommandName 'Get-DhcpServerv4Scope' -ModuleName 'PSWinOps' -MockWith { return $script:mockScope }
            Mock -CommandName 'Get-DhcpServerv4ScopeStatistics' -ModuleName 'PSWinOps' -MockWith { return $script:mockScopeStats }
            Mock -CommandName 'Get-DhcpServerv4Failover' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:results = Get-DhcpServerHealth
        }

        It -Name 'Should set ServiceStatus to Running' -Test {
            $script:results.ServiceStatus | Should -Be 'Running'
        }

        It -Name 'Should set ScopeId to 10.0.1.0' -Test {
            $script:results.ScopeId | Should -Be '10.0.1.0'
        }

        It -Name 'Should set ScopeName to LAN Scope' -Test {
            $script:results.ScopeName | Should -Be 'LAN Scope'
        }

        It -Name 'Should set ScopeState to Active' -Test {
            $script:results.ScopeState | Should -Be 'Active'
        }

        It -Name 'Should set AddressesTotal to 200' -Test {
            $script:results.AddressesTotal | Should -Be 200
        }

        It -Name 'Should set PercentInUse to 50' -Test {
            $script:results.PercentInUse | Should -Be 50
        }

        It -Name 'Should set OverallHealth to Healthy' -Test {
            $script:results.OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should have a Timestamp value' -Test {
            $script:results.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Critical - DHCP service stopped' {

        BeforeAll {
            $script:mockStopped = @(
                @{
                    ServiceStatus   = 'Stopped'
                    ModuleAvailable = $true
                    ScopeId         = 'N/A'
                    ScopeName       = 'N/A'
                    ScopeState      = 'N/A'
                    AddressesTotal  = 0
                    AddressesInUse  = 0
                    AddressesFree   = 0
                    PercentInUse    = [decimal]0
                    FailoverPartner = 'None'
                    FailoverState   = 'None'
                }
            )
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStopped }
            $script:results = Get-DhcpServerHealth -ComputerName 'DHCP01'
        }

        It -Name 'Should set ServiceStatus to Stopped' -Test {
            $script:results.ServiceStatus | Should -Be 'Stopped'
        }

        It -Name 'Should set OverallHealth to Critical' -Test {
            $script:results.OverallHealth | Should -Be 'Critical'
        }
    }

    Context 'Critical - Inactive scope with active leases' {

        BeforeAll {
            $script:mockInactive = @(
                @{
                    ServiceStatus   = 'Running'
                    ModuleAvailable = $true
                    ScopeId         = '10.0.2.0'
                    ScopeName       = 'Legacy Scope'
                    ScopeState      = 'Inactive'
                    AddressesTotal  = 100
                    AddressesInUse  = 15
                    AddressesFree   = 85
                    PercentInUse    = [decimal]15
                    FailoverPartner = 'None'
                    FailoverState   = 'None'
                }
            )
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockInactive }
            $script:results = Get-DhcpServerHealth -ComputerName 'DHCP01'
        }

        It -Name 'Should set ScopeState to Inactive' -Test {
            $script:results.ScopeState | Should -Be 'Inactive'
        }

        It -Name 'Should set AddressesInUse to 15' -Test {
            $script:results.AddressesInUse | Should -Be 15
        }

        It -Name 'Should set OverallHealth to Critical' -Test {
            $script:results.OverallHealth | Should -Be 'Critical'
        }
    }

    Context 'Degraded - Scope utilization above 90 percent' {

        BeforeAll {
            $script:mockHighUsage = @(
                @{
                    ServiceStatus   = 'Running'
                    ModuleAvailable = $true
                    ScopeId         = '10.0.1.0'
                    ScopeName       = 'LAN Scope'
                    ScopeState      = 'Active'
                    AddressesTotal  = 200
                    AddressesInUse  = 190
                    AddressesFree   = 10
                    PercentInUse    = [decimal]95
                    FailoverPartner = 'None'
                    FailoverState   = 'None'
                }
            )
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockHighUsage }
            $script:results = Get-DhcpServerHealth -ComputerName 'DHCP01'
        }

        It -Name 'Should set PercentInUse to 95' -Test {
            $script:results.PercentInUse | Should -Be 95
        }

        It -Name 'Should set OverallHealth to Degraded' -Test {
            $script:results.OverallHealth | Should -Be 'Degraded'
        }
    }

    Context 'Degraded - Failover communication interrupted' {

        BeforeAll {
            $script:mockFailover = @(
                @{
                    ServiceStatus   = 'Running'
                    ModuleAvailable = $true
                    ScopeId         = '10.0.1.0'
                    ScopeName       = 'LAN Scope'
                    ScopeState      = 'Active'
                    AddressesTotal  = 200
                    AddressesInUse  = 100
                    AddressesFree   = 100
                    PercentInUse    = [decimal]50
                    FailoverPartner = 'DHCP02.contoso.com'
                    FailoverState   = 'CommunicationInterrupted'
                }
            )
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockFailover }
            $script:results = Get-DhcpServerHealth -ComputerName 'DHCP01'
        }

        It -Name 'Should set FailoverPartner to DHCP02.contoso.com' -Test {
            $script:results.FailoverPartner | Should -Be 'DHCP02.contoso.com'
        }

        It -Name 'Should set FailoverState to CommunicationInterrupted' -Test {
            $script:results.FailoverState | Should -Be 'CommunicationInterrupted'
        }

        It -Name 'Should set OverallHealth to Degraded' -Test {
            $script:results.OverallHealth | Should -Be 'Degraded'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = Get-DhcpServerHealth -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should set OverallHealth to Healthy' -Test {
            $script:results.OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should call Invoke-Command exactly once' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = @('SRV01', 'SRV02') | Get-DhcpServerHealth
        }

        It -Name 'Should call Invoke-Command for each machine' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write error for unreachable host' -Test {
            { Get-DhcpServerHealth -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-DhcpServerHealth -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-DhcpServerHealth -ComputerName $null } | Should -Throw
        }
    }
}