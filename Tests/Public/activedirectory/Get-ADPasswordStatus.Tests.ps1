#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
        function global:Get-ADUser { }
    }
    if (-not (Get-Command -Name 'Get-ADDefaultDomainPasswordPolicy' -ErrorAction SilentlyContinue)) {
        function global:Get-ADDefaultDomainPasswordPolicy { }
    }
    if (-not (Get-Command -Name 'Get-ADFineGrainedPasswordPolicy' -ErrorAction SilentlyContinue)) {
        function global:Get-ADFineGrainedPasswordPolicy { }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function script:Get-ADUser { }
        }
        if (-not (Get-Command -Name 'Get-ADDefaultDomainPasswordPolicy' -ErrorAction SilentlyContinue)) {
            function script:Get-ADDefaultDomainPasswordPolicy { }
        }
        if (-not (Get-Command -Name 'Get-ADFineGrainedPasswordPolicy' -ErrorAction SilentlyContinue)) {
            function script:Get-ADFineGrainedPasswordPolicy { }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Get-ADPasswordStatus' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:psoDN = 'CN=SvcAccounts-PSO,CN=Password Settings Container,CN=System,DC=contoso,DC=com'

        $script:mockDefaultPolicy = [PSCustomObject]@{
            MaxPasswordAge = [TimeSpan]::FromDays(90)
        }

        $script:mockPSO = [PSCustomObject]@{
            Name              = 'SvcAccounts-PSO'
            DistinguishedName = $script:psoDN
            MaxPasswordAge    = [TimeSpan]::FromDays(365)
        }

        $script:mockExpiredUser = [PSCustomObject]@{
            Name                     = 'Expired User'
            SamAccountName           = 'expireduser'
            Enabled                  = $true
            PasswordExpired          = $true
            PasswordNeverExpires     = $false
            PasswordNotRequired      = $false
            CannotChangePassword     = $false
            PasswordLastSet          = (Get-Date).AddDays(-200)
            Description              = 'Expired password'
            DistinguishedName        = 'CN=Expired User,OU=Users,DC=contoso,DC=com'
            'msDS-ResultantPSO'      = $null
        }

        $script:mockNeverExpiresUser = [PSCustomObject]@{
            Name                     = 'NeverExpires User'
            SamAccountName           = 'neverexpuser'
            Enabled                  = $true
            PasswordExpired          = $false
            PasswordNeverExpires     = $true
            PasswordNotRequired      = $false
            CannotChangePassword     = $false
            PasswordLastSet          = (Get-Date).AddDays(-365)
            Description              = 'Password never expires'
            DistinguishedName        = 'CN=NeverExpires User,OU=Users,DC=contoso,DC=com'
            'msDS-ResultantPSO'      = $null
        }

        $script:mockMustChangeUser = [PSCustomObject]@{
            Name                     = 'MustChange User'
            SamAccountName           = 'mustchangeuser'
            Enabled                  = $true
            PasswordExpired          = $false
            PasswordNeverExpires     = $false
            PasswordNotRequired      = $false
            CannotChangePassword     = $false
            PasswordLastSet          = $null
            Description              = 'Must change at next logon'
            DistinguishedName        = 'CN=MustChange User,OU=Users,DC=contoso,DC=com'
            'msDS-ResultantPSO'      = $null
        }

        $script:mockNormalUser = [PSCustomObject]@{
            Name                     = 'Normal User'
            SamAccountName           = 'normaluser'
            Enabled                  = $true
            PasswordExpired          = $false
            PasswordNeverExpires     = $false
            PasswordNotRequired      = $false
            CannotChangePassword     = $false
            PasswordLastSet          = (Get-Date).AddDays(-10)
            Description              = 'Normal user'
            DistinguishedName        = 'CN=Normal User,OU=Users,DC=contoso,DC=com'
            'msDS-ResultantPSO'      = $null
        }

        $script:mockPSOUser = [PSCustomObject]@{
            Name                     = 'Service Account'
            SamAccountName           = 'svc-backup'
            Enabled                  = $true
            PasswordExpired          = $false
            PasswordNeverExpires     = $false
            PasswordNotRequired      = $false
            CannotChangePassword     = $false
            PasswordLastSet          = (Get-Date).AddDays(-100)
            Description              = 'Backup service account'
            DistinguishedName        = 'CN=Service Account,OU=Service,DC=contoso,DC=com'
            'msDS-ResultantPSO'      = $script:psoDN
        }

        $script:allUsers = @(
            $script:mockExpiredUser,
            $script:mockNeverExpiresUser,
            $script:mockMustChangeUser,
            $script:mockNormalUser,
            $script:mockPSOUser
        )
    }

    Context -Name 'Default behavior returns all enabled accounts' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:allUsers
            }
            Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDefaultPolicy
            }
            Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockPSO)
            }
            $script:results = Get-ADPasswordStatus
        }

        It -Name 'Should return all 5 enabled accounts' -Test {
            $script:results | Should -HaveCount 5
        }

        It -Name 'Should include the normal user' -Test {
            $script:results.SamAccountName | Should -Contain 'normaluser'
        }

        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADPasswordStatus'
        }
    }

    Context -Name 'ProblemsOnly switch filters to problematic accounts' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:allUsers
            }
            Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDefaultPolicy
            }
            Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockPSO)
            }
            $script:results = Get-ADPasswordStatus -ProblemsOnly
        }

        It -Name 'Should exclude normal users' -Test {
            $script:results.SamAccountName | Should -Not -Contain 'normaluser'
        }

        It -Name 'Should exclude accounts with PSO and no problems' -Test {
            $script:results.SamAccountName | Should -Not -Contain 'svc-backup'
        }

        It -Name 'Should include expired, never-expires, and must-change accounts' -Test {
            $script:results.SamAccountName | Should -Contain 'expireduser'
            $script:results.SamAccountName | Should -Contain 'neverexpuser'
            $script:results.SamAccountName | Should -Contain 'mustchangeuser'
        }
    }

    Context -Name 'Password policy resolution' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:allUsers
            }
            Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDefaultPolicy
            }
            Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockPSO)
            }
            $script:results = Get-ADPasswordStatus
        }

        It -Name 'Should assign Default Domain Policy to users without PSO' -Test {
            $normalResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'normaluser' }
            $normalResult.PasswordPolicy | Should -Be 'Default Domain Policy'
        }

        It -Name 'Should assign PSO name to users with Fine-Grained Password Policy' -Test {
            $psoResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'svc-backup' }
            $psoResult.PasswordPolicy | Should -Be 'SvcAccounts-PSO'
        }

        It -Name 'Should compute MaxPasswordAgeDays from default policy (90)' -Test {
            $normalResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'normaluser' }
            $normalResult.MaxPasswordAgeDays | Should -Be 90
        }

        It -Name 'Should compute MaxPasswordAgeDays from PSO (365)' -Test {
            $psoResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'svc-backup' }
            $psoResult.MaxPasswordAgeDays | Should -Be 365
        }
    }

    Context -Name 'Password expiry calculation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:allUsers
            }
            Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDefaultPolicy
            }
            Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockPSO)
            }
            $script:results = Get-ADPasswordStatus
        }

        It -Name 'Should compute DaysUntilExpiry for normal user (90 - 10 = ~80)' -Test {
            $normalResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'normaluser' }
            $normalResult.DaysUntilExpiry | Should -BeGreaterOrEqual 79
            $normalResult.DaysUntilExpiry | Should -BeLessOrEqual 81
        }

        It -Name 'Should compute negative DaysUntilExpiry for expired user' -Test {
            $expiredResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'expireduser' }
            $expiredResult.DaysUntilExpiry | Should -BeLessThan 0
        }

        It -Name 'Should have null DaysUntilExpiry for never-expires user' -Test {
            $neverResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'neverexpuser' }
            $neverResult.DaysUntilExpiry | Should -BeNullOrEmpty
        }

        It -Name 'Should have null DaysUntilExpiry for must-change user' -Test {
            $mustChangeResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'mustchangeuser' }
            $mustChangeResult.DaysUntilExpiry | Should -BeNullOrEmpty
        }

        It -Name 'Should have PasswordExpiresOn as datetime for normal user' -Test {
            $normalResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'normaluser' }
            $normalResult.PasswordExpiresOn | Should -BeOfType [DateTime]
        }

        It -Name 'Should compute DaysUntilExpiry using PSO MaxPasswordAge (365 - 100 = ~265)' -Test {
            $psoResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'svc-backup' }
            $psoResult.DaysUntilExpiry | Should -BeGreaterOrEqual 264
            $psoResult.DaysUntilExpiry | Should -BeLessOrEqual 266
        }
    }

    Context -Name 'PasswordAgeDays calculation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:allUsers
            }
            Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDefaultPolicy
            }
            Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockPSO)
            }
            $script:results = Get-ADPasswordStatus
        }

        It -Name 'Should calculate PasswordAgeDays correctly' -Test {
            $expiredResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'expireduser' }
            $expiredResult.PasswordAgeDays | Should -BeGreaterOrEqual 200
        }

        It -Name 'Should return null PasswordAgeDays when PasswordLastSet is null' -Test {
            $mustChangeResult = $script:results | Where-Object -FilterScript { $_.SamAccountName -eq 'mustchangeuser' }
            $mustChangeResult.PasswordAgeDays | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Server and Credential parameters are accepted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockNormalUser)
            }
            Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDefaultPolicy
            }
            Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
        }

        It -Name 'Should accept Server parameter without error' -Test {
            { Get-ADPasswordStatus -Server 'dc01.contoso.com' } | Should -Not -Throw
        }
    }

    Context -Name 'Output object shape' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockNormalUser)
            }
            Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDefaultPolicy
            }
            Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
            $script:result = Get-ADPasswordStatus
            $script:propertyNames = $script:result[0].PSObject.Properties.Name
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProps = @(
                'Name', 'SamAccountName', 'Enabled', 'PasswordExpired',
                'PasswordNeverExpires', 'MustChangePassword', 'PasswordNotRequired',
                'PasswordLastSet', 'PasswordAgeDays', 'PasswordPolicy',
                'MaxPasswordAgeDays', 'PasswordExpiresOn', 'DaysUntilExpiry',
                'Description', 'DistinguishedName', 'Timestamp'
            )
            foreach ($prop in $expectedProps) {
                $script:propertyNames | Should -Contain $prop
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $script:result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }
}
