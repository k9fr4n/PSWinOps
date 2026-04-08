BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Test-DNSResolution' {

    Context 'Happy path — single DNS server' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{
                    QueryType = 'A'
                    Type      = 1
                    IPAddress = '192.168.1.50'
                    Name      = 'srv01.corp.local'
                }
            }
        }

        It 'Should return a successful resolution' {
            $result = Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1'
            $result.Success | Should -Be $true
            $result.Name | Should -Be 'srv01.corp.local'
            $result.Result | Should -Be '192.168.1.50'
        }

        It 'Should include PSTypeName PSWinOps.DnsResolution' {
            $result = Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.DnsResolution'
        }

        It 'Should include QueryTimeMs' {
            $result = Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1'
            $result.QueryTimeMs | Should -Not -BeNullOrEmpty
        }

        It 'Should show server address in DnsServer property' {
            $result = Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1'
            $result.DnsServer | Should -Be '10.0.0.1'
        }

        It 'Should include Timestamp in ISO 8601 format' {
            $result = Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1'
            $result.Timestamp | Should -Not -BeNullOrEmpty
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }

        It 'Should include all expected properties' {
            $result = Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1'
            $expectedProperties = @('Name', 'DnsServer', 'QueryType', 'Result',
                                    'QueryTimeMs', 'Success', 'Consistent', 'ErrorMessage', 'Timestamp')
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }

    Context 'Positional parameter binding' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'A'; Type = 1; IPAddress = '1.2.3.4'; Name = 'test.local' }
            }
        }

        It 'Should accept Name as positional parameter' {
            $result = Test-DNSResolution 'test.local' -DnsServer '10.0.0.1'
            $result.Name | Should -Be 'test.local'
            $result.Success | Should -Be $true
        }
    }

    Context 'Default DNS server (no -DnsServer specified)' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'A'; Type = 1; IPAddress = '1.2.3.4'; Name = 'test.local' }
            }
        }

        It 'Should set DnsServer to (Default) when parameter is omitted' {
            $result = Test-DNSResolution -Name 'test.local'
            $result.DnsServer | Should -Be '(Default)'
        }

        It 'Should produce output even without -DnsServer' {
            $result = Test-DNSResolution -Name 'test.local'
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
        }

        It 'Should invoke Resolve-DnsName without -Server parameter' {
            $null = Test-DNSResolution -Name 'test.local'
            Should -Invoke -CommandName 'Resolve-DnsName' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $null -eq $Server
            }
        }

        It 'Should set Consistent to null for single-server queries' {
            $result = Test-DNSResolution -Name 'test.local'
            $result.Consistent | Should -BeNullOrEmpty
        }
    }

    Context 'Default DNS server — resolution failure' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                throw 'DNS name does not exist'
            }
        }

        It 'Should produce a failure row even without -DnsServer' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid'
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $false
            $result.DnsServer | Should -Be '(Default)'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Multiple DNS servers — consistent results' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{
                    QueryType = 'A'
                    Type      = 1
                    IPAddress = '10.0.0.50'
                    Name      = 'app.corp.local'
                }
            }
        }

        It 'Should return one result per DNS server' {
            $result = Test-DNSResolution -Name 'app.corp.local' -DnsServer '10.0.0.1', '10.0.0.2'
            $result.Count | Should -Be 2
        }

        It 'Should mark all results as Consistent when results match' {
            $result = Test-DNSResolution -Name 'app.corp.local' -DnsServer '10.0.0.1', '10.0.0.2'
            $result | ForEach-Object { $_.Consistent | Should -Be $true }
        }
    }

    Context 'Multiple DNS servers — inconsistent results' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                param($Name, $Server)
                if ($Server -eq '10.0.0.1') {
                    [PSCustomObject]@{ QueryType = 'A'; Type = 1; IPAddress = '192.168.1.50'; Name = $Name }
                } else {
                    [PSCustomObject]@{ QueryType = 'A'; Type = 1; IPAddress = '10.10.10.50'; Name = $Name }
                }
            }
        }

        It 'Should mark results as inconsistent when IPs differ' {
            $result = Test-DNSResolution -Name 'split.corp.local' -DnsServer '10.0.0.1', '10.0.0.2'
            $result | ForEach-Object { $_.Consistent | Should -Be $false }
        }
    }

    Context 'Multiple DNS servers — partial failure' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                param($Name, $Server)
                if ($Server -eq '10.0.0.1') {
                    [PSCustomObject]@{ QueryType = 'A'; Type = 1; IPAddress = '192.168.1.50'; Name = $Name }
                } else {
                    throw 'DNS server unreachable'
                }
            }
        }

        It 'Should return results for all servers even when some fail' {
            $result = Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1', '10.0.0.2'
            $result.Count | Should -Be 2
        }

        It 'Should set Consistent to null when only one server succeeds' {
            $result = Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1', '10.0.0.2'
            $result | ForEach-Object { $_.Consistent | Should -BeNullOrEmpty }
        }
    }

    Context 'Single DNS server — failure' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                throw 'DNS name does not exist'
            }
        }

        It 'Should return Success=False on resolution failure' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid' -DnsServer '10.0.0.1'
            $result.Success | Should -Be $false
        }

        It 'Should include error message' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid' -DnsServer '10.0.0.1'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
        }

        It 'Should have null Result on failure' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid' -DnsServer '10.0.0.1'
            $result.Result | Should -BeNullOrEmpty
        }

        It 'Should have null QueryTimeMs on failure' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid' -DnsServer '10.0.0.1'
            $result.QueryTimeMs | Should -BeNullOrEmpty
        }

        It 'Should still include PSTypeName on failure' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid' -DnsServer '10.0.0.1'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.DnsResolution'
        }

        It 'Should set Consistent to null for single-server failure' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid' -DnsServer '10.0.0.1'
            $result.Consistent | Should -BeNullOrEmpty
        }
    }

    Context 'DNS response with no matching record type' {

        BeforeEach {
            # Resolve-DnsName returns SOA (negative answer) when querying NS for a host
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{
                    QueryType         = 'SOA'
                    Name              = 'host.corp.local'
                    NameAdministrator = 'admin.corp.local'
                }
            }
        }

        It 'Should set Success=False when no records match the requested type' {
            $result = Test-DNSResolution -Name 'host.corp.local' -DnsServer '10.0.0.1' -Type NS
            $result.Success | Should -Be $false
        }

        It 'Should include descriptive error message for empty results' {
            $result = Test-DNSResolution -Name 'host.corp.local' -DnsServer '10.0.0.1' -Type NS
            $result.ErrorMessage | Should -Match 'No NS records found'
        }

        It 'Should still populate QueryTimeMs (query succeeded at DNS level)' {
            $result = Test-DNSResolution -Name 'host.corp.local' -DnsServer '10.0.0.1' -Type NS
            $result.QueryTimeMs | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Pipeline input' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'A'; Type = 1; IPAddress = '1.2.3.4'; Name = 'test' }
            }
        }

        It 'Should accept multiple names via pipeline' {
            $result = 'host1', 'host2', 'host3' | Test-DNSResolution -DnsServer '10.0.0.1'
            $result.Count | Should -Be 3
        }

        It 'Should invoke Resolve-DnsName once per name' {
            $null = 'host1', 'host2' | Test-DNSResolution -DnsServer '10.0.0.1'
            Should -Invoke -CommandName 'Resolve-DnsName' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should invoke Resolve-DnsName N*M times for N names x M servers' {
            $null = 'host1', 'host2' | Test-DNSResolution -DnsServer '10.0.0.1', '10.0.0.2'
            Should -Invoke -CommandName 'Resolve-DnsName' -ModuleName $script:ModuleName -Times 4 -Exactly
        }
    }

    Context 'Record type parameter' {

        It 'Should extract MX records via NameExchange' {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'MX'; NameExchange = 'mail.corp.local'; Name = 'corp.local' }
            }
            $result = Test-DNSResolution -Name 'corp.local' -DnsServer '10.0.0.1' -Type MX
            $result.QueryType | Should -Be 'MX'
            $result.Success | Should -Be $true
            $result.Result | Should -Be 'mail.corp.local'
        }

        It 'Should extract NS records via NameHost' {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'NS'; NameHost = 'ns1.corp.local'; Name = 'corp.local' }
            }
            $result = Test-DNSResolution -Name 'corp.local' -DnsServer '10.0.0.1' -Type NS
            $result.Success | Should -Be $true
            $result.Result | Should -Be 'ns1.corp.local'
        }

        It 'Should extract TXT records via Strings' {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'TXT'; Strings = @('v=spf1 include:example.com ~all'); Name = 'corp.local' }
            }
            $result = Test-DNSResolution -Name 'corp.local' -DnsServer '10.0.0.1' -Type TXT
            $result.Success | Should -Be $true
            $result.Result | Should -Match 'v=spf1'
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty Name' {
            { Test-DNSResolution -Name '' } | Should -Throw
        }

        It 'Should reject null Name' {
            { Test-DNSResolution -Name $null } | Should -Throw
        }

        It 'Should reject invalid Type' {
            { Test-DNSResolution -Name 'test' -Type 'INVALID' } | Should -Throw
        }

        It 'Should reject empty DnsServer' {
            { Test-DNSResolution -Name 'test' -DnsServer '' } | Should -Throw
        }
    }

    Context 'Integration' -Tag 'Integration' {

        It 'Should resolve a well-known hostname' -Skip:(-not ($env:OS -eq 'Windows_NT')) {
            $result = Test-DNSResolution -Name 'dns.google' -DnsServer '8.8.8.8'
            $result.Success | Should -Be $true
            $result.Result | Should -Match '\d+\.\d+\.\d+\.\d+'
        }
    }
}
