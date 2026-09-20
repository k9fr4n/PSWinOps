#Requires -Version 5.1

function Measure-FolderSize {
    <#
        .SYNOPSIS
            Measures one level of a directory tree (pure sizing helper, no side effects).

        .DESCRIPTION
            Enumerates the immediate children of a single parent directory and returns
            one [PSCustomObject] per immediate child directory, each carrying the
            recursive size and file count of that child, plus one synthetic entry that
            aggregates the loose files sitting directly under the parent. It walks only
            one level: grandchildren are summed into their parent child's totals but are
            never emitted, and the parent is never traversed beyond its children.

            The helper is defect-avoidance by design. It absorbs access-denied and
            long-path errors into a per-child Inaccessible count instead of aborting, so
            one unreadable subfolder cannot discard the whole result. Reparse points
            (junctions, symlinks) are skipped rather than traversed to avoid double
            counting and loops. It exists as a pure, unit-testable seam for the future
            Watch-DriveUsage console loop; it does not sort and it does not render.
            An optional -OnProgress callback lets a caller observe the walk as it
            proceeds without the helper itself performing any console I/O.

        .PARAMETER Path
            The single parent directory to enumerate one level of. Mandatory. Must be an
            existing directory; a non-existent path or a path pointing at a file produces
            a non-terminating error and returns nothing.

        .PARAMETER IncludeFiles
            When set, also emit one entry per file directly under Path (IsContainer =
            $false) in addition to the aggregated loose-files entry. Off by default.

        .PARAMETER OnProgress
            Optional callback scriptblock invoked as the level is measured. It receives
            one [PSCustomObject] per report with FolderIndex, FolderCount, FileCount,
            Bytes and CurrentName, so a caller can render a live progress indicator.

        .EXAMPLE
            Measure-FolderSize -Path 'C:\Temp'
            Returns one entry per immediate child directory of C:\Temp plus a '(files)'
            entry aggregating the loose files directly under C:\Temp.

        .EXAMPLE
            Measure-FolderSize -Path 'D:\Data' -IncludeFiles
            As above, but also emits an entry for each individual file directly under
            D:\Data with IsContainer = $false.

        .EXAMPLE
            Measure-FolderSize -Path 'C:\Windows' |
                Sort-Object -Property SizeBytes -Descending |
                Select-Object -First 5
            Pipes the per-child measurements to the caller for sorting and selection;
            the helper itself never sorts its output.

        .OUTPUTS
            System.Management.Automation.PSCustomObject
            One object per immediate child directory, one aggregated '(files)' entry,
            and (with -IncludeFiles) one object per loose file. Each has Name, FullName,
            SizeBytes, FileCount, IsContainer and Inaccessible.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-09-20
            Requires: PowerShell 5.1+ / Windows only
            Scope: Private - not exported
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeFiles,

        [Parameter(Mandatory = $false)]
        [scriptblock]$OnProgress
    )

    process {
        # Keep the caller alive: a bad path is a non-terminating error, never a throw.
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            Write-Error "[$($MyInvocation.MyCommand)] Path '$Path' does not exist."
            return
        }
        if (-not $item.PSIsContainer) {
            Write-Error "[$($MyInvocation.MyCommand)] Path '$Path' is a file, not a directory."
            return
        }

        $reparse = [System.IO.FileAttributes]::ReparsePoint

        # ---- Immediate child directories ----
        $childErrors = $null
        $childDirs = Get-ChildItem -LiteralPath $Path -Force -Directory `
            -ErrorAction SilentlyContinue -ErrorVariable childErrors
        $topInaccessible = @($childErrors).Count

        # Progress reporting. The optional -OnProgress callback is invoked once at the
        # start of each child (so a folder counter can advance) and, inside a large
        # recursion, at most every 100 ms (so a file counter keeps ticking). Counts are
        # cumulative across the whole level; the helper itself performs no console I/O.
        $dirCount   = @($childDirs).Count
        $dirIndex   = 0
        $totalFiles = [long]0
        $totalBytes = [long]0
        $scanState  = [pscustomobject]@{
            Stopwatch  = [System.Diagnostics.Stopwatch]::StartNew()
            LastReport = [long]0
        }

        $report = {
            param($FolderIndex, $FolderCount, $FileCount, $Bytes, $CurrentName)
            $null = & $OnProgress ([PSCustomObject]@{
                FolderIndex = $FolderIndex
                FolderCount = $FolderCount
                FileCount   = $FileCount
                Bytes       = $Bytes
                CurrentName = $CurrentName
            })
        }

        foreach ($dir in $childDirs) {
            $dirIndex++

            # Reparse points are skipped, not traversed: emit a zero-size marker.
            if (($dir.Attributes -band $reparse) -eq $reparse) {
                if ($null -ne $OnProgress) { & $report $dirIndex $dirCount $totalFiles $totalBytes $dir.Name }
                [PSCustomObject]@{
                    Name         = $dir.Name
                    FullName     = $dir.FullName
                    SizeBytes    = [long]0
                    FileCount    = [long]0
                    IsContainer  = $true
                    Inaccessible = [long]1
                }
                continue
            }

            if ($null -ne $OnProgress) { & $report $dirIndex $dirCount $totalFiles $totalBytes $dir.Name }

            $subErrors = $null
            $accum = [pscustomobject]@{ Size = [long]0; Count = [long]0 }
            Get-ChildItem -LiteralPath $dir.FullName -Force -Recurse -File `
                -ErrorAction SilentlyContinue -ErrorVariable subErrors |
                ForEach-Object {
                    $accum.Size += [long]$_.Length
                    $accum.Count++
                    if ($null -ne $OnProgress -and ($scanState.Stopwatch.ElapsedMilliseconds - $scanState.LastReport) -ge 100) {
                        & $report $dirIndex $dirCount ($totalFiles + $accum.Count) ($totalBytes + $accum.Size) $dir.Name
                        $scanState.LastReport = $scanState.Stopwatch.ElapsedMilliseconds
                    }
                }

            $totalFiles += $accum.Count
            $totalBytes += $accum.Size

            [PSCustomObject]@{
                Name         = $dir.Name
                FullName     = $dir.FullName
                SizeBytes    = $accum.Size
                FileCount    = $accum.Count
                IsContainer  = $true
                Inaccessible = [long]@($subErrors).Count
            }
        }

        # Final cumulative report so the caller can show the completed counts.
        if ($null -ne $OnProgress -and $dirCount -gt 0) {
            & $report $dirCount $dirCount $totalFiles $totalBytes ''
        }

        # ---- Loose files directly under Path ----
        $fileErrors = $null
        $looseFiles = Get-ChildItem -LiteralPath $Path -Force -File `
            -ErrorAction SilentlyContinue -ErrorVariable fileErrors

        $looseSize = [long]0
        $looseCount = [long]0
        foreach ($file in $looseFiles) {
            $looseSize += [long]$file.Length
            $looseCount++
        }

        [PSCustomObject]@{
            Name         = '(files)'
            FullName     = $Path
            SizeBytes    = $looseSize
            FileCount    = $looseCount
            IsContainer  = $true
            Inaccessible = [long]($topInaccessible + @($fileErrors).Count)
        }

        # ---- Optional per-file entries ----
        if ($IncludeFiles) {
            foreach ($file in $looseFiles) {
                [PSCustomObject]@{
                    Name         = $file.Name
                    FullName     = $file.FullName
                    SizeBytes    = [long]$file.Length
                    FileCount    = [long]1
                    IsContainer  = $false
                    Inaccessible = [long]0
                }
            }
        }
    }
}
