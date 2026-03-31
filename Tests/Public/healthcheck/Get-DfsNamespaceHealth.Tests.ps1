#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Stub functions for cmdlets not available on CI runner
    function global:Get-DfsnRoot { }
    function global:Get-DfsnRootTarget { }

}

AfterAll {
    Remove-Item -Path 'Function:Get-DfsnRoot' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-DfsnRootTarget' -ErrorAction SilentlyContinue
}


Describe 'Get-DfsNamespaceHealth' {

    BeforeAll {
        $script:mockServiceRunning = [PSCustomObject]@{
            Name   = 'Dfs'
            Status = 'Running'
        }

        $script:mockServiceStopped = [PSCustomObject]@{
            Name   = 'Dfs'
            Status = 'Stopped'
        }

        $script:mockDfsnModule = [PSCustomObject]@{
            Name    = 'DFSN'
            Version = [Version]'1.0.0'
        }

        $script:mockDfsnRoot = [PSCustomObject]@{
            Path  = '\\contoso.com\Share'
            Type  = 'DomainV2'
            State = 'Online'
        }

        $script:mockTargetsAllOnline = @(
            [PSCustomObject]@{ TargetPath = '\\SRV01\Share'; State = 'Online' },
            [PSCustomObject]@{ TargetPath = '\\SRV02\Share'; State = 'Online' }
        )

        $script:mockTargetsMixed = @(
            [PSCustomObject]@{ TargetPath = '\\SRV01\Share'; State = 'Online' },
            [PSCustomObject]@{ TargetPath = '\\SRV02\Share'; State = 'Offline' }
        )

        $script:mockRemoteResult = @(
            @{
                ServiceStatus  = 'Running'
                RootPath       = '\\contoso.com\Share'
                RootType       = 'DomainV2'
                State          = 'Online'
                TargetCount    = 2
                HealthyTargets = 2
                DfsnAvailable  = $true
                QueryError     = $false
            }
        )
    }

    Context 'RoleUnavailable - DFSN module not available' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:results = Get-DfsNamespaceHealth
        }

        It -Name 'Should return at least one result' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have OverallHealth RoleUnavailable' -Test {
            $script:results[0].OverallHealth | Should -Be 'RoleUnavailable'
        }

        It -Name 'Should have ServiceName Dfs' -Test {
            $script:results[0].ServiceName | Should -Be 'Dfs'
        }
    }

    Context 'Healthy - all targets online' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnRoot }
            Mock -CommandName 'Get-DfsnRootTarget' -ModuleName 'PSWinOps' -MockWith { return $script:mockTargetsAllOnline }
            $script:results = Get-DfsNamespaceHealth
        }

        It -Name 'Should have OverallHealth Healthy' -Test {
            $script:results[0].OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should have TargetCount 2' -Test {
            $script:results[0].TargetCount | Should -Be 2
        }

        It -Name 'Should have HealthyTargets 2' -Test {
            $script:results[0].HealthyTargets | Should -Be 2
        }

        It -Name 'Should have ServiceStatus Running' -Test {
            $script:results[0].ServiceStatus | Should -Be 'Running'
        }

        It -Name 'Should have a RootPath value' -Test {
            $script:results[0].RootPath | Should -Not -Be 'N/A'
        }

        It -Name 'Should have a Timestamp value' -Test {
            $script:results[0].Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Degraded - some targets offline' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnRoot }
            Mock -CommandName 'Get-DfsnRootTarget' -ModuleName 'PSWinOps' -MockWith { return $script:mockTargetsMixed }
            $script:results = Get-DfsNamespaceHealth
        }

        It -Name 'Should have OverallHealth Degraded' -Test {
            $script:results[0].OverallHealth | Should -Be 'Degraded'
        }

        It -Name 'Should have TargetCount 2' -Test {
            $script:results[0].TargetCount | Should -Be 2
        }

        It -Name 'Should have HealthyTargets 1' -Test {
            $script:results[0].HealthyTargets | Should -Be 1
        }
    }

    Context 'Critical - service stopped' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceStopped }
            $script:results = Get-DfsNamespaceHealth
        }

        It -Name 'Should have OverallHealth Critical' -Test {
            $script:results[0].OverallHealth | Should -Be 'Critical'
        }

        It -Name 'Should have ServiceStatus Stopped' -Test {
            $script:results[0].ServiceStatus | Should -Be 'Stopped'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteResult }
            $script:results = Get-DfsNamespaceHealth -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return a result with Timestamp' -Test { $script:results.Timestamp | Should -Not -BeNullOrEmpty }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteResult }
            $script:results = @('SRV01', 'SRV02') | Get-DfsNamespaceHealth
        }

        It -Name 'Should return a result for each pipeline input' -Test {
            @($script:results).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-DfsNamespaceHealth -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-DfsNamespaceHealth -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-DfsNamespaceHealth -ComputerName $null } | Should -Throw
        }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnRoot) }
            Mock -CommandName 'Get-DfsnRootTarget' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnTarget) }
            $script:typeResult = Get-DfsNamespaceHealth
        }
        It -Name 'Should have PSTypeName PSWinOps.DfsNamespaceHealth' -Test { (@($script:typeResult))[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.DfsNamespaceHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnRoot) }
            Mock -CommandName 'Get-DfsnRootTarget' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnTarget) }
            $script:typeResult = Get-DfsNamespaceHealth
        }
        It -Name 'Should have Timestamp matching ISO 8601' -Test { (@($script:typeResult))[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnRoot) }
            Mock -CommandName 'Get-DfsnRootTarget' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnTarget) }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Get-DfsNamespaceHealth -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Get-DfsNamespaceHealth -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-DfsNamespaceHealth'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Get-DfsNamespaceHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Get-DfsNamespaceHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Get-DfsNamespaceHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should accept Name alias' -Test {
            $script:cmd = Get-Command -Name 'Get-DfsNamespaceHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }

    Context 'Local - Get-DfsnRoot throws (Critical)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { throw 'Access denied' }
            $script:results = Get-DfsNamespaceHealth
        }

        It 'Should have OverallHealth Critical' { $script:results[0].OverallHealth | Should -Be 'Critical' }
        It 'Should have RootPath N/A' { $script:results[0].RootPath | Should -Be 'N/A' }
    }

    Context 'Local - Zero roots (Healthy)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return @() }
            $script:results = Get-DfsNamespaceHealth
        }

        It 'Should have OverallHealth Healthy' { $script:results[0].OverallHealth | Should -Be 'Healthy' }
        It 'Should have RootPath N/A' { $script:results[0].RootPath | Should -Be 'N/A' }
        It 'Should have TargetCount 0' { $script:results[0].TargetCount | Should -Be 0 }
    }

    Context 'Local - Get-DfsnRootTarget throws (Critical, 0 targets)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnRoot) }
            Mock -CommandName 'Get-DfsnRootTarget' -ModuleName 'PSWinOps' -MockWith { throw 'Target query failed' }
            $script:results = Get-DfsNamespaceHealth
        }

        It 'Should have OverallHealth Critical' { $script:results[0].OverallHealth | Should -Be 'Critical' }
        It 'Should have TargetCount 0' { $script:results[0].TargetCount | Should -Be 0 }
        It 'Should have HealthyTargets 0' { $script:results[0].HealthyTargets | Should -Be 0 }
    }

    Context 'Local - All targets offline (Critical)' {

        BeforeAll {
            $allOffline = @(
                [PSCustomObject]@{ TargetPath = '\\SRV01\Share'; State = 'Offline' },
                [PSCustomObject]@{ TargetPath = '\\SRV02\Share'; State = 'Offline' }
            )
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnRoot) }
            Mock -CommandName 'Get-DfsnRootTarget' -ModuleName 'PSWinOps' -MockWith { return $allOffline }
            $script:results = Get-DfsNamespaceHealth
        }

        It 'Should have OverallHealth Critical' { $script:results[0].OverallHealth | Should -Be 'Critical' }
        It 'Should have TargetCount 2' { $script:results[0].TargetCount | Should -Be 2 }
        It 'Should have HealthyTargets 0' { $script:results[0].HealthyTargets | Should -Be 0 }
    }

    Context 'Local - Service not found (DFS not installed)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'not found' }
            $script:results = Get-DfsNamespaceHealth
        }

        It 'Should have ServiceStatus NotFound' { $script:results[0].ServiceStatus | Should -Be 'NotFound' }
        It 'Should have OverallHealth RoleUnavailable' { $script:results[0].OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Local - localhost alias' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnRoot) }
            Mock -CommandName 'Get-DfsnRootTarget' -ModuleName 'PSWinOps' -MockWith { return $script:mockTargetsAllOnline }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
            $script:results = Get-DfsNamespaceHealth -ComputerName 'localhost'
        }

        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return LOCALHOST as ComputerName' { $script:results[0].ComputerName | Should -Be 'LOCALHOST' }
    }

    Context 'Local - dot alias' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockDfsnModule }
            Mock -CommandName 'Get-DfsnRoot' -ModuleName 'PSWinOps' -MockWith { return @($script:mockDfsnRoot) }
            Mock -CommandName 'Get-DfsnRootTarget' -ModuleName 'PSWinOps' -MockWith { return $script:mockTargetsAllOnline }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
            $script:results = Get-DfsNamespaceHealth -ComputerName '.'
        }

        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return a result' { $script:results | Should -Not -BeNullOrEmpty }
    }
}