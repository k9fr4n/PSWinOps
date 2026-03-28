#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
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
            QuorumType     = 'NodeAndDiskMajority'
            QuorumResource = $null
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
            QuorumType      = 'NodeAndDiskMajority'
            QuorumState     = 'Normal'
            QueryError      = $null
        }
    }

    Context 'RoleUnavailable - FailoverClusters module not available' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $null }
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

    Context 'Healthy cluster - all nodes up all resources online' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockClusterModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-Cluster' -ModuleName 'PSWinOps' -MockWith { return $script:mockCluster }
            Mock -CommandName 'Get-ClusterNode' -ModuleName 'PSWinOps' -MockWith { return $script:mockNodesAllUp }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -MockWith { return $script:mockResourcesAllOnline }
            Mock -CommandName 'Get-ClusterGroup' -ModuleName 'PSWinOps' -MockWith { return $script:mockGroupsAllOnline }
            Mock -CommandName 'Get-ClusterQuorum' -ModuleName 'PSWinOps' -MockWith { return $script:mockQuorum }
            $script:results = Get-ClusterHealth
        }

        It -Name 'Should have OverallHealth Healthy' -Test {
            $script:results[0].OverallHealth | Should -Be 'Healthy'
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

    Context 'Critical - node down' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $script:mockClusterModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-Cluster' -ModuleName 'PSWinOps' -MockWith { return $script:mockCluster }
            Mock -CommandName 'Get-ClusterNode' -ModuleName 'PSWinOps' -MockWith { return $script:mockNodesOneDown }
            Mock -CommandName 'Get-ClusterResource' -ModuleName 'PSWinOps' -MockWith { return $script:mockResourcesAllOnline }
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

        It -Name 'Should call Invoke-Command' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = @('SRV01', 'SRV02') | Get-ClusterHealth
        }

        It -Name 'Should call Invoke-Command for each machine' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 2 -Exactly
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