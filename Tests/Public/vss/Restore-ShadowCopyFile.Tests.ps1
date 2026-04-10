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
}

Describe 'Restore-ShadowCopyFile' {

    Context 'Happy path' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; SourcePath = 'Data\report.xlsx'; DestinationPath = 'C:\Restore\report.xlsx'; Restored = $true; SizeBytes = [long]102400; ErrorMessage = '' }
            }
            $script:result = Restore-ShadowCopyFile -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -SourcePath 'Data\report.xlsx' -DestinationPath 'C:\Restore\report.xlsx' -Confirm:$false
        }
        It 'Should return PSWinOps.ShadowCopyRestoreResult type' { $script:result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ShadowCopyRestoreResult' }
        It 'Should have Restored true' { $script:result.Restored | Should -BeTrue }
        It 'Should set SizeBytes to 102400' { $script:result.SizeBytes | Should -Be 102400 }
        It 'Should calculate SizeMB' { $script:result.SizeMB | Should -Be 0.1 }
        It 'Should have empty ErrorMessage' { $script:result.ErrorMessage | Should -BeNullOrEmpty }
        It 'Should set ComputerName to local' { $script:result.ComputerName | Should -Be $env:COMPUTERNAME }
    }

    Context 'Shadow copy not found' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; SourcePath = 'Data\report.xlsx'; DestinationPath = 'C:\Restore\report.xlsx'; Restored = $false; SizeBytes = [long]0; ErrorMessage = 'Shadow copy not found' }
            }
            $script:result = Restore-ShadowCopyFile -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -SourcePath 'Data\report.xlsx' -DestinationPath 'C:\Restore\report.xlsx' -Confirm:$false
        }
        It 'Should have Restored false' { $script:result.Restored | Should -BeFalse }
        It 'Should have ErrorMessage' { $script:result.ErrorMessage | Should -BeLike '*not found*' }
    }

    Context 'Destination exists without Force' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; SourcePath = 'Data\report.xlsx'; DestinationPath = 'C:\Restore\report.xlsx'; Restored = $false; SizeBytes = [long]0; ErrorMessage = 'Destination already exists. Use -Force to overwrite.' }
            }
            $script:result = Restore-ShadowCopyFile -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -SourcePath 'Data\report.xlsx' -DestinationPath 'C:\Restore\report.xlsx' -Confirm:$false
        }
        It 'Should have Restored false' { $script:result.Restored | Should -BeFalse }
        It 'Should contain already exists' { $script:result.ErrorMessage | Should -BeLike '*already exists*' }
    }

    Context 'Remote execution' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; SourcePath = 'Data\report.xlsx'; DestinationPath = 'C:\Restore\report.xlsx'; Restored = $true; SizeBytes = [long]102400; ErrorMessage = '' }
            }
            $script:result = Restore-ShadowCopyFile -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -SourcePath 'Data\report.xlsx' -DestinationPath 'C:\Restore\report.xlsx' -ComputerName 'SRV01' -Confirm:$false
        }
        It 'Should set ComputerName to SRV01' { $script:result.ComputerName | Should -Be 'SRV01' }
        It 'Should have Restored true' { $script:result.Restored | Should -BeTrue }
    }

    Context 'Pipeline from Get-ShadowCopy' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; SourcePath = 'Data\report.xlsx'; DestinationPath = 'C:\Restore\report.xlsx'; Restored = $true; SizeBytes = [long]102400; ErrorMessage = '' }
            }
            $script:pipelineInput = [PSCustomObject]@{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; ComputerName = 'SRV01' }
            $script:result = $script:pipelineInput | Restore-ShadowCopyFile -SourcePath 'Data\report.xlsx' -DestinationPath 'C:\Restore\report.xlsx' -Confirm:$false
        }
        It 'Should set ComputerName from pipeline' { $script:result.ComputerName | Should -Be 'SRV01' }
        It 'Should have Restored true' { $script:result.Restored | Should -BeTrue }
    }

    Context 'Per-machine failure' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { throw 'WinRM failed.' }
            $script:result = Restore-ShadowCopyFile -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -SourcePath 'Data\report.xlsx' -DestinationPath 'C:\Restore\report.xlsx' -ComputerName 'SRV01' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:capturedError
        }
        It 'Should write error' { $script:capturedError | Should -Not -BeNullOrEmpty }
        It 'Should have Restored false' { $script:result.Restored | Should -BeFalse }
    }

    Context 'WhatIf support' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { @{} }
            Restore-ShadowCopyFile -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -SourcePath 'Data\report.xlsx' -DestinationPath 'C:\Restore\report.xlsx' -WhatIf
        }
        It 'Should not call Invoke-RemoteOrLocal' { Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Parameter validation' {
        It 'Should reject empty ShadowCopyId' { { Restore-ShadowCopyFile -ShadowCopyId '' -SourcePath 'test' -DestinationPath 'test' -Confirm:$false } | Should -Throw }
        It 'Should reject empty SourcePath' { { Restore-ShadowCopyFile -ShadowCopyId '{id}' -SourcePath '' -DestinationPath 'test' -Confirm:$false } | Should -Throw }
        It 'Should reject empty DestinationPath' { { Restore-ShadowCopyFile -ShadowCopyId '{id}' -SourcePath 'test' -DestinationPath '' -Confirm:$false } | Should -Throw }
    }
}
