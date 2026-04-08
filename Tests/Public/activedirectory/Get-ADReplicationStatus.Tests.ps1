#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    if (-not (Get-Command -Name 'Get-ADReplicationPartnerMetadata' -ErrorAction SilentlyContinue)) {
        function global:Get-ADReplicationPartnerMetadata { }
    }
    if (-not (Get-Command -Name 'Get-ADReplicationFailure' -ErrorAction SilentlyContinue)) {
        function global:Get-ADReplicationFailure { }
    }
    if (-not (Get-Command -Name 'Get-ADDomainController' -ErrorAction SilentlyContinue)) {
        function global:Get-ADDomainController { }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADReplicationPartnerMetadata' -ErrorAction SilentlyContinue)) {
            function script:Get-ADReplicationPartnerMetadata { }
        }
        if (-not (Get-Command -Name 'Get-ADReplicationFailure' -ErrorAction SilentlyContinue)) {
            function script:Get-ADReplicationFailure { }
        }
        if (-not (Get-Command -Name 'Get-ADDomainController' -ErrorAction SilentlyContinue)) {
            function script:Get-ADDomainController { }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Get-ADReplicationStatus' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:mockPartnerHealthy = [PSCustomObject]@{
            Partner                       = 'CN=NTDS Settings,CN=DC02,CN=Servers,CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com'
            Partition                     = 'DC=contoso,DC=com'
            LastReplicationAttempt        = (Get-Date).AddMinutes(-15)
            LastReplicationSuccess        = (Get-Date).AddMinutes(-15)
            LastReplicationResult         = 0
            ConsecutiveReplicationFailures = 0
        }

        $script:mockPartnerWarning = [PSCustomObject]@{
            Partner                       = 'CN=NTDS Settings,CN=DC03,CN=Servers,CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com'
            Partition                     = 'CN=Schema,CN=Configuration,DC=contoso,DC=com'
            LastReplicationAttempt        = (Get-Date).AddHours(-2)
            LastReplicationSuccess        = (Get-Date).AddHours(-4)
            LastReplicationResult         = 8524
            ConsecutiveReplicationFailures = 3
        }

        $script:mockPartnerCritical = [PSCustomObject]@{
            Partner                       = 'CN=NTDS Settings,CN=DC04,CN=Servers,CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com'
            Partition                     = 'DC=contoso,DC=com'
            LastReplicationAttempt        = (Get-Date).AddDays(-1)
            LastReplicationSuccess        = (Get-Date).AddDays(-3)
            LastReplicationResult         = 8456
            ConsecutiveReplicationFailures = 12
        }

        $script:mockDomainController = [PSCustomObject]@{
            HostName = 'DC01.contoso.com'
            Name     = 'DC01'
        }
    }

    Context -Name 'Happy path with explicit Server' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockPartnerHealthy, $script:mockPartnerWarning)
            }
            Mock -CommandName 'Get-ADReplicationFailure' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
            $script:results = Get-ADReplicationStatus -Server 'DC01.contoso.com'
        }

        It -Name 'Should return 2 replication status entries' -Test {
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should have correct PSTypeName' -Test {
            $script:results[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADReplicationStatus'
        }

        It -Name 'Should have Server set to the queried DC' -Test {
            $script:results[0].Server | Should -Be 'DC01.contoso.com'
        }

        It -Name 'Should extract partner name from DN' -Test {
            $script:results[0].Partner | Should -Be 'NTDS Settings'
        }
    }

    Context -Name 'Auto-discovery when no Server specified' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockDomainController)
            }
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockPartnerHealthy)
            }
            Mock -CommandName 'Get-ADReplicationFailure' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
            $script:results = Get-ADReplicationStatus
        }

        It -Name 'Should return results from discovered DC' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have Server from discovered DC hostname' -Test {
            $script:results[0].Server | Should -Be 'DC01.contoso.com'
        }
    }

    Context -Name 'Health status classification' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -ModuleName 'PSWinOps' -MockWith {
                return @(
                    $script:mockPartnerHealthy,
                    $script:mockPartnerWarning,
                    $script:mockPartnerCritical
                )
            }
            Mock -CommandName 'Get-ADReplicationFailure' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
            $script:results = Get-ADReplicationStatus -Server 'DC01'
        }

        It -Name 'Should classify result=0, failures=0 as Healthy' -Test {
            $healthy = $script:results | Where-Object -FilterScript { $_.ConsecutiveFailures -eq 0 }
            $healthy.Status | Should -Be 'Healthy'
        }

        It -Name 'Should classify 1-5 consecutive failures as Warning' -Test {
            $warning = $script:results | Where-Object -FilterScript { $_.ConsecutiveFailures -eq 3 }
            $warning.Status | Should -Be 'Warning'
        }

        It -Name 'Should classify more than 5 consecutive failures as Critical' -Test {
            $critical = $script:results | Where-Object -FilterScript { $_.ConsecutiveFailures -eq 12 }
            $critical.Status | Should -Be 'Critical'
        }
    }

    Context -Name 'Pipeline input is accepted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockPartnerHealthy)
            }
            Mock -CommandName 'Get-ADReplicationFailure' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
        }

        It -Name 'Should accept string input from pipeline' -Test {
            { 'DC01' | Get-ADReplicationStatus } | Should -Not -Throw
        }

        It -Name 'Should accept multiple strings from pipeline' -Test {
            $script:pipeResults = 'DC01', 'DC02' | Get-ADReplicationStatus
            $script:pipeResults | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Per-DC error handling' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -ModuleName 'PSWinOps' -MockWith {
                throw 'RPC server unavailable'
            }
            Mock -CommandName 'Get-ADReplicationFailure' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
        }

        It -Name 'Should not throw when a DC query fails' -Test {
            { Get-ADReplicationStatus -Server 'BADDC01' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should write an error when DC query fails' -Test {
            Get-ADReplicationStatus -Server 'BADDC01' -ErrorVariable 'capturedErr' -ErrorAction SilentlyContinue | Out-Null
            $capturedErr | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'DC discovery failure' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                throw 'Cannot contact domain'
            }
        }

        It -Name 'Should not throw when discovery fails' -Test {
            { Get-ADReplicationStatus -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should write an error when discovery fails' -Test {
            Get-ADReplicationStatus -ErrorVariable 'capturedErr' -ErrorAction SilentlyContinue | Out-Null
            $capturedErr | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Output object shape validation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockPartnerHealthy)
            }
            Mock -CommandName 'Get-ADReplicationFailure' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
            $script:result = Get-ADReplicationStatus -Server 'DC01'
            $script:propertyNames = $script:result[0].PSObject.Properties.Name
        }

        It -Name 'Should have Server property' -Test {
            $script:propertyNames | Should -Contain 'Server'
        }

        It -Name 'Should have Partner property' -Test {
            $script:propertyNames | Should -Contain 'Partner'
        }

        It -Name 'Should have Partition property' -Test {
            $script:propertyNames | Should -Contain 'Partition'
        }

        It -Name 'Should have PartitionDN property' -Test {
            $script:propertyNames | Should -Contain 'PartitionDN'
        }

        It -Name 'Should have LastAttempt property' -Test {
            $script:propertyNames | Should -Contain 'LastAttempt'
        }

        It -Name 'Should have LastSuccess property' -Test {
            $script:propertyNames | Should -Contain 'LastSuccess'
        }

        It -Name 'Should have LastResult property' -Test {
            $script:propertyNames | Should -Contain 'LastResult'
        }

        It -Name 'Should have ConsecutiveFailures property' -Test {
            $script:propertyNames | Should -Contain 'ConsecutiveFailures'
        }

        It -Name 'Should have Status property' -Test {
            $script:propertyNames | Should -Contain 'Status'
        }

        It -Name 'Should have Timestamp in ISO 8601 format' -Test {
            $script:result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }
    }
}
