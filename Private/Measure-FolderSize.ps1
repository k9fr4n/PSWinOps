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

        .PARAMETER Path
            The single parent directory to enumerate one level of. Mandatory. Must be an
            existing directory; a non-existent path or a path pointing at a file produces
            a non-terminating error and returns nothing.

        .PARAMETER IncludeFiles
            When set, also emit one entry per file directly under Path (IsContainer =
            $false) in addition to the aggregated loose-files entry. Off by default.

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
            Last Modified: 2026-09-17
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
        [switch]$IncludeFiles
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

        foreach ($dir in $childDirs) {
            # Reparse points are skipped, not traversed: emit a zero-size marker.
            if (($dir.Attributes -band $reparse) -eq $reparse) {
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

            $subErrors = $null
            $files = Get-ChildItem -LiteralPath $dir.FullName -Force -Recurse -File `
                -ErrorAction SilentlyContinue -ErrorVariable subErrors

            $size = [long]0
            $count = [long]0
            foreach ($file in $files) {
                $size += [long]$file.Length
                $count++
            }

            [PSCustomObject]@{
                Name         = $dir.Name
                FullName     = $dir.FullName
                SizeBytes    = $size
                FileCount    = $count
                IsContainer  = $true
                Inaccessible = [long]@($subErrors).Count
            }
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
