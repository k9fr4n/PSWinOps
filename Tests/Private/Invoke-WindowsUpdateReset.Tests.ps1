#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
    $script:mod        = Get-Module -Name $script:ModuleName
}

Describe 'Invoke-WindowsUpdateReset' {

    Context 'Happy path - services running, DLLs present, no network reset' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should return a PSCustomObject' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'Should have Status Succeeded' {
            $script:result.Status | Should -Be 'Succeeded'
        }

        It 'Should have empty Failures list' {
            $script:result.Failures.Count | Should -Be 0
        }

        It 'Should have 4 services stopped' {
            $script:result.ServicesStopped.Count | Should -Be 4
        }

        It 'Should have 4 services started' {
            $script:result.ServicesStarted.Count | Should -Be 4
        }

        It 'Should have DllsReregistered equal to 36' {
            $script:result.DllsReregistered | Should -Be 36
        }

        It 'Should have NetworkResetPerformed false' {
            $script:result.NetworkResetPerformed | Should -Be $false
        }

        It 'Should have RebootRequired false' {
            $script:result.RebootRequired | Should -Be $false
        }
    }

    Context 'Network reset - all commands succeed' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $true
            }
        }

        It 'Should have NetworkResetPerformed true' {
            $script:result.NetworkResetPerformed | Should -Be $true
        }

        It 'Should have RebootRequired true' {
            $script:result.RebootRequired | Should -Be $true
        }

        It 'Should have Status Succeeded' {
            $script:result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'Network reset - winsock fails' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 1; Output = 'error' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $true
            }
        }

        It 'Should have NetworkResetPerformed false when winsock fails' {
            $script:result.NetworkResetPerformed | Should -Be $false
        }

        It 'Should have failures recorded' {
            $script:result.Failures.Count | Should -BeGreaterThan 0
        }

        It 'Should have Status PartialSuccess' {
            $script:result.Status | Should -Be 'PartialSuccess'
        }
    }

    Context 'Service stop fails - failure recorded, processing continues' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith { throw 'access denied' }
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should record stop failures' {
            $script:result.Failures | Where-Object { $_ -match 'Stop service' } |
                Should -Not -BeNullOrEmpty
        }

        It 'Should have Status PartialSuccess' {
            $script:result.Status | Should -Be 'PartialSuccess'
        }

        It 'Should have empty ServicesStopped list' {
            $script:result.ServicesStopped.Count | Should -Be 0
        }
    }

    Context 'Service start fails - failure recorded' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith { throw 'start failed' }
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should record start failures' {
            $script:result.Failures | Where-Object { $_ -match 'Start service' } |
                Should -Not -BeNullOrEmpty
        }

        It 'Should have Status PartialSuccess' {
            $script:result.Status | Should -Be 'PartialSuccess'
        }
    }

    Context 'All DLL paths absent - DllsFailed populated, PartialSuccess' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                # Only .exe present (sc.exe, wuauclt.exe, etc.) — .dll absent
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should have DllsFailed equal to 36' {
            $script:result.DllsFailed | Should -Be 36
        }

        It 'Should have Status PartialSuccess' {
            $script:result.Status | Should -Be 'PartialSuccess'
        }

        It 'Should report DLL not found in Failures' {
            $script:result.Failures | Where-Object { $_ -match 'DLL not found' } |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'Folders absent - SoftwareDistribution and Catroot2 skipped gracefully' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Stopped' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should report SoftwareDistributionBackup as skipped' {
            $script:result.SoftwareDistributionBackup | Should -Match 'Skipped'
        }

        It 'Should report Catroot2Backup as skipped' {
            $script:result.Catroot2Backup | Should -Match 'Skipped'
        }

        It 'Should have empty ServicesStopped (services already stopped)' {
            $script:result.ServicesStopped.Count | Should -Be 0
        }
    }

    Context 'wuauclt absent, usoclient present and succeeds' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                # wuauclt absent, usoclient + sc.exe present, DLLs present
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$') -or ($t -match 'usoclient\.exe') -or ($t -match 'sc\.exe')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should add a note about wuauclt not found' {
            $script:result.Notes | Where-Object { $_ -match 'wuauclt' } | Should -Not -BeNullOrEmpty
        }

        It 'Should add a note about usoclient detection' {
            $script:result.Notes | Where-Object { $_ -match 'usoclient' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'wuauclt present but fails, usoclient fallback triggered' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    param($FilePath, $ArgumentList)
                    if ($FilePath -match 'wuauclt') {
                        return [PSCustomObject]@{ ExitCode = 1; Output = 'error' }
                    }
                    return [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should add a note about usoclient fallback' {
            $script:result.Notes | Where-Object { $_ -match 'usoclient fallback' } | Should -Not -BeNullOrEmpty
        }

        It 'Should add a note about usoclient StartScan triggered' {
            $script:result.Notes | Where-Object { $_ -match 'usoclient StartScan' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'SoftwareDistribution and Catroot2 folders present - renamed successfully' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                # Folders and DLLs/exes exist; .bak files do not
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$') -or
                           ($t -match 'SoftwareDistribution$') -or
                           ($t -match 'Catroot2$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should have SoftwareDistributionBackup set (not skipped)' {
            $script:result.SoftwareDistributionBackup | Should -Not -Match 'Skipped'
            $script:result.SoftwareDistributionBackup | Should -Not -BeNullOrEmpty
        }

        It 'Should have Catroot2Backup set (not skipped)' {
            $script:result.Catroot2Backup | Should -Not -Match 'Skipped'
            $script:result.Catroot2Backup | Should -Not -BeNullOrEmpty
        }

        It 'Should have Status Succeeded' {
            $script:result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'SoftwareDistribution backup already exists - removed then renamed' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                # Folders, .bak files, DLLs/exes all exist
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$') -or
                           ($t -match 'SoftwareDistribution') -or
                           ($t -match 'Catroot2')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should have SoftwareDistributionBackup set' {
            $script:result.SoftwareDistributionBackup | Should -Not -BeNullOrEmpty
        }

        It 'Should have Status Succeeded' {
            $script:result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'Neither wuauclt nor usoclient present' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                # DLLs and sc.exe only - no wuauclt, no usoclient
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$') -or ($t -match 'sc\.exe')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should add a note that neither wuauclt nor usoclient was found' {
            $script:result.Notes | Where-Object { $_ -match 'Neither' } | Should -Not -BeNullOrEmpty
        }

        It 'Should have Status Succeeded (detection trigger is non-fatal)' {
            $script:result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'qmgr files exist - deleted successfully' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Get-ChildItem'  -MockWith {
                    @(
                        [PSCustomObject]@{ FullName = 'C:\ProgramData\Microsoft\Network\Downloader\qmgr0.dat' }
                        [PSCustomObject]@{ FullName = 'C:\ProgramData\Microsoft\Network\Downloader\qmgr1.dat' }
                    )
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    # qmgr folder and DLLs/exes exist; no WU log; no SD/Catroot2
                    return ($t -match '\.dll$|\.exe$') -or ($t -match 'Downloader$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should have QmgrFilesDeleted equal to 2' {
            $script:result.QmgrFilesDeleted | Should -Be 2
        }

        It 'Should have Status Succeeded' {
            $script:result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'WindowsUpdate.log exists - deleted' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    # DLLs, exes, and WindowsUpdate.log exist
                    return ($t -match '\.dll$|\.exe$') -or ($t -match 'WindowsUpdate\.log$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should have Status Succeeded' {
            $script:result.Status | Should -Be 'Succeeded'
        }

        It 'Should have no failures' {
            $script:result.Failures.Count | Should -Be 0
        }
    }

    Context 'regsvr32 fails for a present DLL - DllsFailed incremented' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    param($FilePath, $ArgumentList)
                    if ($FilePath -match 'regsvr32') {
                        return [PSCustomObject]@{ ExitCode = 5; Output = 'Access denied' }
                    }
                    return [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should have DllsFailed greater than zero' {
            $script:result.DllsFailed | Should -BeGreaterThan 0
        }

        It 'Should have Status PartialSuccess' {
            $script:result.Status | Should -Be 'PartialSuccess'
        }

        It 'Should record regsvr32 failure in Failures' {
            $script:result.Failures | Where-Object { $_ -match 'regsvr32' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Return type validation' {

        BeforeAll {
            $script:result = & $script:mod {
                Mock -CommandName 'Get-Service'    -MockWith { [PSCustomObject]@{ Status = 'Running' } }
                Mock -CommandName 'Stop-Service'   -MockWith {}
                Mock -CommandName 'Start-Sleep'    -MockWith {}
                Mock -CommandName 'Start-Service'  -MockWith {}
                Mock -CommandName 'Get-ChildItem'  -MockWith { @() }
                Mock -CommandName 'Remove-Item'    -MockWith {}
                Mock -CommandName 'Rename-Item'    -MockWith {}
                Mock -CommandName 'Invoke-NativeCommand' -MockWith {
                    [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                Mock -CommandName 'Test-Path' -MockWith {
                    param($LiteralPath, $Path, $PathType)
                    $t = if ($LiteralPath) { $LiteralPath } else { $Path }
                    return ($t -match '\.dll$|\.exe$')
                }
                Invoke-WindowsUpdateReset -DoNetworkReset $false
            }
        }

        It 'Should return exactly one object' {
            @($script:result).Count | Should -Be 1
        }

        It 'Should have all 12 expected properties' {
            $expected = @(
                'Status', 'ServicesStopped', 'ServicesStarted',
                'SoftwareDistributionBackup', 'Catroot2Backup',
                'QmgrFilesDeleted', 'DllsReregistered', 'DllsFailed',
                'NetworkResetPerformed', 'RebootRequired', 'Failures', 'Notes'
            )
            foreach ($prop in $expected) {
                $script:result.PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }
}
