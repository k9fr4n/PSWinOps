#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        foreach ($cmdName in @('Get-ADDomainController', 'Get-ADDomain')) {
            if (-not (Get-Command -Name $cmdName -ErrorAction SilentlyContinue)) {
                Set-Item -Path "function:script:$cmdName" -Value ([scriptblock]::Create(''))
            }
        }
    }
}

Describe 'Get-AdDomainControllerHealth' {

    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus         = 'Running'
            ADModuleAvailable     = $true
            RunAsAccount          = 'CONTOSO\Admin'
            IsLocalAdmin          = $true
            IsDomainAdmin         = $true
            HasRequiredPrivileges = $true
            DCName                = 'DC01.contoso.com'
            DomainName            = 'contoso.com'
            ForestName            = 'contoso.com'
            DomainMode            = 'Windows2016Domain'
            SiteName              = 'Default-First-Site-Name'
            IsGlobalCatalog       = $true
            IsReadOnly            = $false
            OperatingSystem       = 'Windows Server 2022'
            SysvolAccessible      = $true
            NetlogonAccessible    = $true
            ReplicationSuccesses  = 8
            ReplicationFailures   = 0
            DcDiagPassedTests     = 5
            DcDiagFailedTests     = 0
        }

        $script:mockNtdsService = [PSCustomObject]@{
            Name   = 'NTDS'
            Status = 'Running'
        }

        $script:mockAdModule = [PSCustomObject]@{
            Name    = 'ActiveDirectory'
            Version = [version]'1.0.0.0'
        }

        $script:mockDomainController = [PSCustomObject]@{
            HostName        = 'DC01.contoso.com'
            Domain          = 'contoso.com'
            Forest          = 'contoso.com'
            Site            = 'Default-First-Site-Name'
            IsGlobalCatalog = $true
            IsReadOnly      = $false
            OperatingSystem = 'Windows Server 2022'
        }

        $script:mockDomain = [PSCustomObject]@{
            DNSRoot    = 'contoso.com'
            Forest     = 'contoso.com'
            DomainMode = 'Windows2016Domain'
        }
    }

    Context 'RoleUnavailable - AD module not available' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockNtdsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:results = Get-AdDomainControllerHealth
        }

        It -Name 'Should return a result object' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should set OverallHealth to RoleUnavailable' -Test {
            $script:results.OverallHealth | Should -Be 'RoleUnavailable'
        }

        It -Name 'Should set ServiceName to NTDS' -Test {
            $script:results.ServiceName | Should -Be 'NTDS'
        }

        It -Name 'Should NOT call Invoke-Command for local execution' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Local - NTDS service not found' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $null }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:results = Get-AdDomainControllerHealth
        }

        It -Name 'Should return a result' -Test { $script:results | Should -Not -BeNullOrEmpty }
        It -Name 'Should set ServiceStatus to NotFound' -Test { $script:results.ServiceStatus | Should -Be 'NotFound' }
        It -Name 'Should set OverallHealth to RoleUnavailable' -Test { $script:results.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Local - AD module available, full data collection' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockNtdsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'ActiveDirectory' } -MockWith { return $script:mockAdModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith { return $script:mockDomainController }
            Mock -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -MockWith { return $script:mockDomain }
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith { return $null } -ParameterFilter { $Name -eq 'repadmin' -or $Name -eq 'dcdiag' }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            $script:results = Get-AdDomainControllerHealth
        }

        It -Name 'Should NOT call Invoke-Command' -Test { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It -Name 'Should call Import-Module ActiveDirectory' -Test { Should -Invoke -CommandName 'Import-Module' -ModuleName 'PSWinOps' -Times 1 }
        It -Name 'Should call Get-ADDomainController' -Test { Should -Invoke -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -Times 1 }
        It -Name 'Should call Get-ADDomain' -Test { Should -Invoke -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -Times 1 }
        It -Name 'Should set ServiceStatus to Running' -Test { $script:results.ServiceStatus | Should -Be 'Running' }
        It -Name 'Should set DomainName' -Test { $script:results.DomainName | Should -Be 'contoso.com' }
        It -Name 'Should set ForestName' -Test { $script:results.ForestName | Should -Be 'contoso.com' }
        It -Name 'Should set SysvolAccessible to true' -Test { $script:results.SysvolAccessible | Should -BeTrue }
        It -Name 'Should set NetlogonAccessible to true' -Test { $script:results.NetlogonAccessible | Should -BeTrue }
        It -Name 'Should set ReplicationSuccesses to -1 (repadmin unavailable)' -Test { $script:results.ReplicationSuccesses | Should -Be -1 }
        It -Name 'Should set DcDiagPassedTests to -1 (dcdiag unavailable)' -Test { $script:results.DcDiagPassedTests | Should -Be -1 }
        It -Name 'Should have RunAsAccount set' -Test { $script:results.RunAsAccount | Should -Not -BeNullOrEmpty }
    }

    Context 'Local - Get-ADDomainController throws (catches gracefully)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockNtdsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'ActiveDirectory' } -MockWith { return $script:mockAdModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith { throw 'DC not found' }
            Mock -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -MockWith { return $script:mockDomain }
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith { return $null } -ParameterFilter { $Name -eq 'repadmin' -or $Name -eq 'dcdiag' }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            $script:results = Get-AdDomainControllerHealth
        }

        It -Name 'Should return a result' -Test { $script:results | Should -Not -BeNullOrEmpty }
        It -Name 'Should still have DomainName from Get-ADDomain' -Test { $script:results.DomainName | Should -Be 'contoso.com' }
    }

    Context 'Local - Get-ADDomain throws (catches gracefully)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockNtdsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'ActiveDirectory' } -MockWith { return $script:mockAdModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith { return $script:mockDomainController }
            Mock -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -MockWith { throw 'Domain not reachable' }
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith { return $null } -ParameterFilter { $Name -eq 'repadmin' -or $Name -eq 'dcdiag' }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true }
            $script:results = Get-AdDomainControllerHealth
        }

        It -Name 'Should return a result' -Test { $script:results | Should -Not -BeNullOrEmpty }
        It -Name 'Should have null DomainName' -Test { $script:results.DomainName | Should -BeNullOrEmpty }
    }

    Context 'Local - SYSVOL not accessible' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockNtdsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'ActiveDirectory' } -MockWith { return $script:mockAdModule }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith { return $script:mockDomainController }
            Mock -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -MockWith { return $script:mockDomain }
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith { return $null } -ParameterFilter { $Name -eq 'repadmin' -or $Name -eq 'dcdiag' }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $false } -ParameterFilter { $Path -like '*SYSVOL*' }
            Mock -CommandName 'Test-Path' -ModuleName 'PSWinOps' -MockWith { return $true } -ParameterFilter { $Path -like '*NETLOGON*' }
            $script:results = Get-AdDomainControllerHealth
        }

        It -Name 'Should set SysvolAccessible to false' -Test { $script:results.SysvolAccessible | Should -BeFalse }
        It -Name 'Should set NetlogonAccessible to true' -Test { $script:results.NetlogonAccessible | Should -BeTrue }
    }

    Context 'Local - localhost alias' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockNtdsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'localhost'
        }

        It -Name 'Should NOT call Invoke-Command' -Test { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It -Name 'Should set ComputerName to LOCALHOST' -Test { $script:results.ComputerName | Should -Be 'LOCALHOST' }
    }

    Context 'Local - dot alias' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { return $script:mockNtdsService }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:results = Get-AdDomainControllerHealth -ComputerName '.'
        }

        It -Name 'Should NOT call Invoke-Command' -Test { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It -Name 'Should return a result' -Test { $script:results | Should -Not -BeNullOrEmpty }
    }

    Context 'Healthy - All checks pass via remote mock' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'DC01'
        }

        It -Name 'Should set ServiceStatus to Running' -Test {
            $script:results.ServiceStatus | Should -Be 'Running'
        }

        It -Name 'Should set HasRequiredPrivileges to true' -Test {
            $script:results.HasRequiredPrivileges | Should -BeTrue
        }

        It -Name 'Should set RunAsAccount' -Test {
            $script:results.RunAsAccount | Should -Be 'CONTOSO\Admin'
        }

        It -Name 'Should set DomainName to contoso.com' -Test {
            $script:results.DomainName | Should -Be 'contoso.com'
        }

        It -Name 'Should set SiteName' -Test {
            $script:results.SiteName | Should -Be 'Default-First-Site-Name'
        }

        It -Name 'Should set SysvolAccessible to true' -Test {
            $script:results.SysvolAccessible | Should -BeTrue
        }

        It -Name 'Should set NetlogonAccessible to true' -Test {
            $script:results.NetlogonAccessible | Should -BeTrue
        }

        It -Name 'Should set OverallHealth to Healthy' -Test {
            $script:results.OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should have a Timestamp value' -Test {
            $script:results.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'InsufficientPrivilege - not Domain Admin' {

        BeforeAll {
            $script:mockNoPriv = $script:mockRemoteData.Clone()
            $script:mockNoPriv.HasRequiredPrivileges = $false
            $script:mockNoPriv.IsDomainAdmin = $false
            $script:mockNoPriv.RunAsAccount = 'CONTOSO\RegularUser'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockNoPriv }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'DC01'
        }

        It -Name 'Should set HasRequiredPrivileges to false' -Test {
            $script:results.HasRequiredPrivileges | Should -BeFalse
        }

        It -Name 'Should set OverallHealth to InsufficientPrivilege' -Test {
            $script:results.OverallHealth | Should -Be 'InsufficientPrivilege'
        }

        It -Name 'Should set RunAsAccount to the unprivileged user' -Test {
            $script:results.RunAsAccount | Should -Be 'CONTOSO\RegularUser'
        }
    }

    Context 'InsufficientPrivilege - not local admin' {

        BeforeAll {
            $script:mockNoLocalAdmin = $script:mockRemoteData.Clone()
            $script:mockNoLocalAdmin.HasRequiredPrivileges = $false
            $script:mockNoLocalAdmin.IsLocalAdmin = $false
            $script:mockNoLocalAdmin.RunAsAccount = 'CONTOSO\DomainAdmin'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockNoLocalAdmin }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'DC01'
        }

        It -Name 'Should set HasRequiredPrivileges to false' -Test {
            $script:results.HasRequiredPrivileges | Should -BeFalse
        }

        It -Name 'Should set OverallHealth to InsufficientPrivilege' -Test {
            $script:results.OverallHealth | Should -Be 'InsufficientPrivilege'
        }
    }

    Context 'Critical - Replication failures detected' {

        BeforeAll {
            $script:mockReplFailure = $script:mockRemoteData.Clone()
            $script:mockReplFailure.ReplicationFailures = 5
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockReplFailure }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'DC01'
        }

        It -Name 'Should set ReplicationFailures to 5' -Test {
            $script:results.ReplicationFailures | Should -Be 5
        }

        It -Name 'Should set OverallHealth to Critical' -Test {
            $script:results.OverallHealth | Should -Be 'Critical'
        }
    }

    Context 'Critical - DcDiag failures detected' {

        BeforeAll {
            $script:mockDcDiagFail = $script:mockRemoteData.Clone()
            $script:mockDcDiagFail.DcDiagFailedTests = 3
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockDcDiagFail }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'DC01'
        }

        It -Name 'Should set DcDiagFailedTests to 3' -Test {
            $script:results.DcDiagFailedTests | Should -Be 3
        }

        It -Name 'Should set OverallHealth to Critical' -Test {
            $script:results.OverallHealth | Should -Be 'Critical'
        }
    }

    Context 'Critical - NTDS service stopped' {

        BeforeAll {
            $script:mockStopped = $script:mockRemoteData.Clone()
            $script:mockStopped.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStopped }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'DC01'
        }

        It -Name 'Should set ServiceStatus to Stopped' -Test {
            $script:results.ServiceStatus | Should -Be 'Stopped'
        }

        It -Name 'Should set OverallHealth to Critical' -Test {
            $script:results.OverallHealth | Should -Be 'Critical'
        }
    }

    Context 'Degraded - SYSVOL not accessible' {

        BeforeAll {
            $script:mockSysvolDown = $script:mockRemoteData.Clone()
            $script:mockSysvolDown.SysvolAccessible = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockSysvolDown }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'DC01'
        }

        It -Name 'Should set SysvolAccessible to false' -Test {
            $script:results.SysvolAccessible | Should -BeFalse
        }

        It -Name 'Should set OverallHealth to Degraded' -Test {
            $script:results.OverallHealth | Should -Be 'Degraded'
        }
    }

    Context 'Degraded - NETLOGON not accessible' {

        BeforeAll {
            $script:mockNetlogonDown = $script:mockRemoteData.Clone()
            $script:mockNetlogonDown.NetlogonAccessible = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockNetlogonDown }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'DC01'
        }

        It -Name 'Should set NetlogonAccessible to false' -Test {
            $script:results.NetlogonAccessible | Should -BeFalse
        }

        It -Name 'Should set OverallHealth to Degraded' -Test {
            $script:results.OverallHealth | Should -Be 'Degraded'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = Get-AdDomainControllerHealth -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should set OverallHealth to Healthy' -Test {
            $script:results.OverallHealth | Should -Be 'Healthy'
        }

        It -Name 'Should return a non-null result' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have Timestamp property' -Test {
            $script:results.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:results = @('SRV01', 'SRV02') | Get-AdDomainControllerHealth
        }

        It -Name 'Should return 2 results for 2 piped machines' -Test {
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should have distinct ComputerName values' -Test {
            $script:computerNames = $script:results | Select-Object -ExpandProperty ComputerName
            $script:computerNames | Should -Contain 'SRV01'
            $script:computerNames | Should -Contain 'SRV02'
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write error for unreachable host' -Test {
            { Get-AdDomainControllerHealth -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-AdDomainControllerHealth -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-AdDomainControllerHealth -ComputerName $null } | Should -Throw
        }
    }
}