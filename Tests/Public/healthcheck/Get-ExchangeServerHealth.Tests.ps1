#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Stub Exchange cmdlets not available on CI runner
    if (-not (Get-Command -Name 'Add-PSSnapin' -ErrorAction SilentlyContinue)) {
        function global:Add-PSSnapin { param($Name) }
    }
    if (-not (Get-Command -Name 'Get-MailboxDatabase' -ErrorAction SilentlyContinue)) {
        function global:Get-MailboxDatabase { param([switch]$Status) }
    }
    if (-not (Get-Command -Name 'Get-Queue' -ErrorAction SilentlyContinue)) {
        function global:Get-Queue { }
    }
    if (-not (Get-Command -Name 'Get-MailboxDatabaseCopyStatus' -ErrorAction SilentlyContinue)) {
        function global:Get-MailboxDatabaseCopyStatus { }
    }
    if (-not (Get-Command -Name 'Get-ExchangeCertificate' -ErrorAction SilentlyContinue)) {
        function global:Get-ExchangeCertificate { }
    }
}

AfterAll {
    Remove-Item -Path 'Function:Get-MailboxDatabase' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-Queue' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-MailboxDatabaseCopyStatus' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:Get-ExchangeCertificate' -ErrorAction SilentlyContinue
}

Describe 'Get-ExchangeServerHealth' {

    BeforeAll {
        # Standard healthy remote mock data
        $script:mockHealthyData = @{
            TransportStatus          = 'Running'
            InformationStoreStatus   = 'Running'
            ADTopologyStatus         = 'Running'
            ServiceHostStatus        = 'Running'
            SnapinAvailable          = $true
            TotalDatabases           = 4
            MountedDatabases         = 4
            DismountedDatabases      = 0
            TotalQueues              = 3
            TotalQueueMessages       = 12
            HighestQueueLength       = 5
            DAGCopiesTotal           = 8
            DAGCopiesHealthy         = 8
            DAGCopiesUnhealthy       = 0
            CertificatesTotal        = 3
            CertificatesExpiringSoon = 0
            CertificatesExpired      = 0
        }
    }

    Context 'RoleUnavailable - Exchange snapin not available' {

        BeforeAll {
            $script:mockNoSnapin = @{
                TransportStatus          = 'NotFound'
                InformationStoreStatus   = 'NotFound'
                ADTopologyStatus         = 'NotFound'
                ServiceHostStatus        = 'NotFound'
                SnapinAvailable          = $false
                TotalDatabases           = 0
                MountedDatabases         = 0
                DismountedDatabases      = 0
                TotalQueues              = 0
                TotalQueueMessages       = 0
                HighestQueueLength       = 0
                DAGCopiesTotal           = 0
                DAGCopiesHealthy         = 0
                DAGCopiesUnhealthy       = 0
                CertificatesTotal        = 0
                CertificatesExpiringSoon = 0
                CertificatesExpired      = 0
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockNoSnapin }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return RoleUnavailable health status' -Test {
            $script:result.OverallHealth | Should -Be 'RoleUnavailable'
        }

        It -Name 'Should populate the ComputerName property' -Test {
            $script:result.ComputerName | Should -Be 'EX01'
        }

        It -Name 'Should report SnapinAvailable as false via zero databases' -Test {
            $script:result.TotalDatabases | Should -Be 0
        }
    }

    Context 'Healthy - All checks pass' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockHealthyData }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Healthy overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should report Running transport status' -Test {
            $script:result.TransportStatus | Should -Be 'Running'
        }

        It -Name 'Should report Running information store status' -Test {
            $script:result.InformationStoreStatus | Should -Be 'Running'
        }

        It -Name 'Should report 4 total databases' -Test {
            $script:result.TotalDatabases | Should -Be 4
        }

        It -Name 'Should report 4 mounted databases' -Test {
            $script:result.MountedDatabases | Should -Be 4
        }

        It -Name 'Should report 0 dismounted databases' -Test {
            $script:result.DismountedDatabases | Should -Be 0
        }

        It -Name 'Should report 8 healthy DAG copies' -Test {
            $script:result.DAGCopiesHealthy | Should -Be 8
        }

        It -Name 'Should report 0 unhealthy DAG copies' -Test {
            $script:result.DAGCopiesUnhealthy | Should -Be 0
        }

        It -Name 'Should have a Timestamp value' -Test {
            $script:result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Critical - Transport service stopped' {

        BeforeAll {
            $script:mockTransportStopped = $script:mockHealthyData.Clone()
            $script:mockTransportStopped.TransportStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockTransportStopped }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Critical overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Critical'
        }

        It -Name 'Should report Stopped transport status' -Test {
            $script:result.TransportStatus | Should -Be 'Stopped'
        }
    }

    Context 'Critical - Information Store stopped' {

        BeforeAll {
            $script:mockISStopped = $script:mockHealthyData.Clone()
            $script:mockISStopped.InformationStoreStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockISStopped }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Critical overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Critical'
        }

        It -Name 'Should report Stopped information store status' -Test {
            $script:result.InformationStoreStatus | Should -Be 'Stopped'
        }
    }

    Context 'Critical - Database dismounted' {

        BeforeAll {
            $script:mockDBDismounted = $script:mockHealthyData.Clone()
            $script:mockDBDismounted.MountedDatabases = 3
            $script:mockDBDismounted.DismountedDatabases = 1
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockDBDismounted }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Critical overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Critical'
        }

        It -Name 'Should report 1 dismounted database' -Test {
            $script:result.DismountedDatabases | Should -Be 1
        }
    }

    Context 'Critical - Queue exceeds critical threshold' {

        BeforeAll {
            $script:mockQueueCritical = $script:mockHealthyData.Clone()
            $script:mockQueueCritical.HighestQueueLength = 600
            $script:mockQueueCritical.TotalQueueMessages = 850
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockQueueCritical }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Critical overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Critical'
        }

        It -Name 'Should report highest queue length of 600' -Test {
            $script:result.HighestQueueLength | Should -Be 600
        }
    }

    Context 'Degraded - Queue exceeds warning threshold' {

        BeforeAll {
            $script:mockQueueWarn = $script:mockHealthyData.Clone()
            $script:mockQueueWarn.HighestQueueLength = 150
            $script:mockQueueWarn.TotalQueueMessages = 200
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockQueueWarn }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Degraded overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Degraded'
        }

        It -Name 'Should report highest queue length of 150' -Test {
            $script:result.HighestQueueLength | Should -Be 150
        }
    }

    Context 'Degraded - Unhealthy DAG copies' {

        BeforeAll {
            $script:mockDAGUnhealthy = $script:mockHealthyData.Clone()
            $script:mockDAGUnhealthy.DAGCopiesHealthy = 6
            $script:mockDAGUnhealthy.DAGCopiesUnhealthy = 2
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockDAGUnhealthy }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Degraded overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Degraded'
        }

        It -Name 'Should report 2 unhealthy DAG copies' -Test {
            $script:result.DAGCopiesUnhealthy | Should -Be 2
        }
    }

    Context 'Degraded - Certificates expiring soon' {

        BeforeAll {
            $script:mockCertExpiring = $script:mockHealthyData.Clone()
            $script:mockCertExpiring.CertificatesExpiringSoon = 1
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockCertExpiring }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Degraded overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Degraded'
        }

        It -Name 'Should report 1 certificate expiring soon' -Test {
            $script:result.CertificatesExpiringSoon | Should -Be 1
        }
    }

    Context 'Degraded - Expired certificates' {

        BeforeAll {
            $script:mockCertExpired = $script:mockHealthyData.Clone()
            $script:mockCertExpired.CertificatesExpired = 1
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockCertExpired }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Degraded overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Degraded'
        }

        It -Name 'Should report 1 expired certificate' -Test {
            $script:result.CertificatesExpired | Should -Be 1
        }
    }

    Context 'Degraded - ADTopology service stopped' {

        BeforeAll {
            $script:mockADTopStopped = $script:mockHealthyData.Clone()
            $script:mockADTopStopped.ADTopologyStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockADTopStopped }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should return Degraded overall health' -Test {
            $script:result.OverallHealth | Should -Be 'Degraded'
        }

        It -Name 'Should report Stopped ADTopology status' -Test {
            $script:result.ADTopologyStatus | Should -Be 'Stopped'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockHealthyData }
            $script:result = Get-ExchangeServerHealth -ComputerName 'EX01'
        }

        It -Name 'Should set ComputerName to EX01' -Test {
            $script:result.ComputerName | Should -Be 'EX01'
        }

        It -Name 'Should return a result with Timestamp' -Test {
            $script:result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockHealthyData }
            $script:results = @('EX01', 'EX02') | Get-ExchangeServerHealth
        }

        It -Name 'Should return results for each pipeline input' -Test {
            @($script:results).Count | Should -Be 2
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

        It -Name 'Should write error for unreachable host' -Test {
            { Get-ExchangeServerHealth -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should return null when errors are silenced' -Test {
            $failResult = Get-ExchangeServerHealth -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-ExchangeServerHealth -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-ExchangeServerHealth -ComputerName $null } | Should -Throw
        }

        It -Name 'Should throw when QueueWarningThreshold is 0' -Test {
            { Get-ExchangeServerHealth -ComputerName 'EX01' -QueueWarningThreshold 0 } | Should -Throw
        }

        It -Name 'Should throw when CertificateWarningDays exceeds 365' -Test {
            { Get-ExchangeServerHealth -ComputerName 'EX01' -CertificateWarningDays 999 } | Should -Throw
        }
    }

    Context 'Custom thresholds' {

        BeforeAll {
            $script:mockCustomQueue = $script:mockHealthyData.Clone()
            $script:mockCustomQueue.HighestQueueLength = 60
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockCustomQueue }
        }

        It -Name 'Should report Degraded with custom warning threshold of 50' -Test {
            $result = Get-ExchangeServerHealth -ComputerName 'EX01' -QueueWarningThreshold 50
            $result.OverallHealth | Should -Be 'Degraded'
        }

        It -Name 'Should report Healthy with default threshold of 100' -Test {
            $result = Get-ExchangeServerHealth -ComputerName 'EX01'
            $result.OverallHealth | Should -Be 'Healthy'
        }
    }
}
