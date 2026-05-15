#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    # Resolve project root from Tests/Public/iis (3 levels up)
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    # On Windows (Desktop edition): import full module.
    # On Linux/macOS (local Docker validation): dot-source the function directly,
    # bypassing the Windows-only guard in PSWinOps.psm1.
    # CI always runs on windows-latest where the full module is imported.
    if ($IsWindows -or $PSEdition -eq 'Desktop') {
        Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    } else {
        . ([IO.Path]::Combine($script:modulePath, 'Public', 'iis', 'Get-IISParsedLog.ps1'))
    }

    $script:ModuleName = 'PSWinOps'

    # Helper: write a temp IIS log file (UTF-8 no BOM, mirrors real IIS output)
    function script:New-TempIISLog {
        param([string]$Content)
        $tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.log')
        [System.IO.File]::WriteAllText($tmp, $Content, [System.Text.UTF8Encoding]::new($false))
        return $tmp
    }

    $StdHdr = '#Fields: date time s-sitename s-computername s-ip cs-method cs-uri-stem cs-uri-query s-port cs-username c-ip cs(User-Agent) cs(Referer) sc-status sc-substatus sc-win32-status sc-bytes cs-bytes time-taken'

    # ---- LogFile1: 3 data entries (GET 200, POST 404, GET 500) ----
    $script:Log1 = script:New-TempIISLog -Content (
        "#Software: Microsoft Internet Information Services 10.0`r`n" +
        "#Version: 1.0`r`n" +
        "#Date: 2026-05-14 00:00:00`r`n" +
        "$StdHdr`r`n" +
        "2026-05-14 10:00:00 W3SVC1 WEB01 192.168.1.10 GET /index.html - 80 - 10.0.0.42 Mozilla/5.0+(Windows+NT+10.0) https://example.com 200 0 0 1234 512 50`r`n" +
        "2026-05-14 10:01:00 W3SVC1 WEB01 192.168.1.10 POST /api/data - 443 jdoe 10.0.0.43 curl/7.88.1 - 404 0 0 512 256 120`r`n" +
        "2026-05-14 10:02:00 W3SVC1 WEB01 192.168.1.10 GET /api/fail - 443 - 10.0.0.44 Python+Requests/2.28 - 500 0 64 2048 128 3500`r`n"
    )

    # ---- LogFile2: dash-normalised fields (UserAgent, Referer, UserName, UriQuery = '-') ----
    $script:Log2 = script:New-TempIISLog -Content (
        "#Software: Microsoft Internet Information Services 10.0`r`n" +
        "$StdHdr`r`n" +
        "2026-05-14 11:00:00 W3SVC2 WEB02 10.0.1.5 GET /health - 80 - 192.168.99.1 - - 200 0 0 300 64 10`r`n"
    )

    # ---- LogFile3: mid-file #Fields re-detection ----
    $script:Log3 = script:New-TempIISLog -Content (
        "#Software: Microsoft Internet Information Services 10.0`r`n" +
        "#Fields: date time cs-method cs-uri-stem sc-status`r`n" +
        "2026-05-14 12:00:00 GET /before 200`r`n" +
        "#Fields: date time cs-method cs-uri-stem sc-status sc-bytes`r`n" +
        "2026-05-14 12:01:00 GET /after 200 9999`r`n"
    )

    # ---- LogFile4: 5 entries for -Tail circular-buffer test ----
    $script:Log4 = script:New-TempIISLog -Content (
        "#Software: Microsoft Internet Information Services 10.0`r`n" +
        "$StdHdr`r`n" +
        "2026-05-14 13:00:00 W3SVC1 WEB01 10.1.1.1 GET /a - 80 - 10.0.0.1 Agent/1 - 200 0 0 100 50 10`r`n" +
        "2026-05-14 13:01:00 W3SVC1 WEB01 10.1.1.1 GET /b - 80 - 10.0.0.1 Agent/1 - 200 0 0 100 50 11`r`n" +
        "2026-05-14 13:02:00 W3SVC1 WEB01 10.1.1.1 GET /c - 80 - 10.0.0.1 Agent/1 - 200 0 0 100 50 12`r`n" +
        "2026-05-14 13:03:00 W3SVC1 WEB01 10.1.1.1 GET /d - 80 - 10.0.0.1 Agent/1 - 200 0 0 100 50 13`r`n" +
        "2026-05-14 13:04:00 W3SVC1 WEB01 10.1.1.1 GET /e - 80 - 10.0.0.1 Agent/1 - 200 0 0 100 50 14`r`n"
    )

    $script:LogFiles = @($script:Log1, $script:Log2, $script:Log3, $script:Log4)
}

AfterAll {
    $script:LogFiles | ForEach-Object {
        if ($_ -and (Test-Path -LiteralPath $_)) {
            Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-IISParsedLog' {

    # ------------------------------------------------------------------
    # Context 1: Happy path
    # ------------------------------------------------------------------
    Context 'Happy path: all standard W3C fields parsed correctly' {

        It 'Should return one PSWinOps.IISLogEntry object per data line' {
            $results = Get-IISParsedLog -Path $script:Log1
            $results.Count | Should -Be 3
        }

        It 'Should set PSTypeName to PSWinOps.IISLogEntry on every entry' {
            $results = Get-IISParsedLog -Path $script:Log1
            $results[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISLogEntry'
        }

        It 'Should populate Timestamp as a UTC DateTime built from date+time fields' {
            $result = Get-IISParsedLog -Path $script:Log1 | Select-Object -First 1
            $result.Timestamp | Should -BeOfType [datetime]
            $result.Timestamp.Kind | Should -Be ([System.DateTimeKind]::Utc)
            $result.Timestamp.ToString('yyyy-MM-dd HH:mm:ss') | Should -Be '2026-05-14 10:00:00'
        }

        It 'Should set LogFile to the full source file path' {
            $result = Get-IISParsedLog -Path $script:Log1 | Select-Object -First 1
            $result.LogFile | Should -Be $script:Log1
        }

        It 'Should set 1-based LineNumber on each data entry (comment lines skipped)' {
            $results = Get-IISParsedLog -Path $script:Log1
            $results[0].LineNumber | Should -Be 1
            $results[1].LineNumber | Should -Be 2
            $results[2].LineNumber | Should -Be 3
        }

        It 'Should parse SiteName, ServerName, ServerIP and ServerPort correctly' {
            $result = Get-IISParsedLog -Path $script:Log1 | Select-Object -First 1
            $result.SiteName   | Should -Be 'W3SVC1'
            $result.ServerName | Should -Be 'WEB01'
            $result.ServerIP   | Should -Be '192.168.1.10'
            $result.ServerPort | Should -Be 80
        }

        It 'Should parse Method, UriStem, HttpStatus, BytesSent, BytesReceived and TimeTaken' {
            $result = Get-IISParsedLog -Path $script:Log1 | Select-Object -First 1
            $result.Method        | Should -Be 'GET'
            $result.UriStem       | Should -Be '/index.html'
            $result.HttpStatus    | Should -Be 200
            $result.BytesSent     | Should -Be 1234
            $result.BytesReceived | Should -Be 512
            $result.TimeTaken     | Should -Be 50
        }

        It 'Should parse Win32Status as a long integer' {
            $result = Get-IISParsedLog -Path $script:Log1 | Select-Object -First 1
            $result.Win32Status | Should -Be 0
            $result.Win32Status | Should -BeOfType [long]
        }
    }

    # ------------------------------------------------------------------
    # Context 2: Dash normalisation
    # ------------------------------------------------------------------
    Context 'Dash normalisation: IIS "-" placeholder emitted as $null' {

        It 'Should emit $null for UriQuery when the field is "-"' {
            $result = Get-IISParsedLog -Path $script:Log2
            $result.UriQuery | Should -BeNullOrEmpty
        }

        It 'Should emit $null for UserName when the field is "-"' {
            $result = Get-IISParsedLog -Path $script:Log2
            $result.UserName | Should -BeNullOrEmpty
        }

        It 'Should emit $null for UserAgent (string field) when the field is "-"' {
            $result = Get-IISParsedLog -Path $script:Log2
            $result.UserAgent | Should -BeNullOrEmpty
        }

        It 'Should emit $null for Referer when the field is "-"' {
            $result = Get-IISParsedLog -Path $script:Log2
            $result.Referer | Should -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    # Context 3: -After / -Before time filtering
    # ------------------------------------------------------------------
    Context '-After and -Before time filtering applied during streaming' {

        BeforeAll {
            $ic = [System.Globalization.CultureInfo]::InvariantCulture
            $utcStyle = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor `
                        [System.Globalization.DateTimeStyles]::AdjustToUniversal
            $script:TS_1001 = [datetime]::ParseExact('2026-05-14 10:01:00', 'yyyy-MM-dd HH:mm:ss', $ic, $utcStyle)
            $script:TS_1002 = [datetime]::ParseExact('2026-05-14 10:02:00', 'yyyy-MM-dd HH:mm:ss', $ic, $utcStyle)
            $script:TS_far  = [datetime]::ParseExact('2026-05-15 00:00:00', 'yyyy-MM-dd HH:mm:ss', $ic, $utcStyle)
        }

        It 'Should include the entry AT the -After bound (inclusive lower bound)' {
            $results = Get-IISParsedLog -Path $script:Log1 -After $script:TS_1001
            $results.Count | Should -Be 2
            $results[0].UriStem | Should -Be '/api/data'
        }

        It 'Should exclude the entry AT the -Before bound (exclusive upper bound)' {
            $results = Get-IISParsedLog -Path $script:Log1 -Before $script:TS_1002
            $results.Count | Should -Be 2
            ($results | Where-Object UriStem -eq '/api/fail') | Should -BeNullOrEmpty
        }

        It 'Should return zero entries when -After is beyond all timestamps' {
            $results = Get-IISParsedLog -Path $script:Log1 -After $script:TS_far
            $results | Should -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    # Context 4: -Method filter
    # ------------------------------------------------------------------
    Context '-Method filter (case-insensitive, multi-value OR)' {

        It 'Should return only GET entries when -Method GET is specified' {
            $results = Get-IISParsedLog -Path $script:Log1 -Method 'GET'
            $results.Count | Should -Be 2
            $results | ForEach-Object { $_.Method | Should -Be 'GET' }
        }

        It 'Should match -Method case-insensitively (lowercase "get" input)' {
            $results = Get-IISParsedLog -Path $script:Log1 -Method 'get'
            $results.Count | Should -Be 2
        }

        It 'Should return all 3 entries when -Method GET,POST are specified (OR logic)' {
            $results = Get-IISParsedLog -Path $script:Log1 -Method 'GET', 'POST'
            $results.Count | Should -Be 3
        }
    }

    # ------------------------------------------------------------------
    # Context 5: -Status filter
    # ------------------------------------------------------------------
    Context '-Status filter (multi-value OR, integer matching)' {

        It 'Should return only the 500 entry when -Status 500 is specified' {
            $results = Get-IISParsedLog -Path $script:Log1 -Status 500
            $results.Count | Should -Be 1
            $results[0].HttpStatus | Should -Be 500
            $results[0].UriStem   | Should -Be '/api/fail'
        }

        It 'Should return 2 entries when -Status 404,500 are specified (OR logic)' {
            $results = Get-IISParsedLog -Path $script:Log1 -Status 404, 500
            $results.Count | Should -Be 2
        }

        It 'Should return zero entries when -Status matches no entry in the file' {
            $results = Get-IISParsedLog -Path $script:Log1 -Status 503
            $results | Should -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    # Context 6: -UriLike and -ClientIP filters
    # ------------------------------------------------------------------
    Context '-UriLike wildcard and -ClientIP exact filters' {

        It 'Should return entries matching the -UriLike wildcard pattern "/api/*"' {
            $results = Get-IISParsedLog -Path $script:Log1 -UriLike '/api/*'
            $results.Count | Should -Be 2
            $results | ForEach-Object { $_.UriStem | Should -BeLike '/api/*' }
        }

        It 'Should return zero entries when -UriLike matches nothing' {
            $results = Get-IISParsedLog -Path $script:Log1 -UriLike '/notexist/*'
            $results | Should -BeNullOrEmpty
        }

        It 'Should return only entries from the specified -ClientIP (exact match)' {
            $results = Get-IISParsedLog -Path $script:Log1 -ClientIP '10.0.0.42'
            $results.Count | Should -Be 1
            $results[0].ClientIP | Should -Be '10.0.0.42'
        }

        It 'Should support multi-value OR for -ClientIP (two IPs)' {
            $results = Get-IISParsedLog -Path $script:Log1 -ClientIP '10.0.0.42', '10.0.0.43'
            $results.Count | Should -Be 2
        }
    }

    # ------------------------------------------------------------------
    # Context 7: -Tail circular buffer
    # ------------------------------------------------------------------
    Context '-Tail parameter: circular buffer returns last N matching entries per file' {

        It 'Should return exactly N entries when -Tail N is less than total entries' {
            $results = Get-IISParsedLog -Path $script:Log4 -Tail 3
            $results.Count | Should -Be 3
        }

        It 'Should return the LAST N entries (not the first N) in chronological order' {
            $results = Get-IISParsedLog -Path $script:Log4 -Tail 3
            $results[0].UriStem | Should -Be '/c'
            $results[2].UriStem | Should -Be '/e'
        }

        It 'Should return all entries when -Tail N exceeds total file count' {
            $results = Get-IISParsedLog -Path $script:Log4 -Tail 100
            $results.Count | Should -Be 5
        }
    }

    # ------------------------------------------------------------------
    # Context 8: Pipeline by property name (FullName alias)
    # ------------------------------------------------------------------
    Context 'Pipeline by property name: FullName alias (simulates Get-ChildItem output)' {

        It 'Should accept a piped object with FullName property and parse all entries' {
            $pipeInput = [PSCustomObject]@{ FullName = $script:Log1 }
            $results = $pipeInput | Get-IISParsedLog
            $results.Count | Should -Be 3
        }

        It 'Should set LogFile equal to the FullName value from the piped object' {
            $pipeInput = [PSCustomObject]@{ FullName = $script:Log1 }
            $results = $pipeInput | Get-IISParsedLog
            $results[0].LogFile | Should -Be $script:Log1
        }

        It 'Should stream entries from multiple piped FullName objects in order' {
            $pipeInputs = @(
                [PSCustomObject]@{ FullName = $script:Log1 },
                [PSCustomObject]@{ FullName = $script:Log2 }
            )
            $results = $pipeInputs | Get-IISParsedLog
            $results.Count | Should -Be 4
        }
    }

    # ------------------------------------------------------------------
    # Context 9: Header re-detection (mid-file #Fields)
    # ------------------------------------------------------------------
    Context 'Header re-detection: mid-file #Fields directive rebinds column map' {

        It 'Should parse both sections correctly (2 data entries total)' {
            $results = Get-IISParsedLog -Path $script:Log3
            $results.Count | Should -Be 2
        }

        It 'Should set BytesSent to $null for lines before sc-bytes was added to #Fields' {
            $results = Get-IISParsedLog -Path $script:Log3
            $results[0].UriStem   | Should -Be '/before'
            $results[0].BytesSent | Should -BeNullOrEmpty
        }

        It 'Should set BytesSent correctly for lines after #Fields added sc-bytes' {
            $results = Get-IISParsedLog -Path $script:Log3
            $results[1].UriStem   | Should -Be '/after'
            $results[1].BytesSent | Should -Be 9999
        }
    }

    # ------------------------------------------------------------------
    # Context 10: Non-existent path -- Write-Error per ADR conventions
    # ------------------------------------------------------------------
    Context 'Non-existent path: Write-Error (terminating with -ErrorAction Stop)' {

        It 'Should throw when -ErrorAction Stop is used for a missing path' {
            { Get-IISParsedLog -Path '/tmp/pswinops_nosuchfile_test.log' -ErrorAction Stop } |
                Should -Throw
        }

        It 'Should return nothing when -ErrorAction SilentlyContinue suppresses the error' {
            $results = Get-IISParsedLog -Path '/tmp/pswinops_nosuchfile_test.log' `
                -ErrorAction SilentlyContinue
            $results | Should -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    # Context 11: UserAgent / Referer decoding
    # ------------------------------------------------------------------
    Context 'UserAgent decoding: IIS "+" in cs(User-Agent) decoded back to space' {

        It 'Should decode "+" to space in UserAgent field (first entry)' {
            $result = Get-IISParsedLog -Path $script:Log1 | Select-Object -First 1
            $result.UserAgent | Should -Be 'Mozilla/5.0 (Windows NT 10.0)'
        }

        It 'Should decode "+" to space in UserAgent field (third entry)' {
            $results = Get-IISParsedLog -Path $script:Log1
            $results[2].UserAgent | Should -Be 'Python Requests/2.28'
        }

        It 'Should leave UriStem as-logged (URL-encoded by IIS, no + decoding applied)' {
            $result = Get-IISParsedLog -Path $script:Log1 | Select-Object -First 1
            $result.UriStem | Should -Be '/index.html'
        }
    }

    # ------------------------------------------------------------------
    # Context 12: LiteralPath parameter set
    # ------------------------------------------------------------------
    Context 'LiteralPath parameter set: no wildcard expansion, exact file path' {

        It 'Should parse the file correctly when -LiteralPath is used' {
            $results = Get-IISParsedLog -LiteralPath $script:Log1
            $results.Count | Should -Be 3
        }

        It 'Should set LogFile to the resolved LiteralPath value' {
            $results = Get-IISParsedLog -LiteralPath $script:Log1
            $results[0].LogFile | Should -Be $script:Log1
        }

        It 'Should throw for a non-existent LiteralPath when -ErrorAction Stop is used' {
            { Get-IISParsedLog -LiteralPath '/tmp/pswinops_nosuchfile_literal.log' -ErrorAction Stop } |
                Should -Throw
        }
    }

    # ------------------------------------------------------------------
    # Context 13: BOM/CRLF sentinel
    # ------------------------------------------------------------------
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
