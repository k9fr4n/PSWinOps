#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText',
    '',
    Justification = 'Test fixture only -- not a real credential'
)]
param()

BeforeAll -Scriptblock {
    $script:functionPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Public\sessions\Disconnect-RdpSession.ps1'
    . $script:functionPath
}

Describe -Name 'Disconnect-RdpSession' -Fixture {

    BeforeAll -Scriptblock {
        # Default mock: tsdiscon.exe exists
        Mock -CommandName 'Get-Command' -MockWith {
            return [PSCustomObject]@{
                Name        = 'tsdiscon.exe'
                CommandType = 'Application'
                Source      = 'C:\Windows\System32\tsdiscon.exe'
            }
        } -ParameterFilter { $Name -eq 'tsdiscon.exe' }

        # Default mock: Invoke-Command returns exit code 0 (success)
        Mock -CommandName 'Invoke-Command' -MockWith { return 0 }
    }

    Context -Name 'When disconnecting a local session' -Fixture {

        It -Name 'Should return a PSCustomObject with all expected properties' -Test {
            $result = Disconnect-RdpSession -SessionID 3 -Confirm:$false
            $result | Should -BeOfType -ExpectedType ([PSCustomObject])
            $result.PSObject.Properties.Name | Should -Contain -ExpectedValue 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain -ExpectedValue 'SessionID'
            $result.PSObject.Properties.Name | Should -Contain -ExpectedValue 'Action'
            $result.PSObject.Properties.Name | Should -Contain -ExpectedValue 'Success'
            $result.PSObject.Properties.Name | Should -Contain -ExpectedValue 'Timestamp'
        }

        It -Name 'Should return Success true when tsdiscon exits with code 0' -Test {
            $result = Disconnect-RdpSession -SessionID 3 -Confirm:$false
            $result.Success | Should -BeTrue
            $result.Action | Should -Be -ExpectedValue 'Disconnect'
            $result.SessionID | Should -Be -ExpectedValue 3
        }

        It -Name 'Should default ComputerName to the local machine name' -Test {
            $result = Disconnect-RdpSession -SessionID 3 -Confirm:$false
            $result.ComputerName | Should -Be -ExpectedValue $env:COMPUTERNAME
        }

        It -Name 'Should invoke Invoke-Command without ComputerName for local sessions' -Test {
            Disconnect-RdpSession -SessionID 3 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -Times 1 -Exactly -ParameterFilter {
                $null -eq $ComputerName
            }
        }
    }

    Context -Name 'When disconnecting a remote session without credentials' -Fixture {

        It -Name 'Should return Success true with the remote ComputerName' -Test {
            $result = Disconnect-RdpSession -ComputerName 'SRV-REMOTE-01' -SessionID 5 -Confirm:$false
            $result.Success | Should -BeTrue
            $result.ComputerName | Should -Be -ExpectedValue 'SRV-REMOTE-01'
            $result.SessionID | Should -Be -ExpectedValue 5
        }

        It -Name 'Should pass ComputerName to Invoke-Command for remote sessions' -Test {
            Disconnect-RdpSession -ComputerName 'SRV-REMOTE-01' -SessionID 5 -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'SRV-REMOTE-01'
            }
        }
    }

    Context -Name 'When credentials are provided for a remote session' -Fixture {

        BeforeAll -Scriptblock {
            $script:testCredential = [PSCredential]::new(
                'DOMAIN\testuser',
                (ConvertTo-SecureString -String 'FakeP@ss1' -AsPlainText -Force)
            )
        }

        It -Name 'Should pass Credential to Invoke-Command' -Test {
            Disconnect-RdpSession -ComputerName 'SRV-REMOTE-01' -SessionID 3 -Credential $script:testCredential -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential -and $ComputerName -eq 'SRV-REMOTE-01'
            }
        }

        It -Name 'Should return a valid result object with credentials' -Test {
            $result = Disconnect-RdpSession -ComputerName 'SRV-REMOTE-01' -SessionID 3 -Credential $script:testCredential -Confirm:$false
            $result.Success | Should -BeTrue
            $result.ComputerName | Should -Be -ExpectedValue 'SRV-REMOTE-01'
        }
    }

    Context -Name 'When multiple sessions are provided via pipeline' -Fixture {

        It -Name 'Should process each session and return multiple results' -Test {
            $script:pipelineInput = @(
                [PSCustomObject]@{ ComputerName = 'SRV01'; SessionID = 3 }
                [PSCustomObject]@{ ComputerName = 'SRV01'; SessionID = 7 }
            )
            $results = $script:pipelineInput | Disconnect-RdpSession -Confirm:$false
            $results.Count | Should -Be -ExpectedValue 2
            $results[0].SessionID | Should -Be -ExpectedValue 3
            $results[1].SessionID | Should -Be -ExpectedValue 7
        }

        It -Name 'Should call Invoke-Command once per piped session' -Test {
            $script:pipelineInput = @(
                [PSCustomObject]@{ ComputerName = 'SRV01'; SessionID = 3 }
                [PSCustomObject]@{ ComputerName = 'SRV01'; SessionID = 7 }
            )
            $script:pipelineInput | Disconnect-RdpSession -Confirm:$false
            Should -Invoke -CommandName 'Invoke-Command' -Times 2 -Exactly
        }
    }

    Context -Name 'When multiple SessionIDs are passed as an array parameter' -Fixture {

        It -Name 'Should disconnect each session ID individually' -Test {
            $results = Disconnect-RdpSession -ComputerName 'SRV01' -SessionID 2, 4, 6 -Confirm:$false
            $results.Count | Should -Be -ExpectedValue 3
            Should -Invoke -CommandName 'Invoke-Command' -Times 3 -Exactly
        }
    }

    Context -Name 'When tsdiscon.exe returns a non-zero exit code' -Fixture {

        BeforeAll -Scriptblock {
            Mock -CommandName 'Invoke-Command' -MockWith { return 1 }
        }

        It -Name 'Should return Success as false' -Test {
            $result = Disconnect-RdpSession -SessionID 3 -Confirm:$false
            $result.Success | Should -BeFalse
        }

        It -Name 'Should still return a complete result object' -Test {
            $result = Disconnect-RdpSession -SessionID 3 -Confirm:$false
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be -ExpectedValue 'Disconnect'
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'When Invoke-Command returns null exit code' -Fixture {

        BeforeAll -Scriptblock {
            Mock -CommandName 'Invoke-Command' -MockWith { return $null }
        }

        It -Name 'Should return Success as false when exit code is null' -Test {
            $result = Disconnect-RdpSession -SessionID 3 -Confirm:$false
            $result.Success | Should -BeFalse
        }
    }

    Context -Name 'When tsdiscon.exe is not found on the system' -Fixture {

        BeforeAll -Scriptblock {
            Mock -CommandName 'Get-Command' -MockWith {
                return $null
            } -ParameterFilter { $Name -eq 'tsdiscon.exe' }
        }

        It -Name 'Should throw a terminating error mentioning tsdiscon' -Test {
            { Disconnect-RdpSession -SessionID 3 -Confirm:$false } | Should -Throw -ExpectedMessage '*tsdiscon.exe*'
        }

        It -Name 'Should not attempt to invoke any disconnect command' -Test {
            { Disconnect-RdpSession -SessionID 3 -Confirm:$false } | Should -Throw
            Should -Invoke -CommandName 'Invoke-Command' -Times 0 -Exactly
        }
    }

    Context -Name 'When WhatIf is specified' -Fixture {

        It -Name 'Should not execute any disconnect command' -Test {
            Disconnect-RdpSession -ComputerName 'SRV01' -SessionID 3 -WhatIf
            Should -Invoke -CommandName 'Invoke-Command' -Times 0 -Exactly
        }

        It -Name 'Should not return any output' -Test {
            $result = Disconnect-RdpSession -ComputerName 'SRV01' -SessionID 3 -WhatIf
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When a WinRM remoting error occurs' -Fixture {

        BeforeAll -Scriptblock {
            Mock -CommandName 'Invoke-Command' -MockWith {
                throw [System.Management.Automation.Remoting.PSRemotingTransportException]::new(
                    'WinRM cannot complete the operation.'
                )
            }
        }

        It -Name 'Should return Success as false without terminating the pipeline' -Test {
            $result = Disconnect-RdpSession -ComputerName 'SRV-UNREACHABLE' -SessionID 3 -Confirm:$false -ErrorAction SilentlyContinue
            $result.Success | Should -BeFalse
            $result.ComputerName | Should -Be -ExpectedValue 'SRV-UNREACHABLE'
        }

        It -Name 'Should write a non-terminating error to the error stream' -Test {
            $script:disconnectErrors = $null
            Disconnect-RdpSession -ComputerName 'SRV-UNREACHABLE' -SessionID 3 -Confirm:$false -ErrorVariable script:disconnectErrors -ErrorAction SilentlyContinue
            $script:disconnectErrors | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'When a generic error occurs during disconnect' -Fixture {

        BeforeAll -Scriptblock {
            Mock -CommandName 'Invoke-Command' -MockWith {
                throw [System.InvalidOperationException]::new('Unexpected failure')
            }
        }

        It -Name 'Should return Success as false and continue processing' -Test {
            $result = Disconnect-RdpSession -SessionID 3 -Confirm:$false -ErrorAction SilentlyContinue
            $result.Success | Should -BeFalse
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should reject an empty ComputerName' -Test {
            { Disconnect-RdpSession -ComputerName '' -SessionID 3 -Confirm:$false } | Should -Throw
        }

        It -Name 'Should reject a SessionID outside valid range' -Test {
            { Disconnect-RdpSession -SessionID -1 -Confirm:$false } | Should -Throw
            { Disconnect-RdpSession -SessionID 65537 -Confirm:$false } | Should -Throw
        }

        It -Name 'Should require SessionID as mandatory' -Test {
            { Disconnect-RdpSession -ComputerName 'SRV01' -Confirm:$false } | Should -Throw
        }
    }
}
