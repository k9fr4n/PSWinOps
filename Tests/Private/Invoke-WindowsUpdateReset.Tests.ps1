#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'

    # Helper to invoke a private function via the module scope
    function script:Invoke-Private {
        param([string]$Name, [hashtable]$Params = @{})
        & (Get-Module -Name $script:ModuleName) {
            param($n, $p)
            & $n @p
        } $Name $Params
    }

    # Shared mock return values
    $script:mockSvcRunning = [PSCustomObject]@{ Status = 'Running' }
    $script:mockSvcStopped = [PSCustomObject]@{ Status = 'Stopped' }
    $script:mockNativeOk   = [PSCustomObject]@{ ExitCode = 0; Output = '' }
    $script:mockNativeFail = [PSCustomObject]@{ ExitCode = 1; Output = 'error' }
}

Describe 'Invoke-WindowsUpdateReset' {

    Context 'Happy path - all services present, all DLLs present, no network reset' {

        BeforeAll {
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcRunning }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Test-Path'      -ModuleName $script:ModuleName -MockWith { $false }
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith {
                $script:mockNativeOk
            }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $false }
        }

        It 'Should return a PSCustomObject' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'Should have Status Succeeded when no failures' {
            $script:result.Status | Should -Be 'Succeeded'
        }

        It 'Should have empty Failures list' {
            $script:result.Failures.Count | Should -Be 0
        }

        It 'Should have NetworkResetPerformed false' {
            $script:result.NetworkResetPerformed | Should -Be $false
        }

        It 'Should have RebootRequired false' {
            $script:result.RebootRequired | Should -Be $false
        }

        It 'Should call Stop-Service for running services' {
            Should -Invoke -CommandName 'Stop-Service' -ModuleName $script:ModuleName -Times 4 -Exactly
        }

        It 'Should call Start-Service for services' {
            Should -Invoke -CommandName 'Start-Service' -ModuleName $script:ModuleName -Times 4 -Exactly
        }
    }

    Context 'Network reset path - DoNetworkReset = true, winsock succeeds' {

        BeforeAll {
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcRunning }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Test-Path'      -ModuleName $script:ModuleName -MockWith { $false }
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith {
                $script:mockNativeOk
            }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $true }
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

    Context 'Network reset path - winsock fails' {

        BeforeAll {
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcRunning }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Test-Path'      -ModuleName $script:ModuleName -MockWith { $false }
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith {
                $script:mockNativeFail
            }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $true }
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
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcRunning }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith { throw 'access denied' }
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Test-Path'      -ModuleName $script:ModuleName -MockWith { $false }
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith { $script:mockNativeOk }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $false }
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
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcRunning }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Test-Path'      -ModuleName $script:ModuleName -MockWith { $false }
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith { throw 'start failed' }
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith { $script:mockNativeOk }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $false }
        }

        It 'Should record start failures' {
            $script:result.Failures | Where-Object { $_ -match 'Start service' } |
                Should -Not -BeNullOrEmpty
        }

        It 'Should have Status PartialSuccess' {
            $script:result.Status | Should -Be 'PartialSuccess'
        }
    }

    Context 'DLL missing - counted as DllsFailed, non-fatal' {

        BeforeAll {
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcRunning }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            # Test-Path returns false for ALL paths (DLLs not present, folders not present)
            Mock -CommandName 'Test-Path'      -ModuleName $script:ModuleName -MockWith { $false }
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith { $script:mockNativeOk }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $false }
        }

        It 'Should have DllsFailed greater than zero when DLLs missing' {
            $script:result.DllsFailed | Should -BeGreaterThan 0
        }

        It 'Should have Status PartialSuccess due to missing DLLs' {
            $script:result.Status | Should -Be 'PartialSuccess'
        }

        It 'Should report DLL not found in Failures' {
            $script:result.Failures | Where-Object { $_ -match 'DLL not found' } |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'Folders absent - SoftwareDistribution and Catroot2 skipped gracefully' {

        BeforeAll {
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcStopped }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Test-Path'      -ModuleName $script:ModuleName -MockWith { $false }
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith { $script:mockNativeOk }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $false }
        }

        It 'Should report SoftwareDistributionBackup as skipped' {
            $script:result.SoftwareDistributionBackup | Should -Match 'Skipped'
        }

        It 'Should report Catroot2Backup as skipped' {
            $script:result.Catroot2Backup | Should -Match 'Skipped'
        }

        It 'Should not call Stop-Service for already stopped services' {
            Should -Invoke -CommandName 'Stop-Service' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    Context 'wuauclt absent, usoclient present and succeeds' {

        BeforeAll {
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcRunning }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith { $script:mockNativeOk }
            # wuauclt absent, usoclient present
            Mock -CommandName 'Test-Path' -ModuleName $script:ModuleName -MockWith {
                param($LiteralPath, $Path, $PathType)
                $target = if ($LiteralPath) { $LiteralPath } else { $Path }
                return ($target -notmatch 'wuauclt\.exe') -and ($target -match 'usoclient\.exe')
            }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $false }
        }

        It 'Should add a note about wuauclt not found' {
            $script:result.Notes | Where-Object { $_ -match 'wuauclt' } | Should -Not -BeNullOrEmpty
        }

        It 'Should add a note about usoclient detection' {
            $script:result.Notes | Where-Object { $_ -match 'usoclient' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'wuauclt present but fails, usoclient fallback used' {

        BeforeAll {
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcRunning }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            # wuauclt fails, usoclient succeeds
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith {
                param($FilePath, $ArgumentList)
                if ($FilePath -match 'wuauclt') { return $script:mockNativeFail }
                return $script:mockNativeOk
            }
            Mock -CommandName 'Test-Path' -ModuleName $script:ModuleName -MockWith { $false }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $false }
        }

        It 'Should add a note about wuauclt failure and usoclient fallback' {
            $script:result.Notes | Where-Object { $_ -match 'usoclient fallback' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Return type validation' {

        BeforeAll {
            Mock -CommandName 'Get-Service'    -ModuleName $script:ModuleName -MockWith { $script:mockSvcRunning }
            Mock -CommandName 'Stop-Service'   -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Sleep'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Start-Service'  -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Get-ChildItem'  -ModuleName $script:ModuleName -MockWith { @() }
            Mock -CommandName 'Remove-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Rename-Item'    -ModuleName $script:ModuleName -MockWith {}
            Mock -CommandName 'Test-Path'      -ModuleName $script:ModuleName -MockWith { $false }
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -MockWith { $script:mockNativeOk }

            $script:result = script:Invoke-Private -Name 'Invoke-WindowsUpdateReset' -Params @{ DoNetworkReset = $false }
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
