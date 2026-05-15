#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Script-scoped variables are assigned in mocks and assertions across separate scopes'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only — not a real credential'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingComputerNameHardcoded', '',
    Justification = 'Fake target names used exclusively in test fixtures — no real machines are contacted'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'Stub parameters are declared to satisfy the Pester mock engine (PR #42) but have no body'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # IIS module command stubs — parameters declared explicitly so the Pester mock
    # engine can match arguments correctly (project convention, see PR #42).
    if (-not (Get-Command -Name 'Get-Website' -ErrorAction SilentlyContinue)) {
        function global:Get-Website { param([string]$Name) }
    }
    if (-not (Get-Command -Name 'Get-WebApplication' -ErrorAction SilentlyContinue)) {
        function global:Get-WebApplication { param([string]$Site, [string]$Name) }
    }
    if (-not (Get-Command -Name 'Get-IISAppPool' -ErrorAction SilentlyContinue)) {
        function global:Get-IISAppPool { param([string]$Name) }
    }
    if (-not (Get-Command -Name 'Get-IISSite' -ErrorAction SilentlyContinue)) {
        function global:Get-IISSite { param([string]$Name) }
    }
    if (-not (Get-Command -Name 'Get-IISServerManager' -ErrorAction SilentlyContinue)) {
        function global:Get-IISServerManager { param() }
    }

    $script:ModuleName = 'PSWinOps'

    # ── Reusable mock payloads ────────────────────────────────────────────────

    $script:mockRunning = @(
        @{
            ProcessId       = 1234
            AppPoolName     = 'DefaultAppPool'
            Sites           = @('Default Web Site')
            Applications    = @()
            Identity        = 'ApplicationPoolIdentity'
            IdentityType    = 'ApplicationPoolIdentity'
            StartTime       = (Get-Date).AddHours(-2)
            UptimeSeconds   = [long]7200
            CPUSeconds      = [double]12.5
            WorkingSetMB    = [long]256
            PrivateMemoryMB = [long]128
            VirtualMemoryMB = [long]512
            ThreadCount     = 32
            HandleCount     = 512
            CommandLine     = 'c:\windows\system32\inetsrv\w3wp.exe -ap "DefaultAppPool"'
            Status          = 'Running'
            ErrorMessage    = $null
        }
    )

    $script:mockOrphaned = @(
        @{
            ProcessId       = 5678
            AppPoolName     = ''
            Sites           = @()
            Applications    = @()
            Identity        = ''
            IdentityType    = 'Unknown'
            StartTime       = $null
            UptimeSeconds   = [long]0
            CPUSeconds      = [double]0
            WorkingSetMB    = [long]0
            PrivateMemoryMB = [long]0
            VirtualMemoryMB = [long]0
            ThreadCount     = 0
            HandleCount     = 0
            CommandLine     = ''
            Status          = 'Orphaned'
            ErrorMessage    = $null
        }
    )

    $script:mockFailed = @(
        @{
            ProcessId       = $null
            AppPoolName     = $null
            Sites           = @()
            Applications    = @()
            Identity        = $null
            IdentityType    = $null
            StartTime       = $null
            UptimeSeconds   = $null
            CPUSeconds      = $null
            WorkingSetMB    = $null
            PrivateMemoryMB = $null
            VirtualMemoryMB = $null
            ThreadCount     = $null
            HandleCount     = $null
            CommandLine     = $null
            Status          = 'Failed'
            ErrorMessage    = 'CIM query timed out'
        }
    )

    $script:mockIISNotInstalled = @(
        @{
            ProcessId       = $null
            AppPoolName     = $null
            Sites           = @()
            Applications    = @()
            Identity        = $null
            IdentityType    = $null
            StartTime       = $null
            UptimeSeconds   = $null
            CPUSeconds      = $null
            WorkingSetMB    = $null
            PrivateMemoryMB = $null
            VirtualMemoryMB = $null
            ThreadCount     = $null
            HandleCount     = $null
            CommandLine     = $null
            Status          = 'IISNotInstalled'
            ErrorMessage    = 'W3SVC service not found: Cannot find service'
        }
    )

    $script:mockNoWorkerProcess = @(
        @{
            ProcessId       = $null
            AppPoolName     = $null
            Sites           = @()
            Applications    = @()
            Identity        = $null
            IdentityType    = $null
            StartTime       = $null
            UptimeSeconds   = $null
            CPUSeconds      = $null
            WorkingSetMB    = $null
            PrivateMemoryMB = $null
            VirtualMemoryMB = $null
            ThreadCount     = $null
            HandleCount     = $null
            CommandLine     = $null
            Status          = 'NoWorkerProcess'
            ErrorMessage    = $null
        }
    )
}

Describe 'Get-IISWorkerProcess' {

    # ── Context 1 ─────────────────────────────────────────────────────────────
    # Happy path: worker process is Running and all output properties are set.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Happy path: Running worker process enriched with pool and resource data' {

        It 'Should return Status Running with correct PSTypeName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockRunning }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01'
            $result.Status | Should -Be 'Running'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISWorkerProcess'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate AppPoolName, Sites and ProcessId from mock data' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockRunning }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01'
            $result.AppPoolName | Should -Be 'DefaultAppPool'
            $result.ProcessId   | Should -Be 1234
            $result.Sites       | Should -Contain 'Default Web Site'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set ComputerName to upper-case display form' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockRunning }
            $result = Get-IISWorkerProcess -ComputerName 'web01'
            $result.ComputerName | Should -Be 'WEB01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate resource metrics (WorkingSetMB, ThreadCount, HandleCount)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockRunning }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01'
            $result.WorkingSetMB    | Should -Be 256
            $result.PrivateMemoryMB | Should -Be 128
            $result.VirtualMemoryMB | Should -Be 512
            $result.ThreadCount     | Should -Be 32
            $result.HandleCount     | Should -Be 512
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate identity and uptime fields' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockRunning }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01'
            $result.Identity      | Should -Be 'ApplicationPoolIdentity'
            $result.IdentityType  | Should -Be 'ApplicationPoolIdentity'
            $result.UptimeSeconds | Should -Be 7200
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 2 ─────────────────────────────────────────────────────────────
    # Status = Orphaned: w3wp.exe running but its app pool is gone from IIS.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Status = Orphaned: w3wp running but app pool no longer exists in IIS config' {

        It 'Should return Status Orphaned with empty AppPoolName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockOrphaned }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01'
            $result.Status      | Should -Be 'Orphaned'
            $result.AppPoolName | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 3 ─────────────────────────────────────────────────────────────
    # Status = Failed: exception thrown inside the scriptblock.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Status = Failed: exception during data collection' {

        It 'Should return Status Failed with a non-empty ErrorMessage' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockFailed }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01'
            $result.Status       | Should -Be 'Failed'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 4 ─────────────────────────────────────────────────────────────
    # Status = IISNotInstalled: W3SVC service absent on target.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Status = IISNotInstalled: W3SVC service not found on target' {

        It 'Should return Status IISNotInstalled and ErrorMessage mentioning W3SVC' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockIISNotInstalled }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01'
            $result.Status       | Should -Be 'IISNotInstalled'
            $result.ErrorMessage | Should -Match 'W3SVC'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 5 ─────────────────────────────────────────────────────────────
    # Status = NoWorkerProcess: IIS installed but no w3wp.exe currently running.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Status = NoWorkerProcess: IIS installed but no w3wp.exe currently running' {

        It 'Should return Status NoWorkerProcess with null ProcessId' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockNoWorkerProcess }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01'
            $result.Status    | Should -Be 'NoWorkerProcess'
            $result.ProcessId | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 6 ─────────────────────────────────────────────────────────────
    # ShouldProcess: Get-IISWorkerProcess is read-only; -WhatIf makes 0 mutations.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'ShouldProcess: read-only function — -WhatIf makes 0 mutations' {

        It 'Should throw when called with -WhatIf (SupportsShouldProcess not declared)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return @() }
            { Get-IISWorkerProcess -WhatIf -ErrorAction Stop } | Should -Throw
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    # ── Context 7 ─────────────────────────────────────────────────────────────
    # Pipeline by property name: ComputerName and DNSHostName alias binding.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Pipeline by property name (ComputerName / DNSHostName alias)' {

        It 'Should fan-out across pipeline objects bound by ComputerName property' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockRunning }
            $pipeObjects = @(
                [PSCustomObject]@{ ComputerName = 'WEB01' }
                [PSCustomObject]@{ ComputerName = 'WEB02' }
            )
            $results = $pipeObjects | Get-IISWorkerProcess
            @($results).Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should bind a pipeline object via the DNSHostName alias and set ComputerName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockRunning }
            $pipeObj = [PSCustomObject]@{ DNSHostName = 'WEB03' }
            $result  = $pipeObj | Get-IISWorkerProcess
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'WEB03'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 8 ─────────────────────────────────────────────────────────────
    # Credential propagation: PSCredential must reach Invoke-RemoteOrLocal.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Credential propagation: PSCredential forwarded to Invoke-RemoteOrLocal' {

        It 'Should forward Credential to Invoke-RemoteOrLocal and return results' {
            $securePass          = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $cred                = [System.Management.Automation.PSCredential]::new('DOMAIN\svcacct', $securePass)
            $script:capturedCred = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedCred = $Credential
                return $script:mockRunning
            }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01' -Credential $cred
            $result.Status                | Should -Be 'Running'
            $script:capturedCred          | Should -Not -BeNullOrEmpty
            $script:capturedCred.UserName | Should -Be 'DOMAIN\svcacct'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 9 ─────────────────────────────────────────────────────────────
    # ComputerName fan-out: multiple machines queried in sequence.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'ComputerName fan-out: two machines queried in sequence' {

        It 'Should return one result row per machine with correct ComputerName labels' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockRunning }
            $results = Get-IISWorkerProcess -ComputerName 'WEB01', 'WEB02'
            @($results).Count        | Should -Be 2
            $results[0].ComputerName | Should -Be 'WEB01'
            $results[1].ComputerName | Should -Be 'WEB02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ── Context 10 ────────────────────────────────────────────────────────────
    # Error isolation: a failure on one machine must not suppress other results.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Error isolation: failed machine does not suppress results from healthy machine' {

        It 'Should return results for the healthy machine when the first machine throws' {
            $script:isolationCallCount = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:isolationCallCount++
                if ($script:isolationCallCount -eq 1) { throw 'WinRM connection refused' }
                return $script:mockRunning
            }
            $results = Get-IISWorkerProcess -ComputerName 'FAIL01', 'WEB02' -ErrorAction SilentlyContinue
            @($results).Count     | Should -Be 1
            $results.ComputerName | Should -Be 'WEB02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ── Context 11 ────────────────────────────────────────────────────────────
    # BOM/CRLF sentinel: test file must be UTF-8 BOM with CRLF line endings.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'BOM/CRLF sentinel: test file encoding compliance' {

        It 'Should have UTF-8 BOM as first three bytes (EF BB BF)' {
            $filePath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-IISWorkerProcess.Tests.ps1'
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'Should use CRLF line endings throughout the test file' {
            $filePath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-IISWorkerProcess.Tests.ps1'
            $raw = [System.IO.File]::ReadAllText($filePath)
            $raw | Should -Match "`r`n"
        }
    }

    # ── Context 12 ────────────────────────────────────────────────────────────
    # Timestamp: each result must carry a yyyy-MM-dd HH:mm:ss formatted string.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Timestamp property matches yyyy-MM-dd HH:mm:ss format' {

        It 'Should produce Timestamp matching yyyy-MM-dd HH:mm:ss pattern' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockRunning }
            $result = Get-IISWorkerProcess -ComputerName 'WEB01'
            $result.Timestamp | Should -Match "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 13 ────────────────────────────────────────────────────────────
    # AppPoolName filter: array forwarded as ArgumentList[0] to Invoke-RemoteOrLocal.
    # ─────────────────────────────────────────────────────────────────────────
    Context 'AppPoolName filter: filter array forwarded as ArgumentList[0] to Invoke-RemoteOrLocal' {

        It 'Should pass AppPoolName patterns as first element of ArgumentList' {
            $script:capturedPoolFilter = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedPoolFilter = $ArgumentList[0]
                return @()
            }
            Get-IISWorkerProcess -ComputerName 'WEB01' -AppPoolName 'API*', 'DefaultAppPool'
            $script:capturedPoolFilter | Should -Contain 'API*'
            $script:capturedPoolFilter | Should -Contain 'DefaultAppPool'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }
}
