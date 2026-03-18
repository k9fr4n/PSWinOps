#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only -- not a real credential'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force
}

Describe -Name 'Get-ComputerUptime' -Fixture {

    BeforeAll {
        $script:fakeBootTime = (Get-Date).AddDays(-5).AddHours(-3).AddMinutes(-22)
        $script:fakeOsInfo = [PSCustomObject]@{
            LastBootUpTime = $script:fakeBootTime
        }
    }

    BeforeEach {
        Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -MockWith {
            return $script:fakeOsInfo
        }
    }

    Context -Name 'Happy path - local machine' -Fixture {

        It -Name 'Should return uptime for the local machine by default' -Test {
            $result = Get-ComputerUptime
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should call Get-CimInstance without ComputerName for local' -Test {
            Get-ComputerUptime
            Should -Invoke -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -Times 1 -Exactly -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('ComputerName') -and -not $PSBoundParameters.ContainsKey('CimSession')
            }
        }
    }

    Context -Name 'Happy path - explicit remote machine' -Fixture {

        It -Name 'Should return uptime for a named remote machine' -Test {
            $result = Get-ComputerUptime -ComputerName 'SRV01'
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should call Get-CimInstance with ComputerName for remote' -Test {
            Get-ComputerUptime -ComputerName 'SRV01'
            Should -Invoke -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'SRV01'
            }
        }
    }

    Context -Name 'Credential parameter support' -Fixture {

        It -Name 'Should expose a Credential parameter of type PSCredential' -Test {
            $cmd = Get-Command -Name 'Get-ComputerUptime'
            $cmd.Parameters.Keys | Should -Contain 'Credential'
            $cmd.Parameters['Credential'].ParameterType | Should -Be ([PSCredential])
        }

        It -Name 'Should not require Credential as mandatory' -Test {
            $cmd = Get-Command -Name 'Get-ComputerUptime'
            $cmd.Parameters['Credential'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Be $false
        }
    }

    Context -Name 'Pipeline input - multiple machines' -Fixture {

        It -Name 'Should process multiple machines from pipeline' -Test {
            $result = @('SRV01', 'SRV02') | Get-ComputerUptime
            $result | Should -HaveCount 2
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[1].ComputerName | Should -Be 'SRV02'
        }

        It -Name 'Should call Get-CimInstance once per remote machine' -Test {
            @('SRV01', 'SRV02') | Get-ComputerUptime
            Should -Invoke -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -Times 2 -Exactly
        }
    }

    Context -Name 'Per-machine failure handling' -Fixture {

        It -Name 'Should continue to next machine when one fails' -Test {
            Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -ParameterFilter {
                $ComputerName -eq 'BADMACHINE'
            } -MockWith { throw 'RPC server unavailable' }

            $result = Get-ComputerUptime -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue
            $result | Should -HaveCount 1
            $result[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should write an error for the failing machine' -Test {
            Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -ParameterFilter {
                $ComputerName -eq 'BADMACHINE'
            } -MockWith { throw 'RPC server unavailable' }

            $result = Get-ComputerUptime -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue -ErrorVariable 'capturedError'
            $result | Should -HaveCount 1
            $capturedError | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-ComputerUptime -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-ComputerUptime -ComputerName $null } | Should -Throw
        }
    }

    Context -Name 'Output type validation' -Fixture {

        It -Name 'Should return all expected properties' -Test {
            $result = Get-ComputerUptime
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'LastBootTime'
            $result.PSObject.Properties.Name | Should -Contain 'Uptime'
            $result.PSObject.Properties.Name | Should -Contain 'UptimeDays'
            $result.PSObject.Properties.Name | Should -Contain 'UptimeDisplay'
            $result.PSObject.Properties.Name | Should -Contain 'Timestamp'
        }

        It -Name 'Should return correct types' -Test {
            $result = Get-ComputerUptime
            $result.ComputerName | Should -BeOfType ([string])
            $result.LastBootTime | Should -BeOfType ([datetime])
            $result.Uptime | Should -BeOfType ([timespan])
            $result.UptimeDays | Should -BeOfType ([double])
            $result.UptimeDisplay | Should -BeOfType ([string])
            $result.Timestamp | Should -BeOfType ([string])
        }

        It -Name 'Should format UptimeDisplay as human-readable' -Test {
            $result = Get-ComputerUptime
            $result.UptimeDisplay | Should -Match '^\d+ days, \d+ hours, \d+ minutes$'
        }

        It -Name 'Should format Timestamp as ISO 8601' -Test {
            $result = Get-ComputerUptime
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }
}
