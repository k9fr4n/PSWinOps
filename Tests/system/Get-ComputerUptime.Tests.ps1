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

Describe -Name 'Get-ComputerUptime' -Fixture {

    BeforeAll {
        $script:fakeBootTime = (Get-Date).AddDays(-5).AddHours(-3).AddMinutes(-22)
        $script:fakeOsInfo = [PSCustomObject]@{
            LastBootUpTime = $script:fakeBootTime
        }
        $script:testCredential = [PSCredential]::new(
            'testuser',
            (ConvertTo-SecureString -String 'TestPass1!' -AsPlainText -Force)
        )
    }

    BeforeEach {
        Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -MockWith {
            return $script:fakeOsInfo
        }
        Mock -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -MockWith {
            return $script:fakeOsInfo
        }
    }

    Context -Name 'Happy path - local machine' -Fixture {

        It -Name 'Should return uptime for the local machine by default' -Test {
            $result = Get-ComputerUptime
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should not call Invoke-Command for local queries' -Test {
            Get-ComputerUptime
            Should -Invoke -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -Times 0 -Exactly
        }

        It -Name 'Should call Get-CimInstance exactly once' -Test {
            Get-ComputerUptime
            Should -Invoke -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -Times 1 -Exactly
        }
    }

    Context -Name 'Happy path - explicit remote machine' -Fixture {

        It -Name 'Should return uptime for a named remote machine' -Test {
            $result = Get-ComputerUptime -ComputerName 'SRV01'
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should call Invoke-Command for remote queries' -Test {
            Get-ComputerUptime -ComputerName 'SRV01'
            Should -Invoke -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -Times 1 -Exactly
        }

        It -Name 'Should not call Get-CimInstance locally for remote queries' -Test {
            Get-ComputerUptime -ComputerName 'SRV01'
            Should -Invoke -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -Times 0 -Exactly
        }
    }

    Context -Name 'Happy path - with Credential' -Fixture {

        It -Name 'Should accept and use Credential for remote queries' -Test {
            $result = Get-ComputerUptime -ComputerName 'SRV01' -Credential $script:testCredential
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'SRV01'
            Should -Invoke -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -Times 1 -Exactly
        }
    }

    Context -Name 'Pipeline input - multiple machines' -Fixture {

        It -Name 'Should process multiple machines from pipeline' -Test {
            $result = @('SRV01', 'SRV02') | Get-ComputerUptime
            $result | Should -HaveCount 2
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[1].ComputerName | Should -Be 'SRV02'
        }

        It -Name 'Should call Invoke-Command per remote machine' -Test {
            @('SRV01', 'SRV02') | Get-ComputerUptime
            Should -Invoke -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -Times 2 -Exactly
        }
    }

    Context -Name 'Per-machine failure handling' -Fixture {

        It -Name 'Should continue to next machine when one fails' -Test {
            Mock -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -ParameterFilter {
                $ComputerName -eq 'BADMACHINE'
            } -MockWith { throw 'Connection refused' }
            $result = Get-ComputerUptime -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue
            $result | Should -HaveCount 1
            $result[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should write an error for the failing machine' -Test {
            Mock -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -ParameterFilter {
                $ComputerName -eq 'BADMACHINE'
            } -MockWith { throw 'Connection refused' }
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