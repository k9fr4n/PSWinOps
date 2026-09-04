#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    function New-MockProcessEvent {
        param(
            [Parameter(Mandatory = $true)]
            [int]$EventId,
            [Parameter(Mandatory = $true)]
            [datetime]$TimeCreated,
            [Parameter(Mandatory = $true)]
            [string]$XmlContent,
            [string]$Message = 'Simulated process event'
        )

        $mockEvent = [PSCustomObject]@{
            Id          = $EventId
            TimeCreated = $TimeCreated
            Message     = $Message
        }

        $mockEvent | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
            return $XmlContent
        }.GetNewClosure() -Force

        return $mockEvent
    }

    function New-ApplicationErrorXml {
        param(
            [string]$AppName = 'app.exe',
            [string]$AppPath = 'C:\Apps\app.exe',
            [string]$ModuleName = 'fault.dll',
            [string]$ExceptionCode = 'c0000005',
            [string]$FaultingOffset = '0000000000001234',
            [string]$ReportId = 'report-001',
            [string]$UserName = 'CONTOSO\svc-app'
        )

        @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <EventData>
    <Data Name="AppName">$AppName</Data>
    <Data Name="AppPath">$AppPath</Data>
    <Data Name="ModuleName">$ModuleName</Data>
    <Data Name="ExceptionCode">$ExceptionCode</Data>
    <Data Name="FaultingOffset">$FaultingOffset</Data>
    <Data Name="IntegratorReportId">$ReportId</Data>
    <Data Name="UserName">$UserName</Data>
  </EventData>
</Event>
"@
    }

    function New-WerXml {
        param(
            [string]$ReportId = 'report-001',
            [string]$AppName = 'app.exe'
        )

        @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <EventData>
    <Data Name="ReportId">$ReportId</Data>
    <Data Name="AppName">$AppName</Data>
  </EventData>
</Event>
"@
    }

    function New-ApplicationHangXml {
        param(
            [string]$AppName = 'hung.exe',
            [string]$AppPath = 'C:\Apps\hung.exe'
        )

        @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <EventData>
    <Data Name="AppName">$AppName</Data>
    <Data Name="AppPath">$AppPath</Data>
    <Data Name="HangType">TopLevelWindow</Data>
  </EventData>
</Event>
"@
    }
}

Describe -Name 'Get-ProcessCrashEvent' -Fixture {
    Context -Name 'Local happy path and XML parsing' -Fixture {
        BeforeAll {
            $script:crashNewest = New-MockProcessEvent -EventId 1000 -TimeCreated (Get-Date '2026-09-04 10:00:00') `
                -XmlContent (New-ApplicationErrorXml -ReportId 'report-001')
            $script:crashOlder = New-MockProcessEvent -EventId 1000 -TimeCreated (Get-Date '2026-09-03 10:00:00') `
                -XmlContent (New-ApplicationErrorXml -ReportId 'report-002')
            $script:otherCrash = New-MockProcessEvent -EventId 1000 -TimeCreated (Get-Date '2026-09-02 10:00:00') `
                -XmlContent (New-ApplicationErrorXml -AppName 'other.exe' -AppPath 'C:\Apps\other.exe' -ReportId 'report-003')
            $script:wer = New-MockProcessEvent -EventId 1001 -TimeCreated (Get-Date '2026-09-04 10:01:00') `
                -XmlContent (New-WerXml -ReportId 'report-001')

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:wer, $script:crashOlder, $script:otherCrash, $script:crashNewest)
            }
        }

        It -Name 'Should return only crash rows and ignore WER rows' -Test {
            $result = @(Get-ProcessCrashEvent)
            $result.Count | Should -Be 3
            $result.EventType | Should -Not -Contain 'WER'
        }

        It -Name 'Should return a typed object with all required properties' -Test {
            $result = @(Get-ProcessCrashEvent)
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ProcessCrashEvent'
            foreach ($property in @(
                'ComputerName', 'EventTime', 'EventId', 'EventType', 'ProcessName',
                'ProcessPath', 'FaultingModule', 'ExceptionCode', 'FaultingOffset',
                'ReportId', 'UserName', 'CrashCount', 'Message', 'Timestamp'
            )) {
                $result[0].PSObject.Properties.Name | Should -Contain $property
            }
        }

        It -Name 'Should parse named XML fields' -Test {
            $result = @(Get-ProcessCrashEvent)
            $row = $result | Where-Object { $_.ReportId -eq 'report-001' }
            $row.ProcessName | Should -Be 'app.exe'
            $row.ProcessPath | Should -Be 'C:\Apps\app.exe'
            $row.FaultingModule | Should -Be 'fault.dll'
            $row.ExceptionCode | Should -Be 'c0000005'
            $row.FaultingOffset | Should -Be '0000000000001234'
            $row.UserName | Should -Be 'CONTOSO\svc-app'
        }

        It -Name 'Should correlate WER without emitting a duplicate crash row' -Test {
            $result = @(Get-ProcessCrashEvent)
            @($result | Where-Object { $_.ReportId -eq 'report-001' }).Count | Should -Be 1
        }

        It -Name 'Should sort rows newest first' -Test {
            $result = @(Get-ProcessCrashEvent)
            [string[]]$result.EventTime | Should -Be ([string[]]($result.EventTime | Sort-Object -Descending))
        }

        It -Name 'Should aggregate CrashCount before applying ProcessName' -Test {
            $result = @(Get-ProcessCrashEvent -ProcessName 'APP.EXE')
            $result.Count | Should -Be 2
            $result | ForEach-Object { $_.CrashCount | Should -Be 2 }
        }
    }

    Context -Name 'Application Hang inclusion' -Fixture {
        BeforeAll {
            $script:hang = New-MockProcessEvent -EventId 1002 -TimeCreated (Get-Date '2026-09-04 09:00:00') `
                -XmlContent (New-ApplicationHangXml)
            $script:crash = New-MockProcessEvent -EventId 1000 -TimeCreated (Get-Date '2026-09-04 08:00:00') `
                -XmlContent (New-ApplicationErrorXml -AppName 'hung.exe' -AppPath 'C:\Apps\hung.exe' -ReportId 'hang-crash')
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:hang, $script:crash)
            }
        }

        It -Name 'Should exclude event 1002 unless IncludeHang is specified' -Test {
            $result = @(Get-ProcessCrashEvent)
            $result.Count | Should -Be 1
            $result[0].EventType | Should -Be 'Crash'
        }

        It -Name 'Should include event 1002 as a Hang when requested' -Test {
            $result = @(Get-ProcessCrashEvent -IncludeHang)
            $result.Count | Should -Be 2
            ($result | Where-Object EventType -eq 'Hang').ProcessName | Should -Be 'hung.exe'
            $result | ForEach-Object { $_.CrashCount | Should -Be 2 }
        }
    }

    Context -Name 'Incomplete events and empty result' -Fixture {
        It -Name 'Should preserve an incomplete event with empty fields' -Test {
            $incomplete = New-MockProcessEvent -EventId 1000 -TimeCreated (Get-Date '2026-09-04 07:00:00') `
                -XmlContent '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData /></Event>'
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { $incomplete }

            $result = @(Get-ProcessCrashEvent -Verbose)
            $result.Count | Should -Be 1
            $result.ProcessName | Should -Be ''
            $result.CrashCount | Should -Be 1
        }

        It -Name 'Should emit nothing when no events are found' -Test {
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { $null }
            $result = @(Get-ProcessCrashEvent -ErrorAction Stop)
            $result.Count | Should -Be 0
        }
    }

    Context -Name 'Explicit remote machine' -Fixture {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName       = 'PSWinOps.ProcessCrashEvent'
                    ComputerName     = 'SRV01'
                    EventTime        = '2026-09-04T10:00:00.0000000'
                    EventId          = 1000
                    EventType        = 'Crash'
                    ProcessName      = 'app.exe'
                    ProcessPath      = 'C:\Apps\app.exe'
                    FaultingModule   = 'fault.dll'
                    ExceptionCode    = 'c0000005'
                    FaultingOffset   = '0001'
                    ReportId         = 'report-001'
                    UserName         = 'CONTOSO\svc-app'
                    CrashCount       = 1
                    Message          = 'Simulated process crash'
                    Timestamp        = '2026-09-04T10:00:00.0000000'
                }
            }
        }

        It -Name 'Should dispatch through Invoke-Command' -Test {
            $result = Get-ProcessCrashEvent -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should propagate Credential to Invoke-Command' -Test {
            $securePassword = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', $securePassword)
            Get-ProcessCrashEvent -ComputerName 'SRV01' -Credential $credential
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $credential
            }
        }
    }

    Context -Name 'Pipeline and per-machine failure isolation' -Fixture {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw 'Simulated WinRM failure on SRV01'
                }

                [PSCustomObject]@{
                    PSTypeName       = 'PSWinOps.ProcessCrashEvent'
                    ComputerName     = $ComputerName
                    EventTime        = '2026-09-04T10:00:00.0000000'
                    EventId          = 1000
                    EventType        = 'Crash'
                    ProcessName      = 'app.exe'
                    ProcessPath      = 'C:\Apps\app.exe'
                    FaultingModule   = 'fault.dll'
                    ExceptionCode    = 'c0000005'
                    FaultingOffset   = '0001'
                    ReportId         = 'report-001'
                    UserName         = 'CONTOSO\svc-app'
                    CrashCount       = 1
                    Message          = 'Simulated process crash'
                    Timestamp        = '2026-09-04T10:00:00.0000000'
                }
            }
        }

        It -Name 'Should invoke once per piped machine and continue after a failure' -Test {
            $output = 'SRV01', 'SRV02' | Get-ProcessCrashEvent -ErrorAction Continue 2>&1
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
            @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -BeGreaterThan 0
            @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 1
            ($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).ComputerName | Should -Be 'SRV02'
        }
    }

    Context -Name 'Parameter validation' -Fixture {
        It -Name 'Should reject an empty ComputerName' -Test {
            { Get-ProcessCrashEvent -ComputerName '' } | Should -Throw
        }

        It -Name 'Should reject a null ComputerName' -Test {
            { Get-ProcessCrashEvent -ComputerName $null } | Should -Throw
        }

        It -Name 'Should reject Days outside the valid range' -Test {
            { Get-ProcessCrashEvent -Days 0 } | Should -Throw
            { Get-ProcessCrashEvent -Days 3651 } | Should -Throw
        }

        It -Name 'Should reject MaxEvents outside the valid range' -Test {
            { Get-ProcessCrashEvent -MaxEvents 0 } | Should -Throw
            { Get-ProcessCrashEvent -MaxEvents 10001 } | Should -Throw
        }

        It -Name 'Should expose pipeline support and aliases on ComputerName' -Test {
            $command = Get-Command -Name 'Get-ProcessCrashEvent'
            $parameterAttribute = $command.Parameters['ComputerName'].Attributes.Where({
                $_ -is [System.Management.Automation.ParameterAttribute]
            })[0]
            $parameterAttribute.ValueFromPipeline | Should -Be $true
            $parameterAttribute.ValueFromPipelineByPropertyName | Should -Be $true
            $command.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
            $command.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
            $command.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName'
        }
    }
}
