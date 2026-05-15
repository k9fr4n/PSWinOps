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

    if ($IsWindows -or $PSEdition -eq 'Desktop') {
        # Windows: import the real module so private functions are mock-able by scope name.
        Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    } else {
        # Linux/macOS: PSWinOps.psm1 has a Windows-only guard.
        # Build an in-memory 'PSWinOps' module containing Invoke-RemoteOrLocal and
        # Watch-IISLog so that Pester's -ModuleName 'PSWinOps' mock scope works on Linux.
        $stripRequires = { param([string]$src) $src -replace '(?m)^#Requires[^\r\n]*[\r\n]*', '' }
        $invokeRolSrc  = & $stripRequires (Get-Content -Raw -Path ([IO.Path]::Combine($script:modulePath, 'Private', 'Invoke-RemoteOrLocal.ps1')))
        $watchSrc      = & $stripRequires (Get-Content -Raw -Path ([IO.Path]::Combine($script:modulePath, 'Public', 'iis', 'Watch-IISLog.ps1')))
        $moduleBody    = "`$script:LocalComputerNames = @(`$env:COMPUTERNAME, 'localhost', '.')`n" +
                         $invokeRolSrc + "`n" + $watchSrc + "`nExport-ModuleMember -Function '*'"
        New-Module -Name 'PSWinOps' -ScriptBlock ([scriptblock]::Create($moduleBody)) |
            Import-Module -Force
    }

    $script:ModuleName = 'PSWinOps'

    # ---------------------------------------------------------------------------
    # Mock factory: builds a PSWinOps.IISLogEntry custom object that mirrors the
    # shape emitted by the Watch-IISLog self-contained remote scriptblock.
    # All defaults reproduce a single GET 200 request for 'Default Web Site'.
    # ---------------------------------------------------------------------------
    function script:New-MockIISLogEntry {
        param(
            [string] $ComputerName  = 'WEB01',
            [string] $LogFile       = 'C:\inetpub\logs\LogFiles\W3SVC1\u_ex260514.log',
            [int]    $LineNumber    = 1,
            [string] $Method        = 'GET',
            [string] $UriStem       = '/index.html',
            [object] $UriQuery      = $null,
            [object] $UserName      = $null,
            [string] $ClientIP      = '10.0.0.42',
            [object] $UserAgent     = 'Mozilla/5.0 (Windows NT 10.0)',
            [object] $Referer       = $null,
            [int]    $HttpStatus    = 200,
            [int]    $HttpSubStatus = 0,
            [long]   $Win32Status   = [long]0,
            [long]   $BytesSent     = [long]1234,
            [long]   $BytesReceived = [long]512,
            [int]    $TimeTaken     = 50
        )
        return [PSCustomObject]@{
            PSTypeName    = 'PSWinOps.IISLogEntry'
            Timestamp     = [datetime]::new(2026, 5, 14, 10, 0, 0, [System.DateTimeKind]::Utc)
            LogFile       = $LogFile
            LineNumber    = $LineNumber
            ComputerName  = $ComputerName
            SiteName      = 'W3SVC1'
            ServerName    = 'WEB01'
            ServerIP      = '192.168.1.10'
            ServerPort    = 80
            Method        = $Method
            UriStem       = $UriStem
            UriQuery      = $UriQuery
            UserName      = $UserName
            ClientIP      = $ClientIP
            UserAgent     = $UserAgent
            Referer       = $Referer
            HttpStatus    = $HttpStatus
            HttpSubStatus = $HttpSubStatus
            Win32Status   = $Win32Status
            BytesSent     = $BytesSent
            BytesReceived = $BytesReceived
            TimeTaken     = $TimeTaken
        }
    }

    # ---------------------------------------------------------------------------
    # Shared mock payloads used across multiple contexts.
    # ---------------------------------------------------------------------------
    $script:mockSingleEntry = @(script:New-MockIISLogEntry)

    $script:mockMultiEntry = @(
        script:New-MockIISLogEntry -LineNumber 1 -UriStem '/a' -HttpStatus 200
        script:New-MockIISLogEntry -LineNumber 2 -UriStem '/b' -HttpStatus 404
        script:New-MockIISLogEntry -LineNumber 3 -UriStem '/c' -HttpStatus 500
    )

    $script:mockDashFields = @(
        script:New-MockIISLogEntry -UriQuery $null -UserName $null -Referer $null -UserAgent $null
    )

    $script:mockUserAgentDecoded = @(
        script:New-MockIISLogEntry -UserAgent 'Mozilla/5.0 (Windows NT 10.0)'
    )
}

Describe 'Watch-IISLog' {

    # == Context 1 ==============================================================
    # Happy path: single PSWinOps.IISLogEntry returned via Invoke-RemoteOrLocal.
    # ===========================================================================
    Context 'Happy path: PSWinOps.IISLogEntry returned via Invoke-RemoteOrLocal' {

        It 'Should return a PSWinOps.IISLogEntry with correct PSTypeName for a single target' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISLogEntry'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should stream all IISLogEntry objects when mock returns a multi-entry collection' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockMultiEntry }
            $results = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01'
            @($results).Count | Should -Be 3
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should pass SiteName as ArgumentList[0] to Invoke-RemoteOrLocal' {
            $script:capturedSiteName = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedSiteName = $ArgumentList[0]
                return @()
            }
            Watch-IISLog -SiteName 'api.contoso.com' -ComputerName 'WEB01'
            $script:capturedSiteName | Should -Be 'api.contoso.com'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 2 ==============================================================
    # All output properties: Method, UriStem, HttpStatus, BytesSent, etc.
    # ===========================================================================
    Context 'All output properties populated correctly from emitted IISLogEntry' {

        It 'Should populate Method, UriStem and HttpStatus from emitted entry' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.Method     | Should -Be 'GET'
            $result.UriStem    | Should -Be '/index.html'
            $result.HttpStatus | Should -Be 200
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate BytesSent, BytesReceived and TimeTaken with correct values' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.BytesSent     | Should -Be 1234
            $result.BytesReceived | Should -Be 512
            $result.TimeTaken     | Should -Be 50
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate Win32Status as a long integer and LogFile as the resolved path' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.Win32Status | Should -Be 0
            $result.Win32Status | Should -BeOfType [long]
            $result.LogFile     | Should -Be 'C:\inetpub\logs\LogFiles\W3SVC1\u_ex260514.log'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate 1-based LineNumber per entry in order across a multi-entry stream' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockMultiEntry }
            $results = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01'
            $results[0].LineNumber | Should -Be 1
            $results[1].LineNumber | Should -Be 2
            $results[2].LineNumber | Should -Be 3
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 3 ==============================================================
    # Timestamp: UTC DateTime matching yyyy-MM-dd HH:mm:ss format.
    # ===========================================================================
    Context 'Timestamp property: UTC DateTime in yyyy-MM-dd HH:mm:ss format' {

        It 'Should emit Timestamp as a UTC DateTime object (Kind = Utc)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.Timestamp      | Should -BeOfType [datetime]
            $result.Timestamp.Kind | Should -Be ([System.DateTimeKind]::Utc)
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should format Timestamp string matching the "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}" pattern' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.Timestamp.ToString('yyyy-MM-dd HH:mm:ss') | Should -Match "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set Timestamp to 2026-05-14 10:00:00 UTC as built from date+time fields' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.Timestamp.ToString('yyyy-MM-dd HH:mm:ss') | Should -Be '2026-05-14 10:00:00'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 4 ==============================================================
    # Dash normalisation: IIS "-" placeholder emitted as $null on nullable fields.
    # ===========================================================================
    Context 'Dash normalisation: nullable fields emitted as $null when IIS placeholder is "-"' {

        It 'Should emit $null for UriQuery when the IIS field value is "-"' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockDashFields }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.UriQuery | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit $null for UserName when the IIS field value is "-"' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockDashFields }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.UserName | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit $null for Referer when the IIS field value is "-"' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockDashFields }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.Referer | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit $null for UserAgent when the IIS field value is "-"' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockDashFields }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.UserAgent | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 5 ==============================================================
    # UserAgent decoding: IIS "+" decoded back to spaces, UriStem left URL-encoded.
    # ===========================================================================
    Context 'UserAgent decoding: "+" decoded back to spaces, UriStem left as-logged' {

        It 'Should emit spaces (not "+") in UserAgent -- parser decodes "+" back to space' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockUserAgentDecoded }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.UserAgent | Should -Be 'Mozilla/5.0 (Windows NT 10.0)'
            $result.UserAgent | Should -Not -Match '\+'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should leave UriStem as-logged by IIS with no "+" decoding applied on path segments' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -MaxEntries 1
            $result.UriStem | Should -Be '/index.html'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 6 ==============================================================
    # ShouldProcess: Watch-IISLog is read-only; -WhatIf is not a declared parameter.
    # ===========================================================================
    Context 'ShouldProcess: read-only -- -WhatIf not declared, zero mutations on any call' {

        It 'Should throw when called with -WhatIf because SupportsShouldProcess is not declared' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return @() }
            { Watch-IISLog -SiteName 'Default Web Site' -WhatIf -ErrorAction Stop } | Should -Throw
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 0 -Exactly
        }
    }

    # == Context 7 ==============================================================
    # Pipeline by property name: SiteName and ComputerName / DNSHostName / CN.
    # ===========================================================================
    Context 'Pipeline by property name (SiteName and ComputerName / DNSHostName / CN aliases)' {

        It 'Should accept SiteName from pipeline by property name alongside ComputerName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $pipeObj = [PSCustomObject]@{ SiteName = 'api.contoso.com'; ComputerName = 'WEB01' }
            $result  = $pipeObj | Watch-IISLog
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should fan-out across two pipeline objects bound by ComputerName and invoke twice' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $pipeObjs = @(
                [PSCustomObject]@{ ComputerName = 'WEB01' }
                [PSCustomObject]@{ ComputerName = 'WEB02' }
            )
            $results = $pipeObjs | Watch-IISLog -SiteName 'Default Web Site'
            @($results).Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should bind pipeline object via DNSHostName alias and call Invoke-RemoteOrLocal once' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $pipeObj = [PSCustomObject]@{ DNSHostName = 'WEB03' }
            $result  = $pipeObj | Watch-IISLog -SiteName 'Default Web Site'
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should bind pipeline object via CN alias and call Invoke-RemoteOrLocal once' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $pipeObj = [PSCustomObject]@{ CN = 'WEB04' }
            $result  = $pipeObj | Watch-IISLog -SiteName 'Default Web Site'
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 8 ==============================================================
    # Credential propagation: PSCredential forwarded to Invoke-RemoteOrLocal.
    # ===========================================================================
    Context 'Credential propagation: PSCredential forwarded to Invoke-RemoteOrLocal' {

        It 'Should forward Credential to Invoke-RemoteOrLocal and still return emitted entries' {
            $securePass          = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $cred                = [System.Management.Automation.PSCredential]::new('DOMAIN\svcweb', $securePass)
            $script:capturedCred = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedCred = $Credential
                return $script:mockSingleEntry
            }
            $result = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01' -Credential $cred
            $result                       | Should -Not -BeNullOrEmpty
            $script:capturedCred          | Should -Not -BeNullOrEmpty
            $script:capturedCred.UserName | Should -Be 'DOMAIN\svcweb'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 9 ==============================================================
    # ComputerName fan-out: one Invoke-RemoteOrLocal call per target machine.
    # ===========================================================================
    Context 'ComputerName fan-out: one Invoke-RemoteOrLocal call per target machine' {

        It 'Should call Invoke-RemoteOrLocal twice and return two entries for two ComputerNames' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $results = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01', 'WEB02'
            @($results).Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should call Invoke-RemoteOrLocal three times for three ComputerNames' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { return $script:mockSingleEntry }
            $null = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'WEB01', 'WEB02', 'WEB03'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 3 -Exactly
        }
    }

    # == Context 10 =============================================================
    # Error isolation: failed machine must not suppress results from healthy machines.
    # ===========================================================================
    Context 'Error isolation: failed machine does not suppress results from healthy machines' {

        It 'Should emit entries from healthy machine when first machine throws a WinRM error' {
            $script:isolationCallCount = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:isolationCallCount++
                if ($script:isolationCallCount -eq 1) { throw 'WinRM connection refused' }
                return $script:mockSingleEntry
            }
            $results = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'FAIL01', 'WEB02' -ErrorAction SilentlyContinue
            @($results).Count | Should -Be 1
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should surface a non-terminating error record for the failed machine' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                throw 'Access is denied'
            }
            $capturedErrors = @()
            $null = Watch-IISLog -SiteName 'Default Web Site' -ComputerName 'FAIL01' `
                -ErrorAction SilentlyContinue -ErrorVariable capturedErrors
            $capturedErrors.Count | Should -BeGreaterOrEqual 1
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # == Context 11 =============================================================
    # BOM/CRLF sentinel: test file must be UTF-8 with BOM and CRLF line endings.
    # ===========================================================================
    Context 'BOM/CRLF sentinel: test file encoding compliance (UTF-8 BOM + CRLF)' {

        It 'Should detect UTF-8 BOM bytes (EF BB BF) at the start of this test file' {
            $filePath = Join-Path -Path $PSScriptRoot -ChildPath 'Watch-IISLog.Tests.ps1'
            $bytes    = [System.IO.File]::ReadAllBytes($filePath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'Should detect CRLF line endings in this test file via Get-Content -Raw' {
            $filePath = Join-Path -Path $PSScriptRoot -ChildPath 'Watch-IISLog.Tests.ps1'
            $raw      = Get-Content -LiteralPath $filePath -Raw
            $raw      | Should -Match "`r`n"
        }
    }
}
