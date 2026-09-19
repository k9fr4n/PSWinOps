#Requires -Version 5.1
function Show-FolderUsage {
    <#
    .SYNOPSIS
        Shows folder tree disk usage by file extension with a usage bar

    .DESCRIPTION
        Aggregates one folder tree per target computer by file extension and
        emits one PSWinOps.FolderUsage object per extension, sorted descending
        by SizeBytes. Remote calls dispatch through Invoke-RemoteOrLocal, so the
        Path is resolved and the tree is walked, grouped and sorted on the
        target machine, and only the per-extension summary rows cross the wire.
        Unreadable subfolders are tolerated and reported through a non-zero
        InaccessibleCount instead of discarding the partial result, and one
        failing computer never stops the remaining ones.

    .PARAMETER Path
        The folder tree to measure. The path is interpreted on the target
        machine, never resolved locally. Extensionless files are grouped under
        '(none)', and extensions are compared case-insensitively.

    .PARAMETER ComputerName
        One or more computer names to query. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Threshold
        Percentage of the tree's total size below which an extension row is
        omitted, between 0 and 100. Defaults to 0, which keeps every extension.

    .PARAMETER Top
        Keep only the N largest extensions, between 1 and 1000. When omitted,
        every extension that survives the threshold is returned.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote computers.
        Not used for local queries.

    .EXAMPLE
        Show-FolderUsage -Path 'C:\inetpub\wwwroot'

        Reports usage per file extension for the local wwwroot tree.

    .EXAMPLE
        Show-FolderUsage -Path 'C:\inetpub\wwwroot' -ComputerName 'SRV01'

        Reports usage per file extension for the wwwroot tree on SRV01.

    .EXAMPLE
        'SRV01', 'SRV02' | Show-FolderUsage -Path 'C:\inetpub\wwwroot'

        Reports per-extension usage for multiple servers via the pipeline.

    .EXAMPLE
        Show-FolderUsage -Path 'C:\Logs' -Threshold 5 -Top 20

        Shows the 20 largest extensions that make up at least 5 percent of the
        C:\Logs tree.

    .OUTPUTS
        PSWinOps.FolderUsage
        One object per file extension with the file count, the exact byte and
        rounded MB size, the share of the tree total, the tree totals
        (TotalSizeBytes and TotalFileCount, repeated on every row), and the
        number of unreadable subfolders. The default view renders a fixed-width
        usage bar.

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

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-childitem
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.FolderUsage')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 100)]
        [double]$Threshold = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$Top,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # The whole aggregation runs here, on the target machine: the tree is
        # walked, grouped by extension, summed, sorted and truncated remotely so
        # only the per-extension summary rows travel back over the wire.
        $scriptBlock = {
            param($TargetPath, $MinPercent, $MaxRows)

            $rootItem = Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
            if ($null -eq $rootItem) {
                throw "Path '$TargetPath' does not exist on '$env:COMPUTERNAME'."
            }
            if (-not $rootItem.PSIsContainer) {
                throw "Path '$TargetPath' is a file, not a directory."
            }
            $rootPath = $rootItem.FullName

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

            $stats = @{}
            $totalBytes = [long]0
            $totalFiles = [long]0

            foreach ($file in $files) {
                $length = [long]$file.Length
                $totalBytes += $length
                $totalFiles++

                $extension = if ([string]::IsNullOrEmpty($file.Extension)) {
                    '(none)'
                }
                else {
                    $file.Extension.ToLowerInvariant()
                }

                if ($stats.ContainsKey($extension)) {
                    $stats[$extension].FileCount = [long]$stats[$extension].FileCount + 1
                    $stats[$extension].SizeBytes = [long]$stats[$extension].SizeBytes + $length
                }
                else {
                    $stats[$extension] = [PSCustomObject]@{
                        FileCount = [long]1
                        SizeBytes = $length
                    }
                }
            }

            if ($totalFiles -eq 0) {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] The folder '$rootPath' contained no files."
            }

            $rows = foreach ($extension in $stats.Keys) {
                $sizeBytes = [long]$stats[$extension].SizeBytes

                # An empty (or fully unreadable) tree totals zero bytes: report
                # 0 percent instead of dividing by zero.
                $percentOfTotal = [double]0
                if ($totalBytes -gt 0) {
                    $percentOfTotal = [math]::Round(($sizeBytes / $totalBytes) * 100, 2)
                }

                [PSCustomObject]@{
                    Path              = $rootPath
                    Extension         = $extension
                    FileCount         = [long]$stats[$extension].FileCount
                    SizeBytes         = $sizeBytes
                    SizeMB            = [math]::Round($sizeBytes / 1MB, 2)
                    PercentOfTotal    = $percentOfTotal
                    TotalSizeBytes    = $totalBytes
                    TotalFileCount    = $totalFiles
                    InaccessibleCount = [long]$inaccessible
                }
            }

            $rows = @($rows |
                Where-Object -FilterScript { $_.PercentOfTotal -ge $MinPercent } |
                Sort-Object -Property 'SizeBytes' -Descending)

            if ($MaxRows -gt 0) {
                $rows = @($rows | Select-Object -First $MaxRows)
            }

            $rows
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Measuring '$Path' on '$machine'"

                $rows = @(Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock `
                        -ArgumentList @($Path, $Threshold, $Top) -Credential $Credential)

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        PSTypeName        = 'PSWinOps.FolderUsage'
                        ComputerName      = $machine
                        Path              = $row.Path
                        Extension         = $row.Extension
                        FileCount         = [long]$row.FileCount
                        SizeBytes         = [long]$row.SizeBytes
                        SizeMB            = [double]$row.SizeMB
                        PercentOfTotal    = [double]$row.PercentOfTotal
                        TotalSizeBytes    = [long]$row.TotalSizeBytes
                        TotalFileCount    = [long]$row.TotalFileCount
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
