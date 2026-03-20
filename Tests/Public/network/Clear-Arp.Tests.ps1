#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Clear-Arp' {

    Context 'Parameter validation' {
        It 'Should have CmdletBinding with SupportsShouldProcess' {
            $cmd = Get-Command -Name 'Clear-Arp'
            $cmd.CmdletBinding | Should -BeTrue
            $attr = $cmd.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $attr.SupportsShouldProcess | Should -BeTrue
        }

        It 'Should have ConfirmImpact set to Medium' {
            $cmd = Get-Command -Name 'Clear-Arp'
            $attr = $cmd.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $attr.ConfirmImpact | Should -Be 'Medium'
        }

        It 'Should have no mandatory parameters' {
            $cmd = Get-Command -Name 'Clear-Arp'
            $mandatoryParams = $cmd.Parameters.Values | Where-Object {
                $_.Attributes | Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                }
            }
            $mandatoryParams | Should -BeNullOrEmpty
        }

        It 'Should have OutputType of void' {
            $cmd = Get-Command -Name 'Clear-Arp'
            $cmd.OutputType.Type | Should -Contain ([void])
        }
    }

    Context 'Elevation check' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $false }
        }

        It 'Should throw terminating error when not elevated' {
            { Clear-Arp -Confirm:$false } | Should -Throw '*Administrator privileges*'
        }

        It 'Should throw UnauthorizedAccessException when not elevated' {
            $threw = $false
            try {
                Clear-Arp -Confirm:$false
            } catch {
                $threw = $true
                $_.Exception | Should -BeOfType [System.UnauthorizedAccessException]
            }
            $threw | Should -BeTrue
        }
    }

    Context 'Binary validation' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }
        }

        It 'Should throw terminating error when netsh.exe is not found' {
            { Clear-Arp -Confirm:$false } | Should -Throw '*netsh.exe not found*'
        }

        It 'Should throw FileNotFoundException when netsh.exe is missing' {
            $threw = $false
            try {
                Clear-Arp -Confirm:$false
            } catch {
                $threw = $true
                $_.Exception | Should -BeOfType [System.IO.FileNotFoundException]
            }
            $threw | Should -BeTrue
        }
    }

    Context 'Happy path - ARP cache cleared successfully' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-NativeCommand' -MockWith {
                return [PSCustomObject]@{ Output = 'Ok.'; ExitCode = 0 }
            }
        }

        It 'Should not throw on success' {
            { Clear-Arp -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should return void (no output object)' {
            $result = Clear-Arp -Confirm:$false 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] }
            $result | Should -BeNullOrEmpty
        }

        It 'Should call Invoke-NativeCommand with netsh arguments' {
            Clear-Arp -Confirm:$false
            Should -Invoke -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Failure path - netsh returns non-zero exit code' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-NativeCommand' -MockWith {
                return [PSCustomObject]@{ Output = 'The requested operation requires elevation.'; ExitCode = 1 }
            }
        }

        It 'Should write non-terminating error when netsh fails' {
            Clear-Arp -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like '*netsh interface ip delete arpcache failed*') | Should -Not -BeNullOrEmpty
        }

        It 'Should not throw with ErrorAction SilentlyContinue' {
            { Clear-Arp -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'WhatIf support' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Join-Path' -ParameterFilter {
                $ChildPath -eq 'System32\netsh.exe'
            } -MockWith { 'C:\Windows\System32\netsh.exe' }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-NativeCommand' -MockWith {
                return [PSCustomObject]@{ Output = 'Ok.'; ExitCode = 0 }
            }
        }

        It 'Should not execute netsh with -WhatIf' {
            Clear-Arp -WhatIf
            Should -Invoke -CommandName 'Invoke-NativeCommand' -ModuleName $script:ModuleName -Times 0 -Exactly
        }

        It 'Should not throw with -WhatIf' {
            { Clear-Arp -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Integration' -Tag 'Integration' {
        It 'Should clear the ARP cache on a real Windows machine' -Skip:(-not (Test-Path "$env:SystemRoot\System32\netsh.exe")) {
            { Clear-Arp -Confirm:$false } | Should -Not -Throw
        }
    }
}
