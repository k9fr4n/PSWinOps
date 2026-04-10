#Requires -Version 5.1
function Get-DiskCleanupInfo {
    <#
        .SYNOPSIS
            Scans a Windows computer and reports what can be cleaned up without deleting anything

        .DESCRIPTION
            Analyzes multiple cleanup categories on local or remote Windows computers
            and returns size information for each category. Categories include temporary
            files, Windows Update cache, Recycle Bin, crash dumps, old logs, browser
            caches, Windows.old, and thumbnail caches. No files are deleted.

        .PARAMETER ComputerName
            One or more computer names to scan. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Category
            One or more cleanup categories to scan. Valid values are TempFiles,
            WindowsUpdate, RecycleBin, CrashDumps, OldLogs, BrowserCache,
            WindowsOld, ThumbnailCache, and All. Defaults to All.

        .PARAMETER OlderThanDays
            Number of days used to filter the TempFiles and OldLogs categories.
            Only files older than this threshold are reported for those categories.
            Defaults to 30. Has no effect on other categories.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-DiskCleanupInfo

            Scans all cleanup categories on the local computer.

        .EXAMPLE
            Get-DiskCleanupInfo -ComputerName 'SRV01' -Category 'TempFiles', 'OldLogs'

            Scans only TempFiles and OldLogs categories on remote server SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-DiskCleanupInfo -Category 'BrowserCache'

            Scans browser cache on multiple remote servers via pipeline.

        .OUTPUTS
            PSWinOps.DiskCleanupInfo
            Returns one object per cleanup category per computer with file count,
            size in bytes and megabytes, and oldest/newest file timestamps.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-10
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges for full scan accuracy

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/scripting/learn/remoting/running-remote-commands
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DiskCleanupInfo')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateSet('TempFiles', 'WindowsUpdate', 'RecycleBin', 'CrashDumps', 'OldLogs', 'BrowserCache', 'WindowsOld', 'ThumbnailCache', 'All')]
        [string[]]$Category = 'All',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]$OlderThanDays = 30,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $allCategories = @(
            'TempFiles'
            'WindowsUpdate'
            'RecycleBin'
            'CrashDumps'
            'OldLogs'
            'BrowserCache'
            'WindowsOld'
            'ThumbnailCache'
        )

        if ($Category -contains 'All') {
            $resolvedCategories = $allCategories
        }
        else {
            $resolvedCategories = $Category
        }

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Categories: $($resolvedCategories -join ', ')"

        $scanBlock = {
            param(
                [string[]]$CategoriesToScan,
                [int]$LogAgeDays
            )

            $cutoffDate = (Get-Date).AddDays(-$LogAgeDays)

            # Helper: measure a file collection and return a result hashtable
            function Measure-FileCollection {
                param(
                    [string]$CategoryName,
                    [string]$BasePath,
                    [object[]]$FileList
                )
                $fileCount = 0
                $sizeBytes = [long]0
                $oldestFile = $null
                $newestFile = $null

                if ($FileList -and $FileList.Count -gt 0) {
                    $measure = $FileList | Measure-Object -Property Length -Sum
                    $fileCount = $measure.Count
                    $sizeBytes = [long]$measure.Sum
                    $sorted = $FileList | Sort-Object -Property LastWriteTime
                    $oldestFile = $sorted[0].LastWriteTime
                    $newestFile = $sorted[-1].LastWriteTime
                }

                @{
                    Category  = $CategoryName
                    Path      = $BasePath
                    FileCount = [int]$fileCount
                    SizeBytes = $sizeBytes
                    SizeMB    = [math]::Round($sizeBytes / 1MB, 2)
                    OldestFile = $oldestFile
                    NewestFile = $newestFile
                }
            }

            $results = [System.Collections.Generic.List[hashtable]]::new()

            # --- TempFiles ---
            if ($CategoriesToScan -contains 'TempFiles') {
                $tempPaths = @(
                    $env:TEMP
                    (Join-Path -Path $env:SystemRoot -ChildPath 'Temp')
                )
                foreach ($tempPath in $tempPaths) {
                    if (Test-Path -LiteralPath $tempPath) {
                        $files = @(
                            Get-ChildItem -LiteralPath $tempPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                                Where-Object -FilterScript { $_.LastWriteTime -lt $cutoffDate }
                        )
                        $results.Add((Measure-FileCollection -CategoryName 'TempFiles' -BasePath $tempPath -FileList $files))
                    }
                }
            }

            # --- WindowsUpdate ---
            if ($CategoriesToScan -contains 'WindowsUpdate') {
                $wuPath = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\Download'
                if (Test-Path -LiteralPath $wuPath) {
                    $files = @(Get-ChildItem -LiteralPath $wuPath -Recurse -File -Force -ErrorAction SilentlyContinue)
                    $results.Add((Measure-FileCollection -CategoryName 'WindowsUpdate' -BasePath $wuPath -FileList $files))
                }
                else {
                    $results.Add((Measure-FileCollection -CategoryName 'WindowsUpdate' -BasePath $wuPath -FileList @()))
                }
            }

            # --- RecycleBin ---
            if ($CategoriesToScan -contains 'RecycleBin') {
                $recyclePath = Join-Path -Path $env:SystemDrive -ChildPath '$Recycle.Bin'
                $rbFiles = @(Get-ChildItem -LiteralPath $recyclePath -Recurse -File -Force -ErrorAction SilentlyContinue)
                $results.Add((Measure-FileCollection -CategoryName 'RecycleBin' -BasePath $recyclePath -FileList $rbFiles))
            }

            # --- CrashDumps ---
            if ($CategoriesToScan -contains 'CrashDumps') {
                $dumpFiles = [System.Collections.Generic.List[object]]::new()
                $dumpPaths = @(
                    (Join-Path -Path $env:SystemRoot -ChildPath 'Minidump')
                    (Join-Path -Path $env:SystemRoot -ChildPath 'LiveKernelReports')
                )
                foreach ($dumpPath in $dumpPaths) {
                    if (Test-Path -LiteralPath $dumpPath) {
                        $found = @(Get-ChildItem -LiteralPath $dumpPath -Filter '*.dmp' -Recurse -File -Force -ErrorAction SilentlyContinue)
                        foreach ($f in $found) { $dumpFiles.Add($f) }
                    }
                }
                $memoryDmpPath = Join-Path -Path $env:SystemRoot -ChildPath 'MEMORY.DMP'
                if (Test-Path -LiteralPath $memoryDmpPath) {
                    $memDmp = Get-Item -LiteralPath $memoryDmpPath -Force -ErrorAction SilentlyContinue
                    if ($memDmp) { $dumpFiles.Add($memDmp) }
                }
                $results.Add((Measure-FileCollection -CategoryName 'CrashDumps' -BasePath (Join-Path -Path $env:SystemRoot -ChildPath 'Minidump') -FileList $dumpFiles.ToArray()))
            }

            # --- OldLogs ---
            if ($CategoriesToScan -contains 'OldLogs') {
                $logPaths = @(
                    (Join-Path -Path $env:SystemRoot -ChildPath 'Logs')
                    (Join-Path -Path $env:SystemRoot -ChildPath 'System32\LogFiles')
                )
                $inetpubLogs = 'C:\inetpub\logs'
                if (Test-Path -LiteralPath $inetpubLogs) {
                    $logPaths += $inetpubLogs
                }
                $allLogFiles = [System.Collections.Generic.List[object]]::new()
                foreach ($logPath in $logPaths) {
                    if (Test-Path -LiteralPath $logPath) {
                        $found = @(
                            Get-ChildItem -LiteralPath $logPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                                Where-Object -FilterScript {
                                    ($_.Extension -eq '.log' -or $_.Extension -eq '.etl') -and
                                    $_.LastWriteTime -lt $cutoffDate
                                }
                        )
                        foreach ($f in $found) { $allLogFiles.Add($f) }
                    }
                }
                $results.Add((Measure-FileCollection -CategoryName 'OldLogs' -BasePath (Join-Path -Path $env:SystemRoot -ChildPath 'Logs') -FileList $allLogFiles.ToArray()))
            }

            # --- BrowserCache ---
            if ($CategoriesToScan -contains 'BrowserCache') {
                $skipProfiles = @('Public', 'Default', 'Default User', 'All Users')
                $cacheRelatives = @(
                    'AppData\Local\Google\Chrome\User Data\*\Cache\*'
                    'AppData\Local\Microsoft\Edge\User Data\*\Cache\*'
                    'AppData\Local\Mozilla\Firefox\Profiles\*\cache2\*'
                )
                $allCacheFiles = [System.Collections.Generic.List[object]]::new()
                $usersDir = Join-Path -Path $env:SystemDrive -ChildPath 'Users'
                if (Test-Path -LiteralPath $usersDir) {
                    $userDirs = @(
                        Get-ChildItem -LiteralPath $usersDir -Directory -Force -ErrorAction SilentlyContinue |
                            Where-Object -FilterScript { $_.Name -notin $skipProfiles }
                    )
                    foreach ($userDir in $userDirs) {
                        foreach ($rel in $cacheRelatives) {
                            $fullGlob = Join-Path -Path $userDir.FullName -ChildPath $rel
                            $found = @(Get-ChildItem -Path $fullGlob -Recurse -File -Force -ErrorAction SilentlyContinue)
                            foreach ($f in $found) { $allCacheFiles.Add($f) }
                        }
                    }
                }
                $results.Add((Measure-FileCollection -CategoryName 'BrowserCache' -BasePath "$usersDir\*\AppData\Local" -FileList $allCacheFiles.ToArray()))
            }

            # --- WindowsOld ---
            if ($CategoriesToScan -contains 'WindowsOld') {
                $windowsOldPath = Join-Path -Path $env:SystemDrive -ChildPath 'Windows.old'
                if (Test-Path -LiteralPath $windowsOldPath) {
                    $files = @(Get-ChildItem -LiteralPath $windowsOldPath -Recurse -File -Force -ErrorAction SilentlyContinue)
                    $results.Add((Measure-FileCollection -CategoryName 'WindowsOld' -BasePath $windowsOldPath -FileList $files))
                }
            }

            # --- ThumbnailCache ---
            if ($CategoriesToScan -contains 'ThumbnailCache') {
                $thumbPattern = Join-Path -Path $env:SystemDrive -ChildPath 'Users\*\AppData\Local\Microsoft\Windows\Explorer\thumbcache_*.db'
                $thumbFiles = @(Get-ChildItem -Path $thumbPattern -File -Force -ErrorAction SilentlyContinue)
                $results.Add((Measure-FileCollection -CategoryName 'ThumbnailCache' -BasePath "$env:SystemDrive\Users\*\AppData\Local\Microsoft\Windows\Explorer" -FileList $thumbFiles))
            }

            $results.ToArray()
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Scanning '$machine'"

                $rawResults = @(Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scanBlock -ArgumentList @(, $resolvedCategories), $OlderThanDays -Credential $Credential)

                foreach ($raw in $rawResults) {
                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.DiskCleanupInfo'
                        ComputerName = $machine
                        Category     = $raw.Category
                        Path         = $raw.Path
                        FileCount    = [int]$raw.FileCount
                        SizeBytes    = [long]$raw.SizeBytes
                        SizeMB       = [double]$raw.SizeMB
                        OldestFile   = $raw.OldestFile
                        NewestFile   = $raw.NewestFile
                        Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
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
