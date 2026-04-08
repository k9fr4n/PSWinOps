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

    # Create stubs for ADFS cmdlets if the ADFS module is not installed
    & (Get-Module -Name 'PSWinOps') {
        foreach ($cmdName in @('Get-AdfsProperties', 'Get-AdfsSslCertificate', 'Get-AdfsRelyingPartyTrust', 'Get-AdfsEndpoint', 'Test-AdfsServerHealth')) {
            if (-not (Get-Command -Name $cmdName -ErrorAction SilentlyContinue)) {
                Set-Item -Path "function:script:$cmdName" -Value ([scriptblock]::Create(''))
            }
        }
    }
}

Describe 'Get-ADFSHealth' {

    # =========================================================================
    #  Shared data & helpers
    # =========================================================================
    BeforeAll {
        # Hashtable matching the scriptBlock return shape (used by remote tests)
        $script:mockRemoteData = @{
            ServiceStatus         = 'Running'
            ModuleAvailable       = $true
            FederationServiceName = 'fs.contoso.com'
            SslCertExpiry         = '2028-01-01 00:00:00'
            SslCertDaysRemaining  = 700
            TotalRelyingParties   = 15
            EnabledRelyingParties = 12
            EnabledEndpoints      = 8
            ServerHealthOK        = $true
            FarmRole              = 'Primary'
            PrimaryServer         = 'Unknown'
        }

        # Helper: set up all local-path mocks for the scriptBlock
        function Set-ADFSLocalMocks {
            param(
                [string]$ServiceStatus       = 'Running',
                [bool]$ServiceThrows         = $false,
                [bool]$ModuleAvailable       = $true,
                [string]$HostName            = 'fs.contoso.com',
                [bool]$PropertiesThrows      = $false,
                [string]$CertHash            = 'AABBCCDD1122334455',
                [bool]$SslCertThrows         = $false,
                [bool]$SslCertEmpty          = $false,
                [int]$CertDaysFromNow        = 700,
                [bool]$CertNotFound          = $false,
                [int]$TotalRP                = 15,
                [int]$EnabledRP              = 12,
                [bool]$RPThrows              = $false,
                [int]$EnabledEndpoints       = 8,
                [bool]$EndpointThrows        = $false,
                [bool]$HealthCmdExists       = $true,
                [bool]$HealthTestThrows      = $false,
                [bool]$HealthTestFailing     = $false,
                [bool]$IsSecondaryNode       = $false
            )

            # Get-Service
            if ($ServiceThrows) {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'Service not found' }
            }
            else {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                    [PSCustomObject]@{ Status = $ServiceStatus; Name = 'adfssrv' }
                }.GetNewClosure()
            }

            # Get-Module (ADFS)
            if ($ModuleAvailable) {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'ADFS' } -MockWith {
                    [PSCustomObject]@{ Name = 'ADFS'; Version = '3.0.0.0' }
                }
            }
            else {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'ADFS' } -MockWith { return $null }
            }

            # Get-AdfsProperties
            if ($IsSecondaryNode) {
                Mock -CommandName 'Get-AdfsProperties' -ModuleName 'PSWinOps' -MockWith {
                    throw 'PS0033: This cmdlet cannot be executed from a secondary server in a local database farm.  The primary server is presently: adfs01.contoso.com.'
                }
            }
            elseif ($PropertiesThrows) {
                Mock -CommandName 'Get-AdfsProperties' -ModuleName 'PSWinOps' -MockWith { throw 'Cannot get ADFS properties' }
            }
            else {
                Mock -CommandName 'Get-AdfsProperties' -ModuleName 'PSWinOps' -MockWith {
                    [PSCustomObject]@{ HostName = $HostName }
                }.GetNewClosure()
            }

            # Get-AdfsSslCertificate
            if ($SslCertThrows) {
                Mock -CommandName 'Get-AdfsSslCertificate' -ModuleName 'PSWinOps' -MockWith { throw 'SSL cert error' }
            }
            elseif ($SslCertEmpty) {
                Mock -CommandName 'Get-AdfsSslCertificate' -ModuleName 'PSWinOps' -MockWith { return $null }
            }
            else {
                Mock -CommandName 'Get-AdfsSslCertificate' -ModuleName 'PSWinOps' -MockWith {
                    @([PSCustomObject]@{ CertificateHash = $CertHash })
                }.GetNewClosure()
            }

            # Get-Item (certificate store)
            if ($CertNotFound) {
                Mock -CommandName 'Get-Item' -ModuleName 'PSWinOps' -MockWith { return $null }
            }
            else {
                Mock -CommandName 'Get-Item' -ModuleName 'PSWinOps' -MockWith {
                    [PSCustomObject]@{ NotAfter = (Get-Date).AddDays($CertDaysFromNow) }
                }.GetNewClosure()
            }

            # Get-AdfsRelyingPartyTrust
            if ($RPThrows) {
                Mock -CommandName 'Get-AdfsRelyingPartyTrust' -ModuleName 'PSWinOps' -MockWith { throw 'RP trust error' }
            }
            else {
                $rpList = @()
                for ($i = 0; $i -lt $TotalRP; $i++) {
                    $rpList += [PSCustomObject]@{ Name = "RP$i"; Enabled = ($i -lt $EnabledRP) }
                }
                Mock -CommandName 'Get-AdfsRelyingPartyTrust' -ModuleName 'PSWinOps' -MockWith { return $rpList }.GetNewClosure()
            }

            # Get-AdfsEndpoint
            if ($EndpointThrows) {
                Mock -CommandName 'Get-AdfsEndpoint' -ModuleName 'PSWinOps' -MockWith { throw 'Endpoint error' }
            }
            else {
                $epList = @()
                for ($i = 0; $i -lt $EnabledEndpoints; $i++) {
                    $epList += [PSCustomObject]@{ Enabled = $true }
                }
                # Add 2 disabled endpoints for realism
                $epList += [PSCustomObject]@{ Enabled = $false }
                $epList += [PSCustomObject]@{ Enabled = $false }
                Mock -CommandName 'Get-AdfsEndpoint' -ModuleName 'PSWinOps' -MockWith { return $epList }.GetNewClosure()
            }

            # Get-Command for Test-AdfsServerHealth
            if ($HealthCmdExists) {
                Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'Test-AdfsServerHealth' } -MockWith {
                    [PSCustomObject]@{ Name = 'Test-AdfsServerHealth' }
                }
            }
            else {
                Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'Test-AdfsServerHealth' } -MockWith { return $null }
            }

            # Test-AdfsServerHealth
            if ($HealthTestThrows) {
                Mock -CommandName 'Test-AdfsServerHealth' -ModuleName 'PSWinOps' -MockWith { throw 'Health test failure' }
            }
            elseif ($HealthTestFailing) {
                Mock -CommandName 'Test-AdfsServerHealth' -ModuleName 'PSWinOps' -MockWith {
                    @(
                        [PSCustomObject]@{ Name = 'CheckOne'; Result = 'Pass' },
                        [PSCustomObject]@{ Name = 'CheckTwo'; Result = 'Fail' }
                    )
                }
            }
            else {
                Mock -CommandName 'Test-AdfsServerHealth' -ModuleName 'PSWinOps' -MockWith {
                    @(
                        [PSCustomObject]@{ Name = 'CheckOne'; Result = 'Pass' },
                        [PSCustomObject]@{ Name = 'CheckTwo'; Result = 'Pass' }
                    )
                }
            }

            # Block Invoke-Command for local path verification
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
            # Block Write-Warning for capture
            Mock -CommandName 'Write-Warning' -ModuleName 'PSWinOps'
        }
    }

    # =========================================================================
    #  REMOTE PATH — via Invoke-Command
    # =========================================================================
    Context 'Remote - Healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return correct federation name' { $script:result.FederationServiceName | Should -Be 'fs.contoso.com' }
        It 'Should return correct cert days' { $script:result.SslCertDaysRemaining | Should -Be 700 }
        It 'Should report health OK' { $script:result.ServerHealthOK | Should -BeTrue }
        It 'Should set ServiceName to adfssrv' { $script:result.ServiceName | Should -Be 'adfssrv' }
    }

    Context 'Remote - RoleUnavailable' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ModuleAvailable = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Remote - Critical (service stopped)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Remote - Critical (cert expired)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SslCertDaysRemaining = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Remote - Critical (health test failed)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServerHealthOK = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Remote - Degraded (cert expiring soon)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SslCertDaysRemaining = 20
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Remote - Degraded (zero enabled relying parties on primary)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.EnabledRelyingParties = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should report FarmRole as Primary' { $script:result.FarmRole | Should -Be 'Primary' }
    }

    Context 'Remote - Secondary node (WID farm) is Healthy despite zero RPs' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone()
            $d.FarmRole = 'Secondary'
            $d.PrimaryServer = 'adfs01.contoso.com'
            $d.FederationServiceName = 'Unknown'
            $d.EnabledRelyingParties = 0
            $d.TotalRelyingParties = 0
            $d.EnabledEndpoints = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS02'
        }
        It 'Should return Healthy (not Degraded)' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should report FarmRole as Secondary' { $script:result.FarmRole | Should -Be 'Secondary' }
        It 'Should report PrimaryServer' { $script:result.PrimaryServer | Should -Be 'adfs01.contoso.com' }
        It 'Should report FederationServiceName as Unknown' { $script:result.FederationServiceName | Should -Be 'Unknown' }
    }

    Context 'Remote - Pipeline input (two servers)' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:results = 'ADFS01', 'ADFS02' | Get-ADFSHealth
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
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01' -Credential $script:cred
        }
        It 'Should return a result' { $script:result | Should -Not -BeNullOrEmpty }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Remote - Failure handling (non-terminating)' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should not throw' { { Get-ADFSHealth -ComputerName 'ADFS01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
    }

    # =========================================================================
    #  LOCAL PATH — & $scriptBlock
    # =========================================================================
    Context 'Local path - Healthy (all checks pass)' {
        BeforeAll {
            Set-ADFSLocalMocks
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should NOT call Invoke-Command for local computer' {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return Running service status' { $script:result.ServiceStatus | Should -Be 'Running' }
        It 'Should return correct federation name' { $script:result.FederationServiceName | Should -Be 'fs.contoso.com' }
        It 'Should return positive SslCertDaysRemaining' { $script:result.SslCertDaysRemaining | Should -BeGreaterThan 0 }
        It 'Should return correct TotalRelyingParties' { $script:result.TotalRelyingParties | Should -Be 15 }
        It 'Should return correct EnabledRelyingParties' { $script:result.EnabledRelyingParties | Should -Be 12 }
        It 'Should return correct EnabledEndpoints' { $script:result.EnabledEndpoints | Should -Be 8 }
        It 'Should return ServerHealthOK as true' { $script:result.ServerHealthOK | Should -BeTrue }
    }

    Context 'Local path - Service not found (Get-Service throws)' {
        BeforeAll {
            Set-ADFSLocalMocks -ServiceThrows $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return NotFound for ServiceStatus' { $script:result.ServiceStatus | Should -Be 'NotFound' }
        It 'Should return Critical (service not running)' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should NOT call Get-AdfsProperties when service not found' {
            # Module available but service != Running → skip ADFS API
            Should -Invoke -CommandName 'Get-AdfsProperties' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Local path - Module not available' {
        BeforeAll {
            Set-ADFSLocalMocks -ModuleAvailable $false
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
        It 'Should NOT call any ADFS cmdlet' {
            Should -Invoke -CommandName 'Get-AdfsProperties' -ModuleName 'PSWinOps' -Times 0 -Exactly
            Should -Invoke -CommandName 'Get-AdfsSslCertificate' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Local path - Service stopped but module available' {
        BeforeAll {
            Set-ADFSLocalMocks -ServiceStatus 'Stopped'
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Stopped for ServiceStatus' { $script:result.ServiceStatus | Should -Be 'Stopped' }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should NOT call Get-AdfsProperties when service is stopped' {
            Should -Invoke -CommandName 'Get-AdfsProperties' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Local path - Get-AdfsProperties fails (Write-Warning)' {
        BeforeAll {
            Set-ADFSLocalMocks -PropertiesThrows $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Unknown for FederationServiceName' { $script:result.FederationServiceName | Should -Be 'Unknown' }
        It 'Should still return a result' { $script:result | Should -Not -BeNullOrEmpty }
    }

    Context 'Local path - Get-AdfsSslCertificate fails (Write-Warning)' {
        BeforeAll {
            Set-ADFSLocalMocks -SslCertThrows $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return default SslCertDaysRemaining of -1' { $script:result.SslCertDaysRemaining | Should -Be -1 }
        It 'Should return Critical (cert days <= 0)' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Local path - SSL certificate returns empty' {
        BeforeAll {
            Set-ADFSLocalMocks -SslCertEmpty $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return default SslCertDaysRemaining of -1' { $script:result.SslCertDaysRemaining | Should -Be -1 }
        It 'Should return Critical (cert days <= 0)' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Local path - Certificate not found in store' {
        BeforeAll {
            Set-ADFSLocalMocks -CertNotFound $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return default SslCertDaysRemaining of -1' { $script:result.SslCertDaysRemaining | Should -Be -1 }
        It 'Should return Unknown for SslCertExpiry' { $script:result.SslCertExpiry | Should -Be 'Unknown' }
    }

    Context 'Local path - Get-AdfsRelyingPartyTrust fails (Write-Warning)' {
        BeforeAll {
            Set-ADFSLocalMocks -RPThrows $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return 0 for TotalRelyingParties' { $script:result.TotalRelyingParties | Should -Be 0 }
        It 'Should return 0 for EnabledRelyingParties' { $script:result.EnabledRelyingParties | Should -Be 0 }
    }

    Context 'Local path - Get-AdfsEndpoint fails (Write-Warning)' {
        BeforeAll {
            Set-ADFSLocalMocks -EndpointThrows $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return 0 for EnabledEndpoints' { $script:result.EnabledEndpoints | Should -Be 0 }
    }

    Context 'Local path - Test-AdfsServerHealth not available (Get-Command returns null)' {
        BeforeAll {
            Set-ADFSLocalMocks -HealthCmdExists $false
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should NOT call Test-AdfsServerHealth' {
            Should -Invoke -CommandName 'Test-AdfsServerHealth' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
        It 'Should default ServerHealthOK to true' { $script:result.ServerHealthOK | Should -BeTrue }
        It 'Should return Healthy (no health test failure)' { $script:result.OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Local path - Test-AdfsServerHealth throws' {
        BeforeAll {
            Set-ADFSLocalMocks -HealthTestThrows $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should set ServerHealthOK to false' { $script:result.ServerHealthOK | Should -BeFalse }
        It 'Should return Critical (health check failed)' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Local path - Test-AdfsServerHealth has failures' {
        BeforeAll {
            Set-ADFSLocalMocks -HealthTestFailing $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should set ServerHealthOK to false' { $script:result.ServerHealthOK | Should -BeFalse }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Local path - localhost alias triggers local execution' {
        BeforeAll {
            Set-ADFSLocalMocks
            $script:result = Get-ADFSHealth -ComputerName 'localhost'
        }
        It 'Should NOT call Invoke-Command for localhost' {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
        It 'Should return LOCALHOST as ComputerName (uppercased)' { $script:result.ComputerName | Should -Be 'LOCALHOST' }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Local path - dot alias triggers local execution' {
        BeforeAll {
            Set-ADFSLocalMocks
            $script:result = Get-ADFSHealth -ComputerName '.'
        }
        It 'Should NOT call Invoke-Command for dot' {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
        It 'Should return a valid result' { $script:result | Should -Not -BeNullOrEmpty }
    }

    Context 'Local path - Critical (cert expired, negative days)' {
        BeforeAll {
            Set-ADFSLocalMocks -CertDaysFromNow -10
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return negative SslCertDaysRemaining' { $script:result.SslCertDaysRemaining | Should -BeLessThan 0 }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Local path - Degraded (cert expiring within 30 days)' {
        BeforeAll {
            Set-ADFSLocalMocks -CertDaysFromNow 20
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should return cert days less than 30' { $script:result.SslCertDaysRemaining | Should -BeLessThan 30 }
    }

    Context 'Local path - Degraded (zero enabled relying parties on primary)' {
        BeforeAll {
            Set-ADFSLocalMocks -TotalRP 5 -EnabledRP 0
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should return 0 EnabledRelyingParties' { $script:result.EnabledRelyingParties | Should -Be 0 }
        It 'Should return 5 TotalRelyingParties' { $script:result.TotalRelyingParties | Should -Be 5 }
    }

    Context 'Local path - Secondary WID node is Healthy despite zero RPs' {
        BeforeAll {
            Set-ADFSLocalMocks -IsSecondaryNode $true -RPThrows $true -EndpointThrows $true
            $script:result = Get-ADFSHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Healthy (not Degraded)' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should report FarmRole as Secondary' { $script:result.FarmRole | Should -Be 'Secondary' }
        It 'Should report PrimaryServer' { $script:result.PrimaryServer | Should -Be 'adfs01.contoso.com' }
        It 'Should return 0 EnabledRelyingParties' { $script:result.EnabledRelyingParties | Should -Be 0 }
    }

    # =========================================================================
    #  BOUNDARY TESTS
    # =========================================================================
    Context 'Boundary - SslCertDaysRemaining exactly 0 is Critical' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SslCertDaysRemaining = 0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Critical (0 <= 0)' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Boundary - SslCertDaysRemaining exactly 1 is Degraded' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SslCertDaysRemaining = 1
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Degraded (1 < 30)' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Boundary - SslCertDaysRemaining exactly 29 is Degraded' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SslCertDaysRemaining = 29
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Degraded (29 < 30)' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Boundary - SslCertDaysRemaining exactly 30 is Healthy' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.SslCertDaysRemaining = 30
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Healthy (30 is NOT < 30)' { $script:result.OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Boundary - Critical takes precedence over Degraded' {
        BeforeAll {
            # Both: ServerHealthOK=false (Critical) AND cert < 30 (Degraded)
            $d = $script:mockRemoteData.Clone()
            $d.ServerHealthOK = $false
            $d.SslCertDaysRemaining = 20
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should return Critical (not Degraded)' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    # =========================================================================
    #  COMMON VALIDATIONS
    # =========================================================================
    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should have PSTypeName PSWinOps.ADFSHealth' { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADFSHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should have Timestamp matching ISO 8601' { $script:typeResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
        }
        It 'Should produce verbose messages' {
            $script:verbose = Get-ADFSHealth -ComputerName 'ADFS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It 'Should include function name in verbose' {
            $script:verbose = Get-ADFSHealth -ComputerName 'ADFS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-ADFSHealth'
        }
    }

    Context 'Credential parameter' {
        It 'Should have a Credential parameter' {
            $cmd = Get-Command -Name 'Get-ADFSHealth' -Module 'PSWinOps'
            $cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It 'Should have Credential as PSCredential type' {
            $cmd = Get-Command -Name 'Get-ADFSHealth' -Module 'PSWinOps'
            $cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It 'Should accept CN alias' {
            $cmd = Get-Command -Name 'Get-ADFSHealth' -Module 'PSWinOps'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It 'Should accept Name alias' {
            $cmd = Get-Command -Name 'Get-ADFSHealth' -Module 'PSWinOps'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
        It 'Should accept DNSHostName alias' {
            $cmd = Get-Command -Name 'Get-ADFSHealth' -Module 'PSWinOps'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName'
        }
    }

    Context 'Output property completeness (remote)' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:hpResult = Get-ADFSHealth -ComputerName 'ADFS01'
        }
        It 'Should have ComputerName set to ADFS01' { $script:hpResult.ComputerName | Should -Be 'ADFS01' }
        It 'Should have ServiceName property' { $script:hpResult.ServiceName | Should -Be 'adfssrv' }
        It 'Should have ServiceStatus property' { $script:hpResult.ServiceStatus | Should -Be 'Running' }
        It 'Should have FarmRole property' { $script:hpResult.FarmRole | Should -Be 'Primary' }
        It 'Should have PrimaryServer property' { $script:hpResult.PSObject.Properties.Name | Should -Contain 'PrimaryServer' }
        It 'Should have FederationServiceName property' { $script:hpResult.FederationServiceName | Should -Be 'fs.contoso.com' }
        It 'Should have SslCertExpiry property' { $script:hpResult.SslCertExpiry | Should -Be '2028-01-01 00:00:00' }
        It 'Should have SslCertDaysRemaining property' { $script:hpResult.SslCertDaysRemaining | Should -Be 700 }
        It 'Should have TotalRelyingParties property' { $script:hpResult.TotalRelyingParties | Should -Be 15 }
        It 'Should have EnabledRelyingParties property' { $script:hpResult.EnabledRelyingParties | Should -Be 12 }
        It 'Should have EnabledEndpoints property' { $script:hpResult.EnabledEndpoints | Should -Be 8 }
        It 'Should have ServerHealthOK property' { $script:hpResult.ServerHealthOK | Should -Be $true }
        It 'Should have OverallHealth property' { $script:hpResult.OverallHealth | Should -Not -BeNullOrEmpty }
        It 'Should have Timestamp property' { $script:hpResult.Timestamp | Should -Not -BeNullOrEmpty }
    }

    Context 'Parameter validation' {
        It 'Should reject empty ComputerName' { { Get-ADFSHealth -ComputerName '' } | Should -Throw }
        It 'Should reject null ComputerName' { { Get-ADFSHealth -ComputerName $null } | Should -Throw }
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
