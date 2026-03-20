#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-NetworkRoute' {

    Context 'Parameter validation' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command -Name 'Get-NetworkRoute'
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should have OutputType PSWinOps.NetworkRoute' {
            $cmd = Get-Command -Name 'Get-NetworkRoute'
            $cmd.OutputType.Name | Should -Contain 'PSWinOps.NetworkRoute'
        }

        It 'Should have ComputerName parameter with pipeline support' {
            $cmd = Get-Command -Name 'Get-NetworkRoute'
            $param = $cmd.Parameters['ComputerName']
            $param | Should -Not -BeNullOrEmpty
            $pAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pAttr.ValueFromPipeline | Should -BeTrue
            $pAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }

        It 'Should have AddressFamily parameter with ValidateSet IPv4/IPv6' {
            $cmd = Get-Command -Name 'Get-NetworkRoute'
            $param = $cmd.Parameters['AddressFamily']
            $param | Should -Not -BeNullOrEmpty
            $vs = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $vs.ValidValues | Should -Contain 'IPv4'
            $vs.ValidValues | Should -Contain 'IPv6'
        }

        It 'Should have Credential parameter of type PSCredential' {
            $cmd = Get-Command -Name 'Get-NetworkRoute'
            $param = $cmd.Parameters['Credential']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'PSCredential'
        }

        It 'Should reject invalid AddressFamily value' {
            { Get-NetworkRoute -AddressFamily 'IPX' } | Should -Throw
        }

        It 'Should reject empty ComputerName' {
            { Get-NetworkRoute -ComputerName '' } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            { Get-NetworkRoute -ComputerName $null } | Should -Throw
        }
    }

    Context 'Happy path - local machine' {
        BeforeAll {
            $script:mockRoutes = @(
                [PSCustomObject]@{
                    DestinationPrefix = '0.0.0.0/0'
                    NextHop           = '192.168.1.1'
                    InterfaceAlias    = 'Ethernet'
                    InterfaceIndex    = 4
                    RouteMetric       = 256
                    AddressFamily     = 2
                    Protocol          = 'NetMgmt'
                    Store             = 'ActiveStore'
                },
                [PSCustomObject]@{
                    DestinationPrefix = '10.0.0.0/8'
                    NextHop           = '192.168.1.254'
                    InterfaceAlias    = 'Ethernet'
                    InterfaceIndex    = 4
                    RouteMetric       = 100
                    AddressFamily     = 2
                    Protocol          = 'NetMgmt'
                    Store             = 'ActiveStore'
                }
            )

            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                return $script:mockRoutes
            }
        }

        It 'Should return objects with PSTypeName PSWinOps.NetworkRoute' {
            $results = Get-NetworkRoute
            $results | ForEach-Object {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.NetworkRoute'
            }
        }

        It 'Should return correct number of routes' {
            $results = Get-NetworkRoute
            $results | Should -HaveCount 2
        }

        It 'Should include ComputerName on each result' {
            $results = Get-NetworkRoute
            $results | ForEach-Object {
                $_.ComputerName | Should -Be $env:COMPUTERNAME
            }
        }

        It 'Should include Timestamp on each result' {
            $results = Get-NetworkRoute
            $results | ForEach-Object {
                $_.Timestamp | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should convert AddressFamily enum to human-readable string' {
            $results = Get-NetworkRoute
            $results | ForEach-Object {
                $_.AddressFamily | Should -Be 'IPv4'
            }
        }
    }

    Context 'Happy path - explicit remote machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return @(
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        NextHop           = '10.0.0.1'
                        InterfaceAlias    = 'Ethernet'
                        InterfaceIndex    = 3
                        RouteMetric       = 256
                        AddressFamily     = 'IPv4'
                        Protocol          = 'NetMgmt'
                        Store             = 'ActiveStore'
                    }
                )
            }
        }

        It 'Should use Invoke-Command for remote machine' {
            $null = Get-NetworkRoute -ComputerName 'REMOTESRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set ComputerName to the remote machine name' {
            $results = Get-NetworkRoute -ComputerName 'REMOTESRV01'
            $results[0].ComputerName | Should -Be 'REMOTESRV01'
        }
    }

    Context 'Pipeline - multiple machine names' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return @(
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        NextHop           = '10.0.0.1'
                        InterfaceAlias    = 'Ethernet'
                        InterfaceIndex    = 3
                        RouteMetric       = 256
                        AddressFamily     = 'IPv4'
                        Protocol          = 'NetMgmt'
                        Store             = 'ActiveStore'
                    }
                )
            }
        }

        It 'Should accept multiple computers via pipeline' {
            $null = 'REMOTE01', 'REMOTE02' | Get-NetworkRoute
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should return results from each machine' {
            $results = 'REMOTE01', 'REMOTE02' | Get-NetworkRoute
            $results | Should -HaveCount 2
            ($results | Where-Object { $_.ComputerName -eq 'REMOTE01' }) | Should -Not -BeNullOrEmpty
            ($results | Where-Object { $_.ComputerName -eq 'REMOTE02' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Per-machine failure - continues and writes error' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                throw 'WinRM connection failed'
            }
        }

        It 'Should write error for failed machine but not throw' {
            $results = Get-NetworkRoute -ComputerName 'BADSRV01' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like "*Failed on 'BADSRV01'*") | Should -Not -BeNullOrEmpty
        }

        It 'Should continue processing remaining machines after failure' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                param($ComputerName)
                if ($ComputerName -eq 'BADSRV') {
                    throw 'Connection refused'
                }
                return @(
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'; NextHop = '10.0.0.1'
                        InterfaceAlias = 'Ethernet'; InterfaceIndex = 3
                        RouteMetric = 256; AddressFamily = 'IPv4'
                        Protocol = 'NetMgmt'; Store = 'ActiveStore'
                    }
                )
            }

            $results = Get-NetworkRoute -ComputerName 'BADSRV', 'GOODSRV' -ErrorAction SilentlyContinue
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Filtering - DestinationPrefix wildcard' {
        BeforeAll {
            $script:mockRoutes = @(
                [PSCustomObject]@{
                    DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'
                    InterfaceAlias = 'Ethernet'; InterfaceIndex = 4
                    RouteMetric = 256; AddressFamily = 2
                    Protocol = 'NetMgmt'; Store = 'ActiveStore'
                },
                [PSCustomObject]@{
                    DestinationPrefix = '10.0.0.0/8'; NextHop = '192.168.1.254'
                    InterfaceAlias = 'Ethernet'; InterfaceIndex = 4
                    RouteMetric = 100; AddressFamily = 2
                    Protocol = 'NetMgmt'; Store = 'ActiveStore'
                }
            )

            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                return $script:mockRoutes
            }
        }

        It 'Should filter by DestinationPrefix' {
            $results = Get-NetworkRoute -DestinationPrefix '10.*'
            $results | Should -HaveCount 1
            $results[0].DestinationPrefix | Should -Be '10.0.0.0/8'
        }
    }

    Context 'Output object shape' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                return @(
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'
                        InterfaceAlias = 'Ethernet'; InterfaceIndex = 4
                        RouteMetric = 256; AddressFamily = 2
                        Protocol = 'NetMgmt'; Store = 'ActiveStore'
                    }
                )
            }
        }

        It 'Should have all expected properties' {
            $result = Get-NetworkRoute | Select-Object -First 1
            $expectedProperties = @('ComputerName', 'DestinationPrefix', 'NextHop',
                'InterfaceAlias', 'InterfaceIndex', 'RouteMetric',
                'AddressFamily', 'Protocol', 'Store', 'Timestamp')
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }

    Context 'Integration' -Tag 'Integration' {
        It 'Should return real routes on a Windows machine' -Skip:(-not ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')) {
            $results = Get-NetworkRoute -AddressFamily IPv4
            $results | Should -Not -BeNullOrEmpty
            $results[0].AddressFamily | Should -Be 'IPv4'
        }
    }
}
