#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
        function global:Get-ADUser { }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function script:Get-ADUser { }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Get-ADUserInventory' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:mockEnabledUser1 = [PSCustomObject]@{
            SamAccountName       = 'asmith'
            UserPrincipalName    = 'asmith@contoso.com'
            DisplayName          = 'Alice Smith'
            Enabled              = $true
            LastLogonTimestamp   = (Get-Date).AddDays(-3).ToFileTime()
            LockedOut            = $false
            PasswordLastSet      = (Get-Date).AddDays(-30)
            PasswordExpired      = $false
            PasswordNeverExpires = $false
            CannotChangePassword = $false
            DistinguishedName    = 'CN=Alice Smith,OU=Users,DC=contoso,DC=com'
        }

        $script:mockEnabledUser2 = [PSCustomObject]@{
            SamAccountName       = 'jdoe'
            UserPrincipalName    = 'jdoe@contoso.com'
            DisplayName          = 'John Doe'
            Enabled              = $true
            LastLogonTimestamp   = (Get-Date).AddDays(-90).ToFileTime()
            LockedOut            = $false
            PasswordLastSet      = (Get-Date).AddDays(-100)
            PasswordExpired      = $true
            PasswordNeverExpires = $false
            CannotChangePassword = $false
            DistinguishedName    = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
        }

        $script:mockDisabledUser = [PSCustomObject]@{
            SamAccountName       = 'bwilson'
            UserPrincipalName    = 'bwilson@contoso.com'
            DisplayName          = 'Bob Wilson'
            Enabled              = $false
            LastLogonTimestamp   = $null
            LockedOut            = $false
            PasswordLastSet      = (Get-Date).AddDays(-500)
            PasswordExpired      = $false
            PasswordNeverExpires = $true
            CannotChangePassword = $false
            DistinguishedName    = 'CN=Bob Wilson,OU=Disabled,DC=contoso,DC=com'
        }
    }

    Context -Name 'Default behavior returns enabled users only' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockEnabledUser1, $script:mockEnabledUser2)
            }
            $script:results = Get-ADUserInventory
        }

        It -Name 'Should return exactly 2 enabled users' -Test {
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADUserInventory'
        }

        It -Name 'Should sort results by SamAccountName' -Test {
            $script:results[0].SamAccountName | Should -Be 'asmith'
            $script:results[1].SamAccountName | Should -Be 'jdoe'
        }

    }

    Context -Name 'IncludeDisabled switch returns all users' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockEnabledUser1, $script:mockEnabledUser2, $script:mockDisabledUser)
            }
            $script:results = Get-ADUserInventory -IncludeDisabled
        }

        It -Name 'Should return all 3 users including disabled' -Test {
            $script:results | Should -HaveCount 3
        }

        It -Name 'Should include the disabled user' -Test {
            $found = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'bwilson' }
            $found | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Server and Credential parameters are accepted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockEnabledUser1)
            }
            $script:securePass = ConvertTo-SecureString -String 'TestPass123' -AsPlainText -Force
            $script:testCred = [PSCredential]::new('CONTOSO\admin', $script:securePass)
        }

        It -Name 'Should accept Server parameter without error' -Test {
            { Get-ADUserInventory -Server 'dc01.contoso.com' } | Should -Not -Throw
        }

        It -Name 'Should accept Credential parameter without error' -Test {
            { Get-ADUserInventory -Credential $script:testCred } | Should -Not -Throw
        }

        It -Name 'Should accept both parameters together' -Test {
            { Get-ADUserInventory -Server 'dc01.contoso.com' -Credential $script:testCred } | Should -Not -Throw
        }
    }

    Context -Name 'Output object shape validation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockEnabledUser1)
            }
            $script:result = Get-ADUserInventory
            $script:propertyNames = $script:result[0].PSObject.Properties.Name
        }

        It -Name 'Should have SamAccountName property' -Test {
            $script:propertyNames | Should -Contain 'SamAccountName'
        }

        It -Name 'Should have UserPrincipalName property' -Test {
            $script:propertyNames | Should -Contain 'UserPrincipalName'
        }

        It -Name 'Should have DisplayName property' -Test {
            $script:propertyNames | Should -Contain 'DisplayName'
        }

        It -Name 'Should have Enabled property' -Test {
            $script:propertyNames | Should -Contain 'Enabled'
        }

        It -Name 'Should have LastLogonDate property' -Test {
            $script:propertyNames | Should -Contain 'LastLogonDate'
        }

        It -Name 'Should have LockedOut property' -Test {
            $script:propertyNames | Should -Contain 'LockedOut'
        }

        It -Name 'Should have PasswordExpired property' -Test {
            $script:propertyNames | Should -Contain 'PasswordExpired'
        }

        It -Name 'Should have PasswordNeverExpires property' -Test {
            $script:propertyNames | Should -Contain 'PasswordNeverExpires'
        }

        It -Name 'Should have CannotChangePassword property' -Test {
            $script:propertyNames | Should -Contain 'CannotChangePassword'
        }

        It -Name 'Should have OrganizationalUnit property' -Test {
            $script:propertyNames | Should -Contain 'OrganizationalUnit'
        }

        It -Name 'Should have Timestamp in ISO 8601 format' -Test {
            $script:result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It -Name 'Should extract OrganizationalUnit from DN' -Test {
            $script:result[0].OrganizationalUnit | Should -Be 'OU=Users,DC=contoso,DC=com'
        }

        It -Name 'Should convert LastLogonDate to DateTime' -Test {
            $script:result[0].LastLogonDate | Should -BeOfType [DateTime]
        }
    }

    Context -Name 'LastLogonDate handles null timestamp' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockDisabledUser)
            }
            $script:results = Get-ADUserInventory -IncludeDisabled
        }

        It -Name 'Should return null LastLogonDate for null timestamp' -Test {
            $script:results[0].LastLogonDate | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Empty result set produces warning' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $null
            }
        }

        It -Name 'Should write a warning when no users found' -Test {
            Get-ADUserInventory -WarningVariable 'capturedWarn' -WarningAction SilentlyContinue | Out-Null
            $capturedWarn | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should return null when no users found' -Test {
            $script:emptyResult = Get-ADUserInventory -WarningAction SilentlyContinue
            $script:emptyResult | Should -BeNullOrEmpty
        }
    }

    Context -Name 'AD query failure produces error' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                throw 'AD server unreachable'
            }
        }

        It -Name 'Should not throw a terminating error' -Test {
            { Get-ADUserInventory -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should write an error' -Test {
            Get-ADUserInventory -ErrorVariable 'capturedErr' -ErrorAction SilentlyContinue | Out-Null
            $capturedErr | Should -Not -BeNullOrEmpty
        }
    }
}
