#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-WSUSHealth' {
    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus = 'Running'; ModuleAvailable = $true; WSUSServerName = 'WSUS01'
            WSUSPort = 8530; IsSSL = $false; DatabaseType = 'WID'; TotalClients = 100
            ClientsNeedingUpdates = 10; ClientsWithErrors = 0; UnapprovedUpdates = 50
            ContentDirPath = 'D:\WSUS'; ContentDirFreeSpaceGB = 45.5
        }
    }

    Context 'Healthy - all checks pass' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should return Healthy overall health' -Test { $script:result.OverallHealth | Should -Be 'Healthy' }
        It -Name 'Should return Running service status' -Test { $script:result.ServiceStatus | Should -Be 'Running' }
        It -Name 'Should return correct WSUS server name' -Test { $script:result.WSUSServerName | Should -Be 'WSUS01' }
        It -Name 'Should return correct total clients' -Test { $script:result.TotalClients | Should -Be 100 }
        It -Name 'Should return zero clients with errors' -Test { $script:result.ClientsWithErrors | Should -Be 0 }
    }

    Context 'RoleUnavailable - module not available' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ModuleAvailable = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should return RoleUnavailable' -Test { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Critical - service not running' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Critical - clients with errors' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ClientsWithErrors = 5
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
        It -Name 'Should return error count' -Test { $script:result.ClientsWithErrors | Should -Be 5 }
    }

    Context 'Critical - low disk below 5GB' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ContentDirFreeSpaceGB = 3.2
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Degraded - more than 30 percent needing updates' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ClientsNeedingUpdates = 35
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Degraded - disk below 20GB' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ContentDirFreeSpaceGB = 15.0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Degraded - more than 100 unapproved' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.UnapprovedUpdates = 150
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:results = 'WSUS01', 'WSUS02' | Get-WSUSHealth
        }
        It -Name 'Should return two results' -Test { $script:results | Should -HaveCount 2 }
        It -Name 'Should call Invoke-Command twice' -Test { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 2 -Exactly }
    }

    Context 'Failure handling' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It -Name 'Should not throw terminating error' -Test { { Get-WSUSHealth -ComputerName 'WSUS01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject empty ComputerName' -Test { { Get-WSUSHealth -ComputerName '' } | Should -Throw }
        It -Name 'Should reject null ComputerName' -Test { { Get-WSUSHealth -ComputerName $null } | Should -Throw }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should have PSTypeName PSWinOps.WSUSHealth' -Test { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.WSUSHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It -Name 'Should have Timestamp matching ISO 8601' -Test { $script:typeResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Get-WSUSHealth -ComputerName 'WSUS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Get-WSUSHealth -ComputerName 'WSUS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-WSUSHealth'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Get-WSUSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Get-WSUSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Get-WSUSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should accept Name alias' -Test {
            $script:cmd = Get-Command -Name 'Get-WSUSHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:hpResult = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should have ComputerName set to WSUS01' { $script:hpResult.ComputerName | Should -Be 'WSUS01' }
        It 'Should have WSUSServerName property' { $script:hpResult.WSUSServerName | Should -Be 'WSUS01' }
        It 'Should have WSUSPort property' { $script:hpResult.WSUSPort | Should -Be 8530 }
        It 'Should have IsSSL property' { $script:hpResult.IsSSL | Should -Be $false }
        It 'Should have DatabaseType property' { $script:hpResult.DatabaseType | Should -Be 'WID' }
        It 'Should have TotalClients property' { $script:hpResult.TotalClients | Should -Be 100 }
        It 'Should have ClientsNeedingUpdates property' { $script:hpResult.ClientsNeedingUpdates | Should -Be 10 }
        It 'Should have ClientsWithErrors property' { $script:hpResult.ClientsWithErrors | Should -Be 0 }
        It 'Should have ContentDirFreeSpaceGB property' { $script:hpResult.ContentDirFreeSpaceGB | Should -Be 45.5 }
        It 'Should have OverallHealth property' { $script:hpResult.OverallHealth | Should -Not -BeNullOrEmpty }
    }

    Context 'Error message content on failure' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should include computer name in error message' {
            Get-WSUSHealth -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'BADHOST'
        }
        It 'Should include function name in error message' {
            Get-WSUSHealth -ComputerName 'BADHOST2' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'Get-WSUSHealth'
        }
    }
}
