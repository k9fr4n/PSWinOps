#Requires -Version 5.1
function Save-WindowsUpdate {
    <#
        .SYNOPSIS
            Downloads available Windows Updates without installing them

        .DESCRIPTION
            Scans for available Windows Updates and downloads them to the local cache
            without installing. Uses the COM API (Microsoft.Update.Session) to find and
            download updates. Internally calls Get-WindowsUpdate to discover available
            updates, then downloads each one using IUpdateDownloader.
            A progress bar displays download status with speed, percentage based on total
            size, and estimated time remaining. Updates are downloaded one at a time for
            granular progress tracking.
            Use this function to pre-stage updates before a maintenance window, then
            install them later with Install-WindowsUpdate.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not required for local queries.

        .PARAMETER MicrosoftUpdate
            When specified, queries the full Microsoft Update catalog instead of the
            machine's configured source (WSUS, WUFB, or Windows Update).

        .PARAMETER KBArticleID
            Optional filter to download only updates matching the specified KB article IDs.
            Accepts one or more KB identifiers with or without the 'KB' prefix.

        .PARAMETER Classification
            Optional filter to download only updates matching the specified classifications.
            When not specified, all classifications are downloaded.

        .PARAMETER Product
            Optional filter to download only updates matching the specified product names.
            When not specified, all products are downloaded.

        .PARAMETER IncludeHidden
            When specified, includes updates that have been hidden (declined).

        .PARAMETER AcceptEula
            When specified, automatically accepts the End User License Agreement for each
            update before downloading. Required for updates whose EULA has not been
            previously accepted.

        .EXAMPLE
            Save-WindowsUpdate

            Downloads all available updates on the local computer.

        .EXAMPLE
            Save-WindowsUpdate -ComputerName 'SRV01' -KBArticleID 'KB5034441' -AcceptEula

            Downloads a specific update on SRV01, accepting the EULA automatically.

        .EXAMPLE
            'SRV01', 'SRV02' | Save-WindowsUpdate -MicrosoftUpdate -Classification 'Security Updates'

            Downloads security updates from Microsoft Update on SRV01 and SRV02.

        .OUTPUTS
            PSWinOps.WindowsUpdateDownloadResult
            Returns objects with ComputerName, Title, KBArticle, SizeMB, Result, HResult,
            and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-08
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges for downloading updates
            Requires: Windows Update service must be accessible on target machines

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nn-wuapi-iupdatedownloader
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Alias('Download-WindowsUpdate')]
    [OutputType('PSWinOps.WindowsUpdateDownloadResult')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory = $false)]
        [switch]$MicrosoftUpdate,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$KBArticleID,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Classification,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Product,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeHidden,

        [Parameter(Mandatory = $false)]
        [switch]$AcceptEula
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $resultCodeMap = @{
            0 = 'NotStarted'
            1 = 'InProgress'
            2 = 'Succeeded'
            3 = 'SucceededWithErrors'
            4 = 'Failed'
            5 = 'Aborted'
        }

        $downloadScriptBlock = {
            param(
                [string]$UpdateIdToDownload,
                [bool]$UseMicrosoftUpdate,
                [bool]$DoAcceptEula
            )

            try {
                $session = New-Object -ComObject 'Microsoft.Update.Session'
                $session.ClientApplicationID = 'PSWinOps'
                $searcher = $session.CreateUpdateSearcher()

                if ($UseMicrosoftUpdate) {
                    $serviceManager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
                    $serviceManager.ClientApplicationID = 'PSWinOps'
                    $service = $serviceManager.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '')
                    $searcher.ServerSelection = 3
                    $searcher.ServiceID = $service.ServiceID
                }

                $searchResult = $searcher.Search("UpdateID='$UpdateIdToDownload'")

                if ($searchResult.Updates.Count -eq 0) {
                    throw "Update '$UpdateIdToDownload' not found"
                }

                $update = $searchResult.Updates.Item(0)

                if ($DoAcceptEula -and -not $update.EulaAccepted) {
                    $update.AcceptEula()
                }

                if ($update.IsDownloaded) {
                    return [PSCustomObject]@{
                        ResultCode = 2
                        HResult    = 0
                        AlreadyDownloaded = $true
                    }
                }

                if (-not $update.EulaAccepted) {
                    throw "EULA not accepted for '$($update.Title)'. Use -AcceptEula to accept automatically."
                }

                $updateColl = New-Object -ComObject 'Microsoft.Update.UpdateColl'
                $updateColl.Add($update) | Out-Null

                $downloader = $session.CreateUpdateDownloader()
                $downloader.Updates = $updateColl
                $downloadResult = $downloader.Download()

                return [PSCustomObject]@{
                    ResultCode        = [int]$downloadResult.ResultCode
                    HResult           = [int]$downloadResult.HResult
                    AlreadyDownloaded = $false
                }
            }
            catch {
                throw "Failed to download update '$UpdateIdToDownload': $_"
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$computer'"

            try {
                # Step 1: Scan for available updates using Get-WindowsUpdate
                $getParams = @{ ComputerName = $computer }
                if ($MicrosoftUpdate) { $getParams['MicrosoftUpdate'] = $true }
                if ($KBArticleID) { $getParams['KBArticleID'] = $KBArticleID }
                if ($Classification) { $getParams['Classification'] = $Classification }
                if ($Product) { $getParams['Product'] = $Product }
                if ($IncludeHidden) { $getParams['IncludeHidden'] = $true }
                if ($PSBoundParameters.ContainsKey('Credential')) { $getParams['Credential'] = $Credential }

                $activityLabel = "Save-WindowsUpdate — $computer"

                # Step 1: Scan
                Write-Progress -Activity $activityLabel -Status 'Scanning for available updates...' -PercentComplete 0
                $updates = @(Get-WindowsUpdate @getParams)
                Write-Progress -Activity $activityLabel -Status 'Scan complete' -PercentComplete 0

                if ($updates.Count -eq 0) {
                    Write-Progress -Activity $activityLabel -Completed
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No updates to download on '$computer'"
                    continue
                }

                $totalUpdates = $updates.Count
                $totalSizeMB = ($updates | Measure-Object -Property 'SizeMB' -Sum).Sum
                Write-Information -MessageData "[$($MyInvocation.MyCommand)] $computer — $totalUpdates update(s) to download ($([math]::Round($totalSizeMB, 1)) MB)" -InformationAction Continue

                # Step 2: Download each update with progress
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $downloadedSizeMB = 0

                for ($i = 0; $i -lt $totalUpdates; $i++) {
                    $update = $updates[$i]
                    $kbLabel = if ($update.KBArticle) { " ($($update.KBArticle))" } else { '' }

                    # Calculate progress
                    $percentComplete = if ($totalSizeMB -gt 0) {
                        [math]::Min([math]::Floor($downloadedSizeMB / $totalSizeMB * 100), 99)
                    }
                    else {
                        [math]::Min([math]::Floor($i / $totalUpdates * 100), 99)
                    }

                    $elapsedSec = $stopwatch.Elapsed.TotalSeconds
                    $speedMBps = if ($elapsedSec -gt 0 -and $downloadedSizeMB -gt 0) { $downloadedSizeMB / $elapsedSec } else { 0 }
                    $remainingMB = $totalSizeMB - $downloadedSizeMB
                    $etaSeconds = if ($speedMBps -gt 0) { [int]($remainingMB / $speedMBps) } else { -1 }

                    $speedLabel = if ($speedMBps -gt 0) { "$([math]::Round($speedMBps, 1)) MB/s" } else { 'starting...' }
                    $downloadedLabel = "$([math]::Round($downloadedSizeMB, 1))/$([math]::Round($totalSizeMB, 1)) MB"

                    $progressParams = @{
                        Activity         = $activityLabel
                        Status           = "($($i + 1)/$totalUpdates) $downloadedLabel — $speedLabel"
                        CurrentOperation = "$($update.Title)$kbLabel"
                        PercentComplete  = $percentComplete
                    }
                    if ($etaSeconds -ge 0) {
                        $progressParams['SecondsRemaining'] = $etaSeconds
                    }

                    Write-Progress @progressParams

                    if ($PSCmdlet.ShouldProcess("$($update.Title)$kbLabel [$($update.SizeMB) MB]", "Download update on '$computer'")) {
                        $invokeParams = @{
                            ComputerName = $computer
                            ScriptBlock  = $downloadScriptBlock
                            ArgumentList = @($update.UpdateId, [bool]$MicrosoftUpdate, [bool]$AcceptEula)
                        }
                        if ($PSBoundParameters.ContainsKey('Credential')) {
                            $invokeParams['Credential'] = $Credential
                        }

                        try {
                            $dlResult = Invoke-RemoteOrLocal @invokeParams

                            $resultString = if ($resultCodeMap.ContainsKey($dlResult.ResultCode)) {
                                $resultCodeMap[$dlResult.ResultCode]
                            }
                            else {
                                'Unknown'
                            }

                            if ($dlResult.AlreadyDownloaded) {
                                $resultString = 'AlreadyDownloaded'
                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] '$($update.Title)' already downloaded on '$computer'"
                            }

                            $hResultHex = if ($dlResult.HResult -ne 0) {
                                '0x{0:X8}' -f $dlResult.HResult
                            }
                            else {
                                '0x00000000'
                            }

                            [PSCustomObject]@{
                                PSTypeName   = 'PSWinOps.WindowsUpdateDownloadResult'
                                ComputerName = $computer
                                Title        = $update.Title
                                KBArticle    = $update.KBArticle
                                SizeMB       = $update.SizeMB
                                Result       = $resultString
                                HResult      = $hResultHex
                                Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                        }
                        catch {
                            Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to download '$($update.Title)' on '${computer}': $_"

                            [PSCustomObject]@{
                                PSTypeName   = 'PSWinOps.WindowsUpdateDownloadResult'
                                ComputerName = $computer
                                Title        = $update.Title
                                KBArticle    = $update.KBArticle
                                SizeMB       = $update.SizeMB
                                Result       = 'Failed'
                                HResult      = 'Error'
                                Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                        }
                    }

                    $downloadedSizeMB += $update.SizeMB
                }

                Write-Progress -Activity $activityLabel -Completed
                $stopwatch.Stop()
                $elapsed = $stopwatch.Elapsed
                $avgSpeed = if ($elapsed.TotalSeconds -gt 0 -and $downloadedSizeMB -gt 0) {
                    "$([math]::Round($downloadedSizeMB / $elapsed.TotalSeconds, 1)) MB/s"
                }
                else {
                    'N/A'
                }
                Write-Information -MessageData "[$($MyInvocation.MyCommand)] $computer — Done in $($elapsed.ToString('mm\:ss')) ($avgSpeed)" -InformationAction Continue
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${computer}': $_"
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}