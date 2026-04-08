#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    if (-not (Get-Command -Name 'Get-ADComputer' -ErrorAction SilentlyContinue)) {
        function global:Get-ADComputer { }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADComputer' -ErrorAction SilentlyContinue)) {
            function script:Get-ADComputer { }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Get-ADStaleComputer' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:mockStaleComputer = [PSCustomObject]@{
            Name                   = 'OLD-SRV01'
            SamAccountName         = "OLD-SRV01$"
            OperatingSystem        = 'Windows Server 2012 R2 Standard'
            OperatingSystemVersion = '6.3 (9600)'
            IPv4Address            = '10.0.1.50'
            LastLogonDate          = (Get-Date).AddDays(-200)
            PasswordLastSet        = (Get-Date).AddDays(-200)
            WhenCreated            = [datetime]::Parse('2018-06-15')
            Description            = 'Old file server'
            DistinguishedName      = 'CN=OLD-SRV01,OU=Servers,DC=contoso,DC=com'
        }

        $script:mockNeverLoggedComputer = [PSCustomObject]@{
            Name                   = 'GHOST-PC01'
            SamAccountName         = "GHOST-PC01$"
            Enabled                = $true
            OperatingSystem        = $null
            OperatingSystemVersion = $null
            IPv4Address            = $null
            LastLogonDate          = $null
            PasswordLastSet        = $null
            WhenCreated            = [datetime]::Parse('2024-01-10')
            Description            = 'Provisioned but never used'
            DistinguishedName      = 'CN=GHOST-PC01,OU=Workstations,DC=contoso,DC=com'
        }

        $script:mockRecentComputer = [PSCustomObject]@{
            Name                   = 'ACTIVE-DC01'
            SamAccountName         = "ACTIVE-DC01$"
            Enabled                = $true
            OperatingSystem        = 'Windows Server 2022 Datacenter'
            OperatingSystemVersion = '10.0 (20348)'
            IPv4Address            = '10.0.0.10'
            LastLogonDate          = (Get-Date).AddDays(-1)
            PasswordLastSet        = (Get-Date).AddDays(-15)
            WhenCreated            = [datetime]::Parse('2023-03-01')
            Description            = 'Primary DC'
            DistinguishedName      = 'CN=ACTIVE-DC01,OU=Domain Controllers,DC=contoso,DC=com'
        }

        $script:allComputers = @(
            $script:mockStaleComputer,
            $script:mockNeverLoggedComputer,
            $script:mockRecentComputer
        )
    }

    Context -Name 'Default behavior returns stale computers' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return $script:allComputers
            }
            $script:results = Get-ADStaleComputer
        }

        It -Name 'Should return stale and never-logged computers only' -Test {
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should exclude recently active computers' -Test {
            $script:results.Name | Should -Not -Contain 'ACTIVE-DC01'
        }

        It -Name 'Should include stale computers' -Test {
            $script:results.Name | Should -Contain 'OLD-SRV01'
        }

        It -Name 'Should include never-logged-in computers' -Test {
            $script:results.Name | Should -Contain 'GHOST-PC01'
        }

        It -Name 'Should have correct PSTypeName' -Test {
            $script:results[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADStaleComputer'
        }
    }

    Context -Name 'DaysInactive threshold' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return $script:allComputers
            }
        }

        It -Name 'Should default to 90 days without prompting' -Test {
            { Get-ADStaleComputer } | Should -Not -Throw
        }

        It -Name 'Should use custom threshold when specified' -Test {
            $script:results = Get-ADStaleComputer -DaysInactive 300
            $script:results.Name | Should -Not -Contain 'OLD-SRV01'
        }

        It -Name 'Should reject DaysInactive below 1' -Test {
            { Get-ADStaleComputer -DaysInactive 0 } | Should -Throw
        }

        It -Name 'Should reject DaysInactive above 3650' -Test {
            { Get-ADStaleComputer -DaysInactive 3651 } | Should -Throw
        }
    }

    Context -Name 'Operating system information' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockStaleComputer)
            }
            $script:results = Get-ADStaleComputer
        }

        It -Name 'Should include OperatingSystem property' -Test {
            $script:results[0].OperatingSystem | Should -Be 'Windows Server 2012 R2 Standard'
        }

        It -Name 'Should include OperatingSystemVersion property' -Test {
            $script:results[0].OperatingSystemVersion | Should -Be '6.3 (9600)'
        }

        It -Name 'Should include IPv4Address property' -Test {
            $script:results[0].IPv4Address | Should -Be '10.0.1.50'
        }
    }

    Context -Name 'Password age tracking' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockStaleComputer, $script:mockNeverLoggedComputer)
            }
            $script:results = Get-ADStaleComputer
        }

        It -Name 'Should calculate DaysSincePasswordSet for stale computer' -Test {
            $stale = $script:results | Where-Object -FilterScript { $_.Name -eq 'OLD-SRV01' }
            $stale.DaysSincePasswordSet | Should -BeGreaterOrEqual 200
        }

        It -Name 'Should have null DaysSincePasswordSet for never-logged computer' -Test {
            $ghost = $script:results | Where-Object -FilterScript { $_.Name -eq 'GHOST-PC01' }
            $ghost.DaysSincePasswordSet | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Server and SearchBase parameters' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockStaleComputer)
            }
        }

        It -Name 'Should accept Server parameter' -Test {
            { Get-ADStaleComputer -Server 'dc01.contoso.com' } | Should -Not -Throw
        }

        It -Name 'Should accept SearchBase parameter' -Test {
            { Get-ADStaleComputer -SearchBase 'OU=Servers,DC=contoso,DC=com' } | Should -Not -Throw
        }
    }

    Context -Name 'Output object shape' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockStaleComputer)
            }
            $script:result = Get-ADStaleComputer
            $script:propertyNames = $script:result[0].PSObject.Properties.Name
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProps = @(
                'Name', 'SamAccountName', 'Enabled', 'OperatingSystem',
                'OperatingSystemVersion', 'IPv4Address', 'LastLogonDate',
                'DaysSinceLogon', 'PasswordLastSet', 'DaysSincePasswordSet',
                'WhenCreated', 'Description', 'DistinguishedName', 'Timestamp'
            )
            foreach ($prop in $expectedProps) {
                $script:propertyNames | Should -Contain $prop
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $script:result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }
    }

    Context -Name 'Sort order' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return $script:allComputers
            }
            $script:results = Get-ADStaleComputer
        }

        It -Name 'Should sort by most stale first (never logged = first)' -Test {
            $script:results[0].Name | Should -Be 'GHOST-PC01'
        }
    }
}

