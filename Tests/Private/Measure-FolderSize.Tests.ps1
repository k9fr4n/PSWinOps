#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Invoke the private helper through the module's session state.
    function script:InvokeMeasure {
        param([hashtable]$Params)
        & (Get-Module -Name 'PSWinOps') {
            param($p)
            $splat = @{ Path = $p.Path }
            if ($p.IncludeFiles) { $splat['IncludeFiles'] = $true }
            if ($p.OnProgress) { $splat['OnProgress'] = $p.OnProgress }
            Measure-FolderSize @splat
        } $Params
    }

    # Build a fixture tree of exactly-known byte sizes under a REAL TestDrive.
    #   Root\
    #     ChildA\  fileA1 (100) + SubA\fileA2 (50)  => 150 bytes, 2 files
    #     ChildB\  fileB1 (200)                      => 200 bytes, 1 file
    #     EmptyChild\                                 =>   0 bytes, 0 files
    #     loose1.txt (10)                             loose files under Root
    #     loose2.txt (20, hidden)
    $script:root = Join-Path -Path $TestDrive -ChildPath 'Root'

    function script:NewByteFile {
        param([string]$FilePath, [int]$Size)
        [System.IO.File]::WriteAllBytes($FilePath, [byte[]]::new($Size))
    }

    $childA = Join-Path -Path $script:root -ChildPath 'ChildA'
    $subA   = Join-Path -Path $childA      -ChildPath 'SubA'
    $childB = Join-Path -Path $script:root -ChildPath 'ChildB'
    $empty  = Join-Path -Path $script:root -ChildPath 'EmptyChild'
    $null = New-Item -Path $subA  -ItemType Directory -Force
    $null = New-Item -Path $childB -ItemType Directory -Force
    $null = New-Item -Path $empty  -ItemType Directory -Force

    NewByteFile -FilePath (Join-Path $childA 'fileA1.txt') -Size 100
    NewByteFile -FilePath (Join-Path $subA   'fileA2.txt') -Size 50
    NewByteFile -FilePath (Join-Path $childB 'fileB1.txt') -Size 200

    NewByteFile -FilePath (Join-Path $script:root 'loose1.txt') -Size 10
    $hidden = Join-Path $script:root 'loose2.txt'
    NewByteFile -FilePath $hidden -Size 20
    [System.IO.File]::SetAttributes($hidden, [System.IO.FileAttributes]::Hidden)
}

Describe 'Measure-FolderSize' {

    Context 'Directory sizing (fixture tree of known size)' {

        BeforeAll {
            $script:result = script:InvokeMeasure @{ Path = $script:root }
        }

        It 'returns exact SizeBytes and FileCount for a child with nested content' {
            $childA = $script:result | Where-Object { $_.Name -eq 'ChildA' }
            $childA               | Should -Not -BeNullOrEmpty
            $childA.SizeBytes     | Should -Be 150
            $childA.FileCount     | Should -Be 2
            $childA.IsContainer   | Should -BeTrue
            $childA.Inaccessible  | Should -Be 0
        }

        It 'returns exact SizeBytes and FileCount for a flat child' {
            $childB = $script:result | Where-Object { $_.Name -eq 'ChildB' }
            $childB.SizeBytes | Should -Be 200
            $childB.FileCount | Should -Be 1
        }

        It 'emits an empty child directory with zero size and count (not omitted)' {
            $empty = $script:result | Where-Object { $_.Name -eq 'EmptyChild' }
            $empty            | Should -Not -BeNullOrEmpty
            $empty.SizeBytes  | Should -Be 0
            $empty.FileCount  | Should -Be 0
            $empty.IsContainer| Should -BeTrue
        }

        It 'never walks beyond one level (no grandchild entries emitted)' {
            ($script:result | Where-Object { $_.Name -eq 'SubA' }) | Should -BeNullOrEmpty
        }
    }

    Context 'Loose files aggregation' {

        BeforeAll {
            $script:result = script:InvokeMeasure @{ Path = $script:root }
        }

        It 'surfaces loose files as the (files) synthetic entry, not attributed to a child' {
            $files = $script:result | Where-Object { $_.Name -eq '(files)' }
            $files             | Should -Not -BeNullOrEmpty
            $files.FullName    | Should -Be $script:root
            $files.IsContainer | Should -BeTrue
        }

        It 'counts hidden files in the loose-files aggregate (Force enumeration)' {
            $files = $script:result | Where-Object { $_.Name -eq '(files)' }
            $files.SizeBytes | Should -Be 30   # 10 + 20 (hidden)
            $files.FileCount | Should -Be 2
        }
    }

    Context 'IncludeFiles switch' {

        It 'off by default emits no per-file entries' {
            $result = script:InvokeMeasure @{ Path = $script:root }
            ($result | Where-Object { $_.IsContainer -eq $false }) | Should -BeNullOrEmpty
        }

        It 'on emits one entry per loose file with IsContainer = $false' {
            $result = script:InvokeMeasure @{ Path = $script:root; IncludeFiles = $true }
            $fileEntries = $result | Where-Object { $_.IsContainer -eq $false }
            $fileEntries.Count                 | Should -Be 2
            ($fileEntries.Name | Sort-Object)  | Should -Be @('loose1.txt', 'loose2.txt')
            ($fileEntries | Where-Object { $_.Name -eq 'loose1.txt' }).SizeBytes | Should -Be 10
        }
    }

    Context 'CollectGrandchildren switch' {

        It 'populates the GrandchildMap with per-grandchild totals keyed by full path' {
            $map = & (Get-Module -Name 'PSWinOps') {
                param($p)
                $local = @{}
                $null = Measure-FolderSize -Path $p -CollectGrandchildren -GrandchildMap ([ref]$local)
                return $local
            } $script:root

            $subA = Join-Path -Path (Join-Path -Path $script:root -ChildPath 'ChildA') -ChildPath 'SubA'

            $map.Keys.Count         | Should -Be 1
            $map.ContainsKey($subA) | Should -BeTrue
            $map[$subA].SizeBytes   | Should -Be 50
            $map[$subA].FileCount   | Should -Be 1
        }

        It 'keeps the primary output unchanged when CollectGrandchildren is on' {
            $baseline = @(script:InvokeMeasure @{ Path = $script:root })
            $collected = @(& (Get-Module -Name 'PSWinOps') {
                    param($p)
                    $local = @{}
                    Measure-FolderSize -Path $p -CollectGrandchildren -GrandchildMap ([ref]$local)
                } $script:root)

            $baselineProj = @($baseline | Sort-Object -Property FullName | ForEach-Object {
                    '{0}|{1}|{2}|{3}' -f $_.Name, $_.FullName, $_.SizeBytes, $_.FileCount
                })
            $collectedProj = @($collected | Sort-Object -Property FullName | ForEach-Object {
                    '{0}|{1}|{2}|{3}' -f $_.Name, $_.FullName, $_.SizeBytes, $_.FileCount
                })

            $collectedProj | Should -Be $baselineProj
        }

        It 'leaves the GrandchildMap empty when CollectGrandchildren is off' {
            $map = & (Get-Module -Name 'PSWinOps') {
                param($p)
                $local = @{}
                $null = Measure-FolderSize -Path $p -GrandchildMap ([ref]$local)
                return $local
            } $script:root

            $map.Keys.Count | Should -Be 0
        }
    }

    Context 'Bad path handling (non-terminating, returns nothing, no throw)' {

        It 'writes an error and returns nothing for a non-existent path' {
            $missing = Join-Path -Path $TestDrive -ChildPath 'DoesNotExist'
            $out = & (Get-Module -Name 'PSWinOps') {
                param($p) Measure-FolderSize -Path $p -ErrorAction SilentlyContinue
            } $missing
            $out | Should -BeNullOrEmpty

            $errs = & (Get-Module -Name 'PSWinOps') {
                param($p) Measure-FolderSize -Path $p -ErrorAction Continue 2>&1
            } $missing | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }
            $errs.Count | Should -BeGreaterThan 0
        }

        It 'does not throw for a non-existent path' {
            $missing = Join-Path -Path $TestDrive -ChildPath 'DoesNotExist'
            {
                & (Get-Module -Name 'PSWinOps') {
                    param($p) Measure-FolderSize -Path $p -ErrorAction SilentlyContinue
                } $missing
            } | Should -Not -Throw
        }

        It 'writes an error and returns nothing when Path points at a file' {
            $filePath = Join-Path -Path $script:root -ChildPath 'loose1.txt'
            $out = & (Get-Module -Name 'PSWinOps') {
                param($p) Measure-FolderSize -Path $p -ErrorAction SilentlyContinue
            } $filePath
            $out | Should -BeNullOrEmpty

            $errs = & (Get-Module -Name 'PSWinOps') {
                param($p) Measure-FolderSize -Path $p -ErrorAction Continue 2>&1
            } $filePath | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }
            $errs.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Parameter validation' {

        It 'rejects an empty Path' {
            { & (Get-Module -Name 'PSWinOps') { Measure-FolderSize -Path '' } } | Should -Throw
        }

        It 'rejects a null Path' {
            { & (Get-Module -Name 'PSWinOps') { Measure-FolderSize -Path $null } } | Should -Throw
        }
    }

    Context 'Inaccessible subtree is absorbed, others still returned' {

        It 'counts collected errors into Inaccessible without discarding sibling children' {
            # Fail only the recursive read of the blocked child; every other
            # Get-ChildItem call falls through to the real command (real fixture data).
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' `
                -ParameterFilter { $Recurse -and $LiteralPath -like '*ChildA*' } `
                -MockWith { Write-Error 'Access to the path is denied.' -ErrorAction Continue }

            $result = script:InvokeMeasure @{ Path = $script:root }

            $blocked = $result | Where-Object { $_.Name -eq 'ChildA' }
            $blocked.Inaccessible | Should -BeGreaterThan 0
            $blocked.SizeBytes    | Should -Be 0
            $blocked.FileCount    | Should -Be 0

            # A sibling that was not blocked is still measured correctly.
            $sibling = $result | Where-Object { $_.Name -eq 'ChildB' }
            $sibling           | Should -Not -BeNullOrEmpty
            $sibling.SizeBytes | Should -Be 200

            Should -Invoke -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' `
                -ParameterFilter { $Recurse -and $LiteralPath -like '*ChildA*' } -Times 1
        }
    }

    Context 'OnProgress callback' {

        It 'reports one folder counter per child with cumulative file counts' {
            $reports = [System.Collections.Generic.List[object]]::new()
            $callback = { param($p) $reports.Add($p) }.GetNewClosure()

            $null = script:InvokeMeasure @{ Path = $script:root; OnProgress = $callback }

            $reports.Count | Should -BeGreaterOrEqual 3
            foreach ($r in $reports) {
                $r.FolderCount | Should -Be 3
            }
            [int]($reports | Measure-Object -Property FolderIndex -Maximum).Maximum | Should -Be 3
            [int]($reports | Measure-Object -Property FileCount -Maximum).Maximum | Should -Be 3
        }

        It 'reports the documented progress shape' {
            $reports = [System.Collections.Generic.List[object]]::new()
            $callback = { param($p) $reports.Add($p) }.GetNewClosure()

            $null = script:InvokeMeasure @{ Path = $script:root; OnProgress = $callback }

            $last = $reports[$reports.Count - 1]
            foreach ($name in @('FolderIndex', 'FolderCount', 'FileCount', 'Bytes', 'CurrentName')) {
                $last.PSObject.Properties.Name | Should -Contain $name
            }
        }
    }

    Context 'Reparse point handling (Windows junction)' -Tag 'Integration' {

        It 'skips a reparse-point child with SizeBytes = 0 and a skip indication' -Skip:(-not (
                [System.Security.Principal.WindowsPrincipal]::new(
                    [System.Security.Principal.WindowsIdentity]::GetCurrent()
                ).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))) {

            $junction = Join-Path -Path $script:root -ChildPath 'JunctionChild'
            $null = New-Item -ItemType Junction -Path $junction -Target (Join-Path $script:root 'ChildB')

            $result = script:InvokeMeasure @{ Path = $script:root }
            $entry = $result | Where-Object { $_.Name -eq 'JunctionChild' }
            $entry               | Should -Not -BeNullOrEmpty
            $entry.SizeBytes     | Should -Be 0
            $entry.Inaccessible  | Should -BeGreaterThan 0

            Remove-Item -Path $junction -Force -Recurse
        }
    }
}
