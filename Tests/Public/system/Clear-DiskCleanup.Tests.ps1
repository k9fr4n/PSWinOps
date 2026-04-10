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
}
