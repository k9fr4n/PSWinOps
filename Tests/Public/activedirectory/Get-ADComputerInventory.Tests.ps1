#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only'
)]
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

Describe -Name 'Get-ADComputerInventory' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:mockComputer1 = [PSCustomObject]@{
            Name              = 'SRV01'
            SamAccountName    = 'SRV01
            Enabled           = $true
            LastLogonTimestamp = (Get-Date).AddDays(-1).ToFileTime()
            LockedOut         = $false
            PasswordExpired   = $false
            PasswordLastSet   = (Get-Date).AddDays(-15)
            whenChanged       = (Get-Date).AddDays(-2)
            whenCreated       = (Get-Date).AddDays(-180)
            OperatingSystem   = 'Windows Server 2022 Standard'
            DistinguishedName = 'CN=SRV01,OU=Servers,DC=contoso,DC=com'
        }

        $script:mockComputer2 = [PSCustomObject]@{
            Name              = 'PC-LEGACY'
            SamAccountName    = 'PC-LEGACY
            Enabled           = $false
            LastLogonTimestamp = (Get-Date).AddDays(-400).ToFileTime()
            LockedOut         = $false
            PasswordExpired   = $true
            PasswordLastSet   = (Get-Date).AddDays(-400)
            whenChanged       = (Get-Date).AddDays(-350)
            whenCreated       = (Get-Date).AddDays(-900)
            OperatingSystem   = 'Windows Server 2019 Standard'
            DistinguishedName = 'CN=PC-LEGACY,OU=Disabled,DC=contoso,DC=com'
        }

        $script:mockComputerNullLogon = [PSCustomObject]@{
            Name              = 'NEW-SRV'
            SamAccountName    = 'NEW-SRV
            Enabled           = $true
            LastLogonTimestamp = $null
            LockedOut         = $false
            PasswordExpired   = $false
            PasswordLastSet   = (Get-Date).AddDays(-1)
            whenChanged       = (Get-Date).AddDays(-1)
            whenCreated       = (Get-Date).AddDays(-1)
            OperatingSystem   = 'Windows Server 2022 Datacenter'
            DistinguishedName = 'CN=NEW-SRV,OU=Servers,DC=contoso,DC=com'
        }

        $script:mockComputerZeroLogon = [PSCustomObject]@{
            Name              = 'ZERO-SRV'
            SamAccountName    = 'ZERO-SRV
            Enabled           = $true
            LastLogonTimestamp = 0
            LockedOut         = $false
            PasswordExpired   = $false
            PasswordLastSet   = (Get-Date).AddDays(-2)
            whenChanged       = (Get-Date).AddDays(-2)
            whenCreated       = (Get-Date).AddDays(-2)
            OperatingSystem   = 'Windows Server 2022 Datacenter'
            DistinguishedName = 'CN=ZERO-SRV,OU=Staging,DC=contoso,DC=com'
        }
    }

    Context -Name 'Default behavior returns enabled computers' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockComputer1, $script:mockComputerNullLogon)
            }
            $script:results = Get-ADComputerInventory
        }

        It -Name 'Should return exactly 2 enabled computers' -Test {
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADComputerInventory'
        }

        It -Name 'Should return results sorted by Name' -Test {
            $script:results[0].Name | Should -Be 'NEW-SRV'
            $script:results[1].Name | Should -Be 'SRV01'
        }

        It -Name 'Should invoke Get-ADComputer exactly once' -Test {
            Should -Invoke -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'IncludeDisabled switch returns all computers' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockComputer1, $script:mockComputer2, $script:mockComputerNullLogon)
            }
            $script:results = Get-ADComputerInventory -IncludeDisabled
        }

        It -Name 'Should return all 3 computers including disabled' -Test {
            $script:results | Should -HaveCount 3
        }

        It -Name 'Should include the disabled computer' -Test {
            $found = $script:results | Where-Object -FilterScript { $_.Name -eq 'PC-LEGACY' }
            $found | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Server and Credential parameters are accepted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockComputer1)
            }
            $script:securePass = ConvertTo-SecureString -String 'TestPass123' -AsPlainText -Force
            $script:testCred = [PSCredential]::new('CONTOSO\admin', $script:securePass)
        }

        It -Name 'Should accept Server parameter without error' -Test {
            { Get-ADComputerInventory -Server 'dc01.contoso.com' } | Should -Not -Throw
        }

        It -Name 'Should accept Credential parameter without error' -Test {
            { Get-ADComputerInventory -Credential $script:testCred } | Should -Not -Throw
        }

        It -Name 'Should accept both parameters together' -Test {
            { Get-ADComputerInventory -Server 'dc01.contoso.com' -Credential $script:testCred } | Should -Not -Throw
        }
    }

    Context -Name 'Output object shape validation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockComputer1)
            }
            $script:result = Get-ADComputerInventory
            $script:propertyNames = $script:result[0].PSObject.Properties.Name
        }

        It -Name 'Should have Name property' -Test {
            $script:propertyNames | Should -Contain 'Name'
        }

        It -Name 'Should have SamAccountName property' -Test {
            $script:propertyNames | Should -Contain 'SamAccountName'
        }

        It -Name 'Should have Enabled property' -Test {
            $script:propertyNames | Should -Contain 'Enabled'
        }

        It -Name 'Should have LastLogonDate property' -Test {
            $script:propertyNames | Should -Contain 'LastLogonDate'
        }

        It -Name 'Should have OperatingSystem property' -Test {
            $script:propertyNames | Should -Contain 'OperatingSystem'
        }

        It -Name 'Should have WhenCreated property' -Test {
            $script:propertyNames | Should -Contain 'WhenCreated'
        }

        It -Name 'Should have WhenChanged property' -Test {
            $script:propertyNames | Should -Contain 'WhenChanged'
        }

        It -Name 'Should have OrganizationalUnit property' -Test {
            $script:propertyNames | Should -Contain 'OrganizationalUnit'
        }

        It -Name 'Should have Timestamp in ISO 8601 format' -Test {
            $script:result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It -Name 'Should extract OrganizationalUnit from DN' -Test {
            $script:result[0].OrganizationalUnit | Should -Be 'OU=Servers,DC=contoso,DC=com'
        }
    }

    Context -Name 'LastLogonDate conversion handles null and zero timestamps' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockComputerNullLogon, $script:mockComputerZeroLogon)
            }
            $script:results = Get-ADComputerInventory
        }

        It -Name 'Should return null LastLogonDate for null timestamp' -Test {
            $nullComputer = $script:results | Where-Object -FilterScript { $_.Name -eq 'NEW-SRV' }
            $nullComputer.LastLogonDate | Should -BeNullOrEmpty
        }

        It -Name 'Should return null LastLogonDate for zero timestamp' -Test {
            $zeroComputer = $script:results | Where-Object -FilterScript { $_.Name -eq 'ZERO-SRV' }
            $zeroComputer.LastLogonDate | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Empty result set produces warning' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return $null
            }
        }

        It -Name 'Should write a warning when no computers found' -Test {
            Get-ADComputerInventory -WarningVariable 'capturedWarn' -WarningAction SilentlyContinue | Out-Null
            $capturedWarn | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'AD query failure produces error' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                throw 'AD server unreachable'
            }
        }

        It -Name 'Should not throw a terminating error' -Test {
            { Get-ADComputerInventory -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
}
