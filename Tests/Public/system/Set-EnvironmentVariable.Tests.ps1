#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Set-EnvironmentVariable' {

    Context 'Local happy path' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Name = 'FOO'; Value = 'bar'; Scope = 'Machine' }
            }
            $script:result = Set-EnvironmentVariable -Name 'FOO' -Value 'bar' -Scope 'Machine' -Confirm:$false
        }

        It -Name 'Should return PSWinOps.EnvironmentVariable type' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.EnvironmentVariable'
        }

        It -Name 'Should set ComputerName to the local computer' -Test {
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should return Name, Value and Scope from the read-back' -Test {
            $script:result.Name | Should -Be 'FOO'
            $script:result.Value | Should -Be 'bar'
            $script:result.Scope | Should -Be 'Machine'
        }

        It -Name 'Should format Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $script:result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
    }

    Context 'Explicit remote machine with Credential' {

        BeforeAll {
            $script:cred = [System.Management.Automation.PSCredential]::new('user', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Name = 'FOO'; Value = 'bar'; Scope = 'Machine' }
            }
            $script:remoteResult = Set-EnvironmentVariable -Name 'FOO' -Value 'bar' -ComputerName 'SRV01' -Credential $script:cred -Confirm:$false
        }

        It -Name 'Should forward ComputerName and Credential to Invoke-RemoteOrLocal' -Test {
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Scope Context -ParameterFilter {
                $ComputerName -eq 'SRV01' -and $Credential -eq $script:cred
            }
        }

        It -Name 'Should set ComputerName to SRV01 on the returned object' -Test {
            $script:remoteResult.ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline of multiple machine names' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Name = 'FOO'; Value = 'bar'; Scope = 'Machine' }
            }
            $script:pipelineResults = 'SRV01', 'SRV02' | Set-EnvironmentVariable -Name 'FOO' -Value 'bar' -Confirm:$false
        }

        It -Name 'Should return one object per machine' -Test {
            @($script:pipelineResults).Count | Should -Be 2
            $script:pipelineResults[0].ComputerName | Should -Be 'SRV01'
            $script:pipelineResults[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Empty Value performs deletion' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Name = 'FOO'; Value = ''; Scope = 'Machine' }
            }
            $script:deleteResult = Set-EnvironmentVariable -Name 'FOO' -Value '' -Confirm:$false
        }

        It -Name 'Should call Invoke-RemoteOrLocal with DeleteRequested true in ArgumentList' -Test {
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Scope Context -ParameterFilter {
                $ArgumentList[0] -eq 'FOO' -and $ArgumentList[3] -eq $true
            }
        }

        It -Name 'Should emit an empty string Value' -Test {
            $script:deleteResult.Value | Should -Be ''
        }
    }

    Context 'WhatIf writes nothing' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Name = 'FOO'; Value = 'bar'; Scope = 'Machine' }
            }
            $script:whatIfResult = Set-EnvironmentVariable -Name 'FOO' -Value 'bar' -WhatIf
        }

        It -Name 'Should not invoke Invoke-RemoteOrLocal' -Test {
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Scope Context
        }

        It -Name 'Should not return any output object' -Test {
            $script:whatIfResult | Should -BeNullOrEmpty
        }
    }

    Context 'Scope validation' {

        It -Name 'Should reject an invalid Scope value' -Test {
            { Set-EnvironmentVariable -Name 'FOO' -Value 'bar' -Scope 'InvalidScope' -Confirm:$false } | Should -Throw
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should reject an empty or null Name' -Test {
            { Set-EnvironmentVariable -Name '' -Value 'bar' -Confirm:$false } | Should -Throw
        }

        It -Name 'Should reject a null or empty ComputerName' -Test {
            { Set-EnvironmentVariable -Name 'FOO' -Value 'bar' -ComputerName '' -Confirm:$false } | Should -Throw
        }
    }

    Context 'Per-machine failure isolation' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw 'Access denied'
                }
                return [PSCustomObject]@{ Name = 'FOO'; Value = 'bar'; Scope = 'Machine' }
            }
        }

        It -Name 'Should write an error for the failing machine and continue to the next one' -Test {
            $script:isolationResults = 'SRV01', 'SRV02' | Set-EnvironmentVariable -Name 'FOO' -Value 'bar' -Confirm:$false -ErrorVariable errVar -ErrorAction SilentlyContinue
            $errVar | Should -Not -BeNullOrEmpty
            @($script:isolationResults).Count | Should -Be 1
            $script:isolationResults[0].ComputerName | Should -Be 'SRV02'
        }
    }
}
