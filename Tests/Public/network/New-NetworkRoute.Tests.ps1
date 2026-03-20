#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'New-NetworkRoute' {

    Context 'Parameter validation' {
        It 'Should have SupportsShouldProcess' {
            $cmd = Get-Command -Name 'New-NetworkRoute'
            $cmd.CmdletBinding | Should -BeTrue
            $meta = [System.Management.Automation.CommandMetadata]::new($cmd)
            $meta.SupportsShouldProcess | Should -BeTrue
        }

        It 'Should have OutputType PSWinOps.NetworkRoute' {
            $cmd = Get-Command -Name 'New-NetworkRoute'
            $cmd.OutputType.Name | Should -Contain 'PSWinOps.NetworkRoute'
        }

        It 'Should require DestinationPrefix parameter' {
            $cmd = Get-Command -Name 'New-NetworkRoute'
            $cmd.Parameters['DestinationPrefix'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should require NextHop parameter' {
            $cmd = Get-Command -Name 'New-NetworkRoute'
            $cmd.Parameters['NextHop'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should throw if neither InterfaceIndex nor InterfaceAlias is provided' {
            { New-NetworkRoute -DestinationPrefix '10.0.0.0/8' -NextHop '192.168.1.1' -Confirm:$false } | Should -Throw '*InterfaceIndex or InterfaceAlias*'
        }

        It 'Should reject empty ComputerName' {
            { New-NetworkRoute -ComputerName '' -DestinationPrefix '10.0.0.0/8' -NextHop '1.1.1.1' -InterfaceAlias 'Eth' } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            { New-NetworkRoute -ComputerName $null -DestinationPrefix '10.0.0.0/8' -NextHop '1.1.1.1' -InterfaceAlias 'Eth' } | Should -Throw
        }
    }

    Context 'Happy path - local machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'New-NetRoute' -MockWith {
                return [PSCustomObject]@{
                    DestinationPrefix = '10.10.0.0/16'
                    NextHop           = '192.168.1.1'
                    InterfaceAlias    = 'Ethernet'
                    InterfaceIndex    = 4
                    RouteMetric       = 256
                    AddressFamily     = 2
                    Protocol          = 'NetMgmt'
                    Store             = 'ActiveStore'
                }
            }
        }

        It 'Should return PSWinOps.NetworkRoute object' {
            $result = New-NetworkRoute -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet' -Confirm:$false
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.NetworkRoute'
        }

        It 'Should include ComputerName and Timestamp' {
            $result = New-NetworkRoute -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet' -Confirm:$false
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should call New-NetRoute' {
            $null = New-NetworkRoute -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet' -Confirm:$false
            Should -Invoke -CommandName 'New-NetRoute' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should respect -WhatIf and not call New-NetRoute' {
            $null = New-NetworkRoute -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet' -WhatIf
            Should -Invoke -CommandName 'New-NetRoute' -ModuleName $script:ModuleName -Times 0 -Exactly
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
                    RouteMetric       = 256
                    AddressFamily     = 'IPv4'
                    Protocol          = 'NetMgmt'
                    Store             = 'ActiveStore'
                }
            }
        }

        It 'Should use Invoke-Command for remote machine' {
            $null = New-NetworkRoute -ComputerName 'REMOTESRV01' -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet' -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set ComputerName to the remote machine name' {
            $result = New-NetworkRoute -ComputerName 'REMOTESRV01' -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet' -Confirm:$false
            $result.ComputerName | Should -Be 'REMOTESRV01'
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
                    RouteMetric       = 256
                    AddressFamily     = 'IPv4'
                    Protocol          = 'NetMgmt'
                    Store             = 'ActiveStore'
                }
            }
        }

        It 'Should accept multiple computers via pipeline' {
            $null = 'REMOTE01', 'REMOTE02' | New-NetworkRoute -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet' -Confirm:$false
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
            $results = New-NetworkRoute -ComputerName 'BADSRV01' -DestinationPrefix '10.10.0.0/16' -NextHop '192.168.1.1' -InterfaceAlias 'Ethernet' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like "*Failed on 'BADSRV01'*") | Should -Not -BeNullOrEmpty
        }
    }
}
