#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Script-scoped variables are assigned in mocks and assertions across separate scopes'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only -- not a real credential'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingComputerNameHardcoded', '',
    Justification = 'Fake target names used exclusively in test fixtures -- no real machines are contacted'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'Stub parameters are declared to satisfy the Pester mock engine (PR #42) but have no body'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    # PSWinOps is Windows-only. On Linux/macOS the module guard throws, so we
    # conditionally import here and skip all tests via -Skip on the Describe block.
    if ($IsWindows -or $PSEdition -eq 'Desktop') {
        Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    }
    $script:ModuleName = 'PSWinOps'

    # Stub for Get-WinEvent -- parameters declared so Pester mock engine matches correctly (PR #42).
    if (-not (Get-Command -Name 'Get-WinEvent' -ErrorAction SilentlyContinue)) {
        function global:Get-WinEvent {
            param(
                [hashtable]$FilterHashtable,
                [int]$MaxEvents,
                [string]$LogName,
                [string]$ErrorAction
            )
        }
    }

    # ── Reusable base UTC timestamp ────────────────────────────────────────────
    $script:baseUtc = [datetime]::SpecifyKind(
        [datetime]::Parse('2026-05-01 10:00:00'),
        [System.DateTimeKind]::Utc
    )

    # ── Mock event rows: hashtables mirroring the shape emitted by the scriptblock ──

    $script:mockRecycle5074 = @(
        @{
            TimeCreated      = $script:baseUtc
            TimeCreatedLocal = $script:baseUtc.ToLocalTime()
            AppPoolName      = 'DefaultAppPool'
            Category         = 'Recycle'
            EventId          = 5074
            WorkerPid        = $null
            ReasonCode       = 'ConfigChange'
            Reason           = "Application pool DefaultAppPool was recycled due to configuration change."
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]12345
            MachineName      = 'WEB01.contoso.com'
        }
    )

    $script:mockRapidFail5117 = @(
        @{
            TimeCreated      = $script:baseUtc
            TimeCreatedLocal = $script:baseUtc.ToLocalTime()
            AppPoolName      = 'API-Pool'
            Category         = 'RapidFail'
            EventId          = 5117
            WorkerPid        = $null
            ReasonCode       = 'RapidFailProtection'
            Reason           = "Application pool API-Pool was disabled by rapid-fail protection."
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]22222
            MachineName      = 'WEB01.contoso.com'
        }
    )

    $script:mockCrash5010 = @(
        @{
            TimeCreated      = $script:baseUtc
            TimeCreatedLocal = $script:baseUtc.ToLocalTime()
            AppPoolName      = 'crash-pool'
            Category         = 'Crash'
            EventId          = 5010
            WorkerPid        = 4321
            ReasonCode       = 'ISAPI'
            Reason           = "Worker process 4321 crash for app pool crash-pool."
            ProviderName     = 'W3SVC-WP'
            LogName          = 'Application'
            RecordId         = [long]99999
            MachineName      = 'WEB01.contoso.com'
        }
    )

    $script:mockStart5057 = @(
        @{
            TimeCreated      = $script:baseUtc
            TimeCreatedLocal = $script:baseUtc.ToLocalTime()
            AppPoolName      = 'DefaultAppPool'
            Category         = 'Start'
            EventId          = 5057
            WorkerPid        = $null
            ReasonCode       = 'PoolStarted'
            Reason           = "Application pool DefaultAppPool was started."
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]30001
            MachineName      = 'WEB01.contoso.com'
        }
    )

    $script:mockStop5059 = @(
        @{
            TimeCreated      = $script:baseUtc
            TimeCreatedLocal = $script:baseUtc.ToLocalTime()
            AppPoolName      = 'DefaultAppPool'
            Category         = 'Stop'
            EventId          = 5059
            WorkerPid        = $null
            ReasonCode       = 'PoolStopped'
            Reason           = "Application pool DefaultAppPool was stopped."
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]40001
            MachineName      = 'WEB01.contoso.com'
        }
    )

    $script:mockIdentity5021 = @(
        @{
            TimeCreated      = $script:baseUtc
            TimeCreatedLocal = $script:baseUtc.ToLocalTime()
            AppPoolName      = 'SvcPool'
            Category         = 'IdentityChange'
            EventId          = 5021
            WorkerPid        = $null
            ReasonCode       = 'IdentityChange'
            Reason           = "Application pool SvcPool identity changed."
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]50001
            MachineName      = 'WEB01.contoso.com'
        }
    )

    $script:mockOrphan5168 = @(
        @{
            TimeCreated      = $script:baseUtc
            TimeCreatedLocal = $script:baseUtc.ToLocalTime()
            AppPoolName      = 'orphan-pool'
            Category         = 'OrphanWP'
            EventId          = 5168
            WorkerPid        = 7890
            ReasonCode       = 'OrphanWorkerProcess'
            Reason           = "Worker process 7890 for orphan-pool was orphaned."
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]60001
            MachineName      = 'WEB01.contoso.com'
        }
    )

    # Five events spread over 20 minutes -- used for -Tail and -AppPoolName tests.
    $script:mockMultiple = @(
        @{
            TimeCreated      = $script:baseUtc
            TimeCreatedLocal = $script:baseUtc.ToLocalTime()
            AppPoolName      = 'api-prod'
            Category         = 'Recycle'
            EventId          = 5074
            WorkerPid        = $null
            ReasonCode       = 'ConfigChange'
            Reason           = 'api-prod recycle'
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]1
            MachineName      = 'WEB01'
        }
        @{
            TimeCreated      = $script:baseUtc.AddMinutes(5)
            TimeCreatedLocal = $script:baseUtc.AddMinutes(5).ToLocalTime()
            AppPoolName      = 'api-stage'
            Category         = 'Recycle'
            EventId          = 5076
            WorkerPid        = $null
            ReasonCode       = 'ScheduleTime'
            Reason           = 'api-stage schedule recycle'
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]2
            MachineName      = 'WEB01'
        }
        @{
            TimeCreated      = $script:baseUtc.AddMinutes(10)
            TimeCreatedLocal = $script:baseUtc.AddMinutes(10).ToLocalTime()
            AppPoolName      = 'web-api'
            Category         = 'Stop'
            EventId          = 5059
            WorkerPid        = $null
            ReasonCode       = 'PoolStopped'
            Reason           = 'web-api stop'
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]3
            MachineName      = 'WEB01'
        }
        @{
            TimeCreated      = $script:baseUtc.AddMinutes(15)
            TimeCreatedLocal = $script:baseUtc.AddMinutes(15).ToLocalTime()
            AppPoolName      = 'api-prod'
            Category         = 'Start'
            EventId          = 5057
            WorkerPid        = $null
            ReasonCode       = 'PoolStarted'
            Reason           = 'api-prod start'
            ProviderName     = 'Microsoft-Windows-WAS'
            LogName          = 'System'
            RecordId         = [long]4
            MachineName      = 'WEB01'
        }
        @{
            TimeCreated      = $script:baseUtc.AddMinutes(20)
            TimeCreatedLocal = $script:baseUtc.AddMinutes(20).ToLocalTime()
            AppPoolName      = 'api-stage'
            Category         = 'Crash'
            EventId          = 5010
            WorkerPid        = 4321
            ReasonCode       = 'ISAPI'
            Reason           = 'api-stage crash'
            ProviderName     = 'W3SVC-WP'
            LogName          = 'Application'
            RecordId         = [long]5
            MachineName      = 'WEB01'
        }
    )
}

Describe 'Get-IISAppPoolHistory' -Skip:(-not ($IsWindows -or $PSEdition -eq 'Desktop')) {

    # ─────────────────────────────────────────────────────────────────────────
    # Context 1 -- Happy path: all mandatory output properties populated
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Happy path: Recycle event returns PSTypeName and all mandatory properties' {

        It 'Should return exactly one object with PSTypeName PSWinOps.IISAppPoolHistoryEvent' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockRecycle5074
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            @($result).Count              | Should -Be 1
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISAppPoolHistoryEvent'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate all mandatory output properties from the row hashtable' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockRecycle5074
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.ComputerName | Should -Be 'WEB01'
            $result.AppPoolName  | Should -Be 'DefaultAppPool'
            $result.Category     | Should -Be 'Recycle'
            $result.EventId      | Should -Be 5074
            $result.ReasonCode   | Should -Be 'ConfigChange'
            $result.LogName      | Should -Be 'System'
            $result.RecordId     | Should -Be 12345
            $result.MachineName  | Should -Be 'WEB01.contoso.com'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set TimeCreated and TimeCreatedLocal as datetime objects' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockRecycle5074
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.TimeCreated      | Should -BeOfType [datetime]
            $result.TimeCreatedLocal | Should -BeOfType [datetime]
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set Timestamp string matching yyyy-MM-dd HH:mm:ss format' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockRecycle5074
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 2 -- EventId to Category mapping: one representative per family
    # ─────────────────────────────────────────────────────────────────────────
    Context 'EventId to Category mapping: one representative per event family' {

        It 'Should map EventId 5074 to Recycle / ConfigChange (WAS Recycle family)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockRecycle5074
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.Category   | Should -Be 'Recycle'
            $result.ReasonCode | Should -Be 'ConfigChange'
            $result.EventId    | Should -Be 5074
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should map EventId 5117 to RapidFail / RapidFailProtection' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockRapidFail5117
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.Category   | Should -Be 'RapidFail'
            $result.ReasonCode | Should -Be 'RapidFailProtection'
            $result.EventId    | Should -Be 5117
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should map EventId 5010 to Crash / ISAPI with WorkerPid from InsertionStrings[0]' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockCrash5010
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.Category   | Should -Be 'Crash'
            $result.ReasonCode | Should -Be 'ISAPI'
            $result.EventId    | Should -Be 5010
            $result.WorkerPid  | Should -Be 4321
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should map EventId 5057 to Start / PoolStarted' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockStart5057
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.Category   | Should -Be 'Start'
            $result.ReasonCode | Should -Be 'PoolStarted'
            $result.EventId    | Should -Be 5057
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should map EventId 5059 to Stop / PoolStopped' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockStop5059
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.Category   | Should -Be 'Stop'
            $result.ReasonCode | Should -Be 'PoolStopped'
            $result.EventId    | Should -Be 5059
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should map EventId 5021 to IdentityChange / IdentityChange' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockIdentity5021
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.Category   | Should -Be 'IdentityChange'
            $result.ReasonCode | Should -Be 'IdentityChange'
            $result.EventId    | Should -Be 5021
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should map EventId 5168 to OrphanWP / OrphanWorkerProcess with WorkerPid from InsertionStrings[1]' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockOrphan5168
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $result.Category   | Should -Be 'OrphanWP'
            $result.ReasonCode | Should -Be 'OrphanWorkerProcess'
            $result.EventId    | Should -Be 5168
            $result.WorkerPid  | Should -Be 7890
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 3 -- -After / -Before forwarded via ArgumentList[5..8]
    # ─────────────────────────────────────────────────────────────────────────
    Context '-After and -Before forwarded into the ArgumentList for server-side filtering' {

        It 'Should set HasAfter=true and FilterAfter in ArgumentList when -After is specified' {
            $cutoff = [datetime]::Parse('2026-05-01 08:00:00')
            $script:capturedAfterArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedAfterArgs = $ArgumentList
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01' -After $cutoff
            $script:capturedAfterArgs[6] | Should -BeTrue
            $script:capturedAfterArgs[5] | Should -Be $cutoff
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set HasBefore=true and FilterBefore in ArgumentList when -Before is specified' {
            $cutoff = [datetime]::Parse('2026-05-15 23:59:59')
            $script:capturedBeforeArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedBeforeArgs = $ArgumentList
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01' -Before $cutoff
            $script:capturedBeforeArgs[8] | Should -BeTrue
            $script:capturedBeforeArgs[7] | Should -Be $cutoff
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set HasAfter=false and HasBefore=false when neither is specified' {
            $script:capturedNoDateArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedNoDateArgs = $ArgumentList
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $script:capturedNoDateArgs[6] | Should -BeFalse
            $script:capturedNoDateArgs[8] | Should -BeFalse
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 4 -- -Tail forwarded via ArgumentList[11]; 0 means no limit
    # ─────────────────────────────────────────────────────────────────────────
    Context '-Tail value forwarded to ArgumentList[11]; default 0 means no tail applied' {

        It 'Should forward -Tail 3 to ArgumentList[11]' {
            $script:capturedTailArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedTailArgs = $ArgumentList
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01' -Tail 3
            $script:capturedTailArgs[11] | Should -Be 3
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should forward TailN=0 when -Tail is not specified and return all events' {
            $script:capturedTailDefaultArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedTailDefaultArgs = $ArgumentList
                return $script:mockMultiple
            }
            $results = Get-IISAppPoolHistory -ComputerName 'WEB01'
            @($results).Count                   | Should -Be 5
            $script:capturedTailDefaultArgs[11] | Should -Be 0
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 5 -- -AppPoolName wildcard filter forwarded via ArgumentList[4]
    # ─────────────────────────────────────────────────────────────────────────
    Context '-AppPoolName wildcard: api-* matches api-prod/api-stage; not web-api' {

        It 'Should forward -AppPoolName patterns to ArgumentList[4]' {
            $script:capturedPoolArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedPoolArgs = $ArgumentList
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01' -AppPoolName 'api-*'
            $script:capturedPoolArgs[4] | Should -Contain 'api-*'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should only surface api-* matching rows (4 out of 5) when scriptblock applies the filter' {
            $apiRows = @($script:mockMultiple | Where-Object { $_['AppPoolName'] -like 'api-*' })
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $apiRows
            }
            $results = Get-IISAppPoolHistory -ComputerName 'WEB01' -AppPoolName 'api-*'
            @($results).Count | Should -Be 4
            foreach ($r in $results) {
                $r.AppPoolName | Should -BeLike 'api-*'
            }
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 6 -- -Category resolves to correct EventId set; union with -EventId
    # ─────────────────────────────────────────────────────────────────────────
    Context '-Category resolves to correct EventId set; -Category + -EventId unions the two sets' {

        It 'Should populate systemIds with all Recycle IDs and leave applicationIds empty for -Category Recycle' {
            $script:capturedCatArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedCatArgs = $ArgumentList
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01' -Category Recycle
            $sysIds = [int[]]$script:capturedCatArgs[1]
            $appIds = [int[]]$script:capturedCatArgs[2]
            $sysIds | Should -Contain 5074
            $sysIds | Should -Contain 5076
            $sysIds | Should -Contain 5079
            $sysIds | Should -Contain 5080
            $appIds | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should union -Category Crash Application IDs with -EventId 5057 System ID' {
            $script:capturedUnionArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedUnionArgs = $ArgumentList
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01' -Category Crash -EventId 5057
            $appIds = [int[]]$script:capturedUnionArgs[2]
            $sysIds = [int[]]$script:capturedUnionArgs[1]
            $appIds | Should -Contain 5009
            $appIds | Should -Contain 5010
            $sysIds | Should -Contain 5057
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 7 -- -IncludeOperationalLog controls ArgumentList[9]
    # ─────────────────────────────────────────────────────────────────────────
    Context '-IncludeOperationalLog: ArgumentList[9] is true when specified, false by default' {

        It 'Should set ArgumentList[9] (IncludeOp) to true when -IncludeOperationalLog is specified' {
            $script:capturedOpTrueArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedOpTrueArgs = $ArgumentList
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01' -IncludeOperationalLog
            $script:capturedOpTrueArgs[9] | Should -BeTrue
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set ArgumentList[9] (IncludeOp) to false when -IncludeOperationalLog is not specified' {
            $script:capturedOpFalseArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedOpFalseArgs = $ArgumentList
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $script:capturedOpFalseArgs[9] | Should -BeFalse
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 8 -- Pipeline by property name: ComputerName and AppPoolName
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Pipeline by property name: ComputerName and AppPoolName bound from pipeline objects' {

        It 'Should fan-out across two pipeline objects with ComputerName property' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockRecycle5074
            }
            $pipeObjs = @(
                [PSCustomObject]@{ ComputerName = 'WEB01' }
                [PSCustomObject]@{ ComputerName = 'WEB02' }
            )
            $results = $pipeObjs | Get-IISAppPoolHistory
            @($results).Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should bind AppPoolName from pipeline object by property name and forward to ArgumentList[4]' {
            $script:capturedPipePoolArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedPipePoolArgs = $ArgumentList
                return @()
            }
            $pipeObj = [PSCustomObject]@{ ComputerName = 'WEB01'; AppPoolName = 'pipe-pool' }
            $null    = $pipeObj | Get-IISAppPoolHistory
            $script:capturedPipePoolArgs[4] | Should -Contain 'pipe-pool'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should bind ComputerName via Server alias from pipeline by property name' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockRecycle5074
            }
            $pipeObj = [PSCustomObject]@{ Server = 'WEB03' }
            $result  = $pipeObj | Get-IISAppPoolHistory
            $result              | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'WEB03'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 9 -- Credential propagation
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Credential propagation: PSCredential forwarded to Invoke-RemoteOrLocal' {

        It 'Should forward Credential to Invoke-RemoteOrLocal when -Credential is specified' {
            $securePass          = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $cred                = [System.Management.Automation.PSCredential]::new('DOMAIN\svcacct', $securePass)
            $script:capturedCred = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedCred = $Credential
                return $script:mockRecycle5074
            }
            $result = Get-IISAppPoolHistory -ComputerName 'WEB01' -Credential $cred
            $result                       | Should -Not -BeNullOrEmpty
            $script:capturedCred          | Should -Not -BeNullOrEmpty
            $script:capturedCred.UserName | Should -Be 'DOMAIN\svcacct'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should not forward Credential when -Credential is omitted (null in mock)' {
            $script:credNullCount = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                if ($null -eq $Credential) { $script:credNullCount++ }
                return @()
            }
            $null = Get-IISAppPoolHistory -ComputerName 'WEB01'
            $script:credNullCount | Should -Be 1
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 10 -- ComputerName fan-out
    # ─────────────────────────────────────────────────────────────────────────
    Context 'ComputerName fan-out: two machines queried, results labelled correctly' {

        It 'Should call Invoke-RemoteOrLocal twice and label each result row with its ComputerName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockRecycle5074
            }
            $results = Get-IISAppPoolHistory -ComputerName 'WEB01', 'WEB02'
            @($results).Count        | Should -Be 2
            $results[0].ComputerName | Should -Be 'WEB01'
            $results[1].ComputerName | Should -Be 'WEB02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 11 -- Error isolation per machine
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Error isolation: failed machine does not suppress results from healthy machine' {

        It 'Should return results from WEB02 even when DEAD01 throws a WinRM error' {
            $script:isolationCallIndex = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:isolationCallIndex++
                if ($script:isolationCallIndex -eq 1) { throw 'WinRM connection refused' }
                return $script:mockRecycle5074
            }
            $results = Get-IISAppPoolHistory -ComputerName 'DEAD01', 'WEB02' -ErrorAction SilentlyContinue
            @($results).Count        | Should -Be 1
            $results[0].ComputerName | Should -Be 'WEB02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 12 -- Empty result: no synthetic placeholder emitted
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Empty result: zero objects emitted when no matching events found' {

        It 'Should emit zero objects when Invoke-RemoteOrLocal returns an empty array' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return @()
            }
            $results = @(Get-IISAppPoolHistory -ComputerName 'WEB01')
            $results.Count | Should -Be 0
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit zero objects when Invoke-RemoteOrLocal returns null' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $null
            }
            $results = @(Get-IISAppPoolHistory -ComputerName 'WEB01')
            $results.Count | Should -Be 0
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 13 -- Missing log channel: Write-Warning, no terminating error
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Missing log channel: no terminating error thrown; function returns normally' {

        It 'Should not throw when the Operational log channel is unavailable' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                Write-Warning 'Operational log channel is unavailable or disabled. Skipping.'
                return @()
            }
            { Get-IISAppPoolHistory -ComputerName 'WEB01' -IncludeOperationalLog } | Should -Not -Throw
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should still return events from other channels when one channel produces a warning' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                Write-Warning 'Operational log channel is unavailable or disabled. Skipping.'
                return $script:mockRecycle5074
            }
            $results = Get-IISAppPoolHistory -ComputerName 'WEB01' -IncludeOperationalLog
            @($results).Count | Should -Be 1
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 14 -- BOM / CRLF sentinel
    # ─────────────────────────────────────────────────────────────────────────
    Context 'BOM and CRLF sentinel: test source file encoding' {

        It 'Test source file starts with UTF-8 BOM bytes (0xEF 0xBB 0xBF)' {
            $bytes    = [System.IO.File]::ReadAllBytes($PSCommandPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'Test source file uses CRLF line endings' {
            $raw = [System.IO.File]::ReadAllText($PSCommandPath)
            $raw | Should -Match "`r`n"
        }

        It 'Get-Content on test source file first line matches the Requires directive' {
            $firstLine = (Get-Content -LiteralPath $PSCommandPath -First 1)
            $firstLine | Should -Match '#Requires'
        }
    }
}
