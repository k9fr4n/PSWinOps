#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Script-scoped variables used across It blocks'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:testShadowId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'
}

Describe 'New-ShadowCopy' {

    Context 'Happy path local' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ ReturnValue = [uint32]0; ShadowId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; VolumePath = '\\?\Volume{abc123}\' }
            }
            $script:result = New-ShadowCopy -DriveLetter 'C' -Confirm:$false
        }
        It 'Should return PSWinOps.ShadowCopyResult type' { $script:result.PSTypeNames[0] | Should -Be 'PSWinOps.ShadowCopyResult' }
        It 'Should have Success true' { $script:result.Success | Should -BeTrue }
        It 'Should have ReturnCode 0' { $script:result.ReturnCode | Should -Be 0 }
        It 'Should have ReturnMessage Success' { $script:result.ReturnMessage | Should -Be 'Success' }
        It 'Should have correct ShadowCopyId' { $script:result.ShadowCopyId | Should -Be $script:testShadowId }
        It 'Should have DriveLetter C' { $script:result.DriveLetter | Should -Be 'C' }
    }

    Context 'Remote single machine' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ ReturnValue = [uint32]0; ShadowId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; VolumePath = '\\?\Volume{abc123}\' }
            }
            $script:result = New-ShadowCopy -DriveLetter 'C' -ComputerName 'SRV01' -Confirm:$false
        }
        It 'Should have ComputerName SRV01' { $script:result.ComputerName | Should -Be 'SRV01' }
        It 'Should have Success true' { $script:result.Success | Should -BeTrue }
    }

    Context 'Pipeline with multiple computers' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ ReturnValue = [uint32]0; ShadowId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; VolumePath = '\\?\Volume{abc123}\' }
            }
            $script:results = 'SRV01', 'SRV02' | New-ShadowCopy -DriveLetter 'C' -Confirm:$false
        }
        It 'Should return 2 results' { $script:results | Should -HaveCount 2 }
    }

    Context 'Return code failure (InsufficientStorage)' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ ReturnValue = [uint32]4; ShadowId = ''; VolumePath = '\\?\Volume{abc123}\' }
            }
            $script:result = New-ShadowCopy -DriveLetter 'C' -Confirm:$false
        }
        It 'Should have Success false' { $script:result.Success | Should -BeFalse }
        It 'Should have ReturnCode 4' { $script:result.ReturnCode | Should -Be 4 }
        It 'Should have ReturnMessage InsufficientStorage' { $script:result.ReturnMessage | Should -Be 'InsufficientStorage' }
    }

    Context 'Per-machine failure (exception)' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
            $script:result = New-ShadowCopy -DriveLetter 'C' -ComputerName 'DEAD01' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable 'script:capturedError'
        }
        It 'Should write error' { $script:capturedError | Should -Not -BeNullOrEmpty }
        It 'Should have Success false' { $script:result.Success | Should -BeFalse }
        It 'Should have ReturnCode 99' { $script:result.ReturnCode | Should -Be 99 }
    }

    Context 'WhatIf support' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { @{ ReturnValue = [uint32]0; ShadowId = ''; VolumePath = '' } }
            New-ShadowCopy -DriveLetter 'C' -WhatIf
        }
        It 'Should not call Invoke-RemoteOrLocal' { Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Parameter validation' {
        It 'Should reject multi-char DriveLetter' { { New-ShadowCopy -DriveLetter 'CD' -Confirm:$false } | Should -Throw }
        It 'Should reject numeric DriveLetter' { { New-ShadowCopy -DriveLetter '1' -Confirm:$false } | Should -Throw }
    }
}
