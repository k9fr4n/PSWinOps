#Requires -Version 5.1

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {

    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force

    # Real format (from the actual machine)
    $script:mockOutputReal = @(
        '#Peers: 2'
        ''
        'Peer: ntp1.example.com'
        'State: Active'
        'Time Remaining: 7.8917439s'
        'Mode: 1 (Symmetric Active)'
        'Stratum: 2 (secondary reference - syncd by (S)NTP)'
        'PeerPoll Interval: 7 (128s)'
        'HostPoll Interval: 8 (256s)'
        ''
        'Peer: ntp2.example.com'
        'State: Active'
        'Time Remaining: 7.8956880s'
        'Mode: 1 (Symmetric Active)'
        'Stratum: 2 (secondary reference - syncd by (S)NTP)'
        'PeerPoll Interval: 7 (128s)'
        'HostPoll Interval: 8 (256s)'
    )

    # Old format with flags
    $script:mockOutputOldFormat = @(
        '#Peers: 1'
        ''
        'Peer: time.windows.com,0x9'
        'State: Active'
        'Time Remaining: 123.456s'
        'Last Successful Sync Time: 3/12/2026 2:30:15 PM'
        'Poll Interval: 10 (1024s)'
    )

    # Zero peers
    $script:mockOutputZeroPeers = @(
        '#Peers: 0'
    )
}

Describe -Name 'Get-NTPPeer' -Fixture {

    Context -Name 'Real w32tm output format' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockOutputReal
            }
        }

        It -Name 'Should return 2 peer objects' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result.Count | Should -Be 2
        }

        It -Name 'Should parse first peer name correctly' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].PeerName | Should -Be 'ntp1.example.com'
        }

        It -Name 'Should parse second peer name correctly' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[1].PeerName | Should -Be 'ntp2.example.com'
        }

        It -Name 'Should parse State as Active' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].State | Should -Be 'Active'
        }

        It -Name 'Should parse TimeRemaining as double' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].TimeRemaining | Should -BeOfType [double]
            $result[0].TimeRemaining | Should -BeGreaterThan 7.89
            $result[0].TimeRemaining | Should -BeLessThan 7.90
        }

        It -Name 'Should parse Mode string' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].Mode | Should -Be '1 (Symmetric Active)'
        }

        It -Name 'Should parse Stratum string' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].Stratum | Should -BeLike '2 (secondary reference*'
        }

        It -Name 'Should parse PeerPollInterval as integer' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].PeerPollInterval | Should -Be 7
        }

        It -Name 'Should parse HostPollInterval as integer' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].HostPollInterval | Should -Be 8
        }

        It -Name 'Should set ComputerName on each object' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].ComputerName | Should -Be 'REMOTE01'
            $result[1].ComputerName | Should -Be 'REMOTE01'
        }

        It -Name 'Should set Timestamp in ISO 8601 format' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It -Name 'Should have null PeerFlags for modern format' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].PeerFlags | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Old format with 0xFlags' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockOutputOldFormat
            }
        }

        It -Name 'Should parse PeerFlags correctly' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].PeerFlags | Should -Be '0x9'
        }

        It -Name 'Should parse PeerName without flags' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result[0].PeerName | Should -Be 'time.windows.com'
        }
    }

    Context -Name 'Zero peers' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockOutputZeroPeers
            }
        }

        It -Name 'Should return no output' -Test {
            $result = Get-NTPPeer -ComputerName 'REMOTE01'
            $result | Should -BeNullOrEmpty
        }

        It -Name 'Should emit a warning' -Test {
            $warningOutput = Get-NTPPeer -ComputerName 'REMOTE01' 3>&1
            $warningText = ($warningOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warningText | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'w32tm failure' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                throw 'w32tm /query /peers failed (exit code 1): The service has not been started.'
            }
        }

        It -Name 'Should not throw to the caller' -Test {
            { Get-NTPPeer -ComputerName 'BADSERVER' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should produce an error record' -Test {
            $result = Get-NTPPeer -ComputerName 'BADSERVER' -ErrorVariable 'capturedError' -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $capturedError | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Multiple computers' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockOutputReal
            }
        }

        It -Name 'Should return 4 objects for 2 computers with 2 peers each' -Test {
            $result = Get-NTPPeer -ComputerName 'SRV01', 'SRV02'
            $result.Count | Should -Be 4
        }

        It -Name 'Should tag each object with the correct ComputerName' -Test {
            $result = Get-NTPPeer -ComputerName 'SRV01', 'SRV02'
            ($result | Where-Object { $_.ComputerName -eq 'SRV01' }).Count | Should -Be 2
            ($result | Where-Object { $_.ComputerName -eq 'SRV02' }).Count | Should -Be 2
        }
    }

    Context -Name 'Pipeline input' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockOutputReal
            }
        }

        It -Name 'Should accept pipeline input and return results' -Test {
            $result = 'SRV01', 'SRV02' | Get-NTPPeer
            $result.Count | Should -Be 4
        }

        It -Name 'Should preserve correct ComputerName from pipeline' -Test {
            $result = 'SRV01', 'SRV02' | Get-NTPPeer
            $result[0].ComputerName | Should -Be 'SRV01'
        }
    }

    Context -Name 'Per-machine error isolation' -Fixture {

        BeforeAll {
            $script:callIndex = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $script:callIndex++
                if ($script:callIndex -eq 1) {
                    throw 'Connection refused'
                }
                return $script:mockOutputReal
            }
        }

        It -Name 'Should return results from the succeeding machine despite first failure' -Test {
            $script:callIndex = 0
            $result = Get-NTPPeer -ComputerName 'FAIL01', 'OK01' -ErrorAction SilentlyContinue -ErrorVariable 'capturedError'
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].ComputerName | Should -Be 'OK01'
            $capturedError | Should -Not -BeNullOrEmpty
        }
    }
}
