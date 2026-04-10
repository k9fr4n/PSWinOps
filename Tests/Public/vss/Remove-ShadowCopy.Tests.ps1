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

    Context 'Scriptblock execution - ById shadow resolution' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowCopy'
            } -MockWith {
                [PSCustomObject]@{
                    ID = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'
                    VolumeName = '\\?\Volume{abc123}\'
                }
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_Volume'
            } -MockWith {
                [PSCustomObject]@{ DeviceID = '\\?\Volume{abc123}\'; DriveLetter = 'C:' }
            }
            Mock -CommandName 'Remove-CimInstance' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Remove-ShadowCopy -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -Confirm:$false
        }
        It 'Should return a result' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should have correct ShadowCopyId' { $script:result.ShadowCopyId | Should -Be '{AB12CD34-EF56-7890-AB12-CD34EF567890}' }
        It 'Should resolve DriveLetter from volume' { $script:result.DriveLetter | Should -Be 'C' }
    }

    Context 'Scriptblock execution - ById shadow not found' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowCopy'
            } -MockWith {
                [PSCustomObject]@{
                    ID = '{DIFFERENT-GUID-NOT-MATCHING-AT-ALL}'
                    VolumeName = '\\?\Volume{abc123}\'
                }
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_Volume'
            } -MockWith {
                [PSCustomObject]@{ DeviceID = '\\?\Volume{abc123}\'; DriveLetter = 'C:' }
            }
            Mock -CommandName 'Remove-CimInstance' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Remove-ShadowCopy -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -Confirm:$false
        }
        It 'Should have Removed false' { $script:result.Removed | Should -BeFalse }
        It 'Should have ErrorMessage about not found' { $script:result.ErrorMessage | Should -BeLike '*not found*' }
    }

    Context 'Scriptblock execution - ByDrive shadow resolution' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_Volume'
            } -MockWith {
                [PSCustomObject]@{ DeviceID = '\\?\Volume{abc123}\'; DriveLetter = 'C:' }
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowCopy'
            } -MockWith {
                [PSCustomObject]@{
                    ID = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'
                    VolumeName = '\\?\Volume{abc123}\'; InstallDate = (Get-Date).AddDays(-10)
                }
            }
            Mock -CommandName 'Remove-CimInstance' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Remove-ShadowCopy -DriveLetter 'C' -Confirm:$false
        }
        It 'Should return a result' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should have correct ShadowCopyId' { $script:result.ShadowCopyId | Should -Be '{AB12CD34-EF56-7890-AB12-CD34EF567890}' }
        It 'Should resolve DriveLetter' { $script:result.DriveLetter | Should -Be 'C' }
    }

    Context 'Scriptblock execution - ByDrive volume not found' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_Volume'
            } -MockWith { return $null }
            Mock -CommandName 'Remove-CimInstance' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Remove-ShadowCopy -DriveLetter 'X' -Confirm:$false
        }
        It 'Should have Removed false' { $script:result.Removed | Should -BeFalse }
        It 'Should have ErrorMessage about volume not found' { $script:result.ErrorMessage | Should -BeLike '*Volume not found*' }
    }

    Context 'Scriptblock execution - ByDrive no matching shadows' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_Volume'
            } -MockWith {
                [PSCustomObject]@{ DeviceID = '\\?\Volume{abc123}\'; DriveLetter = 'C:' }
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowCopy'
            } -MockWith {
                [PSCustomObject]@{
                    ID = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'
                    VolumeName = '\\?\Volume{other999}\'; InstallDate = (Get-Date).AddDays(-5)
                }
            }
            Mock -CommandName 'Remove-CimInstance' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Remove-ShadowCopy -DriveLetter 'C' -Confirm:$false
        }
        It 'Should have Removed false' { $script:result.Removed | Should -BeFalse }
        It 'Should have ErrorMessage about no matching shadows' { $script:result.ErrorMessage | Should -BeLike '*No matching*' }
    }

    Context 'Scriptblock execution - ByDrive OlderThanDays filter' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_Volume'
            } -MockWith {
                [PSCustomObject]@{ DeviceID = '\\?\Volume{abc123}\'; DriveLetter = 'C:' }
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowCopy'
            } -MockWith {
                [PSCustomObject]@{
                    ID = '{OLD-SHADOW-45-DAYS}'; VolumeName = '\\?\Volume{abc123}\'
                    InstallDate = (Get-Date).AddDays(-45)
                }
                [PSCustomObject]@{
                    ID = '{NEW-SHADOW-5-DAYS}'; VolumeName = '\\?\Volume{abc123}\'
                    InstallDate = (Get-Date).AddDays(-5)
                }
            }
            Mock -CommandName 'Remove-CimInstance' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = Remove-ShadowCopy -DriveLetter 'C' -OlderThanDays 30 -Confirm:$false
        }
        It 'Should return only one result for the old shadow' { @($script:result).Count | Should -Be 1 }
        It 'Should have correct ShadowCopyId for old shadow' { $script:result.ShadowCopyId | Should -Be '{OLD-SHADOW-45-DAYS}' }
        It 'Should have DriveLetter C' { $script:result.DriveLetter | Should -Be 'C' }
    }

    Context 'ByDrive with OlderThanDays - process block path' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @( @{ ShadowCopyId = '{OLD-GUID}'; DriveLetter = 'C'; Removed = $true; ErrorMessage = '' } )
            }
            $script:result = Remove-ShadowCopy -DriveLetter 'C' -OlderThanDays 60 -Confirm:$false
        }
        It 'Should have Removed true' { $script:result.Removed | Should -BeTrue }
        It 'Should have DriveLetter C' { $script:result.DriveLetter | Should -Be 'C' }
        It 'Should have valid Timestamp' { $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}' }
    }
}
