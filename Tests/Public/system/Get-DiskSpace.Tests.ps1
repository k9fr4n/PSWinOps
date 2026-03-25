#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-DiskSpace' {

    BeforeAll {
        $script:mockDisk = [PSCustomObject]@{
            DeviceID   = 'C:'
            VolumeName = 'System'
            FileSystem = 'NTFS'
            Size       = 107374182400
            FreeSpace  = 32212254720
            DriveType  = 3
        }
        $script:mockDiskCritical = [PSCustomObject]@{
            DeviceID   = 'D:'
            VolumeName = 'Data'
            FileSystem = 'NTFS'
            Size       = 107374182400
            FreeSpace  = 5368709120
            DriveType  = 3
        }
        # CimSession mock created inline via New-MockObject
    }

    Context 'Happy path - local' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDisk
            }
            $script:result = Get-DiskSpace
        }

        It -Name 'Should return PSWinOps.DiskSpace type' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.DiskSpace'
        }

        It -Name 'Should return DriveLetter C:' -Test {
            $script:result.DriveLetter | Should -Be 'C:'
        }

        It -Name 'Should return SizeGB approximately 100' -Test {
            $script:result.SizeGB | Should -BeGreaterOrEqual 99
            $script:result.SizeGB | Should -BeLessOrEqual 101
        }

        It -Name 'Should return FreeSpaceGB approximately 30' -Test {
            $script:result.FreeSpaceGB | Should -BeGreaterOrEqual 29
            $script:result.FreeSpaceGB | Should -BeLessOrEqual 31
        }

        It -Name 'Should return PercentFree approximately 30' -Test {
            $script:result.PercentFree | Should -BeGreaterOrEqual 29
            $script:result.PercentFree | Should -BeLessOrEqual 31
        }

        It -Name 'Should return Status OK' -Test {
            $script:result.Status | Should -Be 'OK'
        }
    }

    Context 'Threshold - Critical status' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDiskCritical
            }
            $script:result = Get-DiskSpace
        }

        It -Name 'Should return Status Critical when free space is 5 percent' -Test {
            $script:result.Status | Should -Be 'Critical'
        }
    }

    Context 'Threshold - Warning status' {

        BeforeAll {
            $script:mockDiskWarning = [PSCustomObject]@{
                DeviceID   = 'E:'
                VolumeName = 'Apps'
                FileSystem = 'NTFS'
                Size       = 107374182400
                FreeSpace  = 16106127360
                DriveType  = 3
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDiskWarning
            }
            $script:result = Get-DiskSpace
        }

        It -Name 'Should return Status Warning when free space is 15 percent' -Test {
            $script:result.Status | Should -Be 'Warning'
        }
    }

    Context 'Custom thresholds' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDisk
            }
            $script:result = Get-DiskSpace -WarningThreshold 40 -CriticalThreshold 20
        }

        It -Name 'Should return Status Warning with custom thresholds' -Test {
            $script:result.Status | Should -Be 'Warning'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
            }
            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDisk
            }
            $script:result = Get-DiskSpace -ComputerName 'SRV01'
        }

        It -Name 'Should return ComputerName SRV01' -Test {
            $script:result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return valid DiskSpace object for remote machine' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.DiskSpace'
            $script:result.DriveLetter | Should -Be 'C:'
        }

        It -Name 'Should query Get-CimInstance for remote machine' -Test {
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
            }
            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDisk
            }
            $script:results = 'SRV01', 'SRV02' | Get-DiskSpace
        }

        It -Name 'Should return 2 results' -Test {
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should return distinct ComputerName per machine' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
            $script:results[1].ComputerName | Should -Be 'SRV02'
        }

        It -Name 'Should query Get-CimInstance for each machine' -Test {
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith {
                throw 'Connection failed'
            }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-DiskSpace -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-DiskSpace -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-DiskSpace -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-DiskSpace -ComputerName $null } | Should -Throw
        }
    }
}
