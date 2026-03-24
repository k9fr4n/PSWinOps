BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-PublicIPAddress' {

    BeforeAll {
        $script:mockIPv4Result = [PSCustomObject]@{
            ip = '203.0.113.42'
        }
        $script:mockIPv6Result = [PSCustomObject]@{
            ip = '2001:db8::1'
        }
    }

    Context 'Happy path — local machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                return $script:mockIPv4Result
            } -ModuleName 'PSWinOps'
        }

        It 'Should return a PSWinOps.PublicIPAddress object for the local machine' {
            $result = Get-PublicIPAddress

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.PublicIPAddress'
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.IPv4Address | Should -Be '203.0.113.42'
            $result.Provider | Should -Be 'ipify.org'
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should not populate IPv6Address by default' {
            $result = Get-PublicIPAddress
            $result.IPv6Address | Should -BeNullOrEmpty
        }
    }

    Context 'Happy path — explicit remote machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return [PSCustomObject]@{
                    IPv4Address = '198.51.100.10'
                    IPv6Address = $null
                    Provider    = 'ipify.org'
                }
            } -ModuleName 'PSWinOps'
        }

        It 'Should return the public IP for a remote computer' {
            $result = Get-PublicIPAddress -ComputerName 'REMOTE01'

            $result.ComputerName | Should -Be 'REMOTE01'
            $result.IPv4Address | Should -Be '198.51.100.10'
            $result.Provider | Should -Be 'ipify.org'
        }

        It 'Should pass Credential to Invoke-Command when specified' {
            $cred = [PSCredential]::new('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            Get-PublicIPAddress -ComputerName 'REMOTE01' -Credential $cred

            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -ParameterFilter {
                $Credential -ne $null
            }
        }
    }

    Context 'Pipeline — multiple machine names' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return [PSCustomObject]@{
                    IPv4Address = '198.51.100.10'
                    IPv6Address = $null
                    Provider    = 'ipify.org'
                }
            } -ModuleName 'PSWinOps'
        }

        It 'Should return one result per piped computer name' {
            $results = @('SRV01', 'SRV02', 'SRV03') | Get-PublicIPAddress

            $results | Should -HaveCount 3
            $results[0].ComputerName | Should -Be 'SRV01'
            $results[1].ComputerName | Should -Be 'SRV02'
            $results[2].ComputerName | Should -Be 'SRV03'
        }
    }

    Context 'Per-machine failure — function continues and writes error' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                throw 'Connection refused'
            } -ModuleName 'PSWinOps'
        }

        It 'Should write an error but not throw for a failing machine' {
            $results = @('FAIL01', 'FAIL02') | Get-PublicIPAddress -ErrorAction SilentlyContinue -ErrorVariable errs

            $errs | Should -Not -BeNullOrEmpty
            $errMessages = $errs | ForEach-Object { $_.Exception.Message }
            ($errMessages -like "*Failed on 'FAIL01'*") | Should -Not -BeNullOrEmpty
            ($errMessages -like "*Failed on 'FAIL02'*") | Should -Not -BeNullOrEmpty
        }
    }

    Context 'IPv6 switch' {

        BeforeAll {
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                param ($Uri)
                if ($Uri -match 'api64') {
                    return $script:mockIPv6Result
                }
                return $script:mockIPv4Result
            } -ModuleName 'PSWinOps'
        }

        It 'Should populate IPv6Address when -IPv6 is specified' {
            $result = Get-PublicIPAddress -IPv6

            $result.IPv4Address | Should -Be '203.0.113.42'
            $result.IPv6Address | Should -Be '2001:db8::1'
        }
    }

    Context 'Fallback provider' {

        BeforeAll {
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                throw 'ipify down'
            } -ModuleName 'PSWinOps'

            Mock -CommandName 'Invoke-WebRequest' -MockWith {
                return [PSCustomObject]@{
                    Content = '192.0.2.99'
                }
            } -ModuleName 'PSWinOps'
        }

        It 'Should fall back to ifconfig.me when ipify fails' {
            $result = Get-PublicIPAddress

            $result.IPv4Address | Should -Be '192.0.2.99'
            $result.Provider | Should -Be 'ifconfig.me'
        }
    }

    Context 'All providers unavailable' {

        BeforeAll {
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                throw 'ipify down'
            } -ModuleName 'PSWinOps'

            Mock -CommandName 'Invoke-WebRequest' -MockWith {
                throw 'ifconfig.me down'
            } -ModuleName 'PSWinOps'
        }

        It 'Should return null IPv4Address and Provider = Unavailable' {
            $result = Get-PublicIPAddress

            $result.IPv4Address | Should -BeNullOrEmpty
            $result.Provider | Should -Be 'Unavailable'
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty ComputerName' {
            { Get-PublicIPAddress -ComputerName '' } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            { Get-PublicIPAddress -ComputerName $null } | Should -Throw
        }

        It 'Should reject TimeoutSec out of range' {
            { Get-PublicIPAddress -TimeoutSec 0 } | Should -Throw
            { Get-PublicIPAddress -TimeoutSec 61 } | Should -Throw
        }

        It 'Should support CN, Name, and DNSHostName aliases for ComputerName' {
            $cmd = Get-Command -Name 'Get-PublicIPAddress'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName'
        }

        It 'Should declare OutputType PSWinOps.PublicIPAddress' {
            $cmd = Get-Command -Name 'Get-PublicIPAddress'
            $cmd.OutputType.Name | Should -Contain 'PSWinOps.PublicIPAddress'
        }
    }

    Context 'Output object shape' {

        BeforeAll {
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                return $script:mockIPv4Result
            } -ModuleName 'PSWinOps'
        }

        It 'Should have all expected properties' {
            $result = Get-PublicIPAddress
            $propertyNames = $result.PSObject.Properties.Name

            $propertyNames | Should -Contain 'ComputerName'
            $propertyNames | Should -Contain 'IPv4Address'
            $propertyNames | Should -Contain 'IPv6Address'
            $propertyNames | Should -Contain 'Provider'
            $propertyNames | Should -Contain 'Timestamp'
        }

        It 'Should have Timestamp in ISO 8601 format' {
            $result = Get-PublicIPAddress
            { [datetimeoffset]::Parse($result.Timestamp) } | Should -Not -Throw
        }
    }

    Context 'Integration' -Tag 'Integration' {

        It 'Should return a valid public IPv4 address' {
            $result = Get-PublicIPAddress
            $result.IPv4Address | Should -Match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
        }
    }
}
