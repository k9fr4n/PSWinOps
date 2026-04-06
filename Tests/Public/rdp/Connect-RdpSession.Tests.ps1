#Requires -Version 5.1

BeforeAll {
    <#
.SYNOPSIS
    Test suite for Connect-RdpSession v1.2.0

.DESCRIPTION
    Validates Connect-RdpSession behavior: shadow session initiation via mstsc.exe,
    session verification via qwinsta.exe (wrapped by Invoke-NativeCommand), Control and
    View modes, ShouldProcess support (-WhatIf / -Confirm), and error handling for
    missing executables, failed launches, and non-zero exit codes.

    All native command calls are isolated: Invoke-NativeCommand and Start-Process
    are mocked at module scope. No real qwinsta.exe or mstsc.exe is invoked.

.NOTES
    Author:        Franck SALLET
    Version:       2.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+, Pester 5.x
    Permissions:   None (all external calls mocked)
#>
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force

    # ---------------------------------------------------------------------------
    # Shared qwinsta-formatted output fixtures
    # ---------------------------------------------------------------------------

    # One active session -- session ID 2
    $script:qwinstaSession2 = @(
        ' SESSIONNAME       USERNAME                 ID  STATE',
        ' rdp-tcp#0         adm-fsallet               2  Active'
    )

    # One active session -- session ID 3 (used in pipeline tests)
    $script:qwinstaSession3 = @(
        ' SESSIONNAME       USERNAME                 ID  STATE',
        ' rdp-tcp#1         domain\helpdesk           3  Active'
    )
}

Describe -Name 'Connect-RdpSession' -Fixture {

    BeforeEach {
        # -----------------------------------------------------------------------
        # Default happy-path mocks -- overridden per context as needed.
        # Test-Path returns $true so begin{} never throws on missing mstsc.exe.
        # Invoke-NativeCommand wraps qwinsta.exe -- returns session 2 with ExitCode 0.
        # Start-Process returns ExitCode 0 (shadow session ended normally).
        # -----------------------------------------------------------------------
        Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { $true }

        Mock -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -MockWith {
            [PSCustomObject]@{
                Output   = ($script:qwinstaSession2 -join "`r`n")
                ExitCode = 0
            }
        }

        Mock -CommandName 'Start-Process' -ModuleName 'PSWinOps' -MockWith {
            [PSCustomObject]@{ ExitCode = 0 }
        }
    }

    # ===========================================================================
    Context -Name 'When entering a session successfully in Control mode' -Fixture {

        It -Name 'Should return a result object with Success set to true' -Test {
            $result = Connect-RdpSession -SessionID 2 -Confirm:$false
            $result.Success | Should -Be $true
            $result.ExitCode | Should -Be 0
        }

        It -Name 'Should report Action as Shadow' -Test {
            $result = Connect-RdpSession -SessionID 2 -Confirm:$false
            $result.Action | Should -Be 'Shadow'
        }

        It -Name 'Should default ControlMode to Control' -Test {
            $result = Connect-RdpSession -SessionID 2 -Confirm:$false
            $result.ControlMode | Should -Be 'Control'
        }

        It -Name 'Should include ComputerName in the result object' -Test {
            $result = Connect-RdpSession -SessionID 2 -ComputerName 'ecrmut-ad-02' -Confirm:$false
            $result.ComputerName | Should -Be 'ecrmut-ad-02'
        }

        It -Name 'Should include SessionID in the result object' -Test {
            $result = Connect-RdpSession -SessionID 2 -Confirm:$false
            $result.SessionID | Should -Be 2
        }

        It -Name 'Should invoke Start-Process to launch the shadow window' -Test {
            Connect-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should verify session existence via Invoke-NativeCommand before launching' -Test {
            Connect-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should pass /shadow and /v arguments to mstsc.exe' -Test {
            Connect-RdpSession -SessionID 2 -ComputerName 'ecrmut-ad-02' -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter {
                ($ArgumentList -contains '/shadow:2') -and
                ($ArgumentList -contains '/v:ecrmut-ad-02')
            }
        }

        It -Name 'Should pass /control argument to mstsc.exe in Control mode' -Test {
            Connect-RdpSession -SessionID 2 -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList -contains '/control' }
        }
    }

    # ===========================================================================
    Context -Name 'When entering a session in View mode' -Fixture {

        It -Name 'Should report ControlMode as View' -Test {
            $result = Connect-RdpSession -SessionID 2 -ControlMode View -Confirm:$false
            $result.ControlMode | Should -Be 'View'
        }

        It -Name 'Should not pass /control argument to mstsc.exe in View mode' -Test {
            Connect-RdpSession -SessionID 2 -ControlMode View -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { -not ($ArgumentList -contains '/control') }
        }
    }

    # ===========================================================================
    Context -Name 'When the target session does not exist' -Fixture {
        # Default mock returns only session 2 -- session 999 is intentionally absent.

        It -Name 'Should write an error and not launch mstsc.exe' -Test {
            Connect-RdpSession -SessionID 999 -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Start-Process' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should return no output when the session is not found' -Test {
            $result = Connect-RdpSession -SessionID 999 -Confirm:$false -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    # ===========================================================================
    Context -Name 'When qwinsta reports an error (non-zero exit code)' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    Output   = '[ERROR] Access denied to remote server'
                    ExitCode = 5
                }
            }
        }

        It -Name 'Should write an error and not launch mstsc.exe' -Test {
            Connect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Start-Process' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should return no output on qwinsta failure' -Test {
            $result = Connect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    # ===========================================================================
    Context -Name 'When ShouldProcess is declined via WhatIf' -Fixture {
        # Session verification runs OUTSIDE ShouldProcess -- Invoke-NativeCommand is
        # always called. Start-Process is INSIDE ShouldProcess -- never called with -WhatIf.

        It -Name 'Should not invoke Start-Process when WhatIf is specified' -Test {
            Connect-RdpSession -SessionID 2 -WhatIf
            Should -Invoke -CommandName 'Start-Process' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should still verify session existence via Invoke-NativeCommand when WhatIf is specified' -Test {
            Connect-RdpSession -SessionID 2 -WhatIf
            Should -Invoke -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    # ===========================================================================
    Context -Name 'When mstsc.exe exits with a non-zero exit code' -Fixture {

        BeforeEach {
            Mock -CommandName 'Start-Process' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ExitCode = 1 }
            }
        }

        It -Name 'Should return a result object with Success set to false' -Test {
            $result = Connect-RdpSession -SessionID 2 -Confirm:$false
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $false
        }

        It -Name 'Should include the non-zero exit code in the result object' -Test {
            $result = Connect-RdpSession -SessionID 2 -Confirm:$false
            $result.ExitCode | Should -Be 1
        }
    }

    # ===========================================================================
    Context -Name 'When Start-Process throws an exception' -Fixture {

        BeforeEach {
            Mock -CommandName 'Start-Process' -ModuleName 'PSWinOps' -MockWith {
                throw 'Test-induced Start-Process failure'
            }
        }

        It -Name 'Should write an error without propagating the exception to the caller' -Test {
            { Connect-RdpSession -SessionID 2 -Confirm:$false -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }
    }

    # ===========================================================================
    Context -Name 'When processing pipeline input from Get-RdpSession' -Fixture {

        It -Name 'Should accept SessionID and ComputerName from pipeline by property name' -Test {
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    Output   = ($script:qwinstaSession3 -join "`r`n")
                    ExitCode = 0
                }
            }
            $pipelineInput = [PSCustomObject]@{ SessionID = 3; ComputerName = 'SRV01' }
            $result = $pipelineInput | Connect-RdpSession -Confirm:$false
            $result.SessionID | Should -Be 3
            $result.ComputerName | Should -Be 'SRV01'
        }
    }

    # ===========================================================================
    Context -Name 'When NoUserPrompt switch is specified' -Fixture {

        It -Name 'Should pass /noConsentPrompt to mstsc.exe' -Test {
            Connect-RdpSession -SessionID 2 -NoUserPrompt -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList -contains '/noConsentPrompt' }
        }

        It -Name 'Should complete successfully when NoUserPrompt is specified' -Test {
            $result = Connect-RdpSession -SessionID 2 -NoUserPrompt -Confirm:$false
            $result.Success | Should -Be $true
        }
    }

    # ===========================================================================
    Context -Name 'When a Credential is specified' -Fixture {

        It -Name 'Should forward the credential to Start-Process' -Test {
            $securePassword = New-Object System.Security.SecureString
            'TestPassword1!'.ToCharArray() | ForEach-Object { $securePassword.AppendChar($_) }
            $testCred = [System.Management.Automation.PSCredential]::new(
                'DOMAIN\testuser',
                $securePassword
            )
            Connect-RdpSession -SessionID 2 -Credential $testCred -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $null -ne $Credential }
        }
    }

    # ===========================================================================
    Context -Name 'When mstsc.exe is not found on the system' -Fixture {

        BeforeEach {
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { $false }
        }

        It -Name 'Should throw before attempting session verification' -Test {
            { Connect-RdpSession -SessionID 2 } | Should -Throw
            Should -Invoke -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }
}
