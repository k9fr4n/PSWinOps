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

Describe 'Get-ADComputerDetail' {
    BeforeEach {
        Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
        Mock -CommandName 'Get-ADComputer' -MockWith {
            [PSCustomObject]@{
                Name                      = 'SRV01'
                DNSHostName               = 'SRV01.contoso.com'
                Description               = 'Web Server'
                OperatingSystem           = 'Windows Server 2022 Standard'
                OperatingSystemVersion    = '10.0 (20348)'
                OperatingSystemServicePack = $null
                IPv4Address               = '10.0.1.50'
                Enabled                   = $true
                LastLogonDate             = [datetime]'2026-04-02T18:00:00'
                WhenCreated               = [datetime]'2024-03-15T10:00:00'
                WhenChanged               = [datetime]'2026-04-01T12:00:00'
                MemberOf                  = @(
                    'CN=WebServers,OU=Groups,DC=contoso,DC=com'
                    'CN=PatchGroup1,OU=Groups,DC=contoso,DC=com'
                )
                DistinguishedName         = 'CN=SRV01,OU=Servers,DC=contoso,DC=com'
                ServicePrincipalNames     = @(
                    'HOST/SRV01'
                    'HOST/SRV01.contoso.com'
                    'TERMSRV/SRV01'
                )
                Location                  = 'Datacenter-A Rack-12'
            }
        } -ModuleName 'PSWinOps'
    }

    Context 'Happy path - single identity' {
        It -Name 'Should return object with correct PSTypeName' -Test {
            $result = Get-ADComputerDetail -Identity 'SRV01'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADComputerDetail'
        }

        It -Name 'Should return expected Name' -Test {
            $result = Get-ADComputerDetail -Identity 'SRV01'
            $result.Name | Should -Be 'SRV01'
        }

        It -Name 'Should call Get-ADComputer exactly once' -Test {
            Get-ADComputerDetail -Identity 'SRV01'
            Should -Invoke -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Pipeline - multiple identities' {
        It -Name 'Should return one result per identity' -Test {
            $script:results = @('SRV01', 'SRV02') | Get-ADComputerDetail
            $script:results.Count | Should -Be 2
        }

        It -Name 'Should call Get-ADComputer once per identity' -Test {
            @('SRV01', 'SRV02') | Get-ADComputerDetail
            Should -Invoke -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Per-identity failure handling' {
        It -Name 'Should write error and continue on failure' -Test {
            Mock -CommandName 'Get-ADComputer' -MockWith {
                throw 'Cannot find object'
            } -ModuleName 'PSWinOps'

            { Get-ADComputerDetail -Identity 'BADHOST' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should continue processing after a failure' -Test {
            $script:callCount = 0
            Mock -CommandName 'Get-ADComputer' -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    throw 'Cannot find object'
                }
                [PSCustomObject]@{
                    Name                      = 'SRV02'
                    DNSHostName               = 'SRV02.contoso.com'
                    Description               = $null
                    OperatingSystem           = 'Windows Server 2022 Standard'
                    OperatingSystemVersion    = '10.0 (20348)'
                    OperatingSystemServicePack = $null
                    IPv4Address               = '10.0.1.51'
                    Enabled                   = $true
                    LastLogonDate             = $null
                    WhenCreated               = [datetime]'2025-01-01'
                    WhenChanged               = [datetime]'2025-01-01'
                    MemberOf                  = @()
                    DistinguishedName         = 'CN=SRV02,OU=Servers,DC=contoso,DC=com'
                    ServicePrincipalNames     = @()
                    Location                  = $null
                }
            } -ModuleName 'PSWinOps'

            $script:results = Get-ADComputerDetail -Identity 'BADHOST', 'SRV02' -ErrorAction SilentlyContinue
            $script:results.Count | Should -Be 1
            $script:results.Name | Should -Be 'SRV02'
        }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject null Identity' -Test {
            { Get-ADComputerDetail -Identity $null } | Should -Throw
        }

        It -Name 'Should reject empty string Identity' -Test {
            { Get-ADComputerDetail -Identity '' } | Should -Throw
        }
    }

    Context 'Server passthrough' {
        It -Name 'Should forward Server parameter to Get-ADComputer' -Test {
            Get-ADComputerDetail -Identity 'SRV01' -Server 'dc01.contoso.com'
            Should -Invoke -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Server -eq 'dc01.contoso.com'
            }
        }
    }

    Context 'Credential passthrough' {
        It -Name 'Should forward Credential parameter to Get-ADComputer' -Test {
            $script:testCredential = [System.Management.Automation.PSCredential]::new(
                'testuser',
                (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)
            )
            Get-ADComputerDetail -Identity 'SRV01' -Credential $script:testCredential
            Should -Invoke -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }
    }

    Context 'Output shape' {
        It -Name 'Should include all expected properties' -Test {
            $result = Get-ADComputerDetail -Identity 'SRV01'
            $expectedProps = @(
                'Name', 'DNSHostName', 'Description', 'OperatingSystem',
                'OperatingSystemVersion', 'IPv4Address', 'Enabled', 'LastLogonDate',
                'WhenCreated', 'WhenChanged', 'Location', 'MemberOfCount',
                'SPNCount', 'OrganizationalUnit', 'DistinguishedName', 'Timestamp'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($propName in $expectedProps) {
                $actualProps | Should -Contain $propName
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $result = Get-ADComputerDetail -Identity 'SRV01'
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context 'OU extraction from DistinguishedName' {
        It -Name 'Should extract OrganizationalUnit correctly' -Test {
            $result = Get-ADComputerDetail -Identity 'SRV01'
            $result.OrganizationalUnit | Should -Be 'OU=Servers,DC=contoso,DC=com'
        }
    }

    Context 'Count properties' {
        It -Name 'Should count MemberOf groups correctly' -Test {
            $result = Get-ADComputerDetail -Identity 'SRV01'
            $result.MemberOfCount | Should -Be 2
        }

        It -Name 'Should count ServicePrincipalNames correctly' -Test {
            $result = Get-ADComputerDetail -Identity 'SRV01'
            $result.SPNCount | Should -Be 3
        }

        It -Name 'Should return 0 for MemberOfCount when MemberOf is null' -Test {
            Mock -CommandName 'Get-ADComputer' -MockWith {
                [PSCustomObject]@{
                    Name                      = 'LONELY'
                    DNSHostName               = 'LONELY.contoso.com'
                    Description               = $null
                    OperatingSystem           = $null
                    OperatingSystemVersion    = $null
                    OperatingSystemServicePack = $null
                    IPv4Address               = $null
                    Enabled                   = $true
                    LastLogonDate             = $null
                    WhenCreated               = [datetime]'2025-01-01'
                    WhenChanged               = [datetime]'2025-01-01'
                    MemberOf                  = $null
                    DistinguishedName         = 'CN=LONELY,OU=Servers,DC=contoso,DC=com'
                    ServicePrincipalNames     = $null
                    Location                  = $null
                }
            } -ModuleName 'PSWinOps'

            $result = Get-ADComputerDetail -Identity 'LONELY'
            $result.MemberOfCount | Should -Be 0
            $result.SPNCount | Should -Be 0
        }
    }
}
