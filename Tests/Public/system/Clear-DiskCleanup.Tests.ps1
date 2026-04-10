#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Clear-DiskCleanup' {

    BeforeAll {
        $script:mockCleanResult = @{
            Category       = 'TempFiles'
            FilesRemoved   = 15
            FilesSkipped   = 2
            SpaceRecovered = [long]3145728
            Errors         = @()
        }

        $script:mockCleanResultWithErrors = @{
            Category       = 'WindowsUpdate'
            FilesRemoved   = 5
            FilesSkipped   = 3
            SpaceRecovered = [long]1048576
            Errors         = @('File in use: C:\Windows\SoftwareDistribution\Download\locked.cab')
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should reject empty ComputerName' -Test {
            { Clear-DiskCleanup -ComputerName '' -Force } | Should -Throw
        }

        It -Name 'Should reject null ComputerName' -Test {
            { Clear-DiskCleanup -ComputerName $null -Force } | Should -Throw
        }

        It -Name 'Should reject invalid Category' -Test {
            { Clear-DiskCleanup -Category 'InvalidCategory' -Force } | Should -Throw
        }

        It -Name 'Should reject OlderThanDays below 1' -Test {
            { Clear-DiskCleanup -OlderThanDays 0 -Force } | Should -Throw
        }

        It -Name 'Should reject OlderThanDays above 3650' -Test {
            { Clear-DiskCleanup -OlderThanDays 3651 -Force } | Should -Throw
        }
    }

    Context 'Happy path - local single category' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCleanResult
            }
            $script:results = @(Clear-DiskCleanup -Category 'TempFiles' -Force)
        }

        It -Name 'Should return PSWinOps.DiskCleanupResult type' -Test {
            $script:results[0].PSObject.TypeNames | Should -Contain 'PSWinOps.DiskCleanupResult'
        }

        It -Name 'Should return one result for single category' -Test {
            $script:results | Should -HaveCount 1
        }

        It -Name 'Should set Category to TempFiles' -Test {
            $script:results[0].Category | Should -Be 'TempFiles'
        }

        It -Name 'Should set ComputerName to local machine' -Test {
            $script:results[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should have FilesRemoved 15' -Test {
            $script:results[0].FilesRemoved | Should -Be 15
        }

        It -Name 'Should have FilesSkipped 2' -Test {
            $script:results[0].FilesSkipped | Should -Be 2
        }

        It -Name 'Should have SpaceRecoveredBytes as long' -Test {
            $script:results[0].SpaceRecoveredBytes | Should -Be 3145728
        }

        It -Name 'Should calculate SpaceRecoveredMB' -Test {
            $script:results[0].SpaceRecoveredMB | Should -Be ([math]::Round(3145728 / 1MB, 2))
        }

        It -Name 'Should have empty Errors array' -Test {
            $script:results[0].Errors | Should -HaveCount 0
        }

        It -Name 'Should have a valid Timestamp' -Test {
            $script:results[0].Timestamp | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProps = @('ComputerName', 'Category', 'FilesRemoved', 'FilesSkipped', 'SpaceRecoveredBytes', 'SpaceRecoveredMB', 'Errors', 'Timestamp')
            foreach ($prop in $expectedProps) {
                $script:results[0].PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }

    Context 'Result with errors' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCleanResultWithErrors
            }
            $script:errResult = @(Clear-DiskCleanup -Category 'WindowsUpdate' -Force)
        }

        It -Name 'Should contain error messages' -Test {
            $script:errResult[0].Errors | Should -HaveCount 1
        }

        It -Name 'Should have FilesRemoved 5' -Test {
            $script:errResult[0].FilesRemoved | Should -Be 5
        }

        It -Name 'Should have FilesSkipped 3' -Test {
            $script:errResult[0].FilesSkipped | Should -Be 3
        }
    }

    Context 'ShouldProcess - WhatIf' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCleanResult
            }
        }

        It -Name 'Should not produce output with WhatIf' -Test {
            $whatIfResult = @(Clear-DiskCleanup -Category 'TempFiles' -WhatIf)
            $whatIfResult | Should -HaveCount 0
        }
    }

    Context 'All categories expansion' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return @{
                    Category       = $ArgumentList[0]
                    FilesRemoved   = 1
                    FilesSkipped   = 0
                    SpaceRecovered = [long]1024
                    Errors         = @()
                }
            }
            $script:allResults = @(Clear-DiskCleanup -Category 'All' -Force)
        }

        It -Name 'Should return 8 results for all categories' -Test {
            $script:allResults | Should -HaveCount 8
        }

        It -Name 'Should include every category' -Test {
            $cats = $script:allResults.Category | Sort-Object
            $expected = @('BrowserCache', 'CrashDumps', 'OldLogs', 'RecycleBin', 'TempFiles', 'ThumbnailCache', 'WindowsOld', 'WindowsUpdate')
            $cats | Should -Be $expected
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCleanResult
            }
            $script:remoteResult = @(Clear-DiskCleanup -ComputerName 'SRV01' -Category 'TempFiles' -Force)
        }

        It -Name 'Should stamp ComputerName as SRV01' -Test {
            $script:remoteResult[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return DiskCleanupResult type' -Test {
            $script:remoteResult[0].PSObject.TypeNames | Should -Contain 'PSWinOps.DiskCleanupResult'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCleanResult
            }
            # Pipe via property name
            $pipeInput = @(
                [PSCustomObject]@{ ComputerName = 'SRV01' }
                [PSCustomObject]@{ ComputerName = 'SRV02' }
            )
            $script:pipeResults = @($pipeInput | Clear-DiskCleanup -Category 'TempFiles' -Force)
        }

        It -Name 'Should return 2 results' -Test {
            $script:pipeResults | Should -HaveCount 2
        }

        It -Name 'Should return distinct ComputerName per machine' -Test {
            $script:pipeResults[0].ComputerName | Should -Be 'SRV01'
            $script:pipeResults[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Per-machine error handling' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                throw 'Connection failed'
            }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Clear-DiskCleanup -ComputerName 'BADHOST' -Category 'TempFiles' -Force -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should return no output for failed machine with SilentlyContinue' -Test {
            $failResult = @(Clear-DiskCleanup -ComputerName 'BADHOST' -Category 'TempFiles' -Force -ErrorAction SilentlyContinue)
            $failResult | Should -HaveCount 0
        }
    }

    Context 'Credential parameter' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCleanResult
            }
            $cred = [System.Management.Automation.PSCredential]::new(
                'TestUser',
                (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)
            )
            $script:credResult = @(Clear-DiskCleanup -ComputerName 'SRV01' -Category 'TempFiles' -Credential $cred -Force)
        }

        It -Name 'Should return valid result with Credential' -Test {
            $script:credResult | Should -HaveCount 1
        }

        It -Name 'Should have DiskCleanupResult type with Credential' -Test {
            $script:credResult[0].PSObject.TypeNames | Should -Contain 'PSWinOps.DiskCleanupResult'
        }
    }

    Context 'Verbose output' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockCleanResult
            }
        }

        It -Name 'Should write verbose messages' -Test {
            $verboseOutput = Clear-DiskCleanup -Category 'TempFiles' -Force -Verbose 4>&1
            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Scriptblock execution - TempFiles' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @(
                    [PSCustomObject]@{ FullName = 'C:\Windows\Temp\old1.tmp'; Length = [long]1024; LastWriteTime = (Get-Date).AddDays(-60) }
                    [PSCustomObject]@{ FullName = 'C:\Windows\Temp\old2.tmp'; Length = [long]2048; LastWriteTime = (Get-Date).AddDays(-45) }
                )
            }
            Mock -CommandName 'Remove-Item' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = @(Clear-DiskCleanup -Category 'TempFiles' -Force)
        }

        It -Name 'Should return result' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Category TempFiles' -Test {
            $script:result[0].Category | Should -Be 'TempFiles'
        }
        It -Name 'Should have FilesRemoved greater than 0' -Test {
            $script:result[0].FilesRemoved | Should -BeGreaterThan 0
        }
        It -Name 'Should have SpaceRecoveredBytes greater than 0' -Test {
            $script:result[0].SpaceRecoveredBytes | Should -BeGreaterThan 0
        }
    }

    Context 'Scriptblock execution - CrashDumps' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @(
                    [PSCustomObject]@{ FullName = 'C:\Windows\Minidump\mini1.dmp'; Length = [long]4096; LastWriteTime = (Get-Date).AddDays(-10) }
                )
            }
            Mock -CommandName 'Get-Item' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ FullName = 'C:\Windows\MEMORY.DMP'; Length = [long]1073741824; LastWriteTime = (Get-Date).AddDays(-5) }
            }
            Mock -CommandName 'Remove-Item' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = @(Clear-DiskCleanup -Category 'CrashDumps' -Force)
        }

        It -Name 'Should return result' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Category CrashDumps' -Test {
            $script:result[0].Category | Should -Be 'CrashDumps'
        }
        It -Name 'Should have FilesRemoved' -Test {
            $script:result[0].FilesRemoved | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Scriptblock execution - WindowsUpdate' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Stop-Service' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Start-Service' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @(
                    [PSCustomObject]@{ FullName = 'C:\Windows\SoftwareDistribution\Download\kb1.cab'; Length = [long]10240; LastWriteTime = (Get-Date).AddDays(-30) }
                )
            }
            Mock -CommandName 'Remove-Item' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = @(Clear-DiskCleanup -Category 'WindowsUpdate' -Force)
        }

        It -Name 'Should have Category WindowsUpdate' -Test {
            $script:result[0].Category | Should -Be 'WindowsUpdate'
        }
        It -Name 'Should have FilesRemoved' -Test {
            $script:result[0].FilesRemoved | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Scriptblock execution - OldLogs' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @(
                    [PSCustomObject]@{ FullName = 'C:\Windows\Logs\old.log'; Extension = '.log'; Length = [long]512; LastWriteTime = (Get-Date).AddDays(-60) }
                    [PSCustomObject]@{ FullName = 'C:\Windows\Logs\old.etl'; Extension = '.etl'; Length = [long]256; LastWriteTime = (Get-Date).AddDays(-45) }
                )
            }
            Mock -CommandName 'Remove-Item' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = @(Clear-DiskCleanup -Category 'OldLogs' -Force)
        }

        It -Name 'Should have Category OldLogs' -Test {
            $script:result[0].Category | Should -Be 'OldLogs'
        }
        It -Name 'Should have FilesRemoved' -Test {
            $script:result[0].FilesRemoved | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Scriptblock execution - WindowsOld fast path' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @(
                    [PSCustomObject]@{ FullName = 'C:\Windows.old\Windows\explorer.exe'; Length = [long]4194304; LastWriteTime = (Get-Date).AddDays(-90) }
                )
            }
            Mock -CommandName 'Remove-Item' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = @(Clear-DiskCleanup -Category 'WindowsOld' -Force)
        }

        It -Name 'Should have Category WindowsOld' -Test {
            $script:result[0].Category | Should -Be 'WindowsOld'
        }
        It -Name 'Should have FilesRemoved' -Test {
            $script:result[0].FilesRemoved | Should -BeGreaterOrEqual 1
        }
        It -Name 'Should have SpaceRecoveredBytes' -Test {
            $script:result[0].SpaceRecoveredBytes | Should -BeGreaterThan 0
        }
    }

    Context 'Scriptblock execution - RecycleBin with fallback' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Clear-RecycleBin' -ModuleName 'PSWinOps' -MockWith {
                throw 'Not supported'
            }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @(
                    [PSCustomObject]@{ FullName = 'C:\$Recycle.Bin\S-1-5-21\$Rfile1'; Length = [long]8192; LastWriteTime = (Get-Date).AddDays(-10) }
                )
            }
            Mock -CommandName 'Remove-Item' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = @(Clear-DiskCleanup -Category 'RecycleBin' -Force)
        }

        It -Name 'Should have Category RecycleBin' -Test {
            $script:result[0].Category | Should -Be 'RecycleBin'
        }
        It -Name 'Should have FilesRemoved from fallback path' -Test {
            $script:result[0].FilesRemoved | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Scriptblock execution - BrowserCache' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                param($LiteralPath, $Path)
                if ($LiteralPath -and $LiteralPath -like '*Users*') {
                    @([PSCustomObject]@{ FullName = 'C:\Users\testuser'; Name = 'testuser' })
                }
                else {
                    @([PSCustomObject]@{ FullName = 'C:\Users\testuser\AppData\Local\Google\Chrome\User Data\Default\Cache\data_0'; Length = [long]1024; LastWriteTime = (Get-Date).AddDays(-5) })
                }
            }
            Mock -CommandName 'Remove-Item' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = @(Clear-DiskCleanup -Category 'BrowserCache' -Force)
        }

        It -Name 'Should have Category BrowserCache' -Test {
            $script:result[0].Category | Should -Be 'BrowserCache'
        }
    }

    Context 'Scriptblock execution - ThumbnailCache' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                param($LiteralPath, $Path)
                if ($LiteralPath -and $LiteralPath -like '*Users*') {
                    @([PSCustomObject]@{ FullName = 'C:\Users\testuser'; Name = 'testuser' })
                }
                else {
                    @([PSCustomObject]@{ FullName = 'C:\Users\testuser\AppData\Local\Microsoft\Windows\Explorer\thumbcache_256.db'; Length = [long]2048; LastWriteTime = (Get-Date).AddDays(-15) })
                }
            }
            Mock -CommandName 'Remove-Item' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = @(Clear-DiskCleanup -Category 'ThumbnailCache' -Force)
        }

        It -Name 'Should have Category ThumbnailCache' -Test {
            $script:result[0].Category | Should -Be 'ThumbnailCache'
        }
    }

    Context 'Scriptblock execution - ExcludePath' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $ScriptBlock @ArgumentList
            }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @(
                    [PSCustomObject]@{ FullName = 'C:\Windows\Temp\keep.tmp'; Length = [long]1024; LastWriteTime = (Get-Date).AddDays(-60) }
                    [PSCustomObject]@{ FullName = 'C:\Windows\Temp\delete.tmp'; Length = [long]2048; LastWriteTime = (Get-Date).AddDays(-60) }
                )
            }
            Mock -CommandName 'Remove-Item' -ModuleName 'PSWinOps' -MockWith { }
            $script:result = @(Clear-DiskCleanup -Category 'TempFiles' -ExcludePath 'C:\Windows\Temp\keep.tmp' -Force)
        }

        It -Name 'Should have FilesSkipped for excluded path' -Test {
            $script:result[0].FilesSkipped | Should -BeGreaterOrEqual 1
        }
        It -Name 'Should still have FilesRemoved for non-excluded' -Test {
            $script:result[0].FilesRemoved | Should -BeGreaterOrEqual 1
        }
    }
}
