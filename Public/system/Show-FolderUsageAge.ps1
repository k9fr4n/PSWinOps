#Requires -Version 5.1
function Show-FolderUsageAge {
    <#
    .SYNOPSIS
        Shows folder tree disk usage by file age with a usage bar

    .DESCRIPTION
        Walks one folder tree per target computer and emits one
        PSWinOps.FolderUsageAge object for each of seven fixed age buckets,
        oldest first, always returning all seven even when empty. Files are
        bucketed by their LastWriteTime by default, and the scan runs on the
        target machine through Invoke-RemoteOrLocal so only the seven summary
        rows cross the wire. Age bucket bounds are half-open: MinAgeDays is
        inclusive and MaxAgeDays exclusive, with [int]::MaxValue as MaxAgeDays
        on the unbounded oldest bucket, and future-dated files are clamped
        into the newest bucket.
        Unreadable subfolders are counted in InaccessibleCount, and one failing
        computer never stops the remaining ones.

    .PARAMETER Path
        The folder tree to measure. The path is interpreted on the target
        machine, never resolved locally.

    .PARAMETER Property
        Which file timestamp drives the age bucket: LastWriteTime (the
        default), CreationTime, or LastAccessTime.

    .PARAMETER ComputerName
        One or more computer names to query. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote computers.
        Not used for local queries.

    .EXAMPLE
        Show-FolderUsageAge -Path 'C:\Logs'

        Reports the seven age buckets for the local C:\Logs tree.

    .EXAMPLE
        Show-FolderUsageAge -Path 'C:\Logs' -ComputerName 'SRV01'

        Reports the seven age buckets for C:\Logs on SRV01.

    .EXAMPLE
        'SRV01', 'SRV02' | Show-FolderUsageAge -Path 'C:\Logs'

        Reports age buckets for multiple servers via the pipeline.

    .EXAMPLE
        Show-FolderUsageAge -Path 'C:\Archive' -Property CreationTime

        Buckets C:\Archive by file creation date instead of last write time.

    .OUTPUTS
        PSWinOps.FolderUsageAge
        Seven objects per tree, one per age bucket, ordered oldest first, each
        carrying the AgeBucket label, its inclusive MinAgeDays and exclusive
        MaxAgeDays bounds, the file count, the exact byte and rounded MB size,
        the share of the tree total, the tree totals (TotalSizeBytes and
        TotalFileCount, repeated on every row), the AgeProperty the buckets were
        computed from, and the number of unreadable subfolders. The default
        view renders a fixed-width usage bar.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-19
        Requires: PowerShell 5.1+ / Windows only
        Requires: Read access to Path on the target machine. Subfolders the
        caller cannot read are counted in InaccessibleCount rather than failing
        the whole tree, so non-elevated callers may under-report totals. This
        command walks every file in the tree, so runtime grows with the number
        of files and can be long on very large trees.
        Note: LastAccessTime is unreliable on Windows — NTFS last-access
        updates are disabled by default (NtfsDisableLastAccessUpdate), so
        buckets computed from it may reflect the last write instead.

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-childitem
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.FolderUsageAge')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('LastWriteTime', 'CreationTime', 'LastAccessTime')]
        [string]$Property = 'LastWriteTime',

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # The whole aggregation runs here, on the target machine: the tree is
        # walked and the seven buckets are summed remotely, so only the summary
        # rows travel back over the wire.
        $scriptBlock = {
            param($TargetPath, $AgeProperty)

            $rootItem = Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
            if ($null -eq $rootItem) {
                throw "Path '$TargetPath' does not exist on '$env:COMPUTERNAME'."
            }
            if (-not $rootItem.PSIsContainer) {
                throw "Path '$TargetPath' is a file, not a directory."
            }
            $rootPath = $rootItem.FullName

            # One clock reading for the whole scan, so every file is aged
            # against the same instant.
            $now = Get-Date

            # The seven buckets, oldest first, always emitted in this order even
            # when empty. MinAgeDays is inclusive, MaxAgeDays exclusive;
            # [int]::MaxValue marks the unbounded oldest bucket.
            $buckets = @(
                [PSCustomObject]@{ AgeBucket = '>2y'; MinAgeDays = [int]730; MaxAgeDays = [int]::MaxValue; FileCount = [long]0; SizeBytes = [long]0 }
                [PSCustomObject]@{ AgeBucket = '1-2y'; MinAgeDays = [int]365; MaxAgeDays = [int]730; FileCount = [long]0; SizeBytes = [long]0 }
                [PSCustomObject]@{ AgeBucket = '180-365d'; MinAgeDays = [int]180; MaxAgeDays = [int]365; FileCount = [long]0; SizeBytes = [long]0 }
                [PSCustomObject]@{ AgeBucket = '90-180d'; MinAgeDays = [int]90; MaxAgeDays = [int]180; FileCount = [long]0; SizeBytes = [long]0 }
                [PSCustomObject]@{ AgeBucket = '30-90d'; MinAgeDays = [int]30; MaxAgeDays = [int]90; FileCount = [long]0; SizeBytes = [long]0 }
                [PSCustomObject]@{ AgeBucket = '7-30d'; MinAgeDays = [int]7; MaxAgeDays = [int]30; FileCount = [long]0; SizeBytes = [long]0 }
                [PSCustomObject]@{ AgeBucket = '0-7d'; MinAgeDays = [int]0; MaxAgeDays = [int]7; FileCount = [long]0; SizeBytes = [long]0 }
            )

            # Manual traversal instead of a single -Recurse -File pass so
            # reparse-point directories (junctions, mount points, symlinks) are
            # skipped: following them could double-count files or loop. A
            # subfolder we cannot read raises a non-terminating error that is
            # counted rather than thrown, so the accessible remainder of the
            # tree is still reported.
            $files = [System.Collections.Generic.List[object]]::new()
            $inaccessible = [long]0
            $directoryStack = [System.Collections.Generic.Stack[string]]::new()
            $directoryStack.Push($rootPath)

            while ($directoryStack.Count -gt 0) {
                $directoryPath = $directoryStack.Pop()
                $directoryErrors = $null
                $items = Get-ChildItem -LiteralPath $directoryPath -Force `
                    -ErrorAction SilentlyContinue -ErrorVariable directoryErrors
                $inaccessible += [long]@($directoryErrors).Count

                foreach ($item in $items) {
                    if ($item.PSIsContainer) {
                        $reparsePoint = [int][System.IO.FileAttributes]::ReparsePoint
                        if (([int]$item.Attributes -band $reparsePoint) -eq $reparsePoint) {
                            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Skipping reparse-point directory '$($item.FullName)'."
                            continue
                        }
                        $directoryStack.Push($item.FullName)
                    }
                    else {
                        $files.Add($item)
                    }
                }
            }

            $totalBytes = [long]0
            $totalFiles = [long]0

            foreach ($file in $files) {
                $length = [long]$file.Length
                $totalBytes += $length
                $totalFiles++

                $ageDays = ($now - [datetime]$file.$AgeProperty).TotalDays
                if ($ageDays -lt 0) {
                    # A future-dated timestamp (clock skew, restored archive)
                    # clamps into the newest bucket instead of falling through.
                    $ageDays = [double]0
                }

                foreach ($bucket in $buckets) {
                    $upperBound = $bucket.MaxAgeDays
                    if ($ageDays -ge $bucket.MinAgeDays -and $ageDays -lt $upperBound) {
                        $bucket.FileCount = [long]$bucket.FileCount + 1
                        $bucket.SizeBytes = [long]$bucket.SizeBytes + $length
                        break
                    }
                }
            }

            if ($totalFiles -eq 0) {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] The folder '$rootPath' contained no files."
            }

            $rows = foreach ($bucket in $buckets) {
                $sizeBytes = [long]$bucket.SizeBytes

                # An empty (or fully unreadable) tree totals zero bytes: report
                # 0 percent instead of dividing by zero.
                $percentOfTotal = [double]0
                if ($totalBytes -gt 0) {
                    $percentOfTotal = [math]::Round(($sizeBytes / $totalBytes) * 100, 2)
                }

                [PSCustomObject]@{
                    Path              = $rootPath
                    AgeBucket         = $bucket.AgeBucket
                    MinAgeDays        = [int]$bucket.MinAgeDays
                    MaxAgeDays        = [int]$bucket.MaxAgeDays
                    FileCount         = [long]$bucket.FileCount
                    SizeBytes         = $sizeBytes
                    SizeMB            = [math]::Round($sizeBytes / 1MB, 2)
                    PercentOfTotal    = $percentOfTotal
                    TotalSizeBytes    = $totalBytes
                    TotalFileCount    = $totalFiles
                    AgeProperty       = $AgeProperty
                    InaccessibleCount = [long]$inaccessible
                }
            }

            $rows
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Measuring '$Path' on '$machine' by $Property"

                $rows = @(Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock `
                        -ArgumentList @($Path, $Property) -Credential $Credential)

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        PSTypeName        = 'PSWinOps.FolderUsageAge'
                        ComputerName      = $machine
                        Path              = $row.Path
                        AgeBucket         = $row.AgeBucket
                        MinAgeDays        = [int]$row.MinAgeDays
                        MaxAgeDays        = [int]$row.MaxAgeDays
                        FileCount         = [long]$row.FileCount
                        SizeBytes         = [long]$row.SizeBytes
                        SizeMB            = [double]$row.SizeMB
                        PercentOfTotal    = [double]$row.PercentOfTotal
                        TotalSizeBytes    = [long]$row.TotalSizeBytes
                        TotalFileCount    = [long]$row.TotalFileCount
                        AgeProperty       = $row.AgeProperty
                        InaccessibleCount = [long]$row.InaccessibleCount
                        Timestamp         = Get-Date -Format 'o'
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
