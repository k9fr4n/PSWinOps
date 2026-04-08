#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    if (-not (Get-Command -Name 'Get-ADGroup' -ErrorAction SilentlyContinue)) {
        function global:Get-ADGroup { }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADGroup' -ErrorAction SilentlyContinue)) {
            function script:Get-ADGroup { }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Get-ADGroupInventory' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:mockGroupWith5Members = [PSCustomObject]@{
            Name              = 'Domain Admins'
            SamAccountName    = 'Domain Admins'
            GroupScope        = 'Global'
            GroupCategory     = 'Security'
            Description       = 'Designated administrators of the domain'
            DistinguishedName = 'CN=Domain Admins,CN=Users,DC=contoso,DC=com'
            Member            = @(
                'CN=Admin1,OU=Admins,DC=contoso,DC=com',
                'CN=Admin2,OU=Admins,DC=contoso,DC=com',
                'CN=Admin3,OU=Admins,DC=contoso,DC=com',
                'CN=Admin4,OU=Admins,DC=contoso,DC=com',
                'CN=Admin5,OU=Admins,DC=contoso,DC=com'
            )
        }

        $script:mockGroupEmpty = [PSCustomObject]@{
            Name              = 'Legacy Distribution'
            SamAccountName    = 'Legacy Distribution'
            GroupScope        = 'Universal'
            GroupCategory     = 'Distribution'
            Description       = 'Old distribution group - unused'
            DistinguishedName = 'CN=Legacy Distribution,OU=Groups,DC=contoso,DC=com'
            Member            = @()
        }

        $script:mockGroupWith2Members = [PSCustomObject]@{
            Name              = 'IT Support'
            SamAccountName    = 'IT Support'
            GroupScope        = 'DomainLocal'
            GroupCategory     = 'Security'
            Description       = 'IT support team members'
            DistinguishedName = 'CN=IT Support,OU=Groups,DC=contoso,DC=com'
            Member            = @(
                'CN=Tech1,OU=IT,DC=contoso,DC=com',
                'CN=Tech2,OU=IT,DC=contoso,DC=com'
            )
        }
    }

    Context -Name 'Default behavior excludes empty groups' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @(
                    $script:mockGroupWith5Members,
                    $script:mockGroupEmpty,
                    $script:mockGroupWith2Members
                )
            }
            $script:results = Get-ADGroupInventory
        }

        It -Name 'Should return only non-empty groups' -Test {
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should not include the empty group' -Test {
            $found = $script:results | Where-Object -FilterScript { $_.Name -eq 'Legacy Distribution' }
            $found | Should -BeNullOrEmpty
        }

        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADGroupInventory'
        }

    }

    Context -Name 'IncludeEmpty switch returns all groups' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @(
                    $script:mockGroupWith5Members,
                    $script:mockGroupEmpty,
                    $script:mockGroupWith2Members
                )
            }
            $script:results = Get-ADGroupInventory -IncludeEmpty
        }

        It -Name 'Should return all 3 groups including empty' -Test {
            $script:results | Should -HaveCount 3
        }

        It -Name 'Should include the empty group in results' -Test {
            $found = $script:results | Where-Object -FilterScript { $_.Name -eq 'Legacy Distribution' }
            $found | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'MemberCount accuracy' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @(
                    $script:mockGroupWith5Members,
                    $script:mockGroupEmpty,
                    $script:mockGroupWith2Members
                )
            }
            $script:results = Get-ADGroupInventory -IncludeEmpty
        }

        It -Name 'Should report 5 members for Domain Admins' -Test {
            $found = $script:results | Where-Object -FilterScript { $_.Name -eq 'Domain Admins' }
            $found.MemberCount | Should -Be 5
        }

        It -Name 'Should report 0 members for empty group' -Test {
            $found = $script:results | Where-Object -FilterScript { $_.Name -eq 'Legacy Distribution' }
            $found.MemberCount | Should -Be 0
        }

        It -Name 'Should report 2 members for IT Support' -Test {
            $found = $script:results | Where-Object -FilterScript { $_.Name -eq 'IT Support' }
            $found.MemberCount | Should -Be 2
        }
    }

    Context -Name 'Server and Credential parameters are accepted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroupWith5Members)
            }
            $script:securePass = ConvertTo-SecureString -String 'TestPass123' -AsPlainText -Force
            $script:testCred = [PSCredential]::new('CONTOSO\admin', $script:securePass)
        }

        It -Name 'Should accept Server parameter without error' -Test {
            { Get-ADGroupInventory -Server 'dc01.contoso.com' } | Should -Not -Throw
        }

        It -Name 'Should accept Credential parameter without error' -Test {
            { Get-ADGroupInventory -Credential $script:testCred } | Should -Not -Throw
        }

        It -Name 'Should accept both parameters together' -Test {
            { Get-ADGroupInventory -Server 'dc01.contoso.com' -Credential $script:testCred } | Should -Not -Throw
        }
    }

    Context -Name 'Output object shape validation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroupWith5Members)
            }
            $script:result = Get-ADGroupInventory
            $script:propertyNames = $script:result[0].PSObject.Properties.Name
        }

        It -Name 'Should have Name property' -Test {
            $script:propertyNames | Should -Contain 'Name'
        }

        It -Name 'Should have SamAccountName property' -Test {
            $script:propertyNames | Should -Contain 'SamAccountName'
        }

        It -Name 'Should have GroupScope property' -Test {
            $script:propertyNames | Should -Contain 'GroupScope'
        }

        It -Name 'Should have GroupCategory property' -Test {
            $script:propertyNames | Should -Contain 'GroupCategory'
        }

        It -Name 'Should have MemberCount property' -Test {
            $script:propertyNames | Should -Contain 'MemberCount'
        }

        It -Name 'Should have Description property' -Test {
            $script:propertyNames | Should -Contain 'Description'
        }

        It -Name 'Should have OrganizationalUnit property' -Test {
            $script:propertyNames | Should -Contain 'OrganizationalUnit'
        }

        It -Name 'Should have Timestamp in ISO 8601 format' -Test {
            $script:result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }

        It -Name 'Should extract OrganizationalUnit from DN' -Test {
            $script:result[0].OrganizationalUnit | Should -Be 'CN=Users,DC=contoso,DC=com'
        }
    }

    Context -Name 'AD query failure produces error' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                throw 'AD server unreachable'
            }
        }

        It -Name 'Should not throw a terminating error' -Test {
            { Get-ADGroupInventory -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
}
