#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    $adCmdlets = @(
        'Get-ADReplicationSite', 'Get-ADReplicationSubnet',
        'Get-ADReplicationSiteLink', 'Get-ADDomainController'
    )
    foreach ($cmdlet in $adCmdlets) {
        if (-not (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue)) {
            New-Item -Path "function:global:$cmdlet" -Value { } -Force | Out-Null
        }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        $adCmdlets = @(
            'Get-ADReplicationSite', 'Get-ADReplicationSubnet',
            'Get-ADReplicationSiteLink', 'Get-ADDomainController'
        )
        foreach ($cmdlet in $adCmdlets) {
            if (-not (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue)) {
                New-Item -Path "function:script:$cmdlet" -Value { } -Force | Out-Null
            }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Get-ADSiteTopology' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:parisDN = 'CN=Paris,CN=Sites,CN=Configuration,DC=contoso,DC=com'
        $script:lyonDN = 'CN=Lyon,CN=Sites,CN=Configuration,DC=contoso,DC=com'
        $script:emptyDN = 'CN=EmptySite,CN=Sites,CN=Configuration,DC=contoso,DC=com'

        $script:mockSites = @(
            [PSCustomObject]@{
                Name              = 'Paris'
                Description       = 'Main datacenter'
                DistinguishedName = $script:parisDN
            }
            [PSCustomObject]@{
                Name              = 'Lyon'
                Description       = 'DR site'
                DistinguishedName = $script:lyonDN
            }
            [PSCustomObject]@{
                Name              = 'EmptySite'
                Description       = 'Unused site'
                DistinguishedName = $script:emptyDN
            }
        )

        $script:mockSubnets = @(
            [PSCustomObject]@{
                Name        = '10.0.0.0/24'
                Site        = $script:parisDN
                Location    = 'Paris DC1'
                Description = 'Server VLAN'
            }
            [PSCustomObject]@{
                Name        = '10.0.1.0/24'
                Site        = $script:parisDN
                Location    = 'Paris DC1'
                Description = 'User VLAN'
            }
            [PSCustomObject]@{
                Name        = '10.1.0.0/24'
                Site        = $script:lyonDN
                Location    = 'Lyon'
                Description = 'DR VLAN'
            }
        )

        $script:mockSiteLinks = @(
            [PSCustomObject]@{
                Name                          = 'Paris-Lyon'
                Cost                          = 100
                ReplicationFrequencyInMinutes = 15
                SitesIncluded                 = @($script:parisDN, $script:lyonDN)
                Description                   = 'Main replication link'
            }
        )

        $script:mockDCs = @(
            [PSCustomObject]@{ HostName = 'DC01.contoso.com'; Site = 'Paris' }
            [PSCustomObject]@{ HostName = 'DC02.contoso.com'; Site = 'Paris' }
            [PSCustomObject]@{ HostName = 'DC03.contoso.com'; Site = 'Lyon' }
        )

        Mock -CommandName 'Get-ADReplicationSite' -ModuleName 'PSWinOps' -MockWith { return $script:mockSites }
        Mock -CommandName 'Get-ADReplicationSubnet' -ModuleName 'PSWinOps' -MockWith { return $script:mockSubnets }
        Mock -CommandName 'Get-ADReplicationSiteLink' -ModuleName 'PSWinOps' -MockWith { return $script:mockSiteLinks }
        Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith { return $script:mockDCs }
    }

    Context -Name 'Happy path - returns all sites' -Fixture {

        BeforeAll {
            $script:results = Get-ADSiteTopology
        }

        It -Name 'Should return one object per site' -Test {
            $script:results | Should -HaveCount 3
        }

        It -Name 'Should have correct PSTypeName' -Test {
            $script:results[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADSiteTopology'
        }

        It -Name 'Should be sorted alphabetically by site name' -Test {
            $script:results[0].SiteName | Should -Be 'EmptySite'
            $script:results[1].SiteName | Should -Be 'Lyon'
            $script:results[2].SiteName | Should -Be 'Paris'
        }
    }

    Context -Name 'Subnet mapping' -Fixture {

        BeforeAll {
            $script:results = Get-ADSiteTopology
            $script:paris = $script:results | Where-Object -FilterScript { $_.SiteName -eq 'Paris' }
            $script:lyon = $script:results | Where-Object -FilterScript { $_.SiteName -eq 'Lyon' }
            $script:empty = $script:results | Where-Object -FilterScript { $_.SiteName -eq 'EmptySite' }
        }

        It -Name 'Should map 2 subnets to Paris' -Test {
            $script:paris.SubnetCount | Should -Be 2
        }

        It -Name 'Should map 1 subnet to Lyon' -Test {
            $script:lyon.SubnetCount | Should -Be 1
        }

        It -Name 'Should map 0 subnets to EmptySite' -Test {
            $script:empty.SubnetCount | Should -Be 0
        }

        It -Name 'Should have comma-separated subnet names' -Test {
            $script:paris.Subnets | Should -Match '10\.0\.0\.0/24'
            $script:paris.Subnets | Should -Match '10\.0\.1\.0/24'
        }
    }

    Context -Name 'Site link mapping' -Fixture {

        BeforeAll {
            $script:results = Get-ADSiteTopology
            $script:paris = $script:results | Where-Object -FilterScript { $_.SiteName -eq 'Paris' }
            $script:empty = $script:results | Where-Object -FilterScript { $_.SiteName -eq 'EmptySite' }
        }

        It -Name 'Should map site link to Paris' -Test {
            $script:paris.SiteLinkCount | Should -Be 1
            $script:paris.SiteLinks | Should -Be 'Paris-Lyon'
        }

        It -Name 'Should have 0 site links for EmptySite' -Test {
            $script:empty.SiteLinkCount | Should -Be 0
        }

        It -Name 'Should expose site link details with cost and interval' -Test {
            $script:paris.SiteLinkDetails[0].Cost | Should -Be 100
            $script:paris.SiteLinkDetails[0].ReplicationInterval | Should -Be 15
        }
    }

    Context -Name 'Domain controller mapping' -Fixture {

        BeforeAll {
            $script:results = Get-ADSiteTopology
            $script:paris = $script:results | Where-Object -FilterScript { $_.SiteName -eq 'Paris' }
            $script:lyon = $script:results | Where-Object -FilterScript { $_.SiteName -eq 'Lyon' }
            $script:empty = $script:results | Where-Object -FilterScript { $_.SiteName -eq 'EmptySite' }
        }

        It -Name 'Should map 2 DCs to Paris' -Test {
            $script:paris.DCCount | Should -Be 2
        }

        It -Name 'Should map 1 DC to Lyon' -Test {
            $script:lyon.DCCount | Should -Be 1
        }

        It -Name 'Should map 0 DCs to EmptySite' -Test {
            $script:empty.DCCount | Should -Be 0
        }
    }

    Context -Name 'Server parameter' -Fixture {

        It -Name 'Should accept Server parameter' -Test {
            { Get-ADSiteTopology -Server 'dc01.contoso.com' } | Should -Not -Throw
        }
    }

    Context -Name 'Error handling' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADReplicationSite' -ModuleName 'PSWinOps' -MockWith {
                throw 'Access denied'
            }
        }

        It -Name 'Should not throw on failure' -Test {
            { Get-ADSiteTopology -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context -Name 'Output shape' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADReplicationSite' -ModuleName 'PSWinOps' -MockWith { return $script:mockSites }
            $script:result = (Get-ADSiteTopology)[0]
            $script:propertyNames = $script:result.PSObject.Properties.Name
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProps = @(
                'SiteName', 'Description', 'SubnetCount', 'Subnets', 'SubnetDetails',
                'SiteLinkCount', 'SiteLinks', 'SiteLinkDetails',
                'DomainControllers', 'DCCount', 'DistinguishedName', 'Timestamp'
            )
            foreach ($prop in $expectedProps) {
                $script:propertyNames | Should -Contain $prop
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }
    }
}
