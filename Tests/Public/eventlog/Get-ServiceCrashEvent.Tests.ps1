#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    function New-FakeCrashEvent {
        param(
            [int]$Id,
            [datetime]$TimeCreated,
            [object[]]$PropertyValues = @(),
            [string]$Message = 'Simulated crash event message'
        )
        $props = [System.Collections.Generic.List[object]]::new()
        foreach ($v in $PropertyValues) {
            $props.Add([PSCustomObject]@{ Value = $v })
        }
        [PSCustomObject]@{
            Id          = $Id
            TimeCreated = $TimeCreated
            Properties  = $props.ToArray()
            Message     = $Message
        }
    }

    function New-FakeServiceCimEntry {
        param(
            [string]$Name,
            [string]$DisplayName
        )
        [PSCustomObject]@{
            Name        = $Name
            DisplayName = $DisplayName
        }
    }
}

Describe -Name 'Get-ServiceCrashEvent' -Fixture {

    Context -Name 'Local happy path - mixed crash events' -Fixture {

        BeforeAll {
            $script:evt7024 = New-FakeCrashEvent -Id 7024 -TimeCreated (Get-Date '2026-07-01 10:00:00') `
                -PropertyValues @('Print Spooler', 3489660929)
            $script:evt7031 = New-FakeCrashEvent -Id 7031 -TimeCreated (Get-Date '2026-07-01 09:00:00') `
                -PropertyValues @('Print Spooler', 1, 60, 1, '')
            $script:evt7034 = New-FakeCrashEvent -Id 7034 -TimeCreated (Get-Date '2026-07-01 08:00:00') `
                -PropertyValues @('World Wide Web Publishing Service', 1)
            $script:evt7000 = New-FakeCrashEvent -Id 7000 -TimeCreated (Get-Date '2026-07-01 07:00:00') `
                -PropertyValues @('World Wide Web Publishing Service')

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                return @($script:evt7024, $script:evt7031, $script:evt7034, $script:evt7000)
            }
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                throw 'FailureActions not configured'
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return @(
                    (New-FakeServiceCimEntry -Name 'Spooler' -DisplayName 'Print Spooler'),
                    (New-FakeServiceCimEntry -Name 'W3SVC' -DisplayName 'World Wide Web Publishing Service')
                )
            }
        }

        It -Name 'Should return one row per crash event' -Test {
            $result = Get-ServiceCrashEvent
            $result.Count | Should -Be 4
        }

        It -Name 'Should return a PSWinOps.ServiceCrashEvent typed object' -Test {
            $result = Get-ServiceCrashEvent
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ServiceCrashEvent'
        }

        It -Name 'Should return all required output properties' -Test {
            $result = Get-ServiceCrashEvent
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'ComputerName'
            $props | Should -Contain 'EventTime'
            $props | Should -Contain 'EventId'
            $props | Should -Contain 'ServiceName'
            $props | Should -Contain 'ServiceDisplayName'
            $props | Should -Contain 'ExitCode'
            $props | Should -Contain 'CrashCount'
            $props | Should -Contain 'RecoveryAction'
            $props | Should -Contain 'Message'
            $props | Should -Contain 'Timestamp'
        }

        It -Name 'Should set ComputerName to the local machine' -Test {
            $result = Get-ServiceCrashEvent
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should format EventTime and Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $result = Get-ServiceCrashEvent
            $result[0].EventTime | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
            $result[0].Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }

        It -Name 'Should sort events newest first' -Test {
            $result = Get-ServiceCrashEvent
            $sorted = $result.EventTime | Sort-Object -Descending
            [string[]]$result.EventTime | Should -Be ([string[]]$sorted)
        }

        It -Name 'Should resolve ServiceName from DisplayName via Get-CimInstance' -Test {
            $result = Get-ServiceCrashEvent
            $row = $result | Where-Object { $_.EventId -eq 7024 }
            $row.ServiceName | Should -Be 'Spooler'
            $row.ServiceDisplayName | Should -Be 'Print Spooler'
        }

        It -Name 'Should extract ExitCode from a 7024 event' -Test {
            $result = Get-ServiceCrashEvent
            $row = $result | Where-Object { $_.EventId -eq 7024 }
            $row.ExitCode | Should -Be '3489660929'
        }

        It -Name 'Should leave ExitCode empty for a 7000 event with no error code property' -Test {
            $result = Get-ServiceCrashEvent
            $row = $result | Where-Object { $_.EventId -eq 7000 }
            $row.ExitCode | Should -Be ''
        }

        It -Name 'Should derive RecoveryAction from the 7031 embedded action code as a fallback' -Test {
            $result = Get-ServiceCrashEvent
            $row = $result | Where-Object { $_.EventId -eq 7031 }
            $row.RecoveryAction | Should -Be 'Restart'
        }
    }

    Context -Name 'No matching events on the machine' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                return $null
            }
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                throw 'FailureActions not configured'
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
        }

        It -Name 'Should emit nothing for that machine without error' -Test {
            $result = @(Get-ServiceCrashEvent -ErrorAction Stop)
            $result.Count | Should -Be 0
        }
    }

    Context -Name 'Explicit remote machine' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.ServiceCrashEvent'
                    ComputerName       = 'SRV01'
                    EventTime          = '2026-07-01 10:00:00'
                    EventId            = 7031
                    ServiceName        = 'Spooler'
                    ServiceDisplayName = 'Print Spooler'
                    ExitCode           = ''
                    CrashCount         = 1
                    RecoveryAction     = 'Restart'
                    Message            = 'Simulated crash event message'
                    Timestamp          = '2026-07-05 12:00:00'
                }
            }
        }

        It -Name 'Should dispatch via Invoke-Command for a remote machine' -Test {
            $result = Get-ServiceCrashEvent -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should propagate Credential to Invoke-Command' -Test {
            $securePwd = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('DOMAIN\svc', $securePwd)
            Get-ServiceCrashEvent -ComputerName 'SRV01' -Credential $cred
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $cred
            }
        }
    }

    Context -Name 'Pipeline of multiple machine names' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.ServiceCrashEvent'
                    ComputerName       = $ComputerName
                    EventTime          = '2026-07-01 10:00:00'
                    EventId            = 7034
                    ServiceName        = 'W3SVC'
                    ServiceDisplayName = 'World Wide Web Publishing Service'
                    ExitCode           = ''
                    CrashCount         = 1
                    RecoveryAction     = ''
                    Message            = 'Simulated crash event message'
                    Timestamp          = '2026-07-05 12:00:00'
                }
            }
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per machine and return a result for each' -Test {
            $result = 'SRV01', 'SRV02' | Get-ServiceCrashEvent
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
                    PSTypeName         = 'PSWinOps.ServiceCrashEvent'
                    ComputerName       = $ComputerName
                    EventTime          = '2026-07-01 10:00:00'
                    EventId            = 7034
                    ServiceName        = 'W3SVC'
                    ServiceDisplayName = 'World Wide Web Publishing Service'
                    ExitCode           = ''
                    CrashCount         = 1
                    RecoveryAction     = ''
                    Message            = 'Simulated crash event message'
                    Timestamp          = '2026-07-05 12:00:00'
                }
            }
            $script:perMachineOutput    = 'SRV01', 'SRV02' |
                Get-ServiceCrashEvent -ErrorAction Continue 2>&1
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

    Context -Name '-ServiceName post-read filter narrows rows' -Fixture {

        BeforeAll {
            $script:evtSpooler = New-FakeCrashEvent -Id 7031 -TimeCreated (Get-Date '2026-07-01 10:00:00') `
                -PropertyValues @('Print Spooler', 1, 60, 1, '')
            $script:evtW3svc = New-FakeCrashEvent -Id 7034 -TimeCreated (Get-Date '2026-07-01 09:00:00') `
                -PropertyValues @('World Wide Web Publishing Service', 1)

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                return @($script:evtSpooler, $script:evtW3svc)
            }
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                throw 'FailureActions not configured'
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return @(
                    (New-FakeServiceCimEntry -Name 'Spooler' -DisplayName 'Print Spooler'),
                    (New-FakeServiceCimEntry -Name 'W3SVC' -DisplayName 'World Wide Web Publishing Service')
                )
            }
        }

        It -Name 'Should only return rows matching the requested ServiceName' -Test {
            $result = @(Get-ServiceCrashEvent -ServiceName 'Spooler')
            $result.Count | Should -Be 1
            $result[0].ServiceName | Should -Be 'Spooler'
        }

        It -Name 'Should be case-insensitive when matching ServiceName' -Test {
            $result = @(Get-ServiceCrashEvent -ServiceName 'SPOOLER')
            $result.Count | Should -Be 1
            $result[0].ServiceName | Should -Be 'Spooler'
        }

        It -Name 'Should return all rows when ServiceName is not specified' -Test {
            $result = @(Get-ServiceCrashEvent)
            $result.Count | Should -Be 2
        }
    }

    Context -Name 'CrashCount aggregated per ServiceName over the window' -Fixture {

        BeforeAll {
            $script:evtSpooler1 = New-FakeCrashEvent -Id 7031 -TimeCreated (Get-Date '2026-07-01 12:00:00') `
                -PropertyValues @('Print Spooler', 3, 60, 1, '')
            $script:evtSpooler2 = New-FakeCrashEvent -Id 7034 -TimeCreated (Get-Date '2026-07-01 11:00:00') `
                -PropertyValues @('Print Spooler', 2)
            $script:evtSpooler3 = New-FakeCrashEvent -Id 7034 -TimeCreated (Get-Date '2026-07-01 10:00:00') `
                -PropertyValues @('Print Spooler', 1)
            $script:evtW3svc = New-FakeCrashEvent -Id 7034 -TimeCreated (Get-Date '2026-07-01 09:00:00') `
                -PropertyValues @('World Wide Web Publishing Service', 1)

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                return @($script:evtSpooler1, $script:evtSpooler2, $script:evtSpooler3, $script:evtW3svc)
            }
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'PSWinOps' -MockWith {
                throw 'FailureActions not configured'
            }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return @(
                    (New-FakeServiceCimEntry -Name 'Spooler' -DisplayName 'Print Spooler'),
                    (New-FakeServiceCimEntry -Name 'W3SVC' -DisplayName 'World Wide Web Publishing Service')
                )
            }
        }

        It -Name 'Should stamp the window-level crash count on every row for that service' -Test {
            $result = Get-ServiceCrashEvent
            $spoolerRows = @($result | Where-Object { $_.ServiceName -eq 'Spooler' })
            $spoolerRows.Count | Should -Be 3
            foreach ($row in $spoolerRows) {
                $row.CrashCount | Should -Be 3
            }
        }

        It -Name 'Should compute distinct CrashCount tallies per ServiceName' -Test {
            $result = Get-ServiceCrashEvent
            $w3svcRow = $result | Where-Object { $_.ServiceName -eq 'W3SVC' }
            $w3svcRow.CrashCount | Should -Be 1
        }

        It -Name 'Should keep the window-level tally unchanged when -ServiceName narrows the emitted rows' -Test {
            $result = @(Get-ServiceCrashEvent -ServiceName 'Spooler')
            $result.Count | Should -Be 3
            foreach ($row in $result) {
                $row.CrashCount | Should -Be 3
            }
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-ServiceCrashEvent -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-ServiceCrashEvent -ComputerName $null } | Should -Throw
        }

        It -Name 'Should throw when Days is below the valid range' -Test {
            { Get-ServiceCrashEvent -Days 0 } | Should -Throw
        }

        It -Name 'Should throw when Days is above the valid range' -Test {
            { Get-ServiceCrashEvent -Days 3651 } | Should -Throw
        }

        It -Name 'Should throw when MaxEvents is below the valid range' -Test {
            { Get-ServiceCrashEvent -MaxEvents 0 } | Should -Throw
        }

        It -Name 'Should throw when MaxEvents is above the valid range' -Test {
            { Get-ServiceCrashEvent -MaxEvents 10001 } | Should -Throw
        }

        It -Name 'Should expose ComputerName with pipeline support by value and by property name' -Test {
            $cmd = Get-Command -Name 'Get-ServiceCrashEvent'
            $attr = $cmd.Parameters['ComputerName'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })[0]
            $attr.ValueFromPipeline | Should -Be $true
            $attr.ValueFromPipelineByPropertyName | Should -Be $true
        }

        It -Name 'Should expose ComputerName aliases CN, Name and DNSHostName' -Test {
            $cmd = Get-Command -Name 'Get-ServiceCrashEvent'
            $aliases = $cmd.Parameters['ComputerName'].Aliases
            $aliases | Should -Contain 'CN'
            $aliases | Should -Contain 'Name'
            $aliases | Should -Contain 'DNSHostName'
        }
    }
}
