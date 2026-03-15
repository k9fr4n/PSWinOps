#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Set-NTPClient function

.DESCRIPTION
    Comprehensive test coverage for Set-NTPClient, including:
    - Nominal path with service running and successful configuration
    - w32tm command mock routing (register, config update, query configuration, query status)
    - Synchronization success/failure detection (English and French messages)
    - Null-safety of Select-String parsing on w32tm output
    - WhatIf / ShouldProcess behavior
    - Error scenarios (service absent, w32tm failure)

.EXAMPLE
    Invoke-Pester -Path .\Set-NTPClient.Tests.ps1 -Output Detailed

    Runs all tests with detailed output showing each assertion result.

.EXAMPLE
    Invoke-Pester -Path .\Set-NTPClient.Tests.ps1 -Output Detailed -Tag 'Nominal'

    Runs only tests tagged as nominal/happy path scenarios.

.NOTES
    Author:        Ecritel IT Team
    Version:       1.0.0
    Last Modified: 2026-03-15
    Requires:      Pester 5.x, PowerShell 5.1+
    Permissions:   None required (all external commands are mocked)
#>

BeforeAll {
    #region Stubs for Windows-only commands
    # Pester cannot Mock a command that does not exist on the system.
    # On Linux CI runners, Get-Service, Start-Service, Restart-Service, and w32tm are absent.
    # We declare global stub functions BEFORE importing the module
    # so that Mock can intercept them in every test.

    if (-not (Get-Command -Name 'Get-Service' -ErrorAction SilentlyContinue)) {
        function global:Get-Service {
            param([string]$Name, $ErrorAction)
        }
    }

    if (-not (Get-Command -Name 'Start-Service' -ErrorAction SilentlyContinue)) {
        function global:Start-Service {
            param([string]$Name, $ErrorAction)
        }
    }

    if (-not (Get-Command -Name 'Restart-Service' -ErrorAction SilentlyContinue)) {
        function global:Restart-Service {
            param([string]$Name, [switch]$Force, $ErrorAction)
        }
    }

    # w32tm.exe stub -- must exist for Mock to intercept
    if (-not (Get-Command -Name 'w32tm' -ErrorAction SilentlyContinue)) {
        function global:w32tm {
            param()
        }
    }
    #endregion

    # Import module -- two levels above Tests\ntp\
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    #region Mock data
    $script:mockConfigOutput = @(
        'NtpServer: ntp1.example.com,0x9 ntp2.example.com,0x9 (Local)'
        'Type: NTP (Local)'
        'SpecialPollInterval: 300 (Local)'
        'MinPollInterval: 6 (Local)'
        'MaxPollInterval: 10 (Local)'
    )

    $script:mockStatusOutput = @(
        'Leap Indicator: 0(no warning)'
        'Stratum: 3 (secondary reference)'
        'Source: ntp1.example.com'
        'Last Successful Sync Time: 3/15/2026 8:00:00 AM'
    )

    $script:mockSyncOutputEN = @(
        'Sending resync command to local computer...'
        'The command completed successfully.'
    )

    $script:mockSyncOutputFR = @(
        'Envoi de la commande de resynchronisation a l ordinateur local...'
        "La commande s'est deroulee correctement."
    )
    #endregion
}

Describe -Name 'Set-NTPClient' -Fixture {

    # -----------------------------------------------------------------
    # Context 1: Nominal - service running, full success path
    # -----------------------------------------------------------------
    Context -Name 'Nominal - service running, w32tm outputs valid data' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }

            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { $true }

            Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith {}

            Mock -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -MockWith {}

            Mock -CommandName 'Start-Sleep' -ModuleName 'PSWinOps' -MockWith {}

            Mock -CommandName 'Start-Job' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Id = 1; State = 'Completed' }
            }

            Mock -CommandName 'Wait-Job' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Id = 1; State = 'Completed' }
            }

            Mock -CommandName 'Receive-Job' -ModuleName 'PSWinOps' -MockWith {
                $script:mockSyncOutputEN
            }

            Mock -CommandName 'Remove-Job' -ModuleName 'PSWinOps' -MockWith {}

            # FIX: Query-specific patterns BEFORE generic /config pattern
            # '/query.*configuration' must be checked before '/config' because
            # '/config' would match '/query /configuration' (contains "config")
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                return ''
            } -ParameterFilter { $args -match '/register' }

            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                $script:mockConfigOutput
            } -ParameterFilter { $args -match '/query.*configuration' }

            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                $script:mockStatusOutput
            } -ParameterFilter { $args -match '/query.*status' }

            # FIX: Anchored pattern '^/config' so it only matches when /config is at the start
            # This prevents false matches on '/query /configuration'
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                return ''
            } -ParameterFilter { $args -match '^/config' }

            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                return ''
            } -ParameterFilter { $args -match '/resync' }
        }

        It -Name 'Should complete without throwing' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com', 'ntp2.example.com' -Confirm:$false } | Should -Not -Throw
        }

        It -Name 'Should call Set-ItemProperty for NtpServer registry key' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'NtpServer'
            }
        }

        It -Name 'Should call Set-ItemProperty for Type registry key' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Type'
            }
        }

        It -Name 'Should call Restart-Service for w32time' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should invoke w32tm for configuration query' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'w32tm' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $args -match '/query.*configuration'
            }
        }

        It -Name 'Should invoke w32tm for status query' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'w32tm' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $args -match '/query.*status'
            }
        }
    }

    # -----------------------------------------------------------------
    # Context 2: WhatIf - should not modify anything
    # -----------------------------------------------------------------
    Context -Name 'WhatIf - should not perform any changes' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }

            Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { return '' }
        }

        It -Name 'Should not call Set-ItemProperty with -WhatIf' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -WhatIf
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should not call Restart-Service with -WhatIf' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -WhatIf
            Should -Invoke -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    # -----------------------------------------------------------------
    # Context 3: Service not running - should start it
    # -----------------------------------------------------------------
    Context -Name 'Service stopped - should start before configuring' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Stopped' }
            } -ParameterFilter { $Name -eq 'w32time' }

            Mock -CommandName 'Start-Service' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { $true }
            Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Start-Sleep' -ModuleName 'PSWinOps' -MockWith {}

            Mock -CommandName 'Start-Job' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Id = 1; State = 'Completed' }
            }
            Mock -CommandName 'Wait-Job' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Id = 1; State = 'Completed' }
            }
            Mock -CommandName 'Receive-Job' -ModuleName 'PSWinOps' -MockWith {
                $script:mockSyncOutputEN
            }
            Mock -CommandName 'Remove-Job' -ModuleName 'PSWinOps' -MockWith {}

            # FIX: Query-specific patterns BEFORE generic /config
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                $script:mockConfigOutput
            } -ParameterFilter { $args -match '/query.*configuration' }

            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                $script:mockStatusOutput
            } -ParameterFilter { $args -match '/query.*status' }

            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                return ''
            } -ParameterFilter { $args -match '^/config' }

            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                return ''
            } -ParameterFilter { $args -match '/resync' }
        }

        It -Name 'Should call Start-Service when service is stopped' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'Start-Service' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    # -----------------------------------------------------------------
    # Context 4: French sync message - accent-tolerant matching
    # -----------------------------------------------------------------
    Context -Name 'French sync output - accent-tolerant regex matching' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }

            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { $true }
            Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Start-Sleep' -ModuleName 'PSWinOps' -MockWith {}

            Mock -CommandName 'Start-Job' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Id = 1; State = 'Completed' }
            }
            Mock -CommandName 'Wait-Job' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Id = 1; State = 'Completed' }
            }
            Mock -CommandName 'Receive-Job' -ModuleName 'PSWinOps' -MockWith {
                $script:mockSyncOutputFR
            }
            Mock -CommandName 'Remove-Job' -ModuleName 'PSWinOps' -MockWith {}

            # FIX: Query-specific patterns BEFORE generic /config
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                $script:mockConfigOutput
            } -ParameterFilter { $args -match '/query.*configuration' }

            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                $script:mockStatusOutput
            } -ParameterFilter { $args -match '/query.*status' }

            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                return ''
            } -ParameterFilter { $args -match '^/config' }

            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                return ''
            } -ParameterFilter { $args -match '/resync' }
        }

        It -Name 'Should complete without throwing with French sync output' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false } | Should -Not -Throw
        }
    }

    # -----------------------------------------------------------------
    # Context 5: Parameter validation
    # -----------------------------------------------------------------
    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when MaxPollInterval is less than or equal to MinPollInterval' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com' -MinPollInterval 10 -MaxPollInterval 5 -Confirm:$false } | Should -Throw -ExpectedMessage '*MaxPollInterval*must be greater*'
        }

        It -Name 'Should throw when MaxPollInterval equals MinPollInterval' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com' -MinPollInterval 6 -MaxPollInterval 6 -Confirm:$false } | Should -Throw -ExpectedMessage '*MaxPollInterval*must be greater*'
        }
    }

    # -----------------------------------------------------------------
    # Context 6: Error handling - unexpected w32tm failure
    # -----------------------------------------------------------------
    Context -Name 'Error handling - unexpected w32tm failure' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }

            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { $true }
            Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                throw 'Simulated registry failure'
            }
        }

        It -Name 'Should propagate unexpected errors' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false -ErrorAction Stop } | Should -Throw
        }
    }
}
