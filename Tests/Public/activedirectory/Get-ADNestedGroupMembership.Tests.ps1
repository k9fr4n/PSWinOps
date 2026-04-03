#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-ADNestedGroupMembership' {

    BeforeAll {
        # Fake AD object returned by Get-ADObject
        $script:fakeADObject = [PSCustomObject]@{
            DistinguishedName = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
            SamAccountName    = 'jdoe'
            ObjectClass       = 'user'
            MemberOf          = @(
                'CN=DirectGroup1,OU=Groups,DC=contoso,DC=com',
                'CN=DirectGroup2,OU=Groups,DC=contoso,DC=com'
            )
        }

        # Fake nested groups returned by Get-ADGroup
        $script:fakeNestedGroups = @(
            [PSCustomObject]@{
                Name              = 'DirectGroup1'
                DistinguishedName = 'CN=DirectGroup1,OU=Groups,DC=contoso,DC=com'
                GroupCategory     = 'Security'
                GroupScope        = 'Global'
                Description       = 'First direct group'
            },
            [PSCustomObject]@{
                Name              = 'DirectGroup2'
                DistinguishedName = 'CN=DirectGroup2,OU=Groups,DC=contoso,DC=com'
                GroupCategory     = 'Security'
                GroupScope        = 'DomainLocal'
                Description       = 'Second direct group'
            },
            [PSCustomObject]@{
                Name              = 'NestedGroup1'
                DistinguishedName = 'CN=NestedGroup1,OU=Groups,DC=contoso,DC=com'
                GroupCategory     = 'Distribution'
                GroupScope        = 'Universal'
                Description       = 'A nested group'
            }
        )
    }

    BeforeEach {
        Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADObject' -MockWith { $script:fakeADObject } -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADGroup' -MockWith { $script:fakeNestedGroups } -ModuleName 'PSWinOps'
    }

    Context 'Happy path - single identity' {

        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results = Get-ADNestedGroupMembership -Identity 'jdoe'
            $script:results | ForEach-Object -Process {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADNestedGroupMembership'
            }
        }

        It -Name 'Should return all nested groups' -Test {
            $script:results = Get-ADNestedGroupMembership -Identity 'jdoe'
            $script:results.Count | Should -Be 3
        }

        It -Name 'Should call Get-ADObject once' -Test {
            Get-ADNestedGroupMembership -Identity 'jdoe'
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should call Get-ADGroup once with LDAP filter' -Test {
            Get-ADNestedGroupMembership -Identity 'jdoe'
            Should -Invoke -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'IsDirect flag' {

        It -Name 'Should mark direct groups as IsDirect true' -Test {
            $script:results = Get-ADNestedGroupMembership -Identity 'jdoe'
            $script:directResults = $script:results | Where-Object -FilterScript { $_.GroupName -like 'DirectGroup*' }
            $script:directResults | ForEach-Object -Process {
                $_.IsDirect | Should -BeTrue
            }
        }

        It -Name 'Should mark nested-only groups as IsDirect false' -Test {
            $script:results = Get-ADNestedGroupMembership -Identity 'jdoe'
            $script:nestedResult = $script:results | Where-Object -FilterScript { $_.GroupName -eq 'NestedGroup1' }
            $script:nestedResult.IsDirect | Should -BeFalse
        }
    }

    Context 'Pipeline input - multiple identities' {

        It -Name 'Should process multiple identities from pipeline' -Test {
            $script:results = 'jdoe', 'svc-app01' | Get-ADNestedGroupMembership
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Identity not found' {

        It -Name 'Should write error and continue when identity not found' -Test {
            Mock -CommandName 'Get-ADObject' -MockWith { $null } -ModuleName 'PSWinOps'
            $script:result = Get-ADNestedGroupMembership -Identity 'nonexistent' -ErrorAction SilentlyContinue -ErrorVariable 'script:capturedError'
            $script:capturedError | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ActiveDirectory module missing' {

        It -Name 'Should throw when ActiveDirectory module is not available' -Test {
            Mock -CommandName 'Import-Module' -MockWith { throw 'Module not found' } -ModuleName 'PSWinOps'
            { Get-ADNestedGroupMembership -Identity 'jdoe' } | Should -Throw
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should reject null Identity' -Test {
            { Get-ADNestedGroupMembership -Identity $null } | Should -Throw
        }

        It -Name 'Should reject empty string Identity' -Test {
            { Get-ADNestedGroupMembership -Identity '' } | Should -Throw
        }
    }

    Context 'Server parameter passthrough' {

        It -Name 'Should pass Server parameter to Get-ADObject' -Test {
            Get-ADNestedGroupMembership -Identity 'jdoe' -Server 'DC01.contoso.com'
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Server -eq 'DC01.contoso.com'
            }
        }

        It -Name 'Should pass Server parameter to Get-ADGroup' -Test {
            Get-ADNestedGroupMembership -Identity 'jdoe' -Server 'DC01.contoso.com'
            Should -Invoke -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Server -eq 'DC01.contoso.com'
            }
        }
    }

    Context 'Credential parameter passthrough' {

        BeforeAll {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSAvoidUsingConvertToSecureStringWithPlainText', '',
                Justification = 'Test fixture only'
            )]
            $script:testPassword = ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force
            $script:testCredential = [System.Management.Automation.PSCredential]::new(
                'CONTOSO\admin',
                $script:testPassword
            )
        }

        It -Name 'Should pass Credential parameter to Get-ADObject' -Test {
            Get-ADNestedGroupMembership -Identity 'jdoe' -Credential $script:testCredential
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }

        It -Name 'Should pass Credential parameter to Get-ADGroup' -Test {
            Get-ADNestedGroupMembership -Identity 'jdoe' -Credential $script:testCredential
            Should -Invoke -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }
    }

    Context 'Output shape' {

        It -Name 'Should contain all expected properties on each object' -Test {
            $script:results = Get-ADNestedGroupMembership -Identity 'jdoe'
            $script:expectedProperties = @(
                'Identity', 'GroupName', 'GroupDN', 'GroupCategory',
                'GroupScope', 'Description', 'IsDirect', 'Timestamp'
            )
            foreach ($script:result in $script:results) {
                foreach ($script:propName in $script:expectedProperties) {
                    $script:result.PSObject.Properties.Name | Should -Contain $script:propName
                }
            }
        }

        It -Name 'Should return sorted output by GroupName' -Test {
            $script:results = Get-ADNestedGroupMembership -Identity 'jdoe'
            $script:groupNames = $script:results | Select-Object -ExpandProperty 'GroupName'
            $script:sortedNames = $script:groupNames | Sort-Object
            $script:groupNames | Should -Be $script:sortedNames
        }

        It -Name 'Should return ISO 8601 formatted Timestamp' -Test {
            $script:results = Get-ADNestedGroupMembership -Identity 'jdoe'
            $script:results[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }
}
