#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Create proxy functions for AD cmdlets not available on CI runners
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function global:Get-ADUser { }
        }
    & (Get-Module -Name 'PSWinOps') {
            if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
                function script:Get-ADUser { }
            }
    }
}

Describe 'Get-ADPasswordStatus' {
    BeforeAll {
        $script:fakeUsers = @(
            [PSCustomObject]@{
                Name                 = 'Expired User'
                SamAccountName       = 'expireduser'
                Enabled              = $true
                PasswordExpired      = $true
                PasswordNeverExpires = $false
                PasswordNotRequired  = $false
                CannotChangePassword = $false
                PasswordLastSet      = (Get-Date).AddDays(-200)
                Description          = 'Expired password'
                DistinguishedName    = 'CN=Expired User,OU=Users,DC=contoso,DC=com'
            }
            [PSCustomObject]@{
                Name                 = 'NeverExpires User'
                SamAccountName       = 'neverexpuser'
                Enabled              = $true
                PasswordExpired      = $false
                PasswordNeverExpires = $true
                PasswordNotRequired  = $false
                CannotChangePassword = $false
                PasswordLastSet      = (Get-Date).AddDays(-365)
                Description          = 'Password never expires'
                DistinguishedName    = 'CN=NeverExpires User,OU=Users,DC=contoso,DC=com'
            }
            [PSCustomObject]@{
                Name                 = 'MustChange User'
                SamAccountName       = 'mustchangeuser'
                Enabled              = $true
                PasswordExpired      = $false
                PasswordNeverExpires = $false
                PasswordNotRequired  = $false
                CannotChangePassword = $false
                PasswordLastSet      = $null
                Description          = 'Must change at next logon'
                DistinguishedName    = 'CN=MustChange User,OU=Users,DC=contoso,DC=com'
            }
            [PSCustomObject]@{
                Name                 = 'Normal User'
                SamAccountName       = 'normaluser'
                Enabled              = $true
                PasswordExpired      = $false
                PasswordNeverExpires = $false
                PasswordNotRequired  = $false
                CannotChangePassword = $false
                PasswordLastSet      = (Get-Date).AddDays(-10)
                Description          = 'Normal user'
                DistinguishedName    = 'CN=Normal User,OU=Users,DC=contoso,DC=com'
            }
        )
    }

    BeforeEach {
        Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADUser' -MockWith { $script:fakeUsers } -ModuleName 'PSWinOps'
    }

    Context 'Happy path - Status All' {
        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results = Get-ADPasswordStatus
            $script:results | ForEach-Object -Process {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADPasswordStatus'
            }
        }

        It -Name 'Should return only accounts with password concerns when Status is All' -Test {
            $script:results = Get-ADPasswordStatus -Status 'All'
            $script:results.SamAccountName | Should -Not -Contain 'normaluser'
            $script:results.Count | Should -Be 3
        }
    }

    Context 'Status filter - Expired' {
        It -Name 'Should return only expired password accounts' -Test {
            $script:results = Get-ADPasswordStatus -Status 'Expired'
            $script:results.Count | Should -Be 1
            $script:results[0].SamAccountName | Should -Be 'expireduser'
        }
    }

    Context 'Status filter - NeverExpires' {
        It -Name 'Should return only never-expires accounts' -Test {
            $script:results = Get-ADPasswordStatus -Status 'NeverExpires'
            $script:results.Count | Should -Be 1
            $script:results[0].SamAccountName | Should -Be 'neverexpuser'
        }
    }

    Context 'Status filter - MustChange' {
        It -Name 'Should return only must-change accounts' -Test {
            $script:results = Get-ADPasswordStatus -Status 'MustChange'
            $script:results.Count | Should -Be 1
            $script:results[0].SamAccountName | Should -Be 'mustchangeuser'
        }

        It -Name 'Should have null PasswordLastSet for must-change accounts' -Test {
            $script:results = Get-ADPasswordStatus -Status 'MustChange'
            $script:results[0].PasswordLastSet | Should -BeNullOrEmpty
            $script:results[0].MustChangePassword | Should -BeTrue
        }
    }

    Context 'Status filter - multiple values' {
        It -Name 'Should combine multiple status filters' -Test {
            $script:results = Get-ADPasswordStatus -Status 'Expired', 'MustChange'
            $script:results.Count | Should -Be 2
            $script:results.SamAccountName | Should -Contain 'expireduser'
            $script:results.SamAccountName | Should -Contain 'mustchangeuser'
        }
    }

    Context 'PasswordAgeDays calculation' {
        It -Name 'Should calculate PasswordAgeDays correctly' -Test {
            $script:results = Get-ADPasswordStatus -Status 'Expired'
            $script:results[0].PasswordAgeDays | Should -BeGreaterOrEqual 200
        }

        It -Name 'Should return null PasswordAgeDays when PasswordLastSet is null' -Test {
            $script:results = Get-ADPasswordStatus -Status 'MustChange'
            $script:results[0].PasswordAgeDays | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject invalid Status value' -Test {
            { Get-ADPasswordStatus -Status 'Invalid' } | Should -Throw
        }
    }

    Context 'Server passthrough' {
        It -Name 'Should forward Server parameter to Get-ADUser' -Test {
            Get-ADPasswordStatus -Server 'dc01.contoso.com'
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Server -eq 'dc01.contoso.com'
            }
        }
    }

    Context 'Output shape' {
        It -Name 'Should include all expected properties' -Test {
            $script:results = Get-ADPasswordStatus -Status 'Expired'
            $script:expectedProps = @(
                'Name', 'SamAccountName', 'Enabled', 'PasswordExpired',
                'PasswordNeverExpires', 'MustChangePassword', 'PasswordNotRequired',
                'PasswordLastSet', 'PasswordAgeDays', 'Description',
                'DistinguishedName', 'Timestamp'
            )
            $script:actualProps = $script:results[0].PSObject.Properties.Name
            foreach ($script:propName in $script:expectedProps) {
                $script:actualProps | Should -Contain $script:propName
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $script:results = Get-ADPasswordStatus -Status 'Expired'
            $script:results[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }
}
