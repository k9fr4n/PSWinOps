#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Helper: build a synthetic connection object
    function script:NewConn {
        param(
            [string]$Protocol    = 'TCP',
            [string]$LocalAddr   = '192.168.1.10',
            [int]   $LocalPort   = 12345,
            [string]$RemoteAddr  = '93.184.216.34',
            [int]   $RemotePort  = 443,
            [string]$State       = 'Established',
            [string]$ProcessName = 'svchost'
        )
        [PSCustomObject]@{
            Protocol      = $Protocol
            LocalAddress  = $LocalAddr
            LocalPort     = $LocalPort
            RemoteAddress = $RemoteAddr
            RemotePort    = $RemotePort
            State         = $State
            ProcessName   = $ProcessName
        }
    }
}

Describe -Name 'Format-NetworkStatisticMonitorFrame' -Fixture {

    Context -Name 'Output type' -Fixture {

        It -Name 'Should return a single string' -Test {
            $result = & (Get-Module -Name 'PSWinOps') {
                Format-NetworkStatisticMonitorFrame -SortedConnections @() -ComputerList 'localhost' -CurrentSortMode 'Process' -TimeStr '2026-01-01 00:00:00' -NoColor
            }
            @($result).Count | Should -Be 1
            $result           | Should -BeOfType [string]
        }
    }

    Context -Name 'Empty state (no connections)' -Fixture {

        BeforeAll {
            $script:frame = & (Get-Module -Name 'PSWinOps') {
                Format-NetworkStatisticMonitorFrame -SortedConnections @() -ComputerList 'SRV01' -CurrentSortMode 'Process' -TimeStr '2026-05-14 20:00:00' -Width 120 -Height 30 -NoColor
            }
        }

        It -Name 'Should contain monitor title' -Test {
            $script:frame | Should -Match 'Network Monitor'
        }

        It -Name 'Should contain the computer name' -Test {
            $script:frame | Should -Match 'SRV01'
        }

        It -Name 'Should show no connections message' -Test {
            $script:frame | Should -Match 'No matching connections found'
        }

        It -Name 'Should contain column headers' -Test {
            $script:frame | Should -Match 'PROTO'
            $script:frame | Should -Match 'STATE'
        }

        It -Name 'Should show Connections: 0 in footer' -Test {
            $script:frame | Should -Match 'Connections:.*0'
        }
    }

    Context -Name 'Full state (multiple connections)' -Fixture {

        BeforeAll {
            $script:conns = @(
                (script:NewConn -Protocol 'TCP' -State 'Established' -ProcessName 'chrome' -LocalPort 54321 -RemotePort 443),
                (script:NewConn -Protocol 'TCP' -State 'Listen'      -ProcessName 'svchost' -LocalPort 445 -RemotePort 0),
                (script:NewConn -Protocol 'UDP' -State ''            -ProcessName 'dns'    -LocalPort 53  -RemotePort 0)
            )
            $script:frame = & (Get-Module -Name 'PSWinOps') {
                param($c)
                Format-NetworkStatisticMonitorFrame -SortedConnections $c -ComputerList 'SRV01' -CurrentSortMode 'Process' -TimeStr '2026-05-14 20:00:00' -Width 120 -Height 40 -NoColor
            } $script:conns
        }

        It -Name 'Should contain all process names' -Test {
            $script:frame | Should -Match 'chrome'
            $script:frame | Should -Match 'svchost'
            $script:frame | Should -Match 'dns'
        }

        It -Name 'Should contain TCP and UDP protocols' -Test {
            $script:frame | Should -Match 'TCP'
            $script:frame | Should -Match 'UDP'
        }

        It -Name 'Should show Established state' -Test {
            $script:frame | Should -Match 'Established'
        }

        It -Name 'Should show connection count in footer' -Test {
            $script:frame | Should -Match 'Connections:.*3'
        }

        It -Name 'Should contain timestamp' -Test {
            $script:frame | Should -Match '2026-05-14 20:00:00'
        }
    }

    Context -Name 'Paused indicator' -Fixture {

        It -Name 'Should show PAUSED when paused = true' -Test {
            $frame = & (Get-Module -Name 'PSWinOps') {
                Format-NetworkStatisticMonitorFrame -SortedConnections @() -ComputerList 'host' -CurrentSortMode 'Process' -Paused $true -TimeStr '2026-01-01 00:00:00' -NoColor
            }
            $frame | Should -Match 'PAUSED'
        }

        It -Name 'Should NOT show PAUSED when paused = false' -Test {
            $frame = & (Get-Module -Name 'PSWinOps') {
                Format-NetworkStatisticMonitorFrame -SortedConnections @() -ComputerList 'host' -CurrentSortMode 'Process' -Paused $false -TimeStr '2026-01-01 00:00:00' -NoColor
            }
            $frame | Should -Not -Match 'PAUSED'
        }
    }

    Context -Name 'Sort direction indicator' -Fixture {

        It -Name 'Should show ascending arrow (^) by default' -Test {
            $frame = & (Get-Module -Name 'PSWinOps') {
                Format-NetworkStatisticMonitorFrame -SortedConnections @() -ComputerList 'h' -CurrentSortMode 'Process' -SortDescending $false -TimeStr '2026-01-01 00:00:00' -NoColor
            }
            $frame | Should -Match '\^'
        }

        It -Name 'Should show descending arrow (v) when SortDescending = true' -Test {
            $frame = & (Get-Module -Name 'PSWinOps') {
                Format-NetworkStatisticMonitorFrame -SortedConnections @() -ComputerList 'h' -CurrentSortMode 'Process' -SortDescending $true -TimeStr '2026-01-01 00:00:00' -NoColor
            }
            $frame | Should -Match ' v'
        }
    }

    Context -Name 'Edge values' -Fixture {

        It -Name 'Should not throw with null SortedConnections' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                Format-NetworkStatisticMonitorFrame -SortedConnections $null -ComputerList 'h' -CurrentSortMode 'Process' -TimeStr '2026-01-01 00:00:00' -NoColor
            } } | Should -Not -Throw
        }

        It -Name 'Should not throw when Width is very small' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                Format-NetworkStatisticMonitorFrame -SortedConnections @() -ComputerList 'h' -CurrentSortMode 'Process' -TimeStr '2026-01-01 00:00:00' -Width 10 -Height 5 -NoColor
            } } | Should -Not -Throw
        }

        It -Name 'Should not throw when Height is very small' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                Format-NetworkStatisticMonitorFrame -SortedConnections @() -ComputerList 'h' -CurrentSortMode 'State' -TimeStr '2026-01-01 00:00:00' -Width 80 -Height 1 -NoColor
            } } | Should -Not -Throw
        }

        It -Name 'Should handle connection with empty ProcessName' -Test {
            $conn = [PSCustomObject]@{ Protocol='TCP'; LocalAddress='0.0.0.0'; LocalPort=0; RemoteAddress='0.0.0.0'; RemotePort=0; State='Listen'; ProcessName='' }
            { & (Get-Module -Name 'PSWinOps') {
                param($c)
                Format-NetworkStatisticMonitorFrame -SortedConnections @($c) -ComputerList 'h' -CurrentSortMode 'Process' -TimeStr '2026-01-01 00:00:00' -Width 120 -Height 30 -NoColor
            } $conn } | Should -Not -Throw
        }
    }

    Context -Name 'All sort modes do not throw' -Fixture {

        BeforeAll {
            $script:oneConn = @( (script:NewConn) )
        }

        It -Name 'Should not throw for CurrentSortMode Process' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                param($c)
                Format-NetworkStatisticMonitorFrame -SortedConnections $c -ComputerList 'h' -CurrentSortMode 'Process' -TimeStr '2026-01-01 00:00:00' -NoColor
            } $script:oneConn } | Should -Not -Throw
        }

        It -Name 'Should not throw for CurrentSortMode Protocol' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                param($c)
                Format-NetworkStatisticMonitorFrame -SortedConnections $c -ComputerList 'h' -CurrentSortMode 'Protocol' -TimeStr '2026-01-01 00:00:00' -NoColor
            } $script:oneConn } | Should -Not -Throw
        }

        It -Name 'Should not throw for CurrentSortMode State' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                param($c)
                Format-NetworkStatisticMonitorFrame -SortedConnections $c -ComputerList 'h' -CurrentSortMode 'State' -TimeStr '2026-01-01 00:00:00' -NoColor
            } $script:oneConn } | Should -Not -Throw
        }

        It -Name 'Should not throw for CurrentSortMode LocalPort' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                param($c)
                Format-NetworkStatisticMonitorFrame -SortedConnections $c -ComputerList 'h' -CurrentSortMode 'LocalPort' -TimeStr '2026-01-01 00:00:00' -NoColor
            } $script:oneConn } | Should -Not -Throw
        }

        It -Name 'Should not throw for CurrentSortMode RemoteAddr' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                param($c)
                Format-NetworkStatisticMonitorFrame -SortedConnections $c -ComputerList 'h' -CurrentSortMode 'RemoteAddr' -TimeStr '2026-01-01 00:00:00' -NoColor
            } $script:oneConn } | Should -Not -Throw
        }
    }
}
