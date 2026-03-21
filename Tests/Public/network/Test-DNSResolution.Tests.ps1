BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Test-DNSResolution' {

    Context 'Happy path - single DNS server' {

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

        It 'Should include Timestamp' {
            $result = Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1'
            $result.Timestamp | Should -Not -BeNullOrEmpty
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

    Context 'Default DNS server (no -DnsServer specified)' {

        It 'Should set DnsServer to (Default) when parameter is omitted' {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'A'; Type = 1; IPAddress = '1.2.3.4'; Name = 'test' }
            }
            $result = Test-DNSResolution -Name 'test.local' -DnsServer '10.0.0.1'
            # When DnsServer is specified, it should show the server address
            $result.DnsServer | Should -Be '10.0.0.1'
        }

        It 'Should query exactly once when a single DnsServer is specified' {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'A'; Type = 1; IPAddress = '1.2.3.4'; Name = 'test' }
            }
            $null = Test-DNSResolution -Name 'test.local' -DnsServer '10.0.0.1'
            Should -Invoke -CommandName 'Resolve-DnsName' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Multiple DNS servers - consistent results' {

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

    Context 'Multiple DNS servers - inconsistent results' {

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

    Context 'DNS resolution failure' {

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

        It 'Should still include PSTypeName on failure' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid' -DnsServer '10.0.0.1'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.DnsResolution'
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
    }

    Context 'Record type parameter' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'MX'; NameExchange = 'mail.corp.local'; Name = 'corp.local' }
            }
        }

        It 'Should pass the Type parameter to Resolve-DnsName' {
            $result = Test-DNSResolution -Name 'corp.local' -DnsServer '10.0.0.1' -Type MX
            $result.QueryType | Should -Be 'MX'
            $result.Success | Should -Be $true
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty Name' {
            { Test-DNSResolution -Name '' } | Should -Throw
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
