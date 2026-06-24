#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only -- not a real credential'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe -Name 'Get-RebootHistory' -Fixture {

    BeforeEach {
        Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
            [PSCustomObject]@{
                PSTypeName      = 'PSWinOps.RebootHistory'
                ComputerName    = $ComputerName
                ShutdownTime    = '2026-06-20 10:00:00'
                BootTime        = '2026-06-20 10:05:00'
                DowntimeMinutes = 5.0
                Type            = 'Planned'
                Cause           = 'Operating System: Upgrade (Planned)'
                Initiator       = 'DOMAIN\admin'
                Comment         = 'Scheduled maintenance'
                EventId         = 1074
                Timestamp       = '2026-06-23 12:00:00'
            }
        }
    }

    Context -Name 'Happy path - local machine' -Fixture {

        It -Name 'Should return a result for the local machine by default' -Test {
            $result = Get-RebootHistory
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should return a PSWinOps.RebootHistory typed object' -Test {
            $result = Get-RebootHistory
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.RebootHistory'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once for local machine' -Test {
            Get-RebootHistory
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should return all required output properties' -Test {
            $result = Get-RebootHistory
            $props = $result.PSObject.Properties.Name
            $props | Should -Contain 'ComputerName'
            $props | Should -Contain 'ShutdownTime'
            $props | Should -Contain 'BootTime'
            $props | Should -Contain 'DowntimeMinutes'
            $props | Should -Contain 'Type'
            $props | Should -Contain 'Cause'
            $props | Should -Contain 'Initiator'
            $props | Should -Contain 'Comment'
            $props | Should -Contain 'EventId'
            $props | Should -Contain 'Timestamp'
        }

        It -Name 'Should format Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $result = Get-RebootHistory
            $result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
    }

    Context -Name 'Status enum - Planned' -Fixture {

        It -Name 'Should surface Type=Planned returned by Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Planned'
                    Cause           = 'Operating System: Upgrade (Planned)'
                    Initiator       = 'DOMAIN\admin'
                    Comment         = 'Scheduled maintenance'
                    EventId         = 6006
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            $result = Get-RebootHistory
            $result.Type | Should -Be 'Planned'
        }
    }

    Context -Name 'Status enum - Unexpected' -Fixture {

        It -Name 'Should surface Type=Unexpected returned by Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Unexpected'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 6008
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            $result = Get-RebootHistory
            $result.Type | Should -Be 'Unexpected'
        }
    }

    Context -Name 'Status enum - Crash' -Fixture {

        It -Name 'Should surface Type=Crash with BugcheckCode in Cause' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Crash'
                    Cause           = 'BugcheckCode: 0x0000007E'
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 41
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            $result = Get-RebootHistory
            $result.Type | Should -Be 'Crash'
            $result.Cause | Should -Match "BugcheckCode"
        }
    }

    Context -Name 'Status enum - PowerLoss' -Fixture {

        It -Name 'Should surface Type=PowerLoss with null ShutdownTime' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = $null
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = $null
                    Type            = 'PowerLoss'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 41
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            $result = Get-RebootHistory
            $result.Type | Should -Be 'PowerLoss'
            $result.ShutdownTime | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Status enum - Unknown' -Fixture {

        It -Name 'Should surface Type=Unknown when no correlatable shutdown found' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = $null
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = $null
                    Type            = 'Unknown'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 6005
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            $result = Get-RebootHistory
            $result.Type | Should -Be 'Unknown'
        }
    }

    Context -Name 'Remote machine - explicit ComputerName' -Fixture {

        It -Name 'Should return result for named remote machine' -Test {
            $result = Get-RebootHistory -ComputerName 'SRV01'
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once for a named remote machine' -Test {
            Get-RebootHistory -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'Credential propagation' -Fixture {

        BeforeAll {
            $script:cred = [PSCredential]::new('admin', (ConvertTo-SecureString -String 'pass' -AsPlainText -Force))
        }

        It -Name 'Should pass Credential to Invoke-RemoteOrLocal' -Test {
            Get-RebootHistory -ComputerName 'SRV01' -Credential $script:cred
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }

        It -Name 'Should return a result when Credential is provided' -Test {
            $result = Get-RebootHistory -ComputerName 'SRV01' -Credential $script:cred
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'SRV01'
        }
    }

    Context -Name 'Pipeline by property name - multiple machines' -Fixture {

        It -Name 'Should process multiple machines supplied via pipeline' -Test {
            $result = @('SRV01', 'SRV02') | Get-RebootHistory
            $result | Should -HaveCount 2
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[1].ComputerName | Should -Be 'SRV02'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per piped machine' -Test {
            @('SRV01', 'SRV02') | Get-RebootHistory
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }

        It -Name 'Should process multiple machines from ComputerName array parameter' -Test {
            $result = Get-RebootHistory -ComputerName 'SRV01', 'SRV02', 'SRV03'
            $result | Should -HaveCount 3
        }
    }

    Context -Name 'Per-machine error isolation' -Fixture {

        It -Name 'Should continue to next machine when one fails' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'BADMACHINE') { throw 'WinRM connection failed' }
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Planned'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 1074
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            $result = Get-RebootHistory -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue
            $result | Should -HaveCount 1
            $result[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should write an error for the failing machine' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'BADMACHINE') { throw 'WinRM connection failed' }
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Planned'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 1074
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            Get-RebootHistory -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue -ErrorVariable 'capturedError'
            $capturedError | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'MaxEvents parameter' -Fixture {

        It -Name 'Should throw when MaxEvents is 0 (below valid range)' -Test {
            { Get-RebootHistory -MaxEvents 0 } | Should -Throw
        }

        It -Name 'Should throw when MaxEvents is 10001 (above valid range)' -Test {
            { Get-RebootHistory -MaxEvents 10001 } | Should -Throw
        }

        It -Name 'Should pass MaxEvents as first ArgumentList element to Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:capturedMaxEvents = $ArgumentList[0]
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Planned'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 1074
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            Get-RebootHistory -MaxEvents 10
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $script:capturedMaxEvents | Should -Be 10
        }

        It -Name 'Should default MaxEvents to 50 when not specified' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:capturedDefaultMaxEvents = $ArgumentList[0]
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Planned'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 1074
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            Get-RebootHistory
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $script:capturedDefaultMaxEvents | Should -Be 50
        }
    }

    Context -Name 'After and Before datetime filtering' -Fixture {

        It -Name 'Should set hasAfter flag in ArgumentList when -After is specified' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:capturedAfterFlag = $ArgumentList[3]
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Planned'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 1074
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            Get-RebootHistory -After (Get-Date '2026-01-01')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $script:capturedAfterFlag | Should -Be $true
        }

        It -Name 'Should set hasBefore flag in ArgumentList when -Before is specified' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:capturedBeforeFlag = $ArgumentList[4]
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Planned'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 1074
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            Get-RebootHistory -Before (Get-Date '2026-06-01')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $script:capturedBeforeFlag | Should -Be $true
        }

        It -Name 'Should leave hasAfter false when -After is not specified' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:capturedNoAfterFlag = $ArgumentList[3]
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.RebootHistory'
                    ComputerName    = $ComputerName
                    ShutdownTime    = '2026-06-20 10:00:00'
                    BootTime        = '2026-06-20 10:05:00'
                    DowntimeMinutes = 5.0
                    Type            = 'Planned'
                    Cause           = ''
                    Initiator       = ''
                    Comment         = ''
                    EventId         = 1074
                    Timestamp       = '2026-06-23 12:00:00'
                }
            }
            Get-RebootHistory
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $script:capturedNoAfterFlag | Should -Be $false
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-RebootHistory -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-RebootHistory -ComputerName $null } | Should -Throw
        }

        It -Name 'Should expose ComputerName with pipeline support by value and by property name' -Test {
            $cmd = Get-Command -Name 'Get-RebootHistory'
            $attr = $cmd.Parameters['ComputerName'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })[0]
            $attr.ValueFromPipeline | Should -Be $true
            $attr.ValueFromPipelineByPropertyName | Should -Be $true
        }

        It -Name 'Should expose ComputerName aliases CN, Name and DNSHostName' -Test {
            $cmd = Get-Command -Name 'Get-RebootHistory'
            $aliases = $cmd.Parameters['ComputerName'].Aliases
            $aliases | Should -Contain 'CN'
            $aliases | Should -Contain 'Name'
            $aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should expose After parameter of type datetime' -Test {
            $cmd = Get-Command -Name 'Get-RebootHistory'
            $cmd.Parameters['After'].ParameterType | Should -Be ([datetime])
        }

        It -Name 'Should expose Before parameter of type datetime' -Test {
            $cmd = Get-Command -Name 'Get-RebootHistory'
            $cmd.Parameters['Before'].ParameterType | Should -Be ([datetime])
        }
    }
}
