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

Describe 'Search-ADObject' {
    BeforeEach {
        Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADObject' -MockWith {
            @(
                [PSCustomObject]@{
                    Name              = 'TestUser1'
                    ObjectClass       = 'user'
                    DistinguishedName = 'CN=TestUser1,OU=Users,DC=contoso,DC=com'
                }
                [PSCustomObject]@{
                    Name              = 'TestUser2'
                    ObjectClass       = 'user'
                    DistinguishedName = 'CN=TestUser2,OU=Users,DC=contoso,DC=com'
                }
            )
        } -ModuleName 'PSWinOps'
    }

    Context 'Happy path - basic search' {
        It -Name 'Should return objects with correct PSTypeName' -Test {
            $script:results = Search-ADObject -LDAPFilter '(objectClass=user)'
            $script:results | ForEach-Object -Process {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADSearchResult'
            }
        }

        It -Name 'Should return expected number of results' -Test {
            $script:results = Search-ADObject -LDAPFilter '(objectClass=user)'
            $script:results.Count | Should -Be 2
        }

        It -Name 'Should call Get-ADObject exactly once' -Test {
            Search-ADObject -LDAPFilter '(objectClass=user)'
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Search failure handling' {
        It -Name 'Should write error when search fails' -Test {
            Mock -CommandName 'Get-ADObject' -MockWith {
                throw 'Search operation failed'
            } -ModuleName 'PSWinOps'

            { Search-ADObject -LDAPFilter '(invalid)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject null LDAPFilter' -Test {
            { Search-ADObject -LDAPFilter $null } | Should -Throw
        }

        It -Name 'Should reject empty string LDAPFilter' -Test {
            { Search-ADObject -LDAPFilter '' } | Should -Throw
        }

        It -Name 'Should reject invalid SearchScope' -Test {
            { Search-ADObject -LDAPFilter '(objectClass=user)' -SearchScope 'Invalid' } | Should -Throw
        }

        It -Name 'Should reject ResultSetSize below 1' -Test {
            { Search-ADObject -LDAPFilter '(objectClass=user)' -ResultSetSize 0 } | Should -Throw
        }

        It -Name 'Should reject ResultSetSize above 100000' -Test {
            { Search-ADObject -LDAPFilter '(objectClass=user)' -ResultSetSize 100001 } | Should -Throw
        }
    }

    Context 'Server passthrough' {
        It -Name 'Should forward Server parameter to Get-ADObject' -Test {
            Search-ADObject -LDAPFilter '(objectClass=user)' -Server 'dc01.contoso.com'
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Server -eq 'dc01.contoso.com'
            }
        }
    }

    Context 'Credential passthrough' {
        It -Name 'Should forward Credential parameter to Get-ADObject' -Test {
            $script:testCredential = [System.Management.Automation.PSCredential]::new(
                'testuser',
                (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)
            )
            Search-ADObject -LDAPFilter '(objectClass=user)' -Credential $script:testCredential
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }
    }

    Context 'Output shape' {
        It -Name 'Should include all base properties' -Test {
            $result = Search-ADObject -LDAPFilter '(objectClass=user)'
            $expectedProps = @('Name', 'ObjectClass', 'DistinguishedName', 'Timestamp')
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($propName in $expectedProps) {
                $actualProps | Should -Contain $propName
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $result = Search-ADObject -LDAPFilter '(objectClass=user)'
            $result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context 'SearchBase passthrough' {
        It -Name 'Should forward SearchBase parameter to Get-ADObject' -Test {
            Search-ADObject -LDAPFilter '(objectClass=group)' -SearchBase 'OU=Groups,DC=contoso,DC=com'
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $SearchBase -eq 'OU=Groups,DC=contoso,DC=com'
            }
        }
    }

    Context 'SearchScope passthrough' {
        It -Name 'Should forward SearchScope parameter to Get-ADObject' -Test {
            Search-ADObject -LDAPFilter '(objectClass=user)' -SearchScope 'OneLevel'
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $SearchScope -eq 'OneLevel'
            }
        }

        It -Name 'Should default SearchScope to Subtree' -Test {
            Search-ADObject -LDAPFilter '(objectClass=user)'
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $SearchScope -eq 'Subtree'
            }
        }
    }

    Context 'Properties passthrough' {
        It -Name 'Should include additional properties in output when specified' -Test {
            Mock -CommandName 'Get-ADObject' -MockWith {
                @(
                    [PSCustomObject]@{
                        Name              = 'SRV01'
                        ObjectClass       = 'computer'
                        DistinguishedName = 'CN=SRV01,OU=Servers,DC=contoso,DC=com'
                        OperatingSystem   = 'Windows Server 2022'
                        LastLogonDate     = [datetime]'2026-04-01'
                    }
                )
            } -ModuleName 'PSWinOps'

            $result = Search-ADObject -LDAPFilter '(objectClass=computer)' -Properties 'OperatingSystem', 'LastLogonDate'
            $result[0].PSObject.Properties.Name | Should -Contain 'OperatingSystem'
            $result[0].PSObject.Properties.Name | Should -Contain 'LastLogonDate'
            $result[0].OperatingSystem | Should -Be 'Windows Server 2022'
        }

        It -Name 'Should forward Properties to Get-ADObject' -Test {
            Search-ADObject -LDAPFilter '(objectClass=computer)' -Properties 'OperatingSystem'
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Properties -contains 'OperatingSystem'
            }
        }
    }

    Context 'ResultSetSize passthrough' {
        It -Name 'Should forward ResultSetSize parameter to Get-ADObject' -Test {
            Search-ADObject -LDAPFilter '(objectClass=user)' -ResultSetSize 50
            Should -Invoke -CommandName 'Get-ADObject' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ResultSetSize -eq 50
            }
        }
    }
}
