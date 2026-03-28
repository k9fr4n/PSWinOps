#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-DfsReplicationHealth' {

    BeforeAll {
        $script:mockServiceRunning = [PSCustomObject]@{
            Name   = 'DFSR'
            Status = 'Running'
        }

        $script:mockServiceStopped = [PSCustomObject]@{
            Name   = 'DFSR'
            Status = 'Stopped'
        }

        # State values: 0=Uninitialized, 1=Initialized, 2=Initial Sync, 3=Auto Recovery, 4=Normal, 5=In Error
        $script:mockCimNormal = @(
            [PSCustomObject]@{
                ReplicationGroupName    = 'Domain System Volume'
                ReplicatedFolderName    = 'SYSVOL Share'
                State                   = 4
                CurrentConflictSizeInMb = 0
            }
        )

        $script:mockCimInError = @(
            [PSCustomObject]@{
                ReplicationGroupName    = 'Domain System Volume'
                ReplicatedFolderName    = 'SYSVOL Share'
                State                   = 5
                CurrentConflictSizeInMb = 128
            }
        )

        $script:mockCimInitialSync = @(
            [PSCustomObject]@{
                ReplicationGroupName    = 'Domain System Volume'
                ReplicatedFolderName    = 'SYSVOL Share'
                State                   = 2
                CurrentConflictSizeInMb = 0
            }
        )

        $script:mockRemoteHashtable = @(
            @{
                ServiceStatus        = 'Running'
                ReplicationGroupName = 'Domain System Volume'
                ReplicatedFolderName = 'SYSVOL Share'
                State                = 'Normal'
                CurrentConflictSize  = [long]0
                OverallHealth        = 'Healthy'
            }
        )
    }

    Context 'RoleUnavailable - DFSR CIM class not available' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { throw 'Invalid namespace' }
            $script:results = Get-DfsReplicationHealth
        }

        It -Name 'Should return at least one result' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have OverallHealth RoleUnavailable' -Test {
            $script:results[0].OverallHealth | Should -Be 'RoleUnavailable'
        }

        It -Name 'Should have ServiceName DFSR' -Test {
            $script:results[0].ServiceName | Should -Be 'DFSR'
        }
    }

    Context 'Healthy - Normal replication state' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockCimNormal }
            $script:results = Get-DfsReplicationHealth
        }

        It -Name 'Should have OverallHealth Healthy' -Test {
            $script:results[0].OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should have ServiceStatus Running' -Test {
            $script:results[0].ServiceStatus | Should -Be 'Running'
        }

        It -Name 'Should have State Normal' -Test {
            $script:results[0].State | Should -Be 'Normal'
        }

        It -Name 'Should have a ReplicationGroupName' -Test {
            $script:results[0].ReplicationGroupName | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a Timestamp value' -Test {
            $script:results[0].Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Critical - In Error state' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockCimInError }
            $script:results = Get-DfsReplicationHealth
        }

        It -Name 'Should have OverallHealth Critical' -Test {
            $script:results[0].OverallHealth | Should -Be 'Critical'
        }

        It -Name 'Should have State In Error' -Test {
            $script:results[0].State | Should -Be 'In Error'
        }
    }

    Context 'Degraded - Initial Sync state' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockServiceRunning }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockCimInitialSync }
            $script:results = Get-DfsReplicationHealth
        }

        It -Name 'Should have OverallHealth Degraded' -Test {
            $script:results[0].OverallHealth | Should -Be 'Degraded'
        }

        It -Name 'Should have State Initial Sync' -Test {
            $script:results[0].State | Should -Be 'Initial Sync'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteHashtable }
            $script:results = Get-DfsReplicationHealth -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should call Invoke-Command' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteHashtable }
            $script:results = @('SRV01', 'SRV02') | Get-DfsReplicationHealth
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
            { Get-DfsReplicationHealth -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-DfsReplicationHealth -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-DfsReplicationHealth -ComputerName $null } | Should -Throw
        }
    }
}