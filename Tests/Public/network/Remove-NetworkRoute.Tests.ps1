#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Remove-NetworkRoute' {

    Context 'Parameter validation' {
        It 'Should have SupportsShouldProcess' {
            $cmd = Get-Command -Name 'Remove-NetworkRoute'
            $meta = [System.Management.Automation.CommandMetadata]::new($cmd)
            $meta.SupportsShouldProcess | Should -BeTrue
        }

        It 'Should have ConfirmImpact High' {
            $cmd = Get-Command -Name 'Remove-NetworkRoute'
            $meta = [System.Management.Automation.CommandMetadata]::new($cmd)
            $meta.ConfirmImpact | Should -Be 'High'
        }

        It 'Should have OutputType void' {
            $cmd = Get-Command -Name 'Remove-NetworkRoute'
            $cmd.OutputType.Type | Should -Contain ([void])
        }

        It 'Should require DestinationPrefix parameter' {
            $cmd = Get-Command -Name 'Remove-NetworkRoute'
            $cmd.Parameters['DestinationPrefix'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should reject empty ComputerName' {
            { Remove-NetworkRoute -ComputerName '' -DestinationPrefix '10.0.0.0/8' -Confirm:$false } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            { Remove-NetworkRoute -ComputerName $null -DestinationPrefix '10.0.0.0/8' -Confirm:$false } | Should -Throw
        }
    }

    Context 'Happy path - local machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Remove-NetRoute' -MockWith { }
        }

        It 'Should call Remove-NetRoute' {
            $null = Remove-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -Confirm:$false
            Should -Invoke -CommandName 'Remove-NetRoute' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should not produce pipeline output' {
            $result = Remove-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -Confirm:$false
            $result | Should -BeNullOrEmpty
        }

        It 'Should respect -WhatIf and not call Remove-NetRoute' {
            $null = Remove-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -WhatIf
            Should -Invoke -CommandName 'Remove-NetRoute' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    Context 'Happy path - explicit remote machine' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith { }
        }

        It 'Should use Invoke-Command for remote machine' {
            $null = Remove-NetworkRoute -ComputerName 'REMOTESRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Pipeline - multiple machine names' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith { }
        }

        It 'Should accept multiple computers via pipeline' {
            $null = 'REMOTE01', 'REMOTE02' | Remove-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure - continues and writes error' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                throw 'Access denied'
            }
        }

        It 'Should write error for failed machine but not throw' {
            Remove-NetworkRoute -ComputerName 'BADSRV01' -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like "*Failed on 'BADSRV01'*") | Should -Not -BeNullOrEmpty
        }

        It 'Should continue processing remaining machines after failure' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                param($ComputerName)
                if ($ComputerName -eq 'BADSRV') {
                    throw 'Connection refused'
                }
            }

            { 'BADSRV', 'GOODSRV' | Remove-NetworkRoute -DestinationPrefix '10.10.0.0/16' -InterfaceAlias 'Ethernet' -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }
}
