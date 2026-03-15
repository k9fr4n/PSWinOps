#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only -- not a real credential'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force
}

Describe -Name 'Get-Uptime' -Fixture {

    BeforeAll {
        $script:fakeBootTime = (Get-Date).AddDays(-5).AddHours(-3).AddMinutes(-22)
        $script:fakeOsInfo = [PSCustomObject]@{
            LastBootUpTime = $script:fakeBootTime
        }
        $script:fakeCimSession = [PSCustomObject]@{
            Id           = 1
            ComputerName = 'SRV01'
        }
        $script:testCredential = [PSCredential]::new(
            'testuser',
            (ConvertTo-SecureString -String 'TestPass1!' -AsPlainText -Force)
        )
    }

    BeforeEach {
        Mock -CommandName 'Get-CimInstance' -MockWith { return $script:fakeOsInfo }
        Mock -CommandName 'New-CimSession' -MockWith { return $script:fakeCimSession }
        Mock -CommandName 'Remove-CimSession' -MockWith {}
    }

    Context -Name 'Happy path - local machine' -Fixture {
        It -Name 'Should return uptime for the local machine by default' -Test {
            $result = Get-Uptime
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be $env:COMPUTERNAME
        }
        It -Name 'Should not create a CimSession for local queries' -Test {
            Get-Uptime
            Should -Invoke -CommandName 'New-CimSession' -Times 0 -Exactly
        }
        It -Name 'Should call Get-CimInstance exactly once' -Test {
            Get-Uptime
            Should -Invoke -CommandName 'Get-CimInstance' -Times 1 -Exactly
        }
    }

    Context -Name 'Happy path - explicit remote machine' -Fixture {
        It -Name 'Should return uptime for a named remote machine' -Test {
            $result = Get-Uptime -ComputerName 'SRV01'
            $result.ComputerName | Should -Be 'SRV01'
        }
        It -Name 'Should create a CimSession for remote queries' -Test {
            Get-Uptime -ComputerName 'SRV01'
            Should -Invoke -CommandName 'New-CimSession' -Times 1 -Exactly
        }
    }

    Context -Name 'Happy path - with Credential' -Fixture {
        It -Name 'Should accept and use Credential for remote queries' -Test {
            $result = Get-Uptime -ComputerName 'SRV01' -Credential $script:testCredential
            $result.ComputerName | Should -Be 'SRV01'
            Should -Invoke -CommandName 'New-CimSession' -Times 1 -Exactly
        }
    }

    Context -Name 'Pipeline input - multiple machines' -Fixture {
        It -Name 'Should process multiple machines from pipeline' -Test {
            $result = @('SRV01', 'SRV02') | Get-Uptime
            $result | Should -HaveCount 2
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[1].ComputerName | Should -Be 'SRV02'
        }
        It -Name 'Should create a CimSession per remote item' -Test {
            @('SRV01', 'SRV02') | Get-Uptime
            Should -Invoke -CommandName 'New-CimSession' -Times 2 -Exactly
        }
    }

    Context -Name 'Per-machine failure handling' -Fixture {
        It -Name 'Should continue to next machine when one fails' -Test {
            Mock -CommandName 'New-CimSession' -ParameterFilter {
                $ComputerName -eq 'BADMACHINE'
            } -MockWith { throw 'Connection refused' }
            $result = Get-Uptime -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue
            $result | Should -HaveCount 1
            $result[0].ComputerName | Should -Be 'SRV01'
        }
        It -Name 'Should write an error for the failing machine' -Test {
            Mock -CommandName 'New-CimSession' -ParameterFilter {
                $ComputerName -eq 'BADMACHINE'
            } -MockWith { throw 'Connection refused' }
            $result = Get-Uptime -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue -ErrorVariable 'capturedError'
            $result | Should -HaveCount 1
            $capturedError | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Parameter validation' -Fixture {
        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-Uptime -ComputerName '' } | Should -Throw
        }
        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-Uptime -ComputerName $null } | Should -Throw
        }
    }

    Context -Name 'Output type validation' -Fixture {
        It -Name 'Should return all expected properties' -Test {
            $result = Get-Uptime
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'LastBootTime'
            $result.PSObject.Properties.Name | Should -Contain 'Uptime'
            $result.PSObject.Properties.Name | Should -Contain 'UptimeDays'
            $result.PSObject.Properties.Name | Should -Contain 'UptimeDisplay'
            $result.PSObject.Properties.Name | Should -Contain 'Timestamp'
        }
        It -Name 'Should return correct types' -Test {
            $result = Get-Uptime
            $result.ComputerName | Should -BeOfType ([string])
            $result.LastBootTime | Should -BeOfType ([datetime])
            $result.Uptime | Should -BeOfType ([timespan])
            $result.UptimeDays | Should -BeOfType ([double])
            $result.UptimeDisplay | Should -BeOfType ([string])
            $result.Timestamp | Should -BeOfType ([string])
        }
        It -Name 'Should format UptimeDisplay as human-readable' -Test {
            $result = Get-Uptime
            $result.UptimeDisplay | Should -Match '^\d+ days, \d+ hours, \d+ minutes$'
        }
        It -Name 'Should format Timestamp as ISO 8601' -Test {
            $result = Get-Uptime
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context -Name 'CimSession cleanup' -Fixture {
        It -Name 'Should call Remove-CimSession after successful remote query' -Test {
            Get-Uptime -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Remove-CimSession' -Times 1 -Exactly
        }
        It -Name 'Should not call Remove-CimSession for local queries' -Test {
            Get-Uptime
            Should -Invoke -CommandName 'Remove-CimSession' -Times 0 -Exactly
        }
        It -Name 'Should call Remove-CimSession even when Get-CimInstance fails' -Test {
            Mock -CommandName 'Get-CimInstance' -MockWith { throw 'CIM query failed' }
            Get-Uptime -ComputerName 'SRV01' -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Remove-CimSession' -Times 1 -Exactly
        }
    }
}