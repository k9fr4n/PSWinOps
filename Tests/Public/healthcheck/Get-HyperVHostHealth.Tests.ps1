#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
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
    }

    Context 'When Hyper-V role is unavailable' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone()
                $data.ModuleAvailable = $false
                return $data
            }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return RoleUnavailable health status' -Test { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
        It -Name 'Should populate the ComputerName property' -Test { $script:result.ComputerName | Should -Be 'SRV01' }
        It -Name 'Should still report service status' -Test { $script:result.ServiceStatus | Should -Be 'Running' }
    }

    Context 'When host is healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Healthy overall health' -Test { $script:result.OverallHealth | Should -Be 'Healthy' }
        It -Name 'Should return correct total VM count' -Test { $script:result.TotalVMs | Should -Be 10 }
        It -Name 'Should return correct running VM count' -Test { $script:result.VMsRunning | Should -Be 8 }
        It -Name 'Should return correct logical processor count' -Test { $script:result.LogicalProcessors | Should -Be 16 }
        It -Name 'Should compute memory usage within normal range' -Test { $script:result.MemoryUsagePercent | Should -BeLessOrEqual 90 }
    }

    Context 'When Hyper-V service is stopped' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone(); $data.ServiceStatus = 'Stopped'; return $data
            }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Critical overall health' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
        It -Name 'Should report Stopped service status' -Test { $script:result.ServiceStatus | Should -Be 'Stopped' }
    }

    Context 'When VMs are in critical state' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone(); $data.VMsCritical = 3; return $data
            }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Critical overall health' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
        It -Name 'Should report correct critical VM count' -Test { $script:result.VMsCritical | Should -Be 3 }
    }

    Context 'When memory usage exceeds 90 percent' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone()
                $data.AssignedMemoryBytes = [long](60GB)
                $data.MemoryCapacityBytes = [long](64GB)
                return $data
            }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Degraded overall health' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
        It -Name 'Should compute memory usage above 90 percent' -Test { $script:result.MemoryUsagePercent | Should -BeGreaterThan 90 }
    }

    Context 'When executing against a remote computer' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:result = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return a non-null result' -Test { $script:result | Should -Not -BeNullOrEmpty }
        It -Name 'Should return a populated result object' -Test { $script:result | Should -Not -BeNullOrEmpty }
        It -Name 'Should set the ComputerName property' -Test { $script:result.ComputerName | Should -Be 'SRV01' }
    }

    Context 'When processing pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:pipelineResults = @('SRV01', 'SRV02') | Get-HyperVHostHealth
        }
        It -Name 'Should return a result for each pipeline input' -Test { $script:pipelineResults.Count | Should -Be 2 }
        It -Name 'Should return distinct ComputerName values' -Test {
            @($script:pipelineResults).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'When remote execution fails' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It -Name 'Should throw when ErrorAction is Stop' -Test { { Get-HyperVHostHealth -ComputerName 'SRV01' -ErrorAction 'Stop' } | Should -Throw }
        It -Name 'Should return null when errors are silenced' -Test {
            $failResult = Get-HyperVHostHealth -ComputerName 'SRV01' -ErrorAction 'SilentlyContinue'
            $failResult | Should -BeNullOrEmpty
        }
    }

    Context 'When validating parameters' {
        It -Name 'Should reject empty ComputerName' -Test { { Get-HyperVHostHealth -ComputerName '' } | Should -Throw }
        It -Name 'Should reject null ComputerName' -Test { { Get-HyperVHostHealth -ComputerName $null } | Should -Throw }
        It -Name 'Should support pipeline input by property name' -Test {
            $pipelineAttr = (Get-Command -Name 'Get-HyperVHostHealth').Parameters['ComputerName'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName }
            $pipelineAttr | Should -Not -BeNullOrEmpty
        }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It -Name 'Should have PSTypeName PSWinOps.HyperVHostHealth' -Test { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.HyperVHostHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-HyperVHostHealth -ComputerName 'SRV01'
        }
        It -Name 'Should have Timestamp matching ISO 8601' -Test { $script:typeResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Get-HyperVHostHealth -ComputerName 'SRV01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Get-HyperVHostHealth -ComputerName 'SRV01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-HyperVHostHealth'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Get-HyperVHostHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Get-HyperVHostHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Get-HyperVHostHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should accept Name alias' -Test {
            $script:cmd = Get-Command -Name 'Get-HyperVHostHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }
}