#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    function New-MockScheduledTaskEvent {
        param(
            [Parameter(Mandatory = $true)]
            [int]$EventId,
            [Parameter(Mandatory = $true)]
            [datetime]$TimeCreated,
            [Parameter(Mandatory = $true)]
            [string]$XmlContent,
            [string]$Message = 'Simulated scheduled-task failure'
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

    function New-TaskStartFailureXml {
        param(
            [string]$TaskName = '\Backup\NightlyBackup',
            [string]$UserName = 'CONTOSO\svc-backup',
            [string]$ErrorValue = '2147942402'
        )

        @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <EventData>
    <Data Name="TaskName">$TaskName</Data>
    <Data Name="UserName">$UserName</Data>
    <Data Name="ErrorValue">$ErrorValue</Data>
  </EventData>
</Event>
"@
    }

    function New-ActionFailureXml {
        param(
            [string]$TaskName = '\Backup\NightlyBackup',
            [string]$ActionName = 'C:\Scripts\backup.ps1',
            [string]$ResultCode = '0x80070005'
        )

        @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <EventData>
    <Data Name="TaskName">$TaskName</Data>
    <Data Name="ActionName">$ActionName</Data>
    <Data Name="ResultCode">$ResultCode</Data>
  </EventData>
</Event>
"@
    }
}

Describe -Name 'Get-ScheduledTaskFailure' -Fixture {
    Context -Name 'Local parsing, classification, sorting, and aggregation' -Fixture {
        BeforeAll {
            $script:taskStartFailure = New-MockScheduledTaskEvent -EventId 101 `
                -TimeCreated (Get-Date '2026-09-04 10:00:00') `
                -XmlContent (New-TaskStartFailureXml)
            $script:actionFailure = New-MockScheduledTaskEvent -EventId 202 `
                -TimeCreated (Get-Date '2026-09-03 10:00:00') `
                -XmlContent (New-ActionFailureXml)
            $script:otherTaskFailure = New-MockScheduledTaskEvent -EventId 203 `
                -TimeCreated (Get-Date '2026-09-02 10:00:00') `
                -XmlContent (New-ActionFailureXml -TaskName '\Maintenance\Cleanup' -ActionName 'clean.cmd')

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:otherTaskFailure, $script:actionFailure, $script:taskStartFailure)
            }
        }

        It -Name 'Should return recognized failures newest first and type the output' -Test {
            $result = @(Get-ScheduledTaskFailure)
            $result.Count | Should -Be 3
            $result[0].EventId | Should -Be 101
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ScheduledTaskFailure'
            [string[]]$result.EventTime | Should -Be ([string[]]($result.EventTime | Sort-Object -Descending))
        }

        It -Name 'Should parse task identity, action, user, failure reason, and result codes from XML' -Test {
            $result = @(Get-ScheduledTaskFailure)
            $start = $result | Where-Object EventId -eq 101
            $action = $result | Where-Object EventId -eq 202

            $start.TaskPath | Should -Be '\Backup\'
            $start.TaskName | Should -Be 'NightlyBackup'
            $start.UserName | Should -Be 'CONTOSO\svc-backup'
            $start.FailureReason | Should -Be 'TaskStartFailure'
            $start.ResultCode | Should -Be '2147942402'
            $start.ResultCodeHex | Should -Be '0x80070002'
            $action.ActionName | Should -Be 'C:\Scripts\backup.ps1'
            $action.FailureReason | Should -Be 'ActionFailure'
            $action.ResultCodeHex | Should -Be '0x80070005'
        }

        It -Name 'Should aggregate FailureCount per task before applying filters' -Test {
            $script:secondFailure = New-MockScheduledTaskEvent -EventId 103 `
                -TimeCreated (Get-Date '2026-09-01 10:00:00') `
                -XmlContent (New-TaskStartFailureXml -ErrorValue '2147942402')
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:taskStartFailure, $script:actionFailure, $script:secondFailure)
            }

            $result = @(Get-ScheduledTaskFailure -TaskName 'NIGHTLYBACKUP')
            $result.Count | Should -Be 3
            $result | ForEach-Object { $_.FailureCount | Should -Be 3 }
        }

        It -Name 'Should apply TaskPath after XML extraction' -Test {
            $result = @(Get-ScheduledTaskFailure -TaskPath '\Maintenance\')
            $result.Count | Should -Be 1
            $result[0].TaskName | Should -Be 'Cleanup'
        }
    }

    Context -Name 'Incomplete events and empty result' -Fixture {
        It -Name 'Should preserve an incomplete event with empty extracted fields' -Test {
            $incomplete = New-MockScheduledTaskEvent -EventId 103 `
                -TimeCreated (Get-Date '2026-09-04 07:00:00') `
                -XmlContent '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData /></Event>'
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { $incomplete }

            $result = @(Get-ScheduledTaskFailure)
            $result.Count | Should -Be 1
            $result.TaskName | Should -Be ''
            $result.TaskPath | Should -Be ''
            $result.FailureCount | Should -Be 1
            $result.LastRunTime | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should emit nothing when no events are found' -Test {
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { $null }
            $result = @(Get-ScheduledTaskFailure -ErrorAction Stop)
            $result.Count | Should -Be 0
        }
    }

    Context -Name 'Explicit remote machine' -Fixture {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.ScheduledTaskFailure'
                    ComputerName   = 'SRV01'
                    EventTime      = '2026-09-04T10:00:00.0000000'
                    EventId        = 101
                    TaskName       = 'NightlyBackup'
                    TaskPath       = '\Backup\'
                    ActionName     = ''
                    UserName       = 'CONTOSO\svc-backup'
                    ResultCode     = '2147942402'
                    ResultCodeHex  = '0x80070002'
                    FailureReason  = 'TaskStartFailure'
                    LastRunTime    = '2026-09-04T10:00:00.0000000'
                    FailureCount   = 1
                    Message        = 'Simulated failure'
                    Timestamp      = '2026-09-04T10:00:00.0000000'
                }
            }
        }

        It -Name 'Should dispatch remote queries' -Test {
            $result = @(Get-ScheduledTaskFailure -ComputerName 'SRV01')
            $result.ComputerName | Should -Be 'SRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should propagate Credential to Invoke-Command' -Test {
            $securePassword = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', $securePassword)
            Get-ScheduledTaskFailure -ComputerName 'SRV01' -Credential $credential
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
                    PSTypeName     = 'PSWinOps.ScheduledTaskFailure'
                    ComputerName   = $ComputerName
                    EventTime      = '2026-09-04T10:00:00.0000000'
                    EventId        = 203
                    TaskName       = 'Cleanup'
                    TaskPath       = '\Maintenance\'
                    ActionName     = 'clean.cmd'
                    UserName       = ''
                    ResultCode     = ''
                    ResultCodeHex  = ''
                    FailureReason  = 'ActionLaunchFailure'
                    LastRunTime    = '2026-09-04T10:00:00.0000000'
                    FailureCount   = 1
                    Message        = ''
                    Timestamp      = '2026-09-04T10:00:00.0000000'
                }
            }
        }

        It -Name 'Should continue after a per-machine failure in pipeline input' -Test {
            $output = 'SRV01', 'SRV02' | Get-ScheduledTaskFailure -ErrorAction Continue 2>&1
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
            @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -BeGreaterThan 0
            @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 1
            ($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).ComputerName | Should -Be 'SRV02'
        }
    }

    Context -Name 'Parameter validation and metadata' -Fixture {
        It -Name 'Should reject invalid ComputerName, Days, and MaxEvents' -Test {
            { Get-ScheduledTaskFailure -ComputerName '' } | Should -Throw
            { Get-ScheduledTaskFailure -ComputerName $null } | Should -Throw
            { Get-ScheduledTaskFailure -Days 0 } | Should -Throw
            { Get-ScheduledTaskFailure -Days 3651 } | Should -Throw
            { Get-ScheduledTaskFailure -MaxEvents 0 } | Should -Throw
            { Get-ScheduledTaskFailure -MaxEvents 10001 } | Should -Throw
        }

        It -Name 'Should expose pipeline support and aliases on ComputerName' -Test {
            $command = Get-Command -Name 'Get-ScheduledTaskFailure'
            $parameterAttribute = $command.Parameters['ComputerName'].Attributes.Where({
                $_ -is [System.Management.Automation.ParameterAttribute]
            })[0]
            $parameterAttribute.ValueFromPipeline | Should -Be $true
            $parameterAttribute.ValueFromPipelineByPropertyName | Should -Be $true
            $command.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
            $command.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
            $command.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should expose the required output properties' -Test {
            $script:event = New-MockScheduledTaskEvent -EventId 101 `
                -TimeCreated (Get-Date '2026-09-04 10:00:00') `
                -XmlContent (New-TaskStartFailureXml)
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { $script:event }

            $result = @(Get-ScheduledTaskFailure)
            foreach ($property in @(
                'ComputerName', 'EventTime', 'EventId', 'TaskName', 'TaskPath', 'ActionName',
                'UserName', 'ResultCode', 'ResultCodeHex', 'FailureReason', 'LastRunTime',
                'FailureCount', 'Message', 'Timestamp'
            )) {
                $result[0].PSObject.Properties.Name | Should -Contain $property
            }
        }
    }
}
