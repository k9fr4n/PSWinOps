#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-ADFSHealth' {
    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus = 'Running'; ModuleAvailable = $true; FederationServiceName = 'fs.contoso.com'
            SslCertExpiry = '2028-01-01 00:00:00'; SslCertDaysRemaining = 700
            TotalRelyingParties = 15; EnabledRelyingParties = 12; EnabledEndpoints = 8; ServerHealthOK = $true
        }
    }

    Context 'Healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It -Name 'Should return Healthy' -Test { $script:result.OverallHealth | Should -Be 'Healthy' }
        It -Name 'Should return correct federation name' -Test { $script:result.FederationServiceName | Should -Be 'fs.contoso.com' }
        It -Name 'Should return correct cert days' -Test { $script:result.SslCertDaysRemaining | Should -Be 700 }
        It -Name 'Should report health OK' -Test { $script:result.ServerHealthOK | Should -BeTrue }
    }

    Context 'RoleUnavailable' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ModuleAvailable = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It -Name 'Should return RoleUnavailable' -Test { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Critical - service stopped' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Critical - cert expired' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SslCertDaysRemaining = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Critical - health test failed' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServerHealthOK = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Degraded - cert expiring soon' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SslCertDaysRemaining = 20
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Degraded - zero relying parties' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.EnabledRelyingParties = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:results = 'ADFS01', 'ADFS02' | Get-ADFSHealth
        }
        It -Name 'Should return two results' -Test { $script:results | Should -HaveCount 2 }
    }

    Context 'Failure handling' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It -Name 'Should not throw' -Test { { Get-ADFSHealth -ComputerName 'ADFS01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject empty ComputerName' -Test { { Get-ADFSHealth -ComputerName '' } | Should -Throw }
        It -Name 'Should reject null ComputerName' -Test { { Get-ADFSHealth -ComputerName $null } | Should -Throw }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It -Name 'Should have PSTypeName PSWinOps.ADFSHealth' -Test { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADFSHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It -Name 'Should have Timestamp matching ISO 8601' -Test { $script:typeResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Get-ADFSHealth -ComputerName 'ADFS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Get-ADFSHealth -ComputerName 'ADFS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-ADFSHealth'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Get-ADFSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Get-ADFSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Get-ADFSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should accept Name alias' -Test {
            $script:cmd = Get-Command -Name 'Get-ADFSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:hpResult = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should have ComputerName set to ADFS01' { $script:hpResult.ComputerName | Should -Be 'ADFS01' }
        It 'Should have ServiceName property' { $script:hpResult.ServiceName | Should -Be 'adfssrv' }
        It 'Should have FederationServiceName property' { $script:hpResult.FederationServiceName | Should -Be 'fs.contoso.com' }
        It 'Should have SslCertDaysRemaining property' { $script:hpResult.SslCertDaysRemaining | Should -Be 700 }
        It 'Should have TotalRelyingParties property' { $script:hpResult.TotalRelyingParties | Should -Be 15 }
        It 'Should have EnabledRelyingParties property' { $script:hpResult.EnabledRelyingParties | Should -Be 12 }
        It 'Should have EnabledEndpoints property' { $script:hpResult.EnabledEndpoints | Should -Be 8 }
        It 'Should have ServerHealthOK property' { $script:hpResult.ServerHealthOK | Should -Be $true }
        It 'Should have OverallHealth property' { $script:hpResult.OverallHealth | Should -Not -BeNullOrEmpty }
    }

    Context 'Error message content on failure' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should include computer name in error message' {
            Get-ADFSHealth -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'BADHOST'
        }
        It 'Should include function name in error message' {
            Get-ADFSHealth -ComputerName 'BADHOST2' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'Get-ADFSHealth'
        }
    }
}
