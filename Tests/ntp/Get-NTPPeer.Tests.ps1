#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester v5 tests for the Get-NTPPeer function

.DESCRIPTION
    Comprehensive test coverage for Get-NTPPeer including happy path with English
    and French locale output, zero peers, pipeline input, per-machine failure
    isolation, parameter validation, and property type assertions.

    All external calls (Invoke-Command) are mocked. No real network or w32tm
    access is required.

.EXAMPLE
    Invoke-Pester -Path .\Get-NTPPeer.Tests.ps1 -Output Detailed

    Runs all tests with detailed output.

.EXAMPLE
    Invoke-Pester -Path .\Get-NTPPeer.Tests.ps1 -Output Detailed -Tag 'HappyPath'

    Runs only happy-path tests.

.NOTES
    Author:        Franck SALLET (k9fr4n)
    Version:       1.0.0
    Last Modified: 2026-03-12
    Requires:      Pester 5.x, PowerShell 5.1+
    Permissions:   None required (all external commands are mocked)
#>

BeforeAll {
    # Dot-source the function under test
    $script:functionPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Public\ntp\Get-NTPPeer.ps1'
    . $script:functionPath

    #region Mock data -- 2 peers (English)
    $script:mockTwoPeersEN = @(
        '#Peers: 2'
        ''
        'Peer: ntp1.example.com,0x8'
        'State: Active'
        'Time Remaining: 512.34s'
        'Last Successful Sync Time: 3/12/2026 8:00:00 PM'
        'Poll Interval: 10 (1024s)'
        ''
        'Peer: ntp2.example.com,0x8'
        'State: Pending'
        'Time Remaining: 1024.00s'
        'Last Successful Sync Time: 3/12/2026 7:30:00 PM'
        'Poll Interval: 10 (1024s)'
    )
    #endregion

    #region Mock data -- 0 peers
    $script:mockZeroPeers = @(
        '#Peers: 0'
    )
    #endregion

    #region Mock data -- 1 peer (French)
    $script:mockOnePeerFR = @(
        '#Homologues : 1'
        ''
        'Homologue : ntp-fr.pool.ntp.org,0x8'
        'Etat : Actif'
        'Temps restant : 256.12s'
        'Heure de la derniere synchronisation reussie : 12/03/2026 20:00:00'
        'Intervalle d''interrogation : 10 (1024s)'
    )
    #endregion
}

Describe -Name 'Get-NTPPeer' -Fixture {

    # -------------------------------------------------------------------
    # Context 1: Happy path -- local machine, 2 English peers
    # -------------------------------------------------------------------
    Context -Name 'Happy path - local machine with 2 English peers' -Tag 'HappyPath' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockTwoPeersEN
            }
        }

        It -Name 'Should return exactly 2 peer objects' -Test {
            $result = @(Get-NTPPeer)
            $result.Count | Should -Be 2
        }

        It -Name 'Should set ComputerName to the local machine name' -Test {
            $result = @(Get-NTPPeer)
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
            $result[1].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should return objects with all expected properties' -Test {
            $result = @(Get-NTPPeer)
            $expectedProps = @(
                'ComputerName', 'PeerName', 'PeerFlags', 'State',
                'TimeRemaining', 'LastSyncTime', 'PollInterval', 'Timestamp'
            )
            foreach ($prop in $expectedProps) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It -Name 'Should have PSTypeName PSWinOps.NTPPeer' -Test {
            $result = @(Get-NTPPeer)
            $result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.NTPPeer'
        }

        It -Name 'Should invoke Invoke-Command exactly once' -Test {
            Get-NTPPeer | Out-Null
            Should -Invoke -CommandName 'Invoke-Command' -Times 1 -Exactly
        }

        It -Name 'First peer should be ntp1.example.com with Active state' -Test {
            $result = @(Get-NTPPeer)
            $result[0].PeerName | Should -Be 'ntp1.example.com'
            $result[0].State | Should -Be 'Active'
        }

        It -Name 'Second peer should be ntp2.example.com with Pending state' -Test {
            $result = @(Get-NTPPeer)
            $result[1].PeerName | Should -Be 'ntp2.example.com'
            $result[1].State | Should -Be 'Pending'
        }
    }

    # -------------------------------------------------------------------
    # Context 2: Happy path -- remote machine
    # -------------------------------------------------------------------
    Context -Name 'Happy path - remote machine' -Tag 'HappyPath' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockTwoPeersEN
            } -ParameterFilter { $ComputerName -eq 'REMOTE01' }
        }

        It -Name 'Should set ComputerName to the remote machine name' -Test {
            $result = @(Get-NTPPeer -ComputerName 'REMOTE01')
            $result[0].ComputerName | Should -Be 'REMOTE01'
            $result[1].ComputerName | Should -Be 'REMOTE01'
        }

        It -Name 'Should invoke Invoke-Command with -ComputerName parameter' -Test {
            Get-NTPPeer -ComputerName 'REMOTE01' | Out-Null
            Should -Invoke -CommandName 'Invoke-Command' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'REMOTE01'
            }
        }
    }

    # -------------------------------------------------------------------
    # Context 3: Pipeline input -- multiple machines
    # -------------------------------------------------------------------
    Context -Name 'Pipeline input - multiple machines' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockTwoPeersEN
            }
        }

        It -Name 'Should return peers for each machine in the pipeline' -Test {
            $result = @('ALPHA', 'BRAVO' | Get-NTPPeer)
            $result.Count | Should -Be 4
        }

        It -Name 'Should contain correct ComputerName values from pipeline' -Test {
            $result = @('ALPHA', 'BRAVO' | Get-NTPPeer)
            ($result | Where-Object { $_.ComputerName -eq 'ALPHA' }).Count | Should -Be 2
            ($result | Where-Object { $_.ComputerName -eq 'BRAVO' }).Count | Should -Be 2
        }

        It -Name 'Should invoke Invoke-Command once per machine' -Test {
            'ALPHA', 'BRAVO' | Get-NTPPeer | Out-Null
            Should -Invoke -CommandName 'Invoke-Command' -Times 2 -Exactly
        }
    }

    # -------------------------------------------------------------------
    # Context 4: Zero peers configured
    # -------------------------------------------------------------------
    Context -Name 'Zero peers configured' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockZeroPeers
            }
        }

        It -Name 'Should not emit any objects' -Test {
            $result = @(Get-NTPPeer -ComputerName $env:COMPUTERNAME)
            $result.Count | Should -Be 0
        }

        It -Name 'Should emit a warning about no peers' -Test {
            Get-NTPPeer -ComputerName $env:COMPUTERNAME -WarningVariable 'warnMsg' -WarningAction SilentlyContinue | Out-Null
            $warnMsg | Should -Not -BeNullOrEmpty
            $warnMsg[0] | Should -Match 'No NTP peers configured'
        }
    }

    # -------------------------------------------------------------------
    # Context 5: French locale output
    # -------------------------------------------------------------------
    Context -Name 'French locale output - 1 peer' -Tag 'Locale' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOnePeerFR
            }
        }

        It -Name 'Should return exactly 1 peer object' -Test {
            $result = @(Get-NTPPeer)
            $result.Count | Should -Be 1
        }

        It -Name 'Should parse PeerName correctly from French output' -Test {
            $result = @(Get-NTPPeer)
            $result[0].PeerName | Should -Be 'ntp-fr.pool.ntp.org'
        }

        It -Name 'Should parse PeerFlags correctly from French output' -Test {
            $result = @(Get-NTPPeer)
            $result[0].PeerFlags | Should -Be '0x8'
        }

        It -Name 'Should parse State from French output' -Test {
            $result = @(Get-NTPPeer)
            $result[0].State | Should -Be 'Actif'
        }

        It -Name 'Should parse TimeRemaining as double from French output' -Test {
            $result = @(Get-NTPPeer)
            $result[0].TimeRemaining | Should -Be 256.12
        }

        It -Name 'Should parse PollInterval as int from French output' -Test {
            $result = @(Get-NTPPeer)
            $result[0].PollInterval | Should -Be 10
        }
    }

    # -------------------------------------------------------------------
    # Context 6: Per-machine failure isolation
    # -------------------------------------------------------------------
    Context -Name 'Per-machine failure isolation' -Fixture {

        BeforeAll {
            # Default mock returns data for any call (covers local path)
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockTwoPeersEN
            }

            # Specific mock for BADSERVER throws
            Mock -CommandName 'Invoke-Command' -MockWith {
                throw 'Connection refused'
            } -ParameterFilter { $ComputerName -eq 'BADSERVER' }
        }

        It -Name 'Should return peers for the good machine despite bad machine error' -Test {
            $result = @(Get-NTPPeer -ComputerName 'BADSERVER', $env:COMPUTERNAME -ErrorAction SilentlyContinue)
            $result.Count | Should -Be 2
        }

        It -Name 'Should write a non-terminating error for the bad machine' -Test {
            $result = @(Get-NTPPeer -ComputerName 'BADSERVER', $env:COMPUTERNAME -ErrorVariable 'errVar' -ErrorAction SilentlyContinue)
            $errVar | Should -Not -BeNullOrEmpty
            $errVar[0].ToString() | Should -Match 'BADSERVER'
            $result.Count | Should -Be 2
        }

        It -Name 'Should continue processing after the failed machine' -Test {
            Get-NTPPeer -ComputerName 'BADSERVER', $env:COMPUTERNAME -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -CommandName 'Invoke-Command' -Times 2 -Exactly
        }
    }

    # -------------------------------------------------------------------
    # Context 7: Parameter validation
    # -------------------------------------------------------------------
    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw on empty string ComputerName' -Test {
            { Get-NTPPeer -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw on null ComputerName' -Test {
            { Get-NTPPeer -ComputerName $null } | Should -Throw
        }

        It -Name 'Should throw on empty array element' -Test {
            { Get-NTPPeer -ComputerName @('') } | Should -Throw
        }
    }

    # -------------------------------------------------------------------
    # Context 8: Peer properties validation
    # -------------------------------------------------------------------
    Context -Name 'Peer properties type and value validation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockTwoPeersEN
            }
        }

        It -Name 'PeerName should have flags stripped (no comma or 0x)' -Test {
            $result = @(Get-NTPPeer)
            $result[0].PeerName | Should -Not -Match ',0x'
            $result[0].PeerName | Should -Be 'ntp1.example.com'
        }

        It -Name 'PeerFlags should contain the raw hex flag' -Test {
            $result = @(Get-NTPPeer)
            $result[0].PeerFlags | Should -Be '0x8'
        }

        It -Name 'TimeRemaining should be a double' -Test {
            $result = @(Get-NTPPeer)
            $result[0].TimeRemaining | Should -BeOfType ([double])
            $result[0].TimeRemaining | Should -Be 512.34
        }

        It -Name 'PollInterval should be an int' -Test {
            $result = @(Get-NTPPeer)
            $result[0].PollInterval | Should -BeOfType ([int])
            $result[0].PollInterval | Should -Be 10
        }

        It -Name 'LastSyncTime should not be null for valid data' -Test {
            $result = @(Get-NTPPeer)
            $result[0].LastSyncTime | Should -Not -BeNullOrEmpty
        }

        It -Name 'Timestamp should be a valid ISO 8601 string' -Test {
            $result = @(Get-NTPPeer)
            { [datetime]::Parse($result[0].Timestamp) } | Should -Not -Throw
        }

        It -Name 'State should be a non-empty string' -Test {
            $result = @(Get-NTPPeer)
            $result[0].State | Should -Not -BeNullOrEmpty
            $result[0].State | Should -BeOfType ([string])
        }
    }
}
