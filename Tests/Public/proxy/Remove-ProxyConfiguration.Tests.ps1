#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Remove-ProxyConfiguration' {

    Context 'Parameter validation' {
        It 'Should have CmdletBinding with SupportsShouldProcess' {
            $cmd = Get-Command -Name 'Remove-ProxyConfiguration'
            $cmd.CmdletBinding | Should -BeTrue
            $attr = $cmd.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $attr.SupportsShouldProcess | Should -BeTrue
        }

        It 'Should have ConfirmImpact set to Medium' {
            $cmd = Get-Command -Name 'Remove-ProxyConfiguration'
            $attr = $cmd.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $attr.ConfirmImpact | Should -Be 'Medium'
        }

        It 'Should have no mandatory parameters' {
            $cmd = Get-Command -Name 'Remove-ProxyConfiguration'
            $mandatoryParams = $cmd.Parameters.Values | Where-Object {
                $_.Attributes | Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                }
            }
            $mandatoryParams | Should -BeNullOrEmpty
        }

        It 'Should validate Scope values' {
            { Remove-ProxyConfiguration -Scope 'InvalidScope' -Confirm:$false } | Should -Throw
        }

        It 'Should default Scope to All' {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Remove-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $false } -ParameterFilter { $Path -like '*netsh*' }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter { $ChildPath -eq 'System32\netsh.exe' } -MockWith { 'C:\Windows\System32\netsh.exe' }

            Remove-ProxyConfiguration -Confirm:$false -ErrorAction SilentlyContinue
            # WinINET should be processed (part of All)
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -ParameterFilter {
                $Name -eq 'ProxyEnable' -and $Value -eq 0
            }
        }
    }

    Context 'WinINET scope' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Remove-ItemProperty' -MockWith {}
        }

        It 'Should disable proxy by setting ProxyEnable to 0' {
            Remove-ProxyConfiguration -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'ProxyEnable' -and $Value -eq 0
            }
        }

        It 'Should remove ProxyServer property' {
            Remove-ProxyConfiguration -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Remove-ItemProperty' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'ProxyServer'
            }
        }

        It 'Should remove ProxyOverride property' {
            Remove-ProxyConfiguration -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Remove-ItemProperty' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'ProxyOverride'
            }
        }

        It 'Should remove AutoConfigURL property' {
            Remove-ProxyConfiguration -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Remove-ItemProperty' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'AutoConfigURL'
            }
        }

        It 'Should remove all three properties in one call' {
            Remove-ProxyConfiguration -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Remove-ItemProperty' -ModuleName $script:ModuleName -Times 3 -Exactly
        }
    }

    Context 'WinINET scope - error handling' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith { throw 'Access denied' }
            Mock -ModuleName $script:ModuleName -CommandName 'Remove-ItemProperty' -MockWith {}
        }

        It 'Should write non-terminating error when Set-ItemProperty fails' {
            Remove-ProxyConfiguration -Scope WinINET -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like '*Failed to remove WinINET*') | Should -Not -BeNullOrEmpty
        }

        It 'Should not throw with ErrorAction SilentlyContinue' {
            { Remove-ProxyConfiguration -Scope WinINET -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should not call Remove-ItemProperty if Set-ItemProperty fails' {
            Remove-ProxyConfiguration -Scope WinINET -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Remove-ItemProperty' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    Context 'WinHTTP scope' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
        }

        It 'Should write error when netsh.exe is not found' {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            Remove-ProxyConfiguration -Scope WinHTTP -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like '*netsh.exe not found*') | Should -Not -BeNullOrEmpty
        }

        It 'Should not throw when netsh.exe is missing' {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }

            { Remove-ProxyConfiguration -Scope WinHTTP -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'WinHTTP scope - admin with netsh present' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
        }

        It 'Should pass elevation check when administrator' {
            Remove-ProxyConfiguration -Scope WinHTTP -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Test-IsAdministrator' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should check netsh.exe exists after admin check passes' {
            Remove-ProxyConfiguration -Scope WinHTTP -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Test-Path' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Path -like '*netsh*'
            }
        }

        It 'Should not throw when netsh execution fails gracefully' {
            { Remove-ProxyConfiguration -Scope WinHTTP -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Environment scope' {
        BeforeAll {
            $script:origHttpProxy  = $env:HTTP_PROXY
            $script:origHttpsProxy = $env:HTTPS_PROXY
            $script:origNoProxy    = $env:NO_PROXY
        }

        BeforeEach {
            $env:HTTP_PROXY  = 'http://proxy.example.com:8080'
            $env:HTTPS_PROXY = 'http://proxy.example.com:8080'
            $env:NO_PROXY    = '.example.com,.local'
        }

        AfterEach {
            $env:HTTP_PROXY  = $script:origHttpProxy
            $env:HTTPS_PROXY = $script:origHttpsProxy
            $env:NO_PROXY    = $script:origNoProxy
        }

        It 'Should clear HTTP_PROXY process env var' {
            Remove-ProxyConfiguration -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:HTTP_PROXY | Should -BeNullOrEmpty
        }

        It 'Should clear HTTPS_PROXY process env var' {
            Remove-ProxyConfiguration -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:HTTPS_PROXY | Should -BeNullOrEmpty
        }

        It 'Should clear NO_PROXY process env var' {
            Remove-ProxyConfiguration -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:NO_PROXY | Should -BeNullOrEmpty
        }

        It 'Should clear all three env vars in one call' {
            Remove-ProxyConfiguration -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue
            $env:HTTP_PROXY  | Should -BeNullOrEmpty
            $env:HTTPS_PROXY | Should -BeNullOrEmpty
            $env:NO_PROXY    | Should -BeNullOrEmpty
        }
    }

    Context 'Environment scope - User-level variable cleanup failure' {
        BeforeAll {
            $script:origHttpProxy2  = $env:HTTP_PROXY
            $script:origHttpsProxy2 = $env:HTTPS_PROXY
            $script:origNoProxy2    = $env:NO_PROXY
        }

        BeforeEach {
            $env:HTTP_PROXY  = 'http://proxy.example.com:8080'
            $env:HTTPS_PROXY = 'http://proxy.example.com:8080'
            $env:NO_PROXY    = '.example.com'
        }

        AfterEach {
            $env:HTTP_PROXY  = $script:origHttpProxy2
            $env:HTTPS_PROXY = $script:origHttpsProxy2
            $env:NO_PROXY    = $script:origNoProxy2
        }

        It 'Should still clear process-level env vars even if User-level fails' {
            # On Linux/CI, SetEnvironmentVariable with User target may throw
            # Either way, process-level vars should still be cleared
            Remove-ProxyConfiguration -Scope Environment -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $env:HTTP_PROXY | Should -BeNullOrEmpty
            $env:HTTPS_PROXY | Should -BeNullOrEmpty
            $env:NO_PROXY | Should -BeNullOrEmpty
        }
    }

    Context 'Scope resolution' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Remove-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $false } -ParameterFilter { $Path -like '*netsh*' }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter { $ChildPath -eq 'System32\netsh.exe' } -MockWith { 'C:\Windows\System32\netsh.exe' }
        }

        It 'Should resolve All to all three scopes' {
            Remove-ProxyConfiguration -Scope All -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -ParameterFilter {
                $Name -eq 'ProxyEnable'
            }
        }

        It 'Should handle multiple explicit scopes' {
            Remove-ProxyConfiguration -Scope WinINET, Environment -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -ParameterFilter {
                $Name -eq 'ProxyEnable'
            }
        }

        It 'Should only affect targeted scope' {
            Remove-ProxyConfiguration -Scope WinINET -Confirm:$false
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -ParameterFilter {
                $Name -eq 'ProxyEnable'
            }
            # WinHTTP should not be attempted
            Should -Invoke -CommandName 'Test-Path' -ModuleName $script:ModuleName -Times 0 -Exactly -ParameterFilter {
                $Path -like '*netsh*'
            }
        }
    }

    Context 'WhatIf support' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Remove-ItemProperty' -MockWith {}
        }

        It 'Should not call Set-ItemProperty with -WhatIf' {
            Remove-ProxyConfiguration -Scope WinINET -WhatIf
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -Times 0 -Exactly
        }

        It 'Should not call Remove-ItemProperty with -WhatIf' {
            Remove-ProxyConfiguration -Scope WinINET -WhatIf
            Should -Invoke -CommandName 'Remove-ItemProperty' -ModuleName $script:ModuleName -Times 0 -Exactly
        }

        It 'Should not throw with -WhatIf' {
            { Remove-ProxyConfiguration -WhatIf } | Should -Not -Throw
        }

        It 'Should not clear env vars with -WhatIf' {
            $env:HTTP_PROXY = 'http://proxy.example.com:8080'
            Remove-ProxyConfiguration -Scope Environment -WhatIf
            $env:HTTP_PROXY | Should -Be 'http://proxy.example.com:8080'
            $env:HTTP_PROXY = $null
        }
    }

    Context 'Output' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Remove-ItemProperty' -MockWith {}
        }

        It 'Should return void (no output object)' {
            $result = Remove-ProxyConfiguration -Scope WinINET -Confirm:$false 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] }
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
            Remove-ProxyConfiguration -Scope WinHTTP -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like '*Administrator privileges*') | Should -Not -BeNullOrEmpty
        }

        It 'Should not affect WinINET scope when WinHTTP elevation fails' {
            Mock -ModuleName $script:ModuleName -CommandName 'Set-ItemProperty' -MockWith {}
            Mock -ModuleName $script:ModuleName -CommandName 'Remove-ItemProperty' -MockWith {}
            Remove-ProxyConfiguration -Scope WinINET, WinHTTP -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Set-ItemProperty' -ModuleName $script:ModuleName -ParameterFilter {
                $Name -eq 'ProxyEnable'
            }
        }
    }

}
