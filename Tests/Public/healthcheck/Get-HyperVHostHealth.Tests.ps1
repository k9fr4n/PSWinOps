#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        foreach ($cmdName in @('Get-VMHost', 'Get-VM')) {
            if (-not (Get-Command -Name $cmdName -ErrorAction SilentlyContinue)) {
                Set-Item -Path "function:script:$cmdName" -Value ([scriptblock]::Create(''))
            }
        }
    }
}

Describe 'Get-HyperVHostHealth' {

    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus       = 'Running'
            ModuleAvailable     = $true
            LogicalProcessors   = 16
            MemoryCapacityBytes = [long](64GB)
            TotalVMs            = 10
            VMsRunning          = 8
            VMsOff              = 2
            VMsSaved            = 0
            VMsPaused           = 0
            VMsCritical         = 0
            AssignedMemoryBytes = [long](32GB)
        }

        function Set-HyperVLocalMocks {
            param(
                [string]$ServiceStatus   = 'Running',
                [bool]$ServiceThrows     = $false,
                [bool]$ModuleAvailable   = $true,
                [int]$LogicalProcessors  = 16,
                [long]$MemoryCapacity    = 64GB,
                [array]$VMs              = @(),
                [bool]$VMHostThrows      = $false,
                [bool]$VMThrows          = $false
            )

            if ($ServiceThrows) {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'Service not found' }
            }
            else {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                    [PSCustomObject]@{ Status = $ServiceStatus; Name = 'vmms' }
                }.GetNewClosure()
            }

            if ($ModuleAvailable) {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'Hyper-V' } -MockWith {
                    [PSCustomObject]@{ Name = 'Hyper-V'; Version = '2.0' }
                }
            }
            else {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'Hyper-V' } -MockWith { return $null }
            }

            if ($VMHostThrows) {
                Mock -CommandName 'Get-VMHost' -ModuleName 'PSWinOps' -MockWith { throw 'VMHost query failed' }
            }
            else {
                Mock -CommandName 'Get-VMHost' -ModuleName 'PSWinOps' -MockWith {
                    [PSCustomObject]@{ LogicalProcessorCount = $LogicalProcessors; MemoryCapacity = $MemoryCapacity }
                }.GetNewClosure()
            }

            if ($VMThrows) {
                Mock -CommandName 'Get-VM' -ModuleName 'PSWinOps' -MockWith { throw 'VM query failed' }
            }
            else {
                Mock -CommandName 'Get-VM' -ModuleName 'PSWinOps' -MockWith { return $VMs }.GetNewClosure()
            }

            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
        }
    }

    # =================================================================
    #  REMOTE PATH
    # =================================================================
    Context 'Remote - RoleUnavailable' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone(); $data.ModuleAvailable = $false; return $data
            }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
        It 'Should set ComputerName' { $script:result.ComputerName | Should -Be 'SRV01' }
    }

    Context 'Remote - Healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return TotalVMs = 10' { $script:result.TotalVMs | Should -Be 10 }
        It 'Should return VMsRunning = 8' { $script:result.VMsRunning | Should -Be 8 }
        It 'Should return LogicalProcessors = 16' { $script:result.LogicalProcessors | Should -Be 16 }
        It 'Should compute memory usage <= 90' { $script:result.MemoryUsagePercent | Should -BeLessOrEqual 90 }
    }

    Context 'Remote - Critical (service stopped)' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone(); $data.ServiceStatus = 'Stopped'; return $data
            }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Remote - Critical (VMs critical)' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone(); $data.VMsCritical = 3; return $data
            }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should report 3 VMs critical' { $script:result.VMsCritical | Should -Be 3 }
    }

    Context 'Remote - Degraded (memory > 90%)' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone()
                $data.AssignedMemoryBytes = [long](60GB); $data.MemoryCapacityBytes = [long](64GB)
                return $data
            }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should compute memory > 90' { $script:result.MemoryUsagePercent | Should -BeGreaterThan 90 }
    }

    Context 'Remote - Pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = @('SRV01', 'SRV02') | Get-HyperVHostHealth
        }
        It 'Should return 2 results' { $script:results.Count | Should -Be 2 }
    }

    Context 'Remote - Failure handling' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should throw with -ErrorAction Stop' { { Get-HyperVHostHealth -ComputerName 'SRV01' -ErrorAction 'Stop' } | Should -Throw }
        It 'Should return null with -ErrorAction SilentlyContinue' {
            $r = Get-HyperVHostHealth -ComputerName 'SRV01' -ErrorAction 'SilentlyContinue'; $r | Should -BeNullOrEmpty
        }
    }

    # =================================================================
    #  LOCAL PATH
    # =================================================================
    Context 'Local - Healthy (VMs running, memory normal)' {
        BeforeAll {
            $vms = @(
                [PSCustomObject]@{ Name = 'VM1'; State = 'Running'; MemoryAssigned = 4GB },
                [PSCustomObject]@{ Name = 'VM2'; State = 'Running'; MemoryAssigned = 4GB },
                [PSCustomObject]@{ Name = 'VM3'; State = 'Off';     MemoryAssigned = 0 }
            )
            Set-HyperVLocalMocks -VMs $vms -MemoryCapacity 64GB
            $script:result = Get-HyperVHostHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return TotalVMs = 3' { $script:result.TotalVMs | Should -Be 3 }
        It 'Should return VMsRunning = 2' { $script:result.VMsRunning | Should -Be 2 }
        It 'Should return VMsOff = 1' { $script:result.VMsOff | Should -Be 1 }
        It 'Should return AssignedMemoryGB > 0' { $script:result.AssignedMemoryGB | Should -BeGreaterThan 0 }
        It 'Should return MemoryUsagePercent <= 90' { $script:result.MemoryUsagePercent | Should -BeLessOrEqual 90 }
    }

    Context 'Local - Service not found' {
        BeforeAll {
            Set-HyperVLocalMocks -ServiceThrows $true
            $script:result = Get-HyperVHostHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return NotFound ServiceStatus' { $script:result.ServiceStatus | Should -Be 'NotFound' }
    }

    Context 'Local - Module not available (RoleUnavailable)' {
        BeforeAll {
            Set-HyperVLocalMocks -ModuleAvailable $false
            $script:result = Get-HyperVHostHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
        It 'Should NOT call Get-VMHost' { Should -Invoke -CommandName 'Get-VMHost' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should NOT call Get-VM' { Should -Invoke -CommandName 'Get-VM' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Local - Service stopped (skips VM queries)' {
        BeforeAll {
            Set-HyperVLocalMocks -ServiceStatus 'Stopped'
            $script:result = Get-HyperVHostHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should NOT call Get-VMHost' { Should -Invoke -CommandName 'Get-VMHost' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should NOT call Get-VM' { Should -Invoke -CommandName 'Get-VM' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Local - VMs in critical state' {
        BeforeAll {
            $vms = @(
                [PSCustomObject]@{ Name = 'VM1'; State = 'Running'; MemoryAssigned = 4GB },
                [PSCustomObject]@{ Name = 'VM2'; State = 'Other';   MemoryAssigned = 2GB }
            )
            Set-HyperVLocalMocks -VMs $vms
            $script:result = Get-HyperVHostHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should count 1 VM critical' { $script:result.VMsCritical | Should -Be 1 }
    }

    Context 'Local - Memory > 90% (Degraded)' {
        BeforeAll {
            $vms = @(
                [PSCustomObject]@{ Name = 'VM1'; State = 'Running'; MemoryAssigned = 60GB },
                [PSCustomObject]@{ Name = 'VM2'; State = 'Running'; MemoryAssigned = 2GB }
            )
            Set-HyperVLocalMocks -VMs $vms -MemoryCapacity 64GB
            $script:result = Get-HyperVHostHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should compute MemoryUsagePercent > 90' { $script:result.MemoryUsagePercent | Should -BeGreaterThan 90 }
    }

    Context 'Local - Saved and Paused VMs' {
        BeforeAll {
            $vms = @(
                [PSCustomObject]@{ Name = 'VM1'; State = 'Running'; MemoryAssigned = 4GB },
                [PSCustomObject]@{ Name = 'VM2'; State = 'Saved';   MemoryAssigned = 0 },
                [PSCustomObject]@{ Name = 'VM3'; State = 'Paused';  MemoryAssigned = 2GB }
            )
            Set-HyperVLocalMocks -VMs $vms -MemoryCapacity 64GB
            $script:result = Get-HyperVHostHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should count 1 VM saved' { $script:result.VMsSaved | Should -Be 1 }
        It 'Should count 1 VM paused' { $script:result.VMsPaused | Should -Be 1 }
        It 'Should count 0 VMs critical' { $script:result.VMsCritical | Should -Be 0 }
    }

    Context 'Local - Get-VMHost throws (warns, zeroed data)' {
        BeforeAll {
            Set-HyperVLocalMocks -VMHostThrows $true
            $script:result = Get-HyperVHostHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return a result' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should have LogicalProcessors = 0' { $script:result.LogicalProcessors | Should -Be 0 }
        It 'Should have TotalMemoryGB = 0' { $script:result.TotalMemoryGB | Should -Be 0 }
    }

    Context 'Local - No VMs (Healthy, TotalVMs = 0)' {
        BeforeAll {
            Set-HyperVLocalMocks -VMs @()
            $script:result = Get-HyperVHostHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return TotalVMs = 0' { $script:result.TotalVMs | Should -Be 0 }
    }

    Context 'Local - localhost alias' {
        BeforeAll {
            Set-HyperVLocalMocks -VMs @()
            $script:result = Get-HyperVHostHealth -ComputerName 'localhost'
        }
        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return LOCALHOST as ComputerName' { $script:result.ComputerName | Should -Be 'LOCALHOST' }
    }

    Context 'Local - dot alias' {
        BeforeAll {
            Set-HyperVLocalMocks -VMs @()
            $script:result = Get-HyperVHostHealth -ComputerName '.'
        }
        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return a result' { $script:result | Should -Not -BeNullOrEmpty }
    }

    # =================================================================
    #  COMMON VALIDATIONS
    # =================================================================
    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It 'Should have PSTypeName PSWinOps.HyperVHostHealth' { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.HyperVHostHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It 'Should have Timestamp matching ISO 8601' { $script:typeResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' }
    }

    Context 'Parameter validation' {
        It 'Should reject empty ComputerName' { { Get-HyperVHostHealth -ComputerName '' } | Should -Throw }
        It 'Should reject null ComputerName' { { Get-HyperVHostHealth -ComputerName $null } | Should -Throw }
        It 'Should support pipeline input by property name' {
            $a = (Get-Command -Name 'Get-HyperVHostHealth').Parameters['ComputerName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName }
            $a | Should -Not -BeNullOrEmpty
        }
    }
}