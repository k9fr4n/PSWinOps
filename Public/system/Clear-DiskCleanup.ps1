#Requires -Version 5.1
function Clear-DiskCleanup {
    <#
        .SYNOPSIS
            Removes temporary files and system cleanup targets from local or remote machines

        .DESCRIPTION
            Performs disk cleanup operations across multiple categories including temporary
            files, Windows Update cache, Recycle Bin, crash dumps, old logs, browser caches,
            Windows.old, and thumbnail caches. Supports remote execution via the private
            Invoke-RemoteOrLocal helper. Accepts pipeline input from Get-DiskCleanupInfo.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by property name.

        .PARAMETER Category
            One or more cleanup categories to process. Valid values: TempFiles,
            WindowsUpdate, RecycleBin, CrashDumps, OldLogs, BrowserCache, WindowsOld,
            ThumbnailCache, All. Defaults to All.

        .PARAMETER OlderThanDays
            Only remove files older than this many days for TempFiles and OldLogs
            categories. Valid range 1-3650. Defaults to 30.

        .PARAMETER ExcludePath
            One or more file paths to exclude from cleanup. Files whose full path
            starts with any excluded path will be skipped.

        .PARAMETER Force
            Suppresses the confirmation prompt and forces deletion of read-only files.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Clear-DiskCleanup -Category 'TempFiles' -Force

            Cleans temporary files older than 30 days on the local computer.

        .EXAMPLE
            Clear-DiskCleanup -ComputerName 'SRV01' -Category 'WindowsUpdate', 'OldLogs' -Force

            Cleans WindowsUpdate cache and old log files on remote server SRV01.

        .EXAMPLE
            Get-DiskCleanupInfo -ComputerName 'SRV01' | Where-Object SizeMB -gt 100 | Clear-DiskCleanup -Force

            Pipes scan results and cleans only categories larger than 100 MB.

        .EXAMPLE
            Clear-DiskCleanup -Category 'All' -ExcludePath 'C:\Windows\Logs\CBS' -WhatIf

            Shows what would be cleaned across all categories, excluding a specific path.

        .OUTPUTS
            PSWinOps.DiskCleanupResult
            Returns one result object per category per computer with FilesRemoved,
            FilesSkipped, SpaceRecoveredBytes, SpaceRecoveredMB, and Errors.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-10
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges for most categories

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('PSWinOps.DiskCleanupResult')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('TempFiles', 'WindowsUpdate', 'RecycleBin', 'CrashDumps', 'OldLogs', 'BrowserCache', 'WindowsOld', 'ThumbnailCache', 'All')]
        [string[]]$Category = 'All',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]$OlderThanDays = 30,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludePath,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting disk cleanup"

        $allCategories = @(
            'TempFiles', 'WindowsUpdate', 'RecycleBin', 'CrashDumps',
            'OldLogs', 'BrowserCache', 'WindowsOld', 'ThumbnailCache'
        )

        $resolvedCategories = if ($Category -contains 'All') { $allCategories } else { $Category }

        if ($Force.IsPresent -and -not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = 'None'
        }

        $cleanupBlock = {
            param(
                [string]$CategoryName,
                [int]$DaysOld,
                [string]$ExcludeJson,
                [bool]$ForceCleanup
            )

            $excludes = if ($ExcludeJson) { @(ConvertFrom-Json -InputObject $ExcludeJson) } else { @() }
            $cutoffDate = (Get-Date).AddDays(-$DaysOld)

            $state = @{
                FilesRemoved   = 0
                FilesSkipped   = 0
                SpaceRecovered = [long]0
                Errors         = [System.Collections.Generic.List[string]]::new()
            }

            # Common file deletion helper with exclusion check and error collection
            $processFileList = {
                param([object[]]$FileItems)
                foreach ($fileItem in $FileItems) {
                    $skipItem = $false
                    foreach ($exc in $excludes) {
                        if ($fileItem.FullName.StartsWith($exc, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $skipItem = $true
                            break
                        }
                    }
                    if ($skipItem) {
                        $state.FilesSkipped++
                        continue
                    }
                    try {
                        $itemSize = [long]$fileItem.Length
                        Remove-Item -LiteralPath $fileItem.FullName -Force:$ForceCleanup -ErrorAction Stop
                        $state.FilesRemoved++
                        $state.SpaceRecovered += $itemSize
                    }
                    catch {
                        $state.FilesSkipped++
                        if ($state.Errors.Count -lt 10) {
                            $state.Errors.Add("$($fileItem.FullName): $($_.Exception.Message)")
                        }
                    }
                }
            }

            switch ($CategoryName) {

                'TempFiles' {
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
                            if ($files) { & $processFileList -FileItems $files }
                        }
                    }
                }

                'WindowsUpdate' {
                    $downloadPath = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\Download'
                    $serviceWasStopped = $false
                    try {
                        Stop-Service -Name 'wuauserv' -Force -ErrorAction Stop
                        $serviceWasStopped = $true
                    }
                    catch {
                        if ($state.Errors.Count -lt 10) {
                            $state.Errors.Add("Failed to stop wuauserv: $($_.Exception.Message)")
                        }
                    }
                    if (Test-Path -LiteralPath $downloadPath) {
                        $files = @(Get-ChildItem -LiteralPath $downloadPath -Recurse -File -Force -ErrorAction SilentlyContinue)
                        if ($files) { & $processFileList -FileItems $files }
                    }
                    if ($serviceWasStopped) {
                        try {
                            Start-Service -Name 'wuauserv' -ErrorAction Stop
                        }
                        catch {
                            if ($state.Errors.Count -lt 10) {
                                $state.Errors.Add("Failed to start wuauserv: $($_.Exception.Message)")
                            }
                        }
                    }
                }

                'RecycleBin' {
                    try {
                        Clear-RecycleBin -Force -ErrorAction Stop
                        $state.FilesRemoved++
                    }
                    catch {
                        # Fallback: manual removal
                        $recyclePath = Join-Path -Path $env:SystemDrive -ChildPath '$Recycle.Bin'
                        if (Test-Path -LiteralPath $recyclePath) {
                            $files = @(
                                Get-ChildItem -LiteralPath $recyclePath -Recurse -File -Force -ErrorAction SilentlyContinue
                            )
                            if ($files) { & $processFileList -FileItems $files }
                        }
                    }
                }

                'CrashDumps' {
                    $dumpPaths = @(
                        (Join-Path -Path $env:SystemRoot -ChildPath 'Minidump')
                        (Join-Path -Path $env:SystemRoot -ChildPath 'LiveKernelReports')
                    )
                    foreach ($dumpPath in $dumpPaths) {
                        if (Test-Path -LiteralPath $dumpPath) {
                            $files = @(
                                Get-ChildItem -LiteralPath $dumpPath -Filter '*.dmp' -Recurse -File -Force -ErrorAction SilentlyContinue
                            )
                            if ($files) { & $processFileList -FileItems $files }
                        }
                    }
                    $memoryDmpPath = Join-Path -Path $env:SystemRoot -ChildPath 'MEMORY.DMP'
                    if (Test-Path -LiteralPath $memoryDmpPath) {
                        $memDmp = Get-Item -LiteralPath $memoryDmpPath -Force -ErrorAction SilentlyContinue
                        if ($memDmp) { & $processFileList -FileItems @($memDmp) }
                    }
                }

                'OldLogs' {
                    $logPaths = @(
                        (Join-Path -Path $env:SystemRoot -ChildPath 'Logs')
                        (Join-Path -Path $env:SystemRoot -ChildPath 'System32\LogFiles')
                    )
                    $inetpubLogs = 'C:\inetpub\logs'
                    if (Test-Path -LiteralPath $inetpubLogs) {
                        $logPaths += $inetpubLogs
                    }
                    foreach ($logPath in $logPaths) {
                        if (Test-Path -LiteralPath $logPath) {
                            $files = @(
                                Get-ChildItem -LiteralPath $logPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                                    Where-Object -FilterScript {
                                        ($_.Extension -eq '.log' -or $_.Extension -eq '.etl') -and
                                        $_.LastWriteTime -lt $cutoffDate
                                    }
                            )
                            if ($files) { & $processFileList -FileItems $files }
                        }
                    }
                }

                'BrowserCache' {
                    $skipProfiles = @('Public', 'Default', 'Default User', 'All Users')
                    $cacheRelatives = @(
                        'AppData\Local\Google\Chrome\User Data\*\Cache\*'
                        'AppData\Local\Microsoft\Edge\User Data\*\Cache\*'
                        'AppData\Local\Mozilla\Firefox\Profiles\*\cache2\*'
                    )
                    $usersDir = Join-Path -Path $env:SystemDrive -ChildPath 'Users'
                    if (Test-Path -LiteralPath $usersDir) {
                        $userDirs = @(
                            Get-ChildItem -LiteralPath $usersDir -Directory -Force -ErrorAction SilentlyContinue |
                                Where-Object -FilterScript { $_.Name -notin $skipProfiles }
                        )
                        foreach ($userDir in $userDirs) {
                            foreach ($rel in $cacheRelatives) {
                                $fullGlob = Join-Path -Path $userDir.FullName -ChildPath $rel
                                $files = @(Get-ChildItem -Path $fullGlob -Recurse -File -Force -ErrorAction SilentlyContinue)
                                if ($files) { & $processFileList -FileItems $files }
                            }
                        }
                    }
                }

                'WindowsOld' {
                    $windowsOldPath = Join-Path -Path $env:SystemDrive -ChildPath 'Windows.old'
                    if (Test-Path -LiteralPath $windowsOldPath) {
                        if ($excludes.Count -eq 0) {
                            # Fast path: measure then remove entire directory
                            $files = @(Get-ChildItem -LiteralPath $windowsOldPath -Recurse -File -Force -ErrorAction SilentlyContinue)
                            $totalSize = [long]0
                            foreach ($f in $files) { $totalSize += $f.Length }
                            try {
                                Remove-Item -LiteralPath $windowsOldPath -Recurse -Force:$ForceCleanup -ErrorAction Stop
                                $state.FilesRemoved += $files.Count
                                $state.SpaceRecovered += $totalSize
                            }
                            catch {
                                if ($state.Errors.Count -lt 10) {
                                    $state.Errors.Add("Failed to remove Windows.old: $($_.Exception.Message)")
                                }
                            }
                        }
                        else {
                            # File-by-file to honour exclusions
                            $files = @(Get-ChildItem -LiteralPath $windowsOldPath -Recurse -File -Force -ErrorAction SilentlyContinue)
                            if ($files) { & $processFileList -FileItems $files }
                        }
                    }
                }

                'ThumbnailCache' {
                    $skipProfiles = @('Public', 'Default', 'Default User', 'All Users')
                    $usersDir = Join-Path -Path $env:SystemDrive -ChildPath 'Users'
                    if (Test-Path -LiteralPath $usersDir) {
                        $userDirs = @(
                            Get-ChildItem -LiteralPath $usersDir -Directory -Force -ErrorAction SilentlyContinue |
                                Where-Object -FilterScript { $_.Name -notin $skipProfiles }
                        )
                        foreach ($userDir in $userDirs) {
                            $explorerPath = Join-Path -Path $userDir.FullName -ChildPath 'AppData\Local\Microsoft\Windows\Explorer'
                            if (Test-Path -LiteralPath $explorerPath) {
                                $files = @(
                                    Get-ChildItem -LiteralPath $explorerPath -Filter 'thumbcache_*.db' -File -Force -ErrorAction SilentlyContinue
                                )
                                if ($files) { & $processFileList -FileItems $files }
                            }
                        }
                    }
                }
            }

            @{
                Category       = $CategoryName
                FilesRemoved   = $state.FilesRemoved
                FilesSkipped   = $state.FilesSkipped
                SpaceRecovered = $state.SpaceRecovered
                Errors         = @($state.Errors)
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$machine'"

            $excludeJson = if ($ExcludePath) {
                ConvertTo-Json -InputObject @($ExcludePath) -Compress
            }
            else {
                ''
            }

            foreach ($cat in $resolvedCategories) {
                if (-not $PSCmdlet.ShouldProcess("$machine --> $cat", "Remove $cat cleanup targets")) {
                    continue
                }

                try {
                    $invokeParams = @{
                        ComputerName = $machine
                        ScriptBlock  = $cleanupBlock
                        ArgumentList = @($cat, $OlderThanDays, $excludeJson, $Force.IsPresent)
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $invokeParams['Credential'] = $Credential
                    }

                    $raw = Invoke-RemoteOrLocal @invokeParams

                    [PSCustomObject]@{
                        PSTypeName          = 'PSWinOps.DiskCleanupResult'
                        ComputerName        = $machine
                        Category            = $raw.Category
                        FilesRemoved        = [int]$raw.FilesRemoved
                        FilesSkipped        = [int]$raw.FilesSkipped
                        SpaceRecoveredBytes = [long]$raw.SpaceRecovered
                        SpaceRecoveredMB    = [math]::Round($raw.SpaceRecovered / 1MB, 2)
                        Errors              = $raw.Errors
                        Timestamp           = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
                catch {
                    Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                    continue
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
