#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Create proxy functions for AD cmdlets not available on CI runners
        if (-not (Get-Command -Name 'Search-ADAccount' -ErrorAction SilentlyContinue)) {
            function global:Search-ADAccount { }
        }
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function global:Get-ADUser { }
        }
    & (Get-Module -Name 'PSWinOps') {
            if (-not (Get-Command -Name 'Search-ADAccount' -ErrorAction SilentlyContinue)) {
                function script:Search-ADAccount { }
            }
            if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
                function script:Get-ADUser { }
            }
    }
}

Describe 'Get-ADLockedAccount' {
    BeforeAll {
        $script:fakeLockedAccounts = @(
            [PSCustomObject]@{
                SamAccountName    = 'jdoe'
                DistinguishedName = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
            }
            [PSCustomObject]@{
                SamAccountName    = 'asmith'
                DistinguishedName = 'CN=Alice Smith,OU=Users,DC=contoso,DC=com'
            }
        )

        $script:fakeUserDetails = @{
            'jdoe'   = [PSCustomObject]@{
                Name                   = 'John Doe'
                SamAccountName         = 'jdoe'
                Enabled                = $true
                LockedOut              = $true
                LockoutTime            = [datetime]::Parse('2026-04-03T14:30:00')
                BadLogonCount          = 5
                LastBadPasswordAttempt = [datetime]::Parse('2026-04-03T14:29:50')
                Description            = 'IT Engineer'
                DistinguishedName      = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
            }
            'asmith' = [PSCustomObject]@{
                Name                   = 'Alice Smith'
                SamAccountName         = 'asmith'
                Enabled                = $true
                LockedOut              = $true
                LockoutTime            = [datetime]::Parse('2026-04-03T10:15:00')
                BadLogonCount          = 3
                LastBadPasswordAttempt = [datetime]::Parse('2026-04-03T10:14:45')
                Description            = 'Manager'
                DistinguishedName      = 'CN=Alice Smith,OU=Users,DC=contoso,DC=com'
            }
        }
    }

    BeforeEach {
        Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
        Mock -CommandName 'Search-ADAccount' -MockWith { $script:fakeLockedAccounts } -ModuleName 'PSWinOps'
        # Use a call counter since proxy functions don't bind $Identity
        $script:adUserCallCount = 0
        $script:adUserOrder = @('jdoe', 'asmith')
        Mock -CommandName 'Get-ADUser' -MockWith {
            $script:adUserCallCount++
            $key = $script:adUserOrder[($script:adUserCallCount - 1)]
            $script:fakeUserDetails[$key]
        } -ModuleName 'PSWinOps'
    }

    Context 'Happy path' {
        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results = Get-ADLockedAccount
            $script:results | ForEach-Object -Process {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADLockedAccount'
            }
        }

        It -Name 'Should return all locked accounts' -Test {
            $script:results = Get-ADLockedAccount
            $script:results.Count | Should -Be 2
        }

        It -Name 'Should call Search-ADAccount with LockedOut' -Test {
            Get-ADLockedAccount
            Should -Invoke -CommandName 'Search-ADAccount' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'No locked accounts' {
        It -Name 'Should return nothing when no accounts are locked' -Test {
            Mock -CommandName 'Search-ADAccount' -MockWith { $null } -ModuleName 'PSWinOps'
            $script:results = Get-ADLockedAccount
            $script:results | Should -BeNullOrEmpty
        }
    }

    Context 'Per-account error handling' {
        It -Name 'Should continue when Get-ADUser fails for one account' -Test {
            $script:callCount = 0
            Mock -CommandName 'Get-ADUser' -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) { throw 'Cannot find user' }
                $script:fakeUserDetails['asmith']
            } -ModuleName 'PSWinOps'

            $script:results = Get-ADLockedAccount -ErrorAction SilentlyContinue
            $script:results.Count | Should -Be 1
        }
    }

    Context 'Server passthrough' {
        It -Name 'Should accept Server parameter without error' -Test {
            $script:results = Get-ADLockedAccount -Server 'dc01.contoso.com'
            $script:results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Output shape' {
        It -Name 'Should include all expected properties' -Test {
            $script:results = Get-ADLockedAccount
            $script:expectedProps = @(
                'Name', 'SamAccountName', 'Enabled', 'LockoutTime',
                'BadLogonCount', 'LastBadPasswordAttempt', 'Description',
                'DistinguishedName', 'Timestamp'
            )
            $script:actualProps = $script:results[0].PSObject.Properties.Name
            foreach ($script:propName in $script:expectedProps) {
                $script:actualProps | Should -Contain $script:propName
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $script:results = Get-ADLockedAccount
            $script:results[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }

        It -Name 'Should sort by LockoutTime descending' -Test {
            $script:results = Get-ADLockedAccount
            $script:results[0].SamAccountName | Should -Be 'jdoe'
        }
    }
}
