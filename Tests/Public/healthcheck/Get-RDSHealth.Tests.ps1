#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-RDSHealth' {
    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus = 'Running'; SessionEnvStatus = 'Running'; RDModuleAvailable = $true
            InstalledRoles = 'RDS-SESSION-HOST, RDS-LICENSING'; ActiveSessions = 5
            DisconnectedSessions = 2; LicensingMode = 'PerUser'
        }
    }

    Context 'Healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It -Name 'Should return Healthy' -Test { $script:result.OverallHealth | Should -Be 'Healthy' }
        It -Name 'Should return Running service' -Test { $script:result.ServiceStatus | Should -Be 'Running' }
        It -Name 'Should return Running SessionEnv' -Test { $script:result.SessionEnvStatus | Should -Be 'Running' }
        It -Name 'Should compute TotalSessions' -Test { $script:result.TotalSessions | Should -Be 7 }
        It -Name 'Should return correct roles' -Test { $script:result.InstalledRoles | Should -Be 'RDS-SESSION-HOST, RDS-LICENSING' }
    }

    Context 'RoleUnavailable' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'NotFound'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It -Name 'Should return RoleUnavailable' -Test { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Critical - service stopped' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Critical - SessionEnv stopped' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SessionEnvStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Degraded - more disconnected than active' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ActiveSessions = 2; $d.DisconnectedSessions = 10
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
        It -Name 'Should compute TotalSessions' -Test { $script:result.TotalSessions | Should -Be 12 }
    }

    Context 'Degraded - licensing not configured' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.LicensingMode = 'NotConfigured'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:results = 'RDS01', 'RDS02' | Get-RDSHealth
        }
        It -Name 'Should return two results' -Test { $script:results | Should -HaveCount 2 }
    }

    Context 'Failure handling' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It -Name 'Should not throw' -Test { { Get-RDSHealth -ComputerName 'RDS01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject empty ComputerName' -Test { { Get-RDSHealth -ComputerName '' } | Should -Throw }
        It -Name 'Should reject null ComputerName' -Test { { Get-RDSHealth -ComputerName $null } | Should -Throw }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-RDSHealth -ComputerName 'RDS01'
        }
        It -Name 'Should have PSTypeName PSWinOps.RDSHealth' -Test { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.RDSHealth' }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:propResult = Get-RDSHealth -ComputerName 'RDS01'
        }
        It -Name 'Should have ComputerName set to RDS01' -Test { $script:propResult.ComputerName | Should -Be 'RDS01' }
        It -Name 'Should have ServiceName set to TermService' -Test { $script:propResult.ServiceName | Should -Be 'TermService' }
        It -Name 'Should have ActiveSessions property' -Test { $script:propResult.ActiveSessions | Should -Be 5 }
        It -Name 'Should have DisconnectedSessions property' -Test { $script:propResult.DisconnectedSessions | Should -Be 2 }
        It -Name 'Should have TotalSessions computed correctly' -Test { $script:propResult.TotalSessions | Should -Be 7 }
        It -Name 'Should have InstalledRoles property' -Test { $script:propResult.InstalledRoles | Should -Not -BeNullOrEmpty }
        It -Name 'Should have LicensingMode property' -Test { $script:propResult.LicensingMode | Should -Be 'PerUser' }
        It -Name 'Should have RDModuleAvailable property' -Test { $script:propResult.RDModuleAvailable | Should -BeTrue }
        It -Name 'Should have SessionEnvStatus property' -Test { $script:propResult.SessionEnvStatus | Should -Be 'Running' }
        It -Name 'Should have Timestamp in ISO 8601 format' -Test { $script:propResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Get-RDSHealth -ComputerName 'RDS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Get-RDSHealth -ComputerName 'RDS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-RDSHealth'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Get-RDSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Get-RDSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Get-RDSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should accept Name alias' -Test {
            $script:cmd = Get-Command -Name 'Get-RDSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:hpResult = Get-RDSHealth -ComputerName 'RDS01'
        }
        It 'Should have Timestamp matching ISO 8601 pattern' { $script:hpResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Error message content on failure' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should include computer name in error message' {
            Get-RDSHealth -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'BADHOST'
        }
        It 'Should include function name in error message' {
            Get-RDSHealth -ComputerName 'BADHOST2' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'Get-RDSHealth'
        }
    }
}
