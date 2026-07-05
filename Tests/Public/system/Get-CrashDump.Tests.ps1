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

Describe -Name 'Get-CrashDump' -Fixture {

    BeforeEach {
        Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
            [PSCustomObject]@{
                PSTypeName     = 'PSWinOps.CrashDump'
                ComputerName   = $ComputerName
                DumpFile       = 'C:\Windows\Minidump\070526-12345-01.dmp'
                DumpType       = 'Mini'
                SizeMB         = 0.45
                CreationTime   = '2026-07-05 08:00:00'
                BugCheckCode   = '0x0000009F'
                BugCheckSymbol = 'DRIVER_POWER_STATE_FAILURE'
                Timestamp      = '2026-07-05 12:00:00'
            }
        }
    }

    Context -Name 'Happy path - local machine' -Fixture {

        It -Name 'Should return a result for the local machine by default' -Test {
            $result = Get-CrashDump
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should return a PSWinOps.CrashDump typed object' -Test {
            $result = Get-CrashDump
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.CrashDump'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once for local machine' -Test {
            Get-CrashDump
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }

        It -Name 'Should return all required output properties' -Test {
            $result = Get-CrashDump
            $props = $result.PSObject.Properties.Name
            $props | Should -Contain 'ComputerName'
            $props | Should -Contain 'DumpFile'
            $props | Should -Contain 'DumpType'
            $props | Should -Contain 'SizeMB'
            $props | Should -Contain 'CreationTime'
            $props | Should -Contain 'BugCheckCode'
            $props | Should -Contain 'BugCheckSymbol'
            $props | Should -Contain 'Timestamp'
        }

        It -Name 'Should format Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $result = Get-CrashDump
            $result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }

        It -Name 'Should format CreationTime as yyyy-MM-dd HH:mm:ss' -Test {
            $result = Get-CrashDump
            $result.CreationTime | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
    }

    Context -Name 'DumpType enum - Mini' -Fixture {

        It -Name 'Should surface DumpType=Mini returned by Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\Minidump\070526-12345-01.dmp'
                    DumpType       = 'Mini'
                    SizeMB         = 0.45
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = $null
                    BugCheckSymbol = $null
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            $result = Get-CrashDump
            $result.DumpType | Should -Be 'Mini'
        }
    }

    Context -Name 'DumpType enum - Full' -Fixture {

        It -Name 'Should surface DumpType=Full returned by Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\MEMORY.DMP'
                    DumpType       = 'Full'
                    SizeMB         = 2048.0
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = '0x0000007E'
                    BugCheckSymbol = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED_M'
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            $result = Get-CrashDump
            $result.DumpType | Should -Be 'Full'
        }
    }

    Context -Name 'DumpType enum - Kernel' -Fixture {

        It -Name 'Should surface DumpType=Kernel returned by Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\MEMORY.DMP'
                    DumpType       = 'Kernel'
                    SizeMB         = 512.0
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = $null
                    BugCheckSymbol = $null
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            $result = Get-CrashDump
            $result.DumpType | Should -Be 'Kernel'
        }
    }

    Context -Name 'BugCheck correlation' -Fixture {

        It -Name 'Should populate BugCheckCode and BugCheckSymbol when correlated' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\Minidump\070526-12345-01.dmp'
                    DumpType       = 'Mini'
                    SizeMB         = 0.45
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = '0x0000009F'
                    BugCheckSymbol = 'DRIVER_POWER_STATE_FAILURE'
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            $result = Get-CrashDump
            $result.BugCheckCode | Should -Be '0x0000009F'
            $result.BugCheckSymbol | Should -Be 'DRIVER_POWER_STATE_FAILURE'
        }

        It -Name 'Should leave BugCheckCode and BugCheckSymbol null when unresolved' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\Minidump\070526-12345-01.dmp'
                    DumpType       = 'Mini'
                    SizeMB         = 0.45
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = $null
                    BugCheckSymbol = $null
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            $result = Get-CrashDump
            $result.BugCheckCode | Should -BeNullOrEmpty
            $result.BugCheckSymbol | Should -BeNullOrEmpty
        }
    }

    Context -Name 'No dumps present' -Fixture {

        It -Name 'Should emit nothing and no error when no dumps are found' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
            $result = Get-CrashDump -ErrorVariable 'capturedError'
            $result | Should -BeNullOrEmpty
            $capturedError | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Remote machine - explicit ComputerName' -Fixture {

        It -Name 'Should return result for named remote machine' -Test {
            $result = Get-CrashDump -ComputerName 'SRV01'
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once for a named remote machine' -Test {
            Get-CrashDump -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'Credential propagation' -Fixture {

        BeforeAll {
            $script:cred = [PSCredential]::new('admin', (ConvertTo-SecureString -String 'pass' -AsPlainText -Force))
        }

        It -Name 'Should pass Credential to Invoke-RemoteOrLocal' -Test {
            Get-CrashDump -ComputerName 'SRV01' -Credential $script:cred
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }

        It -Name 'Should return a result when Credential is provided' -Test {
            $result = Get-CrashDump -ComputerName 'SRV01' -Credential $script:cred
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'SRV01'
        }
    }

    Context -Name 'Pipeline by property name - multiple machines' -Fixture {

        It -Name 'Should process multiple machines supplied via pipeline' -Test {
            $result = @('SRV01', 'SRV02') | Get-CrashDump
            $result | Should -HaveCount 2
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[1].ComputerName | Should -Be 'SRV02'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per piped machine' -Test {
            @('SRV01', 'SRV02') | Get-CrashDump
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }

        It -Name 'Should process multiple machines from ComputerName array parameter' -Test {
            $result = Get-CrashDump -ComputerName 'SRV01', 'SRV02', 'SRV03'
            $result | Should -HaveCount 3
        }

        It -Name 'Should accept pipeline input by property name' -Test {
            $objects = @(
                [PSCustomObject]@{ ComputerName = 'SRV01' },
                [PSCustomObject]@{ ComputerName = 'SRV02' }
            )
            $result = $objects | Get-CrashDump
            $result | Should -HaveCount 2
        }
    }

    Context -Name 'Per-machine error isolation' -Fixture {

        It -Name 'Should continue to next machine when one fails' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'BADMACHINE') { throw 'WinRM connection failed' }
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\Minidump\070526-12345-01.dmp'
                    DumpType       = 'Mini'
                    SizeMB         = 0.45
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = $null
                    BugCheckSymbol = $null
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            $result = Get-CrashDump -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue
            $result | Should -HaveCount 1
            $result[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should write an error for the failing machine' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'BADMACHINE') { throw 'WinRM connection failed' }
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\Minidump\070526-12345-01.dmp'
                    DumpType       = 'Mini'
                    SizeMB         = 0.45
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = $null
                    BugCheckSymbol = $null
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            Get-CrashDump -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue -ErrorVariable 'capturedError'
            $capturedError | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Path parameter' -Fixture {

        It -Name 'Should pass HasPath flag and Path value as ArgumentList to Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:capturedHasPath = $ArgumentList[0]
                $script:capturedPath = $ArgumentList[1]
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'D:\Dumps\custom.dmp'
                    DumpType       = 'Mini'
                    SizeMB         = 0.45
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = $null
                    BugCheckSymbol = $null
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            Get-CrashDump -Path 'D:\Dumps\*.dmp'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $script:capturedHasPath | Should -Be $true
            $script:capturedPath | Should -Be 'D:\Dumps\*.dmp'
        }

        It -Name 'Should leave HasPath false when Path is not specified' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:capturedNoPathFlag = $ArgumentList[0]
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\Minidump\070526-12345-01.dmp'
                    DumpType       = 'Mini'
                    SizeMB         = 0.45
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = $null
                    BugCheckSymbol = $null
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            Get-CrashDump
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $script:capturedNoPathFlag | Should -Be $false
        }
    }

    Context -Name 'Newest parameter' -Fixture {

        It -Name 'Should throw when Newest is 0 (below valid range)' -Test {
            { Get-CrashDump -Newest 0 } | Should -Throw
        }

        It -Name 'Should pass HasNewest flag and NewestCount as ArgumentList to Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:capturedHasNewest = $ArgumentList[2]
                $script:capturedNewestCount = $ArgumentList[3]
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\Minidump\070526-12345-01.dmp'
                    DumpType       = 'Mini'
                    SizeMB         = 0.45
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = $null
                    BugCheckSymbol = $null
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            Get-CrashDump -Newest 5
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $script:capturedHasNewest | Should -Be $true
            $script:capturedNewestCount | Should -Be 5
        }

        It -Name 'Should leave HasNewest false when Newest is not specified' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:capturedNoNewestFlag = $ArgumentList[2]
                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.CrashDump'
                    ComputerName   = $ComputerName
                    DumpFile       = 'C:\Windows\Minidump\070526-12345-01.dmp'
                    DumpType       = 'Mini'
                    SizeMB         = 0.45
                    CreationTime   = '2026-07-05 08:00:00'
                    BugCheckCode   = $null
                    BugCheckSymbol = $null
                    Timestamp      = '2026-07-05 12:00:00'
                }
            }
            Get-CrashDump
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $script:capturedNoNewestFlag | Should -Be $false
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-CrashDump -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-CrashDump -ComputerName $null } | Should -Throw
        }

        It -Name 'Should expose ComputerName with pipeline support by value and by property name' -Test {
            $cmd = Get-Command -Name 'Get-CrashDump'
            $attr = $cmd.Parameters['ComputerName'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })[0]
            $attr.ValueFromPipeline | Should -Be $true
            $attr.ValueFromPipelineByPropertyName | Should -Be $true
        }

        It -Name 'Should expose ComputerName aliases CN, Name and DNSHostName' -Test {
            $cmd = Get-Command -Name 'Get-CrashDump'
            $aliases = $cmd.Parameters['ComputerName'].Aliases
            $aliases | Should -Contain 'CN'
            $aliases | Should -Contain 'Name'
            $aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should expose Path parameter of type string' -Test {
            $cmd = Get-Command -Name 'Get-CrashDump'
            $cmd.Parameters['Path'].ParameterType | Should -Be ([string])
        }

        It -Name 'Should expose Newest parameter of type int' -Test {
            $cmd = Get-Command -Name 'Get-CrashDump'
            $cmd.Parameters['Newest'].ParameterType | Should -Be ([int])
        }
    }
}
