#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    function New-MockDiskEvent {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ProviderName,
            [Parameter(Mandatory = $true)]
            [int]$EventId,
            [Parameter(Mandatory = $true)]
            [datetime]$TimeCreated,
            [Parameter(Mandatory = $true)]
            [string]$XmlContent,
            [string]$Message = 'Simulated storage event'
        )

        $mockEvent = [PSCustomObject]@{
            ProviderName = $ProviderName
            Id           = $EventId
            TimeCreated  = $TimeCreated
            Message      = $Message
        }

        $mockEvent | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
            return $XmlContent
        }.GetNewClosure() -Force

        return $mockEvent
    }

    function New-DiskEventXml {
        param(
            [string]$DiskNumber = '0',
            [string]$DeviceName = '\\Device\\Harddisk0\\DR0',
            [string]$DevicePath = '\\Device\\0000007a',
            [string]$ErrorCode = '0xC0000185',
            [string]$RetryCount = '3'
        )

        @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <EventData>
    <Data Name="DiskNumber">$DiskNumber</Data>
    <Data Name="DeviceName">$DeviceName</Data>
    <Data Name="DevicePath">$DevicePath</Data>
    <Data Name="ErrorCode">$ErrorCode</Data>
    <Data Name="RetryCount">$RetryCount</Data>
  </EventData>
</Event>
"@
    }
}

Describe -Name 'Get-DiskErrorEvent' -Fixture {
    Context -Name 'Local parsing, classification, sorting, and aggregation' -Fixture {
        BeforeAll {
            $script:badBlockNewest = New-MockDiskEvent -ProviderName 'Disk' -EventId 7 `
                -TimeCreated (Get-Date '2026-09-04 10:00:00') -XmlContent (New-DiskEventXml)
            $script:badBlockOlder = New-MockDiskEvent -ProviderName 'Disk' -EventId 7 `
                -TimeCreated (Get-Date '2026-09-03 10:00:00') -XmlContent (New-DiskEventXml)
            $script:ioTimeout = New-MockDiskEvent -ProviderName 'Disk' -EventId 51 `
                -TimeCreated (Get-Date '2026-09-02 10:00:00') -XmlContent (New-DiskEventXml -DiskNumber '1' -DeviceName '\\Device\\Harddisk1\\DR1')
            $script:controllerReset = New-MockDiskEvent -ProviderName 'storport' -EventId 129 `
                -TimeCreated (Get-Date '2026-09-01 10:00:00') -XmlContent (New-DiskEventXml -DiskNumber '2' -DeviceName '\\Device\\Harddisk2\\DR2')
            $script:ignoredProvider = New-MockDiskEvent -ProviderName 'CustomProvider' -EventId 7 `
                -TimeCreated (Get-Date '2026-09-04 11:00:00') -XmlContent (New-DiskEventXml)

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:badBlockOlder, $script:ioTimeout, $script:controllerReset, $script:ignoredProvider, $script:badBlockNewest)
            }
        }

        It -Name 'Should return recognized events newest first and ignore unrelated provider IDs' -Test {
            $result = @(Get-DiskErrorEvent)
            $result.Count | Should -Be 4
            $result[0].EventId | Should -Be 7
            $result[0].ProviderName | Should -Be 'Disk'
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.DiskErrorEvent'
            [string[]]$result.EventTime | Should -Be ([string[]]($result.EventTime | Sort-Object -Descending))
        }

        It -Name 'Should parse named XML fields and classify events deterministically' -Test {
            $result = @(Get-DiskErrorEvent)
            $badBlock = $result | Where-Object { $_.EventId -eq 7 } | Select-Object -First 1
            $badBlock.ErrorType | Should -Be 'BadBlock'
            $badBlock.IsCritical | Should -BeTrue
            $badBlock.DiskNumber | Should -Be 0
            $badBlock.DeviceName | Should -Be '\\Device\\Harddisk0\\DR0'
            $badBlock.ErrorCode | Should -Be '0xC0000185'
            $badBlock.RetryCount | Should -Be 3
        }

        It -Name 'Should aggregate EventCount by provider, error type, and device' -Test {
            $result = @(Get-DiskErrorEvent)
            @($result | Where-Object { $_.EventId -eq 7 } | Select-Object -ExpandProperty EventCount) | Should -Be @(2, 2)
        }
    }

    Context -Name 'Filters and incomplete XML' -Fixture {
        BeforeAll {
            $script:critical = New-MockDiskEvent -ProviderName 'Ntfs' -EventId 55 `
                -TimeCreated (Get-Date '2026-09-04 10:00:00') -XmlContent (New-DiskEventXml -DiskNumber '0')
            $script:warning = New-MockDiskEvent -ProviderName 'storport' -EventId 153 `
                -TimeCreated (Get-Date '2026-09-04 09:00:00') -XmlContent (New-DiskEventXml -DiskNumber '1')
            $script:incomplete = New-MockDiskEvent -ProviderName 'Disk' -EventId 154 `
                -TimeCreated (Get-Date '2026-09-04 08:00:00') `
                -XmlContent '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData /></Event>'

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:critical, $script:warning, $script:incomplete)
            }
        }

        It -Name 'Should apply DiskNumber after parsing' -Test {
            $result = @(Get-DiskErrorEvent -DiskNumber 1)
            $result.Count | Should -Be 1
            $result[0].ProviderName | Should -Be 'storport'
            $result[0].DiskNumber | Should -Be 1
        }

        It -Name 'Should apply CriticalOnly after classification' -Test {
            $result = @(Get-DiskErrorEvent -CriticalOnly)
            $result.Count | Should -Be 1
            $result[0].ErrorType | Should -Be 'FileSystem'
            $result[0].IsCritical | Should -BeTrue
        }

        It -Name 'Should preserve incomplete events as non-critical Unknown rows' -Test {
            $result = @(Get-DiskErrorEvent)
            $unknown = $result | Where-Object { $_.EventId -eq 154 }
            $unknown.ErrorType | Should -Be 'Unknown'
            $unknown.IsCritical | Should -BeFalse
            $unknown.DiskNumber | Should -BeNullOrEmpty
            $unknown.DevicePath | Should -Be ''
        }
    }

    Context -Name 'Remote, pipeline, and error isolation' -Fixture {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.DiskErrorEvent'
                    ComputerName = 'SRV01'
                    EventTime    = '2026-09-04T10:00:00.0000000'
                    ProviderName = 'Disk'
                    EventId      = 7
                    ErrorType    = 'BadBlock'
                    IsCritical   = $true
                    DiskNumber   = 0
                    DeviceName   = '\\Device\\Harddisk0\\DR0'
                    DevicePath   = ''
                    ErrorCode    = ''
                    RetryCount   = $null
                    EventCount   = 1
                    Message      = 'Simulated disk error'
                    Timestamp    = '2026-09-04T10:00:00.0000000'
                }
            }
        }

        It -Name 'Should dispatch remote queries and propagate Credential' -Test {
            $securePassword = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', $securePassword)
            $result = @(Get-DiskErrorEvent -ComputerName 'SRV01' -Credential $credential)
            $result.ComputerName | Should -Be 'SRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $credential
            }
        }

        It -Name 'Should continue after a per-machine failure in pipeline input' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw 'Simulated failure on SRV01'
                }

                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.DiskErrorEvent'
                    ComputerName = $ComputerName
                    EventTime    = '2026-09-04T10:00:00.0000000'
                    ProviderName = 'Disk'
                    EventId      = 7
                    ErrorType    = 'BadBlock'
                    IsCritical   = $true
                    DiskNumber   = 0
                    DeviceName   = ''
                    DevicePath   = ''
                    ErrorCode    = ''
                    RetryCount   = $null
                    EventCount   = 1
                    Message      = ''
                    Timestamp    = '2026-09-04T10:00:00.0000000'
                }
            }

            $output = 'SRV01', 'SRV02' | Get-DiskErrorEvent -ErrorAction Continue 2>&1
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
            @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -BeGreaterThan 0
            @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 1
            ($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).ComputerName | Should -Be 'SRV02'
        }
    }

    Context -Name 'Parameter validation and metadata' -Fixture {
        It -Name 'Should reject invalid ComputerName, Days, MaxEvents, and DiskNumber' -Test {
            { Get-DiskErrorEvent -ComputerName '' } | Should -Throw
            { Get-DiskErrorEvent -ComputerName $null } | Should -Throw
            { Get-DiskErrorEvent -Days 0 } | Should -Throw
            { Get-DiskErrorEvent -Days 3651 } | Should -Throw
            { Get-DiskErrorEvent -MaxEvents 0 } | Should -Throw
            { Get-DiskErrorEvent -MaxEvents 10001 } | Should -Throw
            { Get-DiskErrorEvent -DiskNumber -1 } | Should -Throw
        }

        It -Name 'Should expose pipeline support and aliases on ComputerName' -Test {
            $command = Get-Command -Name 'Get-DiskErrorEvent'
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
