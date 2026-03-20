#Requires -Version 5.1

<#
.SYNOPSIS
    Pester v5 test suite for Get-RdpSession v2.0 (quser-based implementation).

.DESCRIPTION
    Validates ConvertFrom-QUserIdleTime and Get-RdpSession using controlled
    quser output strings. Invoke-Command is mocked throughout remote-query tests
    to return deterministic output independent of the test environment.

    Test scope:
      - ConvertFrom-QUserIdleTime: all idle-time formats and edge cases.
      - Get-RdpSession: output parsing, object shape, IsCurrentSession flag,
        idle-time conversion, pipeline input, local-vs-remote code path,
        Credential forwarding, and error handling.

.NOTES
    Author: Franck SALLET
    Version: 2.0.0
    Last Modified: 2026-03-11
    Requires: PowerShell 5.1+, Pester 5.x, PSWinOps module
    Permissions: None -- all system calls are mocked
#>

BeforeAll {
    # ---------------------------------------------------------------------------
    # Fake quser output -- column positions verified against real quser.exe output.
    #
    # Header column offsets:
    #   colUser    =  1 (start of USERNAME field)
    #   colSession = 23 (IndexOf 'SESSIONNAME')
    #   colId      = 42 (IndexOf ' ID ' + 1)
    #   colState   = 46 (IndexOf 'STATE')
    #   colIdle    = 54 (IndexOf 'IDLE TIME')
    #   colLogon   = 65 (IndexOf 'LOGON TIME')
    # ---------------------------------------------------------------------------
    $script:fakeHeader = ' USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME'
    $script:fakeActive = '>adm-fsallet           rdp-tcp#3           3  Active          .  11/03/2026 19:35'
    $script:fakeDisc = ' adm-asaintpierre      rdp-tcp#2           2  Disc      1+08:15  10/03/2026 11:24'
    $script:fakeTwoSessions = @($script:fakeHeader, $script:fakeActive, $script:fakeDisc)
    $script:fakeHeaderOnly = @($script:fakeHeader)
    $script:fakeRemoteHost = 'FAKE-REMOTE-HOST'

    # PSScriptAnalyzer suppression: dummy test credential only, not used in production
    # cSpell:disable
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test-only credential')]
    $script:fakeCredential = [System.Management.Automation.PSCredential]::new(
        'TESTDOMAIN\testuser',
        (ConvertTo-SecureString -String 'FakeTestP@ss!' -AsPlainText -Force)
    )
    # cSpell:enable

    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force
}

# ===========================================================================
# ConvertFrom-QUserIdleTime -- private function, accessed via InModuleScope
# ===========================================================================

Describe -Name 'ConvertFrom-QUserIdleTime' -Fixture {

    Context -Name 'When the session is currently active (zero idle time)' -Fixture {

        It -Name 'Should return TimeSpan.Zero for a dot' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString '.'
                $result | Should -Be ([TimeSpan]::Zero)
            }
        }

        It -Name 'Should return TimeSpan.Zero for the word none' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString 'none'
                $result | Should -Be ([TimeSpan]::Zero)
            }
        }

        It -Name 'Should return TimeSpan.Zero for an empty string' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString ''
                $result | Should -Be ([TimeSpan]::Zero)
            }
        }

        It -Name 'Should return TimeSpan.Zero for a whitespace-only string' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString '   '
                $result | Should -Be ([TimeSpan]::Zero)
            }
        }
    }

    Context -Name 'When idle time is expressed in minutes only' -Fixture {

        It -Name 'Should return the correct TimeSpan for a single-digit minute count' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString '5'
                $result | Should -Be ([TimeSpan]::FromMinutes(5))
            }
        }

        It -Name 'Should return the correct TimeSpan for a two-digit minute count' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString '45'
                $result | Should -Be ([TimeSpan]::FromMinutes(45))
            }
        }
    }

    Context -Name 'When idle time is in H:MM format' -Fixture {

        It -Name 'Should parse hours and minutes into the correct TimeSpan' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString '8:15'
                $result | Should -Be ([TimeSpan]::new(8, 15, 0))
            }
        }

        It -Name 'Should handle zero minutes correctly' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString '2:00'
                $result | Should -Be ([TimeSpan]::new(2, 0, 0))
            }
        }
    }

    Context -Name 'When idle time is in D+H:MM format' -Fixture {

        It -Name 'Should parse a one-day idle period correctly' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString '1+08:15'
                $result | Should -Be ([TimeSpan]::new(1, 8, 15, 0))
            }
        }

        It -Name 'Should parse a multi-day idle period correctly' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString '14+10:17'
                $result | Should -Be ([TimeSpan]::new(14, 10, 17, 0))
            }
        }
    }

    Context -Name 'When the idle time format is not recognised' -Fixture {

        It -Name 'Should return TimeSpan.Zero as a safe fallback' -Test {
            InModuleScope -ModuleName 'PSWinOps' -ScriptBlock {
                $result = ConvertFrom-QUserIdleTime -IdleTimeString 'unknown-format'
                $result | Should -Be ([TimeSpan]::Zero)
            }
        }
    }
}

# ===========================================================================
# Get-RdpSession -- public exported function
# ===========================================================================

Describe -Name 'Get-RdpSession' -Fixture {

    Context -Name 'When a remote computer returns active and disconnected sessions' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:fakeTwoSessions
            }
        }

        It -Name 'Should return one object per data row' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result.Count | Should -Be 2
        }

        It -Name 'Should stamp the correct PSTypeName on each returned object' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.ActiveRdpSession'
        }

        It -Name 'Should expose all expected properties on the returned object' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $propNames = $result[0].PSObject.Properties.Name
            $propNames | Should -Contain 'ComputerName'
            $propNames | Should -Contain 'SessionID'
            $propNames | Should -Contain 'SessionName'
            $propNames | Should -Contain 'UserName'
            $propNames | Should -Contain 'State'
            $propNames | Should -Contain 'IdleTime'
            $propNames | Should -Contain 'LogonTime'
            $propNames | Should -Contain 'IsCurrentSession'
        }

        It -Name 'Should set IsCurrentSession to true only for the line prefixed with >' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[0].IsCurrentSession | Should -BeTrue
            $result[1].IsCurrentSession | Should -BeFalse
        }

        It -Name 'Should parse the Active state for the first session' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[0].State | Should -Be 'Active'
        }

        It -Name 'Should parse the Disc state for the disconnected session' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[1].State | Should -Be 'Disc'
        }

        It -Name 'Should set IdleTime to TimeSpan.Zero for the active session' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[0].IdleTime | Should -Be ([TimeSpan]::Zero)
        }

        It -Name 'Should parse D+H:MM idle time for the disconnected session' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[1].IdleTime | Should -Be ([TimeSpan]::new(1, 8, 15, 0))
        }

        It -Name 'Should parse the correct UserName from the active session' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[0].UserName | Should -Be 'adm-fsallet'
        }

        It -Name 'Should parse the correct UserName from the disconnected session' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[1].UserName | Should -Be 'adm-asaintpierre'
        }

        It -Name 'Should parse the correct SessionName from the active session' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[0].SessionName | Should -Be 'rdp-tcp#3'
        }

        It -Name 'Should set ComputerName to the queried computer on every object' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[0].ComputerName | Should -Be $script:fakeRemoteHost
            $result[1].ComputerName | Should -Be $script:fakeRemoteHost
        }

        It -Name 'Should set SessionID to the parsed integer for the active session' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[0].SessionID | Should -Be 3
        }

        It -Name 'Should set SessionID to the parsed integer for the disconnected session' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[1].SessionID | Should -Be 2
        }

        It -Name 'Should populate LogonTime as a DateTime object' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result[0].LogonTime | Should -BeOfType ([datetime])
        }

        It -Name 'Should invoke Invoke-Command exactly once for a single remote query' -Test {
            Get-RdpSession -ComputerName $script:fakeRemoteHost
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'When the remote computer has no users logged on' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:fakeHeaderOnly
            }
        }

        It -Name 'Should return nothing when quser outputs only a header line' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When the local computer is queried' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {}
        }

        It -Name 'Should not call Invoke-Command when the target is the local machine' -Test {
            # quser.exe is invoked directly for local queries -- WinRM is not used.
            Get-RdpSession -ComputerName $env:COMPUTERNAME -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context -Name 'When multiple computers are provided via pipeline input' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:fakeHeaderOnly
            }
        }

        It -Name 'Should invoke Invoke-Command exactly once per remote computer' -Test {
            @('FAKE-SRV01', 'FAKE-SRV02') | Get-RdpSession -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context -Name 'When a Credential is provided for a remote query' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:fakeHeaderOnly
            }
        }

        It -Name 'Should forward the Credential parameter to Invoke-Command' -Test {
            Get-RdpSession -ComputerName $script:fakeRemoteHost -Credential $script:fakeCredential -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }
    }

    Context -Name 'When a general runtime error occurs during the remote query' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                throw 'Simulated remote query failure'
            }
        }

        It -Name 'Should not throw when an unexpected error is caught' -Test {
            { Get-RdpSession -ComputerName $script:fakeRemoteHost -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should return no objects when an unexpected error occurs' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When access is denied on the remote computer' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                throw [System.UnauthorizedAccessException]::new('Access denied')
            }
        }

        It -Name 'Should not throw when an UnauthorizedAccessException is caught' -Test {
            { Get-RdpSession -ComputerName $script:fakeRemoteHost -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should return no objects when access is denied' -Test {
            $result = Get-RdpSession -ComputerName $script:fakeRemoteHost -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }
}
