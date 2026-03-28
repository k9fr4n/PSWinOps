#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-PrintServerHealth' {
    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus = 'Running'; ModuleAvailable = $true; TotalPrinters = 10
            PrintersOnline = 8; PrintersInError = 0; PrintersOffline = 0
            TotalPrintJobs = 25; ErroredPrintJobs = 0; TotalPorts = 12
        }
    }

    Context 'Healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It -Name 'Should return Healthy' -Test { $script:result.OverallHealth | Should -Be 'Healthy' }
        It -Name 'Should return correct printer count' -Test { $script:result.TotalPrinters | Should -Be 10 }
        It -Name 'Should return correct online count' -Test { $script:result.PrintersOnline | Should -Be 8 }
        It -Name 'Should return zero errors' -Test { $script:result.PrintersInError | Should -Be 0 }
        It -Name 'Should return correct port count' -Test { $script:result.TotalPorts | Should -Be 12 }
    }

    Context 'RoleUnavailable' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ModuleAvailable = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It -Name 'Should return RoleUnavailable' -Test { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Critical - service stopped' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Critical - printers in error' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.PrintersInError = 3
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
        It -Name 'Should return error count' -Test { $script:result.PrintersInError | Should -Be 3 }
    }

    Context 'Degraded - printers offline' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.PrintersOffline = 2
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Degraded - errored print jobs' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ErroredPrintJobs = 4
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:results = 'PRINT01', 'PRINT02' | Get-PrintServerHealth
        }
        It -Name 'Should return two results' -Test { $script:results | Should -HaveCount 2 }
    }

    Context 'Failure handling' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It -Name 'Should not throw' -Test { { Get-PrintServerHealth -ComputerName 'PRINT01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject empty ComputerName' -Test { { Get-PrintServerHealth -ComputerName '' } | Should -Throw }
        It -Name 'Should reject null ComputerName' -Test { { Get-PrintServerHealth -ComputerName $null } | Should -Throw }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It -Name 'Should have PSTypeName PSWinOps.PrintServerHealth' -Test { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.PrintServerHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It -Name 'Should have Timestamp matching ISO 8601' -Test { $script:typeResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Get-PrintServerHealth -ComputerName 'PRINT01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Get-PrintServerHealth -ComputerName 'PRINT01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-PrintServerHealth'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Get-PrintServerHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Get-PrintServerHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Get-PrintServerHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should accept Name alias' -Test {
            $script:cmd = Get-Command -Name 'Get-PrintServerHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:hpResult = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should have ComputerName set to PRINT01' { $script:hpResult.ComputerName | Should -Be 'PRINT01' }
        It 'Should have ServiceName property' { $script:hpResult.ServiceName | Should -Be 'Spooler' }
        It 'Should have TotalPrinters property' { $script:hpResult.TotalPrinters | Should -Be 10 }
        It 'Should have PrintersOnline property' { $script:hpResult.PrintersOnline | Should -Be 8 }
        It 'Should have PrintersInError property' { $script:hpResult.PrintersInError | Should -Be 0 }
        It 'Should have PrintersOffline property' { $script:hpResult.PrintersOffline | Should -Be 0 }
        It 'Should have TotalPrintJobs property' { $script:hpResult.TotalPrintJobs | Should -Be 25 }
        It 'Should have ErroredPrintJobs property' { $script:hpResult.ErroredPrintJobs | Should -Be 0 }
        It 'Should have TotalPorts property' { $script:hpResult.TotalPorts | Should -Be 12 }
        It 'Should have OverallHealth property' { $script:hpResult.OverallHealth | Should -Not -BeNullOrEmpty }
    }

    Context 'Error message content on failure' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should include computer name in error message' {
            Get-PrintServerHealth -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'BADHOST'
        }
        It 'Should include function name in error message' {
            Get-PrintServerHealth -ComputerName 'BADHOST2' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'Get-PrintServerHealth'
        }
    }
}
