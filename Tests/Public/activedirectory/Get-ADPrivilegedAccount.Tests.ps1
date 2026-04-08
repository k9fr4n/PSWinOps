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

    # Create proxy functions for AD cmdlets not available on CI runners
        if (-not (Get-Command -Name 'Get-ADGroup' -ErrorAction SilentlyContinue)) {
            function global:Get-ADGroup { }
        }
        if (-not (Get-Command -Name 'Get-ADGroupMember' -ErrorAction SilentlyContinue)) {
            function global:Get-ADGroupMember { }
        }
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function global:Get-ADUser { }
        }
    & (Get-Module -Name 'PSWinOps') {
            if (-not (Get-Command -Name 'Get-ADGroup' -ErrorAction SilentlyContinue)) {
                function script:Get-ADGroup { }
            }
            if (-not (Get-Command -Name 'Get-ADGroupMember' -ErrorAction SilentlyContinue)) {
                function script:Get-ADGroupMember { }
            }
            if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
                function script:Get-ADUser { }
            }
    }
}

Describe 'Get-ADPrivilegedAccount' {
    BeforeAll {
        $script:fakeGroup = [PSCustomObject]@{
            Name              = 'Domain Admins'
            SamAccountName    = 'Domain Admins'
            DistinguishedName = 'CN=Domain Admins,CN=Users,DC=contoso,DC=com'
        }

        $script:fakeMembers = @(
            [PSCustomObject]@{
                Name              = 'John Doe'
                SamAccountName    = 'jdoe'
                ObjectClass       = 'user'
                DistinguishedName = 'CN=John Doe,OU=Admins,DC=contoso,DC=com'
            }
            [PSCustomObject]@{
                Name              = 'Nested Admins'
                SamAccountName    = 'NestedAdmins'
                ObjectClass       = 'group'
                DistinguishedName = 'CN=Nested Admins,OU=Groups,DC=contoso,DC=com'
            }
        )

        $script:fakeUserDetail = [PSCustomObject]@{
            SamAccountName = 'jdoe'
            Enabled        = $true
            LastLogonDate  = [datetime]::Parse('2026-04-02T10:00:00')
        }
    }

    BeforeEach {
        Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADGroup' -MockWith { $script:fakeGroup } -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADGroupMember' -MockWith { $script:fakeMembers } -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADUser' -MockWith { $script:fakeUserDetail } -ModuleName 'PSWinOps'
    }

    Context 'Happy path - default groups' {
        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins'
            $script:results | ForEach-Object -Process {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADPrivilegedAccount'
            }
        }

        It -Name 'Should return members for the queried group' -Test {
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins'
            $script:results.Count | Should -Be 2
        }

        It -Name 'Should use default group list when GroupName not specified' -Test {
            Get-ADPrivilegedAccount
            Should -Invoke -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -Times 8 -Exactly
        }
    }

    Context 'User member properties' {
        It -Name 'Should populate Enabled and LastLogonDate for user members' -Test {
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins'
            $script:userResult = $script:results | Where-Object -Property 'ObjectClass' -EQ -Value 'user'
            $script:userResult.Enabled | Should -BeTrue
            $script:userResult.LastLogonDate | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have null Enabled and LastLogonDate for non-user members' -Test {
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins'
            $script:groupResult = $script:results | Where-Object -Property 'ObjectClass' -EQ -Value 'group'
            $script:groupResult.Enabled | Should -BeNullOrEmpty
            $script:groupResult.LastLogonDate | Should -BeNullOrEmpty
        }
    }

    Context 'Recursive is the default' {
        It -Name 'Should enumerate recursively by default' -Test {
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins'
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should accept DirectOnly switch to disable recursion' -Test {
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins' -DirectOnly
            $script:results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Per-group error handling' {
        It -Name 'Should continue when one group fails' -Test {
            $script:callCount = 0
            Mock -CommandName 'Get-ADGroup' -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) { throw 'Cannot find group' }
                $script:fakeGroup
            } -ModuleName 'PSWinOps'

            $script:results = Get-ADPrivilegedAccount -GroupName 'BadGroup', 'Domain Admins' -ErrorAction SilentlyContinue
            $script:results.Count | Should -Be 2
        }
    }

    Context 'Server passthrough' {
        It -Name 'Should accept Server parameter without error' -Test {
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins' -Server 'dc01.contoso.com'
            $script:results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Credential passthrough' {
        It -Name 'Should accept Credential parameter without error' -Test {
            $script:testCredential = [System.Management.Automation.PSCredential]::new(
                'testuser',
                (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)
            )
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins' -Credential $script:testCredential
            $script:results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Output shape' {
        It -Name 'Should include all expected properties' -Test {
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins'
            $script:expectedProps = @(
                'GroupName', 'MemberName', 'SamAccountName', 'ObjectClass',
                'Enabled', 'LastLogonDate', 'DistinguishedName', 'Timestamp'
            )
            $script:actualProps = $script:results[0].PSObject.Properties.Name
            foreach ($script:propName in $script:expectedProps) {
                $script:actualProps | Should -Contain $script:propName
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $script:results = Get-ADPrivilegedAccount -GroupName 'Domain Admins'
            $script:results[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }
    }
}
