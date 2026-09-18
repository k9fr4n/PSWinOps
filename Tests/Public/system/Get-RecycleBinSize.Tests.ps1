#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-RecycleBinSize' {

    BeforeAll {
        # 100 GB volume so a 2 GB Recycle Bin is exactly 2 % of it.
        $script:mockVolume = [PSCustomObject]@{
            DeviceID  = 'C:'
            Size      = 107374182400
            DriveType = 3
        }
        # Two 1 GB files => 2 GB total, clean MB/GB rounding.
        $script:mockFiles = @(
            [PSCustomObject]@{ Length = 1073741824 }
            [PSCustomObject]@{ Length = 1073741824 }
        )

        $script:runInline = {
            if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
        }
    }

    Context 'Happy path - local' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { $script:mockVolume }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { $script:mockFiles }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith $script:runInline
            $script:result = Get-RecycleBinSize
        }

        It -Name 'Should return PSWinOps.RecycleBinSize type' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.RecycleBinSize'
        }

        It -Name 'Should default ComputerName to the local machine' -Test {
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should emit one object per fixed volume' -Test {
            $script:result | Should -HaveCount 1
        }

        It -Name 'Should return DriveLetter C:' -Test {
            $script:result.DriveLetter | Should -Be 'C:'
        }

        It -Name 'Should return ItemCount 2' -Test {
            $script:result.ItemCount | Should -Be 2
        }

        It -Name 'Should return exact SizeBytes' -Test {
            $script:result.SizeBytes | Should -Be 2147483648
        }
    }

    Context 'Byte to MB/GB rounding and percentage' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { $script:mockVolume }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { $script:mockFiles }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith $script:runInline
            $script:result = Get-RecycleBinSize
        }

        It -Name 'Should round SizeMB to 2048' -Test {
            $script:result.SizeMB | Should -Be 2048
        }

        It -Name 'Should round SizeGB to 2' -Test {
            $script:result.SizeGB | Should -Be 2
        }

        It -Name 'Should compute PercentOfVolume as 2' -Test {
            $script:result.PercentOfVolume | Should -Be 2
        }
    }

    Context 'Empty or missing Recycle Bin' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { $script:mockVolume }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith $script:runInline
            $script:result = Get-RecycleBinSize
        }

        It -Name 'Should still emit the volume' -Test {
            $script:result | Should -HaveCount 1
        }

        It -Name 'Should report SizeBytes 0' -Test {
            $script:result.SizeBytes | Should -Be 0
        }

        It -Name 'Should report ItemCount 0' -Test {
            $script:result.ItemCount | Should -Be 0
        }
    }

    Context 'Access denied inside the Recycle Bin' {

        BeforeAll {
            # -ErrorAction SilentlyContinue in the function swallows the denial;
            # only the readable subset is returned. No terminating error.
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { $script:mockVolume }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Length = 1073741824 }
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith $script:runInline
        }

        It -Name 'Should return the partial size without throwing' -Test {
            { $script:result = Get-RecycleBinSize -ErrorAction Stop } | Should -Not -Throw
            $script:result = Get-RecycleBinSize
            $script:result.SizeBytes | Should -Be 1073741824
            $script:result.ItemCount | Should -Be 1
        }
    }

    Context 'Zero-size volume' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ DeviceID = 'Z:'; Size = 0; DriveType = 3 }
            }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith $script:runInline
            $script:result = Get-RecycleBinSize
        }

        It -Name 'Should report PercentOfVolume 0 without divide-by-zero' -Test {
            $script:result.PercentOfVolume | Should -Be 0
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { $script:mockVolume }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { $script:mockFiles }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith $script:runInline
            $script:result = Get-RecycleBinSize -ComputerName 'SRV01'
        }

        It -Name 'Should return ComputerName SRV01' -Test {
            $script:result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return a valid RecycleBinSize object' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.RecycleBinSize'
            $script:result.DriveLetter | Should -Be 'C:'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { $script:mockVolume }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { $script:mockFiles }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith $script:runInline
            $script:results = 'SRV01', 'SRV02' | Get-RecycleBinSize
        }

        It -Name 'Should return 2 results' -Test {
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should return distinct ComputerName per machine' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
            $script:results[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Per-machine failure' {

        It -Name 'Should write a terminating error for a failed machine with ErrorAction Stop' -Test {
            { Get-RecycleBinSize -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should not stop the remaining machines on a per-machine failure' -Test {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { $script:mockVolume }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { $script:mockFiles }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'BADHOST') { throw 'boom' }
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = 'BADHOST', 'SRV02' | Get-RecycleBinSize -ErrorAction SilentlyContinue
            $script:results | Should -HaveCount 1
            $script:results[0].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-RecycleBinSize -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-RecycleBinSize -ComputerName $null } | Should -Throw
        }
    }
}
