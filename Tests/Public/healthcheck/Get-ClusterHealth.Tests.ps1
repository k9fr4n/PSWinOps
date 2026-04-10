#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Stub functions for cmdlets not available on CI runner
    function global:Get-Cluster { }
    function global:Get-ClusterNode { }
    function global:Get-ClusterResource { param($Name) }
    function global:Get-ClusterGroup { }
    function global:Get-ClusterQuorum { }

}

AfterAll {
    Remove-Item -Path 'Function:Get-Cluster' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-ClusterNode' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-ClusterResource' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-ClusterGroup' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-ClusterQuorum' -ErrorAction SilentlyContinue
}


Describe 'Get-ClusterHealth' {

    BeforeAll {
        $script:mockServiceRunning = [PSCustomObject]@{
            Name   = 'ClusSvc'
            Status = 'Running'
        }

        $script:mockClusterModule = [PSCustomObject]@{
            Name    = 'FailoverClusters'
            Version = [Version]'2.0.0'
        }

        $script:mockCluster = [PSCustomObject]@{ Name = 'CLUSTER01' }

        $script:mockNodesAllUp = @(
            [PSCustomObject]@{ Name = 'NODE01'; State = 'Up' },
            [PSCustomObject]@{ Name = 'NODE02'; State = 'Up' }
        )

        $script:mockNodesOneDown = @(
            [PSCustomObject]@{ Name = 'NODE01'; State = 'Up' },
            [PSCustomObject]@{ Name = 'NODE02'; State = 'Down' }
        )

        $script:mockNodesOnePaused = @(
            [PSCustomObject]@{ Name = 'NODE01'; State = 'Up' },
            [PSCustomObject]@{ Name = 'NODE02'; State = 'Paused' }
        )

        $script:mockResourcesAllOnline = @(
            [PSCustomObject]@{ Name = 'IP Address 10.0.0.1'; State = 'Online' },
            [PSCustomObject]@{ Name = 'Cluster Name'; State = 'Online' },
            [PSCustomObject]@{ Name = 'Cluster Disk 1'; State = 'Online' }
        )

        $script:mockGroupsAllOnline = @(
            [PSCustomObject]@{ Name = 'Cluster Group'; State = 'Online' },
            [PSCustomObject]@{ Name = 'Available Storage'; State = 'Online' }
        )

        $script:mockQuorum = [PSCustomObject]@{
            QuorumType     = 'NodeAndFileShareMajority'
            QuorumResource = 'File Share Witness'
        }

        $script:mockQuorumNoWitness = [PSCustomObject]@{
            QuorumType     = 'NodeMajority'
            QuorumResource = $null
        }

        $script:mockWitnessResource = [PSCustomObject]@{
            Name         = 'File Share Witness'
            State        = 'Online'
            ResourceType = 'File Share Witness'
        }

        $script:mockWitnessResourceFailed = [PSCustomObject]@{
            Name         = 'File Share Witness'
            State        = 'Failed'
            ResourceType = 'File Share Witness'
        }

        $script:mockRemoteData = @{
            ServiceStatus   = 'Running'
            ModuleAvailable = $true
            ClusterName     = 'CLUSTER01'
            NodeName        = 'NODE01'
            NodeState       = 'Up'
            TotalNodes      = 2
            NodesUp         = 2
            NodesDown       = 0
            NodesPaused     = 0
            TotalResources  = 3
            ResourcesOnline = 3
            ResourcesFailed = 0
            TotalGroups     = 2
            GroupsOnline    = 2
            QuorumType      = 'NodeAndFileShareMajority'
            QuorumState     = 'Normal'
            WitnessType     = 'FileShareWitness'
            WitnessName     = 'File Share Witness'
            WitnessState    = 'Online'
            QueryError      = $null
        }
    }

    Context 'RoleUnavailable - FailoverClusters module not available' {

        BeforeAll {
            # Mock Invoke-RemoteOrLocal to return data indicating the module is not available
            # This avoids the issue where global Get-Cluster stub makes Get-Command succeed
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                @{
                    ServiceStatus   = 'Running'
                    ModuleAvailable = $false
                    ClusterName     = 'N/A'
                    NodeName        = 'N/A'
                    NodeState       = 'N/A'
                    TotalNodes      = 0
                    NodesUp         = 0
                    NodesDown       = 0
                    NodesPaused     = 0
                    TotalResources  = 0
                    ResourcesOnline = 0
                    ResourcesFailed = 0
                    TotalGroups     = 0
                    GroupsOnline    = 0
                    QuorumType      = 'N/A'
                    QuorumState     = 'N/A'
                    WitnessType     = 'N/A'
                    WitnessName     = 'N/A'
                    WitnessState    = 'N/A'
                    QueryError      = $null
                }
            }
            $script:results = Get-ClusterHealth
        }

        It -Name 'Should return at least one result' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have OverallHealth RoleUnavailable' -Test {
            $script:results[0].OverallHealth | Should -Be 'RoleUnavailable'
        }

        It -Name 'Should have ServiceName ClusSvc' -Test {
            $script:results[0].ServiceName | Should -Be 'ClusSvc'
        }
    }

    Context 'Healthy cluster with file share witness online' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockClusterModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-Cluster' -ModuleName 'PSWinOps' -MockWith { return $script:mockCluster }
            Mock -CommandName 'Get-ClusterNode' -ModuleName 'PSWinOps' -MockWith { return $script:mockNodesAllUp }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -MockWith { return $script:mockResourcesAllOnline }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'File Share Witness' } -MockWith { return $script:mockWitnessResource }
            Mock -CommandName 'Get-ClusterGroup' -ModuleName 'PSWinOps' -MockWith { return $script:mockGroupsAllOnline }
            Mock -CommandName 'Get-ClusterQuorum' -ModuleName 'PSWinOps' -MockWith { return $script:mockQuorum }
            $script:results = Get-ClusterHealth
        }

        It -Name 'Should have OverallHealth Healthy' -Test {
            $script:results[0].OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should have WitnessType FileShareWitness' -Test {
            $script:results[0].WitnessType | Should -Be 'FileShareWitness'
        }

        It -Name 'Should have WitnessName File Share Witness' -Test {
            $script:results[0].WitnessName | Should -Be 'File Share Witness'
        }

        It -Name 'Should have WitnessState Online' -Test {
            $script:results[0].WitnessState | Should -Be 'Online'
        }

        It -Name 'Should have TotalNodes 2' -Test {
            $script:results[0].TotalNodes | Should -Be 2
        }

        It -Name 'Should have NodesUp 2' -Test {
            $script:results[0].NodesUp | Should -Be 2
        }

        It -Name 'Should have TotalResources 3' -Test {
            $script:results[0].TotalResources | Should -Be 3
        }

        It -Name 'Should have ResourcesOnline 3' -Test {
            $script:results[0].ResourcesOnline | Should -Be 3
        }

        It -Name 'Should have ResourcesFailed 0' -Test {
            $script:results[0].ResourcesFailed | Should -Be 0
        }

        It -Name 'Should have ClusterName CLUSTER01' -Test {
            $script:results[0].ClusterName | Should -Be 'CLUSTER01'
        }

        It -Name 'Should have ServiceStatus Running' -Test {
            $script:results[0].ServiceStatus | Should -Be 'Running'
        }

        It -Name 'Should have a Timestamp value' -Test {
            $script:results[0].Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Healthy cluster with no witness' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockClusterModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-Cluster' -ModuleName 'PSWinOps' -MockWith { return $script:mockCluster }
            Mock -CommandName 'Get-ClusterNode' -ModuleName 'PSWinOps' -MockWith { return $script:mockNodesAllUp }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -MockWith { return $script:mockResourcesAllOnline }
            Mock -CommandName 'Get-ClusterGroup' -ModuleName 'PSWinOps' -MockWith { return $script:mockGroupsAllOnline }
            Mock -CommandName 'Get-ClusterQuorum' -ModuleName 'PSWinOps' -MockWith { return $script:mockQuorumNoWitness }
            $script:results = Get-ClusterHealth
        }

        It -Name 'Should have OverallHealth Healthy' -Test {
            $script:results[0].OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should have WitnessType None' -Test {
            $script:results[0].WitnessType | Should -Be 'None'
        }

        It -Name 'Should have WitnessName N/A' -Test {
            $script:results[0].WitnessName | Should -Be 'N/A'
        }

        It -Name 'Should have WitnessState N/A' -Test {
            $script:results[0].WitnessState | Should -Be 'N/A'
        }

        It -Name 'Should have QuorumType NodeMajority' -Test {
            $script:results[0].QuorumType | Should -Be 'NodeMajority'
        }
    }

    Context 'Degraded - witness failed' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockClusterModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-Cluster' -ModuleName 'PSWinOps' -MockWith { return $script:mockCluster }
            Mock -CommandName 'Get-ClusterNode' -ModuleName 'PSWinOps' -MockWith { return $script:mockNodesAllUp }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -MockWith { return $script:mockResourcesAllOnline }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'File Share Witness' } -MockWith { return $script:mockWitnessResourceFailed }
            Mock -CommandName 'Get-ClusterGroup' -ModuleName 'PSWinOps' -MockWith { return $script:mockGroupsAllOnline }
            Mock -CommandName 'Get-ClusterQuorum' -ModuleName 'PSWinOps' -MockWith { return $script:mockQuorum }
            $script:results = Get-ClusterHealth
        }

        It -Name 'Should have WitnessState Failed' -Test {
            $script:results[0].WitnessState | Should -Be 'Failed'
        }

        It -Name 'Should have OverallHealth Degraded' -Test {
            $script:results[0].OverallHealth | Should -Be 'Degraded'
        }

        It -Name 'Should have QuorumState Warning' -Test {
            $script:results[0].QuorumState | Should -Be 'Warning'
        }
    }

    Context 'Critical - node down' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockClusterModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-Cluster' -ModuleName 'PSWinOps' -MockWith { return $script:mockCluster }
            Mock -CommandName 'Get-ClusterNode' -ModuleName 'PSWinOps' -MockWith { return $script:mockNodesOneDown }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -MockWith { return $script:mockResourcesAllOnline }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'File Share Witness' } -MockWith { return $script:mockWitnessResource }
            Mock -CommandName 'Get-ClusterGroup' -ModuleName 'PSWinOps' -MockWith { return $script:mockGroupsAllOnline }
            Mock -CommandName 'Get-ClusterQuorum' -ModuleName 'PSWinOps' -MockWith { return $script:mockQuorum }
            $script:results = Get-ClusterHealth
        }

        It -Name 'Should have OverallHealth Critical' -Test {
            $script:results[0].OverallHealth | Should -Be 'Critical'
        }

        It -Name 'Should have NodesUp 1' -Test {
            $script:results[0].NodesUp | Should -Be 1
        }
    }

    Context 'Degraded - node paused' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockClusterModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-Cluster' -ModuleName 'PSWinOps' -MockWith { return $script:mockCluster }
            Mock -CommandName 'Get-ClusterNode' -ModuleName 'PSWinOps' -MockWith { return $script:mockNodesOnePaused }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -MockWith { return $script:mockResourcesAllOnline }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'File Share Witness' } -MockWith { return $script:mockWitnessResource }
            Mock -CommandName 'Get-ClusterGroup' -ModuleName 'PSWinOps' -MockWith { return $script:mockGroupsAllOnline }
            Mock -CommandName 'Get-ClusterQuorum' -ModuleName 'PSWinOps' -MockWith { return $script:mockQuorum }
            $script:results = Get-ClusterHealth
        }

        It -Name 'Should have OverallHealth Degraded' -Test {
            $script:results[0].OverallHealth | Should -Be 'Degraded'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = Get-ClusterHealth -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should have ClusterName CLUSTER01' -Test {
            $script:results[0].ClusterName | Should -Be 'CLUSTER01'
        }

        It -Name 'Should have WitnessType FileShareWitness' -Test {
            $script:results[0].WitnessType | Should -Be 'FileShareWitness'
        }

        It -Name 'Should have WitnessName File Share Witness' -Test {
            $script:results[0].WitnessName | Should -Be 'File Share Witness'
        }

        It -Name 'Should have WitnessState Online' -Test {
            $script:results[0].WitnessState | Should -Be 'Online'
        }

        It -Name 'Should return a result with Timestamp' -Test { $script:results.Timestamp | Should -Not -BeNullOrEmpty }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = @('SRV01', 'SRV02') | Get-ClusterHealth
        }

        It -Name 'Should return distinct ComputerName values' -Test {
            $names = @($script:results) | Select-Object -ExpandProperty ComputerName -Unique
            @($names).Count | Should -Be 2
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-ClusterHealth -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-ClusterHealth -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-ClusterHealth -ComputerName $null } | Should -Throw
        }
    }
}