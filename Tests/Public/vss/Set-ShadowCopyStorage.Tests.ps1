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

Describe 'Set-ShadowCopyStorage' {

    Context 'BySize happy path' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ DriveLetter = 'C'; PreviousMaxSpaceBytes = 10737418240; NewMaxSizeArg = 20480; ExitCode = 0; Output = 'Successfully resized the shadow copy storage association.' }
            }
            $script:result = Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB 20480 -Confirm:$false
        }
        It 'Should return PSWinOps.ShadowCopyStorageResult type' { $script:result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ShadowCopyStorageResult' }
        It 'Should have Success true' { $script:result.Success | Should -BeTrue }
        It 'Should calculate PreviousMaxSpaceMB' { $script:result.PreviousMaxSpaceMB | Should -Be 10240 }
        It 'Should set NewMaxSpaceMB to 20480' { $script:result.NewMaxSpaceMB | Should -Be 20480 }
        It 'Should contain success message' { $script:result.Message | Should -BeLike '*Successfully*' }
        It 'Should set ComputerName to local' { $script:result.ComputerName | Should -Be $env:COMPUTERNAME }
    }

    Context 'Unbounded parameter set' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ DriveLetter = 'D'; PreviousMaxSpaceBytes = 5368709120; NewMaxSizeArg = -1; ExitCode = 0; Output = 'Successfully resized.' }
            }
            $script:result = Set-ShadowCopyStorage -DriveLetter 'D' -Unbounded -Confirm:$false
        }
        It 'Should have Success true' { $script:result.Success | Should -BeTrue }
        It 'Should set NewMaxSpaceMB to Unbounded' { $script:result.NewMaxSpaceMB | Should -Be 'Unbounded' }
    }

    Context 'Remote execution' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ DriveLetter = 'C'; PreviousMaxSpaceBytes = 10737418240; NewMaxSizeArg = 20480; ExitCode = 0; Output = 'Success.' }
            }
            $script:result = Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB 20480 -ComputerName 'SRV01' -Confirm:$false
        }
        It 'Should set ComputerName to SRV01' { $script:result.ComputerName | Should -Be 'SRV01' }
        It 'Should have Success true' { $script:result.Success | Should -BeTrue }
    }

    Context 'Pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ DriveLetter = 'C'; PreviousMaxSpaceBytes = 10737418240; NewMaxSizeArg = 20480; ExitCode = 0; Output = 'Success.' }
            }
            $script:results = 'SRV01', 'SRV02' | Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB 20480 -Confirm:$false
        }
        It 'Should return two results' { $script:results | Should -HaveCount 2 }
        It 'Should call Invoke-RemoteOrLocal twice' { Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly }
    }

    Context 'vssadmin failure' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{ DriveLetter = 'C'; PreviousMaxSpaceBytes = 10737418240; NewMaxSizeArg = 20480; ExitCode = 1; Output = 'Error: Access denied.' }
            }
            $script:result = Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB 20480 -Confirm:$false
        }
        It 'Should have Success false' { $script:result.Success | Should -BeFalse }
    }

    Context 'Per-machine failure' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed.' }
            $script:result = Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB 20480 -ComputerName 'SRV01' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:capturedError
        }
        It 'Should write error' { $script:capturedError | Should -Not -BeNullOrEmpty }
        It 'Should have Success false' { $script:result.Success | Should -BeFalse }
    }

    Context 'WhatIf support' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { @{} }
            Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB 20480 -WhatIf
        }
        It 'Should not call Invoke-RemoteOrLocal' { Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Parameter validation' {
        It 'Should reject multi-char DriveLetter' { { Set-ShadowCopyStorage -DriveLetter 'CC' -MaxSizeMB 1024 -Confirm:$false } | Should -Throw }
        It 'Should reject MaxSizeMB of zero' { { Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB 0 -Confirm:$false } | Should -Throw }
        It 'Should reject negative MaxSizeMB' { { Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB -1 -Confirm:$false } | Should -Throw }
    }
}
