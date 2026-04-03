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
    & (Get-Module -Name 'PSWinOps') {
            if (-not (Get-Command -Name 'Get-ADGroup' -ErrorAction SilentlyContinue)) {
                function script:Get-ADGroup { }
            }
            if (-not (Get-Command -Name 'Get-ADGroupMember' -ErrorAction SilentlyContinue)) {
                function script:Get-ADGroupMember { }
            }
    }
}

Describe 'Get-ADGroupMembership' {
    BeforeEach {
        Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADGroup' -MockWith {
            [PSCustomObject]@{
                Name              = 'TestGroup'
                SamAccountName    = 'TestGroup'
                DistinguishedName = 'CN=TestGroup,OU=Groups,DC=contoso,DC=com'
            }
        } -ModuleName 'PSWinOps'

        $script:directMemberData = @(
            [PSCustomObject]@{
                Name              = 'John Doe'
                SamAccountName    = 'jdoe'
                ObjectClass       = 'user'
                DistinguishedName = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
            }
            [PSCustomObject]@{
                Name              = 'NestedGroup'
                SamAccountName    = 'NestedGroup'
                ObjectClass       = 'group'
                DistinguishedName = 'CN=NestedGroup,OU=Groups,DC=contoso,DC=com'
            }
        )

        $script:recursiveMemberData = @(
            [PSCustomObject]@{
                Name              = 'John Doe'
                SamAccountName    = 'jdoe'
                ObjectClass       = 'user'
                DistinguishedName = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
            }
            [PSCustomObject]@{
                Name              = 'Alice Smith'
                SamAccountName    = 'asmith'
                ObjectClass       = 'user'
                DistinguishedName = 'CN=Alice Smith,OU=Users,DC=contoso,DC=com'
            }
        )

        # Default mock returns direct members (used by non-recursive tests)
        Mock -CommandName 'Get-ADGroupMember' -MockWith {
            $script:directMemberData
        } -ModuleName 'PSWinOps'
    }

    Context 'Happy path - single identity without Recursive' {
        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results = Get-ADGroupMembership -Identity 'TestGroup'
            $script:results | ForEach-Object -Process {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADGroupMember'
            }
        }

        It -Name 'Should return direct members with IsDirect true' -Test {
            $script:results = Get-ADGroupMembership -Identity 'TestGroup'
            $script:results | ForEach-Object -Process {
                $_.IsDirect | Should -Be $true
            }
        }

        It -Name 'Should set GroupName to resolved group name' -Test {
            $script:results = Get-ADGroupMembership -Identity 'TestGroup'
            $script:results[0].GroupName | Should -Be 'TestGroup'
        }
    }

    Context 'Pipeline - multiple identities' {
        It -Name 'Should process multiple groups via pipeline' -Test {
            $script:results = @('TestGroup', 'AnotherGroup') | Get-ADGroupMembership
            Should -Invoke -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Per-identity failure handling' {
        It -Name 'Should write error and continue on failure' -Test {
            Mock -CommandName 'Get-ADGroup' -MockWith {
                throw 'Cannot find group'
            } -ModuleName 'PSWinOps'

            { Get-ADGroupMembership -Identity 'badgroup' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject null Identity' -Test {
            { Get-ADGroupMembership -Identity $null } | Should -Throw
        }

        It -Name 'Should reject empty string Identity' -Test {
            { Get-ADGroupMembership -Identity '' } | Should -Throw
        }
    }

    Context 'Server passthrough' {
        It -Name 'Should accept Server parameter without error' -Test {
            $script:results = Get-ADGroupMembership -Identity 'TestGroup' -Server 'dc01.contoso.com'
            $script:results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Credential passthrough' {
        It -Name 'Should accept Credential parameter without error' -Test {
            $script:testCredential = [System.Management.Automation.PSCredential]::new(
                'testuser',
                (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)
            )
            $script:results = Get-ADGroupMembership -Identity 'TestGroup' -Credential $script:testCredential
            $script:results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Output shape' {
        It -Name 'Should include all expected properties' -Test {
            $result = Get-ADGroupMembership -Identity 'TestGroup'
            $expectedProps = @(
                'GroupName', 'MemberName', 'SamAccountName', 'ObjectClass',
                'DistinguishedName', 'IsDirect', 'Timestamp'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($propName in $expectedProps) {
                $actualProps | Should -Contain $propName
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $result = Get-ADGroupMembership -Identity 'TestGroup'
            $result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It -Name 'Should sort output by ObjectClass then MemberName' -Test {
            $script:results = Get-ADGroupMembership -Identity 'TestGroup'
            $script:sortedResults = $script:results | Sort-Object -Property 'ObjectClass', 'MemberName'
            for ($script:idx = 0; $script:idx -lt $script:results.Count; $script:idx++) {
                $script:results[$script:idx].MemberName | Should -Be $script:sortedResults[$script:idx].MemberName
            }
        }
    }

    Context 'Recursive switch behavior' {
        BeforeEach {
            # Override mock: first call returns direct members, second returns recursive (all) members
            $script:getMemberCallCount = 0
            Mock -CommandName 'Get-ADGroupMember' -MockWith {
                $script:getMemberCallCount++
                if ($script:getMemberCallCount -eq 1) {
                    $script:directMemberData
                }
                else {
                    $script:recursiveMemberData
                }
            } -ModuleName 'PSWinOps'
        }

        It -Name 'Should call Get-ADGroupMember at least twice when Recursive is specified' -Test {
            Get-ADGroupMembership -Identity 'TestGroup' -Recursive
            Should -Invoke -CommandName 'Get-ADGroupMember' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }

        It -Name 'Should mark direct members as IsDirect true with Recursive' -Test {
            $script:results = Get-ADGroupMembership -Identity 'TestGroup' -Recursive
            $script:directResult = $script:results | Where-Object -Property 'SamAccountName' -EQ -Value 'jdoe'
            $script:directResult.IsDirect | Should -Be $true
        }

        It -Name 'Should mark nested-only members as IsDirect false with Recursive' -Test {
            $script:results = Get-ADGroupMembership -Identity 'TestGroup' -Recursive
            $script:nestedResult = $script:results | Where-Object -Property 'SamAccountName' -EQ -Value 'asmith'
            # asmith only appears in recursive results, not in direct results
            $script:nestedResult.IsDirect | Should -BeFalse
        }

        It -Name 'Should only call Get-ADGroupMember once without Recursive switch' -Test {
            Get-ADGroupMembership -Identity 'TestGroup'
            Should -Invoke -CommandName 'Get-ADGroupMember' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }
}
