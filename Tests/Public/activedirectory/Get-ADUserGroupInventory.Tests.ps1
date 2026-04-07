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
        function global:Get-ADUser {
            [CmdletBinding()]
            param($Identity, $Filter, $Properties, $SearchBase, $Server, $Credential)
        }
    }
    if (-not (Get-Command -Name 'Get-ADGroup' -ErrorAction SilentlyContinue)) {
        function global:Get-ADGroup {
            [CmdletBinding()]
            param($LDAPFilter, $Filter, $Properties, $Server, $Credential)
        }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function script:Get-ADUser {
                [CmdletBinding()]
                param($Identity, $Filter, $Properties, $SearchBase, $Server, $Credential)
            }
        }
        if (-not (Get-Command -Name 'Get-ADGroup' -ErrorAction SilentlyContinue)) {
            function script:Get-ADGroup {
                [CmdletBinding()]
                param($LDAPFilter, $Filter, $Properties, $Server, $Credential)
            }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Get-ADUserGroupInventory' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:mockUser = [PSCustomObject]@{
            SamAccountName    = 'jdoe'
            DisplayName       = 'John Doe'
            DistinguishedName = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
            Enabled           = $true
        }

        $script:mockUser2 = [PSCustomObject]@{
            SamAccountName    = 'asmith'
            DisplayName       = 'Alice Smith'
            DistinguishedName = 'CN=Alice Smith,OU=Users,DC=contoso,DC=com'
            Enabled           = $true
        }

        $script:mockGroup1 = [PSCustomObject]@{
            Name              = 'Domain Admins'
            SamAccountName    = 'Domain Admins'
            GroupScope        = 'Global'
            GroupCategory     = 'Security'
            DistinguishedName = 'CN=Domain Admins,CN=Users,DC=contoso,DC=com'
        }

        $script:mockGroup2 = [PSCustomObject]@{
            Name              = 'IT Staff'
            SamAccountName    = 'IT Staff'
            GroupScope        = 'Global'
            GroupCategory     = 'Security'
            DistinguishedName = 'CN=IT Staff,OU=Groups,DC=contoso,DC=com'
        }
    }

    Context -Name 'Happy path with Identity parameter' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroup1, $script:mockGroup2)
            }
            $script:results = Get-ADUserGroupInventory -Identity 'jdoe'
        }

        It -Name 'Should return 2 group membership entries' -Test {
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADUserGroupInventory'
        }

        It -Name 'Should return expected group names' -Test {
            $groupNames = $script:results | Select-Object -ExpandProperty 'GroupName'
            $groupNames | Should -Contain 'Domain Admins'
            $groupNames | Should -Contain 'IT Staff'
        }

        It -Name 'Should have correct UserName value' -Test {
            $script:results[0].UserName | Should -Be 'jdoe'
        }
    }

    Context -Name 'Multiple users via Identity array' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -ParameterFilter {
                $Identity -eq 'jdoe'
            } -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -ParameterFilter {
                $Identity -eq 'asmith'
            } -MockWith {
                return $script:mockUser2
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroup1)
            }
            $script:multiResults = Get-ADUserGroupInventory -Identity 'jdoe', 'asmith'
        }

        It -Name 'Should return entries for both users' -Test {
            @($script:multiResults).Count | Should -Be 2
        }

        It -Name 'Should include jdoe in results' -Test {
            $userNames = $script:multiResults | Select-Object -ExpandProperty 'UserName'
            $userNames | Should -Contain 'jdoe'
        }

        It -Name 'Should include asmith in results' -Test {
            $userNames = $script:multiResults | Select-Object -ExpandProperty 'UserName'
            $userNames | Should -Contain 'asmith'
        }

        It -Name 'Should return results sorted by UserName then GroupName' -Test {
            $script:multiResults[0].UserName | Should -Be 'asmith'
            $script:multiResults[1].UserName | Should -Be 'jdoe'
        }
    }

    Context -Name 'No Identity provided - queries all users' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -ParameterFilter {
                $null -ne $Filter
            } -MockWith {
                return @($script:mockUser, $script:mockUser2)
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroup1)
            }
            $script:allUserResults = Get-ADUserGroupInventory
        }

        It -Name 'Should return entries for discovered users' -Test {
            @($script:allUserResults).Count | Should -Be 2
        }

        It -Name 'Should call Get-ADUser with Filter parameter' -Test {
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 1 -ParameterFilter {
                $null -ne $Filter
            }
        }

        It -Name 'Should include both discovered users' -Test {
            $userNames = $script:allUserResults | Select-Object -ExpandProperty 'UserName' -Unique
            $userNames | Should -Contain 'jdoe'
            $userNames | Should -Contain 'asmith'
        }
    }

    Context -Name 'SearchBase parameter with no Identity' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -ParameterFilter {
                $null -ne $Filter
            } -MockWith {
                return @($script:mockUser)
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroup1)
            }
            $script:searchBaseResults = Get-ADUserGroupInventory -SearchBase 'OU=Users,DC=contoso,DC=com'
        }

        It -Name 'Should return results scoped to SearchBase' -Test {
            $script:searchBaseResults | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should call Get-ADUser with Filter for all users in OU' -Test {
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 1 -ParameterFilter {
                $null -ne $Filter
            }
        }
    }

    Context -Name 'Import-Module ActiveDirectory fails' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith {
                throw 'ActiveDirectory module not found'
            }
        }

        It -Name 'Should write error when ActiveDirectory module is unavailable' -Test {
            Get-ADUserGroupInventory -Identity 'jdoe' -ErrorVariable 'capturedError' -ErrorAction SilentlyContinue
            $capturedError | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should return no results when module is unavailable' -Test {
            $noModResult = Get-ADUserGroupInventory -Identity 'jdoe' -ErrorAction SilentlyContinue
            $noModResult | Should -BeNullOrEmpty
        }
    }

    Context -Name 'No groups found for a user' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return $null
            }
        }

        It -Name 'Should return empty when user has no groups' -Test {
            $noGroupResult = Get-ADUserGroupInventory -Identity 'jdoe'
            $noGroupResult | Should -BeNullOrEmpty
        }

        It -Name 'Should not throw when no groups are found' -Test {
            { Get-ADUserGroupInventory -Identity 'jdoe' } | Should -Not -Throw
        }
    }

    Context -Name 'Get-ADUser throws for one identity in array' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -ParameterFilter {
                $Identity -eq 'jdoe'
            } -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -ParameterFilter {
                $Identity -eq 'baduser'
            } -MockWith {
                throw 'Cannot find an object with identity baduser'
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroup1)
            }
        }

        It -Name 'Should not throw a terminating error' -Test {
            { Get-ADUserGroupInventory -Identity 'jdoe', 'baduser' -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should write a warning for the failing user' -Test {
            Get-ADUserGroupInventory -Identity 'jdoe', 'baduser' -WarningVariable 'capturedWarn' -WarningAction SilentlyContinue | Out-Null
            $capturedWarn | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should still return results for the successful user' -Test {
            $partialResult = Get-ADUserGroupInventory -Identity 'jdoe', 'baduser' -WarningAction SilentlyContinue
            $partialResult | Should -Not -BeNullOrEmpty
            $partialResult[0].UserName | Should -Be 'jdoe'
        }
    }

    Context -Name 'Get-ADUser filter query fails for all users' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -ParameterFilter {
                $null -ne $Filter
            } -MockWith {
                throw 'LDAP server unavailable'
            }
        }

        It -Name 'Should write error when all-user query fails' -Test {
            Get-ADUserGroupInventory -ErrorVariable 'capturedError' -ErrorAction SilentlyContinue
            $capturedError | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should return empty when all-user query fails' -Test {
            $filterFailResult = Get-ADUserGroupInventory -ErrorAction SilentlyContinue
            $filterFailResult | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Pipeline input is accepted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroup1)
            }
        }

        It -Name 'Should accept string input from pipeline' -Test {
            { 'jdoe' | Get-ADUserGroupInventory } | Should -Not -Throw
        }

        It -Name 'Should return results from pipeline input' -Test {
            $script:pipeResult = 'jdoe' | Get-ADUserGroupInventory
            $script:pipeResult | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Per-user error handling writes warning' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                throw 'LDAP query failed for group lookup'
            }
        }

        It -Name 'Should not throw a terminating error when Get-ADGroup fails' -Test {
            { Get-ADUserGroupInventory -Identity 'jdoe' -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should write a warning when Get-ADGroup fails' -Test {
            Get-ADUserGroupInventory -Identity 'jdoe' -WarningVariable 'capturedWarn' -WarningAction SilentlyContinue | Out-Null
            $capturedWarn | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should return empty when group lookup fails' -Test {
            $script:errorResult = Get-ADUserGroupInventory -Identity 'jdoe' -WarningAction SilentlyContinue
            $script:errorResult | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Server and Credential parameters are accepted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroup1)
            }
            $script:securePass = ConvertTo-SecureString -String 'TestPass123' -AsPlainText -Force
            $script:testCred = [PSCredential]::new('CONTOSO\admin', $script:securePass)
        }

        It -Name 'Should accept Server parameter without error' -Test {
            { Get-ADUserGroupInventory -Identity 'jdoe' -Server 'dc01.contoso.com' } | Should -Not -Throw
        }

        It -Name 'Should accept Credential parameter without error' -Test {
            { Get-ADUserGroupInventory -Identity 'jdoe' -Credential $script:testCred } | Should -Not -Throw
        }

        It -Name 'Should accept both parameters together' -Test {
            { Get-ADUserGroupInventory -Identity 'jdoe' -Server 'dc01.contoso.com' -Credential $script:testCred } | Should -Not -Throw
        }
    }

    Context -Name 'Output object shape validation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockGroup1)
            }
            $script:result = Get-ADUserGroupInventory -Identity 'jdoe'
            $script:propertyNames = $script:result[0].PSObject.Properties.Name
        }

        It -Name 'Should have UserName property' -Test {
            $script:propertyNames | Should -Contain 'UserName'
        }

        It -Name 'Should have DisplayName property' -Test {
            $script:propertyNames | Should -Contain 'DisplayName'
        }

        It -Name 'Should have GroupName property' -Test {
            $script:propertyNames | Should -Contain 'GroupName'
        }

        It -Name 'Should have GroupDN property' -Test {
            $script:propertyNames | Should -Contain 'GroupDN'
        }

        It -Name 'Should have GroupScope property' -Test {
            $script:propertyNames | Should -Contain 'GroupScope'
        }

        It -Name 'Should have GroupCategory property' -Test {
            $script:propertyNames | Should -Contain 'GroupCategory'
        }

        It -Name 'Should have Timestamp in ISO 8601 format' -Test {
            $script:result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }
}
