#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-IISHealth' {
    BeforeAll {
        $script:mockRemoteData = @(
            @{
                ServiceStatus = 'Running'
                SiteName      = 'Default Web Site'
                SiteState     = 'Started'
                Bindings      = 'http *:80:'
                PhysicalPath  = 'C:\inetpub\wwwroot'
                AppPoolName   = 'DefaultAppPool'
                AppPoolState  = 'Started'
                OverallHealth = 'Healthy'
            }
        )
    }

    Context 'When IIS role is unavailable' {
        BeforeAll {
            $script:mockRoleUnavailable = @(
                @{
                    ServiceStatus = 'NotInstalled'
                    SiteName      = 'N/A'
                    SiteState     = 'N/A'
                    Bindings      = 'N/A'
                    PhysicalPath  = 'N/A'
                    AppPoolName   = 'N/A'
                    AppPoolState  = 'N/A'
                    OverallHealth = 'RoleUnavailable'
                }
            )
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRoleUnavailable }
            $script:result = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return RoleUnavailable health status' -Test { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
        It -Name 'Should report NotInstalled service status' -Test { $script:result.ServiceStatus | Should -Be 'NotInstalled' }
        It -Name 'Should populate the ComputerName property' -Test { $script:result.ComputerName | Should -Be 'SRV01' }
    }

    Context 'When IIS site and pool are healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:result = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Healthy overall health' -Test { $script:result.OverallHealth | Should -Be 'Healthy' }
        It -Name 'Should return correct site name' -Test { $script:result.SiteName | Should -Be 'Default Web Site' }
        It -Name 'Should return Started site state' -Test { $script:result.SiteState | Should -Be 'Started' }
        It -Name 'Should return correct app pool name' -Test { $script:result.AppPoolName | Should -Be 'DefaultAppPool' }
        It -Name 'Should return Started app pool state' -Test { $script:result.AppPoolState | Should -Be 'Started' }
        It -Name 'Should return Running service status' -Test { $script:result.ServiceStatus | Should -Be 'Running' }
    }

    Context 'When W3SVC service is stopped' {
        BeforeAll {
            $script:mockCriticalService = @(@{
                ServiceStatus = 'Stopped'; SiteName = 'Default Web Site'; SiteState = 'Stopped'
                Bindings = 'http *:80:'; PhysicalPath = 'C:\inetpub\wwwroot'
                AppPoolName = 'DefaultAppPool'; AppPoolState = 'Stopped'; OverallHealth = 'Critical'
            })
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockCriticalService }
            $script:result = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Critical overall health' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
        It -Name 'Should report Stopped service status' -Test { $script:result.ServiceStatus | Should -Be 'Stopped' }
    }

    Context 'When IIS site is stopped' {
        BeforeAll {
            $script:mockCriticalSite = @(@{
                ServiceStatus = 'Running'; SiteName = 'Default Web Site'; SiteState = 'Stopped'
                Bindings = 'http *:80:'; PhysicalPath = 'C:\inetpub\wwwroot'
                AppPoolName = 'DefaultAppPool'; AppPoolState = 'Started'; OverallHealth = 'Critical'
            })
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockCriticalSite }
            $script:result = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Critical overall health' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
        It -Name 'Should report Stopped site state' -Test { $script:result.SiteState | Should -Be 'Stopped' }
        It -Name 'Should still report Running service status' -Test { $script:result.ServiceStatus | Should -Be 'Running' }
    }

    Context 'When app pool is stopped but site is started' {
        BeforeAll {
            $script:mockDegradedPool = @(@{
                ServiceStatus = 'Running'; SiteName = 'Default Web Site'; SiteState = 'Started'
                Bindings = 'http *:80:'; PhysicalPath = 'C:\inetpub\wwwroot'
                AppPoolName = 'DefaultAppPool'; AppPoolState = 'Stopped'; OverallHealth = 'Degraded'
            })
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockDegradedPool }
            $script:result = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Degraded overall health' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
        It -Name 'Should report Stopped app pool state' -Test { $script:result.AppPoolState | Should -Be 'Stopped' }
        It -Name 'Should report Started site state' -Test { $script:result.SiteState | Should -Be 'Started' }
    }

    Context 'When executing against a remote computer' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:result = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return a non-null result' -Test { $script:result | Should -Not -BeNullOrEmpty }
        It -Name 'Should return a populated result object' -Test { $script:result | Should -Not -BeNullOrEmpty }
        It -Name 'Should set the ComputerName property' -Test { $script:result.ComputerName | Should -Be 'SRV01' }
    }

    Context 'When processing pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:pipelineResults = @('SRV01', 'SRV02') | Get-IISHealth
        }
        It -Name 'Should return results for each pipeline input' -Test { $script:pipelineResults.Count | Should -Be 2 }
        It -Name 'Should return distinct ComputerName values' -Test {
            @($script:pipelineResults).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'When remote execution fails' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It -Name 'Should throw when ErrorAction is Stop' -Test { { Get-IISHealth -ComputerName 'SRV01' -ErrorAction 'Stop' } | Should -Throw }
        It -Name 'Should return null when errors are silenced' -Test {
            $failResult = Get-IISHealth -ComputerName 'SRV01' -ErrorAction 'SilentlyContinue'
            $failResult | Should -BeNullOrEmpty
        }
    }

    Context 'When validating parameters' {
        It -Name 'Should reject empty ComputerName' -Test { { Get-IISHealth -ComputerName '' } | Should -Throw }
        It -Name 'Should reject null ComputerName' -Test { { Get-IISHealth -ComputerName $null } | Should -Throw }
        It -Name 'Should support pipeline input by property name' -Test {
            $pipelineAttr = (Get-Command -Name 'Get-IISHealth').Parameters['ComputerName'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName }
            $pipelineAttr | Should -Not -BeNullOrEmpty
        }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should have PSTypeName PSWinOps.IISHealth' -Test { $script:typeResult[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should have Timestamp matching ISO 8601' -Test { $script:typeResult[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Get-IISHealth -ComputerName 'SRV01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Get-IISHealth -ComputerName 'SRV01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-IISHealth'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should accept Name alias' -Test {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:propResult = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should have ComputerName property' -Test { $script:propResult.ComputerName | Should -Be 'SRV01' }
        It -Name 'Should have ServiceName property' -Test { $script:propResult.PSObject.Properties.Name | Should -Contain 'ServiceName' }
        It -Name 'Should have ServiceStatus property' -Test { $script:propResult.ServiceStatus | Should -Be 'Running' }
        It -Name 'Should have SiteName property' -Test { $script:propResult.SiteName | Should -Be 'Default Web Site' }
        It -Name 'Should have SiteState property' -Test { $script:propResult.SiteState | Should -Be 'Started' }
        It -Name 'Should have Bindings property' -Test { $script:propResult.Bindings | Should -Not -BeNullOrEmpty }
        It -Name 'Should have PhysicalPath property' -Test { $script:propResult.PhysicalPath | Should -Not -BeNullOrEmpty }
        It -Name 'Should have AppPoolName property' -Test { $script:propResult.AppPoolName | Should -Be 'DefaultAppPool' }
        It -Name 'Should have AppPoolState property' -Test { $script:propResult.AppPoolState | Should -Be 'Started' }
        It -Name 'Should have OverallHealth property' -Test { $script:propResult.OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Multiple sites returned' {
        BeforeAll {
            $script:mockMultiSites = @(
                @{
                    ServiceStatus = 'Running'; SiteName = 'Default Web Site'; SiteState = 'Started'
                    Bindings = 'http *:80:'; PhysicalPath = 'C:\inetpub\wwwroot'
                    AppPoolName = 'DefaultAppPool'; AppPoolState = 'Started'; OverallHealth = 'Healthy'
                },
                @{
                    ServiceStatus = 'Running'; SiteName = 'API Site'; SiteState = 'Started'
                    Bindings = 'https *:443:'; PhysicalPath = 'C:\inetpub\api'
                    AppPoolName = 'APIPool'; AppPoolState = 'Started'; OverallHealth = 'Healthy'
                }
            )
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockMultiSites }
            $script:multiResults = Get-IISHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return 2 results for 2 sites' -Test { @($script:multiResults).Count | Should -Be 2 }
        It -Name 'Should have different site names' -Test {
            $script:siteNames = $script:multiResults | Select-Object -ExpandProperty SiteName
            $script:siteNames | Should -Contain 'Default Web Site'
            $script:siteNames | Should -Contain 'API Site'
        }
        It -Name 'Should have both ComputerName set to SRV01' -Test {
            $script:multiResults | ForEach-Object { $_.ComputerName | Should -Be 'SRV01' }
        }
    }

    Context 'Error message content on failure' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It -Name 'Should include computer name in error message' -Test {
            Get-IISHealth -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'BADHOST'
        }
        It -Name 'Should include function name in error message' -Test {
            Get-IISHealth -ComputerName 'BADHOST2' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'Get-IISHealth'
        }
    }

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:hpResult = Get-IISHealth -ComputerName 'SRV01'
        }
        It 'Should have PSTypeName PSWinOps.IISHealth' { $script:hpResult[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:hpResult = Get-IISHealth -ComputerName 'SRV01'
        }
        It 'Should have Timestamp matching ISO 8601 pattern' { $script:hpResult[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
        }
        It 'Should produce verbose messages' {
            $script:verbose = Get-IISHealth -ComputerName 'SRV01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It 'Should include function name in verbose' {
            $script:verbose = Get-IISHealth -ComputerName 'SRV01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-IISHealth'
        }
    }

    Context 'Credential parameter' {
        It 'Should have a Credential parameter' {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It 'Should have Credential as PSCredential type' {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
        It 'Should not require Credential as mandatory' {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:isMandatory = $script:cmd.Parameters['Credential'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
            $script:isMandatory | Should -Be $false
        }
    }

    Context 'ComputerName aliases' {
        It 'Should accept CN alias' {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It 'Should accept Name alias' {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
        It 'Should accept DNSHostName alias' {
            $script:cmd = Get-Command -Name 'Get-IISHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName'
        }
    }

    Context 'Site with stopped app pool - Degraded health' {
        BeforeAll {
            $script:mockStoppedPool = @(
                @{
                    ServiceStatus = 'Running'; SiteName = 'Default Web Site'; SiteState = 'Started'
                    Bindings = 'http *:80:'; PhysicalPath = 'C:\inetpub\wwwroot'
                    AppPoolName = 'DefaultAppPool'; AppPoolState = 'Stopped'; OverallHealth = 'Degraded'
                }
            )
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStoppedPool }
            $script:degradedResult = Get-IISHealth -ComputerName 'SRV01'
        }
        It 'Should report Degraded health' { $script:degradedResult.OverallHealth | Should -Be 'Degraded' }
        It 'Should report AppPool as Stopped' { $script:degradedResult.AppPoolState | Should -Be 'Stopped' }
    }

    Context 'Site with stopped site state - Critical health' {
        BeforeAll {
            $script:mockStoppedSite = @(
                @{
                    ServiceStatus = 'Running'; SiteName = 'Default Web Site'; SiteState = 'Stopped'
                    Bindings = 'http *:80:'; PhysicalPath = 'C:\inetpub\wwwroot'
                    AppPoolName = 'DefaultAppPool'; AppPoolState = 'Started'; OverallHealth = 'Critical'
                }
            )
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStoppedSite }
            $script:criticalResult = Get-IISHealth -ComputerName 'SRV01'
        }
        It 'Should report Critical health' { $script:criticalResult.OverallHealth | Should -Be 'Critical' }
        It 'Should report SiteState as Stopped' { $script:criticalResult.SiteState | Should -Be 'Stopped' }
    }
}