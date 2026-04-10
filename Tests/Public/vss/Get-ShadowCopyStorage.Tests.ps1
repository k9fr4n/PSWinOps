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

Describe 'Get-ShadowCopyStorage' {

    BeforeAll {
        $script:mockStorageData = @(
            [PSCustomObject]@{
                DriveLetter    = 'C'
                DeviceID       = '\\?\Volume{abc123}\'
                UsedSpace      = [long]5368709120
                AllocatedSpace = [long]8589934592
                MaxSpace       = [long]10737418240
                SnapshotCount  = 3
            }
        )
    }

    Context 'Happy path - local execution' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockStorageData }
            $script:result = Get-ShadowCopyStorage
        }

        It 'Should return PSWinOps.ShadowCopyStorage type' { $script:result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ShadowCopyStorage' }
        It 'Should set ComputerName to local' { $script:result.ComputerName | Should -Be $env:COMPUTERNAME }
        It 'Should have DriveLetter C' { $script:result.DriveLetter | Should -Be 'C' }
        It 'Should have SnapshotCount 3' { $script:result.SnapshotCount | Should -Be 3 }
        It 'Should calculate UsedSpaceMB' { $script:result.UsedSpaceMB | Should -Be 5120 }
        It 'Should calculate AllocatedSpaceMB' { $script:result.AllocatedSpaceMB | Should -Be 8192 }
        It 'Should calculate MaxSpaceMB' { $script:result.MaxSpaceMB | Should -Be 10240 }
        It 'Should calculate UsedPercent' { $script:result.UsedPercent | Should -Be 50 }
        It 'Should have Timestamp' { $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}' }
    }

    Context 'Unbounded MaxSpace' {
        BeforeAll {
            $script:mockUnbounded = @(
                [PSCustomObject]@{
                    DriveLetter = 'C'; DeviceID = '\\?\Volume{abc123}\'
                    UsedSpace = [long]5368709120; AllocatedSpace = [long]8589934592
                    MaxSpace = [long]-1; SnapshotCount = 3
                }
            )
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockUnbounded }
            $script:result = Get-ShadowCopyStorage
        }
        It 'Should set MaxSpaceMB to Unbounded' { $script:result.MaxSpaceMB | Should -Be 'Unbounded' }
        It 'Should set UsedPercent to 0' { $script:result.UsedPercent | Should -Be 0 }
    }

    Context 'Remote single machine' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockStorageData }
            $script:result = Get-ShadowCopyStorage -ComputerName 'SRV01'
        }
        It 'Should set ComputerName to remote' { $script:result.ComputerName | Should -Be 'SRV01' }
    }

    Context 'Pipeline with multiple computers' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockStorageData }
            $script:result = @('SRV01', 'SRV02') | Get-ShadowCopyStorage
        }
        It 'Should return results for each' { $script:result.Count | Should -BeGreaterOrEqual 2 }
    }

    Context 'Per-machine failure' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { throw 'RPC unavailable' }
            $script:result = Get-ShadowCopyStorage -ComputerName 'SRV01' -ErrorAction SilentlyContinue -ErrorVariable script:capturedError
        }
        It 'Should not throw' { { Get-ShadowCopyStorage -ComputerName 'SRV01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
        It 'Should write error' { $script:capturedError | Should -Not -BeNullOrEmpty }
    }

    Context 'Parameter validation' {
        BeforeAll { $script:cmdInfo = Get-Command -Name 'Get-ShadowCopyStorage' -Module 'PSWinOps' }
        It 'Should accept CN alias' { $script:cmdInfo.Parameters['ComputerName'].Aliases | Should -Contain 'CN' }
        It 'Should reject invalid DriveLetter' { { Get-ShadowCopyStorage -DriveLetter 'ZZ' } | Should -Throw }
    }

    Context 'Scriptblock execution' {
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
                [PSCustomObject]@{ VolumeName = '\\?\Volume{abc123}\' }
                [PSCustomObject]@{ VolumeName = '\\?\Volume{abc123}\' }
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowStorage'
            } -MockWith {
                $script:mockStorage = [PSCustomObject]@{
                    UsedSpace = [long]5368709120; AllocatedSpace = [long]8589934592
                    MaxSpace  = [long]10737418240
                }
                $script:mockVolRef = 'Win32_Volume.DeviceID="\\\\?\Volume{abc123}\\"'
                Add-Member -InputObject $script:mockStorage -MemberType NoteProperty -Name 'Volume' -Value $script:mockVolRef
                return $script:mockStorage
            }
            $script:result = Get-ShadowCopyStorage
        }
        It 'Should return result from scriptblock' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should have DriveLetter C' { $script:result.DriveLetter | Should -Be 'C' }
        It 'Should have SnapshotCount 2' { $script:result.SnapshotCount | Should -Be 2 }
        It 'Should calculate MaxSpaceMB' { $script:result.MaxSpaceMB | Should -Be 10240 }
        It 'Should calculate UsedSpaceMB' { $script:result.UsedSpaceMB | Should -Be 5120 }
        It 'Should calculate UsedPercent' { $script:result.UsedPercent | Should -Be 50 }
    }

    Context 'Scriptblock execution - MaxSpace zero' {
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
            } -MockWith { return $null }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowStorage'
            } -MockWith {
                $script:mockStorage = [PSCustomObject]@{
                    UsedSpace = [long]0; AllocatedSpace = [long]0; MaxSpace = [long]0
                }
                $script:mockVolRef = 'Win32_Volume.DeviceID="\\\\?\Volume{abc123}\\"'
                Add-Member -InputObject $script:mockStorage -MemberType NoteProperty -Name 'Volume' -Value $script:mockVolRef
                return $script:mockStorage
            }
            $script:result = Get-ShadowCopyStorage
        }
        It 'Should return result' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should have MaxSpaceMB 0' { $script:result.MaxSpaceMB | Should -Be 0 }
        It 'Should have UsedPercent 0 avoiding division by zero' { $script:result.UsedPercent | Should -Be 0 }
        It 'Should have SnapshotCount 0' { $script:result.SnapshotCount | Should -Be 0 }
    }

    Context 'Scriptblock execution - drive letter filter' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_Volume'
            } -MockWith {
                [PSCustomObject]@{ DeviceID = '\\?\Volume{abc123}\'; DriveLetter = 'C:' }
                [PSCustomObject]@{ DeviceID = '\\?\Volume{def456}\'; DriveLetter = 'D:' }
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowCopy'
            } -MockWith {
                [PSCustomObject]@{ VolumeName = '\\?\Volume{abc123}\' }
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowStorage'
            } -MockWith {
                $script:storageC = [PSCustomObject]@{
                    UsedSpace = [long]1048576; AllocatedSpace = [long]2097152; MaxSpace = [long]5242880
                }
                Add-Member -InputObject $script:storageC -MemberType NoteProperty -Name 'Volume' -Value 'Win32_Volume.DeviceID="\\\\?\Volume{abc123}\\"'
                $script:storageD = [PSCustomObject]@{
                    UsedSpace = [long]524288; AllocatedSpace = [long]1048576; MaxSpace = [long]2621440
                }
                Add-Member -InputObject $script:storageD -MemberType NoteProperty -Name 'Volume' -Value 'Win32_Volume.DeviceID="\\\\?\Volume{def456}\\"'
                return @($script:storageC, $script:storageD)
            }
            $script:result = Get-ShadowCopyStorage -DriveLetter 'C'
        }
        It 'Should return only one result for filtered drive' { @($script:result).Count | Should -Be 1 }
        It 'Should have DriveLetter C' { $script:result.DriveLetter | Should -Be 'C' }
    }

    Context 'Scriptblock execution - unresolved volume' {
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
            } -MockWith { return $null }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -ParameterFilter {
                $ClassName -eq 'Win32_ShadowStorage'
            } -MockWith {
                $script:mockStorage = [PSCustomObject]@{
                    UsedSpace = [long]1048576; AllocatedSpace = [long]2097152; MaxSpace = [long]5242880
                }
                Add-Member -InputObject $script:mockStorage -MemberType NoteProperty -Name 'Volume' -Value 'Win32_Volume.DeviceID="\\\\?\Volume{unknown999}\\"'
                return $script:mockStorage
            }
            $script:result = Get-ShadowCopyStorage
        }
        It 'Should return result' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should have DriveLetter as question mark fallback' { $script:result.DriveLetter | Should -Be '?' }
        It 'Should have SnapshotCount 0 for unresolved volume' { $script:result.SnapshotCount | Should -Be 0 }
    }
}
