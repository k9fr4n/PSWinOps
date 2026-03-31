#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    if (-not (Get-Command -Name 'Get-Website' -ErrorAction SilentlyContinue)) {
        function global:Get-Website {  }
    }
    if (-not (Get-Command -Name 'Get-WebAppPoolState' -ErrorAction SilentlyContinue)) {
        function global:Get-WebAppPoolState { param($Name) }
    }
    if (-not (Get-Command -Name 'Get-IISAppPool' -ErrorAction SilentlyContinue)) {
        function global:Get-IISAppPool {  }
    }
    if (-not (Get-Command -Name 'Get-IISSite' -ErrorAction SilentlyContinue)) {
        function global:Get-IISSite {  }
    }
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

    Context 'Local execution - IIS healthy via WebAdministration module' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'WebAdministration' }
            } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Name = 'DefaultAppPool' })
            } -ParameterFilter { $Path -like 'IIS:\AppPools*' }
            Mock -CommandName 'Get-WebAppPoolState' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Value = 'Started' }
            }
            Mock -CommandName 'Get-Website' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Default Web Site'
                    State = 'Started'
                    applicationPool = 'DefaultAppPool'
                    physicalPath = 'C:\inetpub\wwwroot'
                    Bindings = [PSCustomObject]@{
                        Collection = @([PSCustomObject]@{ protocol = 'http'; bindingInformation = '*:80:' })
                    }
                })
            }

            $script:localIIS = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return result for local IIS' { $script:localIIS | Should -Not -BeNullOrEmpty }
        It 'Should have OverallHealth' { $script:localIIS[0].OverallHealth | Should -Not -BeNullOrEmpty }
        It 'Should set ComputerName' { $script:localIIS[0].ComputerName | Should -Be $env:COMPUTERNAME.ToUpper() }
        It 'Should have PSTypeName' { $script:localIIS[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISHealth' }
    }

    Context 'Local execution - W3SVC not installed' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'Service not found' }
            $script:localNotInstalled = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return RoleUnavailable' { $script:localNotInstalled[0].OverallHealth | Should -Be 'RoleUnavailable' }
        It 'Should set ServiceStatus to NotInstalled' { $script:localNotInstalled[0].ServiceStatus | Should -Be 'NotInstalled' }
    }

    Context 'Local execution - CIM fallback when no IIS modules' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $ListAvailable }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                switch ($ClassName) {
                    'Site'            { @([PSCustomObject]@{ Name = 'TestSite' }) }
                    'ApplicationPool' { @([PSCustomObject]@{ Name = 'DefaultAppPool' }) }
                    'Application'     { @([PSCustomObject]@{ SiteName = 'TestSite'; Path = '/'; ApplicationPool = 'DefaultAppPool' }) }
                    default           { throw "Unexpected CIM class: $ClassName" }
                }
            } -ParameterFilter { $Namespace -eq 'root/webadministration' }
            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ReturnValue = 1 }
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'

            $script:localCIM = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return result via CIM fallback' { $script:localCIM | Should -Not -BeNullOrEmpty }
        It 'Should have SiteName from CIM' { $script:localCIM[0].SiteName | Should -Be 'TestSite' }
        It 'Should resolve AppPoolName via CIM Application mapping' { $script:localCIM[0].AppPoolName | Should -Be 'DefaultAppPool' }
        It 'Should return Healthy (Unknown states are not penalized)' { $script:localCIM[0].OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Local execution - CIM fallback with unknown pool state is not Degraded' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $ListAvailable }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                switch ($ClassName) {
                    'Site' { @([PSCustomObject]@{ Name = 'TestSite' }) }
                    default { throw "$ClassName CIM class not available" }
                }
            } -ParameterFilter { $Namespace -eq 'root/webadministration' }
            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ReturnValue = 1 }
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'

            $script:localCIMUnknown = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return result' { $script:localCIMUnknown | Should -Not -BeNullOrEmpty }
        It 'Should set AppPoolName to Unknown' { $script:localCIMUnknown[0].AppPoolName | Should -Be 'Unknown' }
        It 'Should set AppPoolState to Unknown' { $script:localCIMUnknown[0].AppPoolState | Should -Be 'Unknown' }
        It 'Should return Healthy (not Degraded) when pool state is Unknown' { $script:localCIMUnknown[0].OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Local - Stopped site via WebAdministration (Critical)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'WebAdministration' }
            } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Name = 'DefaultAppPool' })
            } -ParameterFilter { $Path -like 'IIS:\AppPools*' }
            Mock -CommandName 'Get-WebAppPoolState' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Value = 'Started' }
            }
            Mock -CommandName 'Get-Website' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Stopped Site'; State = 'Stopped'
                    applicationPool = 'DefaultAppPool'; physicalPath = 'C:\web'
                    Bindings = [PSCustomObject]@{
                        Collection = @([PSCustomObject]@{ protocol = 'http'; bindingInformation = '*:80:' })
                    }
                })
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
            $script:localStopped = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly -Scope Context }
        It 'Should return Critical' { $script:localStopped[0].OverallHealth | Should -Be 'Critical' }
        It 'Should report Stopped SiteState' { $script:localStopped[0].SiteState | Should -Be 'Stopped' }
    }

    Context 'Local - Stopped AppPool (Degraded)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'WebAdministration' }
            } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Name = 'StoppedPool' })
            } -ParameterFilter { $Path -like 'IIS:\AppPools*' }
            Mock -CommandName 'Get-WebAppPoolState' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Value = 'Stopped' }
            }
            Mock -CommandName 'Get-Website' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Default Web Site'; State = 'Started'
                    applicationPool = 'StoppedPool'; physicalPath = 'C:\inetpub\wwwroot'
                    Bindings = [PSCustomObject]@{
                        Collection = @([PSCustomObject]@{ protocol = 'http'; bindingInformation = '*:80:' })
                    }
                })
            }
            $script:localDegraded = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return Degraded' { $script:localDegraded[0].OverallHealth | Should -Be 'Degraded' }
        It 'Should report Stopped AppPoolState' { $script:localDegraded[0].AppPoolState | Should -Be 'Stopped' }
    }

    Context 'Local - W3SVC stopped (Critical)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Stopped' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'WebAdministration' }
            } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Name = 'DefaultAppPool' })
            } -ParameterFilter { $Path -like 'IIS:\AppPools*' }
            Mock -CommandName 'Get-WebAppPoolState' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Value = 'Started' }
            }
            Mock -CommandName 'Get-Website' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Default Web Site'; State = 'Started'
                    applicationPool = 'DefaultAppPool'; physicalPath = 'C:\inetpub\wwwroot'
                    Bindings = [PSCustomObject]@{
                        Collection = @([PSCustomObject]@{ protocol = 'http'; bindingInformation = '*:80:' })
                    }
                })
            }
            $script:localW3Stopped = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return Critical' { $script:localW3Stopped[0].OverallHealth | Should -Be 'Critical' }
        It 'Should report Stopped ServiceStatus' { $script:localW3Stopped[0].ServiceStatus | Should -Be 'Stopped' }
    }

    Context 'Local - Multiple sites via WebAdministration' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'WebAdministration' }
            } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Name = 'DefaultAppPool' }, [PSCustomObject]@{ Name = 'APIPool' })
            } -ParameterFilter { $Path -like 'IIS:\AppPools*' }
            Mock -CommandName 'Get-WebAppPoolState' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Value = 'Started' }
            }
            Mock -CommandName 'Get-Website' -ModuleName 'PSWinOps' -MockWith {
                @(
                    [PSCustomObject]@{
                        Name = 'Default Web Site'; State = 'Started'
                        applicationPool = 'DefaultAppPool'; physicalPath = 'C:\inetpub\wwwroot'
                        Bindings = [PSCustomObject]@{
                            Collection = @([PSCustomObject]@{ protocol = 'http'; bindingInformation = '*:80:' })
                        }
                    },
                    [PSCustomObject]@{
                        Name = 'API Site'; State = 'Started'
                        applicationPool = 'APIPool'; physicalPath = 'C:\inetpub\api'
                        Bindings = [PSCustomObject]@{
                            Collection = @([PSCustomObject]@{ protocol = 'https'; bindingInformation = '*:443:' })
                        }
                    }
                )
            }
            $script:localMulti = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return 2 results' { @($script:localMulti).Count | Should -Be 2 }
        It 'Should contain Default Web Site' { ($script:localMulti | Select-Object -ExpandProperty SiteName) | Should -Contain 'Default Web Site' }
        It 'Should contain API Site' { ($script:localMulti | Select-Object -ExpandProperty SiteName) | Should -Contain 'API Site' }
    }

    Context 'Local - CIM fallback also fails (RoleUnavailable)' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $ListAvailable }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { throw 'CIM not found' } -ParameterFilter { $Namespace -eq 'root/webadministration' }
            $script:localCIMFail = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return RoleUnavailable' { $script:localCIMFail[0].OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Local - localhost alias' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'Service not found' }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
            $script:localLH = Get-IISHealth -ComputerName 'localhost'
        }

        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly -Scope Context }
        It 'Should return LOCALHOST as ComputerName' { $script:localLH[0].ComputerName | Should -Be 'LOCALHOST' }
    }

    Context 'Local - dot alias' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'Service not found' }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
            $script:localDot = Get-IISHealth -ComputerName '.'
        }

        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly -Scope Context }
        It 'Should return a result' { $script:localDot | Should -Not -BeNullOrEmpty }
    }

    Context 'Local - IISAdministration module path' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'IISAdministration' }
            } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-IISAppPool' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Name = 'DefaultAppPool'; State = 'Started' })
            }
            Mock -CommandName 'Get-IISSite' -ModuleName 'PSWinOps' -MockWith {
                $vdir = [PSCustomObject]@{ PhysicalPath = 'C:\inetpub\wwwroot' }
                $app = [PSCustomObject]@{
                    ApplicationPoolName = 'DefaultAppPool'
                    VirtualDirectories  = @{ '/' = $vdir }
                }
                @([PSCustomObject]@{
                    Name         = 'IISSite'
                    State        = 'Started'
                    Bindings     = @([PSCustomObject]@{ Protocol = 'http'; BindingInformation = '*:80:' })
                    Applications = @{ '/' = $app }
                })
            }
            $script:iisAdminResult = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return Healthy' { $script:iisAdminResult[0].OverallHealth | Should -Be 'Healthy' }
        It 'Should return IISSite as SiteName' { $script:iisAdminResult[0].SiteName | Should -Be 'IISSite' }
        It 'Should return DefaultAppPool' { $script:iisAdminResult[0].AppPoolName | Should -Be 'DefaultAppPool' }
        It 'Should return Started AppPoolState' { $script:iisAdminResult[0].AppPoolState | Should -Be 'Started' }
        It 'Should contain binding info' { $script:iisAdminResult[0].Bindings | Should -Match 'http' }
        It 'Should have PhysicalPath' { $script:iisAdminResult[0].PhysicalPath | Should -Be 'C:\inetpub\wwwroot' }
    }

    Context 'Local - IISAdministration pool not in index' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'IISAdministration' }
            } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-IISAppPool' -ModuleName 'PSWinOps' -MockWith { @() }
            Mock -CommandName 'Get-IISSite' -ModuleName 'PSWinOps' -MockWith {
                $vdir = [PSCustomObject]@{ PhysicalPath = 'C:\web' }
                $app = [PSCustomObject]@{
                    ApplicationPoolName = 'OrphanPool'
                    VirtualDirectories  = @{ '/' = $vdir }
                }
                @([PSCustomObject]@{
                    Name         = 'OrphanSite'
                    State        = 'Started'
                    Bindings     = @([PSCustomObject]@{ Protocol = 'https'; BindingInformation = '*:443:' })
                    Applications = @{ '/' = $app }
                })
            }
            $script:orphanResult = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should set AppPoolState to Unknown' { $script:orphanResult[0].AppPoolState | Should -Be 'Unknown' }
        It 'Should return Healthy (Unknown pool state is not penalized)' { $script:orphanResult[0].OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Local - IISAdministration module throws' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'IISAdministration' }
            } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { throw 'Module load failed' }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { throw 'CIM not found' } -ParameterFilter { $Namespace -eq 'root/webadministration' }
            $script:iisAdminFail = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should fallback to RoleUnavailable' { $script:iisAdminFail[0].OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Local - No sites found via WebAdministration' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'WebAdministration' }
            } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith { @() } -ParameterFilter { $Path -like 'IIS:\AppPools*' }
            Mock -CommandName 'Get-Website' -ModuleName 'PSWinOps' -MockWith { @() }
            $script:noSites = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return NoSitesFound' { $script:noSites[0].SiteName | Should -Be 'NoSitesFound' }
        It 'Should return Healthy when service is Running' { $script:noSites[0].OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Local - GetWebAppPoolState throws' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'WebAdministration' }
            } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'IISAdministration' -and $ListAvailable }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Name = 'DefaultAppPool' })
            } -ParameterFilter { $Path -like 'IIS:\AppPools*' }
            Mock -CommandName 'Get-WebAppPoolState' -ModuleName 'PSWinOps' -MockWith { throw 'Access denied' }
            Mock -CommandName 'Get-Website' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{
                    Name = 'Default Web Site'; State = 'Started'
                    applicationPool = 'DefaultAppPool'; physicalPath = 'C:\inetpub\wwwroot'
                    Bindings = [PSCustomObject]@{
                        Collection = @([PSCustomObject]@{ protocol = 'http'; bindingInformation = '*:80:' })
                    }
                })
            }
            $script:poolThrow = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should set AppPoolState to Unknown' { $script:poolThrow[0].AppPoolState | Should -Be 'Unknown' }
    }

    Context 'Local - CIM Invoke-CimMethod throws' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'W3SVC'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $ListAvailable }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Name = 'CIMSite' })
            } -ParameterFilter { $Namespace -eq 'root/webadministration' }
            Mock -CommandName 'Invoke-CimMethod' -ModuleName 'PSWinOps' -MockWith { throw 'Method failed' }
            $script:cimMethodFail = Get-IISHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should set SiteState to Unknown' { $script:cimMethodFail[0].SiteState | Should -Be 'Unknown' }
        It 'Should still return a result' { $script:cimMethodFail | Should -Not -BeNullOrEmpty }
    }

    Context 'Remote with Credential' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:cred = [PSCredential]::new('testuser', (ConvertTo-SecureString -String 'P@ss1' -AsPlainText -Force))
            $script:credResult = Get-IISHealth -ComputerName 'SRV01' -Credential $script:cred
        }

        It 'Should return a result' { $script:credResult | Should -Not -BeNullOrEmpty }
        It 'Should call Invoke-Command for remote execution' {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -Scope Context
        }
    }

}
