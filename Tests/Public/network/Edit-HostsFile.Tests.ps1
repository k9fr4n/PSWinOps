#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Edit-HostsFile' {

    Context 'Parameter validation' {
        It 'Should have CmdletBinding with SupportsShouldProcess' {
            $cmd = Get-Command -Name 'Edit-HostsFile'
            $cmd.CmdletBinding | Should -BeTrue
            $meta = [System.Management.Automation.CommandMetadata]::new($cmd)
            $meta.SupportsShouldProcess | Should -BeTrue
        }

        It 'Should have OutputType void' {
            $cmd = Get-Command -Name 'Edit-HostsFile'
            $cmd.OutputType.Type | Should -Contain ([void])
        }

        It 'Should have Editor parameter with default notepad.exe' {
            $cmd = Get-Command -Name 'Edit-HostsFile'
            $param = $cmd.Parameters['Editor']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should reject empty Editor' {
            { Edit-HostsFile -Editor '' } | Should -Throw
        }
    }

    Context 'Happy path - opens hosts file with notepad' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Process' -MockWith { }
        }

        It 'Should call Start-Process with Verb RunAs' {
            Edit-HostsFile -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Verb -eq 'RunAs'
            }
        }

        It 'Should use notepad.exe by default' {
            Edit-HostsFile -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'notepad.exe'
            }
        }

        It 'Should pass the hosts file path as argument' {
            Edit-HostsFile -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $ArgumentList -like '*drivers*etc*hosts'
            }
        }
    }

    Context 'Custom editor' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Process' -MockWith { }
        }

        It 'Should use the specified editor' {
            Edit-HostsFile -Editor 'notepad++.exe' -Confirm:$false
            Should -Invoke -CommandName 'Start-Process' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'notepad++.exe'
            }
        }
    }

    Context 'WhatIf support' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Process' -MockWith { }
        }

        It 'Should not call Start-Process with -WhatIf' {
            Edit-HostsFile -WhatIf
            Should -Invoke -CommandName 'Start-Process' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    Context 'Hosts file not found' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $false }
        }

        It 'Should throw a terminating error if hosts file is missing' {
            { Edit-HostsFile -Confirm:$false } | Should -Throw '*Hosts file not found*'
        }
    }

    Context 'Start-Process failure' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Process' -MockWith {
                throw 'The operation was canceled by the user'
            }
        }

        It 'Should write error when UAC is cancelled' {
            Edit-HostsFile -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like '*Failed to open hosts file*') | Should -Not -BeNullOrEmpty
        }
    }
}
