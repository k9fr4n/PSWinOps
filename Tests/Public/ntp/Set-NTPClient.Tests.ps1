#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
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
    if (-not (Get-Command -Name 'w32tm' -ErrorAction SilentlyContinue)) {
        function global:w32tm {
            param()
        }
    }

    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

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
    $script:mockSyncOutputDE = @(
        'Sendet den Befehl zur erneuten Synchronisierung an den lokalen Computer...'
        'Der Befehl wurde erfolgreich ausgeführt.'
    )
}

Describe -Name 'Set-NTPClient' -Fixture {
    Context -Name 'Nominal - service running, w32tm outputs valid data' -Fixture {
        BeforeEach {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { $true }
            Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Start-Sleep' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { return '' } -ParameterFilter { ($args -join ' ') -match '/register' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { $script:mockConfigOutput } -ParameterFilter { ($args -join ' ') -match '/query.*configuration' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { $script:mockStatusOutput } -ParameterFilter { ($args -join ' ') -match '/query.*status' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { return '' } -ParameterFilter { ($args -join ' ') -match '/config /update' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { $global:LASTEXITCODE = 0; $script:mockSyncOutputEN } -ParameterFilter { ($args -join ' ') -match '/resync' }
        }

        It -Name 'Should complete without throwing' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com', 'ntp2.example.com' -Confirm:$false } | Should -Not -Throw
        }
        It -Name 'Should call Set-ItemProperty for NtpServer registry key' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter { $Name -eq 'NtpServer' }
        }
        It -Name 'Should call Set-ItemProperty for Type registry key' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter { $Name -eq 'Type' }
        }
        It -Name 'Should call Restart-Service for w32time' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
        It -Name 'Should invoke w32tm for configuration query' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'w32tm' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -match '/query.*configuration' }
        }
        It -Name 'Should invoke w32tm for status query' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'w32tm' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -match '/query.*status' }
        }
    }

    Context -Name 'WhatIf - should not perform any changes' -Fixture {
        BeforeEach {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
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

    Context -Name 'Service stopped - should start before configuring' -Fixture {
        BeforeEach {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Stopped' }
            } -ParameterFilter { $Name -eq 'w32time' }
            Mock -CommandName 'Start-Service' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { $true }
            Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Start-Sleep' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { $script:mockConfigOutput } -ParameterFilter { ($args -join ' ') -match '/query.*configuration' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { $script:mockStatusOutput } -ParameterFilter { ($args -join ' ') -match '/query.*status' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { return '' } -ParameterFilter { ($args -join ' ') -match '/config /update' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { $global:LASTEXITCODE = 0; $script:mockSyncOutputEN } -ParameterFilter { ($args -join ' ') -match '/resync' }
        }
        It -Name 'Should call Start-Service when service is stopped' -Test {
            Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false
            Should -Invoke -CommandName 'Start-Service' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'Locale-agnostic - German output with exit code 0' -Fixture {
        BeforeEach {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'w32time' }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { $true }
            Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Restart-Service' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Start-Sleep' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { $script:mockConfigOutput } -ParameterFilter { ($args -join ' ') -match '/query.*configuration' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { $script:mockStatusOutput } -ParameterFilter { ($args -join ' ') -match '/query.*status' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { return '' } -ParameterFilter { ($args -join ' ') -match '/config /update' }
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith { $global:LASTEXITCODE = 0; $script:mockSyncOutputDE } -ParameterFilter { ($args -join ' ') -match '/resync' }
        }
        It -Name 'Should complete without throwing with non-EN/FR output when exit code is 0' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false } | Should -Not -Throw
        }
    }

    Context -Name 'Parameter validation' -Fixture {
        It -Name 'Should throw when MaxPollInterval is less than or equal to MinPollInterval' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com' -MinPollInterval 10 -MaxPollInterval 5 -Confirm:$false } | Should -Throw -ExpectedMessage '*MaxPollInterval*must be greater*'
        }
        It -Name 'Should throw when MaxPollInterval equals MinPollInterval' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com' -MinPollInterval 6 -MaxPollInterval 6 -Confirm:$false } | Should -Throw -ExpectedMessage '*MaxPollInterval*must be greater*'
        }
    }

    Context -Name 'Error handling - unexpected w32tm failure' -Fixture {
        BeforeEach {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
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

    Context -Name 'Elevation check - should throw when not administrator' -Fixture {
        BeforeEach {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $false }
        }

        It -Name 'Should throw UnauthorizedAccessException when not elevated' -Test {
            { Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false -ErrorAction Stop } | Should -Throw -ExpectedMessage '*Administrator privileges*'
        }

        It -Name 'Should not call Set-ItemProperty when not elevated' -Test {
            Mock -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -MockWith {}
            try { Set-NTPClient -NtpServers 'ntp1.example.com' -Confirm:$false -ErrorAction Stop } catch {}
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

}
