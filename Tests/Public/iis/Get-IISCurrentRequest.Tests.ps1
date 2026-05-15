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
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'

    # ---------------------------------------------------------------------------
    # Reusable mock payloads
    # ---------------------------------------------------------------------------

    $script:mockInFlight = @(
        @{
            ProcessId       = 4812
            AppPoolName     = 'DefaultAppPool'
            SiteName        = 'Default Web Site'
            Url             = 'http://web01.contoso.com/api/data?q=test'
            Verb            = 'GET'
            ClientIPAddress = '192.168.1.10'
            TimeElapsed     = [System.TimeSpan]::FromMilliseconds(1523)
            TimeElapsedMs   = [long]1523
            PipelineState   = 'ExecuteRequestHandler'
            Status          = 'InFlight'
            ErrorMessage    = $null
            Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    )

    $script:mockNoRequests = @(
        @{
            ProcessId       = $null
            AppPoolName     = $null
            SiteName        = $null
            Url             = $null
            Verb            = $null
            ClientIPAddress = $null
            TimeElapsed     = $null
            TimeElapsedMs   = $null
            PipelineState   = $null
            Status          = 'NoRequests'
            ErrorMessage    = $null
            Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    )

    $script:mockIISNotInstalled = @(
        @{
            ProcessId       = $null
            AppPoolName     = $null
            SiteName        = $null
            Url             = $null
            Verb            = $null
            ClientIPAddress = $null
            TimeElapsed     = $null
            TimeElapsedMs   = $null
            PipelineState   = $null
            Status          = 'IISNotInstalled'
            ErrorMessage    = 'W3SVC service not found: Cannot find any service with service name W3SVC'
            Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    )

    $script:mockAppcmdMissing = @(
        @{
            ProcessId       = $null
            AppPoolName     = $null
            SiteName        = $null
            Url             = $null
            Verb            = $null
            ClientIPAddress = $null
            TimeElapsed     = $null
            TimeElapsedMs   = $null
            PipelineState   = $null
            Status          = 'AppcmdMissing'
            ErrorMessage    = 'appcmd.exe not found. Install the IIS Management Scripts and Tools feature.'
            Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    )

    $script:mockFailed = @(
        @{
            ProcessId       = $null
            AppPoolName     = $null
            SiteName        = $null
            Url             = $null
            Verb            = $null
            ClientIPAddress = $null
            TimeElapsed     = $null
            TimeElapsedMs   = $null
            PipelineState   = $null
            Status          = 'Failed'
            ErrorMessage    = 'appcmd.exe execution failed: Access is denied'
            Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    )

    $script:mockMultiRequest = @(
        @{
            ProcessId       = 4812
            AppPoolName     = 'APIPool'
            SiteName        = 'api.contoso.com'
            Url             = 'http://api.contoso.com/v1/items'
            Verb            = 'POST'
            ClientIPAddress = '10.0.0.5'
            TimeElapsed     = [System.TimeSpan]::FromMilliseconds(6200)
            TimeElapsedMs   = [long]6200
            PipelineState   = 'ExecuteRequestHandler'
            Status          = 'InFlight'
            ErrorMessage    = $null
            Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        @{
            ProcessId       = 7360
            AppPoolName     = 'DefaultAppPool'
            SiteName        = 'Default Web Site'
            Url             = 'http://web01.contoso.com/home'
            Verb            = 'GET'
            ClientIPAddress = '192.168.1.20'
            TimeElapsed     = [System.TimeSpan]::FromMilliseconds(320)
            TimeElapsedMs   = [long]320
            PipelineState   = 'SendResponse'
            Status          = 'InFlight'
            ErrorMessage    = $null
            Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    )
}

Describe 'Get-IISCurrentRequest' {

    # == Context 1 ==============================================================
    # Happy path: InFlight request with all output properties populated.
    # ===========================================================================
    Context 'Happy path: InFlight request with all properties populated' {

        It 'Should return Status InFlight with correct PSTypeName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.Status                | Should -Be 'InFlight'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISCurrentRequest'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate Url, Verb, ClientIPAddress and AppPoolName from mock' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.Url             | Should -Be 'http://web01.contoso.com/api/data?q=test'
            $result.Verb            | Should -Be 'GET'
            $result.ClientIPAddress | Should -Be '192.168.1.10'
            $result.AppPoolName     | Should -Be 'DefaultAppPool'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate ProcessId, SiteName and PipelineState' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.ProcessId     | Should -Be 4812
            $result.SiteName      | Should -Be 'Default Web Site'
            $result.PipelineState | Should -Be 'ExecuteRequestHandler'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate TimeElapsed as TimeSpan and TimeElapsedMs as long' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.TimeElapsed   | Should -BeOfType [System.TimeSpan]
            $result.TimeElapsedMs | Should -Be 1523
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set ComputerName to the value supplied by the caller' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.ComputerName | Should -Be 'WEB01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 2 ==============================================================
    # Status = NoRequests: IIS healthy but no request in-flight.
    # ===========================================================================
    Context 'Status = NoRequests: IIS healthy but no request in-flight' {

        It 'Should return Status NoRequests with null Url and null ProcessId' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockNoRequests }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.Status    | Should -Be 'NoRequests'
            $result.Url       | Should -BeNullOrEmpty
            $result.ProcessId | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 3 ==============================================================
    # Status = IISNotInstalled: W3SVC service absent on target machine.
    # ===========================================================================
    Context 'Status = IISNotInstalled: W3SVC service absent on target' {

        It 'Should return Status IISNotInstalled with ErrorMessage mentioning W3SVC' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockIISNotInstalled }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.Status       | Should -Be 'IISNotInstalled'
            $result.ErrorMessage | Should -Match 'W3SVC'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 4 ==============================================================
    # Status = AppcmdMissing: appcmd.exe binary not found on target.
    # ===========================================================================
    Context 'Status = AppcmdMissing: appcmd.exe not found on target' {

        It 'Should return Status AppcmdMissing with ErrorMessage mentioning appcmd.exe' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockAppcmdMissing }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.Status       | Should -Be 'AppcmdMissing'
            $result.ErrorMessage | Should -Match 'appcmd\.exe'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should have null ProcessId, Url and PipelineState when AppcmdMissing' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockAppcmdMissing }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.ProcessId     | Should -BeNullOrEmpty
            $result.Url           | Should -BeNullOrEmpty
            $result.PipelineState | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 5 ==============================================================
    # Status = Failed: exception from the scriptblock or Invoke-RemoteOrLocal.
    # ===========================================================================
    Context 'Status = Failed: exception thrown during data collection' {

        It 'Should return Status Failed with non-empty ErrorMessage when Invoke-RemoteOrLocal throws' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { throw 'WinRM connection refused' }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01' -ErrorAction SilentlyContinue
            $result.Status       | Should -Be 'Failed'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return Status Failed from scriptblock appcmd execution error' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockFailed }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.Status       | Should -Be 'Failed'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 6 ==============================================================
    # ShouldProcess: function is read-only; -WhatIf is not a declared parameter.
    # ===========================================================================
    Context 'ShouldProcess: read-only function -- -WhatIf parameter is not declared' {

        It 'Should throw when called with -WhatIf because SupportsShouldProcess is not declared' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return @() }
            { Get-IISCurrentRequest -WhatIf -ErrorAction Stop } | Should -Throw
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    # == Context 7 ==============================================================
    # Pipeline by property name: ComputerName / DNSHostName / CN alias binding.
    # ===========================================================================
    Context 'Pipeline by property name (ComputerName / DNSHostName / CN aliases)' {

        It 'Should fan-out across two pipeline objects bound by ComputerName property' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $pipeObjects = @(
                [PSCustomObject]@{ ComputerName = 'WEB01' }
                [PSCustomObject]@{ ComputerName = 'WEB02' }
            )
            $results = $pipeObjects | Get-IISCurrentRequest
            @($results).Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should bind pipeline object via DNSHostName alias and emit ComputerName correctly' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $pipeObj = [PSCustomObject]@{ DNSHostName = 'WEB03' }
            $result  = $pipeObj | Get-IISCurrentRequest
            $result              | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'WEB03'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should bind pipeline object via CN alias and emit ComputerName correctly' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $pipeObj = [PSCustomObject]@{ CN = 'WEB04' }
            $result  = $pipeObj | Get-IISCurrentRequest
            $result              | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'WEB04'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 8 ==============================================================
    # Credential propagation: PSCredential must reach Invoke-RemoteOrLocal.
    # ===========================================================================
    Context 'Credential propagation: PSCredential forwarded to Invoke-RemoteOrLocal' {

        It 'Should forward Credential to Invoke-RemoteOrLocal and return InFlight results' {
            $securePass          = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $cred                = [System.Management.Automation.PSCredential]::new('DOMAIN\svcweb', $securePass)
            $script:capturedCred = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedCred = $Credential
                return $script:mockInFlight
            }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01' -Credential $cred
            $result.Status                | Should -Be 'InFlight'
            $script:capturedCred          | Should -Not -BeNullOrEmpty
            $script:capturedCred.UserName | Should -Be 'DOMAIN\svcweb'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 9 ==============================================================
    # ComputerName fan-out: multiple machine names queried in sequence.
    # ===========================================================================
    Context 'ComputerName fan-out: multiple machines queried in sequence' {

        It 'Should return one result row per machine with correct ComputerName labels' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $results = Get-IISCurrentRequest -ComputerName 'WEB01', 'WEB02'
            @($results).Count        | Should -Be 2
            $results[0].ComputerName | Should -Be 'WEB01'
            $results[1].ComputerName | Should -Be 'WEB02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # == Context 10 =============================================================
    # Error isolation: failure on one machine must not suppress other results.
    # ===========================================================================
    Context 'Error isolation: failed machine does not suppress results from healthy machine' {

        It 'Should return Failed row for first machine and InFlight for second' {
            $script:isolationCallCount = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:isolationCallCount++
                if ($script:isolationCallCount -eq 1) { throw 'WinRM connection refused' }
                return $script:mockInFlight
            }
            $results = Get-IISCurrentRequest -ComputerName 'FAIL01', 'WEB02' -ErrorAction SilentlyContinue
            @($results).Count        | Should -Be 2
            $results[0].Status       | Should -Be 'Failed'
            $results[0].ComputerName | Should -Be 'FAIL01'
            $results[1].Status       | Should -Be 'InFlight'
            $results[1].ComputerName | Should -Be 'WEB02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # == Context 11 =============================================================
    # BOM/CRLF sentinel: test file must be UTF-8 with BOM and CRLF line endings.
    # ===========================================================================
    Context 'BOM/CRLF sentinel: test file encoding compliance' {

        It 'Should have UTF-8 BOM as first three bytes (EF BB BF)' {
            $filePath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-IISCurrentRequest.Tests.ps1'
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'Should use CRLF line endings throughout the test file' {
            $filePath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-IISCurrentRequest.Tests.ps1'
            $raw = [System.IO.File]::ReadAllText($filePath)
            $raw | Should -Match "`r`n"
        }
    }

    # == Context 12 =============================================================
    # Timestamp property: must match yyyy-MM-dd HH:mm:ss pattern in every row.
    # ===========================================================================
    Context 'Timestamp property matches yyyy-MM-dd HH:mm:ss format' {

        It 'Should produce Timestamp matching yyyy-MM-dd HH:mm:ss pattern for InFlight row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.Timestamp | Should -Match "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should produce Timestamp matching yyyy-MM-dd HH:mm:ss pattern for NoRequests row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockNoRequests }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.Timestamp | Should -Match "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 13 =============================================================
    # AppPoolName filter: filter array forwarded as ArgumentList[0].
    # ===========================================================================
    Context 'AppPoolName filter: array forwarded as ArgumentList[0] to Invoke-RemoteOrLocal' {

        It 'Should pass AppPoolName patterns as first element of ArgumentList' {
            $script:capturedPoolFilter = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedPoolFilter = $ArgumentList[0]
                return @()
            }
            Get-IISCurrentRequest -ComputerName 'WEB01' -AppPoolName 'API*', 'DefaultAppPool'
            $script:capturedPoolFilter | Should -Contain 'API*'
            $script:capturedPoolFilter | Should -Contain 'DefaultAppPool'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 14 =============================================================
    # SiteName filter: filter array forwarded as ArgumentList[1].
    # ===========================================================================
    Context 'SiteName filter: array forwarded as ArgumentList[1] to Invoke-RemoteOrLocal' {

        It 'Should pass SiteName patterns as second element of ArgumentList' {
            $script:capturedSiteFilter = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedSiteFilter = $ArgumentList[1]
                return @()
            }
            Get-IISCurrentRequest -ComputerName 'WEB01' -SiteName 'Default Web Site', 'api.contoso.com'
            $script:capturedSiteFilter | Should -Contain 'Default Web Site'
            $script:capturedSiteFilter | Should -Contain 'api.contoso.com'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 15 =============================================================
    # MinElapsedMs filter: threshold forwarded as ArgumentList[2].
    # ===========================================================================
    Context 'MinElapsedMs filter: threshold forwarded as ArgumentList[2] to Invoke-RemoteOrLocal' {

        It 'Should pass MinElapsedMs as third element of ArgumentList' {
            $script:capturedMinElapsed = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedMinElapsed = $ArgumentList[2]
                return @()
            }
            Get-IISCurrentRequest -ComputerName 'WEB01' -MinElapsedMs 5000
            $script:capturedMinElapsed | Should -Be 5000
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return two result rows when multiple requests are in-flight' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockMultiRequest }
            $results = Get-IISCurrentRequest -ComputerName 'WEB01'
            @($results).Count | Should -Be 2
            $results | ForEach-Object { $_.Status | Should -Be 'InFlight' }
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 16 =============================================================
    # PipelineState enum: valid values pass through; unrecognised -> Unknown.
    # ===========================================================================
    Context 'PipelineState enum: valid values pass through unmodified' {

        It 'Should carry a recognised PipelineState for an InFlight request' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockInFlight }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $validStates = @(
                'BeginRequest', 'AuthenticateRequest', 'AuthorizeRequest',
                'ResolveRequestCache', 'MapRequestHandler', 'AcquireRequestState',
                'PreExecuteRequestHandler', 'ExecuteRequestHandler',
                'ReleaseRequestState', 'UpdateRequestCache', 'LogRequest',
                'EndRequest', 'SendResponse', 'Unknown'
            )
            $result.PipelineState | Should -BeIn $validStates
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should normalise an unrecognised PipelineState value to Unknown' {
            $script:mockUnknownState = @(
                @{
                    ProcessId       = 999
                    AppPoolName     = 'TestPool'
                    SiteName        = 'TestSite'
                    Url             = 'http://test.local/ping'
                    Verb            = 'GET'
                    ClientIPAddress = '127.0.0.1'
                    TimeElapsed     = [System.TimeSpan]::FromMilliseconds(100)
                    TimeElapsedMs   = [long]100
                    PipelineState   = 'Unknown'
                    Status          = 'InFlight'
                    ErrorMessage    = $null
                    Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                }
            )
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockUnknownState }
            $result = Get-IISCurrentRequest -ComputerName 'WEB01'
            $result.PipelineState | Should -Be 'Unknown'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }
}
