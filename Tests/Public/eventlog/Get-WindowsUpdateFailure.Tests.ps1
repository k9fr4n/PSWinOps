#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    function New-MockWindowsUpdateEvent {
        param(
            [Parameter(Mandatory = $true)]
            [int]$EventId,
            [Parameter(Mandatory = $true)]
            [datetime]$TimeCreated,
            [Parameter(Mandatory = $true)]
            [string]$XmlContent,
            [string]$Message = 'Localized Windows Update event message'
        )

        $mockEvent = [PSCustomObject]@{
            Id           = $EventId
            TimeCreated  = $TimeCreated
            Message      = $Message
        }

        $mockEvent | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
            return $XmlContent
        }.GetNewClosure() -Force

        return $mockEvent
    }

    function New-WindowsUpdateXml {
        param(
            [string]$UpdateTitle = '2026-09 Cumulative Update (KB5030211)',
            [string]$UpdateId = '11111111-2222-3333-4444-555555555555',
            [string]$ErrorCode = '',
            [string]$FailureReason = ''
        )

        @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <EventData>
    <Data Name="updateTitle">$UpdateTitle</Data>
    <Data Name="updateGuid">$UpdateId</Data>
    <Data Name="errorCode">$ErrorCode</Data>
    <Data Name="failureReason">$FailureReason</Data>
  </EventData>
</Event>
"@
    }
}

Describe -Name 'Get-WindowsUpdateFailure' -Fixture {
    Context -Name 'Local parsing and classification' -Fixture {
        BeforeAll {
            $script:failedEvent = New-MockWindowsUpdateEvent -EventId 20 `
                -TimeCreated (Get-Date '2026-09-04 10:00:00') `
                -XmlContent (New-WindowsUpdateXml -ErrorCode '-2147024891')
            $script:rebootEvent = New-MockWindowsUpdateEvent -EventId 21 `
                -TimeCreated (Get-Date '2026-09-04 09:00:00') `
                -XmlContent (New-WindowsUpdateXml -UpdateTitle 'Servicing Stack Update')
            $script:successEvent = New-MockWindowsUpdateEvent -EventId 19 `
                -TimeCreated (Get-Date '2026-09-04 08:00:00') `
                -XmlContent (New-WindowsUpdateXml -UpdateTitle 'Definition Update (KB2267602)')

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:successEvent, $script:rebootEvent, $script:failedEvent)
            }
        }

        It -Name 'Should return failures and restart-required events by default, newest first' -Test {
            $result = @(Get-WindowsUpdateFailure)

            $result.Count | Should -Be 2
            $result[0].EventId | Should -Be 20
            $result[0].Status | Should -Be 'Failed'
            $result[1].Status | Should -Be 'RebootRequired'
            $result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateFailure'
            [string[]]$result.EventTime | Should -Be ([string[]]($result.EventTime | Sort-Object -Descending))
        }

        It -Name 'Should parse named XML fields and preserve raw and hexadecimal error codes' -Test {
            $result = @(Get-WindowsUpdateFailure)
            $failed = $result | Where-Object EventId -eq 20

            $failed.KBArticle | Should -Be 'KB5030211'
            $failed.UpdateTitle | Should -Be '2026-09 Cumulative Update (KB5030211)'
            $failed.UpdateId | Should -Be '11111111-2222-3333-4444-555555555555'
            $failed.ErrorCode | Should -Be '-2147024891'
            $failed.ErrorCodeHex | Should -Be '0x80070005'
            $failed.FailureReason | Should -Be 'InstallationFailure'
        }

        It -Name 'Should classify reboot-required events separately from failures' -Test {
            $reboot = (Get-WindowsUpdateFailure) | Where-Object EventId -eq 21

            $reboot.Status | Should -Be 'RebootRequired'
            $reboot.RebootRequired | Should -BeTrue
            $reboot.FailureReason | Should -Be 'RestartRequired'
        }

        It -Name 'Should include successful installations only when requested' -Test {
            $result = @(Get-WindowsUpdateFailure -IncludeSuccess)

            $result.Count | Should -Be 3
            ($result | Where-Object EventId -eq 19).Status | Should -Be 'Succeeded'
            ($result | Where-Object EventId -eq 19).RebootRequired | Should -BeFalse
        }
    }

    Context -Name 'Filters and incomplete events' -Fixture {
        BeforeAll {
            $script:filteredEvent = New-MockWindowsUpdateEvent -EventId 20 `
                -TimeCreated (Get-Date '2026-09-04 10:00:00') `
                -XmlContent (New-WindowsUpdateXml -UpdateTitle 'Security Update (KB5012345)' -ErrorCode '0x800F081F')
            $script:untitledEvent = New-MockWindowsUpdateEvent -EventId 21 `
                -TimeCreated (Get-Date '2026-09-04 09:00:00') `
                -XmlContent '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData /></Event>'

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:filteredEvent, $script:untitledEvent)
            }
        }

        It -Name 'Should filter by KB article after XML extraction' -Test {
            $result = @(Get-WindowsUpdateFailure -KBArticle 'kb5012345')

            $result.Count | Should -Be 1
            $result[0].KBArticle | Should -Be 'KB5012345'
        }

        It -Name 'Should filter by update title case-insensitively' -Test {
            $result = @(Get-WindowsUpdateFailure -UpdateTitle 'SECURITY UPDATE')

            $result.Count | Should -Be 1
            $result[0].UpdateTitle | Should -Be 'Security Update (KB5012345)'
        }

        It -Name 'Should preserve missing optional XML fields as empty values' -Test {
            $result = @(Get-WindowsUpdateFailure)
            $incomplete = $result | Where-Object EventId -eq 21

            $incomplete.KBArticle | Should -Be ''
            $incomplete.UpdateTitle | Should -Be ''
            $incomplete.UpdateId | Should -Be ''
            $incomplete.ErrorCode | Should -Be ''
            $incomplete.ErrorCodeHex | Should -Be ''
        }

        It -Name 'Should return no objects when no events are found' -Test {
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { $null }

            @(Get-WindowsUpdateFailure) | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Remote, credentials, pipeline, and error isolation' -Fixture {
        BeforeEach {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw 'Simulated WinRM failure on SRV01'
                }

                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.WindowsUpdateFailure'
                    ComputerName    = $ComputerName
                    EventTime       = '2026-09-04T10:00:00.0000000'
                    EventId         = 20
                    Status          = 'Failed'
                    KBArticle       = 'KB5030211'
                    UpdateTitle     = 'Security Update'
                    UpdateId        = ''
                    ErrorCode       = '0x80070005'
                    ErrorCodeHex    = '0x80070005'
                    RebootRequired  = $false
                    FailureReason   = 'InstallationFailure'
                    Message         = ''
                    Timestamp       = '2026-09-04T10:00:00.0000000'
                }
            }
        }

        It -Name 'Should query a remote machine and propagate credentials' -Test {
            $securePassword = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', $securePassword)
            $result = @(Get-WindowsUpdateFailure -ComputerName 'SRV02' -Credential $credential)

            $result.ComputerName | Should -Be 'SRV02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'SRV02' -and $Credential -eq $credential
            }
        }

        It -Name 'Should continue after a per-machine failure in pipeline input' -Test {
            $output = 'SRV01', 'SRV02' | Get-WindowsUpdateFailure -ErrorAction Continue 2>&1

            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
            @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -BeGreaterThan 0
            @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 1
            ($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).ComputerName | Should -Be 'SRV02'
        }
    }

    Context -Name 'Parameter validation and metadata' -Fixture {
        It -Name 'Should reject invalid ComputerName, Days, and MaxEvents' -Test {
            { Get-WindowsUpdateFailure -ComputerName '' } | Should -Throw
            { Get-WindowsUpdateFailure -ComputerName $null } | Should -Throw
            { Get-WindowsUpdateFailure -Days 0 } | Should -Throw
            { Get-WindowsUpdateFailure -Days 3651 } | Should -Throw
            { Get-WindowsUpdateFailure -MaxEvents 0 } | Should -Throw
            { Get-WindowsUpdateFailure -MaxEvents 10001 } | Should -Throw
        }

        It -Name 'Should expose pipeline support and aliases on ComputerName' -Test {
            $command = Get-Command -Name 'Get-WindowsUpdateFailure'
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
            $event = New-MockWindowsUpdateEvent -EventId 20 `
                -TimeCreated (Get-Date '2026-09-04 10:00:00') `
                -XmlContent (New-WindowsUpdateXml -ErrorCode '5')
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { $event }

            $result = @(Get-WindowsUpdateFailure)
            foreach ($property in @(
                'ComputerName', 'EventTime', 'EventId', 'Status', 'KBArticle', 'UpdateTitle',
                'UpdateId', 'ErrorCode', 'ErrorCodeHex', 'RebootRequired', 'FailureReason',
                'Message', 'Timestamp'
            )) {
                $result[0].PSObject.Properties.Name | Should -Contain $property
            }
        }
    }
}
