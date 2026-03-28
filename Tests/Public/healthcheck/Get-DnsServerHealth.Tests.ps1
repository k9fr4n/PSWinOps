#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Stub functions for cmdlets not available on CI runner
    function global:Get-DnsServerZone { }
    function global:Get-DnsServerForwarder { }
    function global:Get-DnsServerRootHint { }

}

AfterAll {
    Remove-Item -Path 'Function:Get-DnsServerZone' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-DnsServerForwarder' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-DnsServerRootHint' -ErrorAction SilentlyContinue
}


Describe 'Get-DnsServerHealth' {

    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus   = 'Running'
            ModuleAvailable = $true
            TotalZones      = 5
            PrimaryZones    = 3
            SecondaryZones  = 1
            PausedZones     = 0
            ForwarderCount  = 2
            RootHintsCount  = 13
            SelfResolution  = $true
        }

        $script:mockDnsService = [PSCustomObject]@{
            Name   = 'DNS'
            Status = 'Running'
        }

        $script:mockDnsServiceStopped = [PSCustomObject]@{
            Name   = 'DNS'
            Status = 'Stopped'
        }

        $script:mockDnsModule = [PSCustomObject]@{
            Name    = 'DnsServer'
            Version = [version]'2.0.0.0'
        }

        $script:mockZones = @(
            [PSCustomObject]@{ ZoneName = 'contoso.com'; ZoneType = 'Primary'; IsPaused = $false }
            [PSCustomObject]@{ ZoneName = 'fabrikam.com'; ZoneType = 'Primary'; IsPaused = $false }
            [PSCustomObject]@{ ZoneName = 'backup.com'; ZoneType = 'Primary'; IsPaused = $false }
            [PSCustomObject]@{ ZoneName = 'partner.com'; ZoneType = 'Secondary'; IsPaused = $false }
            [PSCustomObject]@{ ZoneName = '1.168.192.in-addr.arpa'; ZoneType = 'Primary'; IsPaused = $false }
        )

        $script:mockZonesWithPaused = @(
            [PSCustomObject]@{ ZoneName = 'contoso.com'; ZoneType = 'Primary'; IsPaused = $false }
            [PSCustomObject]@{ ZoneName = 'paused.com'; ZoneType = 'Primary'; IsPaused = $true }
            [PSCustomObject]@{ ZoneName = 'paused2.com'; ZoneType = 'Secondary'; IsPaused = $true }
        )

        $script:mockForwarder = [PSCustomObject]@{
            IPAddress = @('8.8.8.8', '8.8.4.4')
        }

        $script:mockRootHints = @(
            [PSCustomObject]@{ NameServer = 'a.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'b.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'c.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'd.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'e.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'f.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'g.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'h.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'i.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'j.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'k.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'l.root-servers.net' }
            [PSCustomObject]@{ NameServer = 'm.root-servers.net' }
        )

        $script:mockResolveDns = [PSCustomObject]@{
            Name    = 'localhost'
            Type    = 'A'
            Address = '127.0.0.1'
        }
    }

    Context 'RoleUnavailable - DnsServer module not available' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockDnsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:results = Get-DnsServerHealth
        }

        It -Name 'Should return a result object' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should set OverallHealth to RoleUnavailable' -Test {
            $script:results.OverallHealth | Should -Be 'RoleUnavailable'
        }

        It -Name 'Should set ServiceName to DNS' -Test {
            $script:results.ServiceName | Should -Be 'DNS'
        }
    }

    Context 'Healthy - All checks pass locally' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockDnsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDnsModule }
            Mock -CommandName 'Get-DnsServerZone' -ModuleName 'PSWinOps' -MockWith { return $script:mockZones }
            Mock -CommandName 'Get-DnsServerForwarder' -ModuleName 'PSWinOps' -MockWith { return $script:mockForwarder }
            Mock -CommandName 'Get-DnsServerRootHint' -ModuleName 'PSWinOps' -MockWith { return $script:mockRootHints }
            Mock -CommandName 'Resolve-DnsName' -ModuleName 'PSWinOps' -MockWith { return $script:mockResolveDns }
            $script:results = Get-DnsServerHealth
        }

        It -Name 'Should set ServiceStatus to Running' -Test {
            $script:results.ServiceStatus | Should -Be 'Running'
        }

        It -Name 'Should set TotalZones to 5' -Test {
            $script:results.TotalZones | Should -Be 5
        }

        It -Name 'Should set PrimaryZones to 4' -Test {
            $script:results.PrimaryZones | Should -Be 4
        }

        It -Name 'Should set SecondaryZones to 1' -Test {
            $script:results.SecondaryZones | Should -Be 1
        }

        It -Name 'Should set PausedZones to 0' -Test {
            $script:results.PausedZones | Should -Be 0
        }

        It -Name 'Should set ForwarderCount to 2' -Test {
            $script:results.ForwarderCount | Should -Be 2
        }

        It -Name 'Should set RootHintsCount to 13' -Test {
            $script:results.RootHintsCount | Should -Be 13
        }

        It -Name 'Should set SelfResolution to true' -Test {
            $script:results.SelfResolution | Should -BeTrue
        }

        It -Name 'Should set OverallHealth to Healthy' -Test {
            $script:results.OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should have a Timestamp value' -Test {
            $script:results.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Critical - DNS service stopped' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockDnsServiceStopped }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDnsModule }
            $script:results = Get-DnsServerHealth
        }

        It -Name 'Should set ServiceStatus to Stopped' -Test {
            $script:results.ServiceStatus | Should -Be 'Stopped'
        }

        It -Name 'Should set OverallHealth to Critical' -Test {
            $script:results.OverallHealth | Should -Be 'Critical'
        }
    }

    Context 'Critical - Self-resolution fails' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockDnsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDnsModule }
            Mock -CommandName 'Get-DnsServerZone' -ModuleName 'PSWinOps' -MockWith { return $script:mockZones }
            Mock -CommandName 'Get-DnsServerForwarder' -ModuleName 'PSWinOps' -MockWith { return $script:mockForwarder }
            Mock -CommandName 'Get-DnsServerRootHint' -ModuleName 'PSWinOps' -MockWith { return $script:mockRootHints }
            Mock -CommandName 'Resolve-DnsName' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:results = Get-DnsServerHealth
        }

        It -Name 'Should set SelfResolution to false' -Test {
            $script:results.SelfResolution | Should -BeFalse
        }

        It -Name 'Should set OverallHealth to Critical' -Test {
            $script:results.OverallHealth | Should -Be 'Critical'
        }
    }

    Context 'Degraded - Paused zones detected' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockDnsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDnsModule }
            Mock -CommandName 'Get-DnsServerZone' -ModuleName 'PSWinOps' -MockWith { return $script:mockZonesWithPaused }
            Mock -CommandName 'Get-DnsServerForwarder' -ModuleName 'PSWinOps' -MockWith { return $script:mockForwarder }
            Mock -CommandName 'Get-DnsServerRootHint' -ModuleName 'PSWinOps' -MockWith { return $script:mockRootHints }
            Mock -CommandName 'Resolve-DnsName' -ModuleName 'PSWinOps' -MockWith { return $script:mockResolveDns }
            $script:results = Get-DnsServerHealth
        }

        It -Name 'Should set PausedZones to 2' -Test {
            $script:results.PausedZones | Should -Be 2
        }

        It -Name 'Should set OverallHealth to Degraded' -Test {
            $script:results.OverallHealth | Should -Be 'Degraded'
        }
    }

    Context 'Degraded - No forwarders configured' {

        BeforeAll {
            $script:mockNoFwd = $script:mockRemoteData.Clone()
            $script:mockNoFwd.ForwarderCount = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockNoFwd }
            $script:results = Get-DnsServerHealth -ComputerName 'DNS01'
        }

        It -Name 'Should set ForwarderCount to 0' -Test {
            $script:results.ForwarderCount | Should -Be 0
        }

        It -Name 'Should set OverallHealth to Degraded' -Test {
            $script:results.OverallHealth | Should -Be 'Degraded'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = Get-DnsServerHealth -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should set OverallHealth to Healthy' -Test {
            $script:results.OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should return a result with Timestamp' -Test { $script:results.Timestamp | Should -Not -BeNullOrEmpty }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = @('SRV01', 'SRV02') | Get-DnsServerHealth
        }

        It -Name 'Should return distinct ComputerName values' -Test {
            $names = @($script:results) | Select-Object -ExpandProperty ComputerName -Unique
            @($names).Count | Should -Be 2
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write error for unreachable host' -Test {
            { Get-DnsServerHealth -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-DnsServerHealth -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-DnsServerHealth -ComputerName $null } | Should -Throw
        }
    }
}