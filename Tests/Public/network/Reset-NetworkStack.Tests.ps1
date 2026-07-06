#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'

    function global:Clear-DnsClientCache {
        param()
    }
}

Describe 'Reset-NetworkStack' {

    Context 'Parameter validation' {
        It 'Should have CmdletBinding with SupportsShouldProcess' {
            $cmd = Get-Command -Name 'Reset-NetworkStack'
            $meta = [System.Management.Automation.CommandMetadata]::new($cmd)
            $meta.SupportsShouldProcess | Should -BeTrue
        }

        It 'Should have ConfirmImpact set to High' {
            $cmd = Get-Command -Name 'Reset-NetworkStack'
            $meta = [System.Management.Automation.CommandMetadata]::new($cmd)
            $meta.ConfirmImpact | Should -Be 'High'
        }

        It 'Should have OutputType of PSWinOps.NetworkStackResetResult' {
            $cmd = Get-Command -Name 'Reset-NetworkStack'
            $cmd.OutputType.Name | Should -Contain 'PSWinOps.NetworkStackResetResult'
        }

        It 'Should have no mandatory parameters' {
            $cmd = Get-Command -Name 'Reset-NetworkStack'
            $mandatoryParams = $cmd.Parameters.Values | Where-Object {
                $_.Attributes | Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                }
            }
            $mandatoryParams | Should -BeNullOrEmpty
        }

        It 'Should reject empty ComputerName' {
            { Reset-NetworkStack -ComputerName '' -Confirm:$false } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            { Reset-NetworkStack -ComputerName $null -Confirm:$false } | Should -Throw
        }

        It 'Should have IncludeFirewall as a switch parameter' {
            $cmd = Get-Command -Name 'Reset-NetworkStack'
            $cmd.Parameters['IncludeFirewall'].ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have SkipDnsFlush as a switch parameter' {
            $cmd = Get-Command -Name 'Reset-NetworkStack'
            $cmd.Parameters['SkipDnsFlush'].ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have a Credential parameter of type PSCredential' {
            $cmd = Get-Command -Name 'Reset-NetworkStack'
            $cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'Elevation check' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $false }
        }

        It 'Should throw terminating error when not elevated' {
            { Reset-NetworkStack -Confirm:$false } | Should -Throw '*Administrator privileges*'
        }

        It 'Should throw UnauthorizedAccessException when not elevated' {
            $threw = $false
            try {
                Reset-NetworkStack -Confirm:$false
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
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $false }
        }

        It 'Should throw terminating error when netsh.exe is not found' {
            { Reset-NetworkStack -Confirm:$false } | Should -Throw '*netsh.exe not found*'
        }

        It 'Should throw FileNotFoundException when netsh.exe is missing' {
            $threw = $false
            try {
                Reset-NetworkStack -Confirm:$false
            } catch {
                $threw = $true
                $_.Exception | Should -BeOfType [System.IO.FileNotFoundException]
            }
            $threw | Should -BeTrue
        }
    }

    Context 'Happy path - local machine' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-NativeCommand' -MockWith {
                [PSCustomObject]@{ Output = ''; ExitCode = 0 }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-DnsClientCache' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Arp' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RemoteOrLocal' -MockWith {
                param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                & $ScriptBlock @ArgumentList
            }
        }

        It 'Should return Success = $true and RebootRequired = $true for the local machine' {
            $result = Reset-NetworkStack -Confirm:$false

            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Success | Should -BeTrue
            $result.RebootRequired | Should -BeTrue
            $result.PSTypeNames | Should -Contain 'PSWinOps.NetworkStackResetResult'
        }

        It 'Should include a valid Timestamp' {
            $result = Reset-NetworkStack -Confirm:$false
            $result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }

        It 'Should run all always-steps by default (Winsock, IpReset, DnsFlush, ArpClear) without FirewallReset' {
            $result = Reset-NetworkStack -Confirm:$false
            $stepNames = $result.StepsRun | ForEach-Object { $_.Step }

            $stepNames | Should -Contain 'WinsockReset'
            $stepNames | Should -Contain 'IpReset'
            $stepNames | Should -Contain 'DnsFlush'
            $stepNames | Should -Contain 'ArpClear'
            $stepNames | Should -Not -Contain 'FirewallReset'
        }

        It 'Should respect -WhatIf and not dispatch via Invoke-RemoteOrLocal' {
            $null = Reset-NetworkStack -WhatIf
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    Context 'Step failure aggregation' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-DnsClientCache' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Arp' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RemoteOrLocal' -MockWith {
                param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                & $ScriptBlock @ArgumentList
            }
        }

        It 'Should keep running remaining steps and report Success = $false when a step exits non-zero' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-NativeCommand' -MockWith {
                param($FilePath, $ArgumentList)
                if ($ArgumentList[0] -eq 'int') {
                    return [PSCustomObject]@{ Output = 'failed'; ExitCode = 1 }
                }
                return [PSCustomObject]@{ Output = ''; ExitCode = 0 }
            }

            $result = Reset-NetworkStack -Confirm:$false

            $result.Success | Should -BeFalse
            $stepNames = $result.StepsRun | ForEach-Object { $_.Step }
            $stepNames | Should -Contain 'WinsockReset'
            $stepNames | Should -Contain 'IpReset'
            $stepNames | Should -Contain 'DnsFlush'
            $stepNames | Should -Contain 'ArpClear'

            $ipStep = $result.StepsRun | Where-Object { $_.Step -eq 'IpReset' }
            $ipStep.ExitCode | Should -Be 1
        }

        It 'Should still report RebootRequired = $true even when a step fails' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-NativeCommand' -MockWith {
                [PSCustomObject]@{ Output = 'failed'; ExitCode = 1 }
            }

            $result = Reset-NetworkStack -Confirm:$false
            $result.RebootRequired | Should -BeTrue
        }
    }

    Context '-SkipDnsFlush' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-NativeCommand' -MockWith {
                [PSCustomObject]@{ Output = ''; ExitCode = 0 }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-DnsClientCache' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Arp' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RemoteOrLocal' -MockWith {
                param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                & $ScriptBlock @ArgumentList
            }
        }

        It 'Should omit the DnsFlush step from StepsRun' {
            $result = Reset-NetworkStack -SkipDnsFlush -Confirm:$false
            $stepNames = $result.StepsRun | ForEach-Object { $_.Step }
            $stepNames | Should -Not -Contain 'DnsFlush'
        }
    }

    Context '-IncludeFirewall' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-NativeCommand' -MockWith {
                [PSCustomObject]@{ Output = ''; ExitCode = 0 }
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-DnsClientCache' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Arp' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RemoteOrLocal' -MockWith {
                param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                & $ScriptBlock @ArgumentList
            }
        }

        It 'Should include the FirewallReset step in StepsRun' {
            $result = Reset-NetworkStack -IncludeFirewall -Confirm:$false
            $stepNames = $result.StepsRun | ForEach-Object { $_.Step }
            $stepNames | Should -Contain 'FirewallReset'
        }
    }

    Context 'Explicit remote machine with Credential propagation' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
        }

        It 'Should dispatch via Invoke-RemoteOrLocal with the target ComputerName and Credential' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RemoteOrLocal' -MockWith {
                param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                [PSCustomObject]@{ StepsRun = @(); Success = $true }
            }

            $securePwd = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('DOMAIN\svc', $securePwd)

            $null = Reset-NetworkStack -ComputerName 'REMOTESRV01' -Credential $cred -Confirm:$false

            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'REMOTESRV01' -and $null -ne $Credential -and $Credential.UserName -eq 'DOMAIN\svc'
            }
        }
    }

    Context 'Pipeline - multiple machine names' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RemoteOrLocal' -MockWith {
                param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                [PSCustomObject]@{ StepsRun = @([PSCustomObject]@{ Step = 'WinsockReset'; ExitCode = 0 }); Success = $true }
            }
        }

        It 'Should produce one result object per machine and call Invoke-RemoteOrLocal for each' {
            $results = 'REMOTE01', 'REMOTE02' | Reset-NetworkStack -Confirm:$false

            $results.Count | Should -Be 2
            ($results | Select-Object -ExpandProperty ComputerName) | Should -Be @('REMOTE01', 'REMOTE02')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    Context 'Per-machine error isolation' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
        }

        It 'Should write an error for the failed machine but not throw' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RemoteOrLocal' -MockWith {
                throw 'WinRM connection refused'
            }

            Reset-NetworkStack -ComputerName 'BADSRV01' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $errMessages = $err | ForEach-Object { $_.Exception.Message }
            ($errMessages -like "*Failed on 'BADSRV01'*") | Should -Not -BeNullOrEmpty
        }

        It 'Should continue processing remaining machines after a failure' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RemoteOrLocal' -MockWith {
                param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                if ($ComputerName -eq 'BADSRV') {
                    throw 'Connection refused'
                }
                [PSCustomObject]@{ StepsRun = @([PSCustomObject]@{ Step = 'WinsockReset'; ExitCode = 0 }); Success = $true }
            }

            { 'BADSRV', 'GOODSRV' | Reset-NetworkStack -Confirm:$false -ErrorAction SilentlyContinue } | Should -Not -Throw
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Test-IsAdministrator' -MockWith { return $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Test-Path' -ParameterFilter {
                $Path -like '*netsh*'
            } -MockWith { $true }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RemoteOrLocal' -MockWith {
                [PSCustomObject]@{ StepsRun = @(); Success = $true }
            }
        }

        It 'Should produce verbose messages including the function name' {
            $script:verbose = Reset-NetworkStack -Confirm:$false -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
            ($script:verbose.Message -join ' ') | Should -Match 'Reset-NetworkStack'
        }
    }
}
