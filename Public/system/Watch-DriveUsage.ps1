#Requires -Version 5.1

function Watch-DriveUsage {
    <#
    .SYNOPSIS
        Interactive disk-space explorer with drill-down navigation

    .DESCRIPTION
        Renders a keyboard-driven console view of disk usage for the local machine.
        Move with the arrow keys, press Enter to drill into a folder and Backspace to
        go back up, R to recompute the current level, F to toggle loose-file
        visibility, Q to quit, and X to quit into the highlighted folder (changing
        the current location to it) so cleanup commands run there. Folder sizes come
        from Measure-FolderSize and the
        frame is drawn by Format-DriveUsageFrame. In folders-only mode the explorer
        shows directories plus the '(files)' aggregate row; in files mode the loose
        files of the current level are shown as first-class rows sorted together with
        the directories.

        Exactly one level is measured at a time, on entering a folder, and the result
        is cached for the rest of the session so going back up does not rescan. This
        command is local-machine only by design: it accepts no -ComputerName and no
        -Credential and never uses WinRM. While a level is being measured, the transient
        status line shows a live folder/file counter so a slow scan stays visibly active
        instead of looking frozen.

    .PARAMETER Path
        Folder to start in. When omitted, a picker lists every fixed volume on the
        local machine and the selected drive is opened instead.

    .PARAMETER Top
        Number of rows kept per folder after sorting by size descending. Valid range
        is 5 to 200. Defaults to 50.

    .PARAMETER NoColor
        Disables ANSI color output for terminals that do not support escape sequences.

    .PARAMETER IncludeFiles
        When set, starts the explorer with loose files shown as first-class rows
        alongside folders, sorted together by size. Press F at any time to toggle
        the mode for the rest of the session.

    .EXAMPLE
        Watch-DriveUsage

        Lists the fixed volumes, then opens the selected drive in the explorer.

    .EXAMPLE
        Watch-DriveUsage -Path 'C:\Windows'

        Opens the explorer directly on C:\Windows and shows its immediate children.

    .EXAMPLE
        Watch-DriveUsage -Top 80 -NoColor

        Starts on the volume picker, keeps 80 rows per folder and emits no ANSI color.

    .EXAMPLE
        Watch-DriveUsage -Path 'C:\Users' -IncludeFiles

        Opens C:\Users with loose files and folders merged in one size-sorted list.

    .OUTPUTS
        None. This function renders an interactive TUI and returns nothing to the
        pipeline.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-20
        Requires: PowerShell 5.1+ / Windows only
        Requires: Interactive console (not ISE or redirected output)
        Requires: Local machine only - no remote support

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive TUI monitor: rendering a frame to the console is the function''s purpose. Requires a live console host (ISE is rejected in begin{}); console state is restored in finally. The Show-* monitors are exempted from this rule by function-name prefix; this function is equivalent and needs the exemption stated explicitly.')]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateRange(5, 200)]
        [int]$Top = 50,

        [Parameter(Mandatory = $false)]
        [switch]$NoColor,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeFiles
    )

    begin {
        # ---- Host check: the TUI needs a real console ----
        if ($Host.Name -eq 'Windows PowerShell ISE Host') {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ISE is not supported. Use Windows Terminal, ConHost, or a remote SSH session."
            return
        }
    }

    process {
        if ($Host.Name -eq 'Windows PowerShell ISE Host') {
            return
        }

        # ============================================================
        # INPUT VALIDATION - everything below happens before [Console]
        # is touched, so a bad input never leaves a half-drawn screen
        # ============================================================
        # Fixed volumes drive both the picker and the header usage bar (Rule 5: CIM).
        $volumes = @()
        try {
            $volumes = @(Get-CimInstance -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3' -ErrorAction Stop)
        }
        catch {
            if (-not $PSBoundParameters.ContainsKey('Path')) {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Could not enumerate fixed volumes: $_"
                return
            }
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Drive figures unavailable: $_"
        }

        $pickerMode = -not $PSBoundParameters.ContainsKey('Path')
        $startItem = $null

        if ($pickerMode) {
            if ($volumes.Count -eq 0) {
                Write-Error -Message "[$($MyInvocation.MyCommand)] No fixed volume was found on this machine."
                return
            }
        }
        else {
            $startItem = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            if ($null -eq $startItem -or -not $startItem.PSIsContainer) {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Path '$Path' is not an existing directory."
                return
            }
        }

        # The picker reuses the folder frame so the module keeps exactly one renderer:
        # a volume row carries the drive letter and label in its name column and its
        # capacity in the size column, and the free space plus used percentage of the
        # highlighted volume are shown on the status line.
        $volumeRows = @()
        if ($pickerMode) {
            $volumeRows = @(
                foreach ($volume in $volumes) {
                    $label = ''
                    if (-not [string]::IsNullOrWhiteSpace($volume.VolumeName)) {
                        $label = "  $($volume.VolumeName)"
                    }
                    [PSCustomObject]@{
                        Name         = "$($volume.DeviceID)$label"
                        FullName     = "$($volume.DeviceID)\"
                        SizeBytes    = [long]$volume.Size
                        FileCount    = [long]0
                        IsContainer  = $true
                        Inaccessible = [long]0
                    }
                }
            )
        }

        # ============================================================
        # SESSION STATE
        # ============================================================
        # Cache: resolved path -> sorted entries for that level. Bounded, oldest first.
        $cache = @{}
        $cacheOrder = [System.Collections.Generic.List[string]]::new()
        $cacheLimit = 256

        $currentPath = if ($pickerMode) { 'Select a drive' } else { $startItem.FullName }
        $entries = @()
        $totalBytes = [long]0
        $selectedIndex = 0
        $stack = [System.Collections.Generic.Stack[string]]::new()
        $statusMessage = ''
        $needCompute = $true
        $scanningPending = $false
        $forceRefresh = $false
        $includeFiles = $IncludeFiles.IsPresent
        $running = $true
        $exitPath = $null

        $previousCtrlC = [Console]::TreatControlCAsInput
        $previousCursorVisible = [Console]::CursorVisible

        try {
            [Console]::TreatControlCAsInput = $true
            [Console]::CursorVisible = $false
            [Console]::Clear()

            while ($running) {
                # ---- Reflow: the window size is re-read on every frame ----
                $width = [math]::Max(80, [Console]::WindowWidth)
                $height = [math]::Max(24, [Console]::WindowHeight)

                # ---- Phase 1: choose the level to draw, one level at a time ----
                # The cache key embeds the visibility mode so a toggle can never
                # reuse the folder-only rows from before the F key was pressed.
                $cacheKey = '{0}|{1}' -f $currentPath, $includeFiles

                if ($needCompute -and -not $scanningPending) {
                    if ($pickerMode) {
                        $entries = $volumeRows
                        $needCompute = $false
                        $forceRefresh = $false
                    }
                    elseif (-not $forceRefresh -and $cache.ContainsKey($cacheKey)) {
                        # Revisit: served from the cache, no rescan, no scanning indicator.
                        $entries = @($cache[$cacheKey])
                        $statusMessage = ''
                        $needCompute = $false
                    }
                    else {
                        # Cache miss or R: announce the scan in the frame first.
                        $scanningPending = $true
                    }
                }

                # ---- Phase 2: draw exactly one frame ----
                $driveLabel = ''
                $driveSizeBytes = [long]0
                $driveFreeBytes = [long]0
                $totalBytes = [long]0

                foreach ($entry in @($entries)) {
                    $totalBytes += [long]$entry.SizeBytes
                }

                if ($pickerMode) {
                    $driveLabel = $env:COMPUTERNAME
                    foreach ($volume in $volumes) {
                        $driveSizeBytes += [long]$volume.Size
                        $driveFreeBytes += [long]$volume.FreeSpace
                    }

                    if ($selectedIndex -lt $volumes.Count) {
                        $highlighted = $volumes[$selectedIndex]
                        $usedPercent = 0
                        if ($highlighted.Size -gt 0) {
                            $usedPercent = [int][math]::Round((($highlighted.Size - $highlighted.FreeSpace) / $highlighted.Size) * 100)
                        }
                        $freeGb = [math]::Round($highlighted.FreeSpace / 1GB, 1)
                        $sizeGb = [math]::Round($highlighted.Size / 1GB, 1)
                        $statusMessage = "$($highlighted.DeviceID)  free $freeGb GB of $sizeGb GB  ($usedPercent% used)"
                    }
                }
                else {
                    $root = [System.IO.Path]::GetPathRoot($currentPath)
                    if (-not [string]::IsNullOrWhiteSpace($root)) {
                        $deviceId = $root.TrimEnd('\')
                        foreach ($volume in $volumes) {
                            if ($volume.DeviceID -eq $deviceId) {
                                $driveLabel = [string]$volume.VolumeName
                                $driveSizeBytes = [long]$volume.Size
                                $driveFreeBytes = [long]$volume.FreeSpace
                            }
                        }
                    }
                }

                $frameParams = @{
                    CurrentPath    = $currentPath
                    Entries        = @($entries)
                    SelectedIndex  = $selectedIndex
                    DriveLabel     = $driveLabel
                    DriveSizeBytes = $driveSizeBytes
                    DriveFreeBytes = $driveFreeBytes
                    TotalBytes     = $totalBytes
                    Width          = $width
                    Height         = $height
                    StatusMessage  = $statusMessage
                    NoColor        = $NoColor
                    IncludeFiles   = $includeFiles
                }

                if ($scanningPending) {
                    # Scanning / Rescanning: the scan is announced before it starts so a
                    # slow folder does not look like a hang.
                    $frameParams['StatusMessage'] = if ($forceRefresh) {
                        'Rescanning this folder...'
                    }
                    else {
                        'Scanning folder sizes, please wait...'
                    }
                    $frame = Format-DriveUsageFrame @frameParams -Scanning
                }
                else {
                    $frame = Format-DriveUsageFrame @frameParams
                }

                # Format-DriveUsageFrame returns the frame without a cursor-home escape
                # (unlike Format-SystemMonitorFrame, which emits its own), so the cursor
                # is homed here: every frame redraws in place instead of scrolling.
                [Console]::SetCursorPosition(0, 0)
                [Console]::Write($frame)
                # Erase whatever a taller previous frame left below this shorter one (a
                # folder with fewer rows than the level just shown) so stale rows never
                # linger at the bottom of the screen. ESC[0J clears from the cursor to
                # the end of the screen and, like the cursor home, ignores -NoColor.
                [Console]::Write("$([char]27)[0J")

                # ---- Phase 3: run the announced scan, then redraw with the result ----
                if ($scanningPending) {
                    $scanErrors = @()

                    # Live progress: while the level is measured, Measure-FolderSize
                    # invokes this callback, which redraws the frame in place with an
                    # advancing folder/file counter so a slow scan visibly moves
                    # instead of looking frozen. The counter goes on the transient
                    # status line; the header keeps its steady 'Scanning...' indicator.
                    # The progress callback runs inside Measure-FolderSize, so it cannot
                    # close over this function's locals with GetNewClosure(): a closure gets
                    # its own module and would lose the private Format-DriveUsageFrame
                    # renderer (and, in picker mode, would also fail copying the empty
                    # [ValidateNotNullOrEmpty()]-constrained $Path). Keep it a plain
                    # scriptblock — which still resolves the module's functions — and share
                    # the per-scan state through module scope.
                    $script:DriveUsageFrameParams  = $frameParams
                    $script:DriveUsageForceRefresh = $forceRefresh

                    $onProgress = {
                        param($progress)
                        $files  = '{0:N0} files' -f [long]$progress.FileCount
                        $label  = if ($script:DriveUsageForceRefresh) { 'Rescanning' } else { 'Scanning' }
                        $status = '{0} {1}/{2} folders - {3}' -f $label, $progress.FolderIndex, $progress.FolderCount, $files
                        $p = @{} + $script:DriveUsageFrameParams
                        $p['StatusMessage'] = $status
                        $scanFrame = Format-DriveUsageFrame @p -Scanning
                        [Console]::SetCursorPosition(0, 0)
                        [Console]::Write($scanFrame)
                        [Console]::Write("$([char]27)[0J")
                    }

                    $measured = @(Measure-FolderSize -Path $currentPath -ErrorAction SilentlyContinue -ErrorVariable scanErrors -IncludeFiles:$includeFiles -OnProgress $onProgress)
                    if ($includeFiles) {
                        # The aggregate row already summarises the same loose bytes as
                        # the per-file rows, so it must not also join the size-sorted
                        # list or every file's percentage would be deflated.
                        $measured = @($measured | Where-Object { -not ($_.IsContainer -and $_.Name -eq '(files)' -and $_.FullName -eq $currentPath) })
                    }
                    $entries = @($measured | Sort-Object -Property 'SizeBytes' -Descending | Select-Object -First $Top)

                    # Cache this level, evicting the oldest entry past the cap.
                    if ($cache.ContainsKey($cacheKey)) {
                        $null = $cacheOrder.Remove($cacheKey)
                    }
                    $cache[$cacheKey] = $entries
                    $cacheOrder.Add($cacheKey)
                    while ($cacheOrder.Count -gt $cacheLimit) {
                        $oldest = $cacheOrder[0]
                        $cacheOrder.RemoveAt(0)
                        $cache.Remove($oldest)
                    }

                    $inaccessible = 0
                    foreach ($entry in $entries) {
                        if ([long]$entry.Inaccessible -gt 0) {
                            $inaccessible++
                        }
                    }

                    if ($scanErrors.Count -gt 0) {
                        # AccessDenied: the level may be incomplete, the session goes on.
                        $statusMessage = 'Partial results: some items could not be read.'
                    }
                    elseif ($inaccessible -gt 0) {
                        # InaccessibleFolder: the offending rows are flagged by the renderer.
                        $statusMessage = "$inaccessible item(s) could not be fully enumerated - marked with !"
                    }
                    elseif ($entries.Count -eq 0) {
                        $statusMessage = 'No subfolders or loose files in this folder.'
                    }
                    else {
                        # Ready: nothing worth reporting.
                        $statusMessage = ''
                    }

                    if ($selectedIndex -ge $entries.Count) {
                        $selectedIndex = [math]::Max(0, $entries.Count - 1)
                    }

                    $scanningPending = $false
                    $needCompute = $false
                    $forceRefresh = $false
                    continue
                }

                # ---- Phase 4: one key, Ctrl+C checked first so it always wins ----
                while (-not [Console]::KeyAvailable) {
                    Start-Sleep -Milliseconds 50
                }

                $key = [Console]::ReadKey($true)

                if ($key.Key -eq [ConsoleKey]::C -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                    $running = $false
                    continue
                }

                if ($key.Key -eq [ConsoleKey]::UpArrow) {
                    if ($selectedIndex -gt 0) {
                        $selectedIndex--
                    }
                }
                elseif ($key.Key -eq [ConsoleKey]::DownArrow) {
                    if ($selectedIndex -lt (@($entries).Count - 1)) {
                        $selectedIndex++
                    }
                }
                elseif ($key.Key -eq [ConsoleKey]::Enter) {
                    if ($pickerMode) {
                        $highlighted = $volumes[$selectedIndex]
                        if ($null -ne $highlighted) {
                            $pickerMode = $false
                            $currentPath = "$($highlighted.DeviceID)\"
                            $selectedIndex = 0
                            $stack.Clear()
                            $needCompute = $true
                            $forceRefresh = $false
                        }
                    }
                    else {
                        $target = @($entries)[$selectedIndex]
                        # Drill down. The '(files)' aggregate reports the folder itself
                        # and file rows cannot be opened: both are deliberate no-ops.
                        if ($null -ne $target -and $target.IsContainer -and $target.FullName -ne $currentPath) {
                            $stack.Push($currentPath)
                            $currentPath = $target.FullName
                            $selectedIndex = 0
                            $needCompute = $true
                            $forceRefresh = $false
                        }
                        elseif ($null -ne $target -and -not $target.IsContainer) {
                            # Files are first-class rows but cannot be opened.
                            $statusMessage = 'Not a folder'
                        }
                    }
                }
                elseif ($key.Key -eq [ConsoleKey]::Backspace) {
                    # At the volume-picker level there is nothing to go back to.
                    if (-not $pickerMode -and $stack.Count -gt 0) {
                        $currentPath = $stack.Pop()
                        $selectedIndex = 0
                        $needCompute = $true
                        $forceRefresh = $false
                    }
                }
                elseif ($key.Key -eq [ConsoleKey]::R) {
                    # Force a recompute of the current level, cache included.
                    $forceRefresh = $true
                    $needCompute = $true
                }
                elseif ($key.Key -eq [ConsoleKey]::F) {
                    # Toggle loose-file visibility. The mode-aware cache key forces a
                    # rescan of the current level instead of serving stale rows.
                    $includeFiles = -not $includeFiles
                    $needCompute = $true
                }
                elseif ($key.Key -eq [ConsoleKey]::X) {
                    # Quit the explorer and change into the highlighted folder (or the
                    # current one when the highlight is a file, the '(files)' row or an
                    # empty list) so the caller lands there ready to clean up.
                    if ($pickerMode) {
                        $exitPath = "$($volumes[$selectedIndex].DeviceID)\"
                    }
                    else {
                        $target = @($entries)[$selectedIndex]
                        if ($null -ne $target -and $target.IsContainer -and $target.FullName -ne $currentPath) {
                            $exitPath = $target.FullName
                        }
                        else {
                            $exitPath = $currentPath
                        }
                    }
                    $running = $false
                }
                elseif ($key.Key -eq [ConsoleKey]::Q -or $key.Key -eq [ConsoleKey]::Escape) {
                    $running = $false
                }
                # Any other key is ignored.
            }
        }
        finally {
            [Console]::CursorVisible = $previousCursorVisible
            [Console]::TreatControlCAsInput = $previousCtrlC
            [Console]::Clear()
            Write-Information -MessageData 'Drive usage monitor stopped.' -InformationAction Continue
        }

        # Land the caller in the folder chosen with X so cleanup commands run there.
        # Set-Location emits nothing to the pipeline, preserving the interactive-monitor
        # contract (Rule 6); Q, Escape and Ctrl+C leave the location untouched.
        if ($exitPath) {
            Set-Location -LiteralPath $exitPath
        }
    }
}
