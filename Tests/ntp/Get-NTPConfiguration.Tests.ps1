<#
.SYNOPSIS
    Pester tests for Get-NTPConfiguration function.
.DESCRIPTION
    Tests covering:
    - Output structure and property types
    - Service availability checks
    - w32tm output parsing (NtpServer, status, peers)
    - IncludePeerDetails switch behavior
    - Error handling (service not found, w32tm failure)
.NOTES
    Author: K9FR4N
    Pester: v5.x
    Run with: Invoke-Pester -Path .\Get-NTPConfiguration.Tests.ps1 -Output Detailed
#>

BeforeAll {
    #region Stubs for Windows-only commands
    # Pester cannot Mock a command that does not exist on the system.
    # On Linux CI runners, Get-Service and w32tm are absent.
    # We declare global stub functions BEFORE dot-sourcing the script
    # so that Mock can intercept them in every test.
    if (-not (Get-Command 'Get-Service' -ErrorAction SilentlyContinue)) {
        function global:Get-Service {
            param([string]$Name, $ErrorAction)
        }
    }
    function global:w32tm {
        param()
    }
    #endregion

    . (Join-Path $PSScriptRoot 'Get-NTPConfiguration.ps1')

    #region Mock data
    $Script:MockConfigOutput = @(
        'NtpServer: ntp1.example.com,0x9 ntp2.example.com,0x9 (Local)'
        'Type: NTP (Local)'
        'SpecialPollInterval: 3600 (Local)'
        'MinPollInterval: 6 (Local)'
        'MaxPollInterval: 10 (Local)'
    )

    $Script:MockStatusOutput = @(
        'Leap Indicator: 0(no warning)'
        'Stratum: 3 (secondary reference)'
        'Source: ntp1.example.com'
        'Last Successful Sync Time: 2/20/2026 8:00:00 AM'
    )

    $Script:MockPeersOutput = @(
        '#Peers: 2'
        'Peer: ntp1.example.com,0x9'
        'State: Active'
        'Peer: ntp2.example.com,0x9'
        'State: Active'
    )
    #endregion
}

Describe 'Get-NTPConfiguration' {

    # ---------------------------------------------------------------
    # Context 1 : Nominal - service running
    # ---------------------------------------------------------------
    Context 'Nominal - service running, w32tm outputs valid data' {

        BeforeEach {
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }

            Mock w32tm {
                switch ($args -join ' ') {
                    '/query /configuration' {
                        return $Script:MockConfigOutput
                    }
                    '/query /status /verbose' {
                        return $Script:MockStatusOutput
                    }
                    '/query /peers' {
                        return $Script:MockPeersOutput
                    }
                }
            }
        }

        It 'Should return a PSCustomObject' {
            Get-NTPConfiguration | Should -BeOfType [PSCustomObject]
        }

        It 'Should expose all expected properties' {
            $r = Get-NTPConfiguration
            $expected = @(
                'ServiceName', 'ServiceStatus', 'SyncType', 'ConfiguredServers',
                'CurrentSource', 'LastSuccessfulSync', 'Stratum', 'LeapIndicator',
                'SpecialPollInterval', 'MinPollInterval', 'MaxPollInterval',
                'MinPollIntervalSec', 'MaxPollIntervalSec', 'QueryTimestamp'
            )
            foreach ($p in $expected) {
                $r.PSObject.Properties.Name | Should -Contain $p
            }
        }

        It 'ServiceName should be w32time' {
            (Get-NTPConfiguration).ServiceName | Should -Be 'w32time'
        }

        It 'ServiceStatus should be Running' {
            (Get-NTPConfiguration).ServiceStatus | Should -Be 'Running'
        }

        It 'SyncType should contain NTP' {
            # w32tm returns 'NTP (Local)' - use -Match to tolerate the suffix
            (Get-NTPConfiguration).SyncType | Should -Match 'NTP'
        }

        It 'ConfiguredServers should contain 2 entries' {
            $r = Get-NTPConfiguration
            $r.ConfiguredServers | Should -HaveCount 2
            $r.ConfiguredServers | Should -Contain 'ntp1.example.com,0x9'
            $r.ConfiguredServers | Should -Contain 'ntp2.example.com,0x9'
        }

        It 'CurrentSource should match mock' {
            (Get-NTPConfiguration).CurrentSource | Should -Be 'ntp1.example.com'
        }

        It 'LastSuccessfulSync should not be Never' {
            (Get-NTPConfiguration).LastSuccessfulSync | Should -Not -Be 'Never'
        }

        It 'Stratum should be [int] equal to 3' {
            $r = Get-NTPConfiguration
            $r.Stratum | Should -BeOfType [int]
            $r.Stratum | Should -Be 3
        }

        It 'SpecialPollInterval should be [int] equal to 3600' {
            $r = Get-NTPConfiguration
            $r.SpecialPollInterval | Should -BeOfType [int]
            $r.SpecialPollInterval | Should -Be 3600
        }

        It 'MinPollInterval should be 6' {
            (Get-NTPConfiguration).MinPollInterval | Should -Be 6
        }

        It 'MaxPollInterval should be 10' {
            (Get-NTPConfiguration).MaxPollInterval | Should -Be 10
        }

        It 'MinPollIntervalSec should equal 2^6 = 64' {
            (Get-NTPConfiguration).MinPollIntervalSec | Should -Be 64
        }

        It 'MaxPollIntervalSec should equal 2^10 = 1024' {
            (Get-NTPConfiguration).MaxPollIntervalSec | Should -Be 1024
        }

        It 'QueryTimestamp should be parseable as ISO 8601' {
            { [datetime]::Parse((Get-NTPConfiguration).QueryTimestamp) } | Should -Not -Throw
        }

        It 'LeapIndicator should not be Unknown' {
            (Get-NTPConfiguration).LeapIndicator | Should -Not -Be 'Unknown'
        }
    }

    # ---------------------------------------------------------------
    # Context 2 : -IncludePeerDetails
    # ---------------------------------------------------------------
    Context '-IncludePeerDetails switch' {

        BeforeEach {
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }
            Mock w32tm {
                switch ($args -join ' ') {
                    '/query /configuration' {
                        return $Script:MockConfigOutput
                    }
                    '/query /status /verbose' {
                        return $Script:MockStatusOutput
                    }
                    '/query /peers' {
                        return $Script:MockPeersOutput
                    }
                }
            }
        }

        It 'Should NOT expose PeerDetails without the switch' {
            $r = Get-NTPConfiguration
            $r.PSObject.Properties.Name | Should -Not -Contain 'PeerDetails'
        }

        It 'Should expose PeerDetails with -IncludePeerDetails' {
            $r = Get-NTPConfiguration -IncludePeerDetails
            $r.PSObject.Properties.Name | Should -Contain 'PeerDetails'
        }

        It 'PeerDetails should reference both peers' {
            $r = Get-NTPConfiguration -IncludePeerDetails
            $r.PeerDetails | Should -Match 'ntp1.example.com'
            $r.PeerDetails | Should -Match 'ntp2.example.com'
        }
    }

    # ---------------------------------------------------------------
    # Context 3 : Degraded - empty w32tm output
    # ---------------------------------------------------------------
    Context 'Degraded - w32tm returns empty output' {

        BeforeEach {
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Stopped' }
            } -ParameterFilter { $Name -eq 'w32time' }
            Mock w32tm { return @() }
        }

        It 'SyncType should default to Unknown' {
            (Get-NTPConfiguration).SyncType | Should -Be 'Unknown'
        }

        It 'ConfiguredServers should be empty' {
            (Get-NTPConfiguration).ConfiguredServers | Should -HaveCount 0
        }

        It 'CurrentSource should default to Unknown' {
            (Get-NTPConfiguration).CurrentSource | Should -Be 'Unknown'
        }

        It 'LastSuccessfulSync should default to Never' {
            (Get-NTPConfiguration).LastSuccessfulSync | Should -Be 'Never'
        }

        It 'Stratum should be null' {
            (Get-NTPConfiguration).Stratum | Should -BeNullOrEmpty
        }

        It 'SpecialPollInterval should be null' {
            (Get-NTPConfiguration).SpecialPollInterval | Should -BeNullOrEmpty
        }

        It 'MinPollIntervalSec should be null when MinPollInterval is null' {
            (Get-NTPConfiguration).MinPollIntervalSec | Should -BeNullOrEmpty
        }

        It 'MaxPollIntervalSec should be null when MaxPollInterval is null' {
            (Get-NTPConfiguration).MaxPollIntervalSec | Should -BeNullOrEmpty
        }
    }

    # ---------------------------------------------------------------
    # Context 4 : Error - service absent
    # ---------------------------------------------------------------
    Context 'Error handling - w32time service absent' {

        BeforeEach {
            Mock Get-Service {
                # Avoid [Microsoft.PowerShell.Commands.ServiceCommandException]
                # which does not exist on Linux CI runners.
                # Throwing a string produces a RuntimeException whose message
                # contains 'w32time', which is what we assert below.
                throw "Cannot find any service with service name 'w32time'."
            } -ParameterFilter { $Name -eq 'w32time' }
        }

        It 'Should throw when service is not found' {
            { Get-NTPConfiguration } | Should -Throw
        }

        It 'Should throw an error mentioning w32time' -Skip:(-not $IsWindows) {
            # On Linux, the production script's 'catch [ServiceCommandException]'
            # itself fails to resolve the type, masking the original message.
            # This assertion is only meaningful on Windows where the type exists.
            { Get-NTPConfiguration } | Should -Throw -ExpectedMessage 'w32time'
        }
    }

    # ---------------------------------------------------------------
    # Context 5 : Error - unexpected w32tm failure
    # ---------------------------------------------------------------
    Context 'Error handling - unexpected w32tm failure' {

        BeforeEach {
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }
            Mock w32tm { throw 'Simulated w32tm failure' }
        }

        It 'Should propagate unexpected w32tm errors' {
            { Get-NTPConfiguration } | Should -Throw
        }
    }
}
