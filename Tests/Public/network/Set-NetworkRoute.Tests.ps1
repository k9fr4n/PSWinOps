#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Set-NetworkRoute' {

    Context 'Parameter validation' {
        It 'Should have SupportsShouldProcess' {
            $cmd = Get-Command -Name 'Set-NetworkRoute'
            $meta = [System.Management.Automation.CommandMetadata]::new($cmd)
            $meta.SupportsShouldProcess | Should -BeTrue
        }

        It 'Should require DestinationPrefix parameter' {
            $cmd = Get-Command -Name 'Set-NetworkRoute'
            $cmd.Parameters['DestinationPrefix'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should require RouteMetric parameter' {
            $cmd = Get-Command -Name 'Set-NetworkRoute'
            $cmd.Parameters['RouteMetric'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should throw if neither InterfaceIndex nor InterfaceAlias is provided' {
            { Set-NetworkRoute -DestinationPrefix '10.0.0.0/8' -RouteMetric 100 -Confirm:$false } | Should -Throw '*InterfaceIndex or InterfaceAlias*'
        }

        It 'Should reject empty ComputerName' {
            { Set-NetworkRoute -ComputerName '' -DestinationPrefix '10.0.0.0/8' -RouteMetric 100 -InterfaceAlias 'Eth' } | Should -Throw
        }
    }

    Context 'Happy path - local machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-NetRoute' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetRoute' -MockWith {
                return [PSCustomObject]@{
                    DestinationPrefix = '10.10.0.0/16'
                    NextHop           = '192.168.1.1'
                    InterfaceAlias    = 'Ethernet'
                    InterfaceIndex    = 4
                    RouteMetric       = 50
                    AddressFamily     = 2
                    Protocol          = 'NetMgmt'
                    Store             = 'ActiveStore'
                }
            }
        }

        It 'Should return PSWinOps.NetworkRoute object' {
            $result = Set-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:$false
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.NetworkRoute'
        }

        It 'Should call Set-NetRoute' {
            $null = Set-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:$false
            Should -Invoke -CommandName 'Set-NetRoute' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should respect -WhatIf and not call Set-NetRoute' {
            $null = Set-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -WhatIf
            Should -Invoke -CommandName 'Set-NetRoute' -ModuleName $script:ModuleName -Times 0 -Exactly
        }

        It 'Should include ComputerName and Timestamp' {
            $result = Set-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:$false
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Happy path - explicit remote machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return [PSCustomObject]@{
                    DestinationPrefix = '10.10.0.0/16'
                    NextHop           = '192.168.1.1'
                    InterfaceAlias    = 'Ethernet'
                    InterfaceIndex    = 4
                    RouteMetric       = 50
                    AddressFamily     = 'IPv4'
                    Protocol          = 'NetMgmt'
                    Store             = 'ActiveStore'
                }
            }
        }

        It 'Should use Invoke-Command for remote machine' {
            $null = Set-NetworkRoute -ComputerName 'REMOTESRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Pipeline - multiple machine names' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                return [PSCustomObject]@{
                    DestinationPrefix = '10.10.0.0/16'
                    NextHop           = '192.168.1.1'
                    InterfaceAlias    = 'Ethernet'
                    InterfaceIndex    = 4
                    RouteMetric       = 50
                    AddressFamily     = 'IPv4'
                    Protocol          = 'NetMgmt'
                    Store             = 'ActiveStore'
                }
            }
        }

        It 'Should accept multiple computers via pipeline' {
            $null = 'REMOTE01', 'REMOTE02' | Set-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure - continues and writes error' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                throw 'Access denied'
            }
        }

        It 'Should write error for failed machine but not throw' {
            $results = Set-NetworkRoute -ComputerName 'BADSRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like "*Failed on 'BADSRV01'*") | Should -Not -BeNullOrEmpty
        }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'Verbose output' {
        BeforeAll {
            Mock -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -MockWith { return @() }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Set-NetworkRoute -ComputerName 'SRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:$false -Verbose -ErrorAction SilentlyContinue 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Set-NetworkRoute -ComputerName 'SRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:$false -Verbose -ErrorAction SilentlyContinue 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Set-NetworkRoute'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Set-NetworkRoute' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Set-NetworkRoute' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Set-NetworkRoute' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -MockWith {
                return [PSCustomObject]@{
                    DestinationPrefix = '10.10.0.0/16'; NextHop = '192.168.1.1'
                    InterfaceAlias = 'Ethernet'; InterfaceIndex = 4; RouteMetric = 50
                    AddressFamily = 'IPv4'; Protocol = 'NetMgmt'; Store = 'ActiveStore'
                }
            }
            $script:propResult = Set-NetworkRoute -ComputerName 'SRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:\$false
            $script:propNames = $script:propResult.PSObject.Properties.Name
        }
        It 'Should have ComputerName property' { $script:propNames | Should -Contain 'ComputerName' }
        It 'Should have Timestamp property' { $script:propNames | Should -Contain 'Timestamp' }
        It 'Should contain all route properties' {
            $script:propNames | Should -Contain 'DestinationPrefix'
            $script:propNames | Should -Contain 'NextHop'
            $script:propNames | Should -Contain 'InterfaceAlias'
            $script:propNames | Should -Contain 'InterfaceIndex'
            $script:propNames | Should -Contain 'RouteMetric'
            $script:propNames | Should -Contain 'AddressFamily'
            $script:propNames | Should -Contain 'Protocol'
            $script:propNames | Should -Contain 'Store'
        }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -MockWith {
                return [PSCustomObject]@{
                    DestinationPrefix = '10.10.0.0/16'; NextHop = '192.168.1.1'
                    InterfaceAlias = 'Ethernet'; InterfaceIndex = 4; RouteMetric = 50
                    AddressFamily = 'IPv4'; Protocol = 'NetMgmt'; Store = 'ActiveStore'
                }
            }
            $script:tsResult = Set-NetworkRoute -ComputerName 'SRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -RouteMetric 50 -Confirm:\$false
        }
        It 'Should have Timestamp matching ISO 8601 pattern' { $script:tsResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'InterfaceIndex path' {
        BeforeAll {
            Mock -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -MockWith {
                return [PSCustomObject]@{
                    DestinationPrefix = '10.10.0.0/16'; NextHop = '192.168.1.1'
                    InterfaceAlias = 'Ethernet'; InterfaceIndex = 4; RouteMetric = 50
                    AddressFamily = 'IPv4'; Protocol = 'NetMgmt'; Store = 'ActiveStore'
                }
            }
        }
        It 'Should accept InterfaceIndex instead of InterfaceAlias' {
            $script:idxResult = Set-NetworkRoute -ComputerName 'SRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceIndex 4 -RouteMetric 50 -Confirm:\$false
            $script:idxResult | Should -Not -BeNullOrEmpty
        }
    }

    Context 'NextHop parameter' {
        BeforeAll {
            Mock -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -MockWith {
                return [PSCustomObject]@{
                    DestinationPrefix = '10.10.0.0/16'; NextHop = '192.168.1.1'
                    InterfaceAlias = 'Ethernet'; InterfaceIndex = 4; RouteMetric = 50
                    AddressFamily = 'IPv4'; Protocol = 'NetMgmt'; Store = 'ActiveStore'
                }
            }
        }
        It 'Should accept optional NextHop parameter' {
            $script:nhResult = Set-NetworkRoute -ComputerName 'SRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -NextHop '192.168.1.1' -RouteMetric 50 -Confirm:\$false
            $script:nhResult | Should -Not -BeNullOrEmpty
        }
    }

    Context 'DNSHostName alias' {
        It 'Should accept DNSHostName alias for ComputerName' {
            $script:cmd = Get-Command -Name 'Set-NetworkRoute' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName'
        }
    }
}
