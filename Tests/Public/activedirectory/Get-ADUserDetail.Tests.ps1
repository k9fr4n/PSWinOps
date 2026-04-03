#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-ADUserDetail' {
    BeforeEach {
        Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADUser' -MockWith {
            [PSCustomObject]@{
                SamAccountName         = 'jdoe'
                DisplayName            = 'John Doe'
                EmailAddress           = 'jdoe@contoso.com'
                Department             = 'IT'
                Title                  = 'Engineer'
                Company                = 'Contoso'
                Office                 = 'HQ'
                Manager                = 'CN=Jane Smith,OU=Managers,DC=contoso,DC=com'
                Description            = 'Test user account'
                Enabled                = $true
                LockedOut              = $false
                LockoutTime            = $null
                LastLogonDate          = [datetime]'2026-04-01T10:00:00'
                LastBadPasswordAttempt = $null
                BadLogonCount          = 0
                PasswordLastSet        = [datetime]'2026-01-15T08:00:00'
                PasswordExpired        = $false
                PasswordNeverExpires   = $false
                CannotChangePassword   = $false
                AccountExpirationDate  = $null
                WhenCreated            = [datetime]'2025-06-01T09:00:00'
                WhenChanged            = [datetime]'2026-03-20T14:30:00'
                MemberOf               = @(
                    'CN=Group1,OU=Groups,DC=contoso,DC=com'
                    'CN=Group2,OU=Groups,DC=contoso,DC=com'
                )
                DistinguishedName      = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
            }
        } -ModuleName 'PSWinOps'
    }

    Context 'Happy path - single identity' {
        It -Name 'Should return object with correct PSTypeName' -Test {
            $result = Get-ADUserDetail -Identity 'jdoe'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADUserDetail'
        }

        It -Name 'Should return expected SamAccountName' -Test {
            $result = Get-ADUserDetail -Identity 'jdoe'
            $result.SamAccountName | Should -Be 'jdoe'
        }

        It -Name 'Should call Get-ADUser exactly once' -Test {
            Get-ADUserDetail -Identity 'jdoe'
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Pipeline - multiple identities' {
        It -Name 'Should return one result per identity' -Test {
            $script:results = @('jdoe', 'asmith') | Get-ADUserDetail
            $script:results.Count | Should -Be 2
        }

        It -Name 'Should call Get-ADUser once per identity' -Test {
            @('jdoe', 'asmith') | Get-ADUserDetail
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Per-identity failure handling' {
        It -Name 'Should write error and continue on failure' -Test {
            Mock -CommandName 'Get-ADUser' -MockWith {
                throw 'Cannot find object'
            } -ModuleName 'PSWinOps'

            { Get-ADUserDetail -Identity 'baduser' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should continue processing after a failure' -Test {
            $script:callCount = 0
            Mock -CommandName 'Get-ADUser' -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    throw 'Cannot find object'
                }
                [PSCustomObject]@{
                    SamAccountName    = 'gooduser'
                    DisplayName       = 'Good User'
                    EmailAddress      = $null
                    Department        = $null
                    Title             = $null
                    Company           = $null
                    Office            = $null
                    Manager           = $null
                    Description       = $null
                    Enabled           = $true
                    LockedOut         = $false
                    LockoutTime       = $null
                    LastLogonDate     = $null
                    LastBadPasswordAttempt = $null
                    BadLogonCount     = 0
                    PasswordLastSet   = $null
                    PasswordExpired   = $false
                    PasswordNeverExpires = $false
                    CannotChangePassword = $false
                    AccountExpirationDate = $null
                    WhenCreated       = [datetime]'2025-01-01'
                    WhenChanged       = [datetime]'2025-01-01'
                    MemberOf          = @()
                    DistinguishedName = 'CN=Good User,OU=Users,DC=contoso,DC=com'
                }
            } -ModuleName 'PSWinOps'

            $script:results = Get-ADUserDetail -Identity 'baduser', 'gooduser' -ErrorAction SilentlyContinue
            $script:results.Count | Should -Be 1
            $script:results.SamAccountName | Should -Be 'gooduser'
        }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject null Identity' -Test {
            { Get-ADUserDetail -Identity $null } | Should -Throw
        }

        It -Name 'Should reject empty string Identity' -Test {
            { Get-ADUserDetail -Identity '' } | Should -Throw
        }
    }

    Context 'Server passthrough' {
        It -Name 'Should forward Server parameter to Get-ADUser' -Test {
            Get-ADUserDetail -Identity 'jdoe' -Server 'dc01.contoso.com'
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Server -eq 'dc01.contoso.com'
            }
        }
    }

    Context 'Credential passthrough' {
        It -Name 'Should forward Credential parameter to Get-ADUser' -Test {
            $script:testCredential = [System.Management.Automation.PSCredential]::new(
                'testuser',
                (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)
            )
            Get-ADUserDetail -Identity 'jdoe' -Credential $script:testCredential
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }
    }

    Context 'Output shape' {
        It -Name 'Should include all expected properties' -Test {
            $result = Get-ADUserDetail -Identity 'jdoe'
            $expectedProps = @(
                'SamAccountName', 'DisplayName', 'EmailAddress', 'Department',
                'Title', 'Company', 'Office', 'Manager', 'Description',
                'Enabled', 'LockedOut', 'LockoutTime', 'LastLogonDate',
                'LastBadPasswordAttempt', 'BadLogonCount', 'PasswordLastSet',
                'PasswordExpired', 'PasswordNeverExpires', 'CannotChangePassword',
                'AccountExpirationDate', 'WhenCreated', 'WhenChanged',
                'MemberOfCount', 'OrganizationalUnit', 'DistinguishedName', 'Timestamp'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($propName in $expectedProps) {
                $actualProps | Should -Contain $propName
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $result = Get-ADUserDetail -Identity 'jdoe'
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context 'Manager name extraction' {
        It -Name 'Should extract Manager CN from DistinguishedName' -Test {
            $result = Get-ADUserDetail -Identity 'jdoe'
            $result.Manager | Should -Be 'Jane Smith'
        }

        It -Name 'Should return null when Manager is not set' -Test {
            Mock -CommandName 'Get-ADUser' -MockWith {
                [PSCustomObject]@{
                    SamAccountName    = 'orphan'
                    DisplayName       = 'Orphan User'
                    EmailAddress      = $null
                    Department        = $null
                    Title             = $null
                    Company           = $null
                    Office            = $null
                    Manager           = $null
                    Description       = $null
                    Enabled           = $true
                    LockedOut         = $false
                    LockoutTime       = $null
                    LastLogonDate     = $null
                    LastBadPasswordAttempt = $null
                    BadLogonCount     = 0
                    PasswordLastSet   = $null
                    PasswordExpired   = $false
                    PasswordNeverExpires = $false
                    CannotChangePassword = $false
                    AccountExpirationDate = $null
                    WhenCreated       = [datetime]'2025-01-01'
                    WhenChanged       = [datetime]'2025-01-01'
                    MemberOf          = $null
                    DistinguishedName = 'CN=Orphan User,OU=Users,DC=contoso,DC=com'
                }
            } -ModuleName 'PSWinOps'

            $result = Get-ADUserDetail -Identity 'orphan'
            $result.Manager | Should -BeNullOrEmpty
        }

        It -Name 'Should return MemberOfCount of 0 when MemberOf is null' -Test {
            Mock -CommandName 'Get-ADUser' -MockWith {
                [PSCustomObject]@{
                    SamAccountName    = 'orphan'
                    DisplayName       = 'Orphan User'
                    EmailAddress      = $null
                    Department        = $null
                    Title             = $null
                    Company           = $null
                    Office            = $null
                    Manager           = $null
                    Description       = $null
                    Enabled           = $true
                    LockedOut         = $false
                    LockoutTime       = $null
                    LastLogonDate     = $null
                    LastBadPasswordAttempt = $null
                    BadLogonCount     = 0
                    PasswordLastSet   = $null
                    PasswordExpired   = $false
                    PasswordNeverExpires = $false
                    CannotChangePassword = $false
                    AccountExpirationDate = $null
                    WhenCreated       = [datetime]'2025-01-01'
                    WhenChanged       = [datetime]'2025-01-01'
                    MemberOf          = $null
                    DistinguishedName = 'CN=Orphan User,OU=Users,DC=contoso,DC=com'
                }
            } -ModuleName 'PSWinOps'

            $result = Get-ADUserDetail -Identity 'orphan'
            $result.MemberOfCount | Should -Be 0
        }
    }

    Context 'OU extraction' {
        It -Name 'Should extract OrganizationalUnit from DistinguishedName' -Test {
            $result = Get-ADUserDetail -Identity 'jdoe'
            $result.OrganizationalUnit | Should -Be 'OU=Users,DC=contoso,DC=com'
        }
    }
}
