#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # A fixture tree of exactly-known sizes and ages, so the local contexts
    # exercise the real aggregation scriptblock (tree walk, reparse-point skip,
    # ageing against a single clock reading, per-bucket summing, percentage and
    # row mapping) end to end. One file per bucket keeps every expectation
    # exact:
    #
    #   Tree\newest.log       1 MB,   1 d old  -> 0-7d
    #   Tree\week.log         1 MB,  10 d old  -> 7-30d
    #   Tree\month.log        1 MB,  60 d old  -> 30-90d
    #   Tree\quarter.log      1 MB, 120 d old  -> 90-180d
    #   Tree\halfyear.log     2 MB, 200 d old  -> 180-365d
    #   Tree\year.log         4 MB, 500 d old  -> 1-2y
    #   Tree\Sub\archive.log  8 MB, 800 d old  -> >2y      (proves recursion)
    #   Tree\EmptySub\                                     (walked, no row)
    #
    # Total is exactly 18 MB over 7 files, so every MB/percent value below is
    # exact (size / 18 MB) and a mis-bucket or a double-count cannot hide in
    # rounding noise.
    $script:treeRoot = Join-Path -Path $TestDrive -ChildPath 'Tree'
    $script:subRoot = Join-Path -Path $script:treeRoot -ChildPath 'Sub'
    $script:emptyRoot = Join-Path -Path $TestDrive -ChildPath 'EmptyTree'
    $script:boundaryRoot = Join-Path -Path $TestDrive -ChildPath 'BoundaryTree'
    $script:futureRoot = Join-Path -Path $TestDrive -ChildPath 'FutureTree'
    # Real (empty) root for the contexts that stub the directory enumeration:
    # the root existence probe still runs against the filesystem.
    $script:mockRoot = Join-Path -Path $TestDrive -ChildPath 'MockRoot'

    function script:NewAgedFile {
        param(
            [string]$FilePath,
            [int]$Size,
            [double]$AgeDays
        )
        [System.IO.File]::WriteAllBytes($FilePath, [byte[]]::new($Size))
        $stamp = (Get-Date).AddDays(-$AgeDays)
        [System.IO.File]::SetLastWriteTime($FilePath, $stamp)
        [System.IO.File]::SetCreationTime($FilePath, $stamp)
        [System.IO.File]::SetLastAccessTime($FilePath, $stamp)
    }

    $null = New-Item -Path $script:subRoot -ItemType Directory -Force
    $null = New-Item -Path (Join-Path -Path $script:treeRoot -ChildPath 'EmptySub') -ItemType Directory -Force
    $null = New-Item -Path (Join-Path -Path $script:emptyRoot -ChildPath 'Nothing') -ItemType Directory -Force
    $null = New-Item -Path $script:boundaryRoot -ItemType Directory -Force
    $null = New-Item -Path $script:futureRoot -ItemType Directory -Force
    $null = New-Item -Path $script:mockRoot -ItemType Directory -Force

    NewAgedFile -FilePath (Join-Path -Path $script:treeRoot -ChildPath 'newest.log') -Size 1048576 -AgeDays 1
    NewAgedFile -FilePath (Join-Path -Path $script:treeRoot -ChildPath 'week.log') -Size 1048576 -AgeDays 10
    NewAgedFile -FilePath (Join-Path -Path $script:treeRoot -ChildPath 'month.log') -Size 1048576 -AgeDays 60
    NewAgedFile -FilePath (Join-Path -Path $script:treeRoot -ChildPath 'quarter.log') -Size 1048576 -AgeDays 120
    NewAgedFile -FilePath (Join-Path -Path $script:treeRoot -ChildPath 'halfyear.log') -Size 2097152 -AgeDays 200
    NewAgedFile -FilePath (Join-Path -Path $script:treeRoot -ChildPath 'year.log') -Size 4194304 -AgeDays 500
    NewAgedFile -FilePath (Join-Path -Path $script:subRoot -ChildPath 'archive.log') -Size 8388608 -AgeDays 800

    # A second real tree probes the half-open bounds (MinAgeDays inclusive,
    # MaxAgeDays exclusive). Each file sits either exactly on a bound or one
    # minute inside it: the scan reads its own clock a moment later, so an
    # "exactly N days" file is guaranteed to have aged past N (pinning the
    # inclusive lower bound) while the "one minute under" file must stay in
    # the younger bucket.
    NewAgedFile -FilePath (Join-Path -Path $script:boundaryRoot -ChildPath 'at7d.bin') -Size 1048576 -AgeDays 7
    NewAgedFile -FilePath (Join-Path -Path $script:boundaryRoot -ChildPath 'under7d.bin') -Size 2097152 -AgeDays (7 - (1 / 1440))
    NewAgedFile -FilePath (Join-Path -Path $script:boundaryRoot -ChildPath 'at30d.bin') -Size 3145728 -AgeDays 30
    NewAgedFile -FilePath (Join-Path -Path $script:boundaryRoot -ChildPath 'under30d.bin') -Size 4194304 -AgeDays (30 - (1 / 1440))
    NewAgedFile -FilePath (Join-Path -Path $script:boundaryRoot -ChildPath 'at730d.bin') -Size 5242880 -AgeDays 730
    NewAgedFile -FilePath (Join-Path -Path $script:boundaryRoot -ChildPath 'under730d.bin') -Size 6291456 -AgeDays (730 - (1 / 1440))

    # A future-dated file (clock skew, restored archive) must clamp into the
    # newest bucket instead of falling through every bucket.
    NewAgedFile -FilePath (Join-Path -Path $script:futureRoot -ChildPath 'future.bin') -Size 1048576 -AgeDays -10

    # Seven rows standing in for the target-side aggregation, so the remote
    # contexts (single machine, property forwarding, credential, pipeline,
    # per-machine failure) stay deterministic: only the dispatch, the parameter
    # forwarding and the row mapping are under test there. $TargetPath is echoed
    # back so the forwarded -ArgumentList[0] is proven by the returned Path
    # property, and $AgeProperty so -ArgumentList[1] is proven by AgeProperty.
    $script:makeRows = {
        param(
            [string]$TargetPath,
            [string]$AgeProperty = 'LastWriteTime',
            [long]$Inaccessible = 2
        )

        $spec = @(
            @{ AgeBucket = '>2y'; MinAgeDays = [int]730; MaxAgeDays = [int]::MaxValue; SizeBytes = [long]8388608; Percent = [double]44.44 }
            @{ AgeBucket = '1-2y'; MinAgeDays = [int]365; MaxAgeDays = [int]730; SizeBytes = [long]4194304; Percent = [double]22.22 }
            @{ AgeBucket = '180-365d'; MinAgeDays = [int]180; MaxAgeDays = [int]365; SizeBytes = [long]2097152; Percent = [double]11.11 }
            @{ AgeBucket = '90-180d'; MinAgeDays = [int]90; MaxAgeDays = [int]180; SizeBytes = [long]1048576; Percent = [double]5.56 }
            @{ AgeBucket = '30-90d'; MinAgeDays = [int]30; MaxAgeDays = [int]90; SizeBytes = [long]1048576; Percent = [double]5.56 }
            @{ AgeBucket = '7-30d'; MinAgeDays = [int]7; MaxAgeDays = [int]30; SizeBytes = [long]1048576; Percent = [double]5.56 }
            @{ AgeBucket = '0-7d'; MinAgeDays = [int]0; MaxAgeDays = [int]7; SizeBytes = [long]1048576; Percent = [double]5.56 }
        )

        foreach ($bucket in $spec) {
            [PSCustomObject]@{
                Path              = $TargetPath
                AgeBucket         = $bucket.AgeBucket
                MinAgeDays        = $bucket.MinAgeDays
                MaxAgeDays        = $bucket.MaxAgeDays
                FileCount         = [long]1
                SizeBytes         = $bucket.SizeBytes
                SizeMB            = [double][math]::Round($bucket.SizeBytes / 1MB, 2)
                PercentOfTotal    = $bucket.Percent
                TotalSizeBytes    = [long]18874368
                TotalFileCount    = [long]7
                AgeProperty       = $AgeProperty
                InaccessibleCount = $Inaccessible
            }
        }
    }
}

Describe 'Show-FolderUsageAge' {

    Context 'Local happy path (real fixture tree)' {

        BeforeAll {
            $script:result = @(Show-FolderUsageAge -Path $script:treeRoot)
            $script:byBucket = @{}
            foreach ($row in $script:result) {
                $script:byBucket[$row.AgeBucket] = $row
            }
        }

        It -Name 'Should return PSWinOps.FolderUsageAge objects' -Test {
            $script:result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.FolderUsageAge'
        }

        It -Name 'Should default ComputerName to the local machine' -Test {
            ($script:result.ComputerName | Sort-Object -Unique) | Should -Be @($env:COMPUTERNAME)
        }

        It -Name 'Should always emit the seven buckets, oldest first' -Test {
            $script:result | Should -HaveCount 7
            $script:result.AgeBucket | Should -Be @('>2y', '1-2y', '180-365d', '90-180d', '30-90d', '7-30d', '0-7d')
        }

        It -Name 'Should expose exactly the documented property set' -Test {
            $expected = @(
                'ComputerName', 'Path', 'AgeBucket', 'MinAgeDays', 'MaxAgeDays', 'FileCount',
                'SizeBytes', 'SizeMB', 'PercentOfTotal', 'TotalSizeBytes',
                'TotalFileCount', 'AgeProperty', 'InaccessibleCount', 'Timestamp'
            )
            $actual = @($script:result[0].PSObject.Properties.Name)
            ($actual | Sort-Object) | Should -Be ($expected | Sort-Object)
        }

        It -Name 'Should report the resolved root path on every row' -Test {
            ($script:result.Path | Sort-Object -Unique) | Should -Be @($script:treeRoot)
        }

        It -Name 'Should expose the documented bounds per bucket' -Test {
            $script:result[0].MinAgeDays | Should -Be 730
            $script:result[0].MaxAgeDays | Should -Be ([int]::MaxValue)
            $script:result[1].MinAgeDays | Should -Be 365
            $script:result[1].MaxAgeDays | Should -Be 730
            $script:result[2].MinAgeDays | Should -Be 180
            $script:result[2].MaxAgeDays | Should -Be 365
            $script:result[3].MinAgeDays | Should -Be 90
            $script:result[3].MaxAgeDays | Should -Be 180
            $script:result[4].MinAgeDays | Should -Be 30
            $script:result[4].MaxAgeDays | Should -Be 90
            $script:result[5].MinAgeDays | Should -Be 7
            $script:result[5].MaxAgeDays | Should -Be 30
            $script:result[6].MinAgeDays | Should -Be 0
            $script:result[6].MaxAgeDays | Should -Be 7
        }

        It -Name 'Should type the numeric properties per the spec' -Test {
            $script:result[0].MinAgeDays.GetType().Name | Should -Be 'Int32'
            $script:result[1].MaxAgeDays.GetType().Name | Should -Be 'Int32'
            $script:result[0].FileCount.GetType().Name | Should -Be 'Int64'
            $script:result[0].SizeBytes.GetType().Name | Should -Be 'Int64'
            $script:result[0].TotalSizeBytes.GetType().Name | Should -Be 'Int64'
            $script:result[0].TotalFileCount.GetType().Name | Should -Be 'Int64'
            $script:result[0].InaccessibleCount.GetType().Name | Should -Be 'Int64'
            $script:result[0].SizeMB.GetType().Name | Should -Be 'Double'
            $script:result[0].PercentOfTotal.GetType().Name | Should -Be 'Double'
        }

        It -Name 'Should place exactly one file in each bucket' -Test {
            foreach ($bucket in @('>2y', '1-2y', '180-365d', '90-180d', '30-90d', '7-30d', '0-7d')) {
                $script:byBucket[$bucket].FileCount | Should -Be 1
            }
        }

        It -Name 'Should sum exact byte totals per bucket' -Test {
            $script:byBucket['>2y'].SizeBytes | Should -Be 8388608
            $script:byBucket['1-2y'].SizeBytes | Should -Be 4194304
            $script:byBucket['180-365d'].SizeBytes | Should -Be 2097152
            $script:byBucket['90-180d'].SizeBytes | Should -Be 1048576
            $script:byBucket['30-90d'].SizeBytes | Should -Be 1048576
            $script:byBucket['7-30d'].SizeBytes | Should -Be 1048576
            $script:byBucket['0-7d'].SizeBytes | Should -Be 1048576
        }

        It -Name 'Should round SizeMB to two decimals' -Test {
            $script:byBucket['>2y'].SizeMB | Should -Be 8
            $script:byBucket['1-2y'].SizeMB | Should -Be 4
            $script:byBucket['180-365d'].SizeMB | Should -Be 2
            $script:byBucket['0-7d'].SizeMB | Should -Be 1
        }

        It -Name 'Should compute PercentOfTotal against the tree total' -Test {
            $script:byBucket['>2y'].PercentOfTotal | Should -Be 44.44
            $script:byBucket['1-2y'].PercentOfTotal | Should -Be 22.22
            $script:byBucket['180-365d'].PercentOfTotal | Should -Be 11.11
            $script:byBucket['0-7d'].PercentOfTotal | Should -Be 5.56
        }

        It -Name 'Should recurse into subfolders' -Test {
            $script:byBucket['>2y'].FileCount | Should -Be 1
            $script:byBucket['>2y'].SizeBytes | Should -Be 8388608
            $script:byBucket['>2y'].PercentOfTotal | Should -Be 44.44
        }

        It -Name 'Should repeat the exact tree totals on every row' -Test {
            foreach ($row in $script:result) {
                $row.TotalSizeBytes | Should -Be 18874368
                $row.TotalFileCount | Should -Be 7
            }
        }

        It -Name 'Should default AgeProperty to LastWriteTime' -Test {
            ($script:result.AgeProperty | Sort-Object -Unique) | Should -Be @('LastWriteTime')
        }

        It -Name 'Should report InaccessibleCount 0 for a fully readable tree' -Test {
            ($script:result.InaccessibleCount | Sort-Object -Unique) | Should -Be @(0)
        }

        It -Name 'Should carry a per-row Timestamp in ISO-8601 (o) form' -Test {
            foreach ($row in $script:result) {
                $row.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+"
            }
        }

        It -Name 'Should accept Path as the first positional argument' -Test {
            @(Show-FolderUsageAge $script:treeRoot) | Should -HaveCount 7
        }

        It -Name 'Should not embed ESC (char 27) in any property value' -Test {
            $esc = [regex]::Escape([string][char]27)
            foreach ($row in $script:result) {
                foreach ($prop in $row.PSObject.Properties) {
                    ($prop.Value | Out-String) | Should -Not -Match $esc
                }
            }
        }

        It -Name 'Should not expose a UsageBar property (the bar is view-only)' -Test {
            $script:result[0].PSObject.Properties.Name | Should -Not -Contain 'UsageBar'
            $script:result[0].PSObject.Properties.Name | Should -Not -Contain 'Usage'
            $script:result[0].PSObject.Properties.Name | Should -Not -Contain 'Buckets'
        }
    }

    Context 'Empty tree (all seven buckets, divide-by-zero guard)' {

        BeforeAll {
            $script:emptyResult = @(Show-FolderUsageAge -Path $script:emptyRoot)
        }

        It -Name 'Should still emit all seven buckets for a tree without files' -Test {
            $script:emptyResult | Should -HaveCount 7
            $script:emptyResult.AgeBucket | Should -Be @('>2y', '1-2y', '180-365d', '90-180d', '30-90d', '7-30d', '0-7d')
        }

        It -Name 'Should report zero counts, bytes and percent without dividing by zero' -Test {
            foreach ($row in $script:emptyResult) {
                $row.FileCount | Should -Be 0
                $row.SizeBytes | Should -Be 0
                $row.SizeMB | Should -Be 0
                $row.PercentOfTotal | Should -Be 0
                $row.TotalSizeBytes | Should -Be 0
                $row.TotalFileCount | Should -Be 0
                $row.InaccessibleCount | Should -Be 0
            }
        }

        It -Name 'Should not throw for an empty tree' -Test {
            { Show-FolderUsageAge -Path $script:emptyRoot -ErrorAction Stop } | Should -Not -Throw
        }

        It -Name 'Should Write-Verbose that the tree held no files' -Test {
            $verboseOutput = Show-FolderUsageAge -Path $script:emptyRoot -Verbose 4>&1
            ($verboseOutput | Out-String) | Should -Match 'contained no files'
        }
    }

    Context 'Age bucket bounds are half-open (real fixture tree)' {

        BeforeAll {
            $script:boundaryResult = @(Show-FolderUsageAge -Path $script:boundaryRoot)
            $script:boundaryByBucket = @{}
            foreach ($row in $script:boundaryResult) {
                $script:boundaryByBucket[$row.AgeBucket] = $row
            }
        }

        It -Name 'Should put a file exactly 7 days old in 7-30d (MinAgeDays inclusive)' -Test {
            $script:boundaryByBucket['7-30d'].FileCount | Should -Be 2
            $script:boundaryByBucket['7-30d'].SizeBytes | Should -Be 5242880
        }

        It -Name 'Should keep a file one minute under 7 days in 0-7d (MaxAgeDays exclusive)' -Test {
            $script:boundaryByBucket['0-7d'].FileCount | Should -Be 1
            $script:boundaryByBucket['0-7d'].SizeBytes | Should -Be 2097152
        }

        It -Name 'Should put a file exactly 30 days old in 30-90d' -Test {
            $script:boundaryByBucket['30-90d'].FileCount | Should -Be 1
            $script:boundaryByBucket['30-90d'].SizeBytes | Should -Be 3145728
        }

        It -Name 'Should put a file exactly 730 days old in the unbounded >2y bucket' -Test {
            $script:boundaryByBucket['>2y'].FileCount | Should -Be 1
            $script:boundaryByBucket['>2y'].SizeBytes | Should -Be 5242880
        }

        It -Name 'Should keep a file one minute under 730 days in 1-2y' -Test {
            $script:boundaryByBucket['1-2y'].FileCount | Should -Be 1
            $script:boundaryByBucket['1-2y'].SizeBytes | Should -Be 6291456
        }

        It -Name 'Should leave the untouched buckets empty but present' -Test {
            $script:boundaryByBucket['90-180d'].FileCount | Should -Be 0
            $script:boundaryByBucket['180-365d'].FileCount | Should -Be 0
            $script:boundaryResult | Should -HaveCount 7
        }

        It -Name 'Should account for every boundary file exactly once' -Test {
            $sum = 0
            foreach ($row in $script:boundaryResult) {
                $sum += $row.FileCount
            }
            $sum | Should -Be 6
            $script:boundaryResult[0].TotalFileCount | Should -Be 6
            $script:boundaryResult[0].TotalSizeBytes | Should -Be 22020096
        }
    }

    Context 'Future-dated file clamps into the newest bucket (real fixture tree)' {

        BeforeAll {
            $script:futureResult = @(Show-FolderUsageAge -Path $script:futureRoot)
        }

        It -Name 'Should clamp a future-dated file into the 0-7d bucket' -Test {
            $newest = @($script:futureResult | Where-Object -FilterScript { $_.AgeBucket -eq '0-7d' })
            $newest | Should -HaveCount 1
            $newest[0].FileCount | Should -Be 1
            $newest[0].SizeBytes | Should -Be 1048576
            $newest[0].PercentOfTotal | Should -Be 100
        }

        It -Name 'Should not leak a negative age into any older bucket' -Test {
            $older = @($script:futureResult | Where-Object -FilterScript { $_.AgeBucket -ne '0-7d' })
            $older | Should -HaveCount 6
            foreach ($row in $older) {
                $row.FileCount | Should -Be 0
                $row.SizeBytes | Should -Be 0
                $row.PercentOfTotal | Should -Be 0
            }
        }
    }

    Context 'Property selection drives the bucketing' {

        BeforeAll {
            # Two synthetic files whose three timestamps each land in a different
            # bucket: LastWriteTime ~100 d (90-180d), CreationTime ~2 d (0-7d)
            # and LastAccessTime ~400 d (1-2y). The real scan scriptblock still
            # runs - only its directory enumeration is stubbed.
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                $base = Get-Date
                @(
                    [PSCustomObject]@{
                        PSIsContainer  = $false
                        FullName       = 'C:\Synthetic\old.bin'
                        Length         = [long]1048576
                        Attributes     = [System.IO.FileAttributes]::Archive
                        LastWriteTime  = $base.AddDays(-100)
                        CreationTime   = $base.AddDays(-2)
                        LastAccessTime = $base.AddDays(-400)
                    }
                    [PSCustomObject]@{
                        PSIsContainer  = $false
                        FullName       = 'C:\Synthetic\shared.bin'
                        Length         = [long]3145728
                        Attributes     = [System.IO.FileAttributes]::Archive
                        LastWriteTime  = $base.AddDays(-100)
                        CreationTime   = $base.AddDays(-2)
                        LastAccessTime = $base.AddDays(-400)
                    }
                )
            }
        }

        It -Name 'Should bucket by LastWriteTime by default' -Test {
            $result = @(Show-FolderUsageAge -Path $script:mockRoot)
            $row = @($result | Where-Object -FilterScript { $_.AgeBucket -eq '90-180d' })
            $row[0].FileCount | Should -Be 2
            $row[0].SizeBytes | Should -Be 4194304
            ($result.AgeProperty | Sort-Object -Unique) | Should -Be @('LastWriteTime')
        }

        It -Name 'Should bucket by CreationTime when Property is CreationTime' -Test {
            $result = @(Show-FolderUsageAge -Path $script:mockRoot -Property 'CreationTime')
            $row = @($result | Where-Object -FilterScript { $_.AgeBucket -eq '0-7d' })
            $row[0].FileCount | Should -Be 2
            $row[0].SizeBytes | Should -Be 4194304
            ($result.AgeProperty | Sort-Object -Unique) | Should -Be @('CreationTime')
        }

        It -Name 'Should bucket by LastAccessTime when Property is LastAccessTime' -Test {
            $result = @(Show-FolderUsageAge -Path $script:mockRoot -Property 'LastAccessTime')
            $row = @($result | Where-Object -FilterScript { $_.AgeBucket -eq '1-2y' })
            $row[0].FileCount | Should -Be 2
            $row[0].SizeBytes | Should -Be 4194304
            ($result.AgeProperty | Sort-Object -Unique) | Should -Be @('LastAccessTime')
        }
    }

    Context 'Unreadable subfolder is counted, accessible rows still stream' {

        BeforeAll {
            # The enumeration raises a non-terminating error that the function
            # collects through -ErrorVariable: the readable remainder must still
            # be reported instead of discarding the whole tree.
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                Write-Error -Message 'Access to the path is denied.' -ErrorAction Continue
                [PSCustomObject]@{
                    PSIsContainer = $false
                    FullName      = 'C:\Synthetic\partial.bin'
                    Length        = [long]2097152
                    Attributes    = [System.IO.FileAttributes]::Archive
                    LastWriteTime = (Get-Date).AddDays(-100)
                }
            }
        }

        It -Name 'Should count the denial and keep the accessible rows' -Test {
            $result = @(Show-FolderUsageAge -Path $script:mockRoot)

            $result | Should -HaveCount 7
            $row = @($result | Where-Object -FilterScript { $_.AgeBucket -eq '90-180d' })
            $row[0].FileCount | Should -Be 1
            $row[0].SizeBytes | Should -Be 2097152
            $row[0].PercentOfTotal | Should -Be 100
            $row[0].InaccessibleCount | Should -BeGreaterThan 0
            Should -Invoke -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeRows -TargetPath $ArgumentList[0] -AgeProperty $ArgumentList[1]
            }
        }

        It -Name 'Should dispatch exactly once to the requested machine' -Test {
            $null = Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ComputerName -eq 'SRV01' }
        }

        It -Name 'Should hand a scriptblock and the path to the dispatcher' -Test {
            $null = Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $null -ne $ScriptBlock -and $ArgumentList[0] -eq 'C:\Logs' }
        }

        It -Name 'Should not resolve the path locally for a remote query' -Test {
            # 'Z:\Does\Not\Exist' is meaningless on the test host; it must still be
            # handed to the target untouched and never validated locally.
            $result = @(Show-FolderUsageAge -Path 'Z:\Does\Not\Exist' -ComputerName 'SRV01')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[0] -eq 'Z:\Does\Not\Exist' }
            $result | Should -HaveCount 7
            ($result.Path | Sort-Object -Unique) | Should -Be @('Z:\Does\Not\Exist')
        }

        It -Name 'Should stamp the queried machine on every row' -Test {
            $result = @(Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01')
            ($result.ComputerName | Sort-Object -Unique) | Should -Be @('SRV01')
            $result | Should -HaveCount 7
        }

        It -Name 'Should accept the CN alias for ComputerName' -Test {
            $result = @(Show-FolderUsageAge -Path 'C:\Logs' -CN 'SRV01')
            ($result.ComputerName | Sort-Object -Unique) | Should -Be @('SRV01')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ComputerName -eq 'SRV01' }
        }

        It -Name 'Should map the target summary rows onto the output contract' -Test {
            $result = @(Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01')
            $result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.FolderUsageAge'
            $result[0].AgeBucket | Should -Be '>2y'
            $result[0].MinAgeDays | Should -Be 730
            $result[0].MaxAgeDays | Should -Be ([int]::MaxValue)
            $result[0].FileCount | Should -Be 1
            $result[0].SizeBytes | Should -Be 8388608
            $result[0].SizeMB | Should -Be 8
            $result[0].PercentOfTotal | Should -Be 44.44
            $result[6].AgeBucket | Should -Be '0-7d'
            $result[6].MaxAgeDays | Should -Be 7
        }

        It -Name 'Should pass the target totals and InaccessibleCount through unchanged' -Test {
            $result = @(Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01')
            foreach ($row in $result) {
                $row.TotalSizeBytes | Should -Be 18874368
                $row.TotalFileCount | Should -Be 7
                $row.InaccessibleCount | Should -Be 2
            }
        }

        It -Name 'Should carry a per-row Timestamp' -Test {
            $result = @(Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01')
            foreach ($row in $result) {
                $row.Timestamp | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Property forwarding to the target' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeRows -TargetPath $ArgumentList[0] -AgeProperty $ArgumentList[1]
            }
        }

        It -Name 'Should default the age property to LastWriteTime' -Test {
            $null = Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[1] -eq 'LastWriteTime' }
        }

        It -Name 'Should forward Property as the second scriptblock argument' -Test {
            $result = @(Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01' -Property 'CreationTime')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[1] -eq 'CreationTime' }
            ($result.AgeProperty | Sort-Object -Unique) | Should -Be @('CreationTime')
        }

        It -Name 'Should forward LastAccessTime unchanged' -Test {
            $result = @(Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01' -Property 'LastAccessTime')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[1] -eq 'LastAccessTime' }
            ($result.AgeProperty | Sort-Object -Unique) | Should -Be @('LastAccessTime')
        }
    }

    Context 'Credential propagation' {

        BeforeAll {
            $script:credential = [System.Management.Automation.PSCredential]::new(
                'testuser',
                (ConvertTo-SecureString -String 'NotARealSecret' -AsPlainText -Force)
            )
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeRows -TargetPath $ArgumentList[0] -AgeProperty $ArgumentList[1]
            }
        }

        It -Name 'Should forward the credential to the remote dispatch' -Test {
            $null = Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01' -Credential $script:credential
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $null -ne $Credential -and $Credential.UserName -eq 'testuser' }
        }

        It -Name 'Should not attach a credential to a local query' -Test {
            $null = Show-FolderUsageAge -Path 'C:\Logs'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $null -eq $Credential }
        }
    }

    Context 'Pipeline of multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeRows -TargetPath $ArgumentList[0] -AgeProperty $ArgumentList[1]
            }
        }

        It -Name 'Should query every piped machine once' -Test {
            $results = @(('SRV01', 'SRV02') | Show-FolderUsageAge -Path 'C:\Logs')
            $results | Should -HaveCount 14
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }

        It -Name 'Should stamp a distinct ComputerName per machine' -Test {
            $results = @(('SRV01', 'SRV02') | Show-FolderUsageAge -Path 'C:\Logs')
            ($results.ComputerName | Sort-Object -Unique) | Should -Be @('SRV01', 'SRV02')
        }

        It -Name 'Should emit the seven buckets per machine' -Test {
            $results = @(('SRV01', 'SRV02') | Show-FolderUsageAge -Path 'C:\Logs')
            $srv01 = @($results | Where-Object -FilterScript { $_.ComputerName -eq 'SRV01' })
            $srv01 | Should -HaveCount 7
            $srv01.AgeBucket | Should -Be @('>2y', '1-2y', '180-365d', '90-180d', '30-90d', '7-30d', '0-7d')
        }

        It -Name 'Should accept Path from the pipeline by property name' -Test {
            $null = [PSCustomObject]@{ Path = 'C:\Piped\Tree' } | Show-FolderUsageAge -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[0] -eq 'C:\Piped\Tree' }
        }
    }

    Context 'Per-machine failure isolation' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'BADHOST') { throw 'boom' }
                & $script:makeRows -TargetPath $ArgumentList[0] -AgeProperty $ArgumentList[1]
            }
        }

        It -Name 'Should surface a terminating error for the failed machine with ErrorAction Stop' -Test {
            { Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should keep measuring the remaining machines' -Test {
            $results = @(('BADHOST', 'SRV02') | Show-FolderUsageAge -Path 'C:\Logs' -ErrorAction SilentlyContinue)
            $results | Should -HaveCount 7
            ($results.ComputerName | Sort-Object -Unique) | Should -Be @('SRV02')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }

        It -Name 'Should write a non-terminating error naming the failed machine' -Test {
            $errors = @()
            $null = 'BADHOST', 'SRV02' | Show-FolderUsageAge -Path 'C:\Logs' -ErrorAction SilentlyContinue -ErrorVariable +errors
            ($errors | Out-String) | Should -Match 'BADHOST'
        }
    }

    Context 'Bad Path (per-machine error, no crash)' {

        It -Name 'Should write an error when the path does not exist' -Test {
            $missing = Join-Path -Path $script:treeRoot -ChildPath 'DoesNotExist'
            { Show-FolderUsageAge -Path $missing -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*does not exist*'
        }

        It -Name 'Should write an error when the path is a file' -Test {
            { Show-FolderUsageAge -Path (Join-Path -Path $script:treeRoot -ChildPath 'newest.log') -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*not a directory*'
        }

        It -Name 'Should not emit any row for a tree it could not measure' -Test {
            $missing = Join-Path -Path $script:treeRoot -ChildPath 'DoesNotExist'
            @(Show-FolderUsageAge -Path $missing -ErrorAction SilentlyContinue) | Should -HaveCount 0
        }
    }

    Context 'Parameter metadata' {

        BeforeAll {
            $script:commandInfo = Get-Command -Name 'Show-FolderUsageAge'
            $script:pathAttr = @($script:commandInfo.Parameters['Path'].Attributes |
                    Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] })
            $script:computerAttr = @($script:commandInfo.Parameters['ComputerName'].Attributes |
                    Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] })
            $script:propertyValidateSet = @($script:commandInfo.Parameters['Property'].Attributes |
                    Where-Object -FilterScript { $_ -is [System.Management.Automation.ValidateSetAttribute] })
        }

        It -Name 'Should declare Path as mandatory, position 0, by property name' -Test {
            $script:pathAttr.Mandatory | Should -BeTrue
            $script:pathAttr.Position | Should -Be 0
            $script:pathAttr.ValueFromPipelineByPropertyName | Should -BeTrue
            $script:pathAttr.ValueFromPipeline | Should -BeFalse
        }

        It -Name 'Should declare ComputerName for pipeline by value and by property name' -Test {
            $script:computerAttr.ValueFromPipeline | Should -BeTrue
            $script:computerAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }

        It -Name 'Should restrict Property to the three supported timestamps' -Test {
            @($script:propertyValidateSet.ValidValues) | Should -Be @('LastWriteTime', 'CreationTime', 'LastAccessTime')
        }

        It -Name 'Should declare Credential as a PSCredential' -Test {
            $script:commandInfo.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }

        It -Name 'Should expose the spec aliases on ComputerName' -Test {
            foreach ($alias in @('CN', 'Name', 'DNSHostName')) {
                $script:commandInfo.Parameters['ComputerName'].Aliases | Should -Contain $alias
            }
        }

        It -Name 'Should not declare ShouldProcess parameters' -Test {
            $script:commandInfo.Parameters.ContainsKey('WhatIf') | Should -BeFalse
            $script:commandInfo.Parameters.ContainsKey('Confirm') | Should -BeFalse
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should reject an empty Path' -Test {
            { Show-FolderUsageAge -Path '' } | Should -Throw
        }

        It -Name 'Should reject a null Path' -Test {
            { Show-FolderUsageAge -Path $null } | Should -Throw
        }

        It -Name 'Should reject an unsupported Property value' -Test {
            { Show-FolderUsageAge -Path 'C:\Logs' -Property 'Modified' } | Should -Throw
            { Show-FolderUsageAge -Path 'C:\Logs' -Property '' } | Should -Throw
        }

        It -Name 'Should reject an empty ComputerName' -Test {
            { Show-FolderUsageAge -Path 'C:\Logs' -ComputerName '' } | Should -Throw
        }

        It -Name 'Should reject a null ComputerName' -Test {
            { Show-FolderUsageAge -Path 'C:\Logs' -ComputerName $null } | Should -Throw
        }
    }

    Context 'Registration' {

        It -Name 'Should be exported from the module' -Test {
            Get-Command -Name 'Show-FolderUsageAge' -Module 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should expose the sfua alias' -Test {
            (Get-Alias -Name 'sfua').ResolvedCommandName | Should -Be 'Show-FolderUsageAge'
        }
    }

    Context 'Format view' {

        BeforeAll {
            $script:formatPath = Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.Format.ps1xml'
            [xml]$script:formatXml = Get-Content -Path $script:formatPath -Raw

            $script:view = @($script:formatXml.Configuration.ViewDefinitions.View |
                    Where-Object -FilterScript { [string]$_.Name -eq 'PSWinOps.FolderUsageAge' })
        }

        It -Name 'Should parse PSWinOps.Format.ps1xml as XML' -Test {
            $script:formatXml | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should contain exactly one View named PSWinOps.FolderUsageAge' -Test {
            @($script:view) | Should -HaveCount 1
        }

        It -Name 'Should select the view by the spec PSTypeName' -Test {
            [string]$script:view[0].ViewSelectedBy.TypeName | Should -Be 'PSWinOps.FolderUsageAge'
        }

        It -Name 'Should render the view as a table' -Test {
            $script:view[0].TableControl | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should label the columns per the spec' -Test {
            $labels = @($script:view[0].TableControl.TableHeaders.TableColumnHeader |
                    ForEach-Object -Process { [string]$_.Label })
            $labels | Should -Be @('AgeBucket', 'FileCount', 'Size(MB)', 'Percent', 'Usage')
        }

        It -Name 'Should render the usage bar from PercentOfTotal in the view ScriptBlock' -Test {
            $items = @($script:view[0].TableControl.TableRowEntries.TableRowEntry.TableColumnItems.TableColumnItem)
            $barItem = @($items | Where-Object -FilterScript { $null -ne $_.ScriptBlock })
            $barItem | Should -HaveCount 1
            $bar = [string]$barItem[0].ScriptBlock
            $bar | Should -Match 'PercentOfTotal'
            $bar | Should -Match '20'
        }
    }

    Context 'Comment-based help' {

        BeforeAll {
            $script:helpInfo = Get-Help -Name 'Show-FolderUsageAge' -Full
        }

        It -Name 'Should have a synopsis' -Test {
            $script:helpInfo.Synopsis.Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a description' -Test {
            ($script:helpInfo.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have at least 3 examples' -Test {
            $script:helpInfo.Examples.Example.Count | Should -BeGreaterOrEqual 3
        }

        It -Name 'Should have an OUTPUTS section naming the object type' -Test {
            ($script:helpInfo.returnValues | Out-String) | Should -Match 'PSWinOps\.FolderUsageAge'
        }

        It -Name 'Should have Author in NOTES' -Test {
            ($script:helpInfo.alertSet | Out-String) | Should -Match 'Franck SALLET'
        }

        It -Name 'Should document the LastAccessTime unreliability caveat in NOTES' -Test {
            ($script:helpInfo.alertSet | Out-String) | Should -Match 'NtfsDisableLastAccessUpdate'
        }

        It -Name 'Should document every declared parameter' -Test {
            $expectedParams = @('Path', 'Property', 'ComputerName', 'Credential')
            $documented = $script:helpInfo.parameters.parameter.name
            foreach ($param in $expectedParams) {
                $documented | Should -Contain $param
            }
        }
    }
}
