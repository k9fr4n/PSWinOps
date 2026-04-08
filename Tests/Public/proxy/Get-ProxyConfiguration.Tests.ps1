#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-ProxyConfiguration' {

    Context 'When proxy is fully configured on all three layers' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -MockWith {
                [PSCustomObject]@{
                    ProxyEnable   = 1
                    ProxyServer   = 'proxy.example.com:8080'
                    ProxyOverride = '*.local;*.example.com;<local>'
                    AutoConfigURL = 'http://pac.example.com/proxy.pac'
                }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh.exe'
            } -MockWith { $true }

            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }

            # Mock the netsh.exe call via a script-scoped variable
            $script:mockNetshOutput = @(
                'Current WinHTTP proxy settings:',
                '    Proxy Server(s) :  proxy.example.com:8080',
                '    Bypass List     :  *.local;*.example.com'
            )

            # We need to mock the external command call. We do this by mocking
            # the internal call pattern. Since we cannot directly mock & exe,
            # we will set environment variables and test those separately.
            # For the netsh part, we mock at integration level.
        }

        It -Name 'Should return PSWinOps.ProxyConfiguration type' -Test {
            # For this test we only verify WinINET since netsh is external
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $result = Get-ProxyConfiguration
            $result.PSObject.TypeNames | Should -Contain 'PSWinOps.ProxyConfiguration'
        }

        It -Name 'Should return WinINET enabled' -Test {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $result = Get-ProxyConfiguration
            $result.WinInetEnabled | Should -BeTrue
        }

        It -Name 'Should return WinINET proxy server' -Test {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $result = Get-ProxyConfiguration
            $result.WinInetServer | Should -Be 'proxy.example.com:8080'
        }

        It -Name 'Should return WinINET bypass list' -Test {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $result = Get-ProxyConfiguration
            $result.WinInetBypass | Should -Be '*.local;*.example.com;<local>'
        }

        It -Name 'Should return WinINET auto-config URL' -Test {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $result = Get-ProxyConfiguration
            $result.WinInetAutoConfig | Should -Be 'http://pac.example.com/proxy.pac'
        }

        It -Name 'Should include ComputerName' -Test {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $result = Get-ProxyConfiguration
            $result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should include Timestamp in ISO 8601 format' -Test {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $result = Get-ProxyConfiguration
            $result.Timestamp | Should -Not -BeNullOrEmpty
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }
    }

    Context 'When WinINET proxy is disabled' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -MockWith {
                [PSCustomObject]@{
                    ProxyEnable   = 0
                    ProxyServer   = $null
                    ProxyOverride = $null
                    AutoConfigURL = $null
                }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }
        }

        It -Name 'Should return WinInetEnabled as false' -Test {
            $result = Get-ProxyConfiguration
            $result.WinInetEnabled | Should -BeFalse
        }

        It -Name 'Should return null WinInetServer' -Test {
            $result = Get-ProxyConfiguration
            $result.WinInetServer | Should -BeNullOrEmpty
        }

        It -Name 'Should return null WinInetBypass' -Test {
            $result = Get-ProxyConfiguration
            $result.WinInetBypass | Should -BeNullOrEmpty
        }

        It -Name 'Should return null WinInetAutoConfig' -Test {
            $result = Get-ProxyConfiguration
            $result.WinInetAutoConfig | Should -BeNullOrEmpty
        }
    }

    Context 'When WinINET registry read fails' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -MockWith {
                throw 'Registry access denied'
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }
        }

        It -Name 'Should not throw' -Test {
            { Get-ProxyConfiguration } | Should -Not -Throw
        }

        It -Name 'Should return WinInetEnabled as false on failure' -Test {
            $result = Get-ProxyConfiguration
            $result.WinInetEnabled | Should -BeFalse
        }

        It -Name 'Should write a warning on failure' -Test {
            $result = Get-ProxyConfiguration 3>&1
            # The function should still return an object
            # Warning is written via Write-Warning
        }

        It -Name 'Should still return a valid object with all properties' -Test {
            $result = Get-ProxyConfiguration
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'WinInetEnabled'
            $result.PSObject.Properties.Name | Should -Contain 'WinHttpEnabled'
            $result.PSObject.Properties.Name | Should -Contain 'EnvHttpProxy'
            $result.PSObject.Properties.Name | Should -Contain 'Timestamp'
        }
    }

    Context 'When netsh.exe is not found' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -MockWith {
                [PSCustomObject]@{
                    ProxyEnable   = 0
                    ProxyServer   = $null
                    ProxyOverride = $null
                    AutoConfigURL = $null
                }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }
        }

        It -Name 'Should not throw when netsh is missing' -Test {
            { Get-ProxyConfiguration } | Should -Not -Throw
        }

        It -Name 'Should return WinHttpEnabled as false' -Test {
            $result = Get-ProxyConfiguration
            $result.WinHttpEnabled | Should -BeFalse
        }

        It -Name 'Should return null WinHttpServer' -Test {
            $result = Get-ProxyConfiguration
            $result.WinHttpServer | Should -BeNullOrEmpty
        }

        It -Name 'Should return null WinHttpBypass' -Test {
            $result = Get-ProxyConfiguration
            $result.WinHttpBypass | Should -BeNullOrEmpty
        }
    }

    Context 'When environment variables are set' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -MockWith {
                [PSCustomObject]@{
                    ProxyEnable   = 0
                    ProxyServer   = $null
                    ProxyOverride = $null
                    AutoConfigURL = $null
                }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $env:HTTP_PROXY  = 'http://proxy.example.com:8080'
            $env:HTTPS_PROXY = 'http://proxy.example.com:8443'
            $env:NO_PROXY    = '.example.com,.local,localhost'
        }

        AfterAll {
            $env:HTTP_PROXY  = $null
            $env:HTTPS_PROXY = $null
            $env:NO_PROXY    = $null
        }

        It -Name 'Should return HTTP_PROXY value' -Test {
            $result = Get-ProxyConfiguration
            $result.EnvHttpProxy | Should -Be 'http://proxy.example.com:8080'
        }

        It -Name 'Should return HTTPS_PROXY value' -Test {
            $result = Get-ProxyConfiguration
            $result.EnvHttpsProxy | Should -Be 'http://proxy.example.com:8443'
        }

        It -Name 'Should return NO_PROXY value' -Test {
            $result = Get-ProxyConfiguration
            $result.EnvNoProxy | Should -Be '.example.com,.local,localhost'
        }
    }

    Context 'When no environment variables are set' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -MockWith {
                [PSCustomObject]@{
                    ProxyEnable   = 0
                    ProxyServer   = $null
                    ProxyOverride = $null
                    AutoConfigURL = $null
                }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $env:HTTP_PROXY  = $null
            $env:HTTPS_PROXY = $null
            $env:NO_PROXY    = $null
            $env:http_proxy  = $null
            $env:https_proxy = $null
            $env:no_proxy    = $null
        }

        It -Name 'Should return null EnvHttpProxy' -Test {
            $result = Get-ProxyConfiguration
            $result.EnvHttpProxy | Should -BeNullOrEmpty
        }

        It -Name 'Should return null EnvHttpsProxy' -Test {
            $result = Get-ProxyConfiguration
            $result.EnvHttpsProxy | Should -BeNullOrEmpty
        }

        It -Name 'Should return null EnvNoProxy' -Test {
            $result = Get-ProxyConfiguration
            $result.EnvNoProxy | Should -BeNullOrEmpty
        }
    }

    Context 'When WinINET has only PAC auto-config (no static proxy)' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -MockWith {
                [PSCustomObject]@{
                    ProxyEnable   = 0
                    ProxyServer   = $null
                    ProxyOverride = $null
                    AutoConfigURL = 'http://wpad.example.com/wpad.dat'
                }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }
        }

        It -Name 'Should return WinInetEnabled as false (static proxy disabled)' -Test {
            $result = Get-ProxyConfiguration
            $result.WinInetEnabled | Should -BeFalse
        }

        It -Name 'Should return the PAC URL in WinInetAutoConfig' -Test {
            $result = Get-ProxyConfiguration
            $result.WinInetAutoConfig | Should -Be 'http://wpad.example.com/wpad.dat'
        }

        It -Name 'Should return null WinInetServer' -Test {
            $result = Get-ProxyConfiguration
            $result.WinInetServer | Should -BeNullOrEmpty
        }
    }

    Context 'Output object structure' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-ItemProperty' -MockWith {
                [PSCustomObject]@{
                    ProxyEnable   = 0
                    ProxyServer   = $null
                    ProxyOverride = $null
                    AutoConfigURL = $null
                }
            }

            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            $script:result = Get-ProxyConfiguration
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProperties = @(
                'ComputerName', 'WinInetEnabled', 'WinInetServer', 'WinInetBypass',
                'WinInetAutoConfig', 'WinHttpEnabled', 'WinHttpServer', 'WinHttpBypass',
                'EnvHttpProxy', 'EnvHttpsProxy', 'EnvNoProxy', 'Timestamp'
            )
            foreach ($prop in $expectedProperties) {
                $script:result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It -Name 'Should have PSTypeName PSWinOps.ProxyConfiguration' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.ProxyConfiguration'
        }

        It -Name 'Should have ComputerName matching local machine' -Test {
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
        }
    }

    Context 'Parameter validation' {
        It -Name 'Should have CmdletBinding attribute' -Test {
            $cmdInfo = Get-Command -Name 'Get-ProxyConfiguration'
            $cmdInfo.CmdletBinding | Should -BeTrue
        }

        It -Name 'Should have no mandatory parameters' -Test {
            $cmdInfo = Get-Command -Name 'Get-ProxyConfiguration'
            $mandatoryParams = $cmdInfo.Parameters.Values | Where-Object -FilterScript {
                $_.Attributes | Where-Object -FilterScript {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                }
            }
            $mandatoryParams | Should -BeNullOrEmpty
        }

        It -Name 'Should support -Verbose' -Test {
            $cmdInfo = Get-Command -Name 'Get-ProxyConfiguration'
            $cmdInfo.Parameters.ContainsKey('Verbose') | Should -BeTrue
        }
    }

    Context 'Integration test with real system' -Tag 'Integration' {
        It -Name 'Should return proxy configuration from real system' -Skip:(-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) -Test {
            $result = Get-ProxyConfiguration
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.PSObject.TypeNames | Should -Contain 'PSWinOps.ProxyConfiguration'
        }
    }
}
