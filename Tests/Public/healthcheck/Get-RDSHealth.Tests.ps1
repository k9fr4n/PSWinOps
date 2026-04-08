#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        foreach ($cmdName in @('Get-RDServer', 'Get-RDUserSession', 'Get-RDLicenseConfiguration')) {
            if (-not (Get-Command -Name $cmdName -ErrorAction SilentlyContinue)) {
                Set-Item -Path "function:script:$cmdName" -Value ([scriptblock]::Create(''))
            }
        }
    }
}

Describe 'Get-RDSHealth' {

    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus = 'Running'; SessionEnvStatus = 'Running'; RDModuleAvailable = $true
            InstalledRoles = 'RDS-SESSION-HOST, RDS-LICENSING'; ActiveSessions = 5
            DisconnectedSessions = 2; LicensingMode = 'PerUser'
        }

        function Set-RDSLocalMocks {
            param(
                [string]$TermServiceStatus  = 'Running',
                [bool]$TermServiceNull      = $false,
                [string]$SessionEnvStatus   = 'Running',
                [bool]$SessionEnvNull       = $false,
                [bool]$ModuleAvailable      = $true,
                [array]$RDServers           = @(),
                [bool]$RDServerThrows       = $false,
                [array]$RDSessions          = @(),
                [bool]$RDSessionThrows      = $false,
                [string]$LicensingMode      = 'PerUser',
                [bool]$LicenseConfigThrows  = $false
            )

            # TermService (uses -ErrorAction SilentlyContinue → null if not found)
            if ($TermServiceNull) {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'TermService' } -MockWith { return $null }
            }
            else {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'TermService' } -MockWith {
                    [PSCustomObject]@{ Status = $TermServiceStatus; Name = 'TermService' }
                }.GetNewClosure()
            }

            # SessionEnv
            if ($SessionEnvNull) {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'SessionEnv' } -MockWith { return $null }
            }
            else {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'SessionEnv' } -MockWith {
                    [PSCustomObject]@{ Status = $SessionEnvStatus; Name = 'SessionEnv' }
                }.GetNewClosure()
            }

            # Get-Module RemoteDesktop
            if ($ModuleAvailable) {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'RemoteDesktop' } -MockWith {
                    [PSCustomObject]@{ Name = 'RemoteDesktop'; Version = '2.0.0.0' }
                }
            }
            else {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'RemoteDesktop' } -MockWith { return $null }
            }

            # Get-RDServer
            if ($RDServerThrows) {
                Mock -CommandName 'Get-RDServer' -ModuleName 'PSWinOps' -MockWith { throw 'RD Management Server unavailable' }
            }
            else {
                Mock -CommandName 'Get-RDServer' -ModuleName 'PSWinOps' -MockWith { return $RDServers }.GetNewClosure()
            }

            # Get-RDUserSession
            if ($RDSessionThrows) {
                Mock -CommandName 'Get-RDUserSession' -ModuleName 'PSWinOps' -MockWith { throw 'Session query failed' }
            }
            else {
                Mock -CommandName 'Get-RDUserSession' -ModuleName 'PSWinOps' -MockWith { return $RDSessions }.GetNewClosure()
            }

            # Get-RDLicenseConfiguration
            if ($LicenseConfigThrows) {
                Mock -CommandName 'Get-RDLicenseConfiguration' -ModuleName 'PSWinOps' -MockWith { throw 'License config error' }
            }
            else {
                Mock -CommandName 'Get-RDLicenseConfiguration' -ModuleName 'PSWinOps' -MockWith {
                    [PSCustomObject]@{ Mode = $LicensingMode }
                }.GetNewClosure()
            }

            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
        }
    }

    # =================================================================
    #  REMOTE PATH
    # =================================================================
    Context 'Remote - Healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return Running service' { $script:result.ServiceStatus | Should -Be 'Running' }
        It 'Should return Running SessionEnv' { $script:result.SessionEnvStatus | Should -Be 'Running' }
        It 'Should compute TotalSessions' { $script:result.TotalSessions | Should -Be 7 }
        It 'Should return correct roles' { $script:result.InstalledRoles | Should -Be 'RDS-SESSION-HOST, RDS-LICENSING' }
    }

    Context 'Remote - RoleUnavailable' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'NotFound'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Remote - Critical (service stopped)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Remote - Critical (SessionEnv stopped)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SessionEnvStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Remote - Degraded (more disconnected than active)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ActiveSessions = 2; $d.DisconnectedSessions = 10
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should compute TotalSessions' { $script:result.TotalSessions | Should -Be 12 }
    }

    Context 'Remote - Degraded (licensing not configured)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.LicensingMode = 'NotConfigured'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-RDSHealth -ComputerName 'RDS01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Remote - Pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:results = 'RDS01', 'RDS02' | Get-RDSHealth
        }
        It 'Should return two results' { $script:results | Should -HaveCount 2 }
    }

    Context 'Remote - Failure handling' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should not throw' { { Get-RDSHealth -ComputerName 'RDS01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
    }

    # =================================================================
    #  LOCAL PATH
    # =================================================================
    Context 'Local - Healthy (both services running, balanced sessions, licensed)' {
        BeforeAll {
            $servers = @(
                [PSCustomObject]@{ Server = $env:COMPUTERNAME; Roles = @('RDS-RD-SERVER', 'RDS-LICENSING') }
            )
            $sessions = @(
                [PSCustomObject]@{ SessionState = 'STATE_ACTIVE' },
                [PSCustomObject]@{ SessionState = 'STATE_ACTIVE' },
                [PSCustomObject]@{ SessionState = 'STATE_DISCONNECTED' }
            )
            Set-RDSLocalMocks -RDServers $servers -RDSessions $sessions -LicensingMode 'PerUser'
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return Running ServiceStatus' { $script:result.ServiceStatus | Should -Be 'Running' }
        It 'Should return Running SessionEnvStatus' { $script:result.SessionEnvStatus | Should -Be 'Running' }
        It 'Should count 2 active sessions' { $script:result.ActiveSessions | Should -Be 2 }
        It 'Should count 1 disconnected session' { $script:result.DisconnectedSessions | Should -Be 1 }
        It 'Should compute TotalSessions = 3' { $script:result.TotalSessions | Should -Be 3 }
        It 'Should report PerUser licensing' { $script:result.LicensingMode | Should -Be 'PerUser' }
    }

    Context 'Local - TermService not found (RoleUnavailable)' {
        BeforeAll {
            Set-RDSLocalMocks -TermServiceNull $true
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
        It 'Should return NotFound ServiceStatus' { $script:result.ServiceStatus | Should -Be 'NotFound' }
    }

    Context 'Local - TermService stopped (Critical)' {
        BeforeAll {
            Set-RDSLocalMocks -TermServiceStatus 'Stopped'
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should return Stopped ServiceStatus' { $script:result.ServiceStatus | Should -Be 'Stopped' }
    }

    Context 'Local - SessionEnv stopped (Critical)' {
        BeforeAll {
            $servers = @([PSCustomObject]@{ Server = $env:COMPUTERNAME; Roles = @('RDS-RD-SERVER') })
            Set-RDSLocalMocks -SessionEnvStatus 'Stopped' -RDServers $servers
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should return Stopped SessionEnvStatus' { $script:result.SessionEnvStatus | Should -Be 'Stopped' }
        It 'Should return Running ServiceStatus' { $script:result.ServiceStatus | Should -Be 'Running' }
    }

    Context 'Local - Module not available (skips RD cmdlets)' {
        BeforeAll {
            Set-RDSLocalMocks -ModuleAvailable $false
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should NOT call Get-RDServer' { Should -Invoke -CommandName 'Get-RDServer' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should NOT call Get-RDUserSession' { Should -Invoke -CommandName 'Get-RDUserSession' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return RDModuleAvailable = false' { $script:result.RDModuleAvailable | Should -BeFalse }
    }

    Context 'Local - Get-RDServer throws (catches gracefully)' {
        BeforeAll {
            Set-RDSLocalMocks -RDServerThrows $true
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return a result' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should NOT call Get-RDLicenseConfiguration' { Should -Invoke -CommandName 'Get-RDLicenseConfiguration' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Local - Get-RDUserSession throws (catches gracefully)' {
        BeforeAll {
            $servers = @([PSCustomObject]@{ Server = $env:COMPUTERNAME; Roles = @('RDS-RD-SERVER') })
            Set-RDSLocalMocks -RDServers $servers -RDSessionThrows $true
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return ActiveSessions as integer' { $script:result.ActiveSessions | Should -BeOfType [int] }
        It 'Should return DisconnectedSessions as integer' { $script:result.DisconnectedSessions | Should -BeOfType [int] }
    }

    Context 'Local - RDS-LICENSING present calls Get-RDLicenseConfiguration' {
        BeforeAll {
            $servers = @([PSCustomObject]@{ Server = $env:COMPUTERNAME; Roles = @('RDS-RD-SERVER', 'RDS-LICENSING') })
            $sessions = @([PSCustomObject]@{ SessionState = 'STATE_ACTIVE' })
            Set-RDSLocalMocks -RDServers $servers -RDSessions $sessions -LicensingMode 'PerDevice'
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return PerDevice licensing' { $script:result.LicensingMode | Should -Be 'PerDevice' }
    }

    Context 'Local - RDS-LICENSING absent skips Get-RDLicenseConfiguration' {
        BeforeAll {
            $servers = @([PSCustomObject]@{ Server = $env:COMPUTERNAME; Roles = @('RDS-RD-SERVER') })
            $sessions = @([PSCustomObject]@{ SessionState = 'STATE_ACTIVE' })
            Set-RDSLocalMocks -RDServers $servers -RDSessions $sessions
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should NOT call Get-RDLicenseConfiguration' { Should -Invoke -CommandName 'Get-RDLicenseConfiguration' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Local - Get-RDLicenseConfiguration throws (Unknown licensing)' {
        BeforeAll {
            $servers = @([PSCustomObject]@{ Server = $env:COMPUTERNAME; Roles = @('RDS-RD-SERVER', 'RDS-LICENSING') })
            $sessions = @([PSCustomObject]@{ SessionState = 'STATE_ACTIVE' })
            Set-RDSLocalMocks -RDServers $servers -RDSessions $sessions -LicenseConfigThrows $true
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Unknown licensing' { $script:result.LicensingMode | Should -Be 'Unknown' }
    }

    Context 'Local - Disconnected > Active (Degraded)' {
        BeforeAll {
            $servers = @([PSCustomObject]@{ Server = $env:COMPUTERNAME; Roles = @('RDS-RD-SERVER') })
            $sessions = @(
                [PSCustomObject]@{ SessionState = 'STATE_ACTIVE' },
                [PSCustomObject]@{ SessionState = 'STATE_DISCONNECTED' },
                [PSCustomObject]@{ SessionState = 'STATE_DISCONNECTED' },
                [PSCustomObject]@{ SessionState = 'STATE_DISCONNECTED' }
            )
            Set-RDSLocalMocks -RDServers $servers -RDSessions $sessions
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should count 1 active' { $script:result.ActiveSessions | Should -Be 1 }
        It 'Should count 3 disconnected' { $script:result.DisconnectedSessions | Should -Be 3 }
    }

    Context 'Local - LicensingMode NotConfigured (Degraded)' {
        BeforeAll {
            $servers = @([PSCustomObject]@{ Server = $env:COMPUTERNAME; Roles = @('RDS-RD-SERVER', 'RDS-LICENSING') })
            $sessions = @([PSCustomObject]@{ SessionState = 'STATE_ACTIVE' }, [PSCustomObject]@{ SessionState = 'STATE_ACTIVE' })
            Set-RDSLocalMocks -RDServers $servers -RDSessions $sessions -LicensingMode 'NotConfigured'
            $script:result = Get-RDSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should return NotConfigured licensing' { $script:result.LicensingMode | Should -Be 'NotConfigured' }
    }

    Context 'Local - localhost alias' {
        BeforeAll {
            Set-RDSLocalMocks
            $script:result = Get-RDSHealth -ComputerName 'localhost'
        }
        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return LOCALHOST as ComputerName' { $script:result.ComputerName | Should -Be 'LOCALHOST' }
    }

    Context 'Local - dot alias' {
        BeforeAll {
            Set-RDSLocalMocks
            $script:result = Get-RDSHealth -ComputerName '.'
        }
        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return a result' { $script:result | Should -Not -BeNullOrEmpty }
    }

    # =================================================================
    #  COMMON VALIDATIONS
    # =================================================================
    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-RDSHealth -ComputerName 'RDS01'
        }
        It 'Should have PSTypeName PSWinOps.RDSHealth' { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.RDSHealth' }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:propResult = Get-RDSHealth -ComputerName 'RDS01'
        }
        It 'Should have ComputerName' { $script:propResult.ComputerName | Should -Be 'RDS01' }
        It 'Should have ServiceName' { $script:propResult.ServiceName | Should -Be 'TermService' }
        It 'Should have ActiveSessions' { $script:propResult.ActiveSessions | Should -Be 5 }
        It 'Should have DisconnectedSessions' { $script:propResult.DisconnectedSessions | Should -Be 2 }
        It 'Should have TotalSessions' { $script:propResult.TotalSessions | Should -Be 7 }
        It 'Should have InstalledRoles' { $script:propResult.InstalledRoles | Should -Not -BeNullOrEmpty }
        It 'Should have LicensingMode' { $script:propResult.LicensingMode | Should -Be 'PerUser' }
        It 'Should have RDModuleAvailable' { $script:propResult.RDModuleAvailable | Should -BeTrue }
        It 'Should have SessionEnvStatus' { $script:propResult.SessionEnvStatus | Should -Be 'Running' }
        It 'Should have Timestamp' { $script:propResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' }
    }

    Context 'Parameter validation' {
        It 'Should reject empty ComputerName' { { Get-RDSHealth -ComputerName '' } | Should -Throw }
        It 'Should reject null ComputerName' { { Get-RDSHealth -ComputerName $null } | Should -Throw }
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
