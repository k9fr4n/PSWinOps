#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Set-ProxyConfiguration' {

    Context 'Parameter validation' {
        It 'Should have CmdletBinding with SupportsShouldProcess' {
            $cmd = Get-Command -Name 'Set-ProxyConfiguration'
            $cmd.CmdletBinding | Should -BeTrue
            $attr = $cmd.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $attr.SupportsShouldProcess | Should -BeTrue
        }

        It 'Should have ConfirmImpact set to Medium' {
            $cmd = Get-Command -Name 'Set-ProxyConfiguration'
            $attr = $cmd.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $attr.ConfirmImpact | Should -Be 'Medium'
        }

        It 'Should throw when neither ProxyServer nor AutoConfigURL is provided' {
            { Set-ProxyConfiguration -Confirm:$false } | Should -Throw -ExpectedMessage '*must specify*'
        }

        It 'Should reject invalid AutoConfigURL (not http/https)' {
            { Set-ProxyConfiguration -AutoConfigURL 'ftp://bad.example.com/pac' -Scope WinINET -Confirm:$false } | Should -Throw
        }

        It 'Should accept valid AutoConfigURL with http' {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            { Set-ProxyConfiguration -AutoConfigURL 'http://wpad.example.com/proxy.pac' -Scope WinINET -Confirm:$false } | Should -Not -Throw
        }

        It 'Should accept valid AutoConfigURL with https' {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            { Set-ProxyConfiguration -AutoConfigURL 'https://wpad.example.com/proxy.pac' -Scope WinINET -Confirm:$false } | Should -Not -Throw
        }

        It 'Should validate Scope values' {
            { Set-ProxyConfiguration -ProxyServer 'proxy:8080' -Scope 'InvalidScope' -Confirm:$false } | Should -Throw
        }
    }

    Context 'WinINET scope - static proxy' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
        }

        It 'Should call Set-ItemProperty to enable proxy' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'ProxyEnable' -and $Value -eq 1
            }
        }

        It 'Should call Set-ItemProperty to set proxy server' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'ProxyServer' -and $Value -eq 'proxy.example.com:8080'
            }
        }

        It 'Should call Set-ItemProperty to set bypass list when provided' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -BypassList '*.local;<local>' -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'ProxyOverride' -and $Value -eq '*.local;<local>'
            }
        }

        It 'Should not set bypass list when not provided' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 0 -Exactly -ParameterFilter {
                $Name -eq 'ProxyOverride'
            }
        }

        It 'Should set AutoConfigURL when provided' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -AutoConfigURL 'http://wpad.example.com/proxy.pac' -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'AutoConfigURL' -and $Value -eq 'http://wpad.example.com/proxy.pac'
            }
        }
    }

    Context 'WinINET scope - PAC only (no static proxy)' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
        }

        It 'Should set AutoConfigURL without setting ProxyEnable' {
            Set-ProxyConfiguration -AutoConfigURL 'http://wpad.example.com/proxy.pac' -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'AutoConfigURL'
            }
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 0 -Exactly -ParameterFilter {
                $Name -eq 'ProxyEnable'
            }
        }
    }

    Context 'WinINET scope - error handling' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {
                throw 'Access denied'
            }
        }

        It 'Should write non-terminating error when Set-ItemProperty fails' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like '*Failed to configure WinINET*') | Should -Not -BeNullOrEmpty
        }

        It 'Should not throw when called with ErrorAction SilentlyContinue' {
            { Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'WinHTTP scope' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
        }

        It 'Should warn and skip when ProxyServer is not provided' {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            $warnings = Set-ProxyConfiguration -AutoConfigURL 'http://wpad.example.com/proxy.pac' -Scope WinHTTP -Confirm:$false 3>&1
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should write error when netsh.exe is not found' {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinHTTP -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].Exception.Message | Should -BeLike '*netsh.exe not found*'
        }
    }

    Context 'Environment scope' {
        BeforeAll {
            $script:origHttpProxy  = $env:HTTP_PROXY
            $script:origHttpsProxy = $env:HTTPS_PROXY
            $script:origNoProxy    = $env:NO_PROXY
        }

        BeforeEach {
            $env:HTTP_PROXY  = $null
            $env:HTTPS_PROXY = $null
            $env:NO_PROXY    = $null
        }

        AfterEach {
            $env:HTTP_PROXY  = $script:origHttpProxy
            $env:HTTPS_PROXY = $script:origHttpsProxy
            $env:NO_PROXY    = $script:origNoProxy
        }

        It 'Should set HTTP_PROXY process env var' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:HTTP_PROXY | Should -Be 'http://proxy.example.com:8080'
        }

        It 'Should set HTTPS_PROXY process env var' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:HTTPS_PROXY | Should -Be 'http://proxy.example.com:8080'
        }

        It 'Should prepend http:// when scheme is missing' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:HTTP_PROXY | Should -BeLike 'http://*'
        }

        It 'Should not prepend http:// when scheme is already present' {
            Set-ProxyConfiguration -ProxyServer 'https://proxy.example.com:8443' -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:HTTP_PROXY | Should -Be 'https://proxy.example.com:8443'
        }

        It 'Should set NO_PROXY with converted bypass list' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -BypassList '*.local;*.example.com;<local>' -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:NO_PROXY | Should -Be '*.local,*.example.com,localhost'
        }

        It 'Should not set NO_PROXY when bypass list is not provided' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:NO_PROXY | Should -BeNullOrEmpty
        }

        It 'Should warn and skip when ProxyServer is not provided' {
            $warnings = Set-ProxyConfiguration -AutoConfigURL 'http://wpad.example.com/proxy.pac' -Scope Environment -Confirm:$false 3>&1
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Scope resolution' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $false } -ParameterFilter { $Path -like '*netsh*' }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
        }

        It 'Should resolve All to WinINET, WinHTTP, and Environment' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope All -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -ParameterFilter {
                $Name -eq 'ProxyEnable'
            }
        }

        It 'Should handle multiple explicit scopes' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET, Environment -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -ParameterFilter {
                $Name -eq 'ProxyEnable'
            }
        }

        It 'Should default Scope to All' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -ParameterFilter {
                $Name -eq 'ProxyEnable'
            }
        }
    }

    Context 'WhatIf support' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $true } -ParameterFilter { $Path -like '*netsh*' }
        }

        It 'Should not call Set-ItemProperty with -WhatIf' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET -WhatIf
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 0 -Exactly
        }

        It 'Should not throw with -WhatIf' {
            { Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Output' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $false } -ParameterFilter { $Path -like '*netsh*' }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
        }

        It 'Should return void (no output object)' {
            $result = Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET -Confirm:$false 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] }
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'WinHTTP scope - elevation check' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $false }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
        }

        It 'Should write error when not elevated and WinHTTP scope is targeted' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinHTTP -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like '*Administrator privileges*') | Should -Not -BeNullOrEmpty
        }

        It 'Should not affect WinINET scope when WinHTTP elevation fails' {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET, WinHTTP -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -ParameterFilter {
                $Name -eq 'ProxyEnable'
            }
        }
    }


    Context 'Environment scope - User-level persistence with BypassList' {
        BeforeAll {
            $script:origHttp = $env:HTTP_PROXY
            $script:origHttps = $env:HTTPS_PROXY
            $script:origNo = $env:NO_PROXY
        }
        BeforeEach {
            $env:HTTP_PROXY = $null; $env:HTTPS_PROXY = $null; $env:NO_PROXY = $null
        }
        AfterEach {
            $env:HTTP_PROXY = $script:origHttp; $env:HTTPS_PROXY = $script:origHttps; $env:NO_PROXY = $script:origNo
        }

        It 'Should set NO_PROXY when BypassList is provided with only Environment scope' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -BypassList '*.local;*.corp;<local>' -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $env:NO_PROXY | Should -Not -BeNullOrEmpty
        }

        It 'Should convert <local> to localhost and semicolons to commas in NO_PROXY' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -BypassList '*.local;<local>' -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $env:NO_PROXY | Should -BeLike '*localhost*'
            $env:NO_PROXY | Should -Match ','
        }

        It 'Should set process-level vars even if User-level persistence fails' {
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $env:HTTP_PROXY | Should -Be 'http://proxy.example.com:8080'
        }
    }

}
