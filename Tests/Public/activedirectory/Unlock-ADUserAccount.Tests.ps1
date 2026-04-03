#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
        function global:Get-ADUser { }
    }
    if (-not (Get-Command -Name 'Unlock-ADAccount' -ErrorAction SilentlyContinue)) {
        function global:Unlock-ADAccount { }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function script:Get-ADUser { }
        }
        if (-not (Get-Command -Name 'Unlock-ADAccount' -ErrorAction SilentlyContinue)) {
            function script:Unlock-ADAccount { }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Unlock-ADUserAccount' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:mockLockedUser = [PSCustomObject]@{
            SamAccountName    = 'jdoe'
            DistinguishedName = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
            LockedOut         = $true
            Enabled           = $true
        }

        $script:mockUnlockedUser = [PSCustomObject]@{
            SamAccountName    = 'asmith'
            DistinguishedName = 'CN=Alice Smith,OU=Users,DC=contoso,DC=com'
            LockedOut         = $false
            Enabled           = $true
        }
    }

    Context -Name 'Unlocks a locked user account' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockLockedUser
            }
            Mock -CommandName 'Unlock-ADAccount' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Unlock-ADUserAccount -Identity 'jdoe' -Confirm:$false
        }

        It -Name 'Should return a result object' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have correct PSTypeName' -Test {
            $script:result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADAccountUnlockResult'
        }

        It -Name 'Should report success' -Test {
            $script:result.Success | Should -BeTrue
        }

        It -Name 'Should have correct UserName' -Test {
            $script:result.UserName | Should -Be 'jdoe'
        }

        It -Name 'Should have a success message' -Test {
            $script:result.Message | Should -Be 'Account unlocked successfully'
        }

        It -Name 'Should have Timestamp in ISO 8601 format' -Test {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context -Name 'Account already unlocked' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUnlockedUser
            }
            Mock -CommandName 'Unlock-ADAccount' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Unlock-ADUserAccount -Identity 'asmith' -Confirm:$false
        }

        It -Name 'Should report success with not-locked message' -Test {
            $script:result.Success | Should -BeTrue
        }

        It -Name 'Should indicate account was not locked' -Test {
            $script:result.Message | Should -Be 'Account was not locked'
        }
    }

    Context -Name 'Pipeline input is accepted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockLockedUser
            }
            Mock -CommandName 'Unlock-ADAccount' -ModuleName 'PSWinOps' -MockWith { }
        }

        It -Name 'Should accept string input from pipeline' -Test {
            { 'jdoe' | Unlock-ADUserAccount -Confirm:$false } | Should -Not -Throw
        }

        It -Name 'Should accept multiple strings from pipeline' -Test {
            $script:pipeResults = 'jdoe', 'asmith' | Unlock-ADUserAccount -Confirm:$false
            $script:pipeResults | Should -HaveCount 2
        }
    }

    Context -Name 'Error handling on failure' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                throw 'User not found in AD'
            }
            $script:result = Unlock-ADUserAccount -Identity 'baduser' -Confirm:$false -ErrorAction SilentlyContinue
        }

        It -Name 'Should return a failure result object' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should report failure' -Test {
            $script:result.Success | Should -BeFalse
        }

        It -Name 'Should have failure message' -Test {
            $script:result.Message | Should -BeLike 'Failed:*'
        }
    }

    Context -Name 'ShouldProcess support' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockLockedUser
            }
            Mock -CommandName 'Unlock-ADAccount' -ModuleName 'PSWinOps' -MockWith { }
        }

        It -Name 'Should support WhatIf without performing action' -Test {
            $script:whatIfResult = Unlock-ADUserAccount -Identity 'jdoe' -WhatIf
            $script:whatIfResult | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Output object shape validation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockLockedUser
            }
            Mock -CommandName 'Unlock-ADAccount' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Unlock-ADUserAccount -Identity 'jdoe' -Confirm:$false
            $script:propertyNames = $script:result.PSObject.Properties.Name
        }

        It -Name 'Should have Identity property' -Test {
            $script:propertyNames | Should -Contain 'Identity'
        }

        It -Name 'Should have UserName property' -Test {
            $script:propertyNames | Should -Contain 'UserName'
        }

        It -Name 'Should have Success property' -Test {
            $script:propertyNames | Should -Contain 'Success'
        }

        It -Name 'Should have Message property' -Test {
            $script:propertyNames | Should -Contain 'Message'
        }

        It -Name 'Should have Timestamp property' -Test {
            $script:propertyNames | Should -Contain 'Timestamp'
        }
    }
}
