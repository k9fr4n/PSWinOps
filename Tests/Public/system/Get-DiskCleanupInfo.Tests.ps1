#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-DiskCleanupInfo' {

    BeforeAll {
        $script:mockFiles = @(
            [PSCustomObject]@{
                FullName      = 'C:\Windows\Temp\file1.tmp'
                Name          = 'file1.tmp'
                Extension     = '.tmp'
                Length        = [long]1048576
                LastWriteTime = (Get-Date).AddDays(-60)
            }
            [PSCustomObject]@{
                FullName      = 'C:\Windows\Temp\file2.tmp'
                Name          = 'file2.tmp'
                Extension     = '.tmp'
                Length        = [long]2097152
                LastWriteTime = (Get-Date).AddDays(-45)
            }
        )

        $script:mockLogFiles = @(
            [PSCustomObject]@{
                FullName      = 'C:\Windows\Logs\old.log'
                Name          = 'old.log'
                Extension     = '.log'
                Length        = [long]512000
                LastWriteTime = (Get-Date).AddDays(-60)
            }
            [PSCustomObject]@{
                FullName      = 'C:\Windows\Logs\old.etl'
                Name          = 'old.etl'
                Extension     = '.etl'
                Length        = [long]256000
                LastWriteTime = (Get-Date).AddDays(-45)
            }
        )
    }

    Context 'Parameter validation' {

        It -Name 'Should reject empty ComputerName' -Test {
            { Get-DiskCleanupInfo -ComputerName '' } | Should -Throw
        }

        It -Name 'Should reject null ComputerName' -Test {
            { Get-DiskCleanupInfo -ComputerName $null } | Should -Throw
        }

        It -Name 'Should reject invalid Category' -Test {
            { Get-DiskCleanupInfo -Category 'InvalidCategory' } | Should -Throw
        }

        It -Name 'Should reject OlderThanDays below 1' -Test {
            { Get-DiskCleanupInfo -OlderThanDays 0 } | Should -Throw
        }

        It -Name 'Should reject OlderThanDays above 3650' -Test {
            { Get-DiskCleanupInfo -OlderThanDays 3651 } | Should -Throw
        }
    }

    Context 'Happy path - local TempFiles' {

        BeforeAll {
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { return $script:mockFiles }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = @(Get-DiskCleanupInfo -Category 'TempFiles')
        }

        It -Name 'Should return PSWinOps.DiskCleanupInfo type' -Test {
            $script:results[0].PSObject.TypeNames | Should -Contain 'PSWinOps.DiskCleanupInfo'
        }

        It -Name 'Should return two objects for TempFiles (env:TEMP + Windows Temp)' -Test {
            $script:results.Count | Should -Be 2
        }

        It -Name 'Should set Category to TempFiles' -Test {
            $script:results[0].Category | Should -Be 'TempFiles'
        }

        It -Name 'Should set ComputerName to local machine' -Test {
            $script:results[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProps = @('ComputerName', 'Category', 'Path', 'FileCount', 'SizeBytes', 'SizeMB', 'OldestFile', 'NewestFile', 'Timestamp')
            foreach ($prop in $expectedProps) {
                $script:results[0].PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It -Name 'Should have FileCount matching mock file count' -Test {
            $script:results[0].FileCount | Should -Be 2
        }

        It -Name 'Should calculate SizeMB correctly' -Test {
            $expectedMB = [math]::Round(($script:mockFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
            $script:results[0].SizeMB | Should -Be $expectedMB
        }

        It -Name 'Should have a valid Timestamp' -Test {
            $script:results[0].Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Category filter - single category' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{
                    Category   = 'WindowsUpdate'
                    Path       = 'C:\Windows\SoftwareDistribution\Download'
                    FileCount  = 5
                    SizeBytes  = [long]1048576
                    SizeMB     = 1.0
                    OldestFile = (Get-Date).AddDays(-30)
                    NewestFile = (Get-Date).AddDays(-1)
                }
            }
            $script:filtered = @(Get-DiskCleanupInfo -Category 'WindowsUpdate')
        }

        It -Name 'Should return only the selected category' -Test {
            $script:filtered | Should -HaveCount 1
            $script:filtered[0].Category | Should -Be 'WindowsUpdate'
        }
    }

    Context 'Category filter - multiple categories' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                # Return two separate hashtables — one per category
                @{
                    Category   = 'TempFiles'
                    Path       = 'C:\Windows\Temp'
                    FileCount  = 10
                    SizeBytes  = [long]2097152
                    SizeMB     = 2.0
                    OldestFile = (Get-Date).AddDays(-60)
                    NewestFile = (Get-Date).AddDays(-5)
                }
                @{
                    Category   = 'WindowsUpdate'
                    Path       = 'C:\Windows\SoftwareDistribution\Download'
                    FileCount  = 5
                    SizeBytes  = [long]1048576
                    SizeMB     = 1.0
                    OldestFile = (Get-Date).AddDays(-30)
                    NewestFile = (Get-Date).AddDays(-1)
                }
            }
            $script:multi = @(Get-DiskCleanupInfo -Category 'TempFiles', 'WindowsUpdate')
        }

        It -Name 'Should return two results' -Test {
            $script:multi | Should -HaveCount 2
        }

        It -Name 'Should contain TempFiles category' -Test {
            $script:multi.Category | Should -Contain 'TempFiles'
        }

        It -Name 'Should contain WindowsUpdate category' -Test {
            $script:multi.Category | Should -Contain 'WindowsUpdate'
        }
    }

    Context 'WindowsOld skip behavior' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
        }

        It -Name 'Should not return WindowsOld when path does not exist' -Test {
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $false }
            $noOld = @(Get-DiskCleanupInfo -Category 'WindowsOld')
            $noOld.Count | Should -Be 0
        }

        It -Name 'Should return WindowsOld when path exists' -Test {
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { return $script:mockFiles }
            $hasOld = @(Get-DiskCleanupInfo -Category 'WindowsOld')
            $hasOld.Count | Should -Be 1
            $hasOld[0].Category | Should -Be 'WindowsOld'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return @{
                    Category   = 'TempFiles'
                    Path       = 'C:\Windows\Temp'
                    FileCount  = 50
                    SizeBytes  = [long]5242880
                    SizeMB     = 5.0
                    OldestFile = (Get-Date).AddDays(-30)
                    NewestFile = (Get-Date).AddDays(-1)
                }
            }
            $script:remoteResult = @(Get-DiskCleanupInfo -ComputerName 'SRV01' -Category 'TempFiles')
        }

        It -Name 'Should stamp ComputerName as SRV01' -Test {
            $script:remoteResult[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return DiskCleanupInfo type' -Test {
            $script:remoteResult[0].PSObject.TypeNames | Should -Contain 'PSWinOps.DiskCleanupInfo'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return @{
                    Category   = 'TempFiles'
                    Path       = 'C:\Windows\Temp'
                    FileCount  = 10
                    SizeBytes  = [long]1048576
                    SizeMB     = 1.0
                    OldestFile = (Get-Date).AddDays(-15)
                    NewestFile = (Get-Date).AddDays(-1)
                }
            }
            $script:pipeResults = @('SRV01', 'SRV02' | Get-DiskCleanupInfo -Category 'TempFiles')
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

        It -Name 'Should write error for failing machine' -Test {
            { Get-DiskCleanupInfo -ComputerName 'BADHOST' -Category 'TempFiles' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should continue to next machine after failure' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'BADHOST') { throw 'Connection failed' }
                return @{
                    Category   = 'TempFiles'
                    Path       = 'C:\Windows\Temp'
                    FileCount  = 5
                    SizeBytes  = [long]500000
                    SizeMB     = 0.48
                    OldestFile = $null
                    NewestFile = $null
                }
            }
            $results = @(Get-DiskCleanupInfo -ComputerName 'BADHOST', $env:COMPUTERNAME -Category 'TempFiles' -ErrorAction SilentlyContinue)
            $results.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'SizeMB calculation' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
        }

        It -Name 'Should return 0 SizeMB when no files found' -Test {
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { return @() }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            $emptyResult = @(Get-DiskCleanupInfo -Category 'WindowsUpdate')
            $emptyResult[0].SizeMB | Should -Be 0
        }
    }
}
