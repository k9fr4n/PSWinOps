#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Create stub for Get-WsusServer if UpdateServices module is not installed
    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-WsusServer' -ErrorAction SilentlyContinue)) {
            function script:Get-WsusServer { }
        }
    }
}

Describe 'Get-WSUSHealth' {

    # =========================================================================
    #  Shared mock data factory
    # =========================================================================
    BeforeAll {
        # Hashtable matching the scriptBlock return shape
        $script:mockRemoteData = @{
            ServiceStatus         = 'Running'
            ModuleAvailable       = $true
            WSUSServerName        = 'WSUS01'
            WSUSPort              = 8530
            IsSSL                 = $false
            DatabaseType          = 'WID'
            TotalClients          = 100
            ClientsNeedingUpdates = 10
            ClientsWithErrors     = 0
            UnapprovedUpdates     = 50
            ContentDirPath        = 'D:\WSUS'
            ContentDirFreeSpaceGB = 45.5
        }

        # Helper: build a mock WSUS server object with ScriptMethods
        function New-MockWsusServer {
            param(
                [string]$ServerName          = 'WSUS01',
                [int]$PortNumber             = 8530,
                [bool]$UseSecureConnection   = $false,
                [int]$ComputerTargetCount    = 100,
                [int]$NeedingUpdates         = 10,
                [int]$WithErrors             = 0,
                [int]$UnapprovedUpdates      = 50,
                [bool]$IsWID                 = $true
            )
            $obj = [PSCustomObject]@{
                ServerName          = $ServerName
                PortNumber          = $PortNumber
                UseSecureConnection = $UseSecureConnection
            }
            $obj | Add-Member -MemberType ScriptMethod -Name 'GetStatus' -Value ([scriptblock]::Create(@"
                [PSCustomObject]@{
                    ComputerTargetCount                  = $ComputerTargetCount
                    ComputerTargetsNeedingUpdatesCount   = $NeedingUpdates
                    ComputerTargetsWithUpdateErrorsCount = $WithErrors
                    NotApprovedUpdateCount               = $UnapprovedUpdates
                }
"@))
            $widLiteral = if ($IsWID) { '$true' } else { '$false' }
            $obj | Add-Member -MemberType ScriptMethod -Name 'GetDatabaseConfiguration' -Value ([scriptblock]::Create(
                "[PSCustomObject]@{ IsUsingWindowsInternalDatabase = $widLiteral }"
            ))
            return $obj
        }

        # Helper: set up all local-path mocks for the scriptBlock
        function Set-LocalPathMocks {
            param(
                [string]$ServiceStatus        = 'Running',
                [bool]$ServiceThrows          = $false,
                [bool]$ModuleAvailable        = $true,
                [object]$WsusServer           = $null,
                [bool]$WsusServerThrows       = $false,
                [string]$ContentDir           = 'D:\WSUS',
                [long]$DiskFreeBytes          = 107374182400   # 100 GB
            )

            if ($ServiceThrows) {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'Service not found' }
            }
            else {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                    [PSCustomObject]@{ Status = $ServiceStatus; Name = 'WsusService' }
                }.GetNewClosure()
            }

            if ($ModuleAvailable) {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'UpdateServices' } -MockWith {
                    [PSCustomObject]@{ Name = 'UpdateServices'; Version = '2.0.0.0' }
                }
            }
            else {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'UpdateServices' } -MockWith { return $null }
            }

            if ($WsusServerThrows) {
                Mock -CommandName 'Get-WsusServer' -ModuleName 'PSWinOps' -MockWith { throw 'WSUS API failure' }
            }
            elseif ($null -ne $WsusServer) {
                Mock -CommandName 'Get-WsusServer' -ModuleName 'PSWinOps' -MockWith { return $WsusServer }.GetNewClosure()
            }
            else {
                Mock -CommandName 'Get-WsusServer' -ModuleName 'PSWinOps' -MockWith { return (New-MockWsusServer) }
            }

            Mock -CommandName 'Get-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ContentDir = $ContentDir }
            }.GetNewClosure()

            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ FreeSpace = $DiskFreeBytes }
            }.GetNewClosure()

            # Prevent local calls from going remote
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
        }
    }

    # =========================================================================
    #  REMOTE PATH — via Invoke-Command
    # =========================================================================
    Context 'Remote - Healthy (all checks pass)' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should return Healthy overall health' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return Running service status' { $script:result.ServiceStatus | Should -Be 'Running' }
        It 'Should return correct WSUS server name' { $script:result.WSUSServerName | Should -Be 'WSUS01' }
        It 'Should return correct total clients' { $script:result.TotalClients | Should -Be 100 }
        It 'Should return zero clients with errors' { $script:result.ClientsWithErrors | Should -Be 0 }
        It 'Should set ServiceName to WsusService' { $script:result.ServiceName | Should -Be 'WsusService' }
    }

    Context 'Remote - RoleUnavailable (module not available)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ModuleAvailable = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Remote - Critical (service not running)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Remote - Critical (clients with errors)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ClientsWithErrors = 5
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should return error count' { $script:result.ClientsWithErrors | Should -Be 5 }
    }

    Context 'Remote - Critical (disk below 5 GB)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ContentDirFreeSpaceGB = 3.2
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Remote - Degraded (more than 30 percent needing updates)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ClientsNeedingUpdates = 35
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Remote - Degraded (disk below 20 GB)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ContentDirFreeSpaceGB = 15.0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Remote - Degraded (more than 100 unapproved)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.UnapprovedUpdates = 150
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Remote - Pipeline input (two servers)' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:results = 'WSUS01', 'WSUS02' | Get-WSUSHealth
        }
        It 'Should return two results' { $script:results | Should -HaveCount 2 }
        It 'Should return distinct ComputerName values' {
            $names = @($script:results) | Select-Object -ExpandProperty ComputerName -Unique
            @($names).Count | Should -Be 2
        }
    }

    Context 'Remote - Credential forwarded to Invoke-Command' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $securePass = ConvertTo-SecureString -String 'P@ss1' -AsPlainText -Force
            $script:cred = [System.Management.Automation.PSCredential]::new('DOMAIN\admin', $securePass)
            $script:result = Get-WSUSHealth -ComputerName 'WSUS01' -Credential $script:cred
        }
        It 'Should return a result' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Remote - Failure handling (non-terminating)' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should not throw terminating error' { { Get-WSUSHealth -ComputerName 'WSUS01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
    }

    # =========================================================================
    #  LOCAL PATH — & $scriptBlock
    # =========================================================================
    Context 'Local path - Healthy (all checks pass)' {
        BeforeAll {
            $wsus = New-MockWsusServer -ComputerTargetCount 100 -NeedingUpdates 10 -WithErrors 0 -UnapprovedUpdates 50
            Set-LocalPathMocks -WsusServer $wsus -DiskFreeBytes 107374182400  # 100 GB
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should NOT call Invoke-Command for local computer' {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return Running service status' { $script:result.ServiceStatus | Should -Be 'Running' }
        It 'Should return correct WSUS server name' { $script:result.WSUSServerName | Should -Be 'WSUS01' }
        It 'Should return correct port' { $script:result.WSUSPort | Should -Be 8530 }
        It 'Should return IsSSL as false' { $script:result.IsSSL | Should -BeFalse }
        It 'Should return WID database type' { $script:result.DatabaseType | Should -Be 'WID' }
        It 'Should return correct TotalClients' { $script:result.TotalClients | Should -Be 100 }
        It 'Should return correct ClientsNeedingUpdates' { $script:result.ClientsNeedingUpdates | Should -Be 10 }
        It 'Should return zero ClientsWithErrors' { $script:result.ClientsWithErrors | Should -Be 0 }
        It 'Should return correct UnapprovedUpdates' { $script:result.UnapprovedUpdates | Should -Be 50 }
        It 'Should return correct ContentDirPath' { $script:result.ContentDirPath | Should -Be 'D:\WSUS' }
        It 'Should return disk free space in GB' { $script:result.ContentDirFreeSpaceGB | Should -BeGreaterThan 0 }
    }

    Context 'Local path - Service not found (Get-Service throws)' {
        BeforeAll {
            Set-LocalPathMocks -ServiceThrows $true
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return NotFound for ServiceStatus' { $script:result.ServiceStatus | Should -Be 'NotFound' }
        It 'Should NOT call Get-WsusServer when service is not found' {
            # moduleAvailable is true but serviceStatus != Running → skip WSUS API
            Should -Invoke -CommandName 'Get-WsusServer' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
        It 'Should return Critical (service not running)' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Local path - Module not available' {
        BeforeAll {
            Set-LocalPathMocks -ModuleAvailable $false
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
        It 'Should NOT call Get-WsusServer when module is absent' {
            Should -Invoke -CommandName 'Get-WsusServer' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Local path - Service stopped but module available' {
        BeforeAll {
            Set-LocalPathMocks -ServiceStatus 'Stopped'
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Stopped for ServiceStatus' { $script:result.ServiceStatus | Should -Be 'Stopped' }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should NOT call Get-WsusServer when service is stopped' {
            Should -Invoke -CommandName 'Get-WsusServer' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Local path - WSUS API failure (internal catch with Write-Warning)' {
        BeforeAll {
            Set-LocalPathMocks -WsusServerThrows $true
            Mock -CommandName 'Write-Warning' -ModuleName 'PSWinOps'
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should still return a result object' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should return default null for WSUSServerName' { $script:result.WSUSServerName | Should -BeNullOrEmpty }
        It 'Should return 0 for TotalClients' { $script:result.TotalClients | Should -Be 0 }
        It 'Should return 0 for ContentDirFreeSpaceGB' { $script:result.ContentDirFreeSpaceGB | Should -Be 0 }
    }

    Context 'Local path - localhost alias triggers local execution' {
        BeforeAll {
            Set-LocalPathMocks
            $script:result = Get-WSUSHealth -ComputerName 'localhost'
        }
        It 'Should NOT call Invoke-Command for localhost' {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
        It 'Should return a valid result' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should return LOCALHOST as ComputerName (uppercased)' { $script:result.ComputerName | Should -Be 'LOCALHOST' }
    }

    Context 'Local path - dot alias triggers local execution' {
        BeforeAll {
            Set-LocalPathMocks
            $script:result = Get-WSUSHealth -ComputerName '.'
        }
        It 'Should NOT call Invoke-Command for dot' {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
        It 'Should return a valid result' { $script:result | Should -Not -BeNullOrEmpty }
    }

    Context 'Local path - SQL database type' {
        BeforeAll {
            $wsus = New-MockWsusServer -IsWID $false
            Set-LocalPathMocks -WsusServer $wsus
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return SQL database type' { $script:result.DatabaseType | Should -Be 'SQL' }
    }

    Context 'Local path - SSL enabled' {
        BeforeAll {
            $wsus = New-MockWsusServer -PortNumber 8531 -UseSecureConnection $true
            Set-LocalPathMocks -WsusServer $wsus
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return IsSSL as true' { $script:result.IsSSL | Should -BeTrue }
        It 'Should return port 8531' { $script:result.WSUSPort | Should -Be 8531 }
    }

    Context 'Local path - Critical (clients with errors)' {
        BeforeAll {
            $wsus = New-MockWsusServer -WithErrors 3
            Set-LocalPathMocks -WsusServer $wsus
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should report 3 clients with errors' { $script:result.ClientsWithErrors | Should -Be 3 }
    }

    Context 'Local path - Critical (disk below 5 GB)' {
        BeforeAll {
            Set-LocalPathMocks -DiskFreeBytes 2147483648  # 2 GB
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Local path - Degraded (31 percent needing updates)' {
        BeforeAll {
            $wsus = New-MockWsusServer -ComputerTargetCount 100 -NeedingUpdates 31
            Set-LocalPathMocks -WsusServer $wsus
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Local path - Degraded (101 unapproved updates)' {
        BeforeAll {
            $wsus = New-MockWsusServer -UnapprovedUpdates 101
            Set-LocalPathMocks -WsusServer $wsus
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Local path - Degraded (disk below 20 GB but above 5 GB)' {
        BeforeAll {
            Set-LocalPathMocks -DiskFreeBytes 16106127360  # ~15 GB
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    # =========================================================================
    #  BOUNDARY TESTS
    # =========================================================================
    Context 'Boundary - Exactly 30 percent needing updates is NOT degraded' {
        BeforeAll {
            $wsus = New-MockWsusServer -ComputerTargetCount 100 -NeedingUpdates 30
            Set-LocalPathMocks -WsusServer $wsus
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Healthy (30% is NOT > 30%)' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should report 30 clients needing updates' { $script:result.ClientsNeedingUpdates | Should -Be 30 }
    }

    Context 'Boundary - Exactly 100 unapproved updates is NOT degraded' {
        BeforeAll {
            $wsus = New-MockWsusServer -UnapprovedUpdates 100
            Set-LocalPathMocks -WsusServer $wsus
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Healthy (100 is NOT > 100)' { $script:result.OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Boundary - Exactly 5 GB disk is NOT critical but IS degraded' {
        BeforeAll {
            Set-LocalPathMocks -DiskFreeBytes 5368709120  # 5 GB
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should NOT be Critical (5 is NOT < 5)' { $script:result.OverallHealth | Should -Not -Be 'Critical' }
        It 'Should be Degraded (5 < 20)' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Boundary - Critical takes precedence over Degraded' {
        BeforeAll {
            # Both: errors > 0 (Critical) AND unapproved > 100 (Degraded)
            $wsus = New-MockWsusServer -WithErrors 5 -UnapprovedUpdates 200 -NeedingUpdates 50
            Set-LocalPathMocks -WsusServer $wsus -DiskFreeBytes 3221225472  # 3 GB
            $script:result = Get-WSUSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical (not Degraded)' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should report clients with errors' { $script:result.ClientsWithErrors | Should -Be 5 }
    }

    # =========================================================================
    #  COMMON VALIDATIONS
    # =========================================================================
    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should have PSTypeName PSWinOps.WSUSHealth' { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.WSUSHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should have Timestamp matching ISO 8601' { $script:typeResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
        }
        It 'Should produce verbose messages' {
            $script:verbose = Get-WSUSHealth -ComputerName 'WSUS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It 'Should include function name in verbose' {
            $script:verbose = Get-WSUSHealth -ComputerName 'WSUS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-WSUSHealth'
        }
    }

    Context 'Credential parameter' {
        It 'Should have a Credential parameter' {
            $cmd = Get-Command -Name 'Get-WSUSHealth' -Module 'PSWinOps'
            $cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It 'Should have Credential as PSCredential type' {
            $cmd = Get-Command -Name 'Get-WSUSHealth' -Module 'PSWinOps'
            $cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It 'Should accept CN alias' {
            $cmd = Get-Command -Name 'Get-WSUSHealth' -Module 'PSWinOps'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It 'Should accept Name alias' {
            $cmd = Get-Command -Name 'Get-WSUSHealth' -Module 'PSWinOps'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
        It 'Should accept DNSHostName alias' {
            $cmd = Get-Command -Name 'Get-WSUSHealth' -Module 'PSWinOps'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName'
        }
    }

    Context 'Output property completeness (remote)' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:hpResult = Get-WSUSHealth -ComputerName 'WSUS01'
        }
        It 'Should have ComputerName set to WSUS01' { $script:hpResult.ComputerName | Should -Be 'WSUS01' }
        It 'Should have ServiceName property' { $script:hpResult.ServiceName | Should -Be 'WsusService' }
        It 'Should have WSUSServerName property' { $script:hpResult.WSUSServerName | Should -Be 'WSUS01' }
        It 'Should have WSUSPort property' { $script:hpResult.WSUSPort | Should -Be 8530 }
        It 'Should have IsSSL property' { $script:hpResult.IsSSL | Should -Be $false }
        It 'Should have DatabaseType property' { $script:hpResult.DatabaseType | Should -Be 'WID' }
        It 'Should have TotalClients property' { $script:hpResult.TotalClients | Should -Be 100 }
        It 'Should have ClientsNeedingUpdates property' { $script:hpResult.ClientsNeedingUpdates | Should -Be 10 }
        It 'Should have ClientsWithErrors property' { $script:hpResult.ClientsWithErrors | Should -Be 0 }
        It 'Should have UnapprovedUpdates property' { $script:hpResult.UnapprovedUpdates | Should -Be 50 }
        It 'Should have ContentDirPath property' { $script:hpResult.ContentDirPath | Should -Be 'D:\WSUS' }
        It 'Should have ContentDirFreeSpaceGB property' { $script:hpResult.ContentDirFreeSpaceGB | Should -Be 45.5 }
        It 'Should have OverallHealth property' { $script:hpResult.OverallHealth | Should -Not -BeNullOrEmpty }
        It 'Should have Timestamp property' { $script:hpResult.Timestamp | Should -Not -BeNullOrEmpty }
    }

    Context 'Parameter validation' {
        It 'Should reject empty ComputerName' { { Get-WSUSHealth -ComputerName '' } | Should -Throw }
        It 'Should reject null ComputerName' { { Get-WSUSHealth -ComputerName $null } | Should -Throw }
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
