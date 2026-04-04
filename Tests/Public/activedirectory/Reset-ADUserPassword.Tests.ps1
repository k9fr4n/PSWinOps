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
    if (-not (Get-Command -Name 'Set-ADAccountPassword' -ErrorAction SilentlyContinue)) {
        function global:Set-ADAccountPassword { }
    }
    if (-not (Get-Command -Name 'Set-ADUser' -ErrorAction SilentlyContinue)) {
        function global:Set-ADUser { }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function script:Get-ADUser { }
        }
        if (-not (Get-Command -Name 'Set-ADAccountPassword' -ErrorAction SilentlyContinue)) {
            function script:Set-ADAccountPassword { }
        }
        if (-not (Get-Command -Name 'Set-ADUser' -ErrorAction SilentlyContinue)) {
            function script:Set-ADUser { }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Reset-ADUserPassword' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:mockUser = [PSCustomObject]@{
            SamAccountName    = 'jdoe'
            DistinguishedName = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
            Enabled           = $true
        }

        $script:testPassword = ConvertTo-SecureString -String 'N3wP4ssw0rd-Test' -AsPlainText -Force
    }

    Context -Name 'Resets password successfully' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Set-ADAccountPassword' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Reset-ADUserPassword -Identity 'jdoe' -NewPassword $script:testPassword -Confirm:$false
        }

        It -Name 'Should return a result object' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have correct PSTypeName' -Test {
            $script:result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADPasswordResetResult'
        }

        It -Name 'Should report success' -Test {
            $script:result.Success | Should -BeTrue
        }

        It -Name 'Should have correct UserName' -Test {
            $script:result.UserName | Should -Be 'jdoe'
        }

        It -Name 'Should have a success message' -Test {
            $script:result.Message | Should -Be 'Password reset successfully'
        }

        It -Name 'Should have MustChangeAtLogon as false by default' -Test {
            $script:result.MustChangeAtLogon | Should -BeFalse
        }

        It -Name 'Should have Timestamp in ISO 8601 format' -Test {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context -Name 'MustChangePasswordAtLogon switch' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Set-ADAccountPassword' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Set-ADUser' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Reset-ADUserPassword -Identity 'jdoe' -NewPassword $script:testPassword -MustChangePasswordAtLogon -Confirm:$false
        }

        It -Name 'Should report MustChangeAtLogon as true' -Test {
            $script:result.MustChangeAtLogon | Should -BeTrue
        }

        It -Name 'Should report success' -Test {
            $script:result.Success | Should -BeTrue
        }
    }

    Context -Name 'Pipeline input is accepted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Set-ADAccountPassword' -ModuleName 'PSWinOps' -MockWith { }
        }

        It -Name 'Should accept string input from pipeline' -Test {
            { 'jdoe' | Reset-ADUserPassword -NewPassword $script:testPassword -Confirm:$false } | Should -Not -Throw
        }

        It -Name 'Should accept multiple strings from pipeline' -Test {
            $script:pipeResults = 'jdoe', 'asmith' | Reset-ADUserPassword -NewPassword $script:testPassword -Confirm:$false
            $script:pipeResults | Should -HaveCount 2
        }
    }

    Context -Name 'Error handling on failure' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                throw 'User not found in AD'
            }
            $script:result = Reset-ADUserPassword -Identity 'baduser' -NewPassword $script:testPassword -Confirm:$false -ErrorAction SilentlyContinue
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
                return $script:mockUser
            }
            Mock -CommandName 'Set-ADAccountPassword' -ModuleName 'PSWinOps' -MockWith { }
        }

        It -Name 'Should support WhatIf without performing action' -Test {
            $script:whatIfResult = Reset-ADUserPassword -Identity 'jdoe' -NewPassword $script:testPassword -WhatIf
            $script:whatIfResult | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Output object shape validation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUser
            }
            Mock -CommandName 'Set-ADAccountPassword' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Reset-ADUserPassword -Identity 'jdoe' -NewPassword $script:testPassword -Confirm:$false
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

        It -Name 'Should have MustChangeAtLogon property' -Test {
            $script:propertyNames | Should -Contain 'MustChangeAtLogon'
        }

        It -Name 'Should have Message property' -Test {
            $script:propertyNames | Should -Contain 'Message'
        }

        It -Name 'Should have Timestamp property' -Test {
            $script:propertyNames | Should -Contain 'Timestamp'
        }
    }
}
