#Requires -Version 5.1

<#
.SYNOPSIS
    Pester tests for Get-NTPConfiguration function

.DESCRIPTION
    Tests covering:
    - Output structure and property types
    - Service availability checks
    - w32tm output parsing (NtpServer, status, peers)
    - IncludePeerDetails switch behavior
    - Error handling (service not found, w32tm failure)

.NOTES
    Author:        K9FR4N
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      Pester v5.x
    Permissions:   None required

.EXAMPLE
    Invoke-Pester -Path .\Get-NTPConfiguration.Tests.ps1 -Output Detailed

    Runs all tests with detailed output.
#>

BeforeAll {
    #region Stubs for Windows-only commands
    # Pester cannot Mock a command that does not exist on the system.
    # On Linux CI runners, Get-Service and w32tm are absent.
    # We declare global stub functions BEFORE dot-sourcing the script
    # so that Mock can intercept them in every test.

    if (-not (Get-Command -Name 'Get-Service' -ErrorAction SilentlyContinue)) {
        function global:Get-Service {
            param([string]$Name, $ErrorAction)
        }
    }

    # w32tm.exe stub -- must exist for Mock to intercept
    if (-not (Get-Command -Name 'w32tm' -ErrorAction SilentlyContinue)) {
        function global:w32tm {
            param()
        }
    }
    #endregion

    # Import module
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    #region Mock data
    $script:mockConfigOutput = @(
        'NtpServer: ntp1.example.com,0x9 ntp2.example.com,0x9 (Local)'
        'Type: NTP (Local)'
        'SpecialPollInterval: 3600 (Local)'
        'MinPollInterval: 6 (Local)'
        'MaxPollInterval: 10 (Local)'
    )

    $script:mockStatusOutput = @(
        'Leap Indicator: 0(no warning)'
        'Stratum: 3 (secondary reference)'
        'Source: ntp1.example.com'
        'Last Successful Sync Time: 2/20/2026 8:00:00 AM'
    )

    $script:mockPeersOutput = @(
        '#Peers: 2'
        'Peer: ntp1.example.com,0x9'
        'State: Active'
        'Peer: ntp2.example.com,0x9'
        'State: Active'
    )
    #endregion
}

Describe -Name 'Get-NTPConfiguration' -Fixture {

    # ---------------------------------------------------------------
    # Context 1: Nominal - service running
    # ---------------------------------------------------------------
    Context -Name 'Nominal - service running, w32tm outputs valid data' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }

            # Mock w32tm with ParameterFilter to match each invocation
            Mock -CommandName 'w32tm' -MockWith {
                $script:mockConfigOutput
            } -ParameterFilter { $args -contains '/query' -and $args -contains '/configuration' }

            Mock -CommandName 'w32tm' -MockWith {
                $script:mockStatusOutput
            } -ParameterFilter { $args -contains '/query' -and $args -contains '/status' }

            Mock -CommandName 'w32tm' -MockWith {
                $script:mockPeersOutput
            } -ParameterFilter { $args -contains '/query' -and $args -contains '/peers' }
        }

        It -Name 'Should return a PSCustomObject' -Test {
            $result = Get-NTPConfiguration
            $result | Should -BeOfType ([PSCustomObject])
        }

        It -Name 'Should expose all expected properties' -Test {
            $result = Get-NTPConfiguration
            $expected = @(
                'ServiceName', 'ServiceStatus', 'SyncType', 'ConfiguredServers',
                'CurrentSource', 'LastSuccessfulSync', 'Stratum', 'LeapIndicator',
                'SpecialPollInterval', 'MinPollInterval', 'MaxPollInterval',
                'MinPollIntervalSec', 'MaxPollIntervalSec', 'QueryTimestamp'
            )
            foreach ($prop in $expected) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It -Name 'ServiceName should be w32time' -Test {
            $result = Get-NTPConfiguration
            $result.ServiceName | Should -Be 'w32time'
        }

        It -Name 'ServiceStatus should be Running' -Test {
            $result = Get-NTPConfiguration
            $result.ServiceStatus | Should -Be 'Running'
        }

        It -Name 'SyncType should contain NTP' -Test {
            # w32tm returns 'NTP (Local)' - use -Match to tolerate the suffix
            $result = Get-NTPConfiguration
            $result.SyncType | Should -Match 'NTP'
        }

        It -Name 'ConfiguredServers should contain 2 entries' -Test {
            $result = Get-NTPConfiguration
            $result.ConfiguredServers | Should -HaveCount 2
            $result.ConfiguredServers | Should -Contain 'ntp1.example.com,0x9'
            $result.ConfiguredServers | Should -Contain 'ntp2.example.com,0x9'
        }

        It -Name 'CurrentSource should match mock' -Test {
            $result = Get-NTPConfiguration
            $result.CurrentSource | Should -Be 'ntp1.example.com'
        }

        It -Name 'LastSuccessfulSync should not be Never' -Test {
            $result = Get-NTPConfiguration
            $result.LastSuccessfulSync | Should -Not -Be 'Never'
        }

        It -Name 'Stratum should be [int] equal to 3' -Test {
            $result = Get-NTPConfiguration
            $result.Stratum | Should -BeOfType ([int])
            $result.Stratum | Should -Be 3
        }

        It -Name 'SpecialPollInterval should be [int] equal to 3600' -Test {
            $result = Get-NTPConfiguration
            $result.SpecialPollInterval | Should -BeOfType ([int])
            $result.SpecialPollInterval | Should -Be 3600
        }

        It -Name 'MinPollInterval should be 6' -Test {
            $result = Get-NTPConfiguration
            $result.MinPollInterval | Should -Be 6
        }

        It -Name 'MaxPollInterval should be 10' -Test {
            $result = Get-NTPConfiguration
            $result.MaxPollInterval | Should -Be 10
        }

        It -Name 'MinPollIntervalSec should equal 2^6 = 64' -Test {
            $result = Get-NTPConfiguration
            $result.MinPollIntervalSec | Should -Be 64
        }

        It -Name 'MaxPollIntervalSec should equal 2^10 = 1024' -Test {
            $result = Get-NTPConfiguration
            $result.MaxPollIntervalSec | Should -Be 1024
        }

        It -Name 'QueryTimestamp should be parseable as ISO 8601' -Test {
            $result = Get-NTPConfiguration
            { [datetime]::Parse($result.QueryTimestamp) } | Should -Not -Throw
        }

        It -Name 'LeapIndicator should not be Unknown' -Test {
            $result = Get-NTPConfiguration
            $result.LeapIndicator | Should -Not -Be 'Unknown'
        }
    }

    # ---------------------------------------------------------------
    # Context 2: -IncludePeerDetails
    # ---------------------------------------------------------------
    Context -Name '-IncludePeerDetails switch' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }

            Mock -CommandName 'w32tm' -MockWith {
                $script:mockConfigOutput
            } -ParameterFilter { $args -contains '/query' -and $args -contains '/configuration' }

            Mock -CommandName 'w32tm' -MockWith {
                $script:mockStatusOutput
            } -ParameterFilter { $args -contains '/query' -and $args -contains '/status' }

            Mock -CommandName 'w32tm' -MockWith {
                $script:mockPeersOutput
            } -ParameterFilter { $args -contains '/query' -and $args -contains '/peers' }
        }

        It -Name 'Should NOT expose PeerDetails without the switch' -Test {
            $result = Get-NTPConfiguration
            $result.PSObject.Properties.Name | Should -Not -Contain 'PeerDetails'
        }

        It -Name 'Should expose PeerDetails with -IncludePeerDetails' -Test {
            $result = Get-NTPConfiguration -IncludePeerDetails
            $result.PSObject.Properties.Name | Should -Contain 'PeerDetails'
        }

        It -Name 'PeerDetails should reference both peers' -Test {
            $result = Get-NTPConfiguration -IncludePeerDetails
            $result.PeerDetails | Should -Match 'ntp1.example.com'
            $result.PeerDetails | Should -Match 'ntp2.example.com'
        }
    }

    # ---------------------------------------------------------------
    # Context 3: Degraded - empty w32tm output
    # ---------------------------------------------------------------
    Context -Name 'Degraded - w32tm returns empty output' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Stopped' }
            } -ParameterFilter { $Name -eq 'w32time' }

            # Mock w32tm to return empty arrays
            Mock -CommandName 'w32tm' -MockWith { @() }
        }

        It -Name 'SyncType should default to Unknown' -Test {
            $result = Get-NTPConfiguration
            $result.SyncType | Should -Be 'Unknown'
        }

        It -Name 'ConfiguredServers should be empty' -Test {
            $result = Get-NTPConfiguration
            $result.ConfiguredServers | Should -HaveCount 0
        }

        It -Name 'CurrentSource should default to Unknown' -Test {
            $result = Get-NTPConfiguration
            $result.CurrentSource | Should -Be 'Unknown'
        }

        It -Name 'LastSuccessfulSync should default to Never' -Test {
            $result = Get-NTPConfiguration
            $result.LastSuccessfulSync | Should -Be 'Never'
        }

        It -Name 'Stratum should be null' -Test {
            $result = Get-NTPConfiguration
            $result.Stratum | Should -BeNullOrEmpty
        }

        It -Name 'SpecialPollInterval should be null' -Test {
            $result = Get-NTPConfiguration
            $result.SpecialPollInterval | Should -BeNullOrEmpty
        }

        It -Name 'MinPollIntervalSec should be null when MinPollInterval is null' -Test {
            $result = Get-NTPConfiguration
            $result.MinPollIntervalSec | Should -BeNullOrEmpty
        }

        It -Name 'MaxPollIntervalSec should be null when MaxPollInterval is null' -Test {
            $result = Get-NTPConfiguration
            $result.MaxPollIntervalSec | Should -BeNullOrEmpty
        }
    }

    # ---------------------------------------------------------------
    # Context 4: Error - service absent
    # ---------------------------------------------------------------
    Context -Name 'Error handling - w32time service absent' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -MockWith {
                $exception = [System.InvalidOperationException]::new("Cannot find any service with service name 'w32time'.")
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'ServiceNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    'w32time'
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            } -ParameterFilter { $Name -eq 'w32time' }
        }

        It -Name 'Should throw when service is not found' -Test {
            { Get-NTPConfiguration -ErrorAction Stop } | Should -Throw
        }

        It -Name 'Should throw an error mentioning w32time' -Test {
            { Get-NTPConfiguration -ErrorAction Stop } | Should -Throw -ExpectedMessage '*w32time*'
        }
    }

    # ---------------------------------------------------------------
    # Context 5: Error - unexpected w32tm failure
    # ---------------------------------------------------------------
    Context -Name 'Error handling - unexpected w32tm failure' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }

            Mock -CommandName 'w32tm' -MockWith {
                throw 'Simulated w32tm failure'
            }
        }

        It -Name 'Should propagate unexpected w32tm errors' -Test {
            { Get-NTPConfiguration -ErrorAction Stop } | Should -Throw
        }
    }
}
