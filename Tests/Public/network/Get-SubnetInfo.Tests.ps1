BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-SubnetInfo' {

    Context 'CIDR notation input' {

        It 'Should calculate /24 subnet correctly' {
            $result = Get-SubnetInfo -IPAddress '192.168.1.0/24'
            $result.NetworkAddress | Should -Be '192.168.1.0'
            $result.BroadcastAddress | Should -Be '192.168.1.255'
            $result.SubnetMask | Should -Be '255.255.255.0'
            $result.FirstUsableHost | Should -Be '192.168.1.1'
            $result.LastUsableHost | Should -Be '192.168.1.254'
            $result.UsableHosts | Should -Be 254
            $result.TotalHosts | Should -Be 256
            $result.PrefixLength | Should -Be 24
        }

        It 'Should calculate /16 subnet correctly' {
            $result = Get-SubnetInfo -IPAddress '10.0.0.0/16'
            $result.NetworkAddress | Should -Be '10.0.0.0'
            $result.BroadcastAddress | Should -Be '10.0.255.255'
            $result.SubnetMask | Should -Be '255.255.0.0'
            $result.UsableHosts | Should -Be 65534
        }

        It 'Should calculate /8 subnet correctly' {
            $result = Get-SubnetInfo -IPAddress '10.0.0.0/8'
            $result.NetworkAddress | Should -Be '10.0.0.0'
            $result.BroadcastAddress | Should -Be '10.255.255.255'
            $result.SubnetMask | Should -Be '255.0.0.0'
            $result.UsableHosts | Should -Be 16777214
        }

        It 'Should handle host IP within subnet (not network address)' {
            $result = Get-SubnetInfo -IPAddress '192.168.1.100/24'
            $result.NetworkAddress | Should -Be '192.168.1.0'
            $result.IPAddress | Should -Be '192.168.1.100'
        }

        It 'Should include PSTypeName PSWinOps.SubnetInfo' {
            $result = Get-SubnetInfo -IPAddress '192.168.1.0/24'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.SubnetInfo'
        }

        It 'Should include CIDR string' {
            $result = Get-SubnetInfo -IPAddress '192.168.1.0/24'
            $result.CIDR | Should -Be '192.168.1.0/24'
        }

        It 'Should include WildcardMask' {
            $result = Get-SubnetInfo -IPAddress '192.168.1.0/24'
            $result.WildcardMask | Should -Be '0.0.0.255'
        }

        It 'Should include Timestamp' {
            $result = Get-SubnetInfo -IPAddress '10.0.0.0/8'
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'PrefixLength parameter' {

        It 'Should accept -PrefixLength instead of CIDR' {
            $result = Get-SubnetInfo -IPAddress '172.16.0.0' -PrefixLength 12
            $result.NetworkAddress | Should -Be '172.16.0.0'
            $result.BroadcastAddress | Should -Be '172.31.255.255'
            $result.SubnetMask | Should -Be '255.240.0.0'
        }
    }

    Context 'SubnetMask parameter' {

        It 'Should accept -SubnetMask dotted notation' {
            $result = Get-SubnetInfo -IPAddress '10.10.0.0' -SubnetMask '255.255.240.0'
            $result.PrefixLength | Should -Be 20
            $result.NetworkAddress | Should -Be '10.10.0.0'
            $result.BroadcastAddress | Should -Be '10.10.15.255'
        }
    }

    Context 'Edge cases' {

        It 'Should handle /32 (single host)' {
            $result = Get-SubnetInfo -IPAddress '10.0.0.1/32'
            $result.TotalHosts | Should -Be 1
            $result.UsableHosts | Should -Be 1
            $result.NetworkAddress | Should -Be '10.0.0.1'
            $result.BroadcastAddress | Should -Be '10.0.0.1'
        }

        It 'Should handle /31 (point-to-point RFC 3021)' {
            $result = Get-SubnetInfo -IPAddress '10.0.0.0/31'
            $result.TotalHosts | Should -Be 2
            $result.UsableHosts | Should -Be 2
        }

        It 'Should handle /0 (entire address space)' {
            $result = Get-SubnetInfo -IPAddress '0.0.0.0/0'
            $result.SubnetMask | Should -Be '0.0.0.0'
            $result.NetworkAddress | Should -Be '0.0.0.0'
            $result.BroadcastAddress | Should -Be '255.255.255.255'
        }
    }

    Context 'Pipeline input' {

        It 'Should accept multiple CIDRs via pipeline' {
            $result = '192.168.1.0/24', '10.0.0.0/8' | Get-SubnetInfo
            $result.Count | Should -Be 2
        }

        It 'Should accept pipeline input by property name' {
            $cmd = Get-Command -Name 'Get-SubnetInfo'
            $paramAttr = $cmd.Parameters['IPAddress'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute]
            }
            $paramAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }

        It 'Should accept objects with IPAddress property via pipeline' {
            $objects = @(
                [PSCustomObject]@{ IPAddress = '192.168.1.0/24' }
                [PSCustomObject]@{ IPAddress = '10.0.0.0/8' }
            )
            $result = $objects | Get-SubnetInfo
            $result.Count | Should -Be 2
        }
    }

    Context 'Error handling' {

        It 'Should error when no prefix length is provided and no CIDR notation' {
            $result = Get-SubnetInfo -IPAddress '192.168.1.0' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
        }

        It 'Should error on invalid IP address format' {
            $result = Get-SubnetInfo -IPAddress 'not-an-ip/24' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty IPAddress' {
            { Get-SubnetInfo -IPAddress '' } | Should -Throw
        }

        It 'Should reject PrefixLength above 32' {
            { Get-SubnetInfo -IPAddress '10.0.0.0' -PrefixLength 33 } | Should -Throw
        }

        It 'Should reject PrefixLength below 0' {
            { Get-SubnetInfo -IPAddress '10.0.0.0' -PrefixLength -1 } | Should -Throw
        }
    }

    Context 'Known subnet calculations (cross-check)' {

        It '/25 = 128 total, 126 usable' {
            $result = Get-SubnetInfo -IPAddress '192.168.1.0/25'
            $result.TotalHosts | Should -Be 128
            $result.UsableHosts | Should -Be 126
            $result.SubnetMask | Should -Be '255.255.255.128'
            $result.BroadcastAddress | Should -Be '192.168.1.127'
        }

        It '/30 = 4 total, 2 usable' {
            $result = Get-SubnetInfo -IPAddress '10.0.0.0/30'
            $result.TotalHosts | Should -Be 4
            $result.UsableHosts | Should -Be 2
            $result.FirstUsableHost | Should -Be '10.0.0.1'
            $result.LastUsableHost | Should -Be '10.0.0.2'
        }
    }
}
