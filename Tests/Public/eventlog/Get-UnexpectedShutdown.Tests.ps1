#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    function New-FakeShutdownEvent {
        param(
            [int]$Id,
            [datetime]$TimeCreated,
            [object[]]$PropertyValues = @()
        )
        $props = [System.Collections.Generic.List[object]]::new()
        foreach ($v in $PropertyValues) {
            $props.Add([PSCustomObject]@{ Value = $v })
        }
        [PSCustomObject]@{
            Id          = $Id
            TimeCreated = $TimeCreated
            Properties  = $props.ToArray()
        }
    }
}

Describe -Name 'Get-UnexpectedShutdown' -Fixture {

    Context -Name 'Local happy path - mixed shutdown/restart events' -Fixture {

        BeforeAll {
            $script:evt1074 = New-FakeShutdownEvent -Id 1074 -TimeCreated (Get-Date '2026-07-01 10:00:00') `
                -PropertyValues @('reason1', 'reason2', 'Operating System: Upgrade', 'code1', '1:2', 'code2', 'DOMAIN\admin', 'code3', 'Scheduled maintenance')
            $script:evt6008 = New-FakeShutdownEvent -Id 6008 -TimeCreated (Get-Date '2026-07-01 09:00:00')
            $script:evt6006 = New-FakeShutdownEvent -Id 6006 -TimeCreated (Get-Date '2026-07-01 08:00:00')
            $script:evt1076 = New-FakeShutdownEvent -Id 1076 -TimeCreated (Get-Date '2026-07-01 07:00:00') `
                -PropertyValues @('code0', 'Power outage reported', 'code2', 'code3', 'DOMAIN\jdoe')
            $script:evt41PowerLoss = New-FakeShutdownEvent -Id 41 -TimeCreated (Get-Date '2026-07-01 06:00:00') -PropertyValues @([uint32]0)
            $script:evt41Crash = New-FakeShutdownEvent -Id 41 -TimeCreated (Get-Date '2026-07-01 05:00:00') -PropertyValues @([uint32]0x7E)

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                if ($FilterHashtable.ContainsKey('ProviderName')) {
                    return @($script:evt41PowerLoss, $script:evt41Crash)
                }
                return @($script:evt1074, $script:evt6008, $script:evt6006, $script:evt1076)
            }
        }

        It -Name 'Should return one row per correlated event' -Test {
            $result = Get-UnexpectedShutdown
            $result.Count | Should -Be 6
        }

        It -Name 'Should return a PSWinOps.UnexpectedShutdown typed object' -Test {
            $result = Get-UnexpectedShutdown
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.UnexpectedShutdown'
        }

        It -Name 'Should return all required output properties' -Test {
            $result = Get-UnexpectedShutdown
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'ComputerName'
            $props | Should -Contain 'EventTime'
            $props | Should -Contain 'EventId'
            $props | Should -Contain 'ShutdownType'
            $props | Should -Contain 'IsExpected'
            $props | Should -Contain 'Cause'
            $props | Should -Contain 'ReasonCode'
            $props | Should -Contain 'Initiator'
            $props | Should -Contain 'Comment'
            $props | Should -Contain 'Timestamp'
        }

        It -Name 'Should set ComputerName to the local machine' -Test {
            $result = Get-UnexpectedShutdown
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should format EventTime and Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $result = Get-UnexpectedShutdown
            $result[0].EventTime | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
            $result[0].Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }

        It -Name 'Should sort events newest first' -Test {
            $result = Get-UnexpectedShutdown
            $sorted = $result.EventTime | Sort-Object -Descending
            [string[]]$result.EventTime | Should -Be ([string[]]$sorted)
        }

        It -Name 'Should map 1074 to ShutdownType Planned and IsExpected true' -Test {
            $result = Get-UnexpectedShutdown
            $row = $result | Where-Object { $_.EventId -eq 1074 }
            $row.ShutdownType | Should -Be 'Planned'
            $row.IsExpected | Should -Be $true
        }

        It -Name 'Should populate Cause, ReasonCode, Initiator and Comment from 1074 properties' -Test {
            $result = Get-UnexpectedShutdown
            $row = $result | Where-Object { $_.EventId -eq 1074 }
            $row.Cause | Should -Be 'Operating System: Upgrade'
            $row.ReasonCode | Should -Be '1:2'
            $row.Initiator | Should -Be 'DOMAIN\admin'
            $row.Comment | Should -Be 'Scheduled maintenance'
        }

        It -Name 'Should map 6008 to ShutdownType Unexpected and IsExpected false' -Test {
            $result = Get-UnexpectedShutdown
            $row = $result | Where-Object { $_.EventId -eq 6008 }
            $row.ShutdownType | Should -Be 'Unexpected'
            $row.IsExpected | Should -Be $false
        }

        It -Name 'Should map 6006 to ShutdownType Clean and IsExpected true' -Test {
            $result = Get-UnexpectedShutdown
            $row = $result | Where-Object { $_.EventId -eq 6006 }
            $row.ShutdownType | Should -Be 'Clean'
            $row.IsExpected | Should -Be $true
        }

        It -Name 'Should map 1076 to ShutdownType ReasonSupplied and IsExpected false' -Test {
            $result = Get-UnexpectedShutdown
            $row = $result | Where-Object { $_.EventId -eq 1076 }
            $row.ShutdownType | Should -Be 'ReasonSupplied'
            $row.IsExpected | Should -Be $false
        }

        It -Name 'Should populate Cause and Initiator from 1076 properties' -Test {
            $result = Get-UnexpectedShutdown
            $row = $result | Where-Object { $_.EventId -eq 1076 }
            $row.Cause | Should -Be 'Power outage reported'
            $row.Initiator | Should -Be 'DOMAIN\jdoe'
        }

        It -Name 'Should map Kernel-Power 41 with BugcheckCode 0 to PowerLoss and IsExpected false' -Test {
            $result = Get-UnexpectedShutdown
            $row = $result | Where-Object { $_.EventId -eq 41 -and $_.EventTime -eq '2026-07-01 06:00:00' }
            $row.ShutdownType | Should -Be 'PowerLoss'
            $row.IsExpected | Should -Be $false
        }

        It -Name 'Should map Kernel-Power 41 with non-zero BugcheckCode to Crash and set Cause' -Test {
            $result = Get-UnexpectedShutdown
            $row = $result | Where-Object { $_.EventId -eq 41 -and $_.EventTime -eq '2026-07-01 05:00:00' }
            $row.ShutdownType | Should -Be 'Crash'
            $row.IsExpected | Should -Be $false
            $row.Cause | Should -Match 'BugcheckCode'
        }
    }

    Context -Name 'No matching events on the machine' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                return $null
            }
        }

        It -Name 'Should emit nothing for that machine without error' -Test {
            $result = @(Get-UnexpectedShutdown -ErrorAction Stop)
            $result.Count | Should -Be 0
        }
    }

    Context -Name 'Explicit remote machine' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.UnexpectedShutdown'
                    ComputerName = 'SRV01'
                    EventTime    = '2026-07-01 10:00:00'
                    EventId      = 1074
                    ShutdownType = 'Planned'
                    IsExpected   = $true
                    Cause        = 'Operating System: Upgrade'
                    ReasonCode   = '1:2'
                    Initiator    = 'DOMAIN\admin'
                    Comment      = 'Scheduled maintenance'
                    Timestamp    = '2026-07-05 12:00:00'
                }
            }
        }

        It -Name 'Should dispatch via Invoke-Command for a remote machine' -Test {
            $result = Get-UnexpectedShutdown -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should propagate Credential to Invoke-Command' -Test {
            $securePwd = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('DOMAIN\svc', $securePwd)
            Get-UnexpectedShutdown -ComputerName 'SRV01' -Credential $cred
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $cred
            }
        }
    }

    Context -Name 'Pipeline of multiple machine names' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.UnexpectedShutdown'
                    ComputerName = $ComputerName
                    EventTime    = '2026-07-01 10:00:00'
                    EventId      = 6006
                    ShutdownType = 'Clean'
                    IsExpected   = $true
                    Cause        = ''
                    ReasonCode   = ''
                    Initiator    = ''
                    Comment      = ''
                    Timestamp    = '2026-07-05 12:00:00'
                }
            }
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per machine and return a result for each' -Test {
            $result = 'SRV01', 'SRV02' | Get-UnexpectedShutdown
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
            ($result | Select-Object -ExpandProperty ComputerName) | Should -Contain 'SRV01'
            ($result | Select-Object -ExpandProperty ComputerName) | Should -Contain 'SRV02'
        }
    }

    Context -Name 'Per-machine failure - continues processing remaining machines' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw 'Simulated WinRM failure on SRV01'
                }
                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.UnexpectedShutdown'
                    ComputerName = $ComputerName
                    EventTime    = '2026-07-01 10:00:00'
                    EventId      = 6006
                    ShutdownType = 'Clean'
                    IsExpected   = $true
                    Cause        = ''
                    ReasonCode   = ''
                    Initiator    = ''
                    Comment      = ''
                    Timestamp    = '2026-07-05 12:00:00'
                }
            }
            $script:perMachineOutput    = 'SRV01', 'SRV02' |
                Get-UnexpectedShutdown -ErrorAction Continue 2>&1
            $script:perMachineErrors    = @($script:perMachineOutput | Where-Object {
                $_ -is [System.Management.Automation.ErrorRecord]
            })
            $script:perMachineSuccesses = @($script:perMachineOutput | Where-Object {
                $_ -isnot [System.Management.Automation.ErrorRecord]
            })
        }

        It -Name 'Should write an error for the failing machine' -Test {
            $script:perMachineErrors.Count | Should -BeGreaterThan 0
        }

        It -Name 'Should still return a result for the succeeding machine' -Test {
            $script:perMachineSuccesses.Count | Should -Be 1
            $script:perMachineSuccesses[0].ComputerName | Should -Be 'SRV02'
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-UnexpectedShutdown -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-UnexpectedShutdown -ComputerName $null } | Should -Throw
        }

        It -Name 'Should throw when MaxEvents is below the valid range' -Test {
            { Get-UnexpectedShutdown -MaxEvents 0 } | Should -Throw
        }

        It -Name 'Should throw when MaxEvents is above the valid range' -Test {
            { Get-UnexpectedShutdown -MaxEvents 10001 } | Should -Throw
        }

        It -Name 'Should throw when Days is below the valid range' -Test {
            { Get-UnexpectedShutdown -Days 0 } | Should -Throw
        }

        It -Name 'Should throw when Days is above the valid range' -Test {
            { Get-UnexpectedShutdown -Days 3651 } | Should -Throw
        }

        It -Name 'Should expose ComputerName with pipeline support by value and by property name' -Test {
            $cmd = Get-Command -Name 'Get-UnexpectedShutdown'
            $attr = $cmd.Parameters['ComputerName'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })[0]
            $attr.ValueFromPipeline | Should -Be $true
            $attr.ValueFromPipelineByPropertyName | Should -Be $true
        }

        It -Name 'Should expose ComputerName aliases CN, Name and DNSHostName' -Test {
            $cmd = Get-Command -Name 'Get-UnexpectedShutdown'
            $aliases = $cmd.Parameters['ComputerName'].Aliases
            $aliases | Should -Contain 'CN'
            $aliases | Should -Contain 'Name'
            $aliases | Should -Contain 'DNSHostName'
        }
    }
}
