#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester v5 tests for the Test-NTPSync function

.DESCRIPTION
    Comprehensive test coverage for Test-NTPSync, including:
    - Happy path local and remote scenarios
    - Pipeline input with multiple machines
    - Offset exceeding threshold (IsSynced = false)
    - Unsynced sources (Free-Running, Local CMOS Clock)
    - Per-machine failure isolation and error handling
    - Parameter validation (MaxOffsetMs bounds, empty ComputerName)
    - Custom MaxOffsetMs threshold behaviour

.EXAMPLE
    Invoke-Pester -Path .\Test-NTPSync.Tests.ps1 -Output Detailed

    Runs all tests with detailed output.

.EXAMPLE
    Invoke-Pester -Path .\Test-NTPSync.Tests.ps1 -Output Detailed -Tag 'Nominal'

    Runs only tests tagged as nominal scenarios.

.NOTES
    Author:        Ecritel IT Team
    Version:       1.0.0
    Last Modified: 2026-03-12
    Requires:      Pester 5.x, PowerShell 5.1+
    Permissions:   None required (all external calls are mocked)
#>

BeforeAll {
    # Dot-source the function under test
    $script:functionPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Public\ntp\Test-NTPSync.ps1'
    . $script:functionPath

    #region Mock data -- English locale, synced with small offset
    $script:mockOutputSynced = @(
        'Leap Indicator: 0(no warning)'
        'Stratum: 3 (secondary reference - syncd by (S)NTP)'
        'Precision: -23 (119.209ns per tick)'
        'Root Delay: 0.0312500s'
        'Root Dispersion: 0.0512345s'
        'ReferenceId: 0xC0A80101 (source IP: 192.168.1.1)'
        'Last Successful Sync Time: 3/12/2026 8:00:00 PM'
        'Source: ntp.example.com'
        'Poll Interval: 10 (1024s)'
        'Phase Offset: 0.0023456s'
    )
    #endregion

    #region Mock data -- high offset (2500ms, exceeds default 1000ms)
    $script:mockOutputHighOffset = @(
        'Leap Indicator: 0(no warning)'
        'Stratum: 3 (secondary reference - syncd by (S)NTP)'
        'Precision: -23 (119.209ns per tick)'
        'Root Delay: 0.0312500s'
        'Root Dispersion: 0.0512345s'
        'ReferenceId: 0xC0A80101 (source IP: 192.168.1.1)'
        'Last Successful Sync Time: 3/12/2026 8:00:00 PM'
        'Source: ntp.example.com'
        'Poll Interval: 10 (1024s)'
        'Phase Offset: 2.5000000s'
    )
    #endregion

    #region Mock data -- Free-Running System Clock source
    $script:mockOutputFreeRunning = @(
        'Leap Indicator: 0(no warning)'
        'Stratum: 0 (unspecified)'
        'Precision: -23 (119.209ns per tick)'
        'Root Delay: 0.0000000s'
        'Root Dispersion: 0.0000000s'
        'ReferenceId: 0x00000000 (unspecified)'
        'Last Successful Sync Time: 1/1/1601 12:00:00 AM'
        'Source: Free-Running System Clock'
        'Poll Interval: 10 (1024s)'
        'Phase Offset: 0.0000000s'
    )
    #endregion

    #region Mock data -- Local CMOS Clock source
    $script:mockOutputLocalCmos = @(
        'Leap Indicator: 0(no warning)'
        'Stratum: 1 (primary reference - syncd by radio clock)'
        'Precision: -23 (119.209ns per tick)'
        'Root Delay: 0.0000000s'
        'Root Dispersion: 0.0100000s'
        'ReferenceId: 0x4C4F434C (source name: LOCL)'
        'Last Successful Sync Time: 3/12/2026 7:00:00 PM'
        'Source: Local CMOS Clock'
        'Poll Interval: 6 (64s)'
        'Phase Offset: 0.0001000s'
    )
    #endregion
}

Describe -Name 'Test-NTPSync' -Fixture {

    # -------------------------------------------------------------------
    # Context 1: Happy path -- local machine, synced
    # -------------------------------------------------------------------
    Context -Name 'Happy path - local machine, synced' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOutputSynced
            }
        }

        It -Name 'Should return a PSCustomObject with IsSynced true' -Test {
            $result = Test-NTPSync
            $result | Should -BeOfType ([PSCustomObject])
            $result.IsSynced | Should -BeTrue
        }

        It -Name 'Should expose all expected properties' -Test {
            $result = Test-NTPSync
            $script:expectedProperties = @(
                'ComputerName', 'IsSynced', 'Source', 'Stratum',
                'OffsetMs', 'MaxOffsetMs', 'LastSyncTime',
                'LeapIndicator', 'PollInterval', 'Timestamp'
            )
            foreach ($prop in $script:expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It -Name 'Should parse Source correctly' -Test {
            $result = Test-NTPSync
            $result.Source | Should -Be 'ntp.example.com'
        }

        It -Name 'Should parse Stratum as integer equal to 3' -Test {
            $result = Test-NTPSync
            $result.Stratum | Should -BeOfType ([int])
            $result.Stratum | Should -Be 3
        }

        It -Name 'Should parse OffsetMs from Phase Offset line' -Test {
            $result = Test-NTPSync
            $result.OffsetMs | Should -BeGreaterThan 0
            $result.OffsetMs | Should -BeLessOrEqual 1000
        }

        It -Name 'Should parse LastSyncTime as datetime' -Test {
            $result = Test-NTPSync
            $result.LastSyncTime | Should -BeOfType ([datetime])
        }

        It -Name 'Should parse PollInterval as 10' -Test {
            $result = Test-NTPSync
            $result.PollInterval | Should -Be 10
        }

        It -Name 'Should default MaxOffsetMs to 1000' -Test {
            $result = Test-NTPSync
            $result.MaxOffsetMs | Should -Be 1000
        }

        It -Name 'Should have a valid ISO 8601 Timestamp' -Test {
            $result = Test-NTPSync
            { [datetime]::Parse($result.Timestamp) } | Should -Not -Throw
        }

        It -Name 'Should parse LeapIndicator' -Test {
            $result = Test-NTPSync
            $result.LeapIndicator | Should -Not -Be 'Unknown'
        }
    }

    # -------------------------------------------------------------------
    # Context 2: Happy path -- explicit remote machine name
    # -------------------------------------------------------------------
    Context -Name 'Happy path - explicit remote machine name' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOutputSynced
            }
        }

        It -Name 'Should return IsSynced true for remote machine' -Test {
            $result = Test-NTPSync -ComputerName 'REMOTE-DC01'
            $result.IsSynced | Should -BeTrue
            $result.ComputerName | Should -Be 'REMOTE-DC01'
        }

        It -Name 'Should call Invoke-Command with -ComputerName for remote target' -Test {
            Test-NTPSync -ComputerName 'REMOTE-DC01'
            Should -Invoke -CommandName 'Invoke-Command' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'REMOTE-DC01'
            }
        }
    }

    # -------------------------------------------------------------------
    # Context 3: Pipeline input -- multiple machine names
    # -------------------------------------------------------------------
    Context -Name 'Pipeline input - multiple machine names' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOutputSynced
            }
        }

        It -Name 'Should return one result per piped machine' -Test {
            $result = @('Server1', 'Server2', 'Server3') | Test-NTPSync
            $result | Should -HaveCount 3
        }

        It -Name 'Should preserve ComputerName for each result' -Test {
            $result = @('Server1', 'Server2') | Test-NTPSync
            $result[0].ComputerName | Should -Be 'Server1'
            $result[1].ComputerName | Should -Be 'Server2'
        }
    }

    # -------------------------------------------------------------------
    # Context 4: Not synced -- offset exceeds MaxOffsetMs
    # -------------------------------------------------------------------
    Context -Name 'Not synced - offset exceeds MaxOffsetMs' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOutputHighOffset
            }
        }

        It -Name 'Should return IsSynced false when offset exceeds threshold' -Test {
            $result = Test-NTPSync -ComputerName 'REMOTE-DC01'
            $result.IsSynced | Should -BeFalse
        }

        It -Name 'Should report OffsetMs greater than default MaxOffsetMs' -Test {
            $result = Test-NTPSync -ComputerName 'REMOTE-DC01'
            $result.OffsetMs | Should -BeGreaterThan 1000
        }
    }

    # -------------------------------------------------------------------
    # Context 5: Not synced -- Free-Running System Clock source
    # -------------------------------------------------------------------
    Context -Name 'Not synced - Free-Running System Clock source' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOutputFreeRunning
            }
        }

        It -Name 'Should return IsSynced false for Free-Running source' -Test {
            $result = Test-NTPSync -ComputerName 'STANDALONE01'
            $result.IsSynced | Should -BeFalse
        }

        It -Name 'Should report the Free-Running source name' -Test {
            $result = Test-NTPSync -ComputerName 'STANDALONE01'
            $result.Source | Should -Be 'Free-Running System Clock'
        }
    }

    # -------------------------------------------------------------------
    # Context 5b: Not synced -- Local CMOS Clock source
    # -------------------------------------------------------------------
    Context -Name 'Not synced - Local CMOS Clock source' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOutputLocalCmos
            }
        }

        It -Name 'Should return IsSynced false for Local CMOS Clock' -Test {
            $result = Test-NTPSync -ComputerName 'ISOLATED01'
            $result.IsSynced | Should -BeFalse
        }

        It -Name 'Should report the Local CMOS Clock source name' -Test {
            $result = Test-NTPSync -ComputerName 'ISOLATED01'
            $result.Source | Should -Be 'Local CMOS Clock'
        }
    }

    # -------------------------------------------------------------------
    # Context 6: Per-machine failure isolation
    # -------------------------------------------------------------------
    Context -Name 'Per-machine failure isolation' -Fixture {

        BeforeEach {
            # Default mock returns good data
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOutputSynced
            }

            # Override for the failing machine
            Mock -CommandName 'Invoke-Command' -MockWith {
                throw 'WinRM connection refused'
            } -ParameterFilter { $ComputerName -eq 'BADSERVER' }
        }

        It -Name 'Should return results for healthy machines and write error for failing one' -Test {
            $result = Test-NTPSync -ComputerName 'GOODSERVER', 'BADSERVER', 'OTHERSERVER' -ErrorAction SilentlyContinue -ErrorVariable capturedError
            $result | Should -HaveCount 2
            $capturedError | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should continue processing after a per-machine failure' -Test {
            $result = Test-NTPSync -ComputerName 'BADSERVER', 'GOODSERVER' -ErrorAction SilentlyContinue
            $result | Should -HaveCount 1
            $result[0].ComputerName | Should -Be 'GOODSERVER'
        }
    }

    # -------------------------------------------------------------------
    # Context 7: Parameter validation
    # -------------------------------------------------------------------
    Context -Name 'Parameter validation' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOutputSynced
            }
        }

        It -Name 'Should throw when MaxOffsetMs is zero' -Test {
            { Test-NTPSync -MaxOffsetMs 0 } | Should -Throw
        }

        It -Name 'Should throw when MaxOffsetMs is negative' -Test {
            { Test-NTPSync -MaxOffsetMs -1 } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is empty string' -Test {
            { Test-NTPSync -ComputerName '' } | Should -Throw
        }
    }

    # -------------------------------------------------------------------
    # Context 8: Custom MaxOffsetMs threshold
    # -------------------------------------------------------------------
    Context -Name 'Custom MaxOffsetMs threshold' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -MockWith {
                return $script:mockOutputHighOffset
            }
        }

        It -Name 'Should return IsSynced true when custom threshold is large enough' -Test {
            $result = Test-NTPSync -ComputerName 'REMOTE-DC01' -MaxOffsetMs 5000
            $result.IsSynced | Should -BeTrue
            $result.MaxOffsetMs | Should -Be 5000
        }

        It -Name 'Should return IsSynced false when custom threshold is too small' -Test {
            $result = Test-NTPSync -ComputerName 'REMOTE-DC01' -MaxOffsetMs 100
            $result.IsSynced | Should -BeFalse
            $result.MaxOffsetMs | Should -Be 100
        }
    }
}
