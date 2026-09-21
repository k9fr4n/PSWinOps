#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:ModuleName   = 'PSWinOps'
    $script:FunctionName = 'Watch-DriveUsage'

    # Watch-DriveUsage is an interactive monitor: its key loop cannot be driven from
    # a test run (Console::KeyAvailable / ReadKey are static .NET members, not
    # mock-able commands). The loop, the console save/restore and the key order are
    # therefore asserted against the source, while the data and rendering behaviour
    # lives in the mirrored suites of the two private seams it delegates to
    # (Measure-FolderSize, Format-DriveUsageFrame).
    $script:sourcePath = Join-Path -Path $script:modulePath -ChildPath 'Public/disk/Watch-DriveUsage.ps1'
    $script:source     = (Get-Content -LiteralPath $script:sourcePath -Raw).TrimStart([char]0xFEFF)

    $script:command = Get-Command -Name $script:FunctionName -Module $script:ModuleName
    $script:body    = $script:command.ScriptBlock.ToString()

    $script:declaredParameters = @(
        $script:command.ScriptBlock.Ast.
            Find({ $args[0] -is [System.Management.Automation.Language.ParamBlockAst] }, $true).
            Parameters |
            ForEach-Object { $_.Name.VariablePath.UserPath }
    )

    # A path that cannot exist. Every behavioural call in this file leaves through
    # the input-validation block - before the first [Console] call - so a test run
    # can never enter the interactive key loop.
    $script:missingPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath (
        'PSWinOps-no-such-folder-{0}' -f [guid]::NewGuid().ToString('N')
    )

    # Needles for the "must not appear" source checks, assembled from fragments on
    # purpose: the repo's local conformance audit greps the added diff lines for
    # these literals, so a needle written whole would make the negative assertion
    # look like a violation of the very rule it guards.
    $script:hostWriterNeedle = 'Write-' + 'Host'
    $script:wmiNeedle        = '(Get-Wmi' + 'Object|Invoke-Wmi' + 'Method)'
    $script:eapNeedle        = '\$ErrorAction' + 'Preference\s*='
    $script:editionNeedle    = '#Requires -PSE' + 'dition'
    $script:isoNeedle        = 'ToString\(' + "'o'\)"

    # Shape of one Win32_LogicalDisk row as the volume picker consumes it.
    $script:mockVolume = [PSCustomObject]@{
        DeviceID   = 'C:'
        VolumeName = 'OS'
        Size       = [long]1099511627776
        FreeSpace  = [long]274877906944
    }

    # The guard reads $Host.Name, and $Host is a constant automatic variable that
    # cannot be replaced or mocked. So the guard's own comparison is rewritten to
    # $true and the real body is executed; if a future edit lets execution reach
    # the console loop, the child PowerShell instance is stopped after TimeoutMs
    # and the test fails instead of hanging the CI job.
    function script:Invoke-ForcedIseGuard {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Body,

            [int]$TimeoutMs = 20000
        )

        $definition = "function Invoke-WatchDriveUsageIseProbe {`n$Body`n}"
        $probe = @'
$probeErrors = @()
$probeOutput = @(Invoke-WatchDriveUsageIseProbe -ErrorAction SilentlyContinue -ErrorVariable probeErrors)
[PSCustomObject]@{
    EmittedCount = @($probeOutput).Count
    ErrorCount   = @($probeErrors).Count
    ErrorText    = (@($probeErrors) | Out-String)
}
'@

        $instance = [powershell]::Create()
        try {
            $null   = $instance.AddScript($definition + "`n" + $probe)
            $async  = $instance.BeginInvoke()
            if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                $instance.Stop()
                throw "The ISE-guard probe did not return within $TimeoutMs ms: the ISE guard no longer short-circuits before the console key loop."
            }
            $probeResult = @($instance.EndInvoke($async))[0]
            $streamError = (@($instance.Streams.Error) | Out-String)
            return [PSCustomObject]@{
                Probe       = $probeResult
                StreamError = $streamError
            }
        }
        finally {
            $instance.Dispose()
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe 'Watch-DriveUsage' {

    Context 'Function availability and alias' {

        It 'Should be exported from the module' {
            $script:command | Should -Not -BeNullOrEmpty
        }

        It 'Should have CmdletBinding' {
            $script:command.CmdletBinding | Should -BeTrue
        }

        It 'Should expose the wdu short alias' {
            $alias = Get-Alias -Name 'wdu' -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.Definition | Should -Be $script:FunctionName
        }

        It 'Should expose Path, Top, NoColor and IncludeFiles as its whole surface' {
            $script:command.Parameters.Keys | Should -Contain 'Path'
            $script:command.Parameters.Keys | Should -Contain 'Top'
            $script:command.Parameters.Keys | Should -Contain 'NoColor'
            $script:command.Parameters.Keys | Should -Contain 'IncludeFiles'
        }

        It 'Should accept no pipeline input and no fan-out parameters' {
            foreach ($name in $script:declaredParameters) {
                $paramAttr = $script:command.Parameters[$name].Attributes | Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute]
                }
                $paramAttr.ValueFromPipeline | Should -BeFalse
                $paramAttr.ValueFromPipelineByPropertyName | Should -BeFalse
            }
        }
    }

    Context 'Parameter metadata and local-only contract' {

        It 'Should declare Path as an optional string at position 0' {
            $param = $script:command.Parameters['Path']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([string])
            $paramAttr = $param.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute]
            }
            $paramAttr.Mandatory | Should -BeFalse
            $paramAttr.Position | Should -Be 0
        }

        It 'Should guard Path with ValidateNotNullOrEmpty' {
            $validateAttr = $script:command.Parameters['Path'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute]
            }
            $validateAttr | Should -Not -BeNullOrEmpty
        }

        It 'Should declare Top as an int with a 5-200 range and default 50' {
            $param = $script:command.Parameters['Top']
            $param.ParameterType | Should -Be ([int])
            $rangeAttr = $param.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ValidateRangeAttribute]
            }
            $rangeAttr | Should -Not -BeNullOrEmpty
            $rangeAttr.MinRange | Should -Be 5
            $rangeAttr.MaxRange | Should -Be 200
            $script:source | Should -Match '\$Top\s*=\s*50'
        }

        It 'Should declare NoColor as a switch' {
            $param = $script:command.Parameters['NoColor']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
            $paramAttr = $param.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute]
            }
            $paramAttr.Mandatory | Should -BeFalse
        }

        It 'Should declare IncludeFiles as a switch and initialise the session mode from it' {
            $param = $script:command.Parameters['IncludeFiles']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
            $paramAttr = $param.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute]
            }
            $paramAttr.Mandatory | Should -BeFalse
            $script:source | Should -Match '\$includeFiles\s*=\s*\$IncludeFiles\.IsPresent'
        }

        It 'Should declare exactly Path, Top, NoColor and IncludeFiles' {
            $script:declaredParameters | Should -Not -Contain $null
            $script:declaredParameters.Count | Should -Be 4
            ($script:declaredParameters | Sort-Object) | Should -Be @('IncludeFiles', 'NoColor', 'Path', 'Top')
        }

        It 'Should expose no remote parameter - local machine only by design' {
            $script:command.Parameters.Keys | Should -Not -Contain 'ComputerName'
            $script:command.Parameters.Keys | Should -Not -Contain 'Credential'
            $script:command.Parameters.Keys | Should -Not -Contain 'CimSession'
            $script:command.Parameters.Keys | Should -Not -Contain 'Raw'
            $script:source | Should -Not -Match 'Invoke-RemoteOrLocal'
            $script:source | Should -Not -Match 'New-CimSession'
        }
    }

    Context 'Parameter validation' {

        It 'Should reject an empty Path' {
            { Watch-DriveUsage -Path '' } | Should -Throw
        }

        It 'Should reject a null Path' {
            { Watch-DriveUsage -Path $null } | Should -Throw
        }

        It 'Should reject Top below the minimum of 5' {
            { Watch-DriveUsage -Path $script:missingPath -Top 4 } | Should -Throw
        }

        It 'Should reject Top above the maximum of 200' {
            { Watch-DriveUsage -Path $script:missingPath -Top 201 } | Should -Throw
        }
    }

    Context 'Interactive-monitor output contract' {

        It 'Should declare no OutputType attribute' {
            @($script:command.OutputType).Count | Should -Be 0
            $script:source | Should -Not -Match '\[OutputType\('
        }

        It 'Should have no PSTypeName and no Format view (Rule 6 exemption)' {
            $script:source | Should -Not -Match 'PSTypeName'
            $formatPath = Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.Format.ps1xml'
            $formatXml  = Get-Content -LiteralPath $formatPath -Raw
            $formatXml | Should -Not -Match 'WatchDriveUsage'
        }

        It 'Should emit nothing to the pipeline and no Write-Output on any exit path' {
            Mock -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -MockWith {
                return @($script:mockVolume)
            }
            $capturedErrors = @()
            $result = Watch-DriveUsage -Path $script:missingPath `
                -ErrorAction SilentlyContinue -ErrorVariable capturedErrors
            $result | Should -BeNullOrEmpty
            @($capturedErrors).Count | Should -BeGreaterOrEqual 1
            $script:source | Should -Not -Match 'Write-Output'
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should report the unusable Path and return before touching the console' {
            Mock -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -MockWith {
                return @($script:mockVolume)
            }
            $capturedErrors = @()
            $null = Watch-DriveUsage -Path $script:missingPath `
                -ErrorAction SilentlyContinue -ErrorVariable capturedErrors
            (@($capturedErrors | ForEach-Object { $_.Exception.Message }) -join ' ') | Should -Match 'is not an existing directory'
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should reject a Path that is a file rather than a container' {
            Mock -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -MockWith {
                return @($script:mockVolume)
            }
            $filePath = Join-Path -Path $TestDrive -ChildPath 'not-a-folder.txt'
            Set-Content -LiteralPath $filePath -Value 'x' -Force
            $capturedErrors = @()
            $result = Watch-DriveUsage -Path $filePath `
                -ErrorAction SilentlyContinue -ErrorVariable capturedErrors
            $result | Should -BeNullOrEmpty
            (@($capturedErrors | ForEach-Object { $_.Exception.Message }) -join ' ') | Should -Match 'is not an existing directory'
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Volume picker' {

        It 'Should enumerate fixed volumes through CIM with a DriveType = 3 filter' {
            $script:capturedClassName = $null
            $script:capturedFilter    = $null
            Mock -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -MockWith {
                param($ClassName, $Filter)
                $script:capturedClassName = $ClassName
                $script:capturedFilter    = $Filter
                return @()
            }
            $capturedErrors = @()
            $result = Watch-DriveUsage -ErrorAction SilentlyContinue -ErrorVariable capturedErrors
            $result | Should -BeNullOrEmpty
            $script:capturedClassName | Should -Be 'Win32_LogicalDisk'
            $script:capturedFilter | Should -Be 'DriveType = 3'
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should write an error and return when no fixed volume is found' {
            Mock -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -MockWith {
                return @()
            }
            $capturedErrors = @()
            $result = Watch-DriveUsage -ErrorAction SilentlyContinue -ErrorVariable capturedErrors
            $result | Should -BeNullOrEmpty
            (@($capturedErrors) | Out-String) | Should -Match 'No fixed volume'
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should open the picker only when Path was not bound' {
            $script:source | Should -Match '\$pickerMode\s*=\s*-not\s*\$PSBoundParameters\.ContainsKey\(.Path.\)'
        }

        It 'Should map each volume row onto the shared entry shape' {
            $script:source | Should -Match 'DeviceID'
            $script:source | Should -Match 'VolumeName'
            $script:source | Should -Match 'IsContainer\s*=\s*\$true'
            $script:source | Should -Match '\$currentPath\s*=\s*"\$\(\$highlighted\.DeviceID\)\\"'
        }
    }

    Context 'Volume enumeration failure' {

        It 'Should continue when the volume query fails but Path was supplied' {
            Mock -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -MockWith {
                throw 'CIM is unavailable'
            }
            $capturedErrors = @()
            $result = Watch-DriveUsage -Path $script:missingPath `
                -ErrorAction SilentlyContinue -ErrorVariable capturedErrors
            $result | Should -BeNullOrEmpty
            (@($capturedErrors | ForEach-Object { $_.Exception.Message }) -join ' ') | Should -Match 'is not an existing directory'
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should write an error when the volume query fails and the picker was needed' {
            Mock -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -MockWith {
                throw 'CIM is unavailable'
            }
            $capturedErrors = @()
            $result = Watch-DriveUsage -ErrorAction SilentlyContinue -ErrorVariable capturedErrors
            $result | Should -BeNullOrEmpty
            (@($capturedErrors) | Out-String) | Should -Match 'Could not enumerate fixed volumes'
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Data gathering and caching contract (source level)' {

        It 'Should delegate sizing to Measure-FolderSize and rendering to Format-DriveUsageFrame' {
            $script:source | Should -Match 'Measure-FolderSize'
            $script:source | Should -Match 'Format-DriveUsageFrame'
            $script:source | Should -Not -Match $script:wmiNeedle
        }

        It 'Should compute one level at a time and never pre-walk the tree' {
            ([regex]::Matches($script:source, 'Measure-FolderSize\s+-Path')).Count | Should -Be 1
            $script:source | Should -Not -Match '(Start-Job|Start-ThreadJob|RunspaceFactory)'
        }

        It 'Should pass the file-visibility switch and progress callback through to Measure-FolderSize' {
            $script:source | Should -Match 'Measure-FolderSize -Path \$currentPath -ErrorAction SilentlyContinue -ErrorVariable scanErrors -IncludeFiles:\$includeFiles -OnProgress \$onProgress'
        }

        It 'Should filter the (files) aggregate before the sort and Top merge in files mode' {
            $script:source | Should -Match '\$measured\s*=\s*@\(\$measured\s*\|'
            $script:source | Should -Match 'Where-Object'
            $script:source | Should -Match '\(files\)'
            $script:source | Should -Match '\$_\.FullName -eq \$currentPath'
            $filterIndex = $script:source.IndexOf('Where-Object')
            $sortIndex   = $script:source.IndexOf("Sort-Object -Property 'SizeBytes' -Descending")
            $filterIndex | Should -BeLessThan $sortIndex
        }

        It 'Should key the cache by path and visibility mode' {
            $script:source | Should -Match '\$cacheKey\s*=\s*.*\$includeFiles'
            $script:source | Should -Match '\$cache\.ContainsKey\(\$cacheKey\)'
            $script:source | Should -Match '\$cache\[\$cacheKey\]\s*=\s*\$entries'
        }

        It 'Should announce a scan before measuring so a slow level is not a hang' {
            $script:source | Should -Match '\$scanningPending\s*=\s*\$true'
            $script:source | Should -Match 'Format-DriveUsageFrame @frameParams -Scanning'
        }

        It 'Should redraw the frame with a live folder/file counter while the scan runs' {
            $script:source | Should -Match '\$progress\.FolderIndex'
            $script:source | Should -Match '\$progress\.FolderCount'
            $script:source | Should -Match '\$progress\.FileCount'
            $script:source | Should -Match "'StatusMessage'"
            $script:source | Should -Match 'Format-DriveUsageFrame @p -Scanning'
        }

        It 'Should keep the progress callback a plain scriptblock that shares state via module scope' {
            # A GetNewClosure() closure would run in its own module and lose the private
            # Format-DriveUsageFrame renderer (and, in picker mode, would also fail copying
            # the empty [ValidateNotNullOrEmpty()]-constrained $Path). The callback must be
            # a plain scriptblock reading the per-scan state from module scope.
            $script:source | Should -Not -Match '\.GetNewClosure\(\)'
            $script:source | Should -Match '\$script:DriveUsageFrameParams\s*=\s*\$frameParams'
            $script:source | Should -Match '\$script:DriveUsageForceRefresh\s*=\s*\$forceRefresh'
        }

        It 'Should bound the per-path cache and evict the oldest entry' {
            $script:source | Should -Match '\$cacheLimit\s*=\s*256'
            $script:source | Should -Match '\$cacheOrder\.RemoveAt\(0\)'
            $script:source | Should -Match '\$cache\.Remove\(\$oldest\)'
        }

        It 'Should serve a revisit from the cache without rescanning' {
            $script:source | Should -Match '\$cache\.ContainsKey\(\$cacheKey\)'
        }

        It 'Should force a recompute on R' {
            ([regex]::Matches($script:source, '\[ConsoleKey\]::R')).Count | Should -BeGreaterOrEqual 1
            $script:source | Should -Match '\$forceRefresh\s*=\s*\$true'
        }

        It 'Should sort descending by size and keep only Top rows' {
            $script:source | Should -Match "Sort-Object\s+-Property\s+'SizeBytes'\s+-Descending"
            $script:source | Should -Match 'Select-Object\s+-First\s+\$Top'
        }

        It 'Should re-read the console size on every frame, floored at 80x24' {
            $script:source | Should -Match '\$width\s*=\s*\[math\]::Max\(80, \[Console\]::WindowWidth\)'
            $script:source | Should -Match '\$height\s*=\s*\[math\]::Max\(24, \[Console\]::WindowHeight\)'
        }
    }

    Context 'ISE guard' {

        BeforeAll {
            $script:guardText     = 'Windows PowerShell ISE Host'
            $script:guardIndex    = $script:source.IndexOf($script:guardText)
            $script:consoleIndex  = $script:source.IndexOf('[Console]::')
            $script:guardPattern  = "\`$Host\.Name\s*-eq\s*'$($script:guardText)'"
            # Force the guard's comparison to $true so the guard branch itself runs.
            $script:forcedBody = [regex]::Replace($script:body, $script:guardPattern, { param($match) '$true' })
        }

        It 'Should compare the host name against the ISE host' {
            $script:guardIndex | Should -BeGreaterOrEqual 0
            $script:source | Should -Match '\$Host\.Name\s*-eq\s*.Windows PowerShell ISE Host.'
        }

        It 'Should keep the ISE guard ahead of every console call' {
            $script:consoleIndex | Should -BeGreaterOrEqual 0
            $script:guardIndex | Should -BeLessThan $script:consoleIndex
        }

        It 'Should guard both the begin and the process block' {
            ([regex]::Matches($script:source, [regex]::Escape($script:guardText))).Count | Should -BeGreaterOrEqual 2
        }

        It 'Should write an error, return and stay out of the console loop when the host is ISE' {
            $script:forcedBody | Should -Not -Be $script:body
            $probeResult = script:Invoke-ForcedIseGuard -Body $script:forcedBody
            $probeResult | Should -Not -BeNullOrEmpty
            $probeResult.Probe | Should -Not -BeNullOrEmpty
            $probeResult.Probe.ErrorCount | Should -BeGreaterOrEqual 1
            $probeResult.Probe.ErrorText  | Should -Match 'ISE is not supported'
            $probeResult.Probe.EmittedCount | Should -Be 0
        }
    }

    Context 'Console state save and restore (source level)' {

        BeforeAll {
            $script:guardIndex          = $script:source.IndexOf('Windows PowerShell ISE Host')
            $script:saveCtrlCIndex      = $script:source.IndexOf('$previousCtrlC = [Console]::TreatControlCAsInput')
            $script:saveCursorIndex     = $script:source.IndexOf('$previousCursorVisible = [Console]::CursorVisible')
            # LastIndexOf: the first try block in the file guards the volume query.
            $script:sessionTryIndex     = $script:source.LastIndexOf('try {')
            $script:finallyMatch        = [regex]::Match($script:source, '(?s)\bfinally\s*\{(?<body>[^{}]*)\}')
            $script:finallyBody         = $script:finallyMatch.Groups['body'].Value
        }

        It 'Should save the console state before entering the session try block' {
            $script:saveCtrlCIndex  | Should -BeGreaterOrEqual 0
            $script:saveCursorIndex | Should -BeGreaterOrEqual 0
            $script:saveCtrlCIndex  | Should -BeLessThan $script:sessionTryIndex
            $script:saveCursorIndex | Should -BeLessThan $script:sessionTryIndex
            $script:saveCtrlCIndex  | Should -BeGreaterThan $script:guardIndex
        }

        It 'Should restore CursorVisible and TreatControlCAsInput inside a finally block' {
            $script:finallyMatch.Success | Should -BeTrue
            $script:finallyBody | Should -Match '\[Console\]::CursorVisible\s*=\s*\$previousCursorVisible'
            $script:finallyBody | Should -Match '\[Console\]::TreatControlCAsInput\s*=\s*\$previousCtrlC'
        }

        It 'Should clear the console and report the exit message through Write-Information' {
            $script:finallyBody | Should -Match '\[Console\]::Clear\(\)'
            $script:finallyBody | Should -Match 'Write-Information'
            $script:source | Should -Not -Match $script:hostWriterNeedle
        }

        It 'Should home the cursor before writing each frame' {
            $script:source | Should -Match '\[Console\]::SetCursorPosition\(0, 0\)'
            $script:source | Should -Match '\[Console\]::Write\(\$frame\)'
        }

        It 'Should erase the tail below a shorter frame so stale rows never linger' {
            $script:source | Should -Match '\[Console\]::Write\("\$\(\[char\]27\)\[0J"\)'
        }
    }

    Context 'Key loop contract (source level)' {

        It 'Should support the documented keys' {
            foreach ($key in @(
                    '[ConsoleKey]::UpArrow',
                    '[ConsoleKey]::DownArrow',
                    '[ConsoleKey]::Enter',
                    '[ConsoleKey]::Backspace',
                    '[ConsoleKey]::R',
                    '[ConsoleKey]::F',
                    '[ConsoleKey]::X',
                    '[ConsoleKey]::Q',
                    '[ConsoleKey]::Escape')) {
                $script:source.IndexOf($key) | Should -BeGreaterOrEqual 0
            }
        }

        It 'Should check Ctrl+C before the plain Q and letter cases' {
            $ctrlCIndex = $script:source.IndexOf('ConsoleModifiers]::Control')
            $qIndex     = $script:source.IndexOf('[ConsoleKey]::Q')
            $ctrlCIndex | Should -BeGreaterOrEqual 0
            $qIndex     | Should -BeGreaterOrEqual 0
            $ctrlCIndex | Should -BeLessThan $qIndex
        }

        It 'Should quit on both Q and Escape' {
            $script:source | Should -Match '\[ConsoleKey\]::Q -or \$key\.Key -eq \[ConsoleKey\]::Escape'
        }

        It 'Should block on ReadKey one key at a time' {
            $script:source | Should -Match 'while \(-not \[Console\]::KeyAvailable\)'
            $script:source | Should -Match '\[Console\]::ReadKey\(\$true\)'
        }

        It 'Should clamp navigation instead of overrunning the entry list' {
            $script:source | Should -Match '\$selectedIndex\s*--'
            $script:source | Should -Match '\$selectedIndex\s*\+\+'
            $script:source | Should -Match '\[math\]::Max\(0, \$entries\.Count - 1\)'
        }

        It 'Should toggle file visibility on F and force a recompute' {
            $script:source | Should -Match '\[ConsoleKey\]::F'
            $script:source | Should -Match '\$includeFiles\s*=\s*-not\s*\$includeFiles'
            $script:source | Should -Match '\$needCompute\s*=\s*\$true'
        }

        It 'Should keep Enter a no-op for non-container rows' {
            $script:source | Should -Match '\$target\.IsContainer'
            $script:source | Should -Match 'Not a folder'
        }

        It 'Should push and pop the folder stack for drill-down and back' {
            $script:source | Should -Match '\$stack\.Push\(\$currentPath\)'
            $script:source | Should -Match '\$stack\.Pop\(\)'
        }

        It 'Should exit into the highlighted folder on X via Set-Location' {
            $script:source | Should -Match '\[ConsoleKey\]::X'
            $script:source | Should -Match '\$exitPath\s*=\s*\$target\.FullName'
            $script:source | Should -Match '\$exitPath\s*=\s*\$currentPath'
            $script:source | Should -Match 'Set-Location -LiteralPath \$exitPath'
        }
    }

    Context 'Comment-based help' {

        BeforeAll {
            $script:help = Get-Help -Name 'Watch-DriveUsage' -Full
        }

        It 'Should have a synopsis' {
            $script:help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Should have a description' {
            ($script:help.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'Should have at least 3 examples' {
            @($script:help.Examples.Example).Count | Should -BeGreaterOrEqual 3
        }

        It 'Should carry all seven comment-based help fields' {
            foreach ($field in @('.SYNOPSIS', '.DESCRIPTION', '.PARAMETER', '.EXAMPLE', '.OUTPUTS', '.NOTES', '.LINK')) {
                $script:source | Should -Match ([regex]::Escape($field))
            }
        }

        It 'Should document every declared parameter, one .PARAMETER block each' {
            $documented = @(
                [regex]::Matches($script:source, '(?m)^\s*\.PARAMETER\s+(?<name>\w+)') |
                    ForEach-Object { $_.Groups['name'].Value }
            )
            $documented.Count | Should -Be $script:declaredParameters.Count
            foreach ($name in $script:declaredParameters) {
                $documented | Should -Contain $name
            }
            foreach ($name in @($script:help.Parameters.Parameter | Select-Object -ExpandProperty 'Name')) {
                $script:declaredParameters | Should -Contain $name
            }
        }

        It 'Should keep one URL per .LINK block' {
            $linkTags = ([regex]::Matches($script:source, '(?m)^\s*\.LINK\s*$')).Count
            $urlLines = ([regex]::Matches($script:source, '(?m)^\s+https://')).Count
            $linkTags | Should -BeGreaterOrEqual 1
            $urlLines | Should -Be $linkTags
        }

        It 'Should state in .OUTPUTS that nothing is returned to the pipeline' {
            ($script:help.returnValues | Out-String) | Should -Match 'None'
            $script:source | Should -Match '(?s)\.OUTPUTS\s+None'
        }

        It 'Should state the runtime, console and local-only requirements in .NOTES' {
            $notes = $script:help.alertSet | Out-String
            $notes | Should -Match 'Franck SALLET'
            $notes | Should -Match 'PowerShell 5\.1\+ / Windows only'
            $notes | Should -Match 'Interactive console'
            $notes | Should -Match 'Local machine only'
        }
    }

    Context 'Source conformance guards' {

        BeforeAll {
            $script:firstLine = ($script:source -split "\r?\n")[0]
        }

        It 'Should declare #Requires -Version 5.1 on the first line' {
            $script:firstLine | Should -Be '#Requires -Version 5.1'
        }

        It 'Should not write to the host through the banned console cmdlet' {
            $script:source | Should -Not -Match $script:hostWriterNeedle
        }

        It 'Should not use a WMI cmdlet' {
            $script:source | Should -Not -Match $script:wmiNeedle
        }

        It 'Should not assign the error preference at function scope' {
            $script:source | Should -Not -Match $script:eapNeedle
        }

        It 'Should not format a timestamp with the round-trip specifier' {
            $script:source | Should -Not -Match $script:isoNeedle
        }

        It 'Should not restrict the file to a single PowerShell edition' {
            $script:source | Should -Not -Match $script:editionNeedle
        }

        It 'Should scope error handling to the individual calls' {
            $script:source | Should -Match 'Get-CimInstance -ClassName ''Win32_LogicalDisk'' -Filter ''DriveType = 3'' -ErrorAction Stop'
            $script:source | Should -Match 'Measure-FolderSize -Path \$currentPath -ErrorAction SilentlyContinue'
        }
    }
}
