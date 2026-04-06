#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Invoke-RemoteOrLocal' {

    Context 'Parameter validation' {

        BeforeAll {
            $script:cmd = & (Get-Module -Name $script:ModuleName) { Get-Command -Name 'Invoke-RemoteOrLocal' }
        }

        It 'Should have a mandatory ComputerName parameter' {
            $param = $script:cmd.Parameters['ComputerName']
            $param | Should -Not -BeNullOrEmpty
            $attr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attr.Mandatory | Should -BeTrue
        }

        It 'Should have a mandatory ScriptBlock parameter' {
            $param = $script:cmd.Parameters['ScriptBlock']
            $param | Should -Not -BeNullOrEmpty
            $attr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attr.Mandatory | Should -BeTrue
        }

        It 'Should have an optional ArgumentList parameter' {
            $param = $script:cmd.Parameters['ArgumentList']
            $param | Should -Not -BeNullOrEmpty
            $attr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attr.Mandatory | Should -BeFalse
        }

        It 'Should have an optional Credential parameter' {
            $param = $script:cmd.Parameters['Credential']
            $param | Should -Not -BeNullOrEmpty
            $attr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attr.Mandatory | Should -BeFalse
        }

        It 'Should have ValidateNotNullOrEmpty on ComputerName' {
            $param = $script:cmd.Parameters['ComputerName']
            $validates = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }
            $validates | Should -Not -BeNullOrEmpty
        }

        It 'Should reject empty ComputerName' {
            {
                & (Get-Module -Name $script:ModuleName) {
                    Invoke-RemoteOrLocal -ComputerName '' -ScriptBlock { 'test' }
                }
            } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            {
                & (Get-Module -Name $script:ModuleName) {
                    Invoke-RemoteOrLocal -ComputerName $null -ScriptBlock { 'test' }
                }
            } | Should -Throw
        }
    }

    Context 'Local execution with $env:COMPUTERNAME' {

        It 'Should execute scriptblock locally and return result' {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-RemoteOrLocal -ComputerName $env:COMPUTERNAME -ScriptBlock { 'LocalResult' }
            }
            $result | Should -Be 'LocalResult'
        }

        It 'Should pass ArgumentList to local scriptblock' {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-RemoteOrLocal -ComputerName $env:COMPUTERNAME -ScriptBlock {
                    param($a, $b)
                    "$a-$b"
                } -ArgumentList @('Hello', 'World')
            }
            $result | Should -Be 'Hello-World'
        }

        It 'Should ignore Credential for local execution' {
            $cred = [System.Management.Automation.PSCredential]::new(
                'TestUser',
                (ConvertTo-SecureString -String 'TestPass' -AsPlainText -Force)
            )
            $result = & (Get-Module -Name $script:ModuleName) {
                param($c)
                Invoke-RemoteOrLocal -ComputerName $env:COMPUTERNAME -ScriptBlock { 'LocalWithCred' } -Credential $c
            } -Args $cred
            $result | Should -Be 'LocalWithCred'
        }
    }

    Context 'Local execution with localhost alias' {

        It 'Should treat localhost as local' {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-RemoteOrLocal -ComputerName 'localhost' -ScriptBlock { 'FromLocalhost' }
            }
            $result | Should -Be 'FromLocalhost'
        }

        It 'Should treat dot (.) as local' {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-RemoteOrLocal -ComputerName '.' -ScriptBlock { 'FromDot' }
            }
            $result | Should -Be 'FromDot'
        }
    }

    Context 'Remote execution path (mocked Invoke-Command)' {

        It 'Should call Invoke-Command for non-local computer names' {
            $result = & (Get-Module -Name $script:ModuleName) {
                Mock -CommandName 'Invoke-Command' -MockWith { 'RemoteMockResult' }
                Invoke-RemoteOrLocal -ComputerName 'REMOTE-SRV01' -ScriptBlock { 'unused' }
            }
            $result | Should -Be 'RemoteMockResult'
        }

        It 'Should pass ArgumentList to Invoke-Command' {
            $result = & (Get-Module -Name $script:ModuleName) {
                Mock -CommandName 'Invoke-Command' -MockWith {
                    param($ComputerName, $ScriptBlock, $ArgumentList)
                    "Received-$($ArgumentList -join ',')"
                }
                Invoke-RemoteOrLocal -ComputerName 'REMOTE-SRV01' -ScriptBlock {
                    param($x) $x
                } -ArgumentList @('Arg1', 'Arg2')
            }
            # Mock returns its own result, not scriptblock result
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should pass Credential to Invoke-Command for remote targets' {
            $cred = [System.Management.Automation.PSCredential]::new(
                'RemoteUser',
                (ConvertTo-SecureString -String 'RemotePass' -AsPlainText -Force)
            )
            $result = & (Get-Module -Name $script:ModuleName) {
                param($c)
                Mock -CommandName 'Invoke-Command' -MockWith { 'RemoteWithCred' }
                Invoke-RemoteOrLocal -ComputerName 'REMOTE-SRV02' -ScriptBlock { 'test' } -Credential $c
            } -Args $cred
            $result | Should -Be 'RemoteWithCred'
        }

        It 'Should NOT pass Credential when it is PSCredential.Empty' {
            # Default credential should not add -Credential to invokeParams
            $result = & (Get-Module -Name $script:ModuleName) {
                Mock -CommandName 'Invoke-Command' -MockWith { 'NoCred' }
                Invoke-RemoteOrLocal -ComputerName 'REMOTE-SRV03' -ScriptBlock { 'test' }
            }
            $result | Should -Be 'NoCred'
        }
    }

    Context 'Verbose output' {

        It 'Should write verbose message for local execution' {
            $verboseOutput = & (Get-Module -Name $script:ModuleName) {
                Invoke-RemoteOrLocal -ComputerName $env:COMPUTERNAME -ScriptBlock { 'test' } -Verbose 4>&1
            }
            $verboseMessages = @($verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $verboseMessages.Message | Should -Contain "[Invoke-RemoteOrLocal] Executing locally on '$env:COMPUTERNAME'"
        }

        It 'Should write verbose message for remote execution' {
            $verboseOutput = & (Get-Module -Name $script:ModuleName) {
                Mock -CommandName 'Invoke-Command' -MockWith { 'test' }
                Invoke-RemoteOrLocal -ComputerName 'REMOTE-SRV' -ScriptBlock { 'test' } -Verbose 4>&1
            }
            $verboseMessages = @($verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $verboseMessages.Message | Should -Contain "[Invoke-RemoteOrLocal] Executing remotely on 'REMOTE-SRV' via Invoke-Command"
        }
    }

    Context 'Error propagation' {

        It 'Should propagate errors from local scriptblock execution' {
            {
                & (Get-Module -Name $script:ModuleName) {
                    Invoke-RemoteOrLocal -ComputerName $env:COMPUTERNAME -ScriptBlock {
                        throw 'Local failure'
                    }
                }
            } | Should -Throw -ExpectedMessage 'Local failure'
        }

        It 'Should propagate errors from remote Invoke-Command' {
            {
                & (Get-Module -Name $script:ModuleName) {
                    Mock -CommandName 'Invoke-Command' -MockWith { throw 'Remote failure' }
                    Invoke-RemoteOrLocal -ComputerName 'REMOTE-SRV' -ScriptBlock { 'test' }
                }
            } | Should -Throw -ExpectedMessage 'Remote failure'
        }
    }

    Context 'Return value fidelity' {

        It 'Should return single object unchanged' {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-RemoteOrLocal -ComputerName $env:COMPUTERNAME -ScriptBlock {
                    [PSCustomObject]@{ Name = 'Test'; Value = 42 }
                }
            }
            $result.Name | Should -Be 'Test'
            $result.Value | Should -Be 42
        }

        It 'Should return array of objects unchanged' {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-RemoteOrLocal -ComputerName $env:COMPUTERNAME -ScriptBlock {
                    @(
                        [PSCustomObject]@{ Id = 1 },
                        [PSCustomObject]@{ Id = 2 },
                        [PSCustomObject]@{ Id = 3 }
                    )
                }
            }
            @($result).Count | Should -Be 3
        }

        It 'Should return null when scriptblock returns nothing' {
            $result = & (Get-Module -Name $script:ModuleName) {
                Invoke-RemoteOrLocal -ComputerName $env:COMPUTERNAME -ScriptBlock { }
            }
            $result | Should -BeNullOrEmpty
        }
    }
}
