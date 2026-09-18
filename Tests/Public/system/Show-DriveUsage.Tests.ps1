#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Show-DriveUsage' {

    BeforeAll {
        # One 100 GB volume, 75 % used, so PercentUsed is a clean 75. Any halving
        # bug (the upstream 0-50 scale) would surface as 37.5 here.
        $script:makeVolumes = {
            param($cn)
            @(
                [PSCustomObject]@{
                    ComputerName = $cn
                    DriveLetter  = 'C:'
                    VolumeName   = 'OS'
                    FileSystem   = 'NTFS'
                    SizeGB       = 100
                    FreeSpaceGB  = 25
                    UsedSpaceGB  = 75
                    PercentFree  = 25
                    PercentUsed  = 75
                    Status       = 'OK'
                }
                [PSCustomObject]@{
                    ComputerName = $cn
                    DriveLetter  = 'D:'
                    VolumeName   = 'Data'
                    FileSystem   = 'NTFS'
                    SizeGB       = 500
                    FreeSpaceGB  = 450
                    UsedSpaceGB  = 50
                    PercentFree  = 90
                    PercentUsed  = 10
                    Status       = 'OK'
                }
            )
        }
    }

    Context 'Happy path - local' {

        BeforeAll {
            Mock -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeVolumes $ComputerName[0]
            }
            $script:result = Show-DriveUsage
        }

        It -Name 'Should return PSWinOps.DriveUsage type' -Test {
            $script:result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.DriveUsage'
        }

        It -Name 'Should default ComputerName to the local machine' -Test {
            $script:result[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should emit one object per volume' -Test {
            $script:result | Should -HaveCount 2
        }

        It -Name 'Should map fields from the Get-DiskSpace result' -Test {
            $script:result[0].DriveLetter | Should -Be 'C:'
            $script:result[0].VolumeName | Should -Be 'OS'
            $script:result[0].SizeGB | Should -Be 100
            $script:result[0].UsedGB | Should -Be 75
            $script:result[0].FreeGB | Should -Be 25
            $script:result[0].PercentFree | Should -Be 25
            $script:result[0].Status | Should -Be 'OK'
        }

        It -Name 'Should carry a Timestamp' -Test {
            $script:result[0].Timestamp | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should own no CIM call' -Test {
            Should -Invoke -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -Times 1 -Exactly -Scope Context
        }
    }

    Context 'PercentUsed regression guard (not halved)' {

        BeforeAll {
            Mock -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeVolumes $ComputerName[0]
            }
            $script:result = Show-DriveUsage
        }

        It -Name 'Should report PercentUsed as the mocked 75, not 37.5' -Test {
            $script:result[0].PercentUsed | Should -Be 75
        }
    }

    Context 'No ANSI escapes or rendered text in any property' {

        BeforeAll {
            Mock -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeVolumes $ComputerName[0]
            }
            $script:result = Show-DriveUsage
        }

        It -Name 'Should not embed ESC (char 27) in any property value' -Test {
            $esc = [char]27
            foreach ($obj in $script:result) {
                foreach ($prop in $obj.PSObject.Properties) {
                    ($prop.Value | Out-String) | Should -Not -Match ([regex]::Escape($esc))
                }
            }
        }

        It -Name 'Should not expose a UsageBar property (bar is view-only)' -Test {
            $script:result[0].PSObject.Properties.Name | Should -Not -Contain 'UsageBar'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeVolumes $ComputerName[0]
            }
            $script:result = Show-DriveUsage -ComputerName 'SRV01'
        }

        It -Name 'Should forward ComputerName to Get-DiskSpace' -Test {
            Should -Invoke -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -Times 1 -Exactly -Scope Context -ParameterFilter {
                $ComputerName -eq 'SRV01'
            }
        }

        It -Name 'Should return ComputerName SRV01' -Test {
            $script:result[0].ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeVolumes $ComputerName[0]
            }
            $script:results = 'SRV01', 'SRV02' | Show-DriveUsage
        }

        It -Name 'Should emit two volumes per machine (4 total)' -Test {
            $script:results | Should -HaveCount 4
        }

        It -Name 'Should return distinct ComputerName per machine' -Test {
            ($script:results.ComputerName | Sort-Object -Unique) | Should -Be @('SRV01', 'SRV02')
        }
    }

    Context 'Threshold forwarding' {

        BeforeAll {
            Mock -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeVolumes $ComputerName[0]
            }
            $null = Show-DriveUsage -WarningThreshold 30 -CriticalThreshold 15
        }

        It -Name 'Should forward WarningThreshold and CriticalThreshold to Get-DiskSpace' -Test {
            Should -Invoke -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -Times 1 -Exactly -Scope Context -ParameterFilter {
                $WarningThreshold -eq 30 -and $CriticalThreshold -eq 15
            }
        }
    }

    Context 'Per-machine failure' {

        It -Name 'Should write a terminating error for a failed machine with ErrorAction Stop' -Test {
            Mock -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -MockWith { throw 'boom' }
            { Show-DriveUsage -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should not stop the remaining machines on a per-machine failure' -Test {
            Mock -CommandName 'Get-DiskSpace' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName[0] -eq 'BADHOST') { throw 'boom' }
                & $script:makeVolumes $ComputerName[0]
            }
            $script:results = 'BADHOST', 'SRV02' | Show-DriveUsage -ErrorAction SilentlyContinue
            $script:results | Should -HaveCount 2
            ($script:results.ComputerName | Sort-Object -Unique) | Should -Be @('SRV02')
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Show-DriveUsage -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Show-DriveUsage -ComputerName $null } | Should -Throw
        }

        It -Name 'Should throw when WarningThreshold is out of range' -Test {
            { Show-DriveUsage -WarningThreshold 0 } | Should -Throw
            { Show-DriveUsage -WarningThreshold 101 } | Should -Throw
        }

        It -Name 'Should throw when CriticalThreshold is out of range' -Test {
            { Show-DriveUsage -CriticalThreshold 0 } | Should -Throw
            { Show-DriveUsage -CriticalThreshold 101 } | Should -Throw
        }
    }

    Context 'Format view' {

        BeforeAll {
            $script:formatPath = Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.Format.ps1xml'
            [xml]$script:formatXml = Get-Content -Path $script:formatPath -Raw
        }

        It -Name 'Should parse PSWinOps.Format.ps1xml as XML' -Test {
            $script:formatXml | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should contain a View named PSWinOps.DriveUsage' -Test {
            $names = $script:formatXml.Configuration.ViewDefinitions.View.Name
            $names | Should -Contain 'PSWinOps.DriveUsage'
        }
    }

    Context 'Comment-based help' {

        BeforeAll {
            $script:helpInfo = Get-Help -Name 'Show-DriveUsage' -Full
        }

        It -Name 'Should have a synopsis' -Test {
            $script:helpInfo.Synopsis.Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a description' -Test {
            ($script:helpInfo.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have at least 3 examples' -Test {
            $script:helpInfo.Examples.Example.Count | Should -BeGreaterOrEqual 3
        }

        It -Name 'Should have OUTPUTS section' -Test {
            ($script:helpInfo.returnValues | Out-String).Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have Author in NOTES' -Test {
            ($script:helpInfo.alertSet | Out-String) | Should -Match 'Franck SALLET'
        }

        It -Name 'Should document all parameters' -Test {
            $expectedParams = @('ComputerName', 'WarningThreshold', 'CriticalThreshold', 'Credential')
            $documented = $script:helpInfo.parameters.parameter.name
            foreach ($param in $expectedParams) {
                $documented | Should -Contain $param
            }
        }
    }
}
