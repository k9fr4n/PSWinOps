#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Helper: pending stat record
    function script:NewPendingStat {
        @{ Sent = 0; Received = 0; Lost = 0; LastMs = -1; MinMs = [int]::MaxValue; MaxMs = 0; TotalMs = [long]0; Status = 'Pending' }
    }

    # Helper: up stat record with data
    function script:NewUpStat {
        param([int]$Last = 20, [int]$Min = 10, [int]$Max = 30, [int]$Sent = 10, [int]$Recv = 10)
        $lost = $Sent - $Recv
        @{ Sent = $Sent; Received = $Recv; Lost = $lost; LastMs = $Last; MinMs = $Min; MaxMs = $Max; TotalMs = [long]($Last * $Recv); Status = 'Up' }
    }
}

Describe -Name 'Format-PingMonitorFrame' -Fixture {

    Context -Name 'Output type' -Fixture {

        It -Name 'Should return exactly one string value' -Test {
            $stats = @{ 'h1' = (script:NewPendingStat) }
            $result = & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('h1') -MaxHostLen 4 -SortMode 'Host' -Paused $false -ElapsedStr '00:00:00' -NoColor
            } $stats
            @($result).Count | Should -Be 1
            $result           | Should -BeOfType [string]
        }

        It -Name 'Should not return null or empty' -Test {
            $stats = @{ 'h1' = (script:NewPendingStat) }
            $result = & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('h1') -MaxHostLen 4 -SortMode 'Host' -Paused $false -ElapsedStr '00:00:00' -NoColor
            } $stats
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Empty / pending state' -Fixture {

        BeforeAll {
            $script:stats = @{ 'host1' = (script:NewPendingStat) }
            $script:frame = & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('host1') -MaxHostLen 5 -SortMode 'Host' -Paused $false -ElapsedStr '00:00:01' -NoColor
            } $script:stats
        }

        It -Name 'Should contain monitor title' -Test {
            $script:frame | Should -Match '=== PING MONITOR ==='
        }

        It -Name 'Should contain HOST column header' -Test {
            $script:frame | Should -Match 'HOST'
        }

        It -Name 'Should show dashes for uninitialised LastMs (-1)' -Test {
            $script:frame | Should -Match '--'
        }

        It -Name 'Should report 0 Up, 0 Down, 1 Pending' -Test {
            $script:frame | Should -Match '0 Up'
            $script:frame | Should -Match '0 Down'
            $script:frame | Should -Match '1 Pending'
        }

        It -Name 'Should contain the elapsed time' -Test {
            $script:frame | Should -Match '00:00:01'
        }
    }

    Context -Name 'Full state (Up + Down hosts)' -Fixture {

        BeforeAll {
            $script:stats = @{
                'server1' = (script:NewUpStat -Last 15 -Min 10 -Max 30 -Sent 10 -Recv 9)
                'server2' = @{ Sent = 10; Received = 0; Lost = 10; LastMs = -1; MinMs = [int]::MaxValue; MaxMs = 0; TotalMs = [long]0; Status = 'Down' }
            }
            $script:frame = & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('server1','server2') -MaxHostLen 7 -SortMode 'Host' -Paused $false -ElapsedStr '00:01:30' -RefreshInterval 2 -NoColor
            } $script:stats
        }

        It -Name 'Should contain both hostnames' -Test {
            $script:frame | Should -Match 'server1'
            $script:frame | Should -Match 'server2'
        }

        It -Name 'Should show Up status' -Test {
            $script:frame | Should -Match '\bUp\b'
        }

        It -Name 'Should show Down status' -Test {
            $script:frame | Should -Match '\bDown\b'
        }

        It -Name 'Should show last RTT for server1' -Test {
            $script:frame | Should -Match '\b15\b'
        }

        It -Name 'Should show loss percentage for server2 (100.0%)' -Test {
            $script:frame | Should -Match '100\.0%'
        }

        It -Name 'Should show elapsed time in footer' -Test {
            $script:frame | Should -Match '00:01:30'
        }
    }

    Context -Name 'Paused indicator' -Fixture {

        It -Name 'Should show PAUSED when paused = true' -Test {
            $stats = @{ 'h' = (script:NewPendingStat) }
            $frame = & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('h') -MaxHostLen 4 -SortMode 'Host' -Paused $true -ElapsedStr '00:00:00' -NoColor
            } $stats
            $frame | Should -Match 'PAUSED'
        }

        It -Name 'Should NOT show PAUSED when paused = false' -Test {
            $stats = @{ 'h' = (script:NewPendingStat) }
            $frame = & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('h') -MaxHostLen 4 -SortMode 'Host' -Paused $false -ElapsedStr '00:00:00' -NoColor
            } $stats
            $frame | Should -Not -Match 'PAUSED'
        }
    }

    Context -Name 'Edge values' -Fixture {

        It -Name 'Should not throw when MaxHostLen is very large' -Test {
            $stats = @{ 'h' = (script:NewUpStat) }
            { & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('h') -MaxHostLen 300 -SortMode 'Host' -Paused $false -ElapsedStr '00:00:00' -TerminalHeight 10 -NoColor
            } $stats } | Should -Not -Throw
        }

        It -Name 'Should not divide by zero when Sent = 0 in Loss sort' -Test {
            $stats = @{ 'h' = (script:NewPendingStat) }
            { & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('h') -MaxHostLen 4 -SortMode 'Loss' -Paused $false -ElapsedStr '00:00:00' -NoColor
            } $stats } | Should -Not -Throw
        }

        It -Name 'Should not throw when TerminalHeight is smaller than frame' -Test {
            $stats = @{ 'h' = (script:NewUpStat) }
            { & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('h') -MaxHostLen 4 -SortMode 'Host' -Paused $false -ElapsedStr '00:00:00' -TerminalHeight 1 -NoColor
            } $stats } | Should -Not -Throw
        }

        It -Name 'Should show 100.0% loss for fully dropped host' -Test {
            $stats = @{ 'bad' = @{ Sent = 5; Received = 0; Lost = 5; LastMs = -1; MinMs = [int]::MaxValue; MaxMs = 0; TotalMs = [long]0; Status = 'Down' } }
            $frame = & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('bad') -MaxHostLen 3 -SortMode 'Host' -Paused $false -ElapsedStr '00:00:00' -NoColor
            } $stats
            $frame | Should -Match '100\.0%'
        }

        It -Name 'Should show 0.0% loss for perfectly responding host' -Test {
            $stats = @{ 'ok' = (script:NewUpStat -Sent 10 -Recv 10) }
            $frame = & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('ok') -MaxHostLen 2 -SortMode 'Host' -Paused $false -ElapsedStr '00:00:00' -NoColor
            } $stats
            $frame | Should -Match '0\.0%'
        }
    }

    Context -Name 'Sort modes do not throw' -Fixture {

        BeforeAll {
            $script:stats = @{
                'aaa' = (script:NewUpStat -Last 100 -Sent 5 -Recv 5)
                'bbb' = (script:NewUpStat -Last 20  -Sent 5 -Recv 3)
            }
        }

        It -Name 'Should not throw for SortMode Host' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('aaa','bbb') -MaxHostLen 3 -SortMode 'Host' -Paused $false -ElapsedStr '00:00:01' -NoColor
            } $script:stats } | Should -Not -Throw
        }

        It -Name 'Should not throw for SortMode Status' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('aaa','bbb') -MaxHostLen 3 -SortMode 'Status' -Paused $false -ElapsedStr '00:00:01' -NoColor
            } $script:stats } | Should -Not -Throw
        }

        It -Name 'Should not throw for SortMode LastMs' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('aaa','bbb') -MaxHostLen 3 -SortMode 'LastMs' -Paused $false -ElapsedStr '00:00:01' -NoColor
            } $script:stats } | Should -Not -Throw
        }

        It -Name 'Should not throw for SortMode Loss' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                param($s)
                Format-PingMonitorFrame -StatsTable $s -HostList @('aaa','bbb') -MaxHostLen 3 -SortMode 'Loss' -Paused $false -ElapsedStr '00:00:01' -NoColor
            } $script:stats } | Should -Not -Throw
        }
    }
}
