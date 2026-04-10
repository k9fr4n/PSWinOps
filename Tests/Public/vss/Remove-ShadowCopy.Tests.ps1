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

Describe 'Remove-ShadowCopy' {

    Context 'ById happy path' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @( @{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; DriveLetter = 'C'; Removed = $true; ErrorMessage = '' } )
            }
            $script:result = Remove-ShadowCopy -ShadowCopyId $script:testShadowId -Confirm:$false
        }
        It 'Should return PSWinOps.ShadowCopyRemoveResult type' { $script:result.PSTypeNames[0] | Should -Be 'PSWinOps.ShadowCopyRemoveResult' }
        It 'Should have Removed true' { $script:result.Removed | Should -BeTrue }
        It 'Should have DriveLetter C' { $script:result.DriveLetter | Should -Be 'C' }
        It 'Should have correct ShadowCopyId' { $script:result.ShadowCopyId | Should -Be $script:testShadowId }
    }

    Context 'ByDrive happy path with multiple shadows' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @(
                    @{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; DriveLetter = 'C'; Removed = $true; ErrorMessage = '' }
                    @{ ShadowCopyId = '{11111111-2222-3333-4444-555555555555}'; DriveLetter = 'C'; Removed = $true; ErrorMessage = '' }
                )
            }
            $script:results = Remove-ShadowCopy -DriveLetter 'C' -Confirm:$false
        }
        It 'Should return multiple results' { $script:results | Should -HaveCount 2 }
        It 'Should have all Removed true' { $script:results | ForEach-Object -Process { $_.Removed | Should -BeTrue } }
    }

    Context 'Pipeline from Get-ShadowCopy' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @( @{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; DriveLetter = 'C'; Removed = $true; ErrorMessage = '' } )
            }
            $script:pipelineInput = @(
                [PSCustomObject]@{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; ComputerName = 'SRV01' }
                [PSCustomObject]@{ ShadowCopyId = '{11111111-2222-3333-4444-555555555555}'; ComputerName = 'SRV02' }
            )
            $script:results = $script:pipelineInput | Remove-ShadowCopy -Confirm:$false
        }
        It 'Should process all piped objects' { $script:results | Should -HaveCount 2 }
        It 'Should call Invoke-RemoteOrLocal for each' { Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly }
    }

    Context 'Shadow copy not found' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @( @{ ShadowCopyId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'; DriveLetter = 'C'; Removed = $false; ErrorMessage = 'Shadow copy not found' } )
            }
            $script:result = Remove-ShadowCopy -ShadowCopyId $script:testShadowId -Confirm:$false
        }
        It 'Should have Removed false' { $script:result.Removed | Should -BeFalse }
        It 'Should have ErrorMessage' { $script:result.ErrorMessage | Should -Not -BeNullOrEmpty }
    }

    Context 'Per-machine failure (exception)' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { throw 'Access denied' }
            $script:result = Remove-ShadowCopy -ShadowCopyId $script:testShadowId -ComputerName 'DEAD01' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable 'script:capturedError'
        }
        It 'Should write error' { $script:capturedError | Should -Not -BeNullOrEmpty }
        It 'Should have Removed false' { $script:result.Removed | Should -BeFalse }
    }

    Context 'WhatIf support' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { @() }
            Remove-ShadowCopy -ShadowCopyId $script:testShadowId -WhatIf
        }
        It 'Should not call Invoke-RemoteOrLocal' { Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Parameter validation' {
        It 'Should reject multi-char DriveLetter' { { Remove-ShadowCopy -DriveLetter 'CD' -Confirm:$false } | Should -Throw }
        It 'Should reject empty ShadowCopyId' { { Remove-ShadowCopy -ShadowCopyId '' -Confirm:$false } | Should -Throw }
    }
}
