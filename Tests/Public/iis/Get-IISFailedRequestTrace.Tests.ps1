#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Script-scoped variables are assigned in BeforeAll and consumed in It blocks across separate scopes'
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
    # PSWinOps is Windows-only. On Linux/macOS the import guard throws, so we
    # conditionally import here and skip all tests via -Skip on the Describe block.
    if ($IsWindows -or $PSEdition -eq 'Desktop') {
        Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    }
    $script:ModuleName = 'PSWinOps'

    # ---------------------------------------------------------------------------
    # Helper: build a sentinel (non-Parsed) hashtable row mirroring the
    # structure emitted by the scriptblock for non-happy-path Status values.
    # ---------------------------------------------------------------------------
    function script:New-SentinelRow {
        param([string]$Status, [string]$Detail, [string]$SiteName)
        return @{
            SiteName           = $SiteName
            SiteId             = $null
            AppPoolName        = $null
            ProcessId          = $null
            Url                = $null
            Verb               = $null
            StatusCode         = $null
            SubStatus          = $null
            Win32Status        = $null
            TriggerStatusCode  = $null
            FailureReason      = $null
            TimeTaken          = $null
            Timestamp          = $null
            ErrorModule        = $null
            ErrorNotification  = $null
            ErrorMessage       = $null
            EventCount         = $null
            Events             = $null
            TraceFile          = $null
            Status             = $Status
            ErrorMessageDetail = $Detail
        }
    }

    # ---------------------------------------------------------------------------
    # Reusable mock payloads -- returned by the mocked Invoke-RemoteOrLocal.
    # These are hashtables matching the shape the inner scriptblock returns.
    # ---------------------------------------------------------------------------

    $script:mockParsed = @(
        @{
            SiteName           = 'Default Web Site'
            SiteId             = 1
            AppPoolName        = 'DefaultAppPool'
            ProcessId          = 4812
            Url                = '/api/orders?id=42'
            Verb               = 'GET'
            StatusCode         = 500
            SubStatus          = $null
            Win32Status        = [long]64
            TriggerStatusCode  = 500
            FailureReason      = 'STATUS_CODE'
            TimeTaken          = 3521
            Timestamp          = [datetime]::SpecifyKind(
                                     [datetime]::Parse('2026-05-15 10:00:00'),
                                     [System.DateTimeKind]::Utc)
            ErrorModule        = 'ManagedPipelineHandler'
            ErrorNotification  = 'EXECUTE_REQUEST_HANDLER'
            ErrorMessage       = 'ManagedPipelineHandler'
            EventCount         = 8
            Events             = $null
            TraceFile          = 'C:\inetpub\logs\FailedReqLogFiles\W3SVC1\fr000001.xml'
            Status             = 'Parsed'
            ErrorMessageDetail = $null
        }
    )

    $script:mockNoTraces = @(
        script:New-SentinelRow 'NoTraces' `
            No fr*.xml files found in 'C:\inetpub\logs\FailedReqLogFiles\W3SVC1'. `
            'Default Web Site'
    )

    $script:mockSiteNotFound = @(
        script:New-SentinelRow 'SiteNotFound' `
            'No matching IIS site found for the specified SiteName/SiteId filters.' `
            $null
    )

    $script:mockFolderNotFound = @(
        script:New-SentinelRow 'FolderNotFound' `
            'FREB folder not found: C:\freb_override\missing.' `
            $null
    )

    $script:mockIISNotInstalled = @(
        script:New-SentinelRow 'IISNotInstalled' `
            'WebAdministration / IISAdministration unavailable and appcmd.exe not found.' `
            $null
    )

    $script:mockFailed = @(
        script:New-SentinelRow 'Failed' `
            'Unexpected exception: Access is denied.' `
            $null
    )

    $script:mockParsedWeb01 = @(
        @{
            SiteName = 'Default Web Site'; SiteId = 1; AppPoolName = 'DefaultAppPool'
            ProcessId = 1000; Url = '/health'; Verb = 'GET'; StatusCode = 503
            SubStatus = $null; Win32Status = $null; TriggerStatusCode = 503
            FailureReason = 'STATUS_CODE'; TimeTaken = 800
            Timestamp = [datetime]::SpecifyKind(
                [datetime]::Parse('2026-05-15 09:00:00'),
                [System.DateTimeKind]::Utc)
            ErrorModule = $null; ErrorNotification = $null; ErrorMessage = $null
            EventCount = 4; Events = $null
            TraceFile = 'C:\inetpub\logs\FailedReqLogFiles\W3SVC1\fr000001.xml'
            Status = 'Parsed'; ErrorMessageDetail = $null
        }
    )

    $script:mockParsedWeb02 = @(
        @{
            SiteName = 'api.contoso.com'; SiteId = 2; AppPoolName = 'APIPool'
            ProcessId = 2000; Url = '/api/v1/data'; Verb = 'POST'; StatusCode = 502
            SubStatus = $null; Win32Status = $null; TriggerStatusCode = 502
            FailureReason = 'STATUS_CODE'; TimeTaken = 15000
            Timestamp = [datetime]::SpecifyKind(
                [datetime]::Parse('2026-05-15 09:05:00'),
                [System.DateTimeKind]::Utc)
            ErrorModule = $null; ErrorNotification = $null; ErrorMessage = $null
            EventCount = 6; Events = $null
            TraceFile = 'C:\inetpub\logs\FailedReqLogFiles\W3SVC2\fr000001.xml'
            Status = 'Parsed'; ErrorMessageDetail = $null
        }
    )

    # ---------------------------------------------------------------------------
    # Fixture FREB XML temp dir (Context 2 passthrough tests, Windows only).
    # On Linux the module import guard in PSWinOps.psm1 throws before this
    # BeforeAll runs, so the fixture code is unreachable on non-Windows.
    # ---------------------------------------------------------------------------
    $script:frebTempDir = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        ('PSWinOps_FREB_' + [System.Guid]::NewGuid().ToString('N')))

    try {
        [void][System.IO.Directory]::CreateDirectory($script:frebTempDir)

        # Minimal structurally valid FREB trace file:
        #   statusCode='404.7'  -> StatusCode=404, SubStatus=7
        #   3 events: Verbose BEGIN_REQUEST, Error MODULE_SET_RESPONSE_ERROR_STATUS,
        #             Information GENERAL_REQUEST_END (Win32Status=2)
        $frebXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<failedRequest url="/api/test" siteId="1" appPoolId="DefaultAppPool"
               processId="1234" verb="GET" remoteUserName="" userName=""
               activityId="{00000000-0000-0000-1900-0080000000FA}"
               statusCode="404.7" subStatusCode="7" win32Status="0"
               triggerStatusCode="404" timeTaken="150"
               failureReason="STATUS_CODE" date="2026-05-15" time="10:00:00">
  <Event>
    <System>
      <Provider Name="WWW Server" Guid="{3A2A4E84-4C21-4981-AE10-3FDA0D9B0F83}"/>
      <EventID>1</EventID>
      <Version>1</Version>
      <Level>5</Level>
      <Opcode>1</Opcode>
      <TimeCreated SystemTime="2026-05-15T10:00:00.000Z"/>
    </System>
    <RenderingInfo>
      <Level>Verbose</Level>
      <Opcode>BEGIN_REQUEST</Opcode>
    </RenderingInfo>
    <EventData>
      <Data Name="ContextId">{00000000}</Data>
      <Data Name="RequestURL">http://web01/api/test</Data>
      <Data Name="RequestVerb">GET</Data>
    </EventData>
  </Event>
  <Event>
    <System>
      <Provider Name="ManagedPipelineHandler" Guid="{00000000-0000-0000-0000-000000000000}"/>
      <EventID>2</EventID>
      <Version>1</Version>
      <Level>3</Level>
      <Opcode>0</Opcode>
      <TimeCreated SystemTime="2026-05-15T10:00:00.120Z"/>
    </System>
    <RenderingInfo>
      <Level>Error</Level>
      <Opcode>MODULE_SET_RESPONSE_ERROR_STATUS</Opcode>
    </RenderingInfo>
    <EventData>
      <Data Name="ModuleName">ManagedPipelineHandler</Data>
      <Data Name="Notification">EXECUTE_REQUEST_HANDLER</Data>
      <Data Name="ErrorCode">0x80070003</Data>
    </EventData>
  </Event>
  <Event>
    <System>
      <Provider Name="WWW Server" Guid="{3A2A4E84-4C21-4981-AE10-3FDA0D9B0F83}"/>
      <EventID>3</EventID>
      <Version>1</Version>
      <Level>4</Level>
      <Opcode>0</Opcode>
      <TimeCreated SystemTime="2026-05-15T10:00:00.150Z"/>
    </System>
    <RenderingInfo>
      <Level>Information</Level>
      <Opcode>GENERAL_REQUEST_END</Opcode>
    </RenderingInfo>
    <EventData>
      <Data Name="BytesSent">0</Data>
      <Data Name="BytesReceived">256</Data>
      <Data Name="Win32Status">2</Data>
    </EventData>
  </Event>
</failedRequest>
"@
        $frebXmlPath = [System.IO.Path]::Combine($script:frebTempDir, 'fr000001.xml')
        [System.IO.File]::WriteAllText($frebXmlPath, $frebXml, [System.Text.Encoding]::UTF8)
    }
    catch {
        Write-Warning -Message "BeforeAll: could not create FREB fixture dir: $($_.Exception.Message)"
    }
}

AfterAll {
    if ($null -ne $script:frebTempDir -and (Test-Path -LiteralPath $script:frebTempDir)) {
        Remove-Item -LiteralPath $script:frebTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IISFailedRequestTrace' -Skip:(-not ($IsWindows -or $PSEdition -eq 'Desktop')) {

    # ==========================================================================
    # Context 1: Happy path -- Status=Parsed, all output properties present
    # ==========================================================================
    Context 'Happy path: Status=Parsed with all output properties populated' {

        It 'Should return a PSCustomObject with PSTypeName PSWinOps.IISFailedRequestTrace' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISFailedRequestTrace'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should stamp ComputerName from the caller parameter onto every result row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.ComputerName | Should -Be 'WEB01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate SiteName, StatusCode, Verb, TimeTaken, TraceFile, FailureReason and ErrorModule' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.SiteName      | Should -Be 'Default Web Site'
            $result.StatusCode    | Should -Be 500
            $result.Verb          | Should -Be 'GET'
            $result.TimeTaken     | Should -Be 3521
            $result.TraceFile     | Should -Not -BeNullOrEmpty
            $result.FailureReason | Should -Be 'STATUS_CODE'
            $result.ErrorModule   | Should -Be 'ManagedPipelineHandler'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit SubStatus as $null when the trace statusCode has no substatus' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.SubStatus | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit Timestamp as a UTC DateTime with correct formatted value' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.Timestamp           | Should -BeOfType [datetime]
            $result.Timestamp.Kind      | Should -Be ([System.DateTimeKind]::Utc)
            $result.Timestamp.ToString('yyyy-MM-dd HH:mm:ss') | Should -Be '2026-05-15 10:00:00'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit Events as $null when -IncludeEvents is not specified' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.Events | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ==========================================================================
    # Context 2: XML fixture parsing -- actual XmlReader execution via passthrough
    # Passthrough mock invokes the real inner scriptblock so that the XmlReader
    # parser, statusCode split logic, and event extraction are exercised end-to-end.
    # (Windows only -- on Linux the module import guard prevents execution.)
    # ==========================================================================
    Context 'XML fixture parsing: StatusCode split, EventCount, ErrorModule, Win32Status, IncludeEvents' {

        BeforeAll {
            # Passthrough: execute the real scriptblock so XmlReader logic runs
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                param(
                    [string]$ComputerName,
                    [scriptblock]$ScriptBlock,
                    [object[]]$ArgumentList,
                    [System.Management.Automation.PSCredential]$Credential
                )
                if ($null -ne $ArgumentList) {
                    return & $ScriptBlock @ArgumentList
                }
                return & $ScriptBlock
            }
            # Make the IIS availability check pass so region-1 does not bail with IISNotInstalled
            Mock -CommandName 'Get-Module' -ModuleName $script:ModuleName -MockWith {
                param([string]$Name, [switch]$ListAvailable)
                if ($ListAvailable -and ($Name -eq 'WebAdministration' -or $Name -eq 'IISAdministration')) {
                    return [PSCustomObject]@{ Name = $Name; ModuleType = 'Manifest' }
                }
                return $null
            }
        }

        It "Should split compound statusCode 404.7 into StatusCode=404 and SubStatus=7" {
            $results = Get-IISFailedRequestTrace -Path $script:frebTempDir
            $parsed = @($results | Where-Object { $_.Status -eq 'Parsed' })
            $parsed | Should -Not -BeNullOrEmpty
            $parsed[0].StatusCode | Should -Be 404
            $parsed[0].SubStatus  | Should -Be 7
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It "Should count EventCount = 3 matching the three Event elements in the fixture" {
            $results = Get-IISFailedRequestTrace -Path $script:frebTempDir
            $parsed = @($results | Where-Object { $_.Status -eq 'Parsed' })
            $parsed | Should -Not -BeNullOrEmpty
            $parsed[0].EventCount | Should -Be 3
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It "Should set ErrorModule to ManagedPipelineHandler from the first Error-level event" {
            $results = Get-IISFailedRequestTrace -Path $script:frebTempDir
            $parsed = @($results | Where-Object { $_.Status -eq 'Parsed' })
            $parsed | Should -Not -BeNullOrEmpty
            $parsed[0].ErrorModule       | Should -Be 'ManagedPipelineHandler'
            $parsed[0].ErrorNotification | Should -Be 'EXECUTE_REQUEST_HANDLER'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It "Should capture Win32Status=2 from the GENERAL_REQUEST_END event" {
            $results = Get-IISFailedRequestTrace -Path $script:frebTempDir
            $parsed = @($results | Where-Object { $_.Status -eq 'Parsed' })
            $parsed | Should -Not -BeNullOrEmpty
            $parsed[0].Win32Status | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It "Should set Events to null when -IncludeEvents is not specified" {
            $results = Get-IISFailedRequestTrace -Path $script:frebTempDir
            $parsed = @($results | Where-Object { $_.Status -eq 'Parsed' })
            $parsed | Should -Not -BeNullOrEmpty
            $parsed[0].Events | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It "Should populate Events as a PSCustomObject array with 3 items when -IncludeEvents is set" {
            $results = Get-IISFailedRequestTrace -Path $script:frebTempDir -IncludeEvents
            $parsed = @($results | Where-Object { $_.Status -eq 'Parsed' })
            $parsed | Should -Not -BeNullOrEmpty
            $parsed[0].Events               | Should -Not -BeNullOrEmpty
            @($parsed[0].Events).Count      | Should -Be 3
            $parsed[0].Events[0].OpcodeName | Should -Be 'BEGIN_REQUEST'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It "Should parse Timestamp as UTC DateTime from the first event TimeCreated SystemTime" {
            $results = Get-IISFailedRequestTrace -Path $script:frebTempDir
            $parsed = @($results | Where-Object { $_.Status -eq 'Parsed' })
            $parsed | Should -Not -BeNullOrEmpty
            $parsed[0].Timestamp.Kind                          | Should -Be ([System.DateTimeKind]::Utc)
            $parsed[0].Timestamp.ToString('yyyy-MM-dd HH:mm:ss') | Should -Be '2026-05-15 10:00:00'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ==========================================================================
    # Context 3: Status = NoTraces
    # ==========================================================================
    Context 'Status = NoTraces: FREB folder exists but contains no fr*.xml files' {

        It 'Should return Status NoTraces with null Url and null EventCount' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockNoTraces }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.Status     | Should -Be 'NoTraces'
            $result.Url        | Should -BeNullOrEmpty
            $result.EventCount | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should carry SiteName in the NoTraces row when the site was resolved' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockNoTraces }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01' -SiteName 'Default Web Site'
            $result.SiteName | Should -Be 'Default Web Site'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ==========================================================================
    # Context 4: Status = SiteNotFound
    # ==========================================================================
    Context 'Status = SiteNotFound: requested SiteName/SiteId does not exist on the target' {

        It 'Should return Status SiteNotFound when the requested site is absent' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSiteNotFound }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01' -SiteName 'Nonexistent'
            $result.Status | Should -Be 'SiteNotFound'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit null TraceFile and null ErrorModule on SiteNotFound' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSiteNotFound }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01' -SiteId 9999
            $result.TraceFile   | Should -BeNullOrEmpty
            $result.ErrorModule | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ==========================================================================
    # Context 5: Status = FolderNotFound
    # ==========================================================================
    Context 'Status = FolderNotFound: FREB root directory does not exist on the target' {

        It 'Should return Status FolderNotFound when the -Path override directory is missing' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockFolderNotFound }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01' -Path 'C:\freb_override\missing'
            $result.Status | Should -Be 'FolderNotFound'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set non-empty ErrorMessageDetail describing the missing path on FolderNotFound' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockFolderNotFound }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01' -Path 'C:\freb_override\missing'
            $result.ErrorMessageDetail | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ==========================================================================
    # Context 6: Status = IISNotInstalled
    # ==========================================================================
    Context 'Status = IISNotInstalled: WebAdministration and appcmd.exe both absent on target' {

        It 'Should return Status IISNotInstalled with null StatusCode and null TraceFile' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockIISNotInstalled }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.Status     | Should -Be 'IISNotInstalled'
            $result.StatusCode | Should -BeNullOrEmpty
            $result.TraceFile  | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should carry non-empty ErrorMessageDetail describing the missing modules on IISNotInstalled' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockIISNotInstalled }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.ErrorMessageDetail | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ==========================================================================
    # Context 7: Status = Failed -- Invoke-RemoteOrLocal throws
    # ==========================================================================
    Context 'Status = Failed: unhandled exception during remote execution' {

        It 'Should return Status Failed with non-empty ErrorMessageDetail when Invoke-RemoteOrLocal throws' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { throw 'WinRM connection refused on port 5985' }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01' -ErrorAction SilentlyContinue
            $result.Status             | Should -Be 'Failed'
            $result.ErrorMessageDetail | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return Status Failed propagated by the scriptblock for internal errors' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockFailed }
            $result = Get-IISFailedRequestTrace -ComputerName 'WEB01'
            $result.Status             | Should -Be 'Failed'
            $result.ErrorMessageDetail | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ==========================================================================
    # Context 8: ShouldProcess -- function is read-only; -WhatIf is not declared
    # ==========================================================================
    Context 'ShouldProcess: read-only function -- -WhatIf is not a declared parameter' {

        It 'Should throw ParameterBinding when called with -WhatIf (SupportsShouldProcess not declared)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return @() }
            { Get-IISFailedRequestTrace -WhatIf -ErrorAction Stop } | Should -Throw
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    # ==========================================================================
    # Context 9: Pipeline by property name -- ComputerName and SiteName binding
    # ==========================================================================
    Context 'Pipeline by property name: ComputerName and SiteName bound from piped objects' {

        It 'Should fan-out across two ComputerName pipeline objects and invoke Invoke-RemoteOrLocal twice' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $pipeObjects = @(
                [PSCustomObject]@{ ComputerName = 'WEB01' }
                [PSCustomObject]@{ ComputerName = 'WEB02' }
            )
            $results = $pipeObjects | Get-IISFailedRequestTrace
            @($results).Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should bind SiteName from a piped object via ValueFromPipelineByPropertyName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $pipeObject = [PSCustomObject]@{ SiteName = 'Default Web Site' }
            $result = $pipeObject | Get-IISFailedRequestTrace
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should bind ComputerName via CN alias from a piped object' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $pipeObject = [PSCustomObject]@{ CN = 'WEB03' }
            $result = $pipeObject | Get-IISFailedRequestTrace
            $result.ComputerName | Should -Be 'WEB03'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ==========================================================================
    # Context 10: Credential propagation
    # ==========================================================================
    Context 'Credential propagation: PSCredential forwarded to Invoke-RemoteOrLocal' {

        It 'Should pass the Credential parameter through to Invoke-RemoteOrLocal when specified' {
            $fakeCred = [System.Management.Automation.PSCredential]::new(
                'domain\testuser',
                (ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force))
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                param(
                    [string]$ComputerName,
                    [scriptblock]$ScriptBlock,
                    [object[]]$ArgumentList,
                    [System.Management.Automation.PSCredential]$Credential
                )
                $script:capturedCred = $Credential
                return $script:mockParsed
            }
            Get-IISFailedRequestTrace -ComputerName 'WEB01' -Credential $fakeCred | Out-Null
            $script:capturedCred.UserName | Should -Be 'domain\testuser'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should not forward Credential to Invoke-RemoteOrLocal when it is not supplied' {
            $script:credPassedWhenAbsent = $false
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                param(
                    [string]$ComputerName,
                    [scriptblock]$ScriptBlock,
                    [object[]]$ArgumentList,
                    [System.Management.Automation.PSCredential]$Credential
                )
                if ($null -ne $Credential) { $script:credPassedWhenAbsent = $true }
                return $script:mockParsed
            }
            Get-IISFailedRequestTrace -ComputerName 'WEB01' | Out-Null
            $script:credPassedWhenAbsent | Should -BeFalse
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ==========================================================================
    # Context 11: ComputerName fan-out
    # ==========================================================================
    Context 'ComputerName fan-out: multiple targets processed sequentially' {

        It 'Should call Invoke-RemoteOrLocal once per target and stamp correct ComputerName per result' {
            $script:fanOutIndex = 0
            $fanOutMocks = @($script:mockParsedWeb01, $script:mockParsedWeb02)
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                param(
                    [string]$ComputerName,
                    [scriptblock]$ScriptBlock,
                    [object[]]$ArgumentList,
                    [System.Management.Automation.PSCredential]$Credential
                )
                $r = $fanOutMocks[$script:fanOutIndex]
                $script:fanOutIndex++
                return $r
            }
            $results = Get-IISFailedRequestTrace -ComputerName 'WEB01', 'WEB02'
            @($results).Count        | Should -Be 2
            $results[0].ComputerName | Should -Be 'WEB01'
            $results[1].ComputerName | Should -Be 'WEB02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should produce one result per host when -Tail 1 is combined with two targets' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockParsed }
            $results = Get-IISFailedRequestTrace -ComputerName 'WEB01', 'WEB02' -Tail 1
            @($results).Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ==========================================================================
    # Context 12: Error isolation per machine
    # ==========================================================================
    Context 'Error isolation: failure on one host does not prevent results from the other hosts' {

        It 'Should return Status Failed for BAD01 and Status Parsed for WEB02 when BAD01 throws' {
            $script:isolIndex = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                param(
                    [string]$ComputerName,
                    [scriptblock]$ScriptBlock,
                    [object[]]$ArgumentList,
                    [System.Management.Automation.PSCredential]$Credential
                )
                $script:isolIndex++
                if ($script:isolIndex -eq 1) { throw 'Network unreachable' }
                return $script:mockParsed
            }
            $results = Get-IISFailedRequestTrace -ComputerName 'BAD01', 'WEB02' -ErrorAction SilentlyContinue
            @($results).Count        | Should -Be 2
            $results[0].Status       | Should -Be 'Failed'
            $results[0].ComputerName | Should -Be 'BAD01'
            $results[1].Status       | Should -Be 'Parsed'
            $results[1].ComputerName | Should -Be 'WEB02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ==========================================================================
    # Context 13: BOM / CRLF sentinel
    # ==========================================================================
    Context 'BOM/CRLF sentinel: this test file is UTF-8 with BOM and CRLF line endings' {

        It 'Should detect the UTF-8 BOM bytes (EF BB BF) at the start of this test file' {
            $bytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'Should detect CRLF line endings in this test file (Get-Content raw match)' {
            $raw = Get-Content -LiteralPath $PSCommandPath -Raw
            $raw | Should -Match "`r`n"
        }
    }
}
