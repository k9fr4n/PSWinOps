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
            $result = Test-DNSResolution -Name 'srv01.corp.local'
            $result.Success | Should -Be $true
            $result.Name | Should -Be 'srv01.corp.local'
            $result.Result | Should -Be '192.168.1.50'
        }

        It 'Should include PSTypeName PSWinOps.DnsResolution' {
            $result = Test-DNSResolution -Name 'srv01.corp.local'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.DnsResolution'
        }

        It 'Should include QueryTimeMs' {
            $result = Test-DNSResolution -Name 'srv01.corp.local'
            $result.QueryTimeMs | Should -Not -BeNullOrEmpty
        }

        It 'Should show (Default) when no DnsServer specified' {
            $result = Test-DNSResolution -Name 'srv01.corp.local'
            $result.DnsServer | Should -Be '(Default)'
        }

        It 'Should include Timestamp' {
            $result = Test-DNSResolution -Name 'srv01.corp.local'
            $result.Timestamp | Should -Not -BeNullOrEmpty
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
            $result = Test-DNSResolution -Name 'nonexistent.invalid'
            $result.Success | Should -Be $false
        }

        It 'Should include error message' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
        }

        It 'Should have null Result on failure' {
            $result = Test-DNSResolution -Name 'nonexistent.invalid'
            $result.Result | Should -BeNullOrEmpty
        }
    }

    Context 'Pipeline input' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Resolve-DnsName' -MockWith {
                [PSCustomObject]@{ QueryType = 'A'; Type = 1; IPAddress = '1.2.3.4'; Name = 'test' }
            }
        }

        It 'Should accept multiple names via pipeline' {
            $result = 'host1', 'host2', 'host3' | Test-DNSResolution
            $result.Count | Should -Be 3
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
