#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # ANSI CSI SGR stripping regex shared by the width assertions.
    $script:ansi = "$([char]27)\[\d+(?:;\d+)*m"

    # Helper: build a synthetic entry shaped exactly like Measure-FolderSize output.
    function script:NewEntry {
        param(
            [string]$Name = 'Folder',
            [long]$SizeBytes = 0,
            [long]$FileCount = 0,
            [bool]$IsContainer = $true,
            [long]$Inaccessible = 0
        )
        [PSCustomObject]@{
            Name         = $Name
            FullName     = $Name
            SizeBytes    = $SizeBytes
            FileCount    = $FileCount
            IsContainer  = $IsContainer
            Inaccessible = $Inaccessible
        }
    }

    # Helper: invoke the private renderer through the module's session state.
    function script:InvokeFrame {
        param([hashtable]$Params)
        & (Get-Module -Name 'PSWinOps') {
            param($p)
            $splat = @{}
            foreach ($key in $p.Keys) { $splat[$key] = $p[$key] }
            if (-not $splat.ContainsKey('NoColor')) { $splat['NoColor'] = $true }
            Format-DriveUsageFrame @splat
        } $Params
    }
}

Describe -Name 'Format-DriveUsageFrame' -Fixture {

    Context -Name 'Output type' -Fixture {

        It -Name 'Should return a single string' -Test {
            $result = script:InvokeFrame @{
                CurrentPath   = 'C:\Data'
                Entries       = @((script:NewEntry -Name 'FolderA'))
                SelectedIndex = 0
            }
            @($result).Count | Should -Be 1
            $result           | Should -BeOfType ([string])
        }

        It -Name 'Should not return null or empty' -Test {
            $result = script:InvokeFrame @{
                CurrentPath   = 'C:\Data'
                Entries       = @((script:NewEntry -Name 'FolderA'))
                SelectedIndex = 0
            }
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Frame content (NoColor)' -Fixture {

        BeforeAll {
            $script:entries = @(
                (script:NewEntry -Name 'Windows'      -SizeBytes 268435456000 -FileCount 84120),
                (script:NewEntry -Name 'Users'        -SizeBytes 193273528320 -FileCount 512003),
                (script:NewEntry -Name 'ProgramData'  -SizeBytes 85899345920  -FileCount 12004)
            )
            $script:frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = $script:entries
                SelectedIndex = 1
            }
        }

        It -Name 'Should contain the current path' -Test {
            $script:frame | Should -Match ([regex]::Escape('C:\'))
        }

        It -Name 'Should contain each entry name' -Test {
            $script:frame | Should -Match 'Windows'
            $script:frame | Should -Match 'Users'
            $script:frame | Should -Match 'ProgramData'
        }

        It -Name 'Should contain the key bar' -Test {
            $script:frame | Should -Match '\[Enter\]'
            $script:frame | Should -Match '\[Backspace\]'
            $script:frame | Should -Match '\[R\]'
            $script:frame | Should -Match '\[Q\]'
        }

        It -Name 'Should place the selection marker on the selected row only' -Test {
            $lines = @($script:frame -split "`r?`n")
            $markerLines = @($lines | Where-Object { $_ -match '^  > ' })
            $markerLines.Count | Should -Be 1
            $markerLines[0]      | Should -Match 'Users'
        }
    }

    Context -Name 'Colour on and off' -Fixture {

        BeforeAll {
            $script:colorEntries = @(
                (script:NewEntry -Name 'One' -SizeBytes 1024 -FileCount 1),
                (script:NewEntry -Name 'Two' -SizeBytes 2048 -FileCount 2)
            )
        }

        It -Name 'Should be escape-free with -NoColor' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = $script:colorEntries
                SelectedIndex = 0
                NoColor       = $true
            }
            $frame | Should -Not -Match ([regex]::Escape([string][char]27))
        }

        It -Name 'Should contain ANSI escapes when colour is enabled' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = $script:colorEntries
                SelectedIndex = 0
                NoColor       = $false
            }
            $frame | Should -Match ([regex]::Escape([string][char]27))
        }
    }

    Context -Name 'Width compliance' -Fixture {

        BeforeAll {
            $script:widthEntries = @(
                (script:NewEntry -Name 'A-reasonably-long-folder-name' -SizeBytes 20971520 -FileCount 400),
                (script:NewEntry -Name 'Short' -SizeBytes 1024 -FileCount 1)
            )
        }

        It -Name 'Should keep every visible line within -Width 80' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\Some\Long\Path'
                Entries       = $script:widthEntries
                SelectedIndex = 0
                Width         = 80
            }
            foreach ($line in @($frame -split "`r?`n")) {
                ($line -replace $script:ansi, '').Length | Should -BeLessOrEqual 80
            }
        }

        It -Name 'Should keep every visible line within -Width 120' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\Some\Long\Path'
                Entries       = $script:widthEntries
                SelectedIndex = 0
                Width         = 120
            }
            foreach ($line in @($frame -split "`r?`n")) {
                ($line -replace $script:ansi, '').Length | Should -BeLessOrEqual 120
            }
        }

        It -Name 'Should keep every visible line within -Width 200' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\Some\Long\Path'
                Entries       = $script:widthEntries
                SelectedIndex = 0
                Width         = 200
            }
            foreach ($line in @($frame -split "`r?`n")) {
                ($line -replace $script:ansi, '').Length | Should -BeLessOrEqual 200
            }
        }

        It -Name 'Should keep coloured lines within -Width 80 after stripping ANSI' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\Some\Long\Path'
                Entries       = $script:widthEntries
                SelectedIndex = 0
                Width         = 80
                NoColor       = $false
            }
            foreach ($line in @($frame -split "`r?`n")) {
                ($line -replace $script:ansi, '').Length | Should -BeLessOrEqual 80
            }
        }
    }

    Context -Name 'Long entry names' -Fixture {

        It -Name 'Should truncate a long name with an ellipsis instead of wrapping' -Test {
            $longName = 'A' * 120
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = @((script:NewEntry -Name $longName -SizeBytes 1024 -FileCount 1))
                SelectedIndex = 0
                Width         = 80
            }
            $frame | Should -Match '\.\.\.'
            $frame | Should -Not -BeLike "*$longName*"
        }
    }

    Context -Name 'Height awareness' -Fixture {

        BeforeAll {
            $script:manyEntries = @()
            for ($i = 0; $i -lt 30; $i++) {
                $script:manyEntries += script:NewEntry -Name ('Entry{0:D2}' -f $i) -SizeBytes 1024 -FileCount $i
            }
        }

        It -Name 'Should keep the selected row visible when rows do not fit -Height' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\Data'
                Entries       = $script:manyEntries
                SelectedIndex = 20
                Height        = 12
            }
            $frame | Should -Match 'Entry20'
        }

        It -Name 'Should emit a more indicator when rows are hidden' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\Data'
                Entries       = $script:manyEntries
                SelectedIndex = 20
                Height        = 12
            }
            $frame | Should -Match 'more'
        }

        It -Name 'Should hide rows outside the scrolled window' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\Data'
                Entries       = $script:manyEntries
                SelectedIndex = 20
                Height        = 12
            }
            $frame | Should -Not -Match 'Entry00'
        }

        It -Name 'Should report the exact number of hidden rows' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\Data'
                Entries       = $script:manyEntries
                SelectedIndex = 20
                Height        = 12
            }
            $frame | Should -Match '24 more'
        }
    }

    Context -Name 'Row percentages' -Fixture {

        It -Name 'Should compute each percentage against -TotalBytes' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = @((script:NewEntry -Name 'Big' -SizeBytes 268435456000 -FileCount 1))
                SelectedIndex = 0
                TotalBytes    = 912680550400
            }
            $frame | Should -Match '29\.4%'
        }

        It -Name 'Should zero percentages and not throw when -TotalBytes is 0' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = @((script:NewEntry -Name 'Big' -SizeBytes 268435456000 -FileCount 1))
                SelectedIndex = 0
                TotalBytes    = 0
            }
            $frame | Should -Match '0\.0%'
        }

        It -Name 'Should zero percentages and not throw when -TotalBytes is absent' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = @((script:NewEntry -Name 'Big' -SizeBytes 268435456000 -FileCount 1))
                SelectedIndex = 0
            }
            $frame | Should -Match '0\.0%'
        }
    }

    Context -Name 'Adaptive size units' -Fixture {

        BeforeAll {
            $script:sizeCases = @(
                @{ Label = '512 B';   Bytes = [long]512 },
                @{ Label = '1.5 KB';  Bytes = [long]1536 },
                @{ Label = '20 MB';   Bytes = [long]20971520 },
                @{ Label = '850 GB';  Bytes = [long]912680550400 },
                @{ Label = '1.2 TB';  Bytes = [long]1319413953331 }
            )
        }

        It -Name 'Should render <Label> with the expected unit' -TestCases $script:sizeCases {
            param($Label, $Bytes)
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = @((script:NewEntry -Name 'Sized' -SizeBytes $Bytes -FileCount 1))
                SelectedIndex = 0
            }
            $frame | Should -Match ([regex]::Escape($Label))
        }
    }

    Context -Name 'Scanning indicator' -Fixture {

        BeforeAll {
            $script:scanEntry = @((script:NewEntry -Name 'FolderA' -SizeBytes 1024 -FileCount 1))
        }

        It -Name 'Should add the scanning indicator when -Scanning is set' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = $script:scanEntry
                SelectedIndex = 0
                Scanning      = $true
            }
            $frame | Should -Match 'Scanning'
        }

        It -Name 'Should omit the scanning indicator when -Scanning is absent' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = $script:scanEntry
                SelectedIndex = 0
            }
            $frame | Should -Not -Match 'Scanning'
        }
    }

    Context -Name 'Status message' -Fixture {

        It -Name 'Should display the -StatusMessage above the key bar' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = @((script:NewEntry -Name 'FolderA'))
                SelectedIndex = 0
                StatusMessage = 'Access denied'
            }
            $frame | Should -Match 'Access denied'
        }
    }

    Context -Name 'Empty entries' -Fixture {

        It -Name 'Should render a valid frame without throwing' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = @()
                SelectedIndex = 0
            }
            $frame | Should -Match '<empty>'
            $frame | Should -Match '\[Q\]'
            $frame | Should -Match ([regex]::Escape('C:\'))
        }
    }

    Context -Name 'Inaccessible marker' -Fixture {

        BeforeAll {
            $script:inaccessibleEntries = @(
                (script:NewEntry -Name 'Normal' -SizeBytes 1024 -FileCount 1 -Inaccessible 0),
                (script:NewEntry -Name 'Locked' -SizeBytes 0 -FileCount 0 -Inaccessible 1)
            )
        }

        It -Name 'Should mark an inaccessible entry with a trailing bang' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = $script:inaccessibleEntries
                SelectedIndex = 0
            }
            $lines = @($frame -split "`r?`n")
            ($lines | Where-Object { $_ -match 'Locked' }) | Should -Match '!$'
        }

        It -Name 'Should not mark an accessible entry' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = $script:inaccessibleEntries
                SelectedIndex = 0
            }
            $lines = @($frame -split "`r?`n")
            ($lines | Where-Object { $_ -match 'Normal' }) | Should -Not -Match '!$'
        }
    }

    Context -Name 'Selected index clamping' -Fixture {

        BeforeAll {
            $script:clampEntries = @(
                (script:NewEntry -Name 'First' -SizeBytes 1024 -FileCount 1),
                (script:NewEntry -Name 'Second' -SizeBytes 2048 -FileCount 2),
                (script:NewEntry -Name 'Third' -SizeBytes 4096 -FileCount 3)
            )
        }

        It -Name 'Should clamp a negative index to the first row without throwing' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = $script:clampEntries
                SelectedIndex = -5
            }
            $lines = @($frame -split "`r?`n")
            $markerLine = $lines | Where-Object { $_ -match '^  > ' }
            $markerLine | Should -Match 'First'
        }

        It -Name 'Should clamp an over-large index to the last row without throwing' -Test {
            $frame = script:InvokeFrame @{
                CurrentPath   = 'C:\'
                Entries       = $script:clampEntries
                SelectedIndex = 999
            }
            $lines = @($frame -split "`r?`n")
            $markerLine = $lines | Where-Object { $_ -match '^  > ' }
            $markerLine | Should -Match 'Third'
        }
    }

    Context -Name 'Comment-based help completeness' -Fixture {

        BeforeAll {
            $script:sourcePath = Join-Path -Path $script:modulePath -ChildPath 'Private\Format-DriveUsageFrame.ps1'
            $script:sourceText = Get-Content -Raw -Path $script:sourcePath
        }

        It -Name 'Should declare all seven help fields' -Test {
            foreach ($tag in '.SYNOPSIS', '.DESCRIPTION', '.PARAMETER', '.EXAMPLE', '.OUTPUTS', '.NOTES', '.LINK') {
                $script:sourceText | Should -Match ([regex]::Escape($tag))
            }
        }

        It -Name 'Should provide one .PARAMETER block per declared parameter' -Test {
            $count = ([regex]::Matches($script:sourceText, '(?m)^\s*\.PARAMETER\b')).Count
            $count | Should -Be 12
        }

        It -Name 'Should provide at least three .EXAMPLE blocks' -Test {
            $count = ([regex]::Matches($script:sourceText, '(?m)^\s*\.EXAMPLE\b')).Count
            $count | Should -BeGreaterOrEqual 3
        }

        It -Name 'Should set the author and private scope in .NOTES' -Test {
            $script:sourceText | Should -Match 'Author: Franck SALLET'
            $script:sourceText | Should -Match 'Scope: Private - not exported'
        }
    }
}
