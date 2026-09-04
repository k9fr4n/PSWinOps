#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Create proxy functions for AD cmdlets not available on CI runners
    if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
        function global:Get-ADUser { param($Identity, $Properties, $Server, $Credential) }
    }
    if (-not (Get-Command -Name 'Get-ADDomainController' -ErrorAction SilentlyContinue)) {
        function global:Get-ADDomainController { param($Discover, $Service) }
    }
    & (Get-Module -Name 'PSWinOps') {
        if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
            function script:Get-ADUser { param($Identity, $Properties, $Server, $Credential) }
        }
        if (-not (Get-Command -Name 'Get-ADDomainController' -ErrorAction SilentlyContinue)) {
            function script:Get-ADDomainController { param($Discover, $Service) }
        }
    }

    function New-FakeLockoutEvent {
        param(
            [datetime]$TimeCreated,
            [string]$TargetUserName,
            [string]$CallerComputer,
            [string]$TargetSid,
            [string]$MachineName = 'DC01.contoso.com',
            [int]$Id = 4740
        )
        $props = [System.Collections.Generic.List[object]]::new()
        $props.Add([PSCustomObject]@{ Value = $TargetUserName })
        $props.Add([PSCustomObject]@{ Value = $CallerComputer })
        $props.Add([PSCustomObject]@{ Value = $TargetSid })
        [PSCustomObject]@{
            Id          = $Id
            TimeCreated = $TimeCreated
            MachineName = $MachineName
            Properties  = $props.ToArray()
        }
    }
}

Describe -Name 'Get-ADLockoutSource' -Fixture {

    Context -Name 'Happy path - SID matched' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ HostName = @('DC01.contoso.com') }
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    SamAccountName = 'jsmith'
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-1111-2222-3333-1001' }
                }
            }

            $script:evtMatchNewer = New-FakeLockoutEvent -TimeCreated (Get-Date '2026-09-01 08:00:00') `
                -TargetUserName 'jsmith' -CallerComputer 'WKS01' -TargetSid 'S-1-5-21-1111-2222-3333-1001'
            $script:evtMatchOlder = New-FakeLockoutEvent -TimeCreated (Get-Date '2026-08-01 08:00:00') `
                -TargetUserName 'jsmith' -CallerComputer 'WKS02' -TargetSid 'S-1-5-21-1111-2222-3333-1001'
            $script:evtOtherSid = New-FakeLockoutEvent -TimeCreated (Get-Date '2026-09-02 08:00:00') `
                -TargetUserName 'other' -CallerComputer 'WKS03' -TargetSid 'S-1-5-21-9999-0000-0000-9999'

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:evtOtherSid, $script:evtMatchOlder, $script:evtMatchNewer)
            }
        }

        It -Name 'Should return only the events matching the resolved SID as PSWinOps.ADLockoutSource' -Test {
            $result = Get-ADLockoutSource -Identity 'jsmith'
            $result.Count | Should -Be 2
            $result | ForEach-Object -Process {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADLockoutSource'
            }
        }

        It -Name 'Should populate all required output properties' -Test {
            $result = Get-ADLockoutSource -Identity 'jsmith'
            $row = $result[0]
            $row.ComputerName | Should -Be 'DC01.contoso.com'
            $row.DomainController | Should -Be 'DC01.contoso.com'
            $row.UserName | Should -Be 'jsmith'
            $row.SamAccountName | Should -Be 'jsmith'
            $row.LockoutSource | Should -Be 'WKS01'
            $row.EventId | Should -Be 4740
            $row.LockoutTime | Should -BeOfType [datetime]
            $row.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}[+-]\d{2}:\d{2}$"
        }

        It -Name 'Should sort results by LockoutTime descending' -Test {
            $result = Get-ADLockoutSource -Identity 'jsmith'
            $result[0].LockoutSource | Should -Be 'WKS01'
            $result[1].LockoutSource | Should -Be 'WKS02'
            $result[0].LockoutTime | Should -BeGreaterThan $result[1].LockoutTime
        }
    }

    Context -Name 'No matching 4740 events' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ HostName = @('DC01.contoso.com') }
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    SamAccountName = 'jsmith'
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-1111-2222-3333-1001' }
                }
            }
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                throw 'No events were found that match the specified selection criteria.'
            }
        }

        It -Name 'Should return nothing and write no error' -Test {
            $out = @(Get-ADLockoutSource -Identity 'jsmith' -ErrorAction Stop 2>&1)
            $out.Count | Should -Be 0
        }
    }

    Context -Name '-After and -MaxEvents passed through to Get-WinEvent' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ HostName = @('DC01.contoso.com') }
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    SamAccountName = 'jsmith'
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-1111-2222-3333-1001' }
                }
            }
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { @() }
        }

        It -Name 'Should pass After as FilterHashtable StartTime and MaxEvents through' -Test {
            $afterDate = Get-Date '2026-01-01 00:00:00'
            Get-ADLockoutSource -Identity 'jsmith' -After $afterDate -MaxEvents 50
            Should -Invoke -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $MaxEvents -eq 50 -and
                $FilterHashtable['LogName'] -eq 'Security' -and
                $FilterHashtable['Id'] -eq 4740 -and
                $FilterHashtable['StartTime'] -eq $afterDate
            }
        }
    }

    Context -Name '-Server explicit bypasses PDC discovery' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ HostName = @('DC01.contoso.com') }
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    SamAccountName = 'jsmith'
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-1111-2222-3333-1001' }
                }
            }
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { @() }
        }

        It -Name 'Should not call Get-ADDomainController when -Server is supplied' -Test {
            Get-ADLockoutSource -Identity 'jsmith' -Server 'DC02.contoso.com'
            Should -Invoke -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should query Get-WinEvent against the explicit server' -Test {
            Get-ADLockoutSource -Identity 'jsmith' -Server 'DC02.contoso.com'
            Should -Invoke -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'DC02.contoso.com'
            }
        }
    }

    Context -Name 'Default PDC discovery when -Server is omitted' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ HostName = @('DC01.contoso.com') }
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    SamAccountName = 'jsmith'
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-1111-2222-3333-1001' }
                }
            }
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { @() }
        }

        It -Name 'Should discover the PDC Emulator once' -Test {
            Get-ADLockoutSource -Identity 'jsmith'
            Should -Invoke -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Discover -eq $true -and $Service -eq 'PrimaryDC'
            }
        }

        It -Name 'Should query Get-WinEvent against the discovered PDC' -Test {
            Get-ADLockoutSource -Identity 'jsmith'
            Should -Invoke -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'DC01.contoso.com'
            }
        }
    }

    Context -Name 'Pipeline of multiple identities' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ HostName = @('DC01.contoso.com') }
            }

            $script:fakeUsers = @{
                'jdoe'   = [PSCustomObject]@{ SamAccountName = 'jdoe'; SID = [PSCustomObject]@{ Value = 'S-1-5-21-1111-1' } }
                'asmith' = [PSCustomObject]@{ SamAccountName = 'asmith'; SID = [PSCustomObject]@{ Value = 'S-1-5-21-1111-2' } }
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                $script:fakeUsers[$Identity]
            }

            $script:evtJdoe = New-FakeLockoutEvent -TimeCreated (Get-Date '2026-09-01 08:00:00') `
                -TargetUserName 'jdoe' -CallerComputer 'WKS01' -TargetSid 'S-1-5-21-1111-1'
            $script:evtAsmith = New-FakeLockoutEvent -TimeCreated (Get-Date '2026-09-01 09:00:00') `
                -TargetUserName 'asmith' -CallerComputer 'WKS02' -TargetSid 'S-1-5-21-1111-2'
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:evtJdoe, $script:evtAsmith)
            }
        }

        It -Name 'Should process identities piped by value' -Test {
            $result = 'jdoe', 'asmith' | Get-ADLockoutSource
            ($result | Select-Object -ExpandProperty SamAccountName) | Should -Contain 'jdoe'
            ($result | Select-Object -ExpandProperty SamAccountName) | Should -Contain 'asmith'
        }

        It -Name 'Should process identities piped by property name via the SamAccountName alias' -Test {
            $lockedAccounts = @(
                [PSCustomObject]@{ SamAccountName = 'jdoe' }
                [PSCustomObject]@{ SamAccountName = 'asmith' }
            )
            $result = $lockedAccounts | Get-ADLockoutSource
            ($result | Select-Object -ExpandProperty SamAccountName) | Should -Contain 'jdoe'
            ($result | Select-Object -ExpandProperty SamAccountName) | Should -Contain 'asmith'
        }
    }

    Context -Name 'Per-identity Get-ADUser failure is isolated' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ HostName = @('DC01.contoso.com') }
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                if ($Identity -eq 'baduser') {
                    throw 'Cannot find an object with identity: baduser'
                }
                [PSCustomObject]@{
                    SamAccountName = 'jsmith'
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-1111-2222-3333-1001' }
                }
            }
            $script:evtMatch = New-FakeLockoutEvent -TimeCreated (Get-Date '2026-09-01 08:00:00') `
                -TargetUserName 'jsmith' -CallerComputer 'WKS01' -TargetSid 'S-1-5-21-1111-2222-3333-1001'
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { @($script:evtMatch) }
        }

        It -Name 'Should write an error for the failing identity and still return the succeeding one' -Test {
            $out = 'baduser', 'jsmith' | Get-ADLockoutSource -ErrorAction Continue 2>&1
            $errors = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $successes = @($out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
            $errors.Count | Should -BeGreaterThan 0
            $successes.Count | Should -Be 1
            $successes[0].SamAccountName | Should -Be 'jsmith'
        }
    }

    Context -Name 'Remote Security log access denied is isolated per identity' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ HostName = @('DC01.contoso.com') }
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    SamAccountName = $Identity
                    SID            = [PSCustomObject]@{ Value = "S-1-5-21-$Identity" }
                }
            }
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                throw 'Access is denied'
            }
        }

        It -Name 'Should write an error per identity without halting the pipeline' -Test {
            $out = 'jdoe', 'asmith' | Get-ADLockoutSource -ErrorAction Continue 2>&1
            $errors = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $errors.Count | Should -Be 2
        }
    }

    Context -Name 'Credential propagation' -Fixture {

        BeforeAll {
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'PSWinOps'
            Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ HostName = @('DC01.contoso.com') }
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    SamAccountName = 'jsmith'
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-1111-2222-3333-1001' }
                }
            }
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { @() }
        }

        It -Name 'Should pass Credential to both Get-ADUser and Get-WinEvent' -Test {
            $securePwd = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('DOMAIN\svc', $securePwd)
            Get-ADLockoutSource -Identity 'jsmith' -Credential $cred
            Should -Invoke -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $cred
            }
            Should -Invoke -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $cred
            }
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when Identity is an empty string' -Test {
            { Get-ADLockoutSource -Identity '' } | Should -Throw
        }

        It -Name 'Should throw when Identity is null' -Test {
            { Get-ADLockoutSource -Identity $null } | Should -Throw
        }

        It -Name 'Should throw when MaxEvents is below the valid range' -Test {
            { Get-ADLockoutSource -Identity 'jsmith' -MaxEvents 0 } | Should -Throw
        }

        It -Name 'Should expose Identity with pipeline support by value and by property name' -Test {
            $cmd = Get-Command -Name 'Get-ADLockoutSource'
            $attr = $cmd.Parameters['Identity'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })[0]
            $attr.ValueFromPipeline | Should -Be $true
            $attr.ValueFromPipelineByPropertyName | Should -Be $true
        }

        It -Name 'Should expose the SamAccountName alias on Identity' -Test {
            $cmd = Get-Command -Name 'Get-ADLockoutSource'
            $cmd.Parameters['Identity'].Aliases | Should -Contain 'SamAccountName'
        }
    }
}
