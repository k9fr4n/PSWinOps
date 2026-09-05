#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    function New-Fake4625Event {
        param(
            [datetime]$TimeCreated,
            [object[]]$PropertyValues = @()
        )
        $props = [System.Collections.Generic.List[object]]::new()
        foreach ($v in $PropertyValues) {
            $props.Add([PSCustomObject]@{ Value = $v })
        }
        [PSCustomObject]@{
            Id          = 4625
            TimeCreated = $TimeCreated
            Properties  = $props.ToArray()
        }
    }

    if (-not (Get-Command -Name 'Get-WinEvent' -ErrorAction SilentlyContinue)) {
        function global:Get-WinEvent {
            param($FilterHashtable, $MaxEvents, $ErrorAction, $ComputerName, $Credential, $LogName)
        }
    }
}

Describe -Name 'Get-LogonFailure' -Fixture {

    Context -Name 'Local happy path - decode single 4625 event' -Fixture {

        BeforeAll {
            # 21-slot property array matching the canonical 4625 template indices (0-20)
            $script:evtBadPassword = New-Fake4625Event -TimeCreated (Get-Date '2026-07-01 10:00:00') -PropertyValues @(
                'S-1-5-18', 'SYSTEM', 'NT AUTHORITY', '0x3e7',
                'S-1-0-0', 'jdoe', 'CONTOSO',
                [int64]0xC000006D,
                '%%2313',
                [int64]0xC000006A,
                3,
                'Advapi', 'Negotiate',
                'WORKSTATION01',
                '-', '-', '0',
                '1234', 'C:\Windows\System32\svchost.exe',
                '10.0.0.5', '49700'
            )

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                return @($script:evtBadPassword)
            }
        }

        It -Name 'Should return a PSWinOps.LogonFailure typed object' -Test {
            $result = Get-LogonFailure
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.LogonFailure'
        }

        It -Name 'Should return all required output properties' -Test {
            $result = Get-LogonFailure
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'ComputerName'
            $props | Should -Contain 'EventTime'
            $props | Should -Contain 'TargetUserName'
            $props | Should -Contain 'TargetDomain'
            $props | Should -Contain 'LogonType'
            $props | Should -Contain 'LogonTypeName'
            $props | Should -Contain 'FailureReason'
            $props | Should -Contain 'Status'
            $props | Should -Contain 'SubStatus'
            $props | Should -Contain 'WorkstationName'
            $props | Should -Contain 'SourceIpAddress'
            $props | Should -Contain 'ProcessName'
            $props | Should -Contain 'Timestamp'
        }

        It -Name 'Should set ComputerName to the local machine' -Test {
            $result = Get-LogonFailure
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should decode TargetUserName and TargetDomain' -Test {
            $result = Get-LogonFailure
            $result[0].TargetUserName | Should -Be 'jdoe'
            $result[0].TargetDomain | Should -Be 'CONTOSO'
        }

        It -Name 'Should decode LogonType and LogonTypeName' -Test {
            $result = Get-LogonFailure
            $result[0].LogonType | Should -Be 3
            $result[0].LogonTypeName | Should -Be 'Network'
        }

        It -Name 'Should format Status and SubStatus as 0x-prefixed hex' -Test {
            $result = Get-LogonFailure
            $result[0].Status | Should -Be '0xC000006D'
            $result[0].SubStatus | Should -Be '0xC000006A'
        }

        It -Name 'Should decode FailureReason from SubStatus' -Test {
            $result = Get-LogonFailure
            $result[0].FailureReason | Should -Be 'Bad password'
        }

        It -Name 'Should decode WorkstationName, SourceIpAddress and ProcessName' -Test {
            $result = Get-LogonFailure
            $result[0].WorkstationName | Should -Be 'WORKSTATION01'
            $result[0].SourceIpAddress | Should -Be '10.0.0.5'
            $result[0].ProcessName | Should -Be 'C:\Windows\System32\svchost.exe'
        }

        It -Name 'Should format EventTime and Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $result = Get-LogonFailure
            $result[0].EventTime | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
            $result[0].Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
    }

    Context -Name 'Each unmapped SubStatus falls back to default FailureReason' -Fixture {

        BeforeAll {
            $script:evtUnknownSubStatus = New-Fake4625Event -TimeCreated (Get-Date '2026-07-01 11:00:00') -PropertyValues @(
                'S-1-5-18', 'SYSTEM', 'NT AUTHORITY', '0x3e7',
                'S-1-0-0', 'asmith', 'CONTOSO',
                [int64]0xC000006D,
                '%%2313',
                [int64]0xC0000999,
                99,
                'Advapi', 'Negotiate',
                'WORKSTATION02',
                '-', '-', '0',
                '5678', 'C:\Windows\System32\lsass.exe',
                '10.0.0.6', '49701'
            )

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                return @($script:evtUnknownSubStatus)
            }
        }

        It -Name 'Should fall back to Other (see SubStatus) for an unmapped code' -Test {
            $result = Get-LogonFailure
            $result[0].FailureReason | Should -Be 'Other (see SubStatus)'
        }

        It -Name 'Should fall back to Unknown for an unmapped LogonType' -Test {
            $result = Get-LogonFailure
            $result[0].LogonTypeName | Should -Be 'Unknown'
        }
    }

    Context -Name 'No matching events on the machine' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                throw 'No events were found that match the specified selection criteria.'
            }
        }

        It -Name 'Should emit nothing for that machine without error' -Test {
            $result = @(Get-LogonFailure -ErrorAction Stop)
            $result.Count | Should -Be 0
        }
    }

    Context -Name 'Explicit remote machine' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.LogonFailure'
                    ComputerName    = 'SRV01'
                    EventTime       = '2026-07-01 10:00:00'
                    TargetUserName  = 'jdoe'
                    TargetDomain    = 'CONTOSO'
                    LogonType       = 3
                    LogonTypeName   = 'Network'
                    FailureReason   = 'Bad password'
                    Status          = '0xC000006D'
                    SubStatus       = '0xC000006A'
                    WorkstationName = 'WORKSTATION01'
                    SourceIpAddress = '10.0.0.5'
                    ProcessName     = 'svchost.exe'
                    Timestamp       = '2026-07-05 12:00:00'
                }
            }
        }

        It -Name 'Should dispatch via Invoke-Command for a remote machine' -Test {
            $result = Get-LogonFailure -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should propagate Credential to Invoke-Command' -Test {
            $securePwd = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('DOMAIN\svc', $securePwd)
            Get-LogonFailure -ComputerName 'SRV01' -Credential $cred
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $cred
            }
        }
    }

    Context -Name 'Pipeline of multiple machine names' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.LogonFailure'
                    ComputerName    = $ComputerName
                    EventTime       = '2026-07-01 10:00:00'
                    TargetUserName  = 'jdoe'
                    TargetDomain    = 'CONTOSO'
                    LogonType       = 3
                    LogonTypeName   = 'Network'
                    FailureReason   = 'Bad password'
                    Status          = '0xC000006D'
                    SubStatus       = '0xC000006A'
                    WorkstationName = 'WORKSTATION01'
                    SourceIpAddress = '10.0.0.5'
                    ProcessName     = 'svchost.exe'
                    Timestamp       = '2026-07-05 12:00:00'
                }
            }
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per machine and return a result for each' -Test {
            $result = 'SRV01', 'SRV02' | Get-LogonFailure
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
            ($result | Select-Object -ExpandProperty ComputerName) | Should -Contain 'SRV01'
            ($result | Select-Object -ExpandProperty ComputerName) | Should -Contain 'SRV02'
        }
    }

    Context -Name 'Per-machine failure - continues processing remaining machines' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw 'Simulated access denied on SRV01'
                }
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.LogonFailure'
                    ComputerName    = $ComputerName
                    EventTime       = '2026-07-01 10:00:00'
                    TargetUserName  = 'jdoe'
                    TargetDomain    = 'CONTOSO'
                    LogonType       = 3
                    LogonTypeName   = 'Network'
                    FailureReason   = 'Bad password'
                    Status          = '0xC000006D'
                    SubStatus       = '0xC000006A'
                    WorkstationName = 'WORKSTATION01'
                    SourceIpAddress = '10.0.0.5'
                    ProcessName     = 'svchost.exe'
                    Timestamp       = '2026-07-05 12:00:00'
                }
            }
            $script:perMachineOutput    = 'SRV01', 'SRV02' |
                Get-LogonFailure -ErrorAction Continue 2>&1
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

    Context -Name 'UserName filter' -Fixture {

        BeforeAll {
            $script:evtJdoe = New-Fake4625Event -TimeCreated (Get-Date '2026-07-01 10:00:00') -PropertyValues @(
                'S-1-5-18', 'SYSTEM', 'NT AUTHORITY', '0x3e7',
                'S-1-0-0', 'jdoe', 'CONTOSO',
                [int64]0xC000006D, '%%2313', [int64]0xC000006A, 3,
                'Advapi', 'Negotiate', 'WORKSTATION01', '-', '-', '0',
                '1234', 'svchost.exe', '10.0.0.5', '49700'
            )
            $script:evtAsmith = New-Fake4625Event -TimeCreated (Get-Date '2026-07-01 09:00:00') -PropertyValues @(
                'S-1-5-18', 'SYSTEM', 'NT AUTHORITY', '0x3e7',
                'S-1-0-0', 'asmith', 'CONTOSO',
                [int64]0xC000006D, '%%2313', [int64]0xC0000072, 2,
                'Advapi', 'Negotiate', 'WORKSTATION02', '-', '-', '0',
                '5678', 'winlogon.exe', '10.0.0.6', '49701'
            )

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                return @($script:evtJdoe, $script:evtAsmith)
            }
        }

        It -Name 'Should emit only rows whose decoded TargetUserName matches the filter' -Test {
            $result = @(Get-LogonFailure -UserName 'jdoe')
            $result.Count | Should -Be 1
            $result[0].TargetUserName | Should -Be 'jdoe'
        }

        It -Name 'Should emit all rows when UserName filter is absent' -Test {
            $result = @(Get-LogonFailure)
            $result.Count | Should -Be 2
        }
    }

    Context -Name 'MaxEvents forwarding and row cap' -Fixture {

        BeforeAll {
            $script:manyEvents = 1..5 | ForEach-Object {
                New-Fake4625Event -TimeCreated (Get-Date '2026-07-01 10:00:00').AddMinutes(-$_) -PropertyValues @(
                    'S-1-5-18', 'SYSTEM', 'NT AUTHORITY', '0x3e7',
                    'S-1-0-0', "user$_", 'CONTOSO',
                    [int64]0xC000006D, '%%2313', [int64]0xC000006A, 3,
                    'Advapi', 'Negotiate', 'WORKSTATION01', '-', '-', '0',
                    '1234', 'svchost.exe', '10.0.0.5', '49700'
                )
            }

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                return @($script:manyEvents)
            }
        }

        It -Name 'Should forward MaxEvents to Get-WinEvent' -Test {
            Get-LogonFailure -MaxEvents 3 | Out-Null
            Should -Invoke -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $MaxEvents -eq 3
            }
        }

        It -Name 'Should cap emitted rows to MaxEvents' -Test {
            $result = @(Get-LogonFailure -MaxEvents 3)
            $result.Count | Should -Be 3
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-LogonFailure -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-LogonFailure -ComputerName $null } | Should -Throw
        }

        It -Name 'Should throw when Days is below the valid range' -Test {
            { Get-LogonFailure -Days 0 } | Should -Throw
        }

        It -Name 'Should throw when Days is above the valid range' -Test {
            { Get-LogonFailure -Days 3651 } | Should -Throw
        }

        It -Name 'Should throw when MaxEvents is below the valid range' -Test {
            { Get-LogonFailure -MaxEvents 0 } | Should -Throw
        }

        It -Name 'Should throw when MaxEvents is above the valid range' -Test {
            { Get-LogonFailure -MaxEvents 10001 } | Should -Throw
        }

        It -Name 'Should expose ComputerName with pipeline support by value and by property name' -Test {
            $cmd = Get-Command -Name 'Get-LogonFailure'
            $attr = $cmd.Parameters['ComputerName'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })[0]
            $attr.ValueFromPipeline | Should -Be $true
            $attr.ValueFromPipelineByPropertyName | Should -Be $true
        }

        It -Name 'Should expose ComputerName aliases CN, Name and DNSHostName' -Test {
            $cmd = Get-Command -Name 'Get-LogonFailure'
            $aliases = $cmd.Parameters['ComputerName'].Aliases
            $aliases | Should -Contain 'CN'
            $aliases | Should -Contain 'Name'
            $aliases | Should -Contain 'DNSHostName'
        }
    }
}
