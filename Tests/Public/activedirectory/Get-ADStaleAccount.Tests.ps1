#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Create proxy functions for AD cmdlets not available on CI runners
    if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
        function global:Get-ADUser { }
    }
    if (-not (Get-Command -Name 'Get-ADComputer' -ErrorAction SilentlyContinue)) {
        function global:Get-ADComputer { }
    }
    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function script:Get-ADUser { }
        }
        if (-not (Get-Command -Name 'Get-ADComputer' -ErrorAction SilentlyContinue)) {
            function script:Get-ADComputer { }
        }
    }
}

Describe 'Get-ADStaleAccount' {
    BeforeAll {
        $script:fakeStaleUsers = @(
            [PSCustomObject]@{
                Name              = 'Old User'
                SamAccountName    = 'olduser'
                Enabled           = $true
                LastLogonDate     = (Get-Date).AddDays(-120)
                WhenCreated       = [datetime]::Parse('2023-01-15')
                Description       = 'Stale user'
                DistinguishedName = 'CN=Old User,OU=Users,DC=contoso,DC=com'
            }
            [PSCustomObject]@{
                Name              = 'Never Logged'
                SamAccountName    = 'neverlogged'
                Enabled           = $true
                LastLogonDate     = $null
                WhenCreated       = [datetime]::Parse('2024-06-01')
                Description       = 'Never logged in'
                DistinguishedName = 'CN=Never Logged,OU=Users,DC=contoso,DC=com'
            }
        )

        $script:fakeStaleComputers = @(
            [PSCustomObject]@{
                Name              = 'OLD-PC01'
                SamAccountName    = 'OLD-PC01
                Enabled           = $true
                LastLogonDate     = (Get-Date).AddDays(-200)
                WhenCreated       = [datetime]::Parse('2022-03-10')
                Description       = 'Old workstation'
                DistinguishedName = 'CN=OLD-PC01,OU=Computers,DC=contoso,DC=com'
            }
        )
    }

    BeforeEach {
        Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADUser' -MockWith { $script:fakeStaleUsers } -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADComputer' -MockWith { $script:fakeStaleComputers } -ModuleName 'PSWinOps'
    }

    Context 'Happy path - default Both' {
        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results = Get-ADStaleAccount -DaysInactive 90
            $script:results | ForEach-Object -Process {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADStaleAccount'
            }
        }

        It -Name 'Should return both users and computers' -Test {
            $script:results = Get-ADStaleAccount -DaysInactive 90
            $script:results.AccountType | Should -Contain 'User'
            $script:results.AccountType | Should -Contain 'Computer'
        }

        It -Name 'Should call both Get-ADUser and Get-ADComputer' -Test {
            Get-ADStaleAccount -DaysInactive 90
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 1 -Exactly
            Should -Invoke -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'AccountType filter' {
        It -Name 'Should only query users when AccountType is User' -Test {
            Get-ADStaleAccount -DaysInactive 90 -AccountType 'User'
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 1 -Exactly
            Should -Invoke -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should only query computers when AccountType is Computer' -Test {
            Get-ADStaleAccount -DaysInactive 90 -AccountType 'Computer'
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 0 -Exactly
            Should -Invoke -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'DaysSinceLogon calculation' {
        It -Name 'Should calculate DaysSinceLogon for accounts with LastLogonDate' -Test {
            $script:results = Get-ADStaleAccount -DaysInactive 90
            $script:userResult = $script:results | Where-Object -Property 'SamAccountName' -EQ -Value 'olduser'
            $script:userResult.DaysSinceLogon | Should -BeGreaterOrEqual 120
        }

        It -Name 'Should return null DaysSinceLogon for never-logged-in accounts' -Test {
            $script:results = Get-ADStaleAccount -DaysInactive 90
            $script:neverResult = $script:results | Where-Object -Property 'SamAccountName' -EQ -Value 'neverlogged'
            $script:neverResult.DaysSinceLogon | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject DaysInactive below 1' -Test {
            { Get-ADStaleAccount -DaysInactive 0 } | Should -Throw
        }

        It -Name 'Should reject DaysInactive above 3650' -Test {
            { Get-ADStaleAccount -DaysInactive 3651 } | Should -Throw
        }

        It -Name 'Should reject invalid AccountType' -Test {
            { Get-ADStaleAccount -DaysInactive 90 -AccountType 'Invalid' } | Should -Throw
        }
    }

    Context 'Server passthrough' {
        It -Name 'Should accept Server parameter without error' -Test {
            $script:results = Get-ADStaleAccount -DaysInactive 90 -AccountType 'User' -Server 'dc01.contoso.com'
            $script:results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Output shape' {
        It -Name 'Should include all expected properties' -Test {
            $script:results = Get-ADStaleAccount -DaysInactive 90
            $script:expectedProps = @(
                'Name', 'SamAccountName', 'AccountType', 'Enabled',
                'LastLogonDate', 'DaysSinceLogon', 'WhenCreated',
                'Description', 'DistinguishedName', 'Timestamp'
            )
            $script:actualProps = $script:results[0].PSObject.Properties.Name
            foreach ($script:propName in $script:expectedProps) {
                $script:actualProps | Should -Contain $script:propName
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $script:results = Get-ADStaleAccount -DaysInactive 90
            $script:results[0].Timestamp | Should -Match '^\d{4}'
        }
    }
}

